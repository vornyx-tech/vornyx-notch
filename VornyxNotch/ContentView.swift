//
//  ContentView.swift
//  VornyxNotchApp
//
//  Created by Harsh Vardhan Goswami  on 02/08/24
//  Modified by Richard Kunkli on 24/08/2024.
//

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI
import SwiftUIIntrospect

@MainActor
struct ContentView: View {
    @EnvironmentObject var vm: VornyxViewModel
    @ObservedObject var webcamManager = WebcamManager.shared

    @ObservedObject var coordinator = VornyxViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var brightnessManager = BrightnessManager.shared
    @ObservedObject var volumeManager = VolumeManager.shared
    @ObservedObject var countdown = CountdownManager.shared
    @ObservedObject var localSend = LocalSendManager.shared
    @ObservedObject var pods = AirPodsManager.shared
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var resizeHoldTask: Task<Void, Never>?
    /// Until when a hover exit must not close the notch.
    ///
    /// The notch resizes itself - the clipboard opening a row, the dashboard
    /// stretching around a long reply - and a resize moves the edge out from
    /// under a pointer that never moved. AppKit re-evaluates the tracking area
    /// and reports an exit, and the notch closes on a gesture the user did not
    /// make. Closing a clipboard row with the up arrow did exactly this.
    @State private var suppressHoverCloseUntil: Date = .distantPast
    /// True while the pointer sits over a part of the page that scrolls itself.
    ///
    /// The close gesture is a scroll monitor that sees the whole window, so
    /// scrolling a chat transcript or the clipboard row was closing the notch
    /// instead of scrolling it. Only the views that actually scroll claim the
    /// gesture, via `scrollableNotchContent()` - over the month grid, the
    /// shortcuts or the player there is nothing to scroll, so a swipe there
    /// closes the notch like a swipe over the header.
    @State private var pointerOverContent: Bool = false

    /// Height the dashboard has grown by to show more of a long AI transcript.
    ///
    /// Zero for every other tab, and reset whenever the notch closes or the tab
    /// changes, so a page always opens at its natural size and grows from there.
    @State private var dashboardGrowth: CGFloat = 0
    @State private var anyDropDebounceTask: Task<Void, Never>?
    /// Holds the LocalSend strip up for the length of a drag on tabs other than
    /// the shelf, and a moment after. See `updateLocalSendDragPin`.
    @State private var localSendDragPinned: Bool = false
    @State private var localSendLingerTask: Task<Void, Never>?

    @State private var gestureProgress: CGFloat = .zero

    @State private var haptics: Bool = false

    @Namespace var albumArtNamespace

    @Default(.useMusicVisualizer) var useMusicVisualizer

    @Default(.showNotHumanFace) var showNotHumanFace

    @Default(.clipboardEnabled) var clipboardEnabled
    @Default(.aiEnabled) var aiEnabled
    @Default(.showMirror) var showMirror
    @Default(.mirrorDisplayMode) var mirrorDisplayMode
    @Default(.mirrorBigScreenHeight) var mirrorBigScreenHeight
    @Default(.localSendEnabled) var localSendEnabled

