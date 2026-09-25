//
//  TimerLiveActivity.swift
//  VornyxNotch
//
//  The countdown in the closed notch.
//

import Defaults
import SwiftUI

/// Label on the left of the cut-out, the time and a ring on the right.
struct TimerLiveActivity: View {
    @EnvironmentObject var vm: VornyxViewModel
    @ObservedObject private var countdown = CountdownManager.shared

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: countdown.state == .finished ? "bell.fill" : "timer")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tint)
                    .symbolEffect(.pulse, isActive: countdown.state == .finished)

                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 10)

            HStack(spacing: 6) {
                Spacer(minLength: 0)

                Text(countdown.label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(countsDown: true))

                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.15), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: countdown.progress)
                        .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.smooth(duration: 0.3), value: countdown.progress)
                }
                .frame(width: 16, height: 16)
            }
            .frame(width: 110, alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    private var title: String {
        switch countdown.state {
        case .finished: return "Time's up"
        case .paused: return "Paused"
        default: return "Timer"
        }
    }

    @Default(.notchEdgeProgress) private var edgeProgress

    /// The edge light's colour while that light is on - accent text under an
    /// orange line clashed - and the accent otherwise.
    private var tint: Color {
        if countdown.state == .paused { return .white.opacity(0.5) }
        return edgeProgress ? CountdownManager.color : Color.effectiveAccent
    }
}
