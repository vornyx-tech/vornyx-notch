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
//  their sizes and placement as they are there.
//

import AppKit
import Defaults
import SwiftUI

/// Everything on the lock screen, laid out from the screen's centre the way
/// DynamicNotch lays it out.
struct LockScreenRootView: View {
    @ObservedObject private var music = MusicManager.shared
    @Default(.lockScreenExpanded) private var expanded

    static let panelSize = CGSize(width: 340, height: 180)
    private static let expandedPanelHeight: CGFloat = panelSize.height - 20
    private static let artworkSize: CGFloat = 500
    private static let artworkSpacing: CGFloat = 90
    private static let clockHeight: CGFloat = 76
    private static let lyricsWidth: CGFloat = 520
    private static let lyricsSpacing: CGFloat = 90
    private static let panelCenterYOffset: CGFloat = (panelSize.height / 2) + 80

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let showsLyrics = expanded && Defaults[.enableLyrics]

            ZStack {
                if expanded {
                    LockScreenArtworkBackground(artwork: music.albumArt)
                        .ignoresSafeArea()
                        .transition(.opacity)

                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        LockScreenClock(
                            date: context.date,
                            width: Self.artworkSize + 120,
                            height: Self.clockHeight)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .offset(y: -height / 2 + 130)

                    Button { withAnimation(.spring(response: 0.65)) { expanded = false } } label: {
                        Image(nsImage: music.albumArt)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: Self.artworkSize, height: Self.artworkSize)
                            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                            .shadow(color: .black.opacity(0.45), radius: 24, x: 0, y: 16)
                    }
                    .buttonStyle(PressFadeButtonStyle())
                    .transition(.scale(scale: 0.82).combined(with: .opacity))
                    .offset(x: showsLyrics ? -((Self.lyricsWidth + Self.lyricsSpacing) / 2) : 0, y: -42)
                }

                if showsLyrics {
                    LockScreenLyrics(width: Self.lyricsWidth)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .offset(x: (Self.artworkSize + Self.artworkSpacing) / 2, y: -42)
                }

                LockScreenMusicCard(expanded: $expanded)
                    .frame(
                        width: Self.panelSize.width,
                        height: expanded ? Self.expandedPanelHeight : Self.panelSize.height,
                        alignment: .topLeading)
                    .background { LockScreenCardSurface(cornerRadius: 28) }
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: .black.opacity(0.24), radius: 26, x: 0, y: 14)
                    .offset(y: expanded ? height / 2 - 180 : Self.panelCenterYOffset)
            }
            .frame(width: proxy.size.width, height: height)
        }
        .animation(.spring(response: 0.58, dampingFraction: 0.86), value: expanded)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .environment(\.colorScheme, .dark)
        .environment(\.controlActiveState, .active)
    }
}

// MARK: - The card

/// Cover, title, artist and a small equalizer; the scrubber; back, play and
/// forward in the middle with the output on the right.
private struct LockScreenMusicCard: View {
    @ObservedObject private var music = MusicManager.shared
    @Binding var expanded: Bool

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

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(.ultraThinMaterial)
            .overlay { shape.stroke(.white.opacity(0.15), lineWidth: 1) }
    }
}

/// Elapsed, a scrubbable bar that thickens under the pointer, and the length.
private struct LockScreenProgressBar: View {
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
                    Rectangle()
                        .fill(.white.opacity(scrubbing ? 0.8 : 0.5))
                        .frame(width: proxy.size.width * min(max(progress, 0), 1), height: track)
                }
                .clipShape(Capsule(style: .continuous))
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
/// its colours.
private struct LockScreenArtworkBackground: View {
    let artwork: NSImage

    var body: some View {
        GeometryReader { proxy in
            let diagonal = hypot(proxy.size.width, proxy.size.height)
            ZStack {
                Color.black
                // A tiny copy scaled up is blurry already, so a smaller blur
                // on top lands where DynamicNotch's 200 does, for less work.
                Image(nsImage: Self.thumbnail(of: artwork))
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: diagonal, height: diagonal)
                    .blur(radius: 70)
                    .saturation(1.45)
                    .opacity(0.6)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                LinearGradient(
                    colors: [.white.opacity(0.08), .black.opacity(0.16)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    private static func thumbnail(of image: NSImage) -> NSImage {
        let side: CGFloat = 48
        let small = NSImage(size: NSSize(width: side, height: side))
        small.lockFocus()
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        small.unlockFocus()
        return small
    }
}

// MARK: - Clock

/// The time and the date side by side, both large.
private struct LockScreenClock: View {
    let date: Date
    let width: CGFloat
    let height: CGFloat

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "EEE d MMM"
        return formatter
    }()

    var body: some View {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let dateString = Self.dateFormatter.string(from: date)

        HStack(alignment: .center, spacing: 58) {
            Spacer()
            Text(String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0))
                .font(.system(size: 38, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text(dateString.prefix(1).localizedUppercase + dateString.dropFirst())
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: true, vertical: false)
            Spacer()
        }
        .frame(width: width, height: height, alignment: .leading)
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
        let far = min(CGFloat(abs(distance)), 4)
        return Text(text.isEmpty ? " " : text)
            .font(.system(size: active ? 38 : 30, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(active ? 0.98 : max(0.15, 0.45 - Double(far) * 0.07)))
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .scaleEffect(max(0.82, 1 - far * 0.045), anchor: .leading)
            .offset(x: active ? 0 : 10)
            .frame(maxWidth: .infinity, alignment: .leading)
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
