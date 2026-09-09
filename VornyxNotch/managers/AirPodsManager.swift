//
//  AirPodsManager.swift
//  VornyxNotch
//
//  Battery for the AirPods - or Beats - currently connected.
//

import Combine
import Defaults
import Foundation
import IOKit

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
}

/// Watches for Apple audio devices connecting and reads their battery.
///
/// The levels come from the IO registry rather than any Bluetooth API: a
/// connected pair publishes an `AppleDeviceManagementHIDEventService` entry
/// carrying its own battery keys, and reading the registry needs no entitlement
/// and no permission prompt - which matters, because the app is sandboxed.
@MainActor
final class AirPodsManager: ObservableObject {
    static let shared = AirPodsManager()

    /// The connected pair, or nil when there is none.
    @Published private(set) var device: AirPodsBattery?

    private var notifyPort: IONotificationPortRef?
    private var publishedIterator: io_iterator_t = 0
    private var terminatedIterator: io_iterator_t = 0
    private var refreshTimer: Timer?
    private var settleTask: Task<Void, Never>?
    /// Which pair the notch has already announced, so re-reads stay quiet.
    private var announcedDevice: String?

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard notifyPort == nil else { return }

        // Two notifications rather than a poll: connecting a pair should show
        // up now, not on the next tick of some timer.
        let port = IONotificationPortCreate(kIOMainPortDefault)
        IONotificationPortSetDispatchQueue(port, .main)
        notifyPort = port

        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOServiceMatchingCallback = { refcon, iterator in
            // A C callback captures nothing, so this names the type outright.
            AirPodsManager.drain(iterator)
            guard let refcon else { return }
            let manager = Unmanaged<AirPodsManager>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in manager.deviceSetChanged() }
        }

        // One matching dictionary per registration: the call consumes a
        // reference to it. The first drain of each iterator arms the
        // notification and reports what is already connected, which is how a
        // pair worn before launch is picked up.
        IOServiceAddMatchingNotification(
            port, kIOMatchedNotification, IOServiceMatching(Self.serviceClass),
            callback, context, &publishedIterator
        )
        Self.drain(publishedIterator)

        IOServiceAddMatchingNotification(
            port, kIOTerminatedNotification, IOServiceMatching(Self.serviceClass),
            callback, context, &terminatedIterator
        )
        Self.drain(terminatedIterator)

        // Levels move slowly, so this is a backstop rather than the mechanism.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.refresh(announce: false) }
        }

        refresh(announce: false)
    }

    func stop() {
        settleTask?.cancel()
        refreshTimer?.invalidate()
        refreshTimer = nil
        for iterator in [publishedIterator, terminatedIterator] where iterator != 0 {
            IOObjectRelease(iterator)
        }
        publishedIterator = 0
        terminatedIterator = 0
        if let notifyPort {
            IONotificationPortDestroy(notifyPort)
            self.notifyPort = nil
        }
    }

    /// Empty an iterator. Not optional: an undrained iterator never fires again.
    private nonisolated static func drain(_ iterator: io_iterator_t) {
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
    }

    // MARK: - Reading

    /// A pair has just appeared or gone. Re-read, and let the notch say so.
    private func deviceSetChanged() {
        // A pair that has only just connected publishes its service before it
        // publishes its battery, so the first read often comes back empty.
        // Read again over the next few seconds rather than reporting a device
        // with no levels and then correcting it.
        settleTask?.cancel()
        settleTask = Task { @MainActor [weak self] in
            for delay in [0, 400, 1200, 2500] {
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
        guard Defaults[.airPodsSneakPeek] else { return }
        VornyxViewCoordinator.shared.announceAirPods()
    }

    private static let serviceClass = "AppleDeviceManagementHIDEventService"

    /// The connected pair, read straight out of the registry.
    private static func read() -> AirPodsBattery? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching(serviceClass), &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }
            var unmanaged: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &unmanaged, kCFAllocatorDefault, 0)
                    == KERN_SUCCESS,
                  let properties = unmanaged?.takeRetainedValue() as? [String: Any],
                  let candidate = device(from: properties)
            else { continue }
            return candidate
        }
        return nil
    }

    /// Turn one registry entry into a pair, or reject it.
    ///
    /// The same service class carries the built-in keyboard and trackpad, so
    /// the entry has to earn its place: either it reports per-ear levels, which
    /// nothing else does, or it names itself as Apple audio hardware.
    private static func device(from properties: [String: Any]) -> AirPodsBattery? {
        let name = (properties["Product"] as? String) ?? "AirPods"

        func level(_ keys: [String]) -> Int? {
            for key in keys {
                if let value = properties[key] as? Int, (1...100).contains(value) { return value }
            }
            return nil
        }
        func flag(_ keys: [String]) -> Bool {
            keys.contains { (properties[$0] as? Bool) == true || (properties[$0] as? Int) == 1 }
        }

        let left = level(["BatteryPercentLeft"])
        let right = level(["BatteryPercentRight"])
        let caseLevel = level(["BatteryPercentCase"])
        let single = level(["BatteryPercentSingle", "BatteryPercentCombined", "BatteryPercent"])

        let looksLikeAudio = ["airpod", "beats", "powerbeats", "solo", "studio", "flex"]
            .contains { name.lowercased().contains($0) }
        guard left != nil || right != nil || (single != nil && looksLikeAudio) else { return nil }

        return AirPodsBattery(
            name: name,
            left: left,
            right: right,
            caseLevel: caseLevel,
            single: single,
            leftCharging: flag(["BatteryChargingLeft"]),
            rightCharging: flag(["BatteryChargingRight"]),
            caseCharging: flag(["BatteryChargingCase"]),
            singleCharging: flag(["BatteryChargingSingle", "BatteryIsCharging"])
        )
    }
}
