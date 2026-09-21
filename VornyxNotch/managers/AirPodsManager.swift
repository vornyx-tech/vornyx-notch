//
//  AirPodsManager.swift
//  VornyxNotch
//
//  Battery for the connected AirPods or Beats.
//

import AppKit
import Combine
import Defaults
import Foundation
import IOBluetooth

/// What a connected pair reports about itself. Every level is optional: buds
/// report a left, a right and a case, over-ears report one number and no case.
struct AirPodsBattery: Equatable {
    var name: String
    var left: Int?
    var right: Int?
    var caseLevel: Int?
    var single: Int?
    /// Apple's Bluetooth product ID, which tells the models apart.
    var productID: UInt16?

    var leftCharging = false
    var rightCharging = false
    var caseCharging = false
    var singleCharging = false

    /// The one number to show when there is only room for one: the lower ear,
    /// case excluded.
    var headline: Int? {
        if let single { return single }
        return [left, right].compactMap { $0 }.min()
    }

    /// True when the pair reports per-ear levels: earbuds, not over-ears.
    var hasEars: Bool { left != nil || right != nil }

    var isCharging: Bool {
        singleCharging || leftCharging || rightCharging
    }

    var model: AirPodsModel {
        AirPodsModel(productID: productID, name: name, hasEars: hasEars)
    }
}

/// Which kind of pair it is, for drawing the right one.
enum AirPodsModel: Equatable {
    case airPods, airPods3, airPods4, pro, max, beatsEarbuds, beatsHeadphones, headphones

    init(productID: UInt16?, name: String, hasEars: Bool) {
        switch productID {
        case 0x200E, 0x2014, 0x2024: self = .pro
        case 0x200A, 0x201F: self = .max
        case 0x2013: self = .airPods3
        case 0x2019, 0x201B: self = .airPods4
        case 0x2002, 0x200F: self = .airPods
        default:
            // A model newer than this table, or Beats: fall back to the name.
            let lowered = name.lowercased()
            if lowered.contains("max") {
                self = .max
            } else if lowered.contains("airpods") && lowered.contains("pro") {
                self = .pro
            } else if lowered.contains("beats") {
                self = hasEars ? .beatsEarbuds : .beatsHeadphones
            } else {
                self = hasEars ? .airPods : .headphones
            }
        }
    }

    var symbol: String {
        switch self {
        case .airPods: return "airpods"
        case .airPods3: return "airpods.gen3"
        case .airPods4: return Self.available("airpods.gen4", or: "airpods.gen3")
        case .pro: return "airpods.pro"
        case .max: return "airpodsmax"
        case .beatsEarbuds: return Self.available("beats.earphones", or: "earbuds")
        case .beatsHeadphones: return Self.available("beats.headphones", or: "headphones")
        case .headphones: return "headphones"
        }
    }

    /// One ear, when there is a drawing of this model's bud.
    var leftSymbol: String? {
        switch self {
        case .pro: return Self.available("airpodpro.left", or: "airpod.left")
        case .airPods3, .airPods4: return Self.available("airpod.gen3.left", or: "airpod.left")
        case .airPods: return "airpod.left"
        default: return nil
        }
    }

    var rightSymbol: String? {
        switch self {
        case .pro: return Self.available("airpodpro.right", or: "airpod.right")
        case .airPods3, .airPods4: return Self.available("airpod.gen3.right", or: "airpod.right")
        case .airPods: return "airpod.right"
        default: return nil
        }
    }

    var caseSymbol: String? {
        switch self {
        case .pro: return Self.available("airpods.pro.chargingcase.wireless", or: "airpodspro.chargingcase.wireless")
        case .airPods3, .airPods4: return Self.available("airpods.gen3.chargingcase.wireless", or: "airpods.chargingcase.wireless")
        case .airPods: return "airpods.chargingcase.wireless"
        case .beatsEarbuds: return Self.available("earbuds.case", or: "airpods.chargingcase")
        default: return nil
        }
    }

    /// Newer symbols fall back to older ones on the macOS versions without them.
    private static func available(_ name: String, or fallback: String) -> String {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil ? name : fallback
    }
}

/// Watches for Apple audio devices connecting and reads their battery. The
/// levels come from `IOBluetoothDevice`, whose battery getters are not in the
/// public headers, so each one is checked for before it is called.
@MainActor
final class AirPodsManager: ObservableObject {
    static let shared = AirPodsManager()

    @Published private(set) var device: AirPodsBattery?

    /// Whether the home page shows the panel; the notch's width follows it too.
    var widgetShowing: Bool {
        Defaults[.showAirPodsWidget] && device != nil
    }

