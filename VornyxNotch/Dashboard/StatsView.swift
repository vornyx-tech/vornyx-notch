//
//  StatsView.swift
//  VornyxNotch
//

import SwiftUI

/// One number, one graph, and two quiet meters under it.
struct StatsView: View {
    @ObservedObject private var stats = StatsManager.shared

    var body: some View {
        // Sized to fit the notch: this column gets about 190pt of the
        // dashboard's 252, and the row takes the height of its tallest child.
        VStack(alignment: .leading, spacing: 6) {
            hero
            chart
            meters
            network
            Spacer(minLength: 0)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { stats.addWatcher() }
        .onDisappear { stats.removeWatcher() }
    }

    private var reading: MachineStats { stats.stats }

    // MARK: - Hero

    private var hero: some View {
        HStack(alignment: .lastTextBaseline, spacing: 3) {
            Text("\(Int((reading.cpu * 100).rounded()))")
                .font(.system(size: 40, weight: .light, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                // Light type on black loses its edges without the gradient.
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, tint.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Text("%")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.35))

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 1) {
                Text("Processor")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text("\(reading.cores) cores · load \(String(format: "%.2f", reading.loadAverage))")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.35))
                    .monospacedDigit()
            }
        }
    }

    /// Full width and unboxed, running off both edges of the page.
    private var chart: some View {
        AreaChart(values: stats.cpuHistory, ceiling: 1, tint: tint)
            .frame(height: 42)
    }

    private var tint: Color {
        switch reading.cpu {
        case ..<0.6: return Color.effectiveAccent
        case ..<0.85: return .orange
        default: return .red
        }
    }

    // MARK: - Meters

    private var meters: some View {
        VStack(spacing: 6) {
            meter(
                "Memory",
                value: reading.memory,
                detail: "\(StatsManager.bytes(reading.memoryUsedBytes)) of "
                    + StatsManager.bytes(reading.memoryTotalBytes),
                tint: reading.memory < 0.85 ? .cyan : .red
            )
            meter(
                "Disk",
                value: reading.disk,
                detail: "\(StatsManager.bytes(reading.diskUsedBytes)) of "
                    + StatsManager.bytes(reading.diskTotalBytes),
                tint: .white.opacity(0.55)
            )
        }
    }

    /// Name on the left, figures on the right, bar underneath spanning both.
    private func meter(_ title: String, value: Double, detail: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer(minLength: 0)
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.35))
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.07))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(3, proxy.size.width * value.clamped(to: 0...1)))
                        .animation(.smooth(duration: 0.4), value: value)
                }
            }
            .frame(height: 3)
        }
    }

    // MARK: - Network

    /// Rates on the outside, the shape of the traffic between them.
    private var network: some View {
        HStack(spacing: 8) {
            rate("arrow.down", StatsManager.rate(reading.networkDown), .cyan)

            MirroredChart(
                values: stats.networkHistory,
                ceiling: max(64_000, stats.networkPeak)
            )
            .frame(height: 20)
            .frame(maxWidth: .infinity)

            rate("arrow.up", StatsManager.rate(reading.networkUp), .orange)
        }
    }

    private func rate(_ symbol: String, _ value: String, _ tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(width: 62, alignment: .leading)
    }

    // MARK: - Footer

    /// The standing facts, in one quiet line.
    private var footer: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(thermalTint)
                .frame(width: 4, height: 4)
            Text(footerText)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.35))
                .monospacedDigit()
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var footerText: String {
        var parts = [reading.thermalLabel, "up \(StatsManager.uptime(reading.uptime))"]
        // Only when there is swap to report.
        if reading.swapUsed > 0 {
            parts.append("swap \(StatsManager.bytes(reading.swapUsed))")
        }
        return parts.joined(separator: " · ")
    }

    private var thermalTint: Color {
        switch reading.thermal {
        case .nominal: return .green.opacity(0.7)
        case .fair: return .yellow
        default: return .red
        }
    }
}

// MARK: - Charts

/// A filled curve rather than a row of bars.
private struct AreaChart: View {
    let values: [Double]
    let ceiling: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let points = self.points(in: proxy.size)

            ZStack(alignment: .bottomLeading) {
                if points.count > 1 {
                    // Filled body first, then the line over it.
                    path(points, closingIn: proxy.size)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.40), tint.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    path(points, closingIn: nil)
                        .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                        .shadow(color: tint.opacity(0.45), radius: 3, y: 1)
                } else {
                    Text("Measuring…")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1, ceiling > 0 else { return [] }
        let step = size.width / CGFloat(max(1, values.count - 1))
        // Half a line width of headroom at each end, for a pegged processor.
        let usable = size.height - 2
        return values.enumerated().map { index, value in
            let ratio = (value / ceiling).clamped(to: 0...1)
            return CGPoint(x: CGFloat(index) * step, y: 1 + usable * (1 - ratio))
        }
    }

    /// Smoothed through segment midpoints; a spline would overshoot the data.
    private func path(_ points: [CGPoint], closingIn size: CGSize?) -> Path {
        var path = Path()
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: first)

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let midpoint = CGPoint(
                x: (previous.x + current.x) / 2,
                y: (previous.y + current.y) / 2
            )
            path.addQuadCurve(to: midpoint, control: previous)
        }
        path.addLine(to: last)

        if let size {
            path.addLine(to: CGPoint(x: last.x, y: size.height))
            path.addLine(to: CGPoint(x: first.x, y: size.height))
            path.closeSubpath()
        }
        return path
    }
}

/// Traffic as a river seen side on: received below the centre line, sent above.
private struct MirroredChart: View {
    let values: [(down: Double, up: Double)]
    let ceiling: Double

    var body: some View {
        GeometryReader { proxy in
            let middle = proxy.size.height / 2
            let step = proxy.size.width / CGFloat(max(1, values.count - 1))

            ZStack {
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(height: 1)
                    .position(x: proxy.size.width / 2, y: middle)

                half(up: true, middle: middle, step: step)
                    .fill(
                        LinearGradient(
                            colors: [.orange.opacity(0.65), .orange.opacity(0.15)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                half(up: false, middle: middle, step: step)
                    .fill(
                        LinearGradient(
                            colors: [.cyan.opacity(0.15), .cyan.opacity(0.65)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
    }

    private func half(up: Bool, middle: CGFloat, step: CGFloat) -> Path {
        var path = Path()
        guard values.count > 1, ceiling > 0 else { return path }

        path.move(to: CGPoint(x: 0, y: middle))
        for (index, value) in values.enumerated() {
            let magnitude = (up ? value.up : value.down) / ceiling
            let height = CGFloat(magnitude.clamped(to: 0...1)) * middle
            path.addLine(to: CGPoint(x: CGFloat(index) * step, y: up ? middle - height : middle + height))
        }
        path.addLine(to: CGPoint(x: CGFloat(values.count - 1) * step, y: middle))
        path.closeSubpath()
        return path
    }
}
