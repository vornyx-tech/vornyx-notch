//
//  LockScreenExpanded.swift
//  VornyxNotch
//
//  The lock screen given over to the music: the cover large, the lyrics
//  scrolling beside it, the room lit in the cover's colours.
//
//  Layout, lyric styling and the moving artwork background after
//  DynamicNotch's LockScreenNowPlayingPanelView and LockScreenLyricsView by
//  Evgeniy Petrukovich (GPL-3.0), https://github.com/jackson-storm/dynamicnotch
//

import AppKit
import Defaults
import SwiftUI

/// Everything on the lock screen: the expanded layout when it is on, and the
/// card either way, where it always sits.
struct LockScreenRootView: View {
    @ObservedObject private var music = MusicManager.shared
    @Default(.lockScreenExpanded) private var expanded

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let artwork = min(460, size.height * 0.38)
            let lyricsWidth = min(540, size.width * 0.34)
            let showsLyrics = Defaults[.enableLyrics]

            ZStack {
                if expanded {
                    LockScreenArtworkBackground(artwork: music.albumArt)
                        .transition(.opacity)

                    LockScreenClock()
                        .position(x: size.width / 2, y: size.height * 0.12)
                        .transition(.move(edge: .top).combined(with: .opacity))

                    HStack(alignment: .center, spacing: 90) {
                        Button { toggle() } label: {
                            Image(nsImage: music.albumArt)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: artwork, height: artwork)
                                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                                .shadow(color: .black.opacity(0.45), radius: 24, y: 16)
                        }
                        .buttonStyle(.plain)
                        .transition(.scale(scale: 0.82).combined(with: .opacity))

                        if showsLyrics {
                            LockScreenLyrics(width: lyricsWidth, height: artwork + 60)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .position(x: size.width / 2, y: size.height * 0.45)
                }

                // The card stays where it always is, above the password field.
                LockScreenPlayerView(onArtworkTap: toggle)
                    .position(x: size.width / 2, y: size.height * (1 - 0.22) - 129)
            }
            .frame(width: size.width, height: size.height)
        }
        .animation(.spring(response: 0.58, dampingFraction: 0.86), value: expanded)
        .environment(\.colorScheme, .dark)
    }

    private func toggle() {
        expanded.toggle()
    }
}

// MARK: - Background

/// The cover, blown up past the screen's corners, blurred to colour, turning
/// slowly and breathing - fading out towards the bottom, so the password field
/// and picture macOS draws there stay in sight.
private struct LockScreenArtworkBackground: View {
    let artwork: NSImage

    @State private var turn: Double = 0
    @State private var breathe: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let diagonal = hypot(proxy.size.width, proxy.size.height)
            ZStack {
                Color.black
                // A tiny copy scaled up is blurry already, so the blur on top
                // can stay small - cheap enough for the whole screen.
                Image(nsImage: Self.thumbnail(of: artwork))
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: diagonal, height: diagonal)
                    .blur(radius: 60)
                    .saturation(1.45)
                    .opacity(0.6)
                    .scaleEffect(breathe)
                    .rotationEffect(.degrees(turn))
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.62),
                        .init(color: .clear, location: 0.9),
                    ],
                    startPoint: .top, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.linear(duration: 40).repeatForever(autoreverses: false)) { turn = 360 }
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) { breathe = 1.35 }
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

private struct LockScreenClock: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 2) {
                Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                Text(context.date.formatted(.dateTime.hour().minute()))
                    .font(.system(size: 88, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.92))
                    .contentTransition(.numericText())
            }
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        }
    }
}

// MARK: - Lyrics

/// Synced lines around the one being sung, the current one large and bright,
/// the rest smaller and dimmer the further they are; plain lyrics, with no
/// timings, as a still page.
private struct LockScreenLyrics: View {
    @ObservedObject private var music = MusicManager.shared

    let width: CGFloat
    let height: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.3)) { context in
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
                ForEach(max(0, active - 4)...(active + 4), id: \.self) { index in
                    if index < music.syncedLyrics.count {
                        line(music.syncedLyrics[index].text, distance: index - active) {
                            music.seek(to: music.syncedLyrics[index].time)
                        }
                    }
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
            .frame(width: width, height: height)
        } else {
            Text(music.isFetchingLyrics ? "Looking for lyrics..." : "No lyrics for this song")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.38))
                .frame(width: width, height: height)
        }
    }

    private func line(_ text: String, distance: Int, onTap: (() -> Void)?) -> some View {
        let active = distance == 0
        let far = min(CGFloat(abs(distance)), 4)
        return Text(text.isEmpty ? " " : text)
            .font(.system(size: active ? 36 : 28, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(active ? 0.98 : max(0.15, 0.45 - Double(far) * 0.07)))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .scaleEffect(max(0.82, 1 - far * 0.045), anchor: .leading)
            .offset(x: active ? 0 : 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { onTap?() }
    }

    /// The last line that has started, by the player's clock carried forward.
    private func activeIndex(at date: Date) -> Int {
        var elapsed = music.elapsedTime
        if music.isPlaying {
            elapsed += date.timeIntervalSince(music.timestampDate) * music.playbackRate
        }
        return music.syncedLyrics.lastIndex { $0.time <= elapsed } ?? 0
    }
}
