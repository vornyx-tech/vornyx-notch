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

            Text("On")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.green)
                .fixedSize()
                .frame(width: side, height: side)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}

/// The hotspot's symbol alone, for joining another activity on its left.
struct HotspotSymbol: View {
    let side: CGFloat

    var body: some View {
        Image(systemName: "personalhotspot")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.green)
            .frame(width: side, height: side)
    }
}
