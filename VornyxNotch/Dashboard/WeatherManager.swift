//
//  WeatherManager.swift
//  VornyxNotch
//
//  The forecast behind the dashboard's weather page.
//

import CoreLocation
import Defaults
import Foundation
import SwiftUI

// MARK: - Model

struct DayForecast: Identifiable, Equatable {
    let date: Date
    let code: Int
    let high: Double
    let low: Double

    var id: Date { date }
}

struct WeatherSnapshot: Equatable {
    var place: String
    var temperature: Double
    var apparent: Double
    var code: Int
    var isDay: Bool
    var wind: Double
    var humidity: Int
    var days: [DayForecast]
    var fetched: Date
}

/// What the WMO weather code means, in a glyph and a word.
///
/// Open-Meteo reports conditions as WMO codes rather than text, which is the
/// good way round: the mapping to an icon and a label lives here, in one place,
/// instead of being parsed back out of somebody's English.
enum WeatherCode {
    static func symbol(_ code: Int, isDay: Bool) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67: return "cloud.rain.fill"
        case 80, 81, 82: return "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    /// The colours the weather wears.
    ///
    /// Chosen for what the sky looks like rather than what the data means -
    /// rain is not "bad" and clear is not "good", so this is not a red-to-green
    /// scale. Three per condition, because the glow needs blobs to mix.
    static func palette(_ code: Int, isDay: Bool) -> [Color] {
        switch code {
        case 0:
            return isDay
                ? [.orange, .yellow, Color(red: 1.0, green: 0.45, blue: 0.35)]
                : [Color(red: 0.22, green: 0.20, blue: 0.55), .indigo, .purple]
        case 1, 2:
            return isDay
                ? [Color(red: 0.35, green: 0.62, blue: 0.95), .orange, .yellow]
                : [.indigo, Color(red: 0.30, green: 0.32, blue: 0.62), .blue]
        case 3:
            return [Color(red: 0.38, green: 0.45, blue: 0.58), .blue.opacity(0.7), .gray]
        case 45, 48:
            return [Color(red: 0.45, green: 0.52, blue: 0.55), .teal.opacity(0.6), .gray]
        case 51, 53, 55, 56, 57:
            return [.teal, Color(red: 0.35, green: 0.55, blue: 0.85), .cyan.opacity(0.7)]
        case 61, 63, 65, 66, 67, 80, 81, 82:
            return [.blue, .cyan, Color(red: 0.25, green: 0.35, blue: 0.75)]
        case 71, 73, 75, 77, 85, 86:
            return [Color(red: 0.72, green: 0.85, blue: 0.95), .cyan.opacity(0.6), .white.opacity(0.5)]
        case 95, 96, 99:
            return [.purple, Color(red: 0.85, green: 0.35, blue: 0.75), .indigo]
        default:
            return [Color(red: 0.38, green: 0.45, blue: 0.58), .blue.opacity(0.6), .gray]
        }
    }

    static func label(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing drizzle"
        case 61, 63, 65: return "Rain"
        case 66, 67: return "Freezing rain"
        case 71, 73, 75: return "Snow"
        case 77: return "Snow grains"
        case 80, 81, 82: return "Showers"
        case 85, 86: return "Snow showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm, hail"
        default: return "—"
        }
    }
}

// MARK: - Manager

@MainActor
final class WeatherManager: NSObject, ObservableObject {
    static let shared = WeatherManager()

    enum State: Equatable {
        case idle
        case loading
        /// No location, and no place typed in Settings to fall back on.
        case needsLocation
        case failed(String)
    }

    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var state: State = .idle

    private let locationManager = CLLocationManager()
    private var fetchTask: Task<Void, Never>?
    private var pendingLocation: CheckedContinuation<CLLocation, Error>?
    private var locationTimeout: Task<Void, Never>?

