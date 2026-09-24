//
//  FocusLiveActivity.swift
//  VornyxNotch
//
//  A Focus going on or off, in the closed notch.
//
//  Layout after DynamicNotch's Focus activity by Evgeniy Petrukovich
//  (GPL-3.0), https://github.com/jackson-storm/dynamicnotch
//

import SwiftUI

/// The mode's symbol and name left of the cut-out, On or Off right of it, in
/// the mode's own colour.
struct FocusLiveActivity: View {
    @EnvironmentObject var vm: VornyxViewModel
    @ObservedObject private var indicators = IndicatorsManager.shared

    private var isOn: Bool { indicators.indicators.focus }
    /// Which mode, when the source says; Do Not Disturb's look otherwise.
    private var mode: FocusMode { indicators.focusMode ?? indicators.lastFocusMode ?? .doNotDisturb }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isOn ? mode.tint : .white.opacity(0.45))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: isOn)
                // Only a named mode is worth the words; "Focus" says nothing
                // the moon does not.
                if indicators.focusMode != nil || indicators.lastFocusMode != nil {
                    Text(mode.name)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }
            .frame(width: 110, alignment: .leading)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 10)

            Text(isOn ? "On" : "Off")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(isOn ? mode.tint : .white.opacity(0.45))
                .contentTransition(.numericText())
                .frame(width: 110, alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .animation(.smooth(duration: 0.25), value: isOn)
    }
}
