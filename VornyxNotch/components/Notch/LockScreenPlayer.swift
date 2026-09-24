//
//  LockScreenPlayer.swift
//  VornyxNotch
//
//  The player card shown over the login screen while the Mac is locked.
//

import AppKit
import Combine
import Defaults
import SkyLightWindow
import SwiftUI

/// Now playing on the lock screen: artwork, title, a scrubber and transport,
/// in a card above the password field.
struct LockScreenPlayerView: View {
    @ObservedObject private var music = MusicManager.shared
    /// Tapping the cover opens the lock screen out to the large layout, and
    /// back.
    var onArtworkTap: () -> Void = {}

    /// Ticks while a track plays, so the elapsed time moves without the
    /// player reporting every second.
    @State private var now = Date()
    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private static let cardWidth: CGFloat = 440
    private static let artworkSide: CGFloat = 62

    var body: some View {
        VStack(spacing: 14) {
            header
            scrubber
            transport
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(width: Self.cardWidth)
        .background { cardSurface }
        .shadow(color: .black.opacity(0.3), radius: 22, y: 8)
        // Room for the shadow to fade out in. Without it the window's own edge
        // cuts it off square, and the card reads as a box with corners.
        .padding(34)
        .onReceive(tick) { date in
            guard music.isPlaying else { return }
            now = date
        }
    }

    /// No tint, anywhere. `notchSurface` darkens its clear glass by default so
    /// white text holds up over a bright window behind the notch, but that is
    /// exactly the tint that was showing up here - so this card gets its own,
    /// completely untinted `.clear` glass instead of going through it.
    @ViewBuilder
    private var cardSurface: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)

