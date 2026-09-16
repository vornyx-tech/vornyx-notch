//
//  IndicatorLights.swift
//  VornyxNotch
//
//  The camera, microphone, Focus and Caps Lock lights.
//

import Defaults
import SwiftUI

/// A row of small lights, shown only for what is actually on.
///
/// Deliberately dots rather than a banner: these are states you want to be able
/// to check without being interrupted, and something that takes over the notch
/// every time you unmute would be intolerable. Nothing on means nothing drawn.
struct IndicatorLights: View {
    @ObservedObject private var monitor = IndicatorsManager.shared

    /// Bigger in the open notch, where there is room and the header is calm.
    var size: CGFloat = 7

    var body: some View {
        HStack(spacing: 4) {
            ForEach(lights, id: \.symbol) { light in
                Image(systemName: light.symbol)
                    .font(.system(size: size, weight: .black))
                    .foregroundStyle(light.tint)
                    .transition(.scale.combined(with: .opacity))
                    .help(light.help)
            }
        }
        .animation(.smooth(duration: 0.2), value: monitor.indicators)
    }

    private struct Light {
        let symbol: String
        let tint: Color
        let help: String
    }

    /// Order is fixed rather than by arrival, so a light never moves under the
    /// pointer as another one comes and goes.
    private var lights: [Light] {
        let state = monitor.indicators
        var lights: [Light] = []

        if state.camera {
            lights.append(.init(symbol: "video.fill", tint: .green, help: "Camera in use"))
        }
        if state.microphone {
            lights.append(.init(symbol: "mic.fill", tint: .orange, help: "Microphone in use"))
        }
        if state.focus {
            lights.append(.init(symbol: "moon.fill", tint: .purple, help: "Focus is on"))
        }
        if state.capsLock {
            lights.append(.init(
                symbol: "capslock.fill",
                tint: Color.effectiveAccent,
                help: "Caps Lock is on"
            ))
        }
        return lights
    }
}

/// What the notch's own edge is saying, if anything.
private enum EdgeSignal: Equatable {
    /// The camera or the microphone is on: the whole outline, breathing.
    case recording(Color)
    /// Something is running: the outline draws itself as it goes.
    case progress(Color, Double)
    /// One thing worth noticing: charged, or nearly empty.
    case attention(Color)
    /// Nothing is happening and music is playing: the cover's own colour,
    /// barely there.
    case ambient(Color)
}

/// The notch's edge as a status light.
///
/// `IndicatorLights` says some of this in the header, but only once the notch
/// is open and only if you look at it. This is for catching out of the corner
/// of your eye, so it traces the notch's own outline: a breathing halo while
/// the camera or microphone is on, a line that fills as a transfer or the
/// timer runs, and a short colour for the battery.
///
/// One thing at a time, in that order: privacy first, then what is running,
/// then the battery.
struct NotchEdgeLight: View {
    @ObservedObject private var monitor = IndicatorsManager.shared
    @ObservedObject private var localSend = LocalSendManager.shared
    @ObservedObject private var countdown = CountdownManager.shared
    @ObservedObject private var battery = BatteryStatusViewModel.shared
    @ObservedObject private var musicManager = MusicManager.shared

    @Default(.recordingGlow) private var recordingGlow
    @Default(.showPrivacyIndicators) private var privacyIndicators
    @Default(.notchEdgeProgress) private var edgeProgress
    @Default(.notchEdgeBattery) private var edgeBattery
    @Default(.notchEdgeAmbient) private var edgeAmbient

    /// True for a few seconds after the battery fills, since "charged" is a
    /// moment rather than a state - the level simply sits at 100 afterwards.
    @State private var justCharged = false
    @State private var chargedReset: Task<Void, Never>?

    let shape: NotchShape
    /// The ambient colour is for the closed notch only: open, the glass is
    /// already carrying the artwork, and a rim light over it is one rendering
    /// layer too many.
    let isOpen: Bool

