//
//  VornyxViewCoordinator.swift
//  VornyxNotch
//
//  Created by Alexander on 2024-11-20.
//

import AppKit
import Combine
import Defaults
import SwiftUI

enum SneakContentType {
    case brightness
    case volume
    case backlight
    case music
    case mic
    case battery
    case download
    case airpods
    case timer
    case audioRoute
}

struct sneakPeek {
    var show: Bool = false
    var type: SneakContentType = .music
    var value: CGFloat = 0
    var icon: String = ""
}

struct SharedSneakPeek: Codable {
    var show: Bool
    var type: String
    var value: String
    var icon: String
}

enum BrowserType {
    case chromium
    case safari
}

struct ExpandedItem {
    var show: Bool = false
    var type: SneakContentType = .battery
    var value: CGFloat = 0
    var browser: BrowserType = .chromium
}

@MainActor
class VornyxViewCoordinator: ObservableObject {
    static let shared = VornyxViewCoordinator()

    @Published var currentView: NotchViews = .home {
        didSet {
            guard oldValue != currentView else { return }
            let tabs = orderedTabs
            let from = tabs.firstIndex(of: oldValue) ?? 0
            let to = tabs.firstIndex(of: currentView) ?? 0
            // Drives which way the page slides in the open notch.
            tabDirection = to >= from ? 1 : -1
        }
    }

    /// +1 when moving right through the tabs, -1 when moving left.
    @Published private(set) var tabDirection: Int = 1

    /// Set when the notch was opened from a keyboard shortcut, so it answers
    /// the keyboard: arrows inside a page, Command-arrows across the tabs.
    ///
    /// A notch reached with the mouse deliberately does not: taking the
    /// keyboard away from whatever you were typing in, because you happened to
    /// hover the notch, would be rude. Lasts until the notch closes, so
    /// stepping from the clipboard to another tab does not end it.
    @Published var keyboardSession: Bool = false

    /// How many rows of clipboard cards are open.
    ///
    /// Lives here rather than in the page because the notch has to grow to hold
    /// the extra row, and the notch's height is worked out in `ContentView`.
    @Published var clipboardRows: Int = 1

    /// How far the LocalSend strip has stretched down to hold a long text
    /// being written. Here for the same reason as `clipboardRows`.
    @Published var localSendComposeGrowth: CGFloat = 0

    /// One spring for every way of changing tab - buttons, swipes, drops - so
    /// the page slide always feels the same.
    static let tabChangeAnimation = Animation.spring(
        response: 0.42, dampingFraction: 0.78, blendDuration: 0)

    @Published var helloAnimationRunning: Bool = false
    private var sneakPeekDispatch: DispatchWorkItem?
    private var expandingViewDispatch: DispatchWorkItem?
    private var hudEnableTask: Task<Void, Never>?

    @AppStorage("firstLaunch") var firstLaunch: Bool = true