    // Shared interactive spring for movement/resizing to avoid conflicting animations
    private let animationSpring = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)

    private let extendedHoverPadding: CGFloat = 30
    private let zeroHeightHoverPadding: CGFloat = 10

    private var usesOpenedRadii: Bool {
        vm.notchState == .open
    }

    private var topCornerRadius: CGFloat {
        usesOpenedRadii
            ? cornerRadiusInsets.opened.top
            : cornerRadiusInsets.closed.top
    }

    private var currentNotchBottomRadius: CGFloat {
        usesOpenedRadii ? cornerRadiusInsets.opened.bottom : cornerRadiusInsets.closed.bottom
    }

    private var currentNotchShape: NotchShape {
        NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: usesOpenedRadii
                ? cornerRadiusInsets.opened.bottom
                : cornerRadiusInsets.closed.bottom
        )
    }

    private var computedChinWidth: CGFloat {
        var chinWidth: CGFloat = vm.closedNotchSize.width

        if coordinator.expandingView.type == .battery && coordinator.expandingView.show
            && vm.notchState == .closed && Defaults[.showPowerStatusNotifications]
        {
            chinWidth = 640
        } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .music)
            && vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle)
            && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed
        {
            chinWidth += (2 * max(0, vm.effectiveClosedNotchHeight - 12) + 20)
        } else if !coordinator.expandingView.show && vm.notchState == .closed
            && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace]
            && !vm.hideOnClosed
        {
            chinWidth += (2 * max(0, vm.effectiveClosedNotchHeight - 12) + 20)
        }

        return chinWidth
    }

    var body: some View {
        // Calculate scale based on gesture progress only
        let gestureScale: CGFloat = {
            guard gestureProgress != 0 else { return 1.0 }
            let scaleFactor = 1.0 + gestureProgress * 0.01
            return max(0.6, scaleFactor)
        }()
        
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                let mainLayout = NotchLayout()
                    .frame(alignment: .top)
                    .padding(
                        .horizontal,
                        vm.notchState == .open
                        ? cornerRadiusInsets.opened.top
                        : cornerRadiusInsets.closed.bottom
                    )
                    .padding([.horizontal, .bottom], vm.notchState == .open ? 12 : 0)
                    // Height belongs here, with the width and *before* the
                    // background: the black shape and its corner curve are then
                    // drawn at the notch's real size. Sizing only the outer
                    // frame let a tab that overflowed - the AI transcript did -
                    // stretch the silhouette far below the region that tracks
                    // the mouse, so the curve landed off-notch and the pointer
                    // fell out of the hover area without ever leaving the black.
                    .frame(
                        width: vm.notchState == .open
                            ? openNotchWidth(for: coordinator.currentView, showingAirPods: pods.widgetShowing)
                            : nil,
                        height: vm.notchState == .open ? openNotchContentHeight : nil,
                        alignment: .top
                    )
                    // Black, or Liquid Glass under a black band that hides in
                    // the hardware notch - see `NotchBackground`.
                    .background {
                        NotchBackground(
                            isOpen: vm.notchState == .open,
                            blackBandHeight: max(vm.effectiveClosedNotchHeight, 24),
                            topRadius: topCornerRadius,
                            bottomRadius: currentNotchBottomRadius)
                    }
                    .clipShape(currentNotchShape)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(.black)
                            .frame(height: 1)
                            .padding(.horizontal, topCornerRadius)
                    }
                    .shadow(
                        color: ((vm.notchState == .open || isHovering) && Defaults[.enableShadow])
                            ? .black.opacity(0.7) : .clear, radius: 6
                    )
                    .overlay {
                        NotchEdgeLight(
                            shape: currentNotchShape, isOpen: vm.notchState == .open)
                    }
                    .padding(
                        .bottom,
                        vm.effectiveClosedNotchHeight == 0 ? 10 : 0
                    )
                
                // No height here: mainLayout is already exactly the notch's
                // size, so letting it report that size keeps the hover region
                // below in step with what is actually drawn.
                mainLayout
                    .conditionalModifier(true) { view in
                        let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
                        let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)
                        
                        return view
                            .animation(vm.notchState == .open ? openAnimation : closeAnimation, value: vm.notchState)
                            .animation(.smooth, value: gestureProgress)
                            // The width change on a tab switch is a resize like
                            // any other, so it rides the same spring.
                            .animation(notchResizeAnimation, value: coordinator.currentView)
                            // The notch growing/shrinking for the big screen mirror.
                            .animation(notchResizeAnimation, value: showsBigScreenMirror)
                            .animation(notchResizeAnimation, value: pods.widgetShowing)
                            .animation(notchResizeAnimation, value: openNotchContentHeight)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        doOpen()
                    }
                    .conditionalModifier(Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .down) { translation, phase in
                                handleDownGesture(translation: translation, phase: phase)
                            }
                    }
                    .conditionalModifier(Defaults[.closeGestureEnabled] && Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .up) { translation, phase in
                                handleUpGesture(translation: translation, phase: phase)
                            }
                    }
                    // The pointer's margin of error around the open notch, as
                    // transparent padding wrapped *around* the notch rather
                    // than a backdrop behind it: the notch paints an opaque
                    // background, and hit testing runs front to back, so
                    // anything behind it never sees the pointer. Wrapped, it
                    // does - onHover reports for a view's descendants too.
                    //
                    // Outside the gestures above, so a swipe still has to start
                    // on the notch itself. Zero when closed, where the region
                    // has to stay exactly the notch or hover-to-open would fire
                    // from the menu bar beside it.
                    .padding(.horizontal, hoverSlack)
                    .padding(.bottom, hoverSlack)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        handleHover(hovering)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
                        if vm.notchState == .open && !isHovering && !vm.isBatteryPopoverActive {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if self.vm.notchState == .open && !self.isHovering && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: vm.notchState) { _, newState in
                        if newState == .closed && isHovering {
                            withAnimation {
                                isHovering = false
                            }
                        }
                        if newState == .closed {
                            dashboardGrowth = 0
                            pointerOverContent = false
                        }
                    }
                    .onChange(of: coordinator.currentView) {
                        // Switching tabs never fires a hover exit, and the new
                        // page starts at its own height rather than the last
                        // one's.
                        dashboardGrowth = 0
                        pointerOverContent = false
                    }
                    .onChange(of: vm.isBatteryPopoverActive) {
                        if !vm.isBatteryPopoverActive && !isHovering && vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if !self.vm.isBatteryPopoverActive && !self.isHovering && self.vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .sensoryFeedback(.alignment, trigger: haptics)
                    .contextMenu {
                        Button("Settings") {
                            DispatchQueue.main.async {
                                SettingsWindowController.shared.showWindow()
                            }
                        }
                        .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
                        //                    Button("Edit") { // Doesnt work....
                        //                        let dn = DynamicNotch(content: EditPanelView())
                        //                        dn.toggle()
                        //                    }
                        //                    .keyboardShortcut("E", modifiers: .command)
                    }
                if vm.chinHeight > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.01))
                        .frame(width: computedChinWidth, height: vm.chinHeight)
                }
            }
        }
        .padding(.bottom, 8)
        .frame(maxWidth: windowSize.width, maxHeight: windowSize.height, alignment: .top)
        .compositingGroup()
        .scaleEffect(
            x: gestureScale,
            y: gestureScale,
            anchor: .top
        )
        .animation(.smooth, value: gestureProgress)
        .background(dragDetector)
        .preferredColorScheme(.dark)
        .environmentObject(vm)
        .onChange(of: vm.anyDropZoneTargeting) { _, isTargeted in
            anyDropDebounceTask?.cancel()

            if isTargeted {
                if vm.notchState == .closed {
                    coordinator.currentView = .shelf
                    doOpen()
                }
                return
            }

            anyDropDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                if vm.dropEvent {
                    vm.dropEvent = false
                    return
                }

                vm.dropEvent = false
                if !SharingStateManager.shared.preventNotchClose {
                    vm.close()
                }
            }
        }
    }

    /// A sneak peek pins the layout to its own size: a standard-style music
    /// peek, or any non-music peek, while the notch is closed.
    private var sneakPeekUsesFixedSize: Bool {
        let peek = coordinator.sneakPeek
        guard peek.show, vm.notchState == .closed else { return false }
        if peek.type == .music {
            return !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard
        }
        return true
    }

    /// The closed notch's banners, and the header once it opens.
    ///
    /// LocalSend is checked first and on its own. Added as one more arm of the
    /// chain, it pushed that expression past what the type checker will solve
    /// in reasonable time; wrapped around it, the chain stays exactly as it
    /// compiled before.
    @ViewBuilder
    private func closedNotchContent() -> some View {
        // Ahead of the other banners: an offer is someone waiting on an
        // answer, and the rest are only news.
        if showsLocalSendBanner {
            LocalSendLiveActivity()
                .environmentObject(vm)
                .transition(.opacity)
        } else {
            notchBannerChain()
        }
    }

    @ViewBuilder
    private func notchBannerChain() -> some View {
        if coordinator.expandingView.type == .battery && coordinator.expandingView.show
            && vm.notchState == .closed && Defaults[.showPowerStatusNotifications]
        {
            HStack(spacing: 0) {
                HStack {
                    Text(batteryModel.statusText)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                }

                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width + 10)

                HStack {
                    VornyxBatteryView(
                        batteryWidth: 30,
                        isCharging: batteryModel.isCharging,
                        isInLowPowerMode: batteryModel.isInLowPowerMode,
                        isPluggedIn: batteryModel.isPluggedIn,
                        levelBattery: batteryModel.levelBattery,
                        isForNotification: true
                    )
                }
                .frame(width: 76, alignment: .trailing)
            }
            .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
          } else if coordinator.expandingView.type == .airpods && coordinator.expandingView.show
                      && vm.notchState == .closed && !vm.hideOnClosed && Defaults[.airPodsSneakPeek] {
              AirPodsLiveActivity()
                  .environmentObject(vm)
                  .transition(.opacity)
          // A running countdown outranks the banner's own timeout:
          // it stays for as long as it is counting, rather than
          // showing for three seconds and leaving.
          } else if countdown.isActive && vm.notchState == .closed && !vm.hideOnClosed
                      && Defaults[.timerLiveActivity] {
              TimerLiveActivity()
                  .environmentObject(vm)
                  .transition(.opacity)
          } else if coordinator.expandingView.type == .timer && coordinator.expandingView.show
                      && vm.notchState == .closed && !vm.hideOnClosed {
              TimerLiveActivity()
                  .environmentObject(vm)
                  .transition(.opacity)
          } else if coordinator.sneakPeek.show && Defaults[.inlineHUD] && (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && (coordinator.sneakPeek.type != .audioRoute) && vm.notchState == .closed {
              InlineHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, hoverAnimation: $isHovering, gestureProgress: $gestureProgress)
                  .transition(.opacity)
          } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .music) && vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle) && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed {
              MusicLiveActivity()
                  .frame(alignment: .center)
          } else if !coordinator.expandingView.show && vm.notchState == .closed && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace] && !vm.hideOnClosed  {
              VornyxFaceAnimation()
           } else if vm.notchState == .open {
               VornyxHeader()
                   .frame(height: max(24, vm.effectiveClosedNotchHeight))
                   .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
           } else {
               Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
           }
    }

    /// Pins the strip when a drag arrives, and lets go only a moment after the
    /// last one leaves.
    ///
    /// Reading `anyDropZoneTargeting` directly was the bug: the flag drops to
    /// false for a frame each time the pointer passes from one drop target to
    /// the next, the strip vanished in that frame, the notch shrank under the
    /// pointer, and the device being aimed at went with it.
    private func updateLocalSendDragPin(dragging: Bool) {
        localSendLingerTask?.cancel()
        guard !dragging else {
            localSendDragPinned = true
            return
        }
        localSendLingerTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            localSendDragPinned = false
        }
    }

    /// The open notch's page, with the mirror and the LocalSend strip under it
    /// when they are showing. Its own function for the same reason as
    /// `closedNotchContent`: inline, `NotchLayout` outgrew the type checker.
    @ViewBuilder
    private func openNotchStack() -> some View {
        VStack(spacing: 8) {
            ZStack {
                tabContent(for: coordinator.currentView)
                    .id(coordinator.currentView)
                    .transition(pageTransition)
            }
            // No .clipped() here: the album art's lighting effect is a
            // blurred, oversized copy of the artwork that deliberately
            // bleeds past the content bounds. mainLayout already clips
            // everything to the notch silhouette, so clipping again here
            // only cuts the glow.
            .animation(VornyxViewCoordinator.tabChangeAnimation, value: coordinator.currentView)
            // Pages claim the scroll gesture per region rather than
            // wholesale; see `scrollableNotchContent()`.
            .environment(\.notchScrollableHover, $pointerOverContent)
            .onPreferenceChange(NotchContentFitKey.self) { fit in
                applyContentFit(fit)
            }

            if showsBigScreenMirror {
                BigScreenMirrorView(
                    webcamManager: webcamManager,
                    height: Defaults[.mirrorBigScreenHeight]
                        .clamped(to: mirrorBigScreenHeightRange)
                )
                .environmentObject(vm)
                .transition(
                    .move(edge: .top)
                        .combined(with: .opacity)
                        .combined(with: .scale(scale: 0.96, anchor: .top))
                )
            }

            if showsLocalSendStrip {
                LocalSendStrip()
                    .environmentObject(vm)
                    .transition(
                        .move(edge: .top)
                            .combined(with: .opacity)
                            .combined(with: .scale(scale: 0.96, anchor: .top))
                    )
            }
        }
        .animation(VornyxViewCoordinator.tabChangeAnimation, value: showsBigScreenMirror)
        .animation(VornyxViewCoordinator.tabChangeAnimation, value: showsLocalSendStrip)
        // Here rather than on `NotchLayout`: both only matter while the notch
        // is open, and that modifier chain is already at the type checker's limit.
        .onChange(of: showsLocalSendStrip) { _, _ in holdOpenAfterResize() }
        .onChange(of: vm.anyDropZoneTargeting) { _, dragging in updateLocalSendDragPin(dragging: dragging) }
        // A pair connecting or going widens or narrows the home page.
        .onChange(of: pods.widgetShowing) { _, _ in holdOpenAfterResize() }
    }

    @ViewBuilder
    func NotchLayout() -> some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                if coordinator.helloAnimationRunning {
                    // No spacers here: the greeting runs while the notch is
                    // closed, where the layout takes its height from content.
                    // A spacer would take the whole window and hang the notch
                    // halfway down the screen.
                    LogoAnimation(onFinish: {
                        vm.closeHello()
                    }).frame(
                        width: getClosedNotchSize().width,
                        height: 72
                    )
                    // Clears the hardware notch: the top of the shape is behind
                    // the camera housing, so the logo starts below it.
                    .padding(.top, vm.effectiveClosedNotchHeight + 16)
                    .padding(.bottom, 24)
                } else {
                    closedNotchContent()

                      if coordinator.sneakPeek.show {
                          if (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && (coordinator.sneakPeek.type != .audioRoute) && !Defaults[.inlineHUD] && vm.notchState == .closed {
                              SystemEventIndicatorModifier(
                                  eventType: $coordinator.sneakPeek.type,
                                  value: $coordinator.sneakPeek.value,
                                  icon: $coordinator.sneakPeek.icon,
                                  sendEventBack: { newVal in
                                      switch coordinator.sneakPeek.type {
                                      case .volume:
                                          VolumeManager.shared.setAbsolute(Float32(newVal))
                                      case .brightness:
                                          BrightnessManager.shared.setAbsolute(value: Float32(newVal))
                                      default:
                                          break
                                      }
                                  }
                              )
                              .padding(.bottom, 10)
                              .padding(.leading, 4)
                              .padding(.trailing, 8)
                          }
                          // Sound moved somewhere else: dropped down under the
                          // notch, the way the music sneak peek is.
                          else if coordinator.sneakPeek.type == .audioRoute {
                              if vm.notchState == .closed && !vm.hideOnClosed && Defaults[.audioRouteSneakPeek] {
                                  AudioRouteSneakPeek()
                              }
                          }
                          // Old sneak peek music
                          else if coordinator.sneakPeek.type == .music {
                              if vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard {
                                  HStack(alignment: .center) {
                                      Image(systemName: "music.note")
                                      GeometryReader { geo in
                                          MarqueeText(.constant(musicManager.songTitle + " - " + musicManager.artistName),  textColor: Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray, minDuration: 1, frameWidth: geo.size.width)
                                      }
                                  }
                                  .foregroundStyle(.gray)
                                  .padding(.bottom, 10)
                              }
                          }
                      }
                  }
              }
              .conditionalModifier(sneakPeekUsesFixedSize) { view in
                  view
                      .fixedSize()
              }
              .zIndex(2)
            if vm.notchState == .open {
                openNotchStack()
                .transition(
                    .scale(scale: 0.8, anchor: .top)
                    .combined(with: .opacity)
                    .animation(.smooth(duration: 0.35))
                )
                .zIndex(1)
                .allowsHitTesting(vm.notchState == .open)
                .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
            }
        }
        // Keys that belong to the notch rather than to whichever page is
        // showing, so they keep working as you step between tabs.
        .onKeyDown(enabled: vm.notchState == .open, handleNotchKey)
        // The open notch answers the keyboard however it was opened - hovered,
        // clicked or shortcut - because Command-arrow has to work from the tab
        // you are already looking at, not only from one you opened by keyboard.
        //
        // Taking key status is what makes that possible, and the panel is
        // non-activating so the app underneath stays frontmost. It does mean
        // the open notch holds the keyboard, which is why this is tied to the
        // notch being open: it closes when the pointer leaves, and the keyboard
        // goes straight back.
        .onChange(of: vm.notchState) { _, state in
            state == .open
                ? VornyxNotchSkyLightWindow.takeKeyboardFocus()
                : endKeyboardSession()
        }
        // Every way the notch changes its own size, so none of them can be
        // mistaken for the pointer leaving.
        .onChange(of: coordinator.currentView) { _, _ in holdOpenAfterResize() }
        .onChange(of: coordinator.clipboardRows) { _, _ in holdOpenAfterResize() }
        .onChange(of: coordinator.localSendComposeGrowth) { _, _ in holdOpenAfterResize() }
        .onChange(of: dashboardGrowth) { _, _ in holdOpenAfterResize() }
        .onChange(of: showsBigScreenMirror) { _, _ in holdOpenAfterResize() }
        // The chat gives the keyboard back when it goes away; the notch is
        // still open, so take it again.
        .onChange(of: coordinator.currentView) { _, _ in
            guard vm.notchState == .open else { return }
            VornyxNotchSkyLightWindow.takeKeyboardFocus()
        }
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], delegate: GeneralDropTargetDelegate(isTargeted: $vm.generalDropTargeting))
        .onReceive(NotificationCenter.default.publisher(for: .localSendRevealShelf)) { _ in
            revealShelfForDelivery()
        }
        .onChange(of: clipboardEnabled) { _, enabled in
            if !enabled && coordinator.currentView == .clipboard {
                coordinator.currentView = .home
            }
        }
    }

    /// Command-left and Command-right step the tabs, and Escape puts the notch
    /// away - from any page, for as long as the notch is answering the keyboard.
    ///
    /// Command is the modifier because the plain arrows are already spoken for
    /// inside a page: the clipboard walks its cards with them.
    private func handleNotchKey(_ event: NSEvent) -> Bool {
        guard let key = NotchKey(event) else { return false }

        if event.modifierFlags.contains(.command) {
            switch key {
            case .leftArrow:
                stepTab(by: -1)
            case .rightArrow:
                stepTab(by: 1)
            default:
                return false
            }
            return true
        }

        guard key == .escape else { return false }
        vm.close()
        return true
    }

    private func stepTab(by offset: Int) {
        withAnimation(VornyxViewCoordinator.tabChangeAnimation) {
            coordinator.stepTab(by: offset)
        }
    }

    /// Hold the notch open for a moment after it resizes itself, then close it
    /// if the pointer never came back.
    ///
    /// The dashboard is far wider than the home page, so clicking home from the
    /// far side of it pulls the notch's edge past the pointer: the button you
    /// just clicked is now off-notch, the hover exit fires, and the notch shuts
    /// on you. Suppressing that exit alone is not enough - nothing would ever
    /// close it afterwards, since the exit already happened - so the hold ends
    /// by making the decision itself: on the notch, stay; not on it, close.
    ///
    /// Three seconds, because the pointer may have a long way to travel.
    ///
    /// A longer hold already running is kept, not cut short: opening the shelf
    /// for a delivery asks for longer, and the tab change it makes asks again
    /// for the usual three seconds a moment later.
    private func holdOpenAfterResize(for duration: TimeInterval = notchResizeGrace) {
        guard vm.notchState == .open else { return }
        let until = max(suppressHoverCloseUntil, Date().addingTimeInterval(duration))
        suppressHoverCloseUntil = until

        resizeHoldTask?.cancel()
        resizeHoldTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(max(0, until.timeIntervalSinceNow)))
            guard !Task.isCancelled,
                  vm.notchState == .open,
                  !isHovering,
                  // Driving from the keyboard: where the pointer sits is not an
                  // opinion about whether the notch should still be here.
                  !coordinator.keyboardSession,
                  !vm.isBatteryPopoverActive,
                  !SharingStateManager.shared.preventNotchClose,
                  // Mid-drag the pointer is on the notch, but hover is not
                  // tracked during a drag, so `isHovering` says it is not.
                  !vm.anyDropZoneTargeting
            else { return }
            vm.close()
        }
    }

    /// Files arrived over LocalSend: open on the shelf, where they flash, and
    /// stay long enough to be seen before closing again if the pointer is not
    /// on the notch.
    private func revealShelfForDelivery() {
        // One notch opens, not one per display: the one on the screen in use.
        if Defaults[.showOnAllDisplays] {
            let mouse = NSEvent.mouseLocation
            guard NSScreen.screens.first(where: { $0.frame.contains(mouse) })?.displayUUID == vm.screenUUID
            else { return }
        }
        // Mid-typing on another page, the page stays; the flash waits for the
        // next look at the shelf.
        guard !coordinator.keyboardSession || vm.notchState == .closed else { return }

        withAnimation(VornyxViewCoordinator.tabChangeAnimation) {
            coordinator.currentView = .shelf
        }
        if vm.notchState == .closed { doOpen() }
        holdOpenAfterResize(for: 5)
    }

    private func endKeyboardSession() {
        coordinator.keyboardSession = false
        VornyxNotchSkyLightWindow.setKeyboardInputEnabled(false)
    }

    /// Height of the visible notch when open. The window reserves room for the
    /// big-screen mirror up front, but the notch itself only stretches down
    /// once the mirror is actually showing.
    private var openNotchContentHeight: CGFloat {
        openNotchHeight(for: coordinator.currentView)
            + dashboardGrowth
            + clipboardGrowth
            + (showsBigScreenMirror
               ? mirrorBigScreenHeight.clamped(to: mirrorBigScreenHeightRange) + 8
               : 0)
            + (showsLocalSendStrip ? localSendStripHeight + coordinator.localSendComposeGrowth + 8 : 0)
    }

    /// Room for the clipboard's extra rows, which it opens out to on a press of
    /// the down arrow. Zero on every other tab, and zero on a one-row clipboard.
    private var clipboardGrowth: CGFloat {
        guard coordinator.currentView == .clipboard else { return 0 }
        return CGFloat(max(0, coordinator.clipboardRows - 1)) * clipboardRowGrowth
    }

    /// The most the dashboard may grow by, on top of its starting height.
    private var maxDashboardGrowth: CGFloat {
        max(0, dashboardNotchMaxHeight - dashboardNotchHeight)
    }

    /// Grow - or shrink - the notch so a page's content fits.
    ///
    /// The page reports how far its content overruns what is on screen, and
    /// that number is added to the growth already applied. One round settles
    /// it: growing by the shortfall makes the shortfall zero, and a page with
    /// room to spare reports a negative one and gives the height back. The
    /// dead band keeps the spring from chasing its own mid-animation frames.
    private func applyContentFit(_ fit: NotchContentFit) {
        guard vm.notchState == .open, coordinator.currentView == .dashboard else { return }

        let target = (dashboardGrowth + fit.shortfall).clamped(to: 0...maxDashboardGrowth)
        guard abs(target - dashboardGrowth) > notchGrowthDeadBand else { return }

        dashboardGrowth = target
    }

    /// The mirror panel that stretches the notch downwards, shown under any tab.
    private var showsBigScreenMirror: Bool {
        showMirror && mirrorDisplayMode == .bigScreen && vm.isCameraExpanded
            && webcamManager.cameraAvailable
    }

    /// Whether LocalSend has a transfer that needs to be seen.
    private var hasLocalSendActivity: Bool {
        localSend.pendingRequest != nil || localSend.incoming != nil || localSend.outgoing != nil
            || localSend.message != nil
    }

    /// The strip under the open notch: always on the shelf, where it can be
    /// found; on other tabs while a drag is pinning it; and anywhere for as
    /// long as a transfer needs it.
    private var showsLocalSendStrip: Bool {
        guard localSendEnabled, localSend.isRunning, vm.notchState == .open else { return false }
        return coordinator.currentView == .shelf || localSendDragPinned || hasLocalSendActivity
    }

    /// The banner in the closed notch. A separate property because the
    /// banner chain it sits in is already at the edge of what the type
    /// checker will solve in one expression.
    private var showsLocalSendBanner: Bool {
        localSendEnabled && vm.notchState == .closed && !vm.hideOnClosed && hasLocalSendActivity
    }

    @ViewBuilder
    private func tabContent(for view: NotchViews) -> some View {
        switch view {
        case .home:
            NotchHomeView(albumArtNamespace: albumArtNamespace)
        case .shelf:
            ShelfView()
        case .clipboard:
            ClipboardView()
        case .dashboard:
            DashboardView()
        }
    }

    /// Pages slide in from the side you are travelling towards, and leave the
    /// other way - so moving right feels like moving right.
    private var pageTransition: AnyTransition {
        let forward = coordinator.tabDirection >= 0
        return .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.94, anchor: forward ? .trailing : .leading)),
            removal: .move(edge: forward ? .leading : .trailing)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.94, anchor: forward ? .leading : .trailing))
        )
    }

    @ViewBuilder
    func VornyxFaceAnimation() -> some View {
        HStack {
            HStack {
                Rectangle()
                    .fill(.clear)
                    .frame(
                        width: max(0, vm.effectiveClosedNotchHeight - 12),
                        height: max(0, vm.effectiveClosedNotchHeight - 12)
                    )
                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width - 20)
                MinimalFaceFeatures()
            }
        }.frame(
            height: vm.effectiveClosedNotchHeight,
            alignment: .center
        )
    }

    @ViewBuilder
    func MusicLiveActivity() -> some View {
        HStack {
            ClosedNotchArtwork(cornerRadius: AlbumArtStyle.closedCornerRadius)
                .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                .frame(
                    width: max(0, vm.effectiveClosedNotchHeight - 12),
                    height: max(0, vm.effectiveClosedNotchHeight - 12)
                )

            Rectangle()
                .fill(.black)
                .overlay(
                    HStack(alignment: .top) {
                        if coordinator.expandingView.show
                            && coordinator.expandingView.type == .music
                        {
                            MarqueeText(
                                .constant(musicManager.songTitle),
                                textColor: Defaults[.coloredSpectrogram]
                                    ? Color(nsColor: musicManager.avgColor) : Color.gray,
                                minDuration: 0.4,
                                frameWidth: 100
                            )
                            .opacity(
                                (coordinator.expandingView.show
                                    && Defaults[.sneakPeekStyles] == .inline)
                                    ? 1 : 0
                            )
                            Spacer(minLength: vm.closedNotchSize.width)
                            // Song Artist
                            Text(musicManager.artistName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(
                                    Defaults[.coloredSpectrogram]
                                        ? Color(nsColor: musicManager.avgColor)
                                        : Color.gray
                                )
                                .opacity(
                                    (coordinator.expandingView.show
                                        && coordinator.expandingView.type == .music
                                        && Defaults[.sneakPeekStyles] == .inline)
                                        ? 1 : 0
                                )
                        }
                    }
                )
                .frame(
                    width: (coordinator.expandingView.show
                        && coordinator.expandingView.type == .music
                        && Defaults[.sneakPeekStyles] == .inline)
                        ? 380
                        : vm.closedNotchSize.width
                            + -cornerRadiusInsets.closed.top
                )

            HStack {
                if useMusicVisualizer {
                    Rectangle()
                        .fill(
                            Defaults[.coloredSpectrogram]
                                ? Color(nsColor: musicManager.avgColor).gradient
                                : Color.gray.gradient
                        )
                        .frame(width: 50, alignment: .center)
                        .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
                        .mask {
                            AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                                .frame(width: 16, height: 12)
                        }
                } else {
                    LottieAnimationContainer()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(
                width: max(
                    0,
                    vm.effectiveClosedNotchHeight - 12
                        + gestureProgress / 2
                ),
                height: max(
                    0,
                    vm.effectiveClosedNotchHeight - 12
                ),
                alignment: .center
            )
            .modifier(TrackChangeGlow(
                trigger: ObjectIdentifier(musicManager.albumArt),
                color: Color(nsColor: musicManager.avgColor),
                radius: 5))
        }
        .frame(
            height: vm.effectiveClosedNotchHeight,
            alignment: .center
        )
    }

    @ViewBuilder
    var dragDetector: some View {
        if Defaults[.shelfEnabled] && vm.notchState == .closed {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
            vm.dropEvent = true
            ShelfStateViewModel.shared.load(providers)
            return true
        }
        } else {
            EmptyView()
        }
    }

    private func doOpen() {
        withAnimation(animationSpring) {
            vm.open()
        }
    }

    // MARK: - Hover Management

    /// How far past the notch the pointer may stray before it counts as gone.
    ///
    /// Open, it is `openNotchHoverSlack` on the left, right and bottom, so
    /// clipping a corner on the way to a button no longer closes the notch out
    /// from under you. Never upwards - the notch's top edge is the screen's.
    /// Closed it is zero: hover-to-open must not fire from the menu bar.
    private var hoverSlack: CGFloat {
        vm.notchState == .open ? openNotchHoverSlack : 0
    }

    private func handleHover(_ hovering: Bool) {
        if coordinator.firstLaunch { return }
        hoverTask?.cancel()
        
        if hovering {
            withAnimation(animationSpring) {
                isHovering = true
            }
            
            if vm.notchState == .closed && Defaults[.enableHaptics] {
                haptics.toggle()
            }
            
            guard vm.notchState == .closed,
                  !coordinator.sneakPeek.show,
                  // A LocalSend banner has buttons to reach: moving the pointer
                  // onto Accept or Decline must not open the notch over them.
                  // Hover opens again once the banner has gone.
                  !showsLocalSendBanner,
                  Defaults[.openNotchOnHover] else { return }
            
            hoverTask = Task {
                try? await Task.sleep(for: .seconds(Defaults[.minimumHoverDuration]))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    guard self.vm.notchState == .closed,
                          self.isHovering,
                          !self.coordinator.sneakPeek.show,
                          // Checked again after the hover delay: the banner may
                          // have appeared while the pointer was already resting.
                          !self.showsLocalSendBanner else { return }
                    
                    self.doOpen()
                }
            }
        } else {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    withAnimation(animationSpring) {
                        self.isHovering = false
                    }
                }

                await MainActor.run {
                    // A pointer that has not moved cannot have left.
                    guard Date() >= self.suppressHoverCloseUntil else { return }

                    if self.vm.notchState == .open && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                        self.vm.close()
                    }
                }
            }
        }
    }

    // MARK: - Gesture Handling

    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .closed else { return }
        guard !pointerOverContent else { return }

        if phase == .ended {
            withAnimation(animationSpring) { gestureProgress = .zero }
            return
        }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * 20
        }

        if translation > Defaults[.gestureSensitivity] {
            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
            doOpen()
        }
    }

    private func handleUpGesture(translation: CGFloat, phase: NSEvent.Phase) {
        // Let content scroll; close from the icons line instead.
        guard !pointerOverContent else { return }
        guard vm.notchState == .open && !vm.isHoveringCalendar else { return }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * -20
        }

        if phase == .ended {
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
        }

        if translation > Defaults[.gestureSensitivity] {
            withAnimation(animationSpring) {
                isHovering = false
            }
            if !SharingStateManager.shared.preventNotchClose { 
                gestureProgress = .zero
                vm.close()
            }

            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
        }
    }
}

