//
//  LyricsViews.swift
//  VornyxNotch
//
//  The lyrics as the open notch shows them: the line under the artist, and
//  the panel it opens below the notch, the way Apple Music's lyrics read -
//  the line being sung bright, the ones around it dim, and the words lighting
//  up letter by letter as they are sung.
//

import Combine
import CoreImage
import Defaults
import SwiftUI

// MARK: - A line being sung

/// A synced line as one `Text`, each word tagged with its timing, so a
/// renderer can light it word by word while the text itself - its wrapping,
/// kerning and joined letters - stays exactly as plain text lays it out.
/// The same text with or without the renderer takes the same room, so a line
/// becoming the one being sung does not move.
enum LyricText {
    static func text(_ line: TimedLyric) -> Text {
        guard #available(macOS 15.0, *), !line.words.isEmpty else { return Text(line.text) }
        var text = Text("")
        for word in line.words {
            text = text + Text(word.text.trimmingCharacters(in: .whitespaces))
                .customAttribute(WordTiming(start: word.start, end: word.end))
            if word.text.last?.isWhitespace == true { text = text + Text(" ") }
        }
        return text
    }
}

/// The line being sung, lit as it is sung: dim, with the light sweeping
/// across it as one soft-edged wipe that follows the singing - the way Apple
/// Music's word-synced lyrics fill in.
struct KaraokeText: View {
    let line: TimedLyric
    /// Where the song is, word lead included.
    let elapsed: Double
    let font: Font
    var dim: Double = 0.32
    /// Width of the wipe's soft edge, in points.
    var softness: CGFloat = 22
    /// How strongly the sung part shows: 1 on the line being sung, 0 on the
    /// others. Animated, so a line handing over fades its light out rather
    /// than losing it at once.
    var strength: Double = 1

    var body: some View {
        if #available(macOS 15.0, *) {
            LyricText.text(line)
                .font(font)
                .foregroundStyle(.white)
                .textRenderer(KaraokeRenderer(elapsed: elapsed, dim: dim, strength: strength, softness: softness))
        } else {
            LyricText.text(line)
                .font(font)
                .foregroundStyle(.white.opacity(elapsed >= line.time && strength > 0.5 ? 1 : dim))
        }
    }
}

@available(macOS 15.0, *)
private struct WordTiming: TextAttribute {
    let start: Double
    let end: Double
}