    /// Replays the first-launch greeting without clearing defaults.
    /// Run with VORNYX_FIRST_OPEN=1 in the scheme's environment.
    static var forcesFirstOpen: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["VORNYX_FIRST_OPEN"] == "1"
        #else
        false
        #endif
    }

    /// Jumps onboarding straight to one step, for looking at it while building.
    /// VORNYX_ONBOARDING_STEP=welcome|permissions|music|features|finished
    static var debugOnboardingStep: OnboardingStep? {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["VORNYX_ONBOARDING_STEP"] {
        case "welcome": return .welcome
        case "permissions": return .permissions
        case "music": return .musicPermission
        case "features": return .features
        case "finished": return .finished
        default: return nil
        }
        #else
        return nil
        #endif
    }
    @AppStorage("showWhatsNew") var showWhatsNew: Bool = true
    @AppStorage("musicLiveActivityEnabled") var musicLiveActivityEnabled: Bool = true
    @AppStorage("currentMicStatus") var currentMicStatus: Bool = true

    @AppStorage("alwaysShowTabs") var alwaysShowTabs: Bool = true {
        didSet {
            if !alwaysShowTabs {
                openLastTabByDefault = false
                if ShelfStateViewModel.shared.isEmpty || !Defaults[.openShelfByDefault] {
                    currentView = .home
                }
            }
        }
    }

    @AppStorage("openLastTabByDefault") var openLastTabByDefault: Bool = false {
        didSet {
            if openLastTabByDefault {
                alwaysShowTabs = true
            }
        }
    }
    
    @Default(.hudReplacement) var hudReplacement: Bool
    
    // Legacy storage for migration
    @AppStorage("preferred_screen_name") private var legacyPreferredScreenName: String?
    
    // New UUID-based storage
    @AppStorage("preferred_screen_uuid") var preferredScreenUUID: String? {
        didSet {
            if let uuid = preferredScreenUUID {
                selectedScreenUUID = uuid
            }
            NotificationCenter.default.post(name: Notification.Name.selectedScreenChanged, object: nil)
        }
    }

    @Published var selectedScreenUUID: String = NSScreen.notched?.displayUUID ?? NSScreen.main?.displayUUID ?? ""

    @Published var optionKeyPressed: Bool = true
    private var accessibilityObserver: Any?
    private var hudReplacementCancellable: AnyCancellable?

    private init() {
        // Perform migration from name-based to UUID-based storage
        if preferredScreenUUID == nil, let legacyName = legacyPreferredScreenName {
            // Try to find screen by name and migrate to UUID
            if let screen = NSScreen.screens.first(where: { $0.localizedName == legacyName }),
               let uuid = screen.displayUUID {
                preferredScreenUUID = uuid
                NSLog("✅ Migrated display preference from name '\(legacyName)' to UUID '\(uuid)'")
            } else {
                // Fallback to main screen if legacy screen not found
                preferredScreenUUID = NSScreen.main?.displayUUID
                NSLog("⚠️ Could not find display named '\(legacyName)', falling back to main screen")
            }
            // Clear legacy value after migration
            legacyPreferredScreenName = nil
        } else if preferredScreenUUID == nil {
            // No legacy value, use main screen
            preferredScreenUUID = NSScreen.main?.displayUUID
        }
        
        selectedScreenUUID = preferredScreenUUID ?? NSScreen.main?.displayUUID ?? ""
        // Observe changes to accessibility authorization and react accordingly
        accessibilityObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.accessibilityAuthorizationChanged,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                if Defaults[.hudReplacement] {
                    await MediaKeyInterceptor.shared.start(promptIfNeeded: false)
                }
            }
        }

        // Observe changes to hudReplacement
        hudReplacementCancellable = Defaults.publisher(.hudReplacement)
            .sink { [weak self] change in
                Task { @MainActor in
                    guard let self = self else { return }

                    self.hudEnableTask?.cancel()
                    self.hudEnableTask = nil

                    if change.newValue {
                        self.hudEnableTask = Task { @MainActor in
                            let granted = await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: true)
                            if Task.isCancelled { return }

                            if granted {
                                await MediaKeyInterceptor.shared.start()
                            } else {
                                Defaults[.hudReplacement] = false
                            }
                        }
                    } else {
                        MediaKeyInterceptor.shared.stop()
                    }
                }
            }

        Task { @MainActor in
            // A beat after the window is up, so the greeting animates open
            // instead of being there from the first frame.
            if firstLaunch || Self.forcesFirstOpen {
                try? await Task.sleep(for: .milliseconds(280))
                helloAnimationRunning = true
            }

            if Defaults[.hudReplacement] {
                let authorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
                if !authorized {
                    Defaults[.hudReplacement] = false
                } else {
                    await MediaKeyInterceptor.shared.start(promptIfNeeded: false)
                }
            }
        }
    }
    
    @objc func sneakPeekEvent(_ notification: Notification) {
        let decoder = JSONDecoder()
        if let decodedData = try? decoder.decode(
            SharedSneakPeek.self, from: notification.userInfo?.first?.value as! Data)
        {
            let contentType =
                decodedData.type == "brightness"
                ? SneakContentType.brightness
                : decodedData.type == "volume"
                    ? SneakContentType.volume
                    : decodedData.type == "backlight"
                        ? SneakContentType.backlight
                        : decodedData.type == "mic"
                            ? SneakContentType.mic : SneakContentType.brightness

            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.numberStyle = .decimal
            let value = CGFloat((formatter.number(from: decodedData.value) ?? 0.0).floatValue)
            let icon = decodedData.icon

            print("Decoded: \(decodedData), Parsed value: \(value)")

            toggleSneakPeek(status: decodedData.show, type: contentType, value: value, icon: icon)

        } else {
            print("Failed to decode JSON data")
        }
    }

    /// `duration` overrides the configured display time for one specific peek;
    /// pass nil (the default) to use the user's setting.
    func toggleSneakPeek(
        status: Bool, type: SneakContentType, duration: TimeInterval? = nil, value: CGFloat = 0,
        icon: String = ""
    ) {
        sneakPeekDuration = duration ?? Defaults[.sneakPeekDuration]
        // Music and the output changing are news of their own; everything
        // else here stands in for the system HUD, and only when it is replaced.
        if type != .music && type != .audioRoute {
            // close()
            if !Defaults[.hudReplacement] {
                return
            }
        }
        // Volume is drawn as where the sound is going - AirPods, this Mac -
        // rather than one speaker for every output. Only when nobody chose an
        // icon: the helper's own events still get theirs.
        let icon = type == .volume && icon.isEmpty ? AudioDeviceManager.shared.currentSymbol : icon
        Task { @MainActor in
            withAnimation(.smooth) {
                self.sneakPeek.show = status
                self.sneakPeek.type = type
                self.sneakPeek.value = value
                self.sneakPeek.icon = icon
            }
        }

        if type == .mic {
            currentMicStatus = value == 1
        }
    }

    private var sneakPeekDuration: TimeInterval = Defaults[.sneakPeekDuration]
    private var sneakPeekTask: Task<Void, Never>?

    // Helper function to manage sneakPeek timer using Swift Concurrency
    private func scheduleSneakPeekHide(after duration: TimeInterval) {
        sneakPeekTask?.cancel()

        sneakPeekTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self = self, !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation {
                    self.toggleSneakPeek(status: false, type: .music)
                    self.sneakPeekDuration = Defaults[.sneakPeekDuration]
                }
            }
        }
    }

    @Published var sneakPeek: sneakPeek = .init() {
        didSet {
            if sneakPeek.show {
                scheduleSneakPeekHide(after: sneakPeekDuration)
            } else {
                sneakPeekTask?.cancel()
            }
        }
    }

    func toggleExpandingView(
        status: Bool,
        type: SneakContentType,
        value: CGFloat = 0,
        browser: BrowserType = .chromium
    ) {
        Task { @MainActor in
            withAnimation(.smooth) {
                self.expandingView.show = status
                self.expandingView.type = type
                self.expandingView.value = value
                self.expandingView.browser = browser
            }
        }
    }

    private var expandingViewTask: Task<Void, Never>?

    @Published var expandingView: ExpandedItem = .init() {
        didSet {
            if expandingView.show {
                expandingViewTask?.cancel()
                let duration: TimeInterval = (expandingView.type == .download ? 2 : 3)
                let currentType = expandingView.type
                expandingViewTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(duration))
                    guard let self = self, !Task.isCancelled else { return }
                    self.toggleExpandingView(status: false, type: currentType)
                }
            } else {
                expandingViewTask?.cancel()
            }
        }
    }
    
    func showEmpty() {
        currentView = .home
    }

    /// Say in the closed notch that a pair has just connected. Whether there is
    /// anywhere to say it - the notch may be open, or hidden under a fullscreen
    /// video - is settled by the view, the same way the music banner settles it.
    func announceAirPods() {
        toggleExpandingView(status: true, type: .airpods)
    }

    /// Say in the closed notch that sound has moved to another output - a pair
    /// connecting, or dropping back to the built-in speakers.
    ///
    /// A pair's own banner outranks this one: it carries the same name plus the
    /// battery levels, so replacing it with the plainer version would be a step
    /// backwards a second after it appeared.
    ///
    /// A sneak peek, like the music one: the notch drops down a row to say it.
    func announceAudioRoute() {
        guard !(expandingView.show && expandingView.type == .airpods) else { return }
        toggleSneakPeek(status: true, type: .audioRoute, duration: 3)
    }

    /// Show the countdown in the closed notch. Started, paused, resumed and
    /// finished are each worth a glance, and each one calls this.
    func announceTimer() {
        toggleExpandingView(status: true, type: .timer)
    }

    // MARK: - Tab navigation

    /// The tabs currently reachable, left to right. Mirrors what the header
    /// actually shows, so swiping can never land on a hidden page.
    var orderedTabs: [NotchViews] {
        var tabs: [NotchViews] = [.home]
        if Defaults[.shelfEnabled] {
            tabs.append(.shelf)
        }
        if Defaults[.clipboardEnabled] {
            tabs.append(.clipboard)
        }
        tabs.append(.dashboard)
        return tabs
    }

    /// Step one tab to the left or right. Stops at the ends rather than
    /// wrapping, so a long swipe cannot spin through the pages.
    func stepTab(by offset: Int) {
        let tabs = orderedTabs
        guard tabs.count > 1,
              let index = tabs.firstIndex(of: currentView) ?? tabs.firstIndex(of: .home)
        else { return }

        let target = index + offset
        guard tabs.indices.contains(target) else { return }

        // The trackpad thump as the page changes under your fingers.
        Defaults[.hapticStrength].perform()

        withAnimation(Self.tabChangeAnimation) {
            currentView = tabs[target]
        }
    }
}
