//
//  AirPodsView.swift
//  VornyxNotch
//
//  AirPods battery, in the closed notch and beside the player.
//

import Defaults
import SwiftUI

// MARK: - Shared pieces

/// One level: a glyph, a bar and a number.
///
/// The bar rather than a ring, because these sit in a row and bars of the same
/// length are far easier to compare down a line than arcs are.
private struct LevelPill: View {
    let symbol: String
    let level: Int
    let charging: Bool
    var barWidth: CGFloat = 26

    /// Green is not used: a full battery is not a state worth colouring, and
    /// reserving colour for trouble means the colour actually means something.
    private var tint: Color {
        if charging { return .green }
        if level <= 10 { return .red }
        if level <= 20 { return .orange }
        return .white.opacity(0.85)
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 11)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.12))
                Capsule()
                    .fill(tint)
                    .frame(width: max(3, barWidth * CGFloat(level) / 100))
            }
            .frame(width: barWidth, height: 4)

            Text("\(level)")
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 20, alignment: .trailing)
        }
    }
}

/// The rows a given pair has to show: two ears and a case, or one level.
private func levelRows(_ device: AirPodsBattery) -> [(String, Int, Bool)] {
    var rows: [(String, Int, Bool)] = []
    if device.hasEars {
        if let left = device.left { rows.append(("airpod.left", left, device.leftCharging)) }
        if let right = device.right { rows.append(("airpod.right", right, device.rightCharging)) }
        if let caseLevel = device.caseLevel {
            rows.append(("airpodscase", caseLevel, device.caseCharging))
        }
    } else if let single = device.single {
        rows.append(("airpodsmax", single, device.singleCharging))
    }
    return rows
}

// MARK: - Closed notch

/// The banner shown when a pair connects: name on the left of the notch
/// cut-out, levels on the right, the same shape the battery banner uses.
struct AirPodsLiveActivity: View {
    @EnvironmentObject var vm: VornyxViewModel
    @ObservedObject private var pods = AirPodsManager.shared

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: glyph)
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

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if let device = pods.device {
                    ForEach(levelRows(device), id: \.0) { row in
                        LevelPill(symbol: row.0, level: row.1, charging: row.2, barWidth: 18)
                    }
                }
            }
            .frame(width: 150, alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    private var glyph: String {
        guard let device = pods.device else { return "airpods.gen3" }
        return device.hasEars ? "airpods.gen3" : "airpodsmax"
    }
}

// MARK: - Home page

/// The levels beside the player, for as long as a pair is connected.
///
/// Opt-in from Settings, because it widens the home notch - see
/// `airPodsWidgetWidth`. When nothing is connected it says so rather than
/// vanishing: a panel that appears and disappears would resize the notch under
/// the pointer every time you take an ear out.
struct AirPodsWidgetView: View {
    @ObservedObject private var pods = AirPodsManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header

            if let device = pods.device {
                ForEach(levelRows(device), id: \.0) { row in
                    LevelPill(symbol: row.0, level: row.1, charging: row.2)
                }
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                Text("Not connected")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: innerPanelCornerRadius, style: .continuous)
                .fill(.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: innerPanelCornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: pods.device?.hasEars == false ? "airpodsmax" : "airpods.gen3")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(pods.device == nil ? .white.opacity(0.3) : .white.opacity(0.75))
            Text(pods.device?.name ?? "AirPods")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(pods.device == nil ? .white.opacity(0.3) : .white.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
    }
}
