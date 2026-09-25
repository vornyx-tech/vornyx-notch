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
        case batteryLow, batteryFull, bluetooth, hotspot, timer, timerEnd, lockScreen
        case airPodsPro, airPods3, airPods2, airPodsMax, speaker
        case screenRecording, charging, unplugged, colorPicked, inputSource

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
            case .hotspot: return "Hotspot"
            case .timer: return "Timer"
            case .timerEnd: return "Timer ending"
            case .lockScreen: return "Lock screen"
            case .airPodsPro: return "AirPods Pro"
            case .airPods3: return "AirPods 3"
            case .airPods2: return "AirPods 2"
            case .airPodsMax: return "AirPods Max"
            case .speaker: return "Speaker"
            case .screenRecording: return "Screen recording"
            case .charging: return "Charging"
            case .unplugged: return "Unplugged"
            case .colorPicked: return "Colour picked"
            case .inputSource: return "Keyboard layout"
            }
        }
    }

    @Published private(set) var focus: (on: Bool, mode: FocusMode)?
    @Published private(set) var vpn: (vpn: ConnectedVPN, up: Bool)?
    @Published private(set) var battery: (alert: BatteryStatusViewModel.BatteryAlert, level: Int)?
    @Published private(set) var bluetooth: ConnectedBluetoothDevice?
    @Published private(set) var hotspot = false
    /// A recording "running" since this date.
    @Published private(set) var recording: Date?
    /// Plugged in or not, at this level, this many minutes from full.
    @Published private(set) var power: (pluggedIn: Bool, level: Int, minutesToFull: Int)?

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
        focus = nil; vpn = nil; battery = nil; bluetooth = nil; hotspot = false; recording = nil; power = nil
        let coordinator = VornyxViewCoordinator.shared

        switch kind {
        case .focusOn:
            focus = (true, .work)
            IndicatorsManager.shared.holdFocusInline()
        case .focusOff:
            focus = (false, .work)
            IndicatorsManager.shared.holdFocusInline()
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
        case .hotspot:
            hotspot = true
            coordinator.announceHotspot()
        case .timer:
            CountdownManager.shared.start(90)
        case .timerEnd:
            CountdownManager.shared.start(3)
        case .lockScreen:
            LockScreenPlayerController.shared.preview()
        case .airPodsPro, .airPods3, .airPods2, .airPodsMax:
            // Real product IDs, so each goes through the same model lookup a
            // connecting pair does.
            let pair: AirPodsBattery = switch kind {
            case .airPodsPro: AirPodsBattery(name: "AirPods Pro", left: 72, right: 71, caseLevel: 48, productID: 0x2014)
            case .airPods3: AirPodsBattery(name: "AirPods", left: 64, right: 66, caseLevel: 90, productID: 0x2013)
            case .airPods2: AirPodsBattery(name: "AirPods", left: 38, right: 41, caseLevel: 17, productID: 0x200F)
            default: AirPodsBattery(name: "AirPods Max", single: 83, productID: 0x201F)
            }
            bluetooth = BluetoothDeviceManager.device(for: pair)
            coordinator.announceBluetooth()
        case .colorPicked:
            ColorPickerManager.shared.picked(NSColor(red: 0.95, green: 0.33, blue: 0.47, alpha: 1))
        case .inputSource:
            coordinator.announceInputSource()
        case .screenRecording:
            recording = Date().addingTimeInterval(-42)
            coordinator.announceScreenRecording()
        case .charging:
            power = (true, 67, 83)
            coordinator.toggleExpandingView(status: true, type: .battery)
        case .unplugged:
            power = (false, 67, 0)
            coordinator.toggleExpandingView(status: true, type: .battery)
        case .speaker:
            bluetooth = ConnectedBluetoothDevice(name: "JBL Flip 6", symbol: "hifispeaker.fill", battery: 58)
            coordinator.announceBluetooth()
        }

        log.notice("preview \(kind.rawValue, privacy: .public)")
        // The banner is switched on a run loop pass later; say what landed.
        Task { @MainActor [log] in
            let banner = VornyxViewCoordinator.shared.expandingView
            log.notice("banner \(String(describing: banner.type), privacy: .public) showing: \(banner.show, privacy: .public)")
        }

        // A little longer than the banner itself, so it never flips back to
        // real data while still on screen.
        // The hotspot stays on for a while after its banner, so what the notch
        // shows while one is in use - alone, or beside the music - can be seen.
        let hold: Duration = switch kind {
        case .hotspot, .screenRecording: .seconds(15)
        case .focusOn, .focusOff: .seconds(IndicatorsManager.focusInlineSeconds)
        default: .seconds(4)
        }
        clear = Task { [weak self] in
            try? await Task.sleep(for: hold)
            guard let self, !Task.isCancelled else { return }
            self.focus = nil; self.vpn = nil; self.battery = nil; self.bluetooth = nil; self.hotspot = false; self.recording = nil; self.power = nil
        }
    }
}
