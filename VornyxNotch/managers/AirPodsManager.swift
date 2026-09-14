//
//  AirPodsManager.swift
//  VornyxNotch
//
//  Battery for the AirPods - or Beats - currently connected.
//

import AppKit
import Combine
import Defaults
import Foundation
import IOBluetooth

/// What a connected pair reports about itself.
///
/// Every level is optional because the shape of the answer depends on the
/// hardware: buds report a left, a right and a case, while the over-ears report
/// one number and no case at all. Nothing here invents a value it was not told.
struct AirPodsBattery: Equatable {
    var name: String
    var left: Int?
    var right: Int?
    var caseLevel: Int?
    var single: Int?
    /// Apple's Bluetooth product ID. This, not the name, is what tells the
    /// Pros from the Max from the plain ones: the name is whatever the owner
    /// typed.
    var productID: UInt16?

    var leftCharging = false
    var rightCharging = false
    var caseCharging = false
    var singleCharging = false

    /// The one number to show when there is only room for one.
    ///
    /// The lower ear, not the average: what you want to know is how long until
    /// something in your ear dies, and that is decided by whichever bud is
    /// worse off. The case is left out - it is not what runs out mid-call.
    var headline: Int? {
        if let single { return single }
        return [left, right].compactMap { $0 }.min()
    }

    /// True when the pair reports per-ear levels, which is what tells earbuds
    /// apart from the over-ears at display time.
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
            // A model newer than this table, or Beats. The name is a guess,
            // but it is the product name unless someone renamed the pair.
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

    /// The pair as a whole.
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

/// Watches for Apple audio devices connecting and reads their battery.
///
/// The levels come from `IOBluetoothDevice`. This used to read them out of the
/// IO registry, where a connected pair published an
/// `AppleDeviceManagementHIDEventService` entry carrying battery keys - current
/// macOS no longer publishes it at all, and the widget sat on "Not connected"
/// with a pair in both ears. The battery getters are not in the public
/// headers, so each one is checked for before it is called: a macOS that drops
/// one loses that number, not the app.
@MainActor
final class AirPodsManager: ObservableObject {
    static let shared = AirPodsManager()

    /// The connected pair, or nil when there is none.
    @Published private(set) var device: AirPodsBattery?

    /// Whether the home page shows the panel: asked for, and a pair connected.
    /// The page and the notch's width both follow this, so they cannot disagree.
    var widgetShowing: Bool {
        Defaults[.showAirPodsWidget] && device != nil
    }

    private let observer = BluetoothObserver()
    private var connectNotification: IOBluetoothUserNotification?
    private var refreshTimer: Timer?
    private var settleTask: Task<Void, Never>?
    /// Which pair the notch has already announced, so re-reads stay quiet.
    private var announcedDevice: String?
    /// Registering for connections reports the ones that already exist, which
    /// is not news - a pair worn before launch should not be announced.
    private var quietUntil = Date.distantPast

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard connectNotification == nil else { return }
        quietUntil = Date().addingTimeInterval(3)

        // Notifications rather than a poll: connecting a pair should show up
        // now, not on the next tick of some timer.
        observer.onChange = { [weak self] in
            Task { @MainActor in self?.deviceSetChanged() }
        }
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: observer,
            selector: #selector(BluetoothObserver.connected(_:device:)))

        // Nothing announces a change in the levels themselves, so this is what
        // keeps the numbers moving while a pair stays connected.
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

    /// A device has just connected or gone. Re-read, and let the notch say so.
    private func deviceSetChanged() {
        // A pair reports its levels a little after it connects, so the first
        // read often comes back empty. Read again over the next few seconds
        // rather than reporting a device with no levels and then correcting it.
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
            // Gone. The next pair to connect gets its own announcement.
            announcedDevice = nil
            return
        }

        // Once per connection, and only once the levels have arrived: a banner
        // reading "AirPods" with no number is worse than a moment's wait. The
        // name is the latch, so swapping the Pros for the Max still announces.
        guard announce, announcedDevice != found.name, found.headline != nil else { return }
        announcedDevice = found.name
        guard Date() >= quietUntil, Defaults[.airPodsSneakPeek] else { return }
        VornyxViewCoordinator.shared.announceAirPods()
    }

    /// The first connected device that reports what a pair reports.
    private static func read() -> AirPodsBattery? {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        for candidate in paired where candidate.isConnected() {
            if let battery = battery(of: candidate) { return battery }
        }
        return nil
    }

    /// Turn one device into a pair, or reject it.
    ///
    /// Keyboards and mice report a single level too, so a device has to earn
    /// its place: per-ear levels, which nothing else has, or a single level
    /// from audio hardware - major device class 0x04, "Audio/Video".
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

    /// The Bluetooth product ID, when the vendor is Apple - Beats included.
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
    /// through the implementation pointer: `perform` is only defined for
    /// methods that return objects. Zero means "not reported" - the case reads
    /// zero whenever its lid is shut.
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
