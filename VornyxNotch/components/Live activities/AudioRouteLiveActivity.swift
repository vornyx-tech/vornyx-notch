//
//  AudioRouteLiveActivity.swift
//  VornyxNotch
//
//  Sound has moved somewhere else, said under the closed notch.
//

import SwiftUI

/// The sneak peek shown when the default output changes: the device's glyph,
/// its name, and a few bars of sound going to it.
struct AudioRouteSneakPeek: View {
    @ObservedObject private var audio = AudioDeviceManager.shared

    /// Bumped on appear and on every change of device, to play the glyph's
    /// bounce.
    @State private var arrivals = 0

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: arrivals)
                .frame(width: 18)

            GeometryReader { geo in
                MarqueeText(
                    .constant(name), textColor: .gray, minDuration: 1, frameWidth: geo.size.width)
            }

            EqualiserBars(height: 11)
        }
        .foregroundStyle(.gray)
        .padding(.bottom, 10)
        .onAppear { arrivals += 1 }
        .onChange(of: audio.currentID) { _, _ in arrivals += 1 }
    }

    private var symbol: String {
        audio.current.map(audio.symbol(for:)) ?? "speaker.wave.2.fill"
    }

    private var name: String {
        audio.current?.name ?? String(localized: "Sound output")
    }
}

// MARK: - Pieces

/// Four bars keeping time, for as long as the banner is up. Each bar has its
/// own duration; equal ones drift into step and the row pumps as a block.
private struct EqualiserBars: View {
    let height: CGFloat

    @State private var moving = false

    /// Fractions of the given height.
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
