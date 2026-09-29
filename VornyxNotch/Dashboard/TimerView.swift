//
//  TimerView.swift
//  VornyxNotch
//

import Defaults
import SwiftUI

/// A ring with the time in it on the left; on the right, lengths to start
/// with one click, fine steps, and play and reset.
///
/// Idle, the steps set the next countdown's length. Running or paused, they
/// add or take time off the one going.
struct TimerView: View {
    @ObservedObject private var countdown = CountdownManager.shared
    /// Read here rather than through the manager: a setting changing does
    /// not republish the manager, so the length stepped with - and + stayed
    /// on screen as it was until the countdown started.
    @Default(.timerLastDuration) private var lastDuration

    /// Lengths offered for a click, in minutes.
    private static let presets: [Int] = [5, 10, 15, 25, 45, 60]
    private static let longest: Double = 12 * 60 * 60

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            ring
                .frame(width: 138, height: 138)

            VStack(alignment: .leading, spacing: 10) {
                presetGrid
                stepper
                transport
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Reading

    private var isGoing: Bool { countdown.isActive }

    private var timeLabel: String {
        if isGoing || countdown.state == .finished { return countdown.label }
        return CountdownManager.format(lastDuration)
    }

    /// How much of the ring is lit: what is left of the countdown, or all of
    /// it while nothing runs.
    private var fraction: Double {
        switch countdown.state {
        case .running, .paused: return 1 - countdown.progress
        case .finished: return 0
        case .idle: return 1
        }
    }

    private var status: String {
        switch countdown.state {
        case .idle: return "Ready"
        case .running: return "Running"
        case .paused: return "Paused"
        case .finished: return "Done"
        }
    }

    private var tint: Color { CountdownManager.color }

    // MARK: - Pieces

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.08), lineWidth: 8)

            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    tint.opacity(countdown.state == .idle ? 0.35 : 1),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(countdown.state == .running ? 0.45 : 0), radius: 6)
                .animation(.linear(duration: 1), value: fraction)
                .animation(.smooth(duration: 0.3), value: countdown.state)

            VStack(spacing: 2) {
                Text(timeLabel)
                    .font(.system(size: timeLabel.count > 5 ? 22 : 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.smooth(duration: 0.2), value: timeLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(status)
                    .font(.system(size: 9, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .foregroundStyle(countdown.state == .finished ? tint : .white.opacity(0.4))
            }
            .padding(.horizontal, 14)
        }
    }

    /// One click starts a countdown of that length, over whatever runs.
    private var presetGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3),
            spacing: 6
        ) {
            ForEach(Self.presets, id: \.self) { minutes in
                let current = !isGoing && Int(lastDuration / 60) == minutes
                Button {
                    countdown.start(Double(minutes) * 60)
                } label: {
                    Text(minutes == 60 ? "1h" : "\(minutes)m")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(current ? .black.opacity(0.85) : .white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .background {
                            Capsule().fill(current ? tint.opacity(0.9) : .white.opacity(0.08))
                        }
                        .contentShape(Capsule())
                }
                .springyTile(hoverScale: 1.06, pressScale: 0.94, hoverBrightness: 0.12)
            }
        }
    }

    /// A minute off or on: the next length while idle, the running one else.
    private var stepper: some View {
        HStack(spacing: 6) {
            stepButton("minus", seconds: -60)
            Text(isGoing ? "Adjust" : "Length")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .frame(maxWidth: .infinity)
            stepButton("plus", seconds: 60)
        }
        .frame(height: 24)
        .background { Capsule().fill(.white.opacity(0.05)) }
    }

    private func stepButton(_ symbol: String, seconds: TimeInterval) -> some View {
        Button {
            if isGoing {
                countdown.adjust(by: seconds)
            } else {
                lastDuration = (lastDuration + seconds).clamped(to: 60...Self.longest)
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 32, height: 24)
                .contentShape(Capsule())
        }
        .springyTile(hoverScale: 1.1, pressScale: 0.9, hoverBrightness: 0.15)
    }

    private var transport: some View {
        HStack(spacing: 6) {
            Button {
                countdown.toggle()
            } label: {
                Label(
                    countdown.state == .running ? "Pause" : (countdown.state == .paused ? "Resume" : "Start"),
                    systemImage: countdown.state == .running ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background { Capsule().fill(tint) }
                    .contentShape(Capsule())
            }
            .springyTile(hoverScale: 1.04, pressScale: 0.95, hoverBrightness: 0.1)

            Button {
                countdown.reset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .background { Circle().fill(.white.opacity(0.1)) }
                    .contentShape(Circle())
            }
            .springyTile(hoverScale: 1.1, pressScale: 0.9, hoverBrightness: 0.15)
            .disabled(countdown.state == .idle)
            .opacity(countdown.state == .idle ? 0.35 : 1)
        }
    }
}