/// Draws the line dim, then again bright through a mask: solid up to where
/// the singing has got, fading out over `softness` points past it. Where the
/// singing has got is a point that runs along the laid-out text - through
/// each word over the time it is sung and on across the space after it - so
/// the light moves continuously, never a letter or a word at a time.
@available(macOS 15.0, *)
private struct KaraokeRenderer: TextRenderer {
    let elapsed: Double
    var dim: Double
    var strength: Double
    let softness: CGFloat

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(dim, strength) }
        set {
            dim = newValue.first
            strength = newValue.second
        }
    }

    /// The least time a word is swept over, so a quick word is not a flash.
    private static let minimumSpan = 0.25
    /// The glow at the light's front: how far back from the front it
    /// reaches, how soft it is, and how bright.
    private static let glowReach: CGFloat = 46
    private static let glowRadius: CGFloat = 5
    private static let glowOpacity = 0.85
    /// How long the glow takes to die away once a word is sung and the
    /// light waits for the next.
    private static let glowFade = 0.7

    var displayPadding: EdgeInsets {
        let room = Self.glowRadius * 3
        return EdgeInsets(top: room, leading: room, bottom: room, trailing: room)
    }

    private struct Word {
        let timing: WordTiming
        let rect: CGRect
        let row: Int
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var words: [Word] = []
        for (row, line) in layout.enumerated() {
            for run in line {
                guard let timing = run[WordTiming.self] else { continue }
                words.append(Word(timing: timing, rect: run.typographicBounds.rect, row: row))
            }
        }
        let (litRow, litX, glows) = sweep(words)

        for (row, line) in layout.enumerated() {
            var base = context
            base.opacity = dim
            base.draw(line)

            guard row <= litRow, strength > 0.001 else { continue }
            let bounds = line.typographicBounds.rect.insetBy(dx: -softness, dy: -4)
            var bright = context
            bright.opacity = strength
            if row == litRow {
                bright.clipToLayer { mask in
                    let solid = litX - softness / 2
                    mask.fill(
                        Path(CGRect(x: bounds.minX, y: bounds.minY,
                                    width: max(0, solid - bounds.minX), height: bounds.height)),
                        with: .color(.black))
                    mask.fill(
                        Path(CGRect(x: solid, y: bounds.minY, width: softness, height: bounds.height)),
                        with: .linearGradient(
                            Gradient(colors: [.black, .clear]),
                            startPoint: CGPoint(x: solid, y: 0),
                            endPoint: CGPoint(x: solid + softness, y: 0)))
                }
            }
            bright.draw(line)

            for glow in glows where glow.row == row && glow.amount > 0.01 {
                drawGlow(line, at: glow.x, amount: glow.amount * strength, bounds: bounds, in: context)
            }
        }
    }

    /// The letters the light is reaching, drawn again blurred: a glow that
    /// peaks just behind the light's front and fades out over `glowReach`
    /// behind it, so only what is being sung glows and the words already
    /// sung are left plain.
    private func drawGlow(_ line: Text.Layout.Line, at x: CGFloat, amount: Double,
                          bounds: CGRect, in context: GraphicsContext) {
        var glow = context
        glow.opacity = Self.glowOpacity * amount
        let band = bounds.insetBy(dx: 0, dy: -Self.glowRadius * 2)
        let front = x + softness * 0.15
        let back = front - Self.glowReach
        glow.clipToLayer { mask in
            mask.fill(
                Path(CGRect(x: back, y: band.minY, width: front + softness * 0.5 - back, height: band.height)),
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.75),
                        .init(color: .clear, location: 1),
                    ]),
                    startPoint: CGPoint(x: back, y: 0),
                    endPoint: CGPoint(x: front + softness * 0.5, y: 0)))
        }
        glow.addFilter(.blur(radius: Self.glowRadius))
        glow.draw(line)
    }

    private struct Glow {
        let row: Int
        let x: CGFloat
        let amount: Double
    }

    /// The row the light is on, how far along it the light has got, and the
    /// glows to draw: at the light's front, dying away once a word is sung,
    /// and - when the light has just gone on to the next row - the one it
    /// left at the end of the last row, dying away too rather than vanishing.
    /// Before the first word, row -1: nothing lit.
    private func sweep(_ words: [Word]) -> (row: Int, x: CGFloat, glows: [Glow]) {
        guard let index = words.lastIndex(where: { $0.timing.start <= elapsed }) else {
            return (-1, 0, [])
        }
        let front = front(of: words, at: index)
        var glows = [Glow(row: words[index].row, x: front.glowX, amount: front.glow)]
        if index > 0, words[index - 1].row != words[index].row {
            let last = self.front(of: words, at: index - 1)
            glows.append(Glow(row: words[index - 1].row, x: last.glowX, amount: last.glow))
        }
        return (words[index].row, front.x, glows)
    }

    /// Where the light's front is for word `index`, where its glow is, and
    /// how strongly it glows.
    private func front(of words: [Word], at index: Int) -> (x: CGFloat, glowX: CGFloat, glow: Double) {
        let word = words[index]
        let span = max(word.timing.end - word.timing.start, Self.minimumSpan)
        let progress = CGFloat(((elapsed - word.timing.start) / span).clamped(to: 0...1))
        // Through the word and on across the space to the next one on the
        // same row, so the light does not jump between words.
        let next = index + 1 < words.count && words[index + 1].row == word.row
            ? words[index + 1].rect.minX : word.rect.maxX
        let x = word.rect.minX + (next - word.rect.minX) * progress
        // Past the end of a row, the light carries its soft edge off it.
        let pastEnd = progress >= 1 && next == word.rect.maxX
        // The glow stays on the last letters and fades out there, rather
        // than leaving with the edge.
        let glow = 1 - Self.smooth((elapsed - (word.timing.start + span)) / Self.glowFade)
        return (pastEnd ? x + softness : x, x, glow)
    }

    private static func smooth(_ x: Double) -> Double {
        let t = x.clamped(to: 0...1)
        return t * t * (3 - 2 * t)
    }
}

// MARK: - The line under the artist

/// The line being sung, on one row. A line too long for the row moves along
/// with the singing - by the words where they are timed, by the line's own
/// span where they are not - so the part being sung is always on screen and
/// the line has finished moving by the time it has been sung. A slow marquee
/// that set off on its own could not keep up with a fast line.
struct SyncedLyricStrip: View {
    let line: TimedLyric
    /// Where the song is, word lead included.
    let elapsed: Double
    /// When the line stops being sung.
    let end: Double
    let font: Font
    let nsFont: NSFont
    let width: CGFloat

    /// How far into the row the part being sung may get before the line moves.
    private static let focus: CGFloat = 0.62
    private static let fade: CGFloat = 14
    private static let glowRoom: CGFloat = 16

