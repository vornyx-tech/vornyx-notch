//
//  TimerView.swift
//  VornyxNotch
//

import Defaults
import SwiftUI

/// The ring and the time on the left, the presets on the right.
struct TimerView: View {
    @ObservedObject private var countdown = CountdownManager.shared

    /// Minutes.
    private let presets: [Int] = [1, 3, 5, 10, 15, 25, 45, 60]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            dial
            controls
        }
    }

    // MARK: - The dial

    private var dial: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.08), lineWidth: 6)

                Circle()
                    .trim(from: 0, to: countdown.isActive || countdown.state == .finished
                          ? countdown.progress : 0)
                    .stroke(
                        AngularGradient(
                            colors: [Color.effectiveAccent.opacity(0.7), Color.effectiveAccent],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth(duration: 0.3), value: countdown.progress)

                VStack(spacing: 0) {
                    Text(countdown.isActive || countdown.state == .finished
                         ? countdown.label
                         : CountdownManager.format(countdown.lastDuration))
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())

                    Text(status)
                        .font(.system(size: 8, weight: .semibold))
                        .textCase(.uppercase)
                        .kerning(0.5)
                        .foregroundStyle(statusTint)
                }
            }
            .frame(width: 96, height: 96)

            transport
        }
        .frame(width: 110)
    }

    private var status: String {
        switch countdown.state {
        case .idle: return "Ready"
        case .running: return "Running"
        case .paused: return "Paused"
        case .finished: return "Done"
        }
    }

    private var statusTint: Color {
        switch countdown.state {
        case .finished: return Color.effectiveAccent
        case .running: return .white.opacity(0.45)
        default: return .white.opacity(0.3)
        }
    }

    private var transport: some View {
        HStack(spacing: 6) {
            circleButton(
                countdown.state == .running ? "pause.fill" : "play.fill",
                prominent: true
            ) {
                countdown.toggle()
            }

            circleButton("arrow.counterclockwise", prominent: false) {
                countdown.reset()
            }
            .disabled(countdown.state == .idle)
            .opacity(countdown.state == .idle ? 0.35 : 1)

            circleButton("plus", prominent: false) {
                countdown.adjust(by: 60)
            }
            .help("Add a minute")
        }
    }

    private func circleButton(
        _ symbol: String,
        prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Circle()
                .fill(prominent ? Color.effectiveAccent.opacity(0.85) : .white.opacity(0.10))
                .frame(width: prominent ? 28 : 24, height: prominent ? 28 : 24)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: prominent ? 11 : 9, weight: .bold))
                        .foregroundStyle(prominent ? .black.opacity(0.85) : .white.opacity(0.8))
                }
        }
        .springyTile(hoverScale: 1.12, pressScale: 0.9, hoverBrightness: 0.12)
    }

    // MARK: - Presets

    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Start")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .kerning(0.6)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 4),
                spacing: 5
            ) {
                ForEach(presets, id: \.self) { minutes in
                    presetTile(minutes)
                }
            }

            Spacer(minLength: 0)

            if countdown.isActive {
                Text("Counting down in the closed notch too.")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func presetTile(_ minutes: Int) -> some View {
        let selected = Int(countdown.lastDuration / 60) == minutes && countdown.isActive

        return Button {
            countdown.start(TimeInterval(minutes) * 60)
        } label: {
            Text("\(minutes)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(selected ? Color.effectiveAccent : .white.opacity(0.85))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: nestedCornerRadius(inset: 6, cap: 8), style: .continuous)
                        .fill(selected ? Color.effectiveAccent.opacity(0.22) : .white.opacity(0.07))
                )
        }
        .springyTile(hoverScale: 1.07, pressScale: 0.93, hoverBrightness: 0.10)
        .help("\(minutes) minute\(minutes == 1 ? "" : "s")")
    }
}
