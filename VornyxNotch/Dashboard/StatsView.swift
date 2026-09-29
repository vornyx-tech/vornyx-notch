//
//  StatsView.swift
//  VornyxNotch
//

import SwiftUI

/// Three rings for the processor, memory and disk; under them, the
/// processor's recent history and the network, each in a tile of its own.
struct StatsView: View {
    @ObservedObject private var stats = StatsManager.shared

    var body: some View {
        // Sized to fit the notch: this column gets about 190pt of the
        // dashboard's 252.
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                gauge(
                    "Processor", value: reading.cpu, tint: cpuTint,
                    detail: "\(reading.cores) cores")
                gauge(
                    "Memory", value: reading.memory,
                    tint: reading.memory < 0.85 ? .cyan : .red,
                    detail: "\(StatsManager.bytes(reading.memoryUsedBytes)) of \(StatsManager.bytes(reading.memoryTotalBytes))")
                gauge(
                    "Disk", value: reading.disk,
                    tint: reading.disk < 0.9 ? .purple : .red,
                    detail: "\(StatsManager.bytes(reading.diskUsedBytes)) of \(StatsManager.bytes(reading.diskTotalBytes))")
            }
            // Their own height; the tiles below take what is left.
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                historyTile
                networkTile
            }

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { stats.addWatcher() }
        .onDisappear { stats.removeWatcher() }
    }

    private var reading: MachineStats { stats.stats }

    private var cpuTint: Color {
        switch reading.cpu {
        case ..<0.6: return Color.effectiveAccent
        case ..<0.85: return .orange
        default: return .red
        }
    }

    // MARK: - Tiles

    private func tile<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.05))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.06), lineWidth: 1)
            }
    }

    /// A ring filled to the reading, the percentage in it, name and figures
    /// under it.
    private func gauge(_ title: String, value: Double, tint: Color, detail: String) -> some View {
        tile {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.08), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: value.clamped(to: 0...1))
                        .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: tint.opacity(0.4), radius: 4)
                        .animation(.smooth(duration: 0.5), value: value)
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("\(Int((value * 100).rounded()))")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(.smooth(duration: 0.3), value: Int((value * 100).rounded()))
                        Text("%")
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)

                VStack(spacing: 1) {
                    Text(title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(detail)
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.4))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
    }

    /// The processor over the last while, and its load.
    private var historyTile: some View {
        tile {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("Activity")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer(minLength: 0)
                    Text("load \(String(format: "%.2f", reading.loadAverage))")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.4))
                        .monospacedDigit()
                }
                AreaChart(values: stats.cpuHistory, ceiling: 1, tint: cpuTint)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    /// Down and up, their rates beside the shape of the traffic.
    private var networkTile: some View {
        tile {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    rate("arrow.down", StatsManager.rate(reading.networkDown), .cyan)
                    rate("arrow.up", StatsManager.rate(reading.networkUp), .orange)
                    Spacer(minLength: 0)
                }
                MirroredChart(
                    values: stats.networkHistory,
                    ceiling: max(64_000, stats.networkPeak)
                )
                .frame(maxHeight: .infinity)
            }
        }
    }

    private func rate(_ symbol: String, _ value: String, _ tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 7, weight: .black))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
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
        .padding(.horizontal, 4)
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
