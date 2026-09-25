//
//  NotchHomeView.swift
//  VornyxNotch
//
//  Created by Hugo Persson on 2024-08-18.
//  Modified by Harsh Vardhan Goswami & Richard Kunkli & Mustafa Ramadan
//

import Combine
import Defaults
import SwiftUI

// MARK: - Music Player Components

struct MusicPlayerView: View {
    @EnvironmentObject var vm: VornyxViewModel
    let albumArtNamespace: Namespace.ID

    var body: some View {
        HStack {
            AlbumArtView(vm: vm, albumArtNamespace: albumArtNamespace).padding(.all, 5)
            MusicControlsView().compositingGroup()
        }
    }
}

struct AlbumArtView: View {
    @Default(.trackChangeAnimation) private var trackChangeAnimation
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var vm: VornyxViewModel
    let albumArtNamespace: Namespace.ID

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if Defaults[.lightingEffect] {
                albumArtBackground
            }
            albumArtButton
        }
    }

    /// A new track's glow fades in over the old one's rather than replacing it,
    /// so the colour behind the player drifts to the new artwork instead of
    /// jumping. Slower than the artwork itself: a wash of colour changing fast
    /// reads as a flash.
    private var albumArtBackground: some View {
        ZStack {
            LivingGlow(
                image: musicManager.albumArt,
                isActive: musicManager.isPlaying,
                cornerRadius: AlbumArtStyle.openCornerRadius
            )
            .id(ObjectIdentifier(musicManager.albumArt))
            .transition(.opacity)
        }
        .animation(.smooth(duration: 0.8), value: ObjectIdentifier(musicManager.albumArt))
    }

    private var albumArtButton: some View {
        ZStack {
            Button {
                musicManager.openMusicApp()
            } label: {
                ZStack(alignment:.bottomTrailing) {
                    albumArtImage
                    appIconOverlay
                }
            }
            // No brightness: the artwork's glow is drawn from it, and would flash.
            .springyTile(hoverScale: 1.03, pressScale: 0.96, hoverBrightness: 0)
            .scaleEffect(musicManager.isPlaying ? 1 : 0.85)
            
            albumArtDarkOverlay
        }
    }

    private var albumArtDarkOverlay: some View {
        Rectangle()
            .aspectRatio(1, contentMode: .fit)
            .foregroundColor(Color.black)
            .opacity(musicManager.isPlaying ? 0 : 0.8)
            .blur(radius: 50)
    }
                

    /// The artwork, blurring out and back in when the track changes.
    ///
    /// Keyed by the image itself, not the title: the artwork arrives a moment
    /// after the title, and `MusicManager` only replaces the image when the
    /// artwork really changed, so this runs once per new cover. The matched
    /// geometry stays on the frame around the images, so the artwork still
    /// flies between the closed and the open notch.
    private var albumArtImage: some View {
        ZStack {
            switch trackChangeAnimation {
            case .blur:
                Image(nsImage: musicManager.albumArt)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .id(ObjectIdentifier(musicManager.albumArt))
                    .transition(.artworkBlur)
            case .flip:
                FlippingArtwork(
                    image: musicManager.albumArt,
                    cornerRadius: AlbumArtStyle.openCornerRadius)
            }
        }
            .aspectRatio(1, contentMode: .fit)
            // Drives the blur's transition only. The flip runs its own timeline,
            // and an animation here would smear the face swap it hides edge-on.
            .animation(
                trackChangeAnimation == .blur ? .smooth(duration: 0.55) : nil,
                value: ObjectIdentifier(musicManager.albumArt))
            .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
            // The blur is clipped to the rounded cover. The flip rounds its own
            // corners, and has to be free to grow past its frame while it
            // overshoots and wobbles - clipped here, all of that was cut off.
            .clipShape(ArtworkClip(
                cornerRadius: AlbumArtStyle.openCornerRadius,
                clips: trackChangeAnimation == .blur))
    }

    @ViewBuilder
    private var appIconOverlay: some View {
        if vm.notchState == .open && !musicManager.usingAppIconForArtwork {
            AppIcon(for: musicManager.bundleIdentifier ?? "com.apple.Music")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: AlbumArtStyle.appIconSize, height: AlbumArtStyle.appIconSize)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: AlbumArtStyle.appIconCornerRadius, style: .continuous)
                )
                .offset(x: 10, y: 10)
                .transition(.scale.combined(with: .opacity))
                .zIndex(2)
        }
    }
}