    private let observer = BluetoothObserver()
    private var connectNotification: IOBluetoothUserNotification?
    private var refreshTimer: Timer?
    private var settleTask: Task<Void, Never>?
    /// Which pair the notch has already announced, so re-reads stay quiet.
    private var announcedDevice: String?
    /// Registering for connections also reports the existing ones.
    private var quietUntil = Date.distantPast

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard connectNotification == nil else { return }
        quietUntil = Date().addingTimeInterval(3)

        observer.onChange = { [weak self] in
            Task { @MainActor in self?.deviceSetChanged() }
        }
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: observer,
            selector: #selector(BluetoothObserver.connected(_:device:)))

        // Nothing announces a change in the levels themselves.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.refresh(announce: false) }
        }

        refresh(announce: false)
        announcedDevice = device?.name
    }

    func stop() {
        settleTask?.cancel()
        refreshTimer?.invalidate()
        refreshTimer = nil
        connectNotification?.unregister()
        connectNotification = nil
    }

    // MARK: - Reading

    /// A device has just connected or gone.
    private func deviceSetChanged() {
        // A pair reports its levels a little after it connects, so the first
        // read often comes back empty. Retry over the next few seconds.
        settleTask?.cancel()
        settleTask = Task { @MainActor [weak self] in
            for delay in [0, 500, 1500, 3000, 6000] {
                if delay > 0 {
                    try? await Task.sleep(for: .milliseconds(delay))
                    guard !Task.isCancelled else { return }
                }
                self?.refresh(announce: true)
                if self?.device?.headline != nil { return }
            }
        }
    }

    private func refresh(announce: Bool) {
        let found = Self.read()
        if found != device { device = found }

        guard let found else {
            announcedDevice = nil
            return
        }

        // Once per connection, and only once the levels have arrived.
        guard announce, announcedDevice != found.name, found.headline != nil else { return }
        announcedDevice = found.name
        guard Date() >= quietUntil, Defaults[.airPodsSneakPeek] else { return }
        VornyxViewCoordinator.shared.announceAirPods()
    }

    /// The first connected device that reports levels like a pair.
    private static func read() -> AirPodsBattery? {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        for candidate in paired where candidate.isConnected() {
            if let battery = battery(of: candidate) { return battery }
        }
        return nil
    }

    /// Turn one device into a pair, or reject it. Keyboards and mice report a
    /// single level too, so that counts only for device class 0x04, audio.
    private static func battery(of device: IOBluetoothDevice) -> AirPodsBattery? {
        let left = level(device, "batteryPercentLeft")
        let right = level(device, "batteryPercentRight")
        let caseLevel = level(device, "batteryPercentCase")
        let single = level(device, "batteryPercentSingle") ?? level(device, "batteryPercentCombined")

        let hasEars = left != nil || right != nil
        guard hasEars || (single != nil && device.deviceClassMajor == 0x04) else { return nil }

        return AirPodsBattery(
            name: device.name ?? "AirPods",
            left: left,
            right: right,
            caseLevel: caseLevel,
            single: hasEars ? nil : single,
            productID: appleProductID(device))
    }

    /// The Bluetooth product ID, when the vendor is Apple (Beats included).
    private static func appleProductID(_ device: IOBluetoothDevice) -> UInt16? {
        func read(_ name: String) -> UInt16? {
            let selector = NSSelectorFromString(name)
            guard device.responds(to: selector), let implementation = device.method(for: selector) else {
                return nil
            }
            typealias Getter = @convention(c) (AnyObject, Selector) -> UInt16
            return unsafeBitCast(implementation, to: Getter.self)(device, selector)
        }
        guard read("vendorID") == 0x004C, let product = read("productID"), product != 0 else { return nil }
        return product
    }

    /// One battery getter. They return an unsigned char, so the call goes
    /// through the implementation pointer. Zero means not reported.
    private static func level(_ device: IOBluetoothDevice, _ name: String) -> Int? {
        let selector = NSSelectorFromString(name)
        guard device.responds(to: selector), let implementation = device.method(for: selector) else {
            return nil
        }
        typealias Getter = @convention(c) (AnyObject, Selector) -> UInt8
        let value = Int(unsafeBitCast(implementation, to: Getter.self)(device, selector))
        return (1...100).contains(value) ? value : nil
    }
}

/// Target for IOBluetooth's selector-based notifications, which are delivered
/// on the main run loop.
private final class BluetoothObserver: NSObject {
    var onChange: (() -> Void)?

    @objc func connected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        device.register(forDisconnectNotification: self, selector: #selector(disconnected(_:device:)))
        onChange?()
    }

    @objc func disconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        notification.unregister()
        onChange?()
    }
}
