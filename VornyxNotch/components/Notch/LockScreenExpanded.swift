//
//  LockScreenExpanded.swift
//  VornyxNotch
//
//  The lock screen's music: a card above the password field, and - with the
//  cover tapped - the whole screen given over to it, cover and lyrics large.
//
//  Ported from DynamicNotch by Evgeniy Petrukovich (GPL-3.0),
//  https://github.com/jackson-storm/dynamicnotch - LockScreenNowPlayingPanelView,
//  LockScreenNowPlayingView, LockScreenLyricsView, LockScreenClockView,
//  LockScreenWidgetSurface, PlayerProgressBar and PlayerControlButton, with
//  their sizes and placement. The look is ours: the stacked clock, the moving
//  background, the cover's colour lighting the cover, the bar and the lyrics,
//  and Liquid Glass on the card.
//

import AppKit
import CoreImage
import Defaults
import SwiftUI

/// The large layout behind the card: background, clock, cover and lyrics,
/// placed from the screen's centre the way DynamicNotch places them. Only
/// drawn - its window lets every click through to the lock screen.
struct LockScreenBackdropView: View {
    @ObservedObject private var music = MusicManager.shared

    static let panelSize = CGSize(width: 340, height: 180)
    static let expandedPanelHeight: CGFloat = panelSize.height - 20
    private static let artworkSize: CGFloat = 500
    private static let artworkSpacing: CGFloat = 90
    private static let lyricsWidth: CGFloat = 520
    private static let lyricsSpacing: CGFloat = 90
    static let panelCenterYOffset: CGFloat = (panelSize.height / 2) + 80

    /// Where the card's centre sits below the screen's, compact or expanded.
    static func cardOffset(expanded: Bool, screenHeight: CGFloat) -> CGFloat {
        expanded ? screenHeight / 2 - 180 : panelCenterYOffset
    }

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let showsLyrics = Defaults[.enableLyrics]
            let cover = LockScreenPalette.cover(music.avgColor)

            ZStack {
                LockScreenArtworkBackground(artwork: music.albumArt, tint: cover)
                    .ignoresSafeArea()

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    LockScreenClock(date: context.date)
                }
                .offset(y: -height / 2 + 120)

                Image(nsImage: music.albumArt)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Self.artworkSize, height: Self.artworkSize)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    // Lit by its own colour, not a black drop shadow.
                    .shadow(color: cover.opacity(0.55), radius: 40, x: 0, y: 18)
                    .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 8)
                    .offset(x: showsLyrics ? -((Self.lyricsWidth + Self.lyricsSpacing) / 2) : 0, y: -42)

                if showsLyrics {
                    LockScreenLyrics(width: Self.lyricsWidth, glow: cover)
                        .offset(x: (Self.artworkSize + Self.artworkSpacing) / 2, y: -42)
                }
            }
            .frame(width: proxy.size.width, height: height)
            // Fading out towards the bottom, where macOS draws the user's
            // picture and the password field: they show through, and since
            // this window takes no clicks, stay usable. The edge is a
            // shoreline, not a ruler - reaching further down in places, the
            // way water runs up a beach - blurred soft, and breathing.
            .mask { BreathingShoreline() }
        }
        .environment(\.colorScheme, .dark)
    }
}

/// The shoreline, rising and falling like a breath and drifting a little
/// sideways as waves would.
///
/// Only its position moves. The shape and its blur are drawn once and
/// flattened, and a finished bitmap sliding about is next to free - where
/// redrawing a full-screen blurred mask each frame is what made this screen
/// stutter before. It is drawn wider and taller than the screen so the
/// drift never shows an edge.
private struct BreathingShoreline: View {
    @State private var inhale = false
    @State private var drift = false