/// The blurred artwork behind the player, drifting slowly so it feels alive
/// rather than pasted on.
///
/// Five sine waves at periods that share no common multiple drive scale,
/// rotation, position and opacity. Because they never line up, the motion has
/// no visible loop - it wanders. A per-instance random phase means two tracks
/// never breathe in lockstep either.
///
/// It only animates while something is playing, and the home page only exists
/// while the notch is open, so it costs nothing the rest of the time.
private struct LivingGlow: View {
    let image: NSImage
    let isActive: Bool
    let cornerRadius: CGFloat

    @State private var phase = Double.random(in: 0..<1000)
    @State private var tick: Double = 0

    /// A plain timer rather than TimelineView(.animation): the notch lives in a
    /// non-activating panel, where the display-link schedule cannot be relied
    /// on to keep firing.
    ///
    /// Stored, NOT computed: a computed property hands `onReceive` a brand new
    /// publisher on every body pass, so the timer was being torn down and
    /// rebuilt many times a second.
    private let clock = Timer.publish(
        every: 1 / AlbumArtStyle.Glow.frameRate, on: .main, in: .common
    ).autoconnect()

    var body: some View {
        let g = AlbumArtStyle.Glow.self
        let t = tick + phase
        // Stronger over Liquid Glass, untouched over black - see `liquidGlassIntensity`.
        let intensity = NotchGlass.isActive ? g.liquidGlassIntensity : 1

        Group {
            let breathe = sin(t / g.breathePeriod)
            let rotate = sin(t / g.rotatePeriod)
            let sway = sin(t / g.swayPeriod)
            let bob = cos(t / g.bobPeriod)
            let shimmer = sin(t / g.shimmerPeriod)

            Image(nsImage: image)
                .resizable()
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .aspectRatio(1, contentMode: .fit)
                .scaleEffect(
                    x: g.baseScale.x + g.scaleSwing * breathe,
                    y: g.baseScale.y + g.scaleSwing * breathe
                )
                .rotationEffect(.degrees(g.baseRotation + g.rotationSwing * rotate))
                .offset(x: g.driftRadius * sway, y: g.driftRadius * bob)
                .blur(radius: g.blur)
                .opacity(isActive ? min(1, (g.baseOpacity + g.opacitySwing * shimmer) * intensity) : 0)
                .animation(.easeInOut(duration: 0.6), value: isActive)
        }
        .onReceive(clock) { date in
            guard isActive else { return }
            tick = date.timeIntervalSinceReferenceDate
        }
    }
}

struct MusicControlsView: View {
    @ObservedObject var musicManager = MusicManager.shared
        @EnvironmentObject var vm: VornyxViewModel
        @ObservedObject var webcamManager = WebcamManager.shared
    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast
    @Default(.musicControlSlots) private var slotConfig
    @Default(.musicControlSlotLimit) private var slotLimit