    private var lineWidth: CGFloat {
        ceil((line.text as NSString).size(withAttributes: [.font: nsFont]).width)
    }

    var body: some View {
        let overflow = max(0, lineWidth - width)
        let sung = CGFloat(line.progress(at: elapsed, end: end)) * lineWidth
        let offset = (sung - width * Self.focus).clamped(to: 0...overflow)

        KaraokeText(line: line, elapsed: elapsed, font: font, dim: 0.5, softness: 14)
            .lineLimit(1)
            .fixedSize()
            // Room for the glow to fade out fully above and below the words
            // before the clip, rather than end in a hard edge; taken back
            // below, so the line keeps its own height.
            .padding(.vertical, Self.glowRoom)
            .offset(x: -offset)
            .frame(width: width, alignment: .leading)
            .clipped()
            .mask {
                // Fade only the edge text is running off.
                HStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: offset > 1 ? Self.fade : 0)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: offset < overflow - 1 ? Self.fade : 0)
                }
            }
            .padding(.vertical, -Self.glowRoom)
    }
}

// MARK: - The panel below the notch

/// The lyrics panel the notch stretches down into, opened from the line
/// under the artist. The line being sung a third of the way down, the ones
/// before it fading out above, the ones to come below, each a tap away from
/// being played.
struct NotchLyricsPanel: View {
    @ObservedObject private var music = MusicManager.shared
    let height: CGFloat

    private var cornerRadius: CGFloat { innerPanelCornerRadius }
    private static let fontSize: CGFloat = 21
    private static let font = Font.system(size: fontSize, weight: .bold, design: .rounded)
    private static let spacing: CGFloat = 12
    /// Average brightness, 0 to 1, past which a cover counts as pale.
    private static let paleLuminance = 0.62

    @State private var bakedGlow: NSImage?
    /// The cover is pale enough that its glow inside the panel would wash
    /// out white text: the glow is then turned down and the glass darkened.
    @State private var paleCover = false
    @Default(.lightingEffect) private var lightingEffect

    /// How far down the panel the line being sung sits.
    private static let focus: CGFloat = 0.3
    /// The column's move to the next line: slow out of the old line, slower
    /// into the new, no bounce.
    private static let glide = Animation.timingCurve(0.3, 0.0, 0.15, 1.0, duration: 0.85)

