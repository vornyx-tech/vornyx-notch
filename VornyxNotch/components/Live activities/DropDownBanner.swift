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
        case .focus, .vpn, .batteryAlert, .bluetooth, .hotspot: return true
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
    @ObservedObject private var hotspot = HotspotManager.shared
    @ObservedObject private var countdown = CountdownManager.shared

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
        // A finished countdown outranks the rest: it waits on a click.
        if countdown.state == .finished {
            timerDone
        } else {
            banner
        }
    }

    @ViewBuilder
    private var banner: some View {
        switch coordinator.expandingView.type {
        case .focus: focus
        case .vpn: vpnRow
        case .batteryAlert: batteryRow
        case .bluetooth: bluetoothRow
        case .hotspot: hotspotRow
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
        let lowPower = battery.isInLowPowerMode && preview.battery == nil
        let tint: Color = lowPower ? .yellow : (isLow ? .red : .green)

        return Group {
            titles(
                isLow ? "Battery Low" : "Full Battery", value: "\(level)%", tint: tint,
                isLow
                    ? (lowPower ? "Low Power Mode is on. Plug in soon." : "Turn on Low Power Mode, or plug in.")
                    : "Your Mac is fully charged.")
            Spacer(minLength: 0)
            if isLow {
                LowBatteryIndicator(tint: tint, pulses: !lowPower)
            } else {
                MagSafeIndicator()
            }
        }
    }

    // MARK: - Timer

    /// Stop on the left, the zeroed time on the right, in the timer's orange.
    ///
    /// After DynamicNotch's TimerExpandedNotchView by Evgeniy Petrukovich
    /// (GPL-3.0): the same pieces, one Stop in place of pause and close.
    private var timerDone: some View {
        Group {
            Button {
                countdown.reset()
            } label: {
                Text("Stop")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CountdownManager.color)
                    .frame(width: 84, height: 40)
                    .background(CountdownManager.color.opacity(0.3), in: Capsule())
                    // Breathes with the ringing, so the way out is the
                    // brightest thing in the notch.
                    .background {
                        Capsule()
                            .fill(CountdownManager.color)
                            .blur(radius: pulse ? 10 : 4)
                            .opacity(pulse ? 0.45 : 0.12)
                    }
                    .shadow(color: CountdownManager.color.opacity(pulse ? 0.6 : 0.15), radius: pulse ? 8 : 2)
                    .contentShape(Capsule())
            }
            // springyTile is the button style; a .plain before it would win,
            // being closer to the button, and the hover would never show.
            .springyTile(hoverScale: 1.1, pressScale: 0.92, hoverBrightness: 0.14)

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Timer")
                    .font(.system(size: 14))
                    .foregroundStyle(CountdownManager.color.opacity(0.8))
                Text("00:00")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(CountdownManager.color)
                    .opacity(pulse ? 1 : 0.55)
            }
        }
    }

    // MARK: - Hotspot

    private var hotspotRow: some View {
        Group {
            Image(systemName: "personalhotspot")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.green)
                .symbolEffect(.pulse)
                .frame(width: 30)
            titles("Personal Hotspot", "Connected")
            Spacer(minLength: 0)
            Text("On")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.green)
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

/// A battery nearly empty inside a pill, its last bar blinking and a ring
/// closing in on it.
///
/// From DynamicNotch's LowPowerNotchView by Evgeniy Petrukovich (GPL-3.0).
private struct LowBatteryIndicator: View {
    let tint: Color
    let pulses: Bool

    @State private var pulse = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30)
                .fill(tint.opacity(0.2))
                .frame(width: 66, height: 38)

            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.4)).frame(width: 34, height: 20)
                RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.4)).frame(width: 3, height: 7)
            }
            .padding(.trailing, 4)

            RoundedRectangle(cornerRadius: 6)
                .fill(tint.gradient)
                .frame(width: 7, height: 12)
                .opacity(pulses ? (pulse ? 1 : 0.3) : 1)
                .offset(x: -12)

            if pulses {
                RoundedRectangle(cornerRadius: 30)
                    .stroke(tint.opacity(0.9).gradient, lineWidth: 1.5)
                    .frame(width: pulse ? 7 : 26, height: pulse ? 12 : 28)
                    .offset(x: -12)
                    .opacity(pulse ? 0.3 : 1)
            }
        }
        .onAppear {
            guard pulses else { return }
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

/// A MagSafe plug in the port, its light going from charging orange to green.
///
/// From DynamicNotch's FullPowerNotchView by Evgeniy Petrukovich (GPL-3.0).
private struct MagSafeIndicator: View {
    @State private var charged = false

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(.gray.opacity(0.15)).frame(width: 26, height: 5)
            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.gray.opacity(0.2).gradient)
                    .frame(width: 30, height: 38)
                Circle()
                    .fill(charged ? .green : .orange)
                    .shadow(color: charged ? .green : .orange, radius: 5)
                    .frame(width: 5, height: 5)
            }
            Rectangle().fill(.white.opacity(0.4)).frame(width: 3, height: 30)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.spring(duration: 0.3)) { charged = true }
            }
        }
    }
}
