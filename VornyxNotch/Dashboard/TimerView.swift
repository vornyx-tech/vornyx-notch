//
//  TimerView.swift
//  VornyxNotch
//

import Defaults
import SwiftUI

/// The time on top, a horizontal slider that sets it, the controls below.
///
/// Idle, the slider picks the next countdown's length. Running or paused, it
/// shows what is left and dragging it moves the countdown's end.
struct TimerView: View {
    @ObservedObject private var countdown = CountdownManager.shared

    /// What the knob is on while it is held, in minutes.
    @State private var dragMinutes: Double?

    static let range: ClosedRange<Double> = 1...120

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            TimerSlider(
                minutes: sliderMinutes,
                range: Self.range,
                tint: Color.effectiveAccent,
                onChange: { dragMinutes = $0 },
                onCommit: commit
            )
            .frame(height: 40)
            transport
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Reading

    /// Minutes the slider sits at: the held value, what is left, or the next
    /// countdown's length.
    private var sliderMinutes: Double {
        if let dragMinutes { return dragMinutes }
        if countdown.isActive || countdown.state == .finished {
            return countdown.remaining / 60
        }
        return countdown.lastDuration / 60
    }

    private var timeLabel: String {
        if let dragMinutes { return CountdownManager.format(dragMinutes.rounded() * 60) }
        if countdown.isActive || countdown.state == .finished { return countdown.label }
        return CountdownManager.format(countdown.lastDuration)
    }

    private var status: String {
        if dragMinutes != nil { return countdown.isActive ? "Change" : "Set" }
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

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(timeLabel)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.15), value: timeLabel)

            Text(status)
                .font(.system(size: 9, weight: .semibold))
                .textCase(.uppercase)
                .kerning(0.5)
                .foregroundStyle(statusTint)

            Spacer(minLength: 0)
        }
    }

    private var transport: some View {
        HStack(spacing: 8) {
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

            Spacer(minLength: 0)

            if countdown.isActive {
                Text("Also in the closed notch")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
            }
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

    // MARK: - Driving

    private func commit(_ minutes: Double) {
        dragMinutes = nil
        let seconds = minutes.rounded() * 60
        switch countdown.state {
        case .running, .paused:
            countdown.adjust(by: seconds - countdown.remaining)
        case .idle, .finished:
            countdown.lastDuration = seconds
        }
    }
}

/// A ruler you drag along: a tick every five minutes, a taller one every
/// fifteen, the fill up to the knob. Snaps to whole minutes.
private struct TimerSlider: View {
    let minutes: Double
    let range: ClosedRange<Double>
    let tint: Color
    let onChange: (Double) -> Void
    let onCommit: (Double) -> Void

    @State private var held = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let span = range.upperBound - range.lowerBound
            let fraction = ((minutes - range.lowerBound) / span).clamped(to: 0...1)
            let knobX = fraction * width
            let trackHeight: CGFloat = held ? 10 : 8

            ZStack(alignment: .leading) {
                // Just under the track, which sits on the centre line.
                ticks(width: width, span: span)
                    .offset(y: 14)

                Capsule()
                    .fill(.white.opacity(0.10))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.6), tint],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: max(trackHeight, knobX), height: trackHeight)

                Circle()
                    .fill(.white)
                    .frame(width: held ? 18 : 14, height: held ? 18 : 14)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .offset(x: knobX.clamped(to: 0...width) - (held ? 9 : 7))
            }
            .frame(height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        held = true
                        onChange(value(at: gesture.location.x, width: width, span: span))
                    }
                    .onEnded { gesture in
                        held = false
                        onCommit(value(at: gesture.location.x, width: width, span: span))
                    }
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: held)
        }
    }

    private func value(at x: CGFloat, width: CGFloat, span: Double) -> Double {
        guard width > 0 else { return range.lowerBound }
        let raw = range.lowerBound + Double(x / width) * span
        return raw.rounded().clamped(to: range)
    }

    /// Ticks under the track, with the fifteens labelled.
    private func ticks(width: CGFloat, span: Double) -> some View {
        let marks = stride(from: 0, through: Int(range.upperBound), by: 5).map { $0 }
        return ZStack(alignment: .topLeading) {
            ForEach(marks, id: \.self) { mark in
                let x = CGFloat((Double(max(mark, Int(range.lowerBound))) - range.lowerBound) / span) * width
                let major = mark % 15 == 0
                Rectangle()
                    .fill(.white.opacity(major ? 0.28 : 0.14))
                    .frame(width: 1, height: major ? 6 : 3)
                    .offset(x: x, y: 0)
                if major && mark > 0 && mark < Int(range.upperBound) {
                    Text("\(mark)")
                        .font(.system(size: 7, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.3))
                        .fixedSize()
                        .offset(x: x - 5, y: 7)
                }
            }
        }
        .frame(width: width, height: 16, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}
