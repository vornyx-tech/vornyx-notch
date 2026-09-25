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
        // Room for the shadow to fade out in. Without it the window's own edge
        // cuts the glow off square, and the card reads as a box with corners.
        .padding(34)
        .onReceive(tick) { date in
            guard music.isPlaying else { return }
            now = date
        }
    }

    /// Liquid Glass where the system draws it, a material before that, tinted
    /// by the cover either way.
    @ViewBuilder
    private var cardSurface: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)

        ZStack {
            if #available(macOS 26.0, *) {
                Rectangle()
                    .fill(.clear)
                    .glassEffect(.regular, in: shape)
            } else {
                shape.fill(.ultraThinMaterial)
            }

            shape.fill(Color(nsColor: music.avgColor).opacity(0.18))
            shape.strokeBorder(.white.opacity(0.14), lineWidth: 1)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.3), radius: 22, y: 8)
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
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private func makeWindow() -> NSWindow {
        let size = CGSize(width: 440 + 68, height: 190 + 68)
        let window = VornyxNotchSkyLightWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: LockScreenPlayerView())
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.hasShadow = false
        position(window)
        return window
    }

    /// Centred, resting just above the user's picture rather than over the
    /// clock: the login field sits about a fifth of the way up the screen.
    private func position(_ window: NSWindow) {
        guard let screen = NSScreen.notched ?? NSScreen.main else { return }
        let frame = screen.frame
        let size = window.frame.size
        window.setFrameOrigin(
            NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.minY + frame.height * 0.22
            )
        )
    }
}
