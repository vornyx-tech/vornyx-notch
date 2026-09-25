//
//  FocusLiveActivity.swift
//  VornyxNotch
//
//  A Focus going on or off: a slim peek in the closed notch.
//
//  After DynamicNotch's Focus activity by Evgeniy Petrukovich (GPL-3.0),
//  https://github.com/jackson-storm/dynamicnotch
//

import SwiftUI

/// The mode's symbol left of the cut-out and On or Off right of it, in the
/// mode's colour - built from the music activity's pieces, so it is exactly
/// as wide and no taller than the notch.
struct FocusLiveActivity: View {
    @EnvironmentObject var vm: VornyxViewModel
    @ObservedObject private var indicators = IndicatorsManager.shared
    @ObservedObject private var preview = BannerPreview.shared

    private var isOn: Bool { preview.focus?.on ?? indicators.indicators.focus }
    /// Which mode, when the source says; a plain Focus's look otherwise, not
    /// Do Not Disturb's, which would be a guess.
    /// The last mode seen stands in only for Off - the one that just ended.
    /// For On it would be stale: a mode from hours ago, shown as current.
    private var mode: FocusMode {
        if let mode = preview.focus?.mode { return mode }
        if isOn { return indicators.focusMode ?? .other }
        return indicators.lastFocusMode ?? .other
    }

    var body: some View {
        let side = max(0, vm.effectiveClosedNotchHeight - 12)
        let tint = isOn ? mode.tint : .white.opacity(0.45)

        HStack {
            Image(systemName: mode.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: isOn)
                .frame(width: side, height: side)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)

            Text(isOn ? "On" : "Off")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .fixedSize()
                .frame(width: side, height: side)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .animation(.smooth(duration: 0.25), value: isOn)
    }
}