    /// The line the column is laid out around, and whether it has started:
    /// moved to the playing line inside an animation.
    @State private var shownActive = 0
    @State private var shownStarted = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipped()
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.16),
                        .init(color: .black, location: 0.78),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom)
            }
            // In the background, so the cover - filling the panel - cannot
            // size it.
            .background { coverWash.clipShape(shape) }
            // Clear glass, barely tinted: what colours it is the cover's glow
            // inside it, so it reads as liquid rather than a coloured plate.
            // With Liquid Glass off, a faint wash of the colour on black.
            .notchSurface(shape, stroke: 0.07,
                          tint: paleCover ? .black.opacity(0.28) : coverColor.opacity(0.12))
            .clipShape(shape)
            // The cover's colours glowing out around the panel, onto the
            // notch, the way they glow behind the album art.
            .background {
                if lightingEffect { PanelGlow(image: bakedGlow, isActive: music.isPlaying) }
            }
    }

    private var coverColor: Color {
        Color(nsColor: music.avgColor).ensureMinimumBrightness(factor: 0.45)
    }

    /// The cover's colours drifting inside the glass - the same blurred,
    /// slowly moving glow as behind the album art, and as around the panel -
    /// and see-through, so the glass stays glass.
    private var coverWash: some View {
        PanelGlow(image: bakedGlow, isActive: true, intensity: paleCover ? 0.3 : 0.55, bleed: 60)
            .overlay(Color.black.opacity(paleCover ? 0.18 : 0))
            .clipped()
            .allowsHitTesting(false)
            .task(id: ObjectIdentifier(music.albumArt)) {
                let image = music.albumArt
                let (glow, luminance) = await Task.detached(priority: .userInitiated) {
                    (PanelGlow.bake(image), PanelGlow.luminance(of: image))
                }.value
                withAnimation(.easeInOut(duration: 0.6)) {
                    bakedGlow = glow
                    paleCover = luminance > Self.paleLuminance
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if music.isFetchingLyrics {
            message("Loading lyrics…")
        } else if !music.syncedLyrics.isEmpty {
            // Ten times a second is plenty to notice the next line; the line
            // being sung keeps its own sixty, in `LyricRow`.
            LyricsTicker(isRunning: music.isPlaying, interval: 0.1) { now in
                synced(at: music.smoothedElapsed(at: now))
            }
        } else if !music.currentLyrics.isEmpty {
            ScrollView(.vertical, showsIndicators: false) {
                Text(music.currentLyrics)
                    .font(.system(size: Self.fontSize - 4, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 24)
            }
            .scrollableNotchContent()
        } else {
            message("No lyrics found")
        }
    }

    private func message(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(Self.font)
            .foregroundStyle(.white.opacity(0.35))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Every line of the song in one column, moved so the line being sung
    /// sits near the top, the way Apple Music's lyrics move: the whole
    /// column gliding up together when the next line starts.
    private func synced(at elapsed: Double) -> some View {
        let lines = music.syncedLyrics
        let active = music.activeLyricIndex(at: elapsed) ?? 0
        // Before the first line is sung, nothing is the line being sung.
        let started = elapsed + MusicManager.lyricsLead >= lines[active].time

        // A window of lines around the one being sung, not the whole song:
        // only these can show, and laying out and animating a hundred lines
        // on every move took the frames from everything else in the notch.
        let shown = shownActive.clamped(to: 0...(lines.count - 1))
        let window = max(0, shown - 3)...min(lines.count - 1, shown + 7)

        return LyricColumn(active: shown - window.lowerBound, focus: Self.focus, spacing: Self.spacing) {
            ForEach(window, id: \.self) { index in
                let distance = shownStarted ? index - shownActive : index - shownActive + 1
                LyricRow(
                    line: lines[index],
                    // The rest hold still: all sung above, none below.
                    resting: distance < 0 ? .infinity : -.infinity,
                    clock: distance == 0 ? .shared : .idle,
                    isActive: distance == 0,
                    idle: max(0.16, 0.32 - Double(min(abs(distance), 4)) * 0.04),
                    font: Self.font)
                .onTapGesture { music.seek(to: lines[index].time) }
            }
        }
        // The column slides to the new line: the state it is laid out by is
        // changed inside the animation, so every line glides to its place.
        .onChange(of: active) { _, line in
            withAnimation(Self.glide) { shownActive = line }
        }
        .onChange(of: started) { _, value in
            withAnimation(Self.glide) { shownStarted = value }
        }
        .onAppear {
            shownActive = active
            shownStarted = started
        }
    }
}

/// One line of the panel. The same view whether it is being sung or not,
/// so a line becoming the one sung is not swapped for another view - which
/// faded one out and the other in - but lit, and the light faded in.
private struct LyricRow: View {
    let line: TimedLyric
    /// The time the line is drawn at while it is not being sung.
    let resting: Double
    /// The shared clock for the line being sung, a still one for the rest:
    /// only the line being sung redraws every frame.
    @ObservedObject var clock: LyricsClock
    let isActive: Bool
    let idle: Double
    let font: Font

    /// Where the song was when this line stopped being sung. Drawn at that
    /// moment while its light fades, so its glow fades with it - drawn as
    /// fully sung instead, the glow vanished the instant the next line came.
    @State private var leftAt: Double?

    var body: some View {
        KaraokeText(
            line: line,
            elapsed: isActive
                ? MusicManager.shared.smoothedElapsed(at: clock.now) + MusicManager.wordLead
                : leftAt ?? resting,
            font: font,
            dim: isActive ? 0.32 : idle,
            strength: isActive ? 1 : 0)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onAppear { if isActive { LyricsClock.shared.follow() } }
        .onDisappear { if isActive { LyricsClock.shared.unfollow() } }
        .onChange(of: isActive) { _, active in
            if active {
                leftAt = nil
                LyricsClock.shared.follow()
            } else {
                leftAt = MusicManager.shared.smoothedElapsed(at: Date()) + MusicManager.wordLead
                LyricsClock.shared.unfollow()
            }
        }
    }
}

/// The time for the lyrics' animation, sixty times a second, from one
/// timer however many views follow it - and only while one does. A plain
/// timer rather than TimelineView(.animation), for the reason the album
/// art's glow gives: the notch is a non-activating panel, where the
/// display-link schedule cannot be relied on to keep firing.
@MainActor
final class LyricsClock: ObservableObject {
    static let shared = LyricsClock()
    /// Never ticks: what the lines not being sung follow.
    static let idle = LyricsClock()

    @Published private(set) var now = Date()
    private var timer: Timer?
    private var followers = 0

    func follow() {
        followers += 1
        guard timer == nil, self !== Self.idle else { return }
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.now = Date() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func unfollow() {
        followers = max(0, followers - 1)
        guard followers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }
}

/// Hands its content the time every `interval` while running - every frame
/// by default, from the shared clock.
struct LyricsTicker<Content: View>: View {
    let isRunning: Bool
    var interval: Double? = nil
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        if let interval {
            SlowTicker(isRunning: isRunning, interval: interval, content: content)
        } else {
            FrameTicker(isRunning: isRunning, content: content)
        }
    }
}

private struct FrameTicker<Content: View>: View {
    let isRunning: Bool
    let content: (Date) -> Content
    @ObservedObject private var clock = LyricsClock.shared

    var body: some View {
        content(clock.now)
            .onAppear { clock.follow() }
            .onDisappear { clock.unfollow() }
    }
}

private struct SlowTicker<Content: View>: View {
    let isRunning: Bool
    let content: (Date) -> Content
    /// Stored, as the album art glow's is: made in a body pass, it would be
    /// a new timer every pass.
    private let clock: Publishers.Autoconnect<Timer.TimerPublisher>
    @State private var now = Date()

    init(isRunning: Bool, interval: Double, content: @escaping (Date) -> Content) {
        self.isRunning = isRunning
        self.content = content
        clock = Timer.publish(every: interval, on: .main, in: .common).autoconnect()
    }

    var body: some View {
        content(now)
            .onReceive(clock) { date in
                guard isRunning else { return }
                now = date
            }
    }
}

/// The lyrics in a column, each line where the one before it ends, the
/// whole column shifted so line `active` starts `focus` of the way down.
/// The layout knows every line's height, so the shift is exact for lines
/// that wrap, and a change of `active` moves the lines - animated - rather
/// than scrolling anything.
private struct LyricColumn: Layout {
    let active: Int
    let focus: CGFloat
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = ProposedViewSize(width: bounds.width, height: nil)
        let heights = subviews.map { $0.sizeThatFits(width).height }
        var tops: [CGFloat] = []
        var y: CGFloat = 0
        for height in heights {
            tops.append(y)
            y += height + spacing
        }
        let focusTop = tops.indices.contains(active) ? tops[active] : 0
        let shift = bounds.minY + bounds.height * focus - focusTop
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX, y: tops[index] + shift),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: heights[index]))
        }
    }
}