    var body: some View {
        GeometryReader { proxy in
            ShorelineShape()
                .fill(.black)
                .blur(radius: 36)
                .frame(width: proxy.size.width + 120, height: proxy.size.height + 60)
                .drawingGroup()
                .offset(x: drift ? -30 : -90, y: inhale ? 18 : -18)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) { inhale = true }
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}

/// Everything above an uneven line across the lower screen: a few gentle
/// swells of different lengths laid over each other, so it never repeats
/// across the width, and dips lowest off-centre rather than in the middle.
private struct ShorelineShape: Shape {
    func path(in rect: CGRect) -> Path {
        let base = rect.height * 0.72
        let swell = rect.height * 0.07
        var path = Path()
        path.move(to: CGPoint(x: rect.minX - 60, y: rect.minY - 60))
        path.addLine(to: CGPoint(x: rect.maxX + 60, y: rect.minY - 60))
        let steps = 96
        for step in stride(from: steps, through: 0, by: -1) {
            let t = Double(step) / Double(steps)
            let x = rect.minX - 60 + (rect.width + 120) * t
            let wave = sin(t * .pi * 2.3 + 0.8) * 0.55
                + sin(t * .pi * 5.1 + 2.1) * 0.3
                + sin(t * .pi * 9.7 + 0.4) * 0.15
            path.addLine(to: CGPoint(x: x, y: base + swell * wave))
        }
        path.closeSubpath()
        return path
    }
}

/// The card on its own, in a window just its size, so nothing but the card
/// stands between the user and the lock screen.
struct LockScreenCardView: View {
    @ObservedObject private var music = MusicManager.shared
    @Default(.lockScreenExpanded) private var expanded

    var body: some View {
        LockScreenMusicCard(expanded: $expanded, tint: LockScreenPalette.cover(music.avgColor))
            .frame(
                width: LockScreenBackdropView.panelSize.width,
                height: expanded ? LockScreenBackdropView.expandedPanelHeight : LockScreenBackdropView.panelSize.height,
                alignment: .topLeading)
            .background { LockScreenCardSurface(cornerRadius: 28) }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.24), radius: 26, x: 0, y: 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.58, dampingFraction: 0.86), value: expanded)
            .environment(\.colorScheme, .dark)
            .environment(\.controlActiveState, .active)
    }
}

enum LockScreenPalette {
    /// The cover's own colour, lifted so a dark cover still lights something.
    static func cover(_ color: NSColor) -> Color {
        Color(nsColor: color).ensureMinimumBrightness(factor: 0.55)
    }
}

// MARK: - The card

/// Cover, title, artist and a small equalizer; the scrubber; back, play and
/// forward in the middle with the output on the right.
private struct LockScreenMusicCard: View {
    @ObservedObject private var music = MusicManager.shared
    @Binding var expanded: Bool
    /// The cover's colour, for the bar.
    let tint: Color

    @State private var scrubProgress: CGFloat?

    var body: some View {
        TimelineView(.periodic(from: .now, by: music.isPlaying ? 1 : 30)) { context in
            content(at: context.date)
        }
    }