    var body: some View {
        VStack(alignment: .leading) {
            songInfoAndSlider
            slotToolbar
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var songInfoAndSlider: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 4) {
                songInfo(width: geo.size.width)
                musicSlider
            }
        }
        .padding(.top, 10)
        .padding(.leading, 5)
    }

    /// Forward pushes the new title in from the right, back from the left.
    private var titlePushEdge: Edge {
        musicManager.skipDirection == .backward ? .leading : .trailing
    }

    private func songInfo(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MarqueeText(
                $musicManager.songTitle, font: .headline, nsFont: .headline, textColor: .white,
                frameWidth: width, pushFrom: titlePushEdge)
            MarqueeText(
                $musicManager.artistName,
                font: .headline,
                nsFont: .headline,
                textColor: Defaults[.playerColorTinting]
                    ? Color(nsColor: musicManager.avgColor)
                        .ensureMinimumBrightness(factor: 0.6) : .gray,
                frameWidth: width,
                pushFrom: titlePushEdge
            )
            .fontWeight(.medium)
            if Defaults[.enableLyrics] {
                TimelineView(.animation(minimumInterval: 0.25)) { timeline in
                    let currentElapsed: Double = {
                        guard musicManager.isPlaying else { return musicManager.elapsedTime }
                        let delta = timeline.date.timeIntervalSince(musicManager.timestampDate)
                        let progressed = musicManager.elapsedTime + (delta * musicManager.playbackRate)
                        return min(max(progressed, 0), musicManager.songDuration)
                    }()
                    let line: String = {
                        if musicManager.isFetchingLyrics { return "Loading lyrics…" }
                        if !musicManager.syncedLyrics.isEmpty {
                            return musicManager.lyricLine(at: currentElapsed)
                        }
                        let trimmed = musicManager.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed.isEmpty ? "No lyrics found" : trimmed.replacingOccurrences(of: "\n", with: " ")
                    }()
                    let isPersian = line.unicodeScalars.contains { scalar in
                        let v = scalar.value
                        return v >= 0x0600 && v <= 0x06FF
                    }
                    MarqueeText(
                        .constant(line),
                        font: .subheadline,
                        nsFont: .subheadline,
                        textColor: musicManager.isFetchingLyrics ? .gray.opacity(0.7) : .gray,
                        frameWidth: width
                    )
                    .font(isPersian ? .custom("Vazirmatn-Regular", size: NSFont.preferredFont(forTextStyle: .subheadline).pointSize) : .subheadline)
                    .lineLimit(1)
                    .opacity(musicManager.isPlaying ? 1 : 0)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var musicSlider: some View {
        TimelineView(.animation(minimumInterval: musicManager.playbackRate > 0 ? 0.1 : nil)) { timeline in
            MusicSliderView(
                sliderValue: $sliderValue,
                duration: $musicManager.songDuration,
                lastDragged: $lastDragged,
                color: musicManager.avgColor,
                dragging: $dragging,
                currentDate: timeline.date,
                timestampDate: musicManager.timestampDate,
                elapsedTime: musicManager.elapsedTime,
                playbackRate: musicManager.playbackRate,
                isPlaying: musicManager.isPlaying
            ) { newValue in
                MusicManager.shared.seek(to: newValue)
            }
            .padding(.top, 5)
            .frame(height: 36)
        }
    }

    private var slotToolbar: some View {
        let slots = activeSlots
        return HStack(spacing: 6) {
            ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
                slotView(for: slot)
                    .frame(alignment: .center)
            }
        }
        // Wide, like the AirPods panel beside it and the LocalSend strip
        // below: clear glass shows what is behind it, so a card that only hugs
        // five buttons has no area to catch any light and reads as a black
        // plate. The same surface call and the same numbers as those two, and
        // no tint of its own, so it takes the glass settings they take.
        .padding(.horizontal, 12)
        // Shorter than the buttons' own frames: those are 30 and 40 points, but
        // the glyphs inside them are small, so the glass closes in on the icons
        // instead of clipping anything.
        .frame(height: 34)
        .notchSurface(
            RoundedRectangle(cornerRadius: innerPanelCornerRadius, style: .continuous),
            fill: 0.05, stroke: 0.06, interactive: true)
        // The card is as long as the buttons in it, so adding or removing one
        // in Settings lengthens or shortens it. The full width goes *after* the
        // surface, where it only centres the card instead of stretching it.
        .frame(maxWidth: .infinity)
    }

    private var activeSlots: [MusicControlButton] {
        let sanitizedLimit = min(
            max(slotLimit, MusicControlButton.minSlotCount),
            MusicControlButton.maxSlotCount
        )
        let padded = slotConfig.padded(to: sanitizedLimit, filler: .none)
        let result = Array(padded.prefix(sanitizedLimit))
        // If calendar and camera are both visible alongside music, hide the edge slots
        let shouldHideEdges = Defaults[.showCalendar] && Defaults[.showMirror] && webcamManager.cameraAvailable && vm.isCameraExpanded
        if shouldHideEdges && result.count >= 5 {
            return Array(result.dropFirst().dropLast())
        }

        return result
    }

    @ViewBuilder
    private func slotView(for slot: MusicControlButton) -> some View {
        switch slot {
        case .shuffle:
            HoverButton(icon: "shuffle", iconColor: musicManager.isShuffled ? .red : .primary, scale: .medium) {
                MusicManager.shared.toggleShuffle()
            }
        case .previous:
            HoverButton(icon: "backward.fill", scale: .medium) {
                MusicManager.shared.previousTrack()
            }
        case .playPause:
            HoverButton(icon: musicManager.isPlaying ? "pause.fill" : "play.fill", scale: .large) {
                MusicManager.shared.togglePlay()
            }
        case .next:
            HoverButton(icon: "forward.fill", scale: .medium) {
                MusicManager.shared.nextTrack()
            }
        case .repeatMode:
            HoverButton(icon: repeatIcon, iconColor: repeatIconColor, scale: .medium) {
                MusicManager.shared.toggleRepeat()
            }
        case .volume:
            VolumeControlView()
        case .favorite:
            FavoriteControlButton()
        case .goBackward:
            HoverButton(icon: "gobackward.15", scale: .medium) {
                MusicManager.shared.skip(seconds: -15)
            }
        case .goForward:
            HoverButton(icon: "goforward.15", scale: .medium) {
                MusicManager.shared.skip(seconds: 15)
            }
        case .none:
            Color.clear.frame(width: 0, height: 1)
        }
    }

    private var repeatIcon: String {
        switch musicManager.repeatMode {
        case .off:
            return "repeat"
        case .all:
            return "repeat"
        case .one:
            return "repeat.1"
        }
    }

    private var repeatIconColor: Color {
        switch musicManager.repeatMode {
        case .off:
            return .primary
        case .all, .one:
            return .red
        }
    }
}

struct FavoriteControlButton: View {
    @ObservedObject var musicManager = MusicManager.shared

    var body: some View {
        HoverButton(icon: iconName, iconColor: iconColor, scale: .medium) {
            MusicManager.shared.toggleFavoriteTrack()
        }
        .disabled(!musicManager.canFavoriteTrack)
        .opacity(musicManager.canFavoriteTrack ? 1 : 0.35)
    }

    private var iconName: String {
        musicManager.isFavoriteTrack ? "heart.fill" : "heart"
    }

    private var iconColor: Color {
        musicManager.isFavoriteTrack ? .red : .primary
    }
}

private extension Array where Element == MusicControlButton {
    func padded(to length: Int, filler: MusicControlButton) -> [MusicControlButton] {
        if count >= length { return self }
        return self + Array(repeating: filler, count: length - count)
    }
}

// MARK: - Volume Control View

struct VolumeControlView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @State private var volumeSliderValue: Double = 0.5
    @State private var dragging: Bool = false
    @State private var showVolumeSlider: Bool = false
    @State private var lastVolumeUpdateTime: Date = Date.distantPast
    private let volumeUpdateThrottle: TimeInterval = 0.1
    
    var body: some View {
        HStack(spacing: 4) {
            Button(action: {
                if musicManager.volumeControlSupported {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        showVolumeSlider.toggle()
                    }
                }
            }) {
                Image(systemName: volumeIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(musicManager.volumeControlSupported ? .white : .gray)
            }
            .springyTile(hoverScale: 1.15, pressScale: 0.9, hoverBrightness: 0.15)
            .disabled(!musicManager.volumeControlSupported)
            .frame(width: 24)

            if showVolumeSlider && musicManager.volumeControlSupported {
                CustomSlider(
                    value: $volumeSliderValue,
                    range: 0.0...1.0,
                    color: .white,
                    dragging: $dragging,
                    lastDragged: .constant(Date.distantPast),
                    onValueChange: { newValue in
                        MusicManager.shared.setVolume(to: newValue)
                    },
                    onDragChange: { newValue in
                        let now = Date()
                        if now.timeIntervalSince(lastVolumeUpdateTime) > volumeUpdateThrottle {
                            MusicManager.shared.setVolume(to: newValue)
                            lastVolumeUpdateTime = now
                        }
                    }
                )
                .frame(width: 48, height: 8)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .clipped()
        .onReceive(musicManager.$volume) { volume in
            if !dragging {
                volumeSliderValue = volume
            }
        }
        .onReceive(musicManager.$volumeControlSupported) { supported in
            if !supported {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showVolumeSlider = false
                }
            }
        }
        .onChange(of: showVolumeSlider) { _, isShowing in
            if isShowing {
                // Sync volume from app when slider appears
                Task {
                    await MusicManager.shared.syncVolumeFromActiveApp()
                }
            }
        }
        .onDisappear {
            // volumeUpdateTask?.cancel() // No longer needed
        }
    }
    
    
    private var volumeIcon: String {
        if !musicManager.volumeControlSupported {
            return "speaker.slash"
        } else if volumeSliderValue == 0 {
            return "speaker.slash.fill"
        } else if volumeSliderValue < 0.33 {
            return "speaker.1.fill"
        } else if volumeSliderValue < 0.66 {
            return "speaker.2.fill"
        } else {
            return "speaker.3.fill"
        }
    }
}

// MARK: - Main View

struct NotchHomeView: View {
    @EnvironmentObject var vm: VornyxViewModel
    @ObservedObject private var pods = AirPodsManager.shared
    @ObservedObject var webcamManager = WebcamManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = VornyxViewCoordinator.shared
    let albumArtNamespace: Namespace.ID

    var body: some View {
        Group {
            if !coordinator.firstLaunch {
                mainContent
            }
        }
    }

    private var shouldShowCamera: Bool {
        Defaults[.showMirror] && Defaults[.mirrorDisplayMode] == .inline
            && webcamManager.cameraAvailable && vm.isCameraExpanded
    }

    /// The month grid lives on the dashboard tab; the home page shows the
    /// agenda beside the player when the user wants it there.
    private var shouldShowCalendar: Bool {
        Defaults[.showCalendar]
    }

    /// Opt-in, and only while a pair is connected. `ContentView` sizes the notch
    /// off the same `widgetShowing`, so the page and the notch agree.
    private var shouldShowAirPods: Bool {
        pods.widgetShowing
    }

    private var mainContent: some View {
        HStack(alignment: .top, spacing: (shouldShowCamera && shouldShowCalendar) ? 10 : 15) {
            MusicPlayerView(albumArtNamespace: albumArtNamespace)

            if shouldShowAirPods {
                AirPodsWidgetView()
                    .frame(width: airPodsWidgetWidth)
                    .transition(.opacity)
            }

            if shouldShowCalendar {
                CalendarView()
                    .frame(width: shouldShowCamera ? 170 : 215)
                    .onHover { isHovering in
                        vm.isHoveringCalendar = isHovering
                    }
                    .environmentObject(vm)
                    .transition(.opacity)
            }

            if shouldShowCamera {
                CameraPreviewView(webcamManager: webcamManager)
                    .scaledToFit()
                    .opacity(vm.notchState == .closed ? 0 : 1)
                    .blur(radius: vm.notchState == .closed ? 20 : 0)
                    .animation(.interactiveSpring(response: 0.32, dampingFraction: 0.76, blendDuration: 0), value: shouldShowCamera)
            }
        }
        .animation(.smooth(duration: 0.3), value: shouldShowAirPods)
        // No transition of its own: the page slide at the call site owns how
        // this arrives, and a .move(edge: .top) here fought it, which is why
        // home dropped in from above while the other tabs slid sideways.
        .blur(radius: vm.notchState == .closed ? 30 : 0)
    }
}

struct MusicSliderView: View {
    @Binding var sliderValue: Double
    @Binding var duration: Double
    @Binding var lastDragged: Date
    var color: NSColor
    @Binding var dragging: Bool
    let currentDate: Date
    let timestampDate: Date
    let elapsedTime: Double
    let playbackRate: Double
    let isPlaying: Bool
    var onValueChange: (Double) -> Void


    var body: some View {
        VStack {
            CustomSlider(
                value: $sliderValue,
                range: 0...duration,
                color: Defaults[.sliderColor] == SliderColorEnum.albumArt
                    ? Color(nsColor: color).ensureMinimumBrightness(factor: 0.8)
                    : Defaults[.sliderColor] == SliderColorEnum.accent ? .effectiveAccent : .white,
                dragging: $dragging,
                lastDragged: $lastDragged,
                onValueChange: onValueChange
            )
            .frame(height: 10, alignment: .center)

            HStack {
                Text(timeString(from: sliderValue))
                Spacer()
                Text(timeString(from: duration))
            }
            .fontWeight(.medium)
            .foregroundColor(
                Defaults[.playerColorTinting]
                    ? Color(nsColor: color).ensureMinimumBrightness(factor: 0.6) : .gray
            )
            .font(.caption)
        }
        .onChange(of: currentDate) {
           guard !dragging, timestampDate.timeIntervalSince(lastDragged) > -1 else { return }
            sliderValue = MusicManager.shared.estimatedPlaybackPosition(at: currentDate)
        }
    }

    func timeString(from seconds: Double) -> String {
        let totalMinutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        } else {
            return String(format: "%d:%02d", minutes, remainingSeconds)
        }
    }
}