/// The glow around the lyrics panel: the cover blurred to soft-edged
/// colour, larger than the panel and drifting slowly behind it. Blurred once
/// per cover into a bitmap; only the finished bitmap moves, which costs next
/// to nothing - blurring live every frame is what slowed the lock screen.
private struct PanelGlow: View {
    let image: NSImage?
    let isActive: Bool
    /// How strong; by default stronger over Liquid Glass, where the same
    /// glow reads faintly.
    var intensity: Double?
    /// How far past the view's edges the glow reaches.
    var bleed: CGFloat = 34

    @State private var drift = false

    var body: some View {
        let intensity = self.intensity ?? (NotchGlass.isActive ? 0.95 : 0.6)
        Color.clear
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaleEffect(x: drift ? 1.08 : 0.98, y: drift ? 1.0 : 1.12)
                        .offset(x: drift ? 18 : -18, y: drift ? -6 : 6)
                        .transition(.opacity)
                }
            }
            .padding(-bleed)
            .opacity(isActive ? intensity : 0)
            .animation(.easeInOut(duration: 0.6), value: isActive)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeInOut(duration: 5.3).repeatForever(autoreverses: true)) { drift = true }
            }
    }

    /// The cover's average brightness, 0 to 1, as the eye weighs it.
    nonisolated static func luminance(of image: NSImage) -> Double {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 0 }
        let input = CIImage(cgImage: cg)
        let average = input.applyingFilter(
            "CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: input.extent)])
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()]).render(
            average, toBitmap: &pixel, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return (0.2126 * Double(pixel[0]) + 0.7152 * Double(pixel[1]) + 0.0722 * Double(pixel[2])) / 255
    }

    /// The cover made small, set in a wide margin of nothing and blurred
    /// into it, so the glow fades out at every edge instead of ending in one.
    nonisolated static func bake(_ image: NSImage) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let side: CGFloat = 64
        let margin: CGFloat = 40
        let input = CIImage(cgImage: cg)
        let scale = side / max(input.extent.width, input.extent.height)
        let small = input
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: margin, y: margin))
        let canvas = CGRect(x: 0, y: 0, width: side + margin * 2, height: side + margin * 2)
        let glow = small
            .composited(over: CIImage(color: .clear).cropped(to: canvas))
            .applyingGaussianBlur(sigma: 16)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.5])
            .cropped(to: canvas)
        guard let output = CIContext().createCGImage(glow, from: canvas) else { return nil }
        return NSImage(cgImage: output, size: canvas.size)
    }
}
