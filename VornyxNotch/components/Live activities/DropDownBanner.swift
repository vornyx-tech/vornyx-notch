//
//  DropDownBanner.swift
//  VornyxNotch
//
//  The Focus, VPN, battery and Bluetooth banners, dropped down under the
//  camera instead of either side of it.
//
//  After DynamicNotch's expanded activities by Evgeniy Petrukovich (GPL-3.0),
//  https://github.com/jackson-storm/dynamicnotch
//

import Defaults
import SwiftUI

/// Whether a banner of this type has a drop-down form.
extension SneakContentType {
    var hasDropDownBanner: Bool {
        switch self {
        case .focus, .vpn, .batteryAlert, .bluetooth: return true
        default: return false
        }
    }
}

/// The row under the closed notch's own, for the banner showing. The notch
/// grows down around it, so there is room for two lines and a proper icon.
struct DropDownBanner: View {
    @EnvironmentObject var vm: VornyxViewModel
    @ObservedObject private var coordinator = VornyxViewCoordinator.shared
    @ObservedObject private var preview = BannerPreview.shared
    @ObservedObject private var indicators = IndicatorsManager.shared
    @ObservedObject private var vpn = VPNManager.shared
    @ObservedObject private var battery = BatteryStatusViewModel.shared
    @ObservedObject private var bluetooth = BluetoothDeviceManager.shared

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            content
        }
        .padding(.horizontal, 20)
        .frame(width: vm.closedNotchSize.width + 170, height: 52)
        .padding(.bottom, 8)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch coordinator.expandingView.type {
        case .focus: focus
        case .vpn: vpnRow
        case .batteryAlert: batteryRow
        case .bluetooth: bluetoothRow
        default: EmptyView()
        }
    }

    // MARK: - Pieces

    private func titles(_ title: String, value: String? = nil, tint: Color = .white, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let value {
                    Text(value)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                }
            }
            Text(subtitle)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Focus

    private var focus: some View {
        let isOn = preview.focus?.on ?? indicators.indicators.focus
        let mode = preview.focus?.mode ?? indicators.focusMode ?? indicators.lastFocusMode ?? .doNotDisturb

        return Group {
            Image(systemName: mode.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isOn ? mode.tint : .white.opacity(0.45))
                .symbolEffect(.bounce, value: isOn)
                .frame(width: 30)
            titles(mode.name, isOn ? "Focus is on" : "Focus is off")
            Spacer(minLength: 0)
            Text(isOn ? "On" : "Off")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(isOn ? mode.tint : .white.opacity(0.45))
        }
    }

    // MARK: - VPN

    private static let vpnTint = Color(red: 1.0, green: 0.62, blue: 0.2)

    private var vpnRow: some View {
        let shown = preview.vpn?.vpn ?? vpn.connected ?? vpn.last
        let isUp = preview.vpn?.up ?? (vpn.connected != nil)

        return Group {
            Group {
                if let icon = VPNManager.icon(for: shown) {
                    Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isUp ? Self.vpnTint : .white.opacity(0.45))
                }
            }
            .frame(width: 30, height: 30)
            titles(shown?.name ?? "VPN", isUp ? "Connected" : "Disconnected")
            Spacer(minLength: 0)
            Group {
                if isUp, let since = shown?.connectedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(VPNLiveActivity.elapsed(from: since, to: context.date))
                            .contentTransition(.numericText())
                    }
                    .foregroundStyle(Self.vpnTint)
                } else {
                    Text(isUp ? "On" : "Off")
                        .foregroundStyle(isUp ? Self.vpnTint : .white.opacity(0.45))
                }
            }
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .monospacedDigit()
        }
    }

    // MARK: - Battery

    private var batteryRow: some View {
        let isLow = (preview.battery?.alert ?? battery.alert) != .full
        let level = preview.battery?.level ?? Int(battery.levelBattery)
        let tint: Color = isLow ? .red : .green

        return Group {
            titles(
                isLow ? "Battery Low" : "Full Battery", value: "\(level)%", tint: tint,
                isLow ? "Plug in, or turn on Low Power Mode." : "Your Mac is fully charged.")
            Spacer(minLength: 0)
            if isLow {
                Image(systemName: "battery.25percent")
                    .font(.system(size: 26, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                    .opacity(pulse ? 0.45 : 1)
            } else {
                HStack(spacing: 0) {
                    Capsule().fill(.white.opacity(0.25)).frame(width: 18, height: 2)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(.white.opacity(0.12))
                        .frame(width: 16, height: 22)
                        .overlay(Circle().fill(tint).frame(width: 4, height: 4)
                            .shadow(color: tint, radius: pulse ? 5 : 1))
                }
            }
        }
    }

    // MARK: - Bluetooth

    private var bluetoothRow: some View {
        let device = preview.bluetooth ?? bluetooth.latest

        return Group {
            Image(systemName: device?.symbol ?? "dot.radiowaves.left.and.right")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 30)
            titles(device?.name ?? "Bluetooth", "Connected")
            Spacer(minLength: 0)
            if let level = device?.battery {
                BatteryRing(level: level)
                    .scaleEffect(1.35)
                    .padding(.trailing, 4)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.green)
            }
        }
    }
}