    private func content(at date: Date) -> some View {
        let elapsed = elapsedTime(at: date)
        let duration = music.songDuration
        let progress = duration > 0 ? min(max(CGFloat(elapsed / duration), 0), 1) : 0
        let shown = min(max(scrubProgress ?? progress, 0), 1)

        return VStack {
            HStack(spacing: 15) {
                if !expanded {
                    Button { withAnimation(.spring(response: 0.6)) { expanded = true } } label: {
                        Image(nsImage: music.albumArt)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressFadeButtonStyle())
                }

                HStack(alignment: .top) {
                    Button { withAnimation(.spring(response: 0.6)) { expanded.toggle() } } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            MarqueeText(
                                .constant(music.songTitle.isEmpty ? "Unknown Track" : music.songTitle),
                                font: .system(size: 16, weight: .medium), nsFont: .headline,
                                textColor: .white.opacity(0.8), minDuration: 2,
                                frameWidth: expanded ? 260 : 180)
                            MarqueeText(
                                .constant(music.artistName.isEmpty ? "Unknown Artist" : music.artistName),
                                font: .system(size: 14), nsFont: .headline,
                                textColor: .white.opacity(0.5), minDuration: 3,
                                frameWidth: expanded ? 260 : 180)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressFadeButtonStyle())

                    Spacer()

                    Rectangle()
                        .fill(.white.opacity(0.7))
                        .mask { AudioSpectrumView(isPlaying: .constant(music.isPlaying)) }
                        .frame(width: 13, height: 15)
                }
                .padding(.trailing, 5)
            }

            Spacer()

            LockScreenProgressBar(
                tint: tint,
                progress: shown,
                elapsed: duration > 0 ? TimeInterval(shown) * duration : elapsed,
                duration: duration,
                onScrub: { scrubProgress = $0 },
                onScrubEnded: { value in
                    music.seek(to: duration * TimeInterval(value))
                    scrubProgress = nil
                })

            Spacer()

            ZStack {
                HStack(spacing: 25) {
                    LockScreenControlButton(symbol: "backward.fill", fontSize: 22, style: .backward) {
                        music.previousTrack()
                    }
                    LockScreenControlButton(
                        symbol: music.isPlaying ? "pause.fill" : "play.fill", fontSize: 32, style: .playPause
                    ) {
                        music.togglePlay()
                    }
                    LockScreenControlButton(symbol: "forward.fill", fontSize: 22, style: .forward) {
                        music.nextTrack()
                    }
                }

                HStack {
                    Spacer()
                    LockScreenControlButton(symbol: outputSymbol, fontSize: 21, style: .neutral) {
                        AudioDeviceManager.shared.start()
                    }
                }
                .padding(.horizontal, 5)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(18)
    }

    private var outputSymbol: String {
        let audio = AudioDeviceManager.shared
        return audio.current.map(audio.symbol(for:)) ?? "airplayaudio"
    }

    /// The player's own timestamp carried forward by the clock.
    private func elapsedTime(at date: Date) -> TimeInterval {
        guard music.isPlaying else { return music.elapsedTime }
        let drift = date.timeIntervalSince(music.timestampDate) * music.playbackRate
        return min(music.songDuration, max(0, music.elapsedTime + drift))
    }
}

/// Ultra-thin material with a faint white edge - DynamicNotch's default
/// widget surface, untinted, at normal brightness.
private struct LockScreenCardSurface: View {
    let cornerRadius: CGFloat
    @Default(.liquidGlassNotch) private var liquidGlass

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            // The notch's own glass when it is on, so the lock screen matches.
            if #available(macOS 26.0, *), liquidGlass {
                Rectangle().fill(.clear).glassEffect(.clear, in: shape)
            } else {
                shape.fill(.ultraThinMaterial)
            }
        }
        .overlay { shape.stroke(.white.opacity(0.15), lineWidth: 1) }
    }
}

/// Elapsed, a scrubbable bar that thickens under the pointer, and the length.
private struct LockScreenProgressBar: View {
    let tint: Color
    let progress: CGFloat
    let elapsed: TimeInterval
    let duration: TimeInterval
    let onScrub: (CGFloat) -> Void
    let onScrubEnded: (CGFloat) -> Void

    @State private var scrubbing = false

