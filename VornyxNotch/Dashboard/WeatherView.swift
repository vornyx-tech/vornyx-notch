//
//  WeatherView.swift
//  VornyxNotch
//
//  The dashboard's other left-hand page.
//

import Defaults
import SwiftUI

/// Now on the left, the next few days on the right - the same split the month
/// and the agenda use, so the two pages feel like the same drawer.
struct WeatherView: View {
    @ObservedObject private var weather = WeatherManager.shared
    @Default(.weatherUnit) private var unit

    var body: some View {
        Group {
            if let snapshot = weather.snapshot {
                content(snapshot)
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { weather.refreshIfStale() }
    }

    // MARK: - Loaded

    private func content(_ snapshot: WeatherSnapshot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            now(snapshot)
            VStack(spacing: 0) {
                days(snapshot)
                Spacer(minLength: 0)
            }
        }
        .background(WeatherGlow(code: snapshot.code, isDay: snapshot.isDay))
    }

    // MARK: Now

    private func now(_ snapshot: WeatherSnapshot) -> some View {
        let palette = WeatherCode.palette(snapshot.code, isDay: snapshot.isDay)

        return VStack(alignment: .leading, spacing: 0) {
            placeChip(snapshot.place)

            // The hero: the number and the sky it belongs to, on one line. The
            // icon carries a halo of its own colour so it reads as lit rather
            // than stamped on.
            HStack(alignment: .center, spacing: 6) {
                HStack(alignment: .top, spacing: 1) {
                    Text(degrees(snapshot.temperature))
                        .font(.system(size: 46, weight: .medium, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, palette[0].opacity(0.9)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .monospacedDigit()
                    Text("°")
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.top, 6)
                }

                ZStack {
                    Circle()
                        .fill(palette[0])
                        .frame(width: 30, height: 30)
                        .blur(radius: 14)
                        .opacity(0.65)
                    conditionSymbol(snapshot.code, isDay: snapshot.isDay, size: 26)
                }
            }
            .padding(.top, 2)

            Text(WeatherCode.label(snapshot.code))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))

            Text("Feels like \(degrees(snapshot.apparent))°")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.top, 1)

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                detail("humidity", "\(snapshot.humidity)%")
                detail("wind", "\(Int(snapshot.wind.rounded()))")
            }
        }
        .frame(width: 124, alignment: .leading)
    }

    /// A symbol that moves: rain falls, sun shimmers. Indefinite symbol effects
    /// rather than an animation of our own, so the motion is the system's and
    /// costs nothing to keep running.
    @ViewBuilder
    private func conditionSymbol(_ code: Int, isDay: Bool, size: CGFloat) -> some View {
        let symbol = Image(systemName: WeatherCode.symbol(code, isDay: isDay))
            .font(.system(size: size))
            .symbolRenderingMode(.multicolor)

        switch code {
        case 51...86, 95...99:
            // Anything falling out of the sky: the layers cycle downwards.
            symbol.symbolEffect(.variableColor.iterative.reversing)
        case 0:
            symbol.symbolEffect(.pulse)
        default:
            symbol
        }
    }

    private func placeChip(_ place: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "location.fill")
                .font(.system(size: 7))
            Text(place)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.75))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(.white.opacity(0.10)))
    }

    private func detail(_ symbol: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .monospacedDigit()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(.white.opacity(0.07)))
    }

    // MARK: Days

    /// Today plus the next three, on a surface of their own. Bars rather than
    /// bare numbers: the point of a forecast at a glance is which day is the
    /// warm one, and that is a shape question, not a reading question.
    private func days(_ snapshot: WeatherSnapshot) -> some View {
        let range = temperatureRange(snapshot.days)

        return VStack(spacing: 2) {
            ForEach(snapshot.days.prefix(4)) { day in
                dayRow(day, range: range, now: snapshot)
            }
        }
        .padding(6)
        // Hugs its four rows rather than stretching: a card two thirds empty
        // reads as something failing to load. The glow has the rest.
        .frame(maxWidth: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: nestedCornerRadius(inset: 4), style: .continuous)
                .fill(.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: nestedCornerRadius(inset: 4), style: .continuous)
                        .strokeBorder(.white.opacity(0.07), lineWidth: 1)
                )
        )
    }

    private func dayRow(
        _ day: DayForecast,
        range: ClosedRange<Double>,
        now snapshot: WeatherSnapshot
    ) -> some View {
        let today = isToday(day.date)

        return HStack(spacing: 4) {
            Text(weekday(day.date))
                .font(.system(size: 10, weight: today ? .bold : .medium, design: .rounded))
                .foregroundStyle(.white.opacity(today ? 0.95 : 0.5))
                .lineLimit(1)
                // "Today" in bold rounded needs every point of this. At 30 it
                // truncated to "Tod…" while the three-letter days sat in space.
                .frame(width: 38, alignment: .leading)

            conditionSymbol(day.code, isDay: true, size: 11)
                // Wider than the point size: the wet symbols are broad glyphs -
                // `cloud.rain.fill` runs about 15pt across at 11pt type - and
                // in a 16pt frame it overflowed left into the day's name.
                .frame(width: 20)

            Text(degrees(day.low))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
                .monospacedDigit()
                .frame(width: 17, alignment: .trailing)

            band(for: day, in: range, now: today ? snapshot.temperature : nil)

            Text(degrees(day.high))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(today ? 0.95 : 0.75))
                .monospacedDigit()
                .frame(width: 17, alignment: .leading)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(
            Capsule().fill(.white.opacity(today ? 0.08 : 0))
        )
    }

    /// One day's low-to-high, placed along the whole week's range - so the bars
    /// can be read against each other rather than each against itself.
    ///
    /// The bar is coloured by the temperatures at its own ends, so a cold day
    /// is a blue stub and a hot one runs into red. Today also carries a marker
    /// for where the temperature is right now, between its two ends.
    private func band(for day: DayForecast, in range: ClosedRange<Double>, now: Double?) -> some View {
        GeometryReader { proxy in
            let span = max(1, range.upperBound - range.lowerBound)
            let start = (day.low - range.lowerBound) / span
            let width = max(0.08, (day.high - day.low) / span)

            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.09))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                temperatureColor(day.low, in: range),
                                temperatureColor(day.high, in: range),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * width)
                    .offset(x: proxy.size.width * start)

                if let now {
                    let position = ((now - range.lowerBound) / span)
                        .clamped(to: 0...1)
                    Circle()
                        .fill(.white)
                        .frame(width: 5, height: 5)
                        .shadow(color: .black.opacity(0.5), radius: 1)
                        .offset(x: proxy.size.width * position - 2.5)
                }
            }
        }
        .frame(height: 5)
        .frame(maxWidth: .infinity)
    }

    /// Cold to hot across the week's own range, so the scale always uses its
    /// whole span whether the week runs 2° to 8° or 18° to 34°.
    private func temperatureColor(_ value: Double, in range: ClosedRange<Double>) -> Color {
        let stops: [Color] = [
            Color(red: 0.35, green: 0.55, blue: 0.95),
            .cyan,
            .teal,
            .yellow,
            .orange,
            Color(red: 0.95, green: 0.35, blue: 0.30),
        ]
        let span = max(1, range.upperBound - range.lowerBound)
        let normalized = ((value - range.lowerBound) / span).clamped(to: 0...1)
        let index = Int((normalized * Double(stops.count - 1)).rounded())
        return stops[index]
    }

    private func temperatureRange(_ days: [DayForecast]) -> ClosedRange<Double> {
        let lows = days.map(\.low)
        let highs = days.map(\.high)
        guard let low = lows.min(), let high = highs.max(), low < high else { return 0...1 }
        return low...high
    }

    // MARK: - Not loaded yet

    @ViewBuilder
    private var placeholder: some View {
        VStack(spacing: 7) {
            switch weather.state {
            case .loading, .idle:
                ProgressView()
                    .controlSize(.small)
                Text("Getting the forecast…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            case .needsLocation:
                Image(systemName: "location.slash")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                Text("Location is off")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Allow it, or name a place in Settings.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                settingsButton
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 6) {
                    Button("Try again") { weather.refresh() }
                    settingsButton
                }
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var settingsButton: some View {
        Button("Open Settings") {
            DispatchQueue.main.async {
                SettingsWindowController.shared.showWindow()
            }
        }
        .controlSize(.small)
    }

    // MARK: - Formatting

    /// Whole degrees, with the unit said once in the big number rather than on
    /// every value in the column.
    private func degrees(_ value: Double) -> String {
        "\(Int(value.rounded()))"
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private func weekday(_ date: Date) -> String {
        if isToday(date) { return "Today" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}

// MARK: - Glow

/// The weather's colour, behind the page.
///
/// The same trick as the album art's living glow, with the condition's palette
/// standing in for the artwork: three soft blobs, blurred past recognition,
/// drifting on periods that share no common multiple so the motion never
/// resolves into a loop. See `WeatherGlowStyle` for the numbers.
private struct WeatherGlow: View {
    let code: Int
    let isDay: Bool

    @State private var phase = Double.random(in: 0..<1000)
    @State private var tick: Double = 0

    /// A plain timer rather than `TimelineView(.animation)`, for the same
    /// reason the album art uses one: the notch lives in a non-activating
    /// panel, where the display-link schedule cannot be relied on to keep
    /// firing. Stored, not computed - a computed publisher would be rebuilt on
    /// every body pass.
    private let clock = Timer.publish(
        every: 1 / WeatherGlowStyle.frameRate, on: .main, in: .common
    ).autoconnect()

    var body: some View {
        let style = WeatherGlowStyle.self
        let colors = WeatherCode.palette(code, isDay: isDay)
        let t = tick + phase

        GeometryReader { proxy in
            ZStack {
                ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
                    // Each blob is offset in time from the last, so they never
                    // swell together.
                    let seed = Double(index) * 31
                    let breathe = sin((t + seed) / style.breathePeriod)
                    let sway = sin((t + seed * 1.7) / style.swayPeriod)
                    let bob = cos((t + seed * 2.3) / style.bobPeriod)
                    let anchor = style.anchors[index % style.anchors.count]

                    Circle()
                        .fill(color.opacity(0.75))
                        .frame(width: proxy.size.width * 0.6)
                        .scaleEffect(style.baseScale + style.scaleSwing * breathe)
                        .position(
                            x: proxy.size.width * anchor.x + style.driftRadius * sway,
                            y: proxy.size.height * anchor.y + style.driftRadius * bob
                        )
                }
            }
            .blur(radius: style.blur)
            .opacity(style.opacity)
            // Fade to nothing before the page's edges, so the column's clip has
            // nothing left to cut into a straight line. Inset and blurred by
            // the same amount, which puts the mask at roughly zero right where
            // the clip happens.
            .mask(
                Rectangle()
                    .fill(.white)
                    .padding(style.edgeFade)
                    .blur(radius: style.edgeFade)
            )
        }
        .onReceive(clock) { date in
            tick = date.timeIntervalSinceReferenceDate
        }
        // Decoration only: it must never take a click meant for the page.
        .allowsHitTesting(false)
    }
}
