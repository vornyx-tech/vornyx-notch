//
//  BannerPreview.swift
//  VornyxNotch
//
//  Every closed-notch banner on demand, with made-up data.
//

import Foundation
import OSLog
import SwiftUI

/// Shows a banner without waiting for the real thing: a Focus, a VPN, the
/// battery crossing a line, a device connecting.
///
/// Each banner's view reads its override from here first, so the real
/// sources polling underneath cannot flip it back mid-preview. From Settings,
/// or from outside the app:
///
///     swift -e 'import Foundation; DistributedNotificationCenter.default()
///         .postNotificationName(.init("tech.vornyx.notch.preview"),
///         object: "batteryLow", userInfo: nil, deliverImmediately: true)'
@MainActor
final class BannerPreview: ObservableObject {
    static let shared = BannerPreview()

    enum Kind: String, CaseIterable, Identifiable {
        case focusOn, focusOff, vpnConnected, vpnDisconnected
        case batteryLow, batteryFull, bluetooth, timer

        var id: String { rawValue }

        var title: String {
            switch self {
            case .focusOn: return "Focus on"
            case .focusOff: return "Focus off"
            case .vpnConnected: return "VPN connected"
            case .vpnDisconnected: return "VPN disconnected"
            case .batteryLow: return "Battery low"
            case .batteryFull: return "Battery full"
            case .bluetooth: return "Bluetooth device"
            case .timer: return "Timer"
            }
        }
    }

    @Published private(set) var focus: (on: Bool, mode: FocusMode)?
    @Published private(set) var vpn: (vpn: ConnectedVPN, up: Bool)?
    @Published private(set) var battery: (alert: BatteryStatusViewModel.BatteryAlert, level: Int)?
    @Published private(set) var bluetooth: ConnectedBluetoothDevice?

    private let log = Logger(subsystem: "tech.vornyx.notch", category: "Preview")
    private var clear: Task<Void, Never>?
    private var observer: NSObjectProtocol?

    private init() {}

    /// Listens for previews asked for from outside the app.
    func listen() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: .init("tech.vornyx.notch.preview"), object: nil, queue: .main
        ) { notification in
            let name = notification.object as? String
            Task { @MainActor in
                guard let kind = name.flatMap(Kind.init(rawValue:)) else { return }
                BannerPreview.shared.show(kind)
            }
        }
    }

    /// The notch has to be closed for a banner, so a preview asked for from
    /// Settings closes it first.
    func show(_ kind: Kind) {
        clear?.cancel()
        focus = nil; vpn = nil; battery = nil; bluetooth = nil
        let coordinator = VornyxViewCoordinator.shared

        switch kind {
        case .focusOn:
            focus = (true, .work)
            coordinator.announceFocus()
        case .focusOff:
            focus = (false, .work)
            coordinator.announceFocus()
        case .vpnConnected, .vpnDisconnected:
            vpn = (ConnectedVPN(
                id: "preview", name: "WireGuard Tunnel", bundleID: "com.wireguard.macos",
                connectedAt: Date().addingTimeInterval(-515)), kind == .vpnConnected)
            coordinator.announceVPN()
        case .batteryLow:
            battery = (.low, 14)
            coordinator.toggleExpandingView(status: true, type: .batteryAlert)
        case .batteryFull:
            battery = (.full, 100)
            coordinator.toggleExpandingView(status: true, type: .batteryAlert)
        case .bluetooth:
            bluetooth = ConnectedBluetoothDevice(name: "Magic Keyboard", symbol: "keyboard", battery: 76)
            coordinator.announceBluetooth()
        case .timer:
            CountdownManager.shared.start(90)
        }

        log.notice("preview \(kind.rawValue, privacy: .public)")
        // The banner is switched on a run loop pass later; say what landed.
        Task { @MainActor [log] in
            let banner = VornyxViewCoordinator.shared.expandingView
            log.notice("banner \(String(describing: banner.type), privacy: .public) showing: \(banner.show, privacy: .public)")
        }

        // A little longer than the banner itself, so it never flips back to
        // real data while still on screen.
        clear = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, !Task.isCancelled else { return }
            self.focus = nil; self.vpn = nil; self.battery = nil; self.bluetooth = nil
        }
    }
}