    var body: some View {
        HStack(spacing: 10) {
            Text(Self.format(elapsed))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(scrubbing ? .white.opacity(0.8) : .secondary)

            GeometryReader { proxy in
                let track: CGFloat = scrubbing ? 11 : 7
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(.white.opacity(0.15))
                        .frame(height: track)
                    // The cover's colour, glowing, where DynamicNotch has white.
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [tint.opacity(scrubbing ? 0.95 : 0.75), tint],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * min(max(progress, 0), 1), height: track)
                }
                .clipShape(Capsule(style: .continuous))
                .shadow(color: tint.opacity(0.6), radius: 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard duration > 0 else { return }
                            scrubbing = true
                            onScrub(Self.fraction(value.location.x, proxy.size.width))
                        }
                        .onEnded { value in
                            guard duration > 0 else { return }
                            scrubbing = false
                            onScrubEnded(Self.fraction(value.location.x, proxy.size.width))
                        })
            }
            .frame(height: 18)

            Text(duration > 0 ? Self.format(duration) : "LIVE")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(scrubbing ? .white : .secondary)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: scrubbing)
    }

    private static func fraction(_ x: CGFloat, _ width: CGFloat) -> CGFloat {
        width > 0 ? min(max(x / width, 0), 1) : 0
    }

    static func format(_ time: TimeInterval) -> String {
        guard time.isFinite else { return "--:--" }
        let total = max(0, Int(time.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

/// A transport button that answers a press with a soft flash behind it and a
/// nudge of the symbol - back and forward lean the way they go.
private struct LockScreenControlButton: View {
    enum Style {
        case neutral, backward, playPause, forward

        var travel: CGFloat { self == .backward ? -3.5 : (self == .forward ? 3.5 : 0) }
        var rotation: Double { self == .backward ? -7 : (self == .forward ? 7 : 0) }
        var peak: CGFloat { self == .playPause ? 1.18 : 1.11 }
        var flash: Double { self == .playPause ? 0.22 : 0.14 }
        var flashScale: CGFloat { self == .playPause ? 1.34 : 1.24 }
    }

    let symbol: String
    let fontSize: CGFloat
    let style: Style
    let action: () -> Void

    @State private var flashScale: CGFloat = 0.74
    @State private var flashOpacity: Double = 0
    @State private var iconScale: CGFloat = 1
    @State private var iconOffset: CGFloat = 0
    @State private var iconRotation: Double = 0
    @State private var hovering = false

    var body: some View {
        Button(action: press) {
            ZStack {
                Circle()
                    .fill(.white)
                    .opacity(flashOpacity)
                    .scaleEffect(flashScale)
                    .blur(radius: 4)
                Image(systemName: symbol)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .scaleEffect(iconScale)
                    .offset(x: iconOffset)
                    .rotationEffect(.degrees(iconRotation))
                    .contentTransition(.symbolEffect(.replace))
                    .animation(.spring(response: 0.26, dampingFraction: 0.76), value: symbol)
            }
            .frame(width: 42, height: 42)
            .background(Circle().fill(.white.opacity(hovering ? 0.12 : 0)))
            .contentShape(Circle())
        }
        .buttonStyle(PressFadeButtonStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    private func press() {
        flashScale = 0.74
        flashOpacity = style.flash
        iconScale = 0.96
        withAnimation(.easeOut(duration: 0.22)) {
            flashScale = style.flashScale
            flashOpacity = 0
        }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) {
            iconScale = style.peak
            iconOffset = style.travel
            iconRotation = style.rotation
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) {
                iconScale = 1
                iconOffset = 0
                iconRotation = 0
            }
        }
        action()
    }
}

/// Dims a little and shrinks a touch while held.
private struct PressFadeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Background

/// The cover, over black, blown up past the screen's corners and blurred to
/// its colours - turning slowly and breathing, with its colour pooled at the
/// bottom.
private struct LockScreenArtworkBackground: View {
    let artwork: NSImage
    let tint: Color

    @State private var turn: Double = 0
    @State private var breathe: CGFloat = 1
    @State private var blurred: NSImage?

    var body: some View {
        GeometryReader { proxy in
            let diagonal = hypot(proxy.size.width, proxy.size.height)
            ZStack {
                Color.black
                // Blurred once, up front: blurring a screen-sized layer every
                // frame while it turns and breathes dropped the whole lock
                // screen - lyrics included - to a handful of frames a second.
                // A finished bitmap turning is next to free.
                if let blurred {
                    Image(nsImage: blurred)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: diagonal, height: diagonal)
                        .opacity(0.6)
                        .scaleEffect(breathe)
                        .rotationEffect(.degrees(turn))
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                        .transition(.opacity)
                }
                RadialGradient(
                    colors: [tint.opacity(0.35), .clear],
                    center: .bottom, startRadius: 0, endRadius: proxy.size.height * 0.8)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .drawingGroup()
        }
        .task(id: ObjectIdentifier(artwork)) {
            let image = artwork
            let baked = await Task.detached(priority: .userInitiated) { Self.bake(image) }.value
            withAnimation(.easeInOut(duration: 0.6)) { blurred = baked }
        }
        .onAppear {
            withAnimation(.linear(duration: 60).repeatForever(autoreverses: false)) { turn = 360 }
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) { breathe = 1.3 }
        }
    }

    /// The cover made small, blurred to its colours and saturated, once.
    nonisolated private static func bake(_ image: NSImage) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let side: CGFloat = 96
        let input = CIImage(cgImage: cg)
        let scale = side / max(input.extent.width, input.extent.height)
        let small = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let blurred = small
            .clampedToExtent()
            .applyingGaussianBlur(sigma: 10)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.45])
            .cropped(to: small.extent)
        guard let output = CIContext().createCGImage(blurred, from: small.extent) else { return nil }
        return NSImage(cgImage: output, size: NSSize(width: side, height: side))
    }
}