struct CustomSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var color: Color = .white
    @Binding var dragging: Bool
    @Binding var lastDragged: Date
    var onValueChange: ((Double) -> Void)?
    var onDragChange: ((Double) -> Void)?

    /// Clear unless the user asked for the glow, so the shadow costs nothing
    /// when it is off.
    private var glowColor: Color {
        Defaults[.sliderGlow] ? color.ensureMinimumBrightness(factor: 0.7) : .clear
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = CGFloat(dragging ? 9 : 5)
            let rangeSpan = range.upperBound - range.lowerBound

            let progress = rangeSpan == .zero ? 0 : (value - range.lowerBound) / rangeSpan
            let filledTrackWidth = min(max(progress, 0), 1) * width

            // Capsules rather than rectangles clipped by an outer
            // .cornerRadius: that clip sat outside the fill and swallowed the
            // glow, which is drawn beyond the bar's own bounds by definition.
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.gray.opacity(0.3))
                    .frame(height: height)

                Capsule()
                    .fill(color)
                    .frame(width: filledTrackWidth, height: height)
                    // Two passes: a tight bright bloom over a wide soft one, so
                    // it reads as light coming off the bar rather than a blur.
                    .shadow(color: glowColor.opacity(0.9), radius: 4)
                    .shadow(color: glowColor.opacity(0.55), radius: 10, x: 3)
            }
            .frame(height: 10)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        withAnimation {
                            dragging = true
                        }
                        let newValue = range.lowerBound + Double(gesture.location.x / width) * rangeSpan
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                        onDragChange?(value)
                    }
                    .onEnded { _ in
                        onValueChange?(value)
                        dragging = false
                        lastDragged = Date()
                    }
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: dragging)
        }
    }
}

