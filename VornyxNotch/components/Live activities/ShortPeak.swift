//
//  ShortPeak.swift
//  VornyxNotch
//
//  The slim inline banner: one thing left of the camera, one right of it.
//

import SwiftUI

/// Built from the music activity's own pieces - a square either side of the
/// cut-out, the black between - so every short peak is exactly as wide as
/// the music and no taller than the notch. Focus, the battery, the keyboard
/// layout and the rest all use it, so they never drift apart in size.
struct ShortPeak<Leading: View, Trailing: View>: View {
    @EnvironmentObject var vm: VornyxViewModel
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        let side = max(0, vm.effectiveClosedNotchHeight - 12)

        HStack {
            leading
                .frame(width: side, height: side)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)

            trailing
                .fixedSize()
                .frame(width: side, height: side)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}
