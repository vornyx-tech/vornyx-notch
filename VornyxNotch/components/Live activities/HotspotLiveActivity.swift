//
//  HotspotLiveActivity.swift
//  VornyxNotch
//
//  A Personal Hotspot in use, in the closed notch.
//
//  After DynamicNotch's HotspotActiveNotchView by Evgeniy Petrukovich
//  (GPL-3.0), https://github.com/jackson-storm/dynamicnotch
//

import SwiftUI

/// The hotspot symbol left of the cut-out and On right of it, for as long as
/// the hotspot is in use - built from the music activity's own pieces, so it
/// is exactly as wide.
struct HotspotLiveActivity: View {
    @EnvironmentObject var vm: VornyxViewModel

    var body: some View {
        let side = max(0, vm.effectiveClosedNotchHeight - 12)

        HStack {
            HotspotSymbol(side: side)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)

            HotspotUsage()
                .frame(width: side, height: side)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}

/// The hotspot's symbol, with a slow green glow breathing behind it.
struct HotspotSymbol: View {
    let side: CGFloat

    @State private var glowing = false

    var body: some View {
        Image(systemName: "personalhotspot")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.green)
            .background {
                Circle()
                    .fill(.green)
                    .frame(width: 16, height: 16)
                    .blur(radius: glowing ? 7 : 4)
                    .opacity(glowing ? 0.55 : 0.12)
                    .scaleEffect(glowing ? 1.25 : 0.8)
            }
            .shadow(color: .green.opacity(glowing ? 0.7 : 0.2), radius: glowing ? 4 : 1)
            .frame(width: side, height: side)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                    glowing = true
                }
            }
    }
}

/// How much of the phone's data the hotspot has used, or On before any has.
struct HotspotUsage: View {
    @ObservedObject private var hotspot = HotspotManager.shared
    @ObservedObject private var preview = BannerPreview.shared

    var body: some View {
        let bytes = preview.hotspot ? 84_000_000 : hotspot.sessionBytes

        Text(bytes >= 1_000_000 ? HotspotManager.compact(bytes) : "On")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.green)
            .contentTransition(.numericText())
            .animation(.smooth, value: bytes / 1_000_000)
            .fixedSize()
            .help("Mobile data used through the hotspot since the Mac joined it")
    }
}