// MARK: - Track change

/// Blur, fade and a touch of scale, on the way in and on the way out.
private struct ArtworkBlur: ViewModifier {
    let blur: CGFloat
    let opacity: Double
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .opacity(opacity)
            .scaleEffect(scale)
    }
}

private extension AnyTransition {
    /// The old cover softens, shrinks slightly and fades; the new one comes into
    /// focus from slightly large. Opposite scales, so the two read as one cover
    /// being replaced rather than two images cross-fading.
    static var artworkBlur: AnyTransition {
        let settled = ArtworkBlur(blur: 0, opacity: 1, scale: 1)
        return .asymmetric(
            insertion: .modifier(active: ArtworkBlur(blur: 16, opacity: 0, scale: 1.06), identity: settled),
            removal: .modifier(active: ArtworkBlur(blur: 16, opacity: 0, scale: 0.94), identity: settled))
    }

    /// The same change for the closed notch's cover, where 16 points of blur
    /// would wipe out a twenty-point image before it began.
    static var closedArtworkBlur: AnyTransition {
        let settled = ArtworkBlur(blur: 0, opacity: 1, scale: 1)
        return .asymmetric(
            insertion: .modifier(active: ArtworkBlur(blur: 4, opacity: 0, scale: 1.15), identity: settled),
            removal: .modifier(active: ArtworkBlur(blur: 4, opacity: 0, scale: 0.85), identity: settled))
    }
}