    var body: some View {
        ZStack {
            if let signal {
                Group {
                    switch signal {
                    case .recording(let tint):
                        breathing(halo(tint), duration: 1.1)
                    case .attention(let tint):
                        // Slower: nothing here is urgent enough to flicker at you.
                        breathing(halo(tint), duration: 1.8)
                    case .progress(let tint, let fraction):
                        progress(tint, fraction)
                    case .ambient(let tint):
                        // Slow and shallow: it should read as the notch being
                        // lit from inside, not as something asking for you.
                        breathing(ambient(tint), duration: 3.4, from: 0.7)
                    }
                }
                // Nothing across the top: that edge sits under the hardware
                // notch, and on a screen without one it drew a bright wire
                // along the screen's top edge. Faded in rather than cut off, or
                // the mask leaves a seam of its own for the shadows to light up.
                //
                // Inside the branch on purpose: a mask is a rendering layer of
                // its own, and with nothing lit there is nothing to mask - the
                // overlay then adds no layer over the notch's glass at all.
                .mask {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: 18)
                        Color.black
                    }
                }
                .transition(.opacity)
            }
        }
        // Nothing here is touchable: the notch's own hit area has to stay whole.
        .allowsHitTesting(false)
        .animation(.smooth(duration: 0.3), value: signal)
        .onChange(of: battery.levelBattery) { previous, level in
            guard edgeBattery, level >= 100, previous < 100, battery.isPluggedIn else { return }
            justCharged = true
            chargedReset?.cancel()
            chargedReset = Task {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                justCharged = false
            }
        }
    }

    private var signal: EdgeSignal? {
        // The colours macOS itself uses for the camera and the microphone.
        if recordingGlow, privacyIndicators {
            if monitor.indicators.camera { return .recording(.green) }
            if monitor.indicators.microphone { return .recording(.orange) }
        }

        if edgeProgress {
            if let outgoing = localSend.outgoing, !outgoing.isOver {
                return .progress(.blue, outgoing.fraction)
            }
            if let incoming = localSend.incoming, incoming.phase == .receiving {
                return .progress(.blue, incoming.fraction)
            }
            if case .running = countdown.state, countdown.total > 0 {
                // Draining, not filling: the timer shows what is left.
                return .progress(.orange, countdown.remaining / countdown.total)
            }
        }

        if edgeBattery {
            if justCharged { return .attention(.green) }
            // Deliberately silent while charging - only full, or nearly empty.
            if battery.levelBattery <= 20, !battery.isPluggedIn { return .attention(.red) }
        }

        if edgeAmbient, !isOpen, musicManager.isPlaying {
            // Lifted, or a dark cover would leave nothing to see at all.
            return .ambient(
                Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.65))
        }

        return nil
    }

    private func halo(_ tint: Color) -> some View {
        shape
            .stroke(tint, lineWidth: 1.5)
            // Two shadows: a tight one for the edge itself, a wide one for the
            // light it throws onto the screen around it.
            .shadow(color: tint.opacity(0.9), radius: 5)
            .shadow(color: tint.opacity(0.45), radius: 14)
    }

    private func breathing<Content: View>(
        _ content: Content, duration: Double, from low: Double = 0.45
    ) -> some View {
        content.phaseAnimator([low, 1.0]) { halo, phase in
            halo.opacity(phase)
        } animation: { _ in
            .easeInOut(duration: duration)
        }
    }

    /// The cover's colour on the edge: much weaker than a signal, because it is
    /// not one - it is only there while something plays.
    private func ambient(_ tint: Color) -> some View {
        shape
            .stroke(tint.opacity(0.5), lineWidth: 1)
            .shadow(color: tint.opacity(0.45), radius: 6)
            .shadow(color: tint.opacity(0.25), radius: 16)
    }

    /// The outline drawn as far as `fraction`, from the top left down and round.
    private func progress(_ tint: Color, _ fraction: Double) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            // `NotchShape` starts at the top-left corner, runs down the left
            // side, along the bottom and up the right, then closes across the
            // top - and that closing run is the part the hardware notch hides,
            // so a full sweep stops just before it.
            let visible = (2 * size.height + size.width)
                / max(1, 2 * size.height + 2 * size.width)

            shape
                .trim(from: 0, to: visible * max(0, min(1, fraction)))
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .shadow(color: tint.opacity(0.9), radius: 5)
                .shadow(color: tint.opacity(0.45), radius: 12)
                .animation(.smooth(duration: 0.25), value: fraction)
        }
    }
}
