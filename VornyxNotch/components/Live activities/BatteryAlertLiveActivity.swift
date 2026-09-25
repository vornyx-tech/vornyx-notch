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

/// A short peak: the battery, drawn as in the drop-down, small on the left;
/// the level on the right. Red when low, green when full, yellow in Low Power
/// Mode.
struct BatteryAlertLiveActivity: View {
    @ObservedObject private var battery = BatteryStatusViewModel.shared
    @ObservedObject private var preview = BannerPreview.shared

    private var isLow: Bool { (preview.battery?.alert ?? battery.alert) != .full }
    private var level: Int { preview.battery?.level ?? Int(battery.levelBattery) }
    private var tint: Color {
        if battery.isInLowPowerMode { return .yellow }
        return isLow ? .red : .green
    }

    var body: some View {
        ShortPeak {
            CompactBatteryGlyph(level: level, tint: tint, width: 20, charging: !isLow && level < 100)
        } trailing: {
            Text("\(level)%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
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