/// The artwork turning over to the next track, like something liquid.
///
/// One continuous angle drives the turn, and everything the cover does is
/// worked out from it on every frame - which face it shows, how it leans and
/// stretches, where the glint is - so nothing stalls or falls out of step.
///
/// The choreography: it sinks well back; starts turning while still sinking;
/// swells past full size as it comes round; and lands with a jelly wobble,
/// squashing one way then the other as it settles.
private struct FlippingArtwork: View {
    let image: NSImage
    let cornerRadius: CGFloat

    @State private var current: NSImage
    @State private var previous: NSImage
    /// Half-turns asked for so far. At rest the angle is exactly this many
    /// half-turns, and the cover is `current`.
    @State private var turns = 0
    @State private var angle: Double = 0
    @State private var scale: CGFloat = 1
    /// The landing wobble: 1 is squashed wide, 0 at rest, and the spring back to
    /// 0 is loose enough to swing past it a few times.
    @State private var jelly: Double = 0
    @State private var choreography: Task<Void, Never>?

    init(image: NSImage, cornerRadius: CGFloat) {
        self.image = image
        self.cornerRadius = cornerRadius
        _current = State(initialValue: image)
        _previous = State(initialValue: image)
    }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .modifier(TurningCover(
                angle: angle, jelly: jelly, turns: turns,
                current: current, previous: previous, cornerRadius: cornerRadius))
            .scaleEffect(scale)
            .onChange(of: ObjectIdentifier(image)) { _, _ in turn(to: image) }
    }

    private func turn(to next: NSImage) {
        // Swapped before the angle moves: until it passes the edge, the angle
        // still says "previous", so there is no frame of the new cover early.
        previous = current
        current = next
        turns += 1

        // Sink well back - quick, so it leads the turn.
        withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) { scale = 0.74 }

        // The turn, one spring from face to face. A second skip mid-turn only
        // retargets it, carrying the speed it already has.
        withAnimation(.spring(response: 0.62, dampingFraction: 0.72).delay(0.05)) {
            angle = Double(turns) * 180
        }

        choreography?.cancel()
        choreography = Task { @MainActor in
            // Swell past full size as it comes round...
            try? await Task.sleep(for: .milliseconds(170))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) { scale = 1.08 }

            // ...then settle to size, squashing as it lands...
            try? await Task.sleep(for: .milliseconds(230))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { scale = 1 }
            withAnimation(.spring(response: 0.12, dampingFraction: 1)) { jelly = 1 }

            // ...and wobble out of it.
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.28)) { jelly = 0 }
        }
    }
}

