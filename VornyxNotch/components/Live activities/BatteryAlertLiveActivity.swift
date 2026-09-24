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

    @State private var pulse = false

    private var isLow: Bool { battery.alert != .full }
    private var tint: Color { isLow ? .red : .green }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Text(isLow ? "Battery Low" : "Full Battery")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("\(Int(battery.levelBattery))%")
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
