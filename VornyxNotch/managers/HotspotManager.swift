//
//  HotspotManager.swift
//  VornyxNotch
//
//  Whether the Mac is on a phone's Personal Hotspot.
//
//  Detection after DynamicNotch's WifiMonitor by Evgeniy Petrukovich (GPL-3.0),
//  https://github.com/jackson-storm/dynamicnotch
//

import Defaults
import Foundation
import Network

/// A hotspot is a Wi-Fi path macOS marks expensive but not constrained - what
/// it does for a phone sharing its connection. No permission needed.
@MainActor
final class HotspotManager: ObservableObject {
    static let shared = HotspotManager()

    @Published private(set) var isActive = false

    private let monitor = NWPathMonitor()
    /// No banner for the state found at launch.
    private var known = false

    private init() {}

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
        // Once, on joining; after that the closed notch keeps it up on its own.
        if changed, hotspot, Defaults[.hotspotLiveActivity] {
            VornyxViewCoordinator.shared.announceHotspot()
        }
    }
}
