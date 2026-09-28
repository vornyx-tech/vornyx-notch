//
//  IndicatorLights.swift
//  VornyxNotch
//
//  The camera, microphone, Focus and Caps Lock lights.
//

import Defaults
import SwiftUI

/// A row of small lights, shown only for what is actually on.
struct IndicatorLights: View {
    @ObservedObject private var monitor = IndicatorsManager.shared
    @ObservedObject private var preview = BannerPreview.shared

    /// Bigger in the open notch.
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
        .animation(.smooth(duration: 0.2), value: preview.focus?.on)
    }

    private struct Light {
        let symbol: String
        let tint: Color
        let help: String
    }

    /// Fixed order, so a light never moves as another comes and goes.
    private var lights: [Light] {
        let state = monitor.indicators
        var lights: [Light] = []

        if state.camera {
            lights.append(.init(symbol: "video.fill", tint: .green, help: "Camera in use"))
        }
        if state.microphone {
            lights.append(.init(symbol: "mic.fill", tint: .orange, help: "Microphone in use"))
        }
        if state.focus || preview.focus?.on == true {
            // The mode's own symbol and colour when it is known - a briefcase
            // for Work - so the light says which Focus, not only that one is on.
            let mode = preview.focus?.mode ?? monitor.focusMode ?? .other
            lights.append(.init(symbol: mode.symbol, tint: mode.tint, help: "\(mode.name) is on"))
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
    /// A state that is simply on, such as Caps Lock: a steady outline.
    case steady(Color)
    /// Music is playing: the cover's own colour, barely there.
    case ambient(Color)
}

/// The notch's edge as a status light: a breathing halo while the camera or
/// microphone is on, a line that fills as a transfer or the timer runs, and a
/// short colour for the battery. One at a time, in that order.
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
    @Default(.showCapsLockIndicator) private var capsLockIndicator

    /// True for a few seconds after the battery fills; the level then sits at
    /// 100 with nothing to mark the moment.
    @State private var justCharged = false
    @State private var chargedReset: Task<Void, Never>?
    /// The last light shown, kept to fade out on.
    @State private var lastSignal: EdgeSignal?

    /// How far past the notch the widest glow shows: a shadow fades out over
    /// about three times its radius, and the widest here is 16.
    private static let glowReach: CGFloat = 48

    let shape: NotchShape
    /// The ambient colour is for the closed notch only.
    let isOpen: Bool
    /// Live activities paused by their shortcut: no light either.
    var paused: Bool = false

    var body: some View {
        ZStack {
            // Kept in place and faded, rather than inserted and removed: a
            // removed view is frozen at its last size, so the light going out
            // as a banner grew the notch - Caps Lock off - stayed the old
            // notch's size, and could be left there as a stray outline.
            if let shown = signal ?? lastSignal {
                Group {
                    switch shown {
                    case .recording(let tint):
                        breathing(halo(tint), duration: 1.1)
                    case .attention(let tint):
                        breathing(halo(tint), duration: 1.8)
                    case .steady(let tint):
                        halo(tint).opacity(0.85)
                    case .progress(let tint, let fraction):
                        progress(tint, fraction)
                    case .ambient(let tint):
                        breathing(ambient(tint), duration: 3.4, from: 0.7)
                    }
                }
                // Fade out the top edge, and keep the mask wider than the notch
                // so it does not clip the glow the shadows throw.
                .mask {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: 18)
                        Color.black
                    }
                    .padding(.horizontal, -Self.glowReach)
                    .padding(.bottom, -Self.glowReach)
                }
                .opacity(signal == nil ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
        .animation(.smooth(duration: 0.3), value: signal)
        .onChange(of: signal, initial: true) { _, next in
            if let next {
                lastSignal = next
                return
            }
            // Gone once it has faded, so a breathing light does not go on
            // animating unseen.
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                if signal == nil { lastSignal = nil }
            }
        }
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
        if paused { return nil }
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
                return .progress(CountdownManager.color, countdown.remaining / countdown.total)
            }
        }

        if edgeBattery {
            if justCharged { return .attention(.green) }
            if battery.levelBattery <= 20, !battery.isPluggedIn { return .attention(.red) }
        }

        // Caps Lock has no other tell while the notch is closed: the lights in
        // the header only exist once it is open.
        if Defaults[.showCapsLockIndicator], monitor.indicators.capsLock {
            return .steady(Color.effectiveAccent)
        }

        // Open as well as closed: the glow rides the notch's own outline, so it
        // grows and shrinks with it rather than fading out of the way.
        if edgeAmbient, musicManager.isPlaying {
            // Lifted, or a dark cover leaves nothing to see.
            return .ambient(
                Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.65))
        }

        return nil
    }

    private func halo(_ tint: Color) -> some View {
        onEdge(
            shape
                .stroke(tint, lineWidth: 1.5)
                .shadow(color: tint.opacity(0.9), radius: 5)
                .shadow(color: tint.opacity(0.45), radius: 14))
    }

    /// The light as part of the notch's own edge: the same shape, in the same
    /// frame, on the same spring as the black - drawn in one pass on the GPU.
    ///
    /// Soft shadows on a path redrawn on the CPU every frame were what made
    /// the light crawl behind the notch as it grew or shrank. The padding
    /// gives the glow room inside the flattened layer, which would clip it at
    /// the notch's own bounds, and is taken back after.
    private func onEdge<Content: View>(_ light: Content) -> some View {
        light
            .padding(Self.glowReach)
            .drawingGroup()
            .padding(-Self.glowReach)
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

    /// The cover's colour on the edge, much weaker than a signal.
    private func ambient(_ tint: Color) -> some View {
        onEdge(
            shape
                .stroke(tint.opacity(0.5), lineWidth: isOpen ? 1.4 : 1)
                .shadow(color: tint.opacity(0.45), radius: 6)
                .shadow(color: tint.opacity(0.25), radius: 16))
    }

    /// The outline drawn as far as `fraction`, from the top left down and round.
    private func progress(_ tint: Color, _ fraction: Double) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            // `NotchShape` closes across the top, which the hardware notch
            // hides, so a full sweep stops just before that run.
            let visible = (2 * size.height + size.width)
                / max(1, 2 * size.height + 2 * size.width)

            onEdge(
                shape
                    .trim(from: 0, to: visible * max(0, min(1, fraction)))
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .shadow(color: tint.opacity(0.9), radius: 5)
                    .shadow(color: tint.opacity(0.45), radius: 12)
                    .animation(.smooth(duration: 0.25), value: fraction))
        }
    }
}

/// Said under the closed notch when the live activities are paused or back.
struct LivePauseSneakPeek: View {
    let isPaused: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: isPaused ? "eye.slash" : "eye")
                .foregroundStyle(isPaused ? .gray : Color.effectiveAccent)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 18)

            Text(isPaused ? "Notch live off" : "Notch live on")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.gray)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.bottom, 10)
    }
}

/// Said under the closed notch when Caps Lock goes on or off.
struct CapsLockSneakPeek: View {
    let isOn: Bool

    @State private var arrivals = 0

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: isOn ? "capslock.fill" : "capslock")
                .foregroundStyle(isOn ? Color.effectiveAccent : .gray)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: arrivals)
                .frame(width: 18)

            Text(isOn ? "Caps Lock on" : "Caps Lock off")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.gray)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.bottom, 10)
        .onAppear { arrivals += 1 }
        .onChange(of: isOn) { _, _ in arrivals += 1 }
    }
}