/// The cover at a given angle and wobble, recomputed on every frame.
private struct TurningCover: ViewModifier, Animatable {
    var angle: Double
    var jelly: Double
    let turns: Int
    let current: NSImage
    let previous: NSImage
    let cornerRadius: CGFloat

    var animatableData: AnimatablePair<Double, Double> {
        get { .init(angle, jelly) }
        set {
            angle = newValue.first
            jelly = newValue.second
        }
    }

    func body(content: Content) -> some View {
        // Which half-turn the card is nearest, counting the edge as the switch.
        let halfTurns = Int(((angle + 90) / 180).rounded(.down))
        let face = halfTurns >= turns ? current : previous
        let radians = angle * .pi / 180
        // 0 facing front, 1 edge-on.
        let edge = abs(sin(radians))
        // Position within the nearest half-turn: -0.5 just past the edge,
        // 0 facing front.
        let phase = angle / 180 - Double(halfTurns)
        // The glint crosses while the new face turns towards you.
        let glint = phase <= 0 ? 1 + phase * 4 : 1
        // The top leads the bottom into the turn and trails it out: gone facing
        // front and edge-on, strongest in between. It is what makes the cover
        // pour round rather than pivot on a rod.
        let lean = CGFloat(0.1 * sin(2 * radians))
        // An odd number of half-turns shows the card from behind; mirror the
        // picture back so the cover reads the right way.
        let mirror: CGFloat = halfTurns % 2 == 0 ? 1 : -1
        let stretchX = CGFloat(1 + 0.07 * jelly)
        let stretchY = CGFloat((1 - 0.07 * jelly) * (1 + 0.12 * edge))

        return content
            .overlay {
                Image(nsImage: face)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .overlay { Self.glint(at: glint) }
                    // Rounder in motion, like a drop drawing in.
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius + 24 * edge, style: .continuous))
                    .blur(radius: 3 * edge)
                    .scaleEffect(x: mirror * stretchX, y: stretchY)
                    .modifier(Lean(amount: lean))
            }
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
    }

    /// A diagonal band of light. -1 is off the left edge, 1 off the right.
    private static func glint(at position: Double) -> some View {
        GeometryReader { proxy in
            LinearGradient(
                colors: [.clear, .white.opacity(0.45), .clear],
                startPoint: .leading, endPoint: .trailing)
                .frame(width: proxy.size.width * 0.5, height: proxy.size.height * 1.6)
                .rotationEffect(.degrees(18))
                .position(
                    x: proxy.size.width / 2 + position * proxy.size.width * 0.95,
                    y: proxy.size.height / 2)
                .blendMode(.screen)
        }
        .allowsHitTesting(false)
    }
}

/// A horizontal shear about the middle: the top slides one way, the bottom the other.
private struct Lean: GeometryEffect {
    var amount: CGFloat

    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(
            a: 1, b: 0, c: amount, d: 1, tx: -amount * size.height / 2, ty: 0))
    }
}