    /// How long to wait for a fix before giving up on it.
    ///
    /// `requestLocation` is not guaranteed to call back at all - with Location
    /// Services off system-wide it can simply never answer - and an await on a
    /// continuation that never resumes is a permanent "Getting the forecast…".
    private let locationPatience: Duration = .seconds(8)

    /// Weather does not change fast enough to be worth asking more often, and
    /// the page is opened far more often than that.
    private let staleAfter: TimeInterval = 15 * 60

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    // MARK: Refreshing

    func refreshIfStale() {
        if let snapshot, Date().timeIntervalSince(snapshot.fetched) < staleAfter { return }
        refresh()
    }

    func refresh() {
        // Cancel and restart rather than bail out. Refusing while a fetch is in
        // flight means one stuck fetch disables every later attempt, including
        // the "Try again" button - which is exactly when a retry matters most.
        fetchTask?.cancel()
        settle(.failure(LocationError.unavailable))

        state = .loading
        fetchTask = Task { [weak self] in
            await self?.load()
            await MainActor.run { [weak self] in self?.fetchTask = nil }
        }
    }

    private func load() async {
        do {
            let (coordinate, name) = try await resolvePlace()
            let snapshot = try await Self.fetchForecast(at: coordinate, place: name)
            self.snapshot = snapshot
            state = .idle
        } catch let error as LocationError {
            switch error {
            case .awaitingPermission: state = .loading
            case .denied: state = .needsLocation
            default: state = .failed(error.message)
            }
        } catch {
            state = .failed("Could not reach the weather service.")
        }
    }

    // MARK: Where

    enum LocationError: Error, Equatable {
        case denied
        case unknownPlace(String)
        case unavailable
        /// The prompt is on screen. Not a failure - the answer arrives at
        /// `locationManagerDidChangeAuthorization`, which starts the fetch again.
        case awaitingPermission

        var message: String {
            switch self {
            case .denied: return "Location is off."
            case .unknownPlace(let name): return "Couldn't find \"\(name)\"."
            case .unavailable: return "Couldn't work out where you are. Name a place in Settings."
            case .awaitingPermission: return "Waiting for permission…"
            }
        }
    }

    /// A typed-in place wins over the device's own location: someone who has
    /// gone to the trouble of naming a city means it, and it is also the way
    /// out when location is denied.
    private func resolvePlace() async throws -> (CLLocationCoordinate2D, String) {
        let typed = Defaults[.weatherPlace].trimmingCharacters(in: .whitespaces)
        if !typed.isEmpty {
            return try await Self.geocode(typed)
        }

        let location = try await currentLocation()
        let name = (try? await Self.reverseGeocode(location)) ?? "Here"
        return (location.coordinate, name)
    }

    private func currentLocation() async throws -> CLLocation {
        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            throw LocationError.denied
        case .notDetermined:
            // Ask, then stop here. Calling requestLocation before the answer
            // comes back just fails, and showing "couldn't work out where you
            // are" while the prompt is still on screen would be nonsense.
            locationManager.requestWhenInUseAuthorization()
            throw LocationError.awaitingPermission
        default:
            break
        }

        if let last = locationManager.location, last.timestamp.timeIntervalSinceNow > -3600 {
            return last
        }

