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
import Darwin
import Network

/// A hotspot is a Wi-Fi path macOS marks expensive but not constrained - what
/// it does for a phone sharing its connection. No permission needed.
@MainActor
final class HotspotManager: ObservableObject {
    static let shared = HotspotManager()

    @Published private(set) var isActive = false
    /// Bytes through the hotspot, both ways, since the Mac joined it - the
    /// phone's mobile data, which is what a hotspot costs.
    @Published private(set) var sessionBytes: UInt64 = 0

    private let monitor = NWPathMonitor()
    private var baseline: UInt64?
    private var usageTimer: Timer?
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
        hotspot ? startCounting() : stopCounting()
        // Once, on joining; after that the closed notch keeps it up on its own.
        if changed, hotspot, Defaults[.hotspotLiveActivity] {
            VornyxViewCoordinator.shared.announceHotspot()
        }
    }

    // MARK: - Data used

    private func startCounting() {
        baseline = Self.wifiBytes()
        sessionBytes = 0
        usageTimer?.invalidate()
        usageTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in
                let manager = HotspotManager.shared
                guard let base = manager.baseline, let now = Self.wifiBytes() else { return }
                // The counters restart if the interface does; start over too.
                if now < base { manager.baseline = now; return }
                manager.sessionBytes = now - base
            }
        }
    }

    private func stopCounting() {
        usageTimer?.invalidate()
        usageTimer = nil
        baseline = nil
        sessionBytes = 0
    }

    /// In and out on the Wi-Fi interfaces, from the link-level counters every
    /// interface keeps. Readable inside the sandbox; nil if none were found.
    private static func wifiBytes() -> UInt64? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }

        var total: UInt64 = 0
        var found = false
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                  let data = entry.ifa_data?.assumingMemoryBound(to: if_data.self)
            else { continue }
            // en0 is Wi-Fi on every Mac with it built in; the path monitor has
            // already said the path is Wi-Fi.
            guard String(cString: entry.ifa_name) == "en0" else { continue }
            total += UInt64(data.pointee.ifi_ibytes) + UInt64(data.pointee.ifi_obytes)
            found = true
        }
        return found ? total : nil
    }

    /// `640K`, `84M`, `1.2G` - narrow enough for the notch's side.
    static func compact(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        switch value {
        case ..<1_000_000: return "\(Int(value / 1_000))K"
        case ..<1_000_000_000: return "\(Int(value / 1_000_000))M"
        default: return String(format: "%.1fG", value / 1_000_000_000)
        }
    }
}
