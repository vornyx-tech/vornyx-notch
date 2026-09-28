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
            // One outline, always there, that only changes colour, weight and
            // how far round it goes - never a view inserted or removed, or
            // swapped for another. A removed view is frozen at its last size
            // and an inserted one starts at its final size: the light going
            // out as a banner grew the notch stayed the old notch's size, and
            // one coming on as the notch opened was the open notch's size
            // before the black was. With nothing to show it is clear.
            lightLook(EdgeLook(signal ?? lastSignal, isOpen: isOpen))
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

    private func lightLook(_ look: EdgeLook) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            // `NotchShape` closes across the top, which the hardware notch
            // hides, so a full sweep stops just before that run.
            let visible = (2 * size.height + size.width)
                / max(1, 2 * size.height + 2 * size.width)
            let end: CGFloat = look.fraction.map { visible * CGFloat(max(0, min(1, $0))) } ?? 1

            onEdge(
                shape
                    .trim(from: 0, to: end)
                    .stroke(
                        look.tint.opacity(look.strokeOpacity),
                        style: StrokeStyle(lineWidth: look.lineWidth, lineCap: .round))
                    .shadow(color: look.tint.opacity(look.nearGlow), radius: look.nearRadius)
                    .shadow(color: look.tint.opacity(look.farGlow), radius: look.farRadius))
        }
        // Breathing only for the signals that breathe; one phase is still.
        .phaseAnimator(look.breath.map { [$0.low, 1.0] } ?? [1.0]) { (light, phase: Double) in
            light.opacity(phase)
        } animation: { _ in
            .easeInOut(duration: look.breath?.duration ?? 1)
        }
    }
}

/// What the edge light looks like for a signal, as numbers one outline can
/// move between.
private struct EdgeLook: Equatable {
    var tint: Color = .clear
    var lineWidth: CGFloat = 1.5
    var strokeOpacity: Double = 1
    var nearGlow: Double = 0.9
    var nearRadius: CGFloat = 5
    var farGlow: Double = 0.45
    var farRadius: CGFloat = 14
    /// How far round the outline goes; nil for all the way.
    var fraction: Double?
    var breath: Breath?

    struct Breath: Equatable {
        let duration: Double
        let low: Double
    }

    init(_ signal: EdgeSignal?, isOpen: Bool) {
        switch signal {
        case nil:
            break
        case .recording(let tint):
            self.tint = tint
            breath = Breath(duration: 1.1, low: 0.45)
        case .attention(let tint):
            self.tint = tint
            breath = Breath(duration: 1.8, low: 0.45)
        case .steady(let tint):
            self.tint = tint
            strokeOpacity = 0.85
            nearGlow = 0.9 * 0.85
            farGlow = 0.45 * 0.85
        case .progress(let tint, let fraction):
            self.tint = tint
            lineWidth = 2
            farRadius = 12
            self.fraction = fraction
        case .ambient(let tint):
            self.tint = tint
            lineWidth = isOpen ? 1.4 : 1
            strokeOpacity = 0.5
            nearGlow = 0.45
            nearRadius = 6
            farGlow = 0.25
            farRadius = 16
            breath = Breath(duration: 3.4, low: 0.7)
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
