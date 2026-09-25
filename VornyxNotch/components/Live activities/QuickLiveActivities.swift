//
//  QuickLiveActivities.swift
//  VornyxNotch
//
//  The inline forms of the glance banners: a colour picked, the layout.
//

import SwiftUI

/// The colour's swatch left of the cut-out, its hex right of it.
struct ColorPickedLiveActivity: View {
    @EnvironmentObject var vm: VornyxViewModel
    @ObservedObject private var colors = ColorPickerManager.shared

    var body: some View {
        let picked = colors.recent.first ?? .white

        HStack(spacing: 0) {
            Circle()
                .fill(Color(nsColor: picked))
                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
                .frame(width: 16, height: 16)
                .frame(width: 90, alignment: .leading)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 10)

            Text(ColorPickerManager.hex(picked))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 90, alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}

/// A short peak: the language's flag on the left, its code on the right.
struct InputSourceLiveActivity: View {
    @ObservedObject private var input = InputSourceManager.shared

    var body: some View {
        let source = input.current

        ShortPeak {
            if let flag = source?.flag {
                Text(flag).font(.system(size: 13))
            } else {
                Image(systemName: "keyboard")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
            }
        } trailing: {
            Text(source?.code ?? "")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}