// MARK: - Clock

/// The date small over the time large, the way a phone's lock screen has it.
private struct LockScreenClock: View {
    let date: Date

    var body: some View {
        VStack(spacing: 0) {
            Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
            Text(date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()))
                .font(.system(size: 92, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.92))
                .contentTransition(.numericText())
        }
        .shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Lyrics

/// Nine synced lines around the one being sung - it large and bright, the
/// rest smaller and dimmer the further off, tap one to go there - or plain
/// lyrics as a still page.
private struct LockScreenLyrics: View {
    @ObservedObject private var music = MusicManager.shared

    let width: CGFloat
    /// The cover's colour, glowing behind the line being sung.
    let glow: Color
    private let height: CGFloat = 520

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.35)) { context in
            content(at: context.date)
                .frame(width: width, height: height, alignment: .leading)
                .clipped()
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.16),
                            .init(color: .black, location: 0.84),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom)
                }
        }
    }

    @ViewBuilder
    private func content(at date: Date) -> some View {
        if !music.syncedLyrics.isEmpty {
            let active = activeIndex(at: date)
            VStack(alignment: .leading, spacing: 20) {
                ForEach((active - 4)...(active + 4), id: \.self) { index in
                    let exists = index >= 0 && index < music.syncedLyrics.count
                    line(exists ? music.syncedLyrics[index].text : " ", distance: index - active) {
                        if exists { music.seek(to: music.syncedLyrics[index].time) }
                    }
                    .transition(.opacity)
                }
            }
            .frame(width: width, height: height)
            .animation(.spring(response: 0.4, dampingFraction: 0.88), value: active)
        } else if !music.currentLyrics.isEmpty {
            let lines = music.currentLyrics.split(separator: "\n").prefix(9).map(String.init)
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, text in
                    line(text, distance: index - lines.count / 2, onTap: nil)
                }
            }
            .frame(width: width, height: height, alignment: .center)
        } else {
            Text(music.isFetchingLyrics ? "Looking for the lyrics" : "The lyrics were not found")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.38))
                .frame(width: width, height: height, alignment: .center)
        }
    }

    private func line(_ text: String, distance: Int, onTap: (() -> Void)?) -> some View {
        let active = distance == 0
        let far: CGFloat = min(CGFloat(abs(distance)), 4)
        let opacity: Double = active ? 0.98 : max(0.15, 0.45 - Double(far) * 0.07)
        let scale: CGFloat = max(0.82, 1 - far * 0.045)
        let shadow: Color = active ? glow.opacity(0.7) : .clear
        return Text(text.isEmpty ? " " : text)
            .font(.system(size: active ? 38 : 30, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(opacity))
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .scaleEffect(scale, anchor: .leading)
            .offset(x: active ? 0 : 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .shadow(color: shadow, radius: 14)
            .contentTransition(.opacity)
            .zIndex(Double(10 - far))
            .contentShape(Rectangle())
            .onTapGesture { onTap?() }
    }

    private func activeIndex(at date: Date) -> Int {
        var elapsed = music.elapsedTime
        if music.isPlaying {
            elapsed += date.timeIntervalSince(music.timestampDate) * music.playbackRate
        }
        return music.syncedLyrics.lastIndex { $0.time <= elapsed } ?? 0
    }
}