// MARK: - Closed notch

/// The cover in the closed notch, changing over the way the open notch's does -
/// the blur scaled down, or the flip cut down to what reads at twenty points -
/// and giving off a flash of the new cover's colour as it lands.
struct ClosedNotchArtwork: View {
    @ObservedObject private var musicManager = MusicManager.shared
    @Default(.trackChangeAnimation) private var trackChangeAnimation
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            switch trackChangeAnimation {
            case .blur:
                Image(nsImage: musicManager.albumArt)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .id(ObjectIdentifier(musicManager.albumArt))
                    .transition(.closedArtworkBlur)
            case .flip:
                MiniFlippingArtwork(image: musicManager.albumArt, cornerRadius: cornerRadius)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(
            trackChangeAnimation == .blur ? .smooth(duration: 0.45) : nil,
            value: ObjectIdentifier(musicManager.albumArt))
        .modifier(TrackChangeGlow(
            trigger: ObjectIdentifier(musicManager.albumArt),
            color: Color(nsColor: musicManager.avgColor)))
    }
}

/// `FlippingArtwork` cut down for the closed notch. At that size the sink, the
/// glint and the jelly are lost, so it is the turn and a small pop as it lands.
private struct MiniFlippingArtwork: View {
    let image: NSImage
    let cornerRadius: CGFloat

    @State private var current: NSImage
    @State private var previous: NSImage
    @State private var turns = 0
    @State private var angle: Double = 0
    @State private var scale: CGFloat = 1
    @State private var landing: Task<Void, Never>?

    init(image: NSImage, cornerRadius: CGFloat) {
        self.image = image
        self.cornerRadius = cornerRadius
        _current = State(initialValue: image)
        _previous = State(initialValue: image)
    }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .modifier(MiniTurningCover(
                angle: angle, turns: turns, current: current, previous: previous,
                cornerRadius: cornerRadius))
            .scaleEffect(scale)
            .onChange(of: ObjectIdentifier(image)) { _, _ in turn(to: image) }
    }

    private func turn(to next: NSImage) {
        previous = current
        current = next
        turns += 1

        withAnimation(.spring(response: 0.18, dampingFraction: 0.9)) { scale = 0.8 }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
            angle = Double(turns) * 180
        }

        landing?.cancel()
        landing = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.45)) { scale = 1 }
        }
    }
}

/// The small cover at a given angle, recomputed on every frame, with the same
/// face rule as `TurningCover`.
private struct MiniTurningCover: ViewModifier, Animatable {
    var angle: Double
    let turns: Int
    let current: NSImage
    let previous: NSImage
    let cornerRadius: CGFloat

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        let halfTurns = Int(((angle + 90) / 180).rounded(.down))
        let face = halfTurns >= turns ? current : previous
        let mirror: CGFloat = halfTurns % 2 == 0 ? 1 : -1
        let edge = abs(sin(angle * .pi / 180))

        return content
            .overlay {
                Image(nsImage: face)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    // Darker edge-on, as if turning away from the light.
                    .brightness(-0.3 * edge)
                    .scaleEffect(x: mirror, y: 1)
            }
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
    }
}

/// A flash of the new cover's colour: a halo that blooms and fades, and a lift
/// in brightness on whatever it wraps. Keyed on the artwork, like the change
/// itself, and coloured by `avgColor`, which catches up while it fades.
struct TrackChangeGlow: ViewModifier {
    let trigger: ObjectIdentifier
    let color: Color
    var radius: CGFloat = 7

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, glow in
            view
                .shadow(color: color.opacity(0.95 * glow), radius: radius * glow)
                .brightness(0.2 * glow)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(1, duration: 0.16)
                CubicKeyframe(0, duration: 0.9)
            }
        }
    }
}

/// The artwork's clip: the rounded cover, or - for the flip - its frame with a
/// generous margin, so the cover can overshoot and wobble without being cut.
private struct ArtworkClip: Shape {
    let cornerRadius: CGFloat
    let clips: Bool

    func path(in rect: CGRect) -> Path {
        guard clips else {
            return Path(rect.insetBy(dx: -rect.width * 0.3, dy: -rect.height * 0.3))
        }
        return RoundedRectangle(cornerRadius: cornerRadius).path(in: rect)
    }
}
