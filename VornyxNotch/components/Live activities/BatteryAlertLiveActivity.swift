//
//  BatteryAlertLiveActivity.swift
//  VornyxNotch
//
//  The battery running low, or reaching full, in the closed notch.
//
//  After DynamicNotch's battery activities by Evgeniy Petrukovich (GPL-3.0),
//  https://github.com/jackson-storm/dynamicnotch
//

import SwiftUI

/// What happened and the level left of the cut-out; a battery, or the plug
/// that filled it, right of it.
struct BatteryAlertLiveActivity: View {
    @EnvironmentObject var vm: VornyxViewModel
    @ObservedObject private var battery = BatteryStatusViewModel.shared
    @ObservedObject private var preview = BannerPreview.shared

    @State private var pulse = false

    private var isLow: Bool { (preview.battery?.alert ?? battery.alert) != .full }
    private var level: Int { preview.battery?.level ?? Int(battery.levelBattery) }
    private var tint: Color { isLow ? .red : .green }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Text(isLow ? "Battery Low" : "Full Battery")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("\(level)%")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                }
                Text(isLow ? "Plug in, or turn on Low Power Mode" : "You can unplug")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            .frame(width: 150, alignment: .leading)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 10)

            Group {
                if isLow {
                    Image(systemName: "battery.25percent")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(tint)
                        .symbolRenderingMode(.hierarchical)
                        .opacity(pulse ? 0.45 : 1)
                } else {
                    Image(systemName: "powerplug.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                        .shadow(color: tint.opacity(pulse ? 0.8 : 0.2), radius: 5)
                }
            }
            .frame(width: 150, alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

/// A battery filled to exactly its level: a translucent case in the tint, the
/// charge a solid bar across it, the tip lit only when full.
///
/// From DynamicNotch's BatteryCompactStatusView by Evgeniy Petrukovich
/// (GPL-3.0), sized by `width`.
struct CompactBatteryGlyph: View {
    let level: Int
    let tint: Color
    var width: CGFloat = 28
    /// Breathes while charging.
    var charging = false

    @State private var breathing = false

    var body: some View {
        let height = width * 16 / 28
        let fraction = CGFloat(max(0, min(level, 100))) / 100

        HStack(spacing: width * 1.5 / 28) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height * 0.375, style: .continuous)
                    .fill(tint.opacity(0.3))
                Rectangle()
                    .fill(tint.gradient)
                    .frame(width: fraction * width)
                    .opacity(charging && breathing ? 0.7 : 1)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: height * 0.375, style: .continuous))

            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(level >= 100 ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(0.3)))
                .frame(width: max(2, width / 14), height: height * 0.375)
        }
        .animation(.smooth(duration: 0.4), value: level)
        .onAppear {
            guard charging else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { breathing = true }
        }
    }
}
