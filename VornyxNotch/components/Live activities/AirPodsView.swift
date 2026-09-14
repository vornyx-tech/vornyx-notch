//
//  AirPodsView.swift
//  VornyxNotch
//
//  AirPods battery, in the closed notch and beside the player.
//

import Defaults
import SwiftUI

// MARK: - Shared pieces

/// A level's colour. Kept for trouble: a full battery is not a state worth
/// colouring, so white means fine and colour means look.
private func levelTint(_ level: Int, charging: Bool) -> Color {
    if charging { return .green }
    if level <= 10 { return .red }
    if level <= 20 { return .orange }
    return .white
}

/// One part of a pair with a level of its own: an ear, the case, or the whole
/// set of over-ears.
private struct PodPart: Identifiable {
    let id: String
    let symbol: String?
    let label: String
    let level: Int
    let charging: Bool
}

/// The parts a given pair has to show: two ears and a case, or one level.
private func parts(of device: AirPodsBattery) -> [PodPart] {
    let model = device.model
    var parts: [PodPart] = []
    if device.hasEars {
        if let left = device.left {
            parts.append(PodPart(id: "left", symbol: model.leftSymbol, label: "L",
                                 level: left, charging: device.leftCharging))
        }
        if let right = device.right {
            parts.append(PodPart(id: "right", symbol: model.rightSymbol, label: "R",
                                 level: right, charging: device.rightCharging))
        }
        if let caseLevel = device.caseLevel {
            parts.append(PodPart(id: "case", symbol: model.caseSymbol, label: "C",
                                 level: caseLevel, charging: device.caseCharging))
        }
    } else if let single = device.single {
        parts.append(PodPart(id: "single", symbol: model.symbol, label: "",
                             level: single, charging: device.singleCharging))
    }
    return parts
}

/// A level as a ring with the part drawn inside it.
///
/// Rings rather than bars, the way the Batteries widget on an iPhone shows the
/// same numbers - which is what makes this read as "my AirPods" at a glance
/// instead of as a stack of progress bars.
private struct LevelRing: View {
    let part: PodPart
    let diameter: CGFloat

    var body: some View {
        let tint = levelTint(part.level, charging: part.charging)
        let lineWidth = max(2.5, diameter * 0.1)

        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: CGFloat(part.level) / 100)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth(duration: 0.6), value: part.level)

                if let symbol = part.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: diameter * 0.36, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                } else {
                    Text(part.label)
                        .font(.system(size: diameter * 0.3, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .frame(width: diameter, height: diameter)

            Text("\(part.level)%")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint == .white ? Color.white.opacity(0.75) : tint)
                .contentTransition(.numericText(value: Double(part.level)))
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// A ring small enough for the closed notch, with its number beside it.
private struct CompactLevel: View {
    let part: PodPart

    var body: some View {
        let tint = levelTint(part.level, charging: part.charging)

        HStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.15), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: CGFloat(part.level) / 100)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 12, height: 12)

            Text("\(part.level)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Closed notch

/// The banner shown when a pair connects: the pair and its name on the left of
/// the cut-out, levels on the right - the shape the battery banner uses.
struct AirPodsLiveActivity: View {
    @EnvironmentObject var vm: VornyxViewModel
    @ObservedObject private var pods = AirPodsManager.shared

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: pods.device?.model.symbol ?? "airpods")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                Text(pods.device?.name ?? "AirPods")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 10)

            HStack(spacing: 9) {
                Spacer(minLength: 0)
                if let device = pods.device {
                    ForEach(parts(of: device)) { part in
                        CompactLevel(part: part)
                    }
                }
            }
            .frame(width: 150, alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}

// MARK: - Home page

/// The pair beside the player, while one is connected.
///
/// Appears and goes with the connection, and the home page makes room for it
/// on exactly the same condition - see `homePageWidth(showingAirPods:)`. The
/// cost is the notch widening when a pair connects, which happens once per
/// connection: taking one ear out keeps the pair connected, so it does not
/// flicker with every earbud.
struct AirPodsWidgetView: View {
    @ObservedObject private var pods = AirPodsManager.shared

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: innerPanelCornerRadius, style: .continuous)

        VStack(spacing: 12) {
            if let device = pods.device {
                let pieces = parts(of: device)

                VStack(spacing: 4) {
                    Image(systemName: device.model.symbol)
                        .font(.system(size: 26, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                        .frame(height: 30)
                    Text(device.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                HStack(alignment: .top, spacing: 6) {
                    ForEach(pieces) { part in
                        LevelRing(part: part, diameter: Self.ringDiameter(for: pieces.count))
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            shape
                .fill(.white.opacity(0.05))
                .overlay(shape.strokeBorder(.white.opacity(0.06), lineWidth: 1))
        )
        .animation(.smooth(duration: 0.3), value: pods.device?.caseLevel == nil)
    }

    /// Three rings have to share the panel's width; fewer get to be bigger.
    private static func ringDiameter(for count: Int) -> CGFloat {
        switch count {
        case ...1: return 42
        case 2: return 34
        default: return 28
        }
    }
}