        return try await withCheckedThrowingContinuation { continuation in
            pendingLocation = continuation

            locationTimeout?.cancel()
            locationTimeout = Task { @MainActor [weak self] in
                guard let patience = self?.locationPatience else { return }
                try? await Task.sleep(for: patience)
                guard !Task.isCancelled else { return }
                self?.settle(.failure(LocationError.unavailable))
            }

            locationManager.requestLocation()
        }
    }

    private func settle(_ result: Result<CLLocation, Error>) {
        locationTimeout?.cancel()
        locationTimeout = nil
        guard let pendingLocation else { return }
        self.pendingLocation = nil
        pendingLocation.resume(with: result)
    }

    // MARK: Network

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        return URLSession(configuration: configuration)
    }()

    private static func geocode(_ name: String) async throws -> (CLLocationCoordinate2D, String) {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            .init(name: "name", value: name),
            .init(name: "count", value: "1"),
            .init(name: "language", value: "en"),
            .init(name: "format", value: "json"),
        ]
        let (data, _) = try await session.data(from: components.url!)
        let decoded = try JSONDecoder().decode(GeocodeResponse.self, from: data)
        guard let first = decoded.results?.first else { throw LocationError.unknownPlace(name) }
        return (.init(latitude: first.latitude, longitude: first.longitude), first.name)
    }

    private static func reverseGeocode(_ location: CLLocation) async throws -> String {
        let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
        guard let placemark = placemarks.first else { throw LocationError.unavailable }
        return placemark.locality ?? placemark.administrativeArea ?? placemark.country ?? "Here"
    }

    private static func fetchForecast(
        at coordinate: CLLocationCoordinate2D,
        place: String
    ) async throws -> WeatherSnapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(coordinate.latitude)),
            .init(name: "longitude", value: String(coordinate.longitude)),
            .init(
                name: "current",
                value: "temperature_2m,apparent_temperature,is_day,weather_code,relative_humidity_2m,wind_speed_10m"
            ),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            .init(name: "forecast_days", value: "4"),
            .init(name: "timezone", value: "auto"),
            .init(name: "temperature_unit", value: Defaults[.weatherUnit].apiValue),
            .init(name: "wind_speed_unit", value: Defaults[.weatherUnit].windAPIValue),
        ]

        let (data, _) = try await session.data(from: components.url!)
        let decoded = try JSONDecoder().decode(ForecastResponse.self, from: data)

        // POSIX, because this parses a fixed machine format rather than
        // anything the reader sees: under a non-Gregorian regional calendar
        // "yyyy" means that calendar's year, "2026-09-10" fails to parse, and
        // the `compactMap` below silently drops every day of the forecast.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let days: [DayForecast] = zip(
            zip(decoded.daily.time, decoded.daily.weather_code),
            zip(decoded.daily.temperature_2m_max, decoded.daily.temperature_2m_min)
        ).compactMap { pair, temperatures in
            guard let date = formatter.date(from: pair.0) else { return nil }
            return DayForecast(date: date, code: pair.1, high: temperatures.0, low: temperatures.1)
        }

        return WeatherSnapshot(
            place: place,
            temperature: decoded.current.temperature_2m,
            apparent: decoded.current.apparent_temperature,
            code: decoded.current.weather_code,
            isDay: decoded.current.is_day == 1,
            wind: decoded.current.wind_speed_10m,
            humidity: decoded.current.relative_humidity_2m,
            days: days,
            fetched: Date()
        )
    }

    // MARK: Wire format

    private struct GeocodeResponse: Decodable {
        struct Result: Decodable {
            let name: String
            let latitude: Double
            let longitude: Double
        }
        let results: [Result]?
    }

    private struct ForecastResponse: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let apparent_temperature: Double
            let is_day: Int
            let weather_code: Int
            let relative_humidity_2m: Int
            let wind_speed_10m: Double
        }
        struct Daily: Decodable {
            let time: [String]
            let weather_code: [Int]
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
        }
        let current: Current
        let daily: Daily
    }
}

// MARK: - Location delegate

extension WeatherManager: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        Task { @MainActor in settle(.success(location)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in settle(.failure(LocationError.unavailable)) }
    }

    /// The answer to the permission prompt arrives here, long after the request
    /// returned. Retry once it does, so the page fills in by itself rather than
    /// sitting on an error until it is opened again.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .denied, .restricted:
                settle(.failure(LocationError.denied))
                if Defaults[.weatherPlace].isEmpty { state = .needsLocation }
            case .notDetermined:
                break
            default:
                if snapshot == nil { refresh() }
            }
        }
    }
}
