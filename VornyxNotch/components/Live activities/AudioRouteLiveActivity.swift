//
//  AudioRouteLiveActivity.swift
//  VornyxNotch
//
//  Sound has moved somewhere else - said in the closed notch.
//

import Defaults
import SwiftUI

/// The banner shown when the default output changes.
///
/// Two shapes, the same two the music banner offers and chosen by the same
/// kind of setting. `standard` is a pair of squares hugging the cut-out - the
/// device on one side, sound on the other - and says everything a glance
/// needs. `inline` spreads out and names the device, for when the glyph alone
/// is not enough to tell two pairs apart.
///
/// The glyph animates rather than simply appearing. A route change is not a
/// state you read, it is a thing that just happened - the ring leaving the icon
/// and the bars starting to move say "sound is going here now" faster than any
/// wording would, and they say it while your eye is still travelling up.
struct AudioRouteLiveActivity: View {
    @EnvironmentObject var vm: VornyxViewModel
    @ObservedObject private var audio = AudioDeviceManager.shared
    @Default(.audioRouteSneakPeekStyle) private var style

    /// Flipped once on appear, which is what every entrance animation here
    /// hangs off. Replayed on a change of device below, so switching outputs
    /// twice in a row plays the animation again instead of leaving the second
    /// one static.
    @State private var landed = false

    var body: some View {
        Group {
            switch style {
            case .standard: compact
            case .inline: wide
            }
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .onAppear { play() }
        // The banner is not rebuilt when one output replaces another inside its
        // three seconds, so the change of device is what restarts it.
        .onChange(of: audio.currentID) { _, _ in
            landed = false
            play()
        }
    }

    // MARK: - Shapes

    /// Square, square, the cut-out between them: the music banner's silhouette,
    /// so a device change and a track change sit at the same weight.
    private var compact: some View {
        HStack(spacing: 0) {
            RoutedGlyph(symbol: symbol, landed: landed, size: side * 0.62)
                .frame(width: side, height: side)

            Rectangle()
                .fill(.black)
                // The music banner's own spacer, to the point: the two have to
                // line up against the same physical cut-out.
                .frame(width: vm.closedNotchSize.width + -cornerRadiusInsets.closed.top)

            EqualiserBars(height: side * 0.7)
                .frame(width: side, height: side)
                .opacity(landed ? 1 : 0)
        }
    }

    /// Name on the left of the cut-out, sound on the right - the shape the
    /// battery, AirPods and timer banners share.
    private var wide: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                RoutedGlyph(symbol: symbol, landed: landed, size: 13)
                    .frame(width: 20, height: 20)

                Text(name)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .opacity(landed ? 1 : 0)
                    .offset(x: landed ? 0 : -6)
            }

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 10)

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                EqualiserBars(height: 16)
                    .opacity(landed ? 1 : 0)
            }
            .frame(width: 110, alignment: .trailing)
        }
    }

    /// The album art's own side length, so the squares match the music banner's
    /// to the point.
    private var side: CGFloat { max(0, vm.effectiveClosedNotchHeight - 12) }

    private func play() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.7).delay(0.04)) {
            landed = true
        }
    }

    private var symbol: String {
        audio.current?.symbol ?? "speaker.fill"
    }

    private var name: String {
        audio.current?.name ?? String(localized: "Sound output")
    }
}

// MARK: - Pieces

/// The device glyph, arriving with a ring going out from behind it.
private struct RoutedGlyph: View {
    let symbol: String
    let landed: Bool
    let size: CGFloat

    /// Driven separately from `landed`: the ring is a one-shot that has to run
    /// past the icon's spring, so it gets its own longer, flatter curve.
    @State private var ringOut = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.effectiveAccent.opacity(ringOut ? 0 : 0.45), lineWidth: 1.5)
                .frame(width: size * 1.4, height: size * 1.4)
                .scaleEffect(ringOut ? 2.1 : 0.6)

            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .scaleEffect(landed ? 1 : 0.55)
                .opacity(landed ? 1 : 0)
        }
        .onAppear(perform: pulse)
        .onChange(of: symbol) { _, _ in pulse() }
    }

    private func pulse() {
        ringOut = false
        withAnimation(.easeOut(duration: 0.85).delay(0.06)) {
            ringOut = true
        }
    }
}

/// Four bars keeping time, for as long as the banner is up.
///
/// Each bar gets its own duration rather than a shared one with offsets: equal
/// durations drift back into step within a second and the row starts pumping as
/// a block, which reads as a progress bar rather than as sound.
private struct EqualiserBars: View {
    let height: CGFloat

    @State private var moving = false

    /// Fractions of the given height, so the row keeps its shape whichever
    /// banner it is standing in.
    private let peaks: [CGFloat] = [0.45, 0.85, 0.58, 1.0]
    private let periods: [Double] = [0.42, 0.55, 0.47, 0.62]

    var body: some View {
        HStack(alignment: .center, spacing: max(2, height * 0.16)) {
            ForEach(peaks.indices, id: \.self) { index in
                Capsule()
                    .fill(Color.effectiveAccent)
                    .frame(
                        width: max(2, height * 0.16),
                        height: moving ? height * peaks[index] : max(2, height * 0.16)
                    )
                    .animation(
                        .easeInOut(duration: periods[index]).repeatForever(autoreverses: true),
                        value: moving
                    )
            }
        }
        .frame(height: height)
        .onAppear { moving = true }
    }
}
