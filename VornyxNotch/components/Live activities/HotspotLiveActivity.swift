//
//  HotspotLiveActivity.swift
//  VornyxNotch
//
//  A Personal Hotspot joined, either side of the camera.
//
//  After DynamicNotch's HotspotActiveNotchView by Evgeniy Petrukovich
//  (GPL-3.0), https://github.com/jackson-storm/dynamicnotch
//

import SwiftUI

/// The hotspot symbol left of the cut-out; the phone's charge, or On, right of it.
struct HotspotLiveActivity: View {
    @EnvironmentObject var vm: VornyxViewModel
    @ObservedObject private var hotspot = HotspotManager.shared
    @ObservedObject private var preview = BannerPreview.shared

    var body: some View {
        let level = preview.hotspot?.battery ?? hotspot.phoneBattery

        HStack(spacing: 0) {
            Image(systemName: "personalhotspot")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.green)
                .symbolEffect(.pulse)
                .frame(width: 90, alignment: .leading)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 10)

            Group {
                if let level {
                    BatteryRing(level: level)
                } else {
                    Text("On")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.green)
                }
            }
            .frame(width: 90, alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}
