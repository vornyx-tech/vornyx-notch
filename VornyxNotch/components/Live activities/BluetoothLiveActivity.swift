//
//  BluetoothLiveActivity.swift
//  VornyxNotch
//
//  A Bluetooth device connecting, in the closed notch.
//
//  Layout after DynamicNotch's Bluetooth activity by Evgeniy Petrukovich
//  (GPL-3.0), https://github.com/jackson-storm/dynamicnotch
//

import SwiftUI

/// The device's symbol and name left of the cut-out, its charge in a ring
/// right of it.
struct BluetoothLiveActivity: View {
    @EnvironmentObject var vm: VornyxViewModel
    @ObservedObject private var bluetooth = BluetoothDeviceManager.shared
    @ObservedObject private var preview = BannerPreview.shared

    var body: some View {
        let device = preview.bluetooth ?? bluetooth.latest

        HStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: device?.symbol ?? "dot.radiowaves.left.and.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Connected")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(device?.name ?? "Bluetooth")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(width: 130, alignment: .leading)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 10)

            Group {
                if let level = device?.battery {
                    BatteryRing(level: level)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.green)
                }
            }
            .frame(width: 130, alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}

/// The level as a number inside a ring: green, orange under 50, red under 20.
struct BatteryRing: View {
    let level: Int

    @State private var drawn: CGFloat = 0

    private var tint: Color {
        level < 20 ? .red : (level < 50 ? .orange : .green)
    }

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.2), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: drawn)
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(level)")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .frame(width: 22, height: 22)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { drawn = CGFloat(level) / 100 }
        }
    }
}