        if #available(macOS 26.0, *) {
            Rectangle()
                .fill(.clear)
                .glassEffect(.clear.interactive(), in: shape)
                .overlay { shape.strokeBorder(.white.opacity(0.16), lineWidth: 1) }
        } else {
            shape
                .fill(.ultraThinMaterial.opacity(0.4))
                .overlay { shape.strokeBorder(.white.opacity(0.16), lineWidth: 1) }
        }
    }

    // MARK: - Rows

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: music.albumArt)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: Self.artworkSide, height: Self.artworkSide)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onTapGesture(perform: onArtworkTap)
                .help("Show the cover and lyrics large")

            VStack(alignment: .leading, spacing: 3) {
                Text(music.songTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(music.artistName)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "waveform")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(music.isPlaying ? 0.85 : 0.35))
                .symbolEffect(.variableColor.iterative, isActive: music.isPlaying)
        }
    }

    private var scrubber: some View {
        HStack(spacing: 10) {
            Text(timeLabel(elapsed))
                .frame(width: 42, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.22))
                    Capsule()
                        .fill(.white.opacity(0.9))
                        .frame(width: proxy.size.width * fraction)
                }
                .frame(height: 4)
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    let target = (location.x / max(1, proxy.size.width)) * music.songDuration
                    music.seek(to: max(0, min(music.songDuration, target)))
                }
            }
            .frame(height: 14)

            Text("-" + timeLabel(max(0, music.songDuration - elapsed)))
                .frame(width: 42, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .medium).monospacedDigit())
        .foregroundStyle(.white.opacity(0.7))
    }

    private var transport: some View {
        HStack(spacing: 0) {
            control("shuffle", size: 15, tinted: music.isShuffled) { music.toggleShuffle() }
            Spacer()
            control("backward.fill", size: 19) { music.previousTrack() }
            Spacer()
            control(music.isPlaying ? "pause.fill" : "play.fill", size: 27) { music.togglePlay() }
            Spacer()
            control("forward.fill", size: 19) { music.nextTrack() }
            Spacer()
            control(outputSymbol, size: 17) { AudioDeviceManager.shared.start() }
        }
        .padding(.horizontal, 6)
    }

    // MARK: - Pieces

    private func control(
        _ symbol: String,
        size: CGFloat,
        tinted: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(tinted ? Color.effectiveAccent : .white)
                .frame(width: 44, height: 34)
                .background { controlSurface }
        }
        .buttonStyle(.plain)
    }

    /// The same untinted `.clear` glass as the card, not `notchSurface`.
    @ViewBuilder
    private var controlSurface: some View {
        if #available(macOS 26.0, *) {
            Rectangle()
                .fill(.clear)
                .glassEffect(.clear.interactive(), in: Capsule())
        } else {
            Capsule().fill(.white.opacity(0.06))
        }
    }

    private var outputSymbol: String {
        let audio = AudioDeviceManager.shared
        return audio.current.map(audio.symbol(for:)) ?? "laptopcomputer"
    }

    /// Where the track is now: the player's own timestamp carried forward by
    /// the clock, so the bar moves between updates.
    private var elapsed: TimeInterval {
        guard music.isPlaying else { return music.elapsedTime }
        let drift = now.timeIntervalSince(music.timestampDate) * music.playbackRate
        return min(music.songDuration, max(0, music.elapsedTime + drift))
    }

    private var fraction: Double {
        guard music.songDuration > 0 else { return 0 }
        return min(1, max(0, elapsed / music.songDuration))
    }

    private func timeLabel(_ interval: TimeInterval) -> String {
        guard interval.isFinite, interval >= 0 else { return "0:00" }
        let total = Int(interval)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Owns the card's window: up while the Mac is locked and something is
/// playing, gone the moment it unlocks.
@MainActor
final class LockScreenPlayerController {
    static let shared = LockScreenPlayerController()

    private var window: NSWindow?
    private var playbackWatcher: AnyCancellable?
    private var previewTask: Task<Void, Never>?

    private init() {}

    func screenLocked() {
        guard Defaults[.lockScreenPlayer] else { return }
        // Follow the player while locked: nothing to show before the first
        // track starts, and nothing to leave up after the last one stops.
        playbackWatcher = MusicManager.shared.$isPlayerIdle
            .combineLatest(MusicManager.shared.$isPlaying)
            .receive(on: RunLoop.main)
            .sink { [weak self] idle, playing in
                if playing || !idle {
                    self?.show()
                } else {
                    self?.hide()
                }
            }
    }

    /// The lock screen's layout over the desktop for a while, without locking
    /// anything - for seeing it from Settings.
    func preview(for seconds: Double = 20) {
        previewTask?.cancel()
        show()
        previewTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled, self.playbackWatcher == nil else { return }
            self.hide()
        }
    }

    func screenUnlocked() {
        playbackWatcher?.cancel()
        playbackWatcher = nil
        hide()
    }

    // MARK: - Window

    private func show() {
        if window == nil {
            window = makeWindow()
        }
        guard let window else { return }
        window.orderFrontRegardless()
        if let sky = window as? VornyxNotchSkyLightWindow {
            sky.enableSkyLight()
        }
    }

    private func hide() {
        guard let window else { return }
        if let sky = window as? VornyxNotchSkyLightWindow {
            sky.disableSkyLight()
        }
        window.orderOut(nil)
    }

    /// The whole screen: the large layout needs it, and with it off the rest
    /// is clear, which lets clicks through to the login screen underneath.
    private func makeWindow() -> NSWindow {
        let size = (NSScreen.notched ?? NSScreen.main)?.frame.size ?? CGSize(width: 1512, height: 982)
        let window = VornyxNotchSkyLightWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = NSHostingView(rootView: LockScreenRootView())
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.hasShadow = false
        position(window)
        return window
    }

    /// Over the whole screen; the card places itself inside, resting just
    /// above the user's picture about a fifth of the way up.
    private func position(_ window: NSWindow) {
        guard let screen = NSScreen.notched ?? NSScreen.main else { return }
        window.setFrame(screen.frame, display: true)
    }
}