struct FullScreenDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: () -> Void

    func dropEntered(info _: DropInfo) {
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info _: DropInfo) -> Bool {
        isTargeted = false
        onDrop()
        return true
    }

}

struct GeneralDropTargetDelegate: DropDelegate {
    @Binding var isTargeted: Bool

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .cancel)
    }

    func performDrop(info: DropInfo) -> Bool {
        return false
    }
}

#Preview {
    let vm = VornyxViewModel()
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}

// MARK: - Notch background

/// What the notch is made of.
///
/// Two layers, both always there while Liquid Glass is on: the glass
/// underneath, and the black the notch has always been on top of it. Opening
/// and closing only change how much of the glass the black covers - it fades
/// out as the notch opens and back in as it closes, riding the notch's own
/// spring - so neither layer comes or goes in the middle of an animation.
/// When the glass was taken away at the start of a close, the notch spent the
/// close with no background at all, and its text and artwork shrank on their
/// own. Closed, the black covers the glass completely, so the closed notch is
/// the same black as the hardware notch.
///
/// Animatable over its corner radii. The glass is shaped by a modifier, and a
/// modifier is handed only the end value: its corners jumped straight to the
/// closed radius while the notch around it was still easing there. As an
/// animatable view it is redrawn every frame with the radii in between - the
/// same values the notch's own clip is drawn with.
///
/// Over the glass, a black band as tall as the hardware notch fades into it so
/// it hides in the cut-out; the dimming holds through the middle for the white
/// text and lets go towards the bottom edge.
private struct NotchBackground: View, Animatable {
    let isOpen: Bool
    let blackBandHeight: CGFloat
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    @Default(.liquidGlassNotch) private var liquidGlass

