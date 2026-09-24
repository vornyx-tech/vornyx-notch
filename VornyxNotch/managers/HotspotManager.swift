//
//  HotspotManager.swift
//  VornyxNotch
//
//  Whether the Mac is on a phone's Personal Hotspot, and the phone's charge.
//
//  Detection and the phone battery read after DynamicNotch's WifiMonitor and
//  HotspotBatteryMonitor by Evgeniy Petrukovich (GPL-3.0),
//  https://github.com/jackson-storm/dynamicnotch
//

import Defaults
import Foundation
import Network

/// A hotspot is a Wi-Fi path macOS marks expensive but not constrained - what
/// it does for a phone sharing its connection. No permission needed.
///
/// The phone's charge comes from Sharing.framework's private
/// `SFRemoteHotspotSession`, the same source as the menu bar's Wi-Fi list. It
/// is looked up at run time; where it is missing or refuses the sandbox, the
/// banner simply has no level.
@MainActor
final class HotspotManager: NSObject, ObservableObject {
    static let shared = HotspotManager()

    @Published private(set) var isActive = false
    @Published private(set) var phoneBattery: Int?
    @Published private(set) var phoneName: String?

    private let monitor = NWPathMonitor()
    private var session: NSObject?
    private var browsing = false
    /// No banner for the state found at launch.
    private var known = false

    private override init() { super.init() }

    func start() {
        monitor.pathUpdateHandler = { path in
            let hotspot = path.status == .satisfied && path.usesInterfaceType(.wifi)
                && path.isExpensive && !path.isConstrained
            Task { @MainActor in HotspotManager.shared.apply(hotspot) }
        }
        monitor.start(queue: .global(qos: .utility))
    }

    private func apply(_ hotspot: Bool) {
        guard hotspot != isActive || !known else { return }
        let changed = known && hotspot != isActive
        isActive = hotspot
        known = true
        hotspot ? startBrowsing() : stopBrowsing()
        if changed, hotspot, Defaults[.hotspotLiveActivity] {
            VornyxViewCoordinator.shared.announceHotspot()
        }
    }

    // MARK: - Phone battery

    private func startBrowsing() {
        if session == nil {
            guard let bundle = Bundle(path: "/System/Library/PrivateFrameworks/Sharing.framework"),
                  bundle.load(),
                  let type = NSClassFromString("SFRemoteHotspotSession") as? NSObject.Type
            else { return }
            let session = type.init()
            session.setValue(self, forKey: "delegate")
            self.session = session
        }
        guard !browsing, let session, session.responds(to: Selector(("startBrowsing"))) else { return }
        browsing = true
        session.perform(Selector(("startBrowsing")))
    }

    private func stopBrowsing() {
        phoneBattery = nil
        phoneName = nil
        guard browsing, let session, session.responds(to: Selector(("stopBrowsing"))) else { return }
        browsing = false
        session.perform(Selector(("stopBrowsing")))
    }

    /// `SFRemoteHotspotSessionDelegate`: the phones in reach, with their charge.
    @objc nonisolated func session(_ session: AnyObject, updatedFoundDevices devices: [NSObject]) {
        let found = devices.lazy.compactMap { device -> (String?, Int)? in
            guard let level = (device.value(forKey: "batteryLife") as? NSNumber)?.intValue, level > 0 else { return nil }
            return (device.value(forKey: "deviceName") as? String, level)
        }.first
        guard let found else { return }
        Task { @MainActor in
            let manager = HotspotManager.shared
            guard manager.browsing else { return }
            manager.phoneName = found.0
            manager.phoneBattery = min(100, found.1)
        }
    }
}
