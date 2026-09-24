//
//  VPNLiveActivity.swift
//  VornyxNotch
//
//  A VPN connecting or dropping, in the closed notch.
//
//  Layout after DynamicNotch's VPN activity by Evgeniy Petrukovich
//  (GPL-3.0), https://github.com/jackson-storm/dynamicnotch
//

import SwiftUI

/// The VPN app's icon and the tunnel's name left of the cut-out, how long it
/// has been up right of it.
struct VPNLiveActivity: View {
    @EnvironmentObject var vm: VornyxViewModel
    @ObservedObject private var vpn = VPNManager.shared

    private static let tint = Color(red: 1.0, green: 0.62, blue: 0.2)

    var body: some View {
        let shown = vpn.connected ?? vpn.last
        let isUp = vpn.connected != nil

        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Group {
                    if let icon = VPNManager.icon(for: shown) {
                        Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isUp ? Self.tint : .white.opacity(0.45))
                    }
                }
                .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 0) {
                    Text(isUp ? "Connected" : "Disconnected")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(shown?.name ?? "VPN")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(width: 120, alignment: .leading)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 10)

            Group {
                if isUp, let since = shown?.connectedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(Self.elapsed(from: since, to: context.date))
                            .foregroundStyle(Self.tint)
                            .contentTransition(.numericText())
                    }
                } else {
                    Text(isUp ? "On" : "Off")
                        .foregroundStyle(isUp ? Self.tint : .white.opacity(0.45))
                }
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .frame(width: 120, alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    /// `8:35`, or `1:08:35` past an hour.
    static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