    /// How far the black takes to fade down to the middle dimming.
    private let fadeHeight: CGFloat = 90
    /// Dimming through the middle, where most of the white text sits.
    private let middleDim: Double = 0.60
    /// Dimming at the bottom edge. Held close to the middle value: letting it
    /// go left a bright clear line along the bottom of the notch.
    private let bottomDim: Double = 0.55

    /// The notch's outline at this frame's radii.
    private var shape: NotchShape {
        NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius)
    }

    var body: some View {
        ZStack(alignment: .top) {
            if #available(macOS 26.0, *), liquidGlass {
                Rectangle()
                    .fill(.clear)
                    .glassEffect(.clear, in: shape)

                // One gradient, not a stack of pieces: stacked, every seam
                // flashed as a thin bright line while the notch resized.
                GeometryReader { proxy in
                    let height = max(proxy.size.height, 1)
                    let bandEnd = min(1, blackBandHeight / height)
                    let fadeEnd = min(1, (blackBandHeight + fadeHeight) / height)
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: bandEnd),
                            .init(color: .black.opacity(middleDim), location: fadeEnd),
                            .init(color: .black.opacity(bottomDim), location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom)
                }
                .clipShape(shape)
            }

            // No animation of its own: the change arrives with the notch's open
            // or close spring from `mainLayout`, so the black fades exactly as
            // fast as the notch moves.
            shape.fill(.black)
                .opacity(isOpen && glassAvailable ? 0 : 1)
        }
    }

    private var glassAvailable: Bool {
        guard liquidGlass else { return false }
        if #available(macOS 26.0, *) { return true }
        return false
    }
}
