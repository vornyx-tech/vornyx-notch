//
//  LockScreenPlayer.swift
//  VornyxNotch
//
//  The windows the lock screen's music is shown in, while the Mac is locked:
//  LockScreenCardView and LockScreenBackdropView, in LockScreenExpanded.swift.
//

import AppKit
import Combine
import Defaults
import SkyLightWindow
import SwiftUI

/// Owns the card's window: up while the Mac is locked and something is
/// playing, gone the moment it unlocks.
@MainActor
final class LockScreenPlayerController {
    static let shared = LockScreenPlayerController()

    /// The large layout, drawn only: it ignores the mouse, so clicks and
    /// Touch ID go to the lock screen as if it were not there.
    private var backdrop: NSWindow?
    /// The card with its controls, in a window only its size.
    private var card: NSWindow?
    private var playbackWatcher: AnyCancellable?
    private var expandedWatcher: AnyCancellable?
    private var previewTask: Task<Void, Never>?
    private var showTask: Task<Void, Never>?
    private var isShowing = false

    /// The card and its shadow's room, around the 340 x 180 card.
    private static let cardWindowSize = CGSize(width: 340 + 80, height: 180 + 80)

    private init() {}

    func screenLocked() {
        guard Defaults[.lockScreenPlayer] else { return }
        // Follow the player while locked: nothing before the first track
        // starts, nothing left up after the last one stops. Only real changes
        // count - the player republishes the same state often, and every show
        // handed the window to the lock screen again, which made the screen
        // blink off and on.
        playbackWatcher = MusicManager.shared.$isPlayerIdle
            .combineLatest(MusicManager.shared.$isPlaying)
            .map { idle, playing in playing || !idle }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] playing in
                guard let self else { return }
                if playing {
                    // A second after locking, once macOS has its own lock
                    // screen up, rather than in the middle of putting it up.
                    self.showTask?.cancel()
                    self.showTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(1))
                        guard !Task.isCancelled else { return }
                        self?.show()
                    }
                } else {
                    self.showTask?.cancel()
                    self.hide()
                }
            }
    }

    /// The lock screen's layout over the desktop for a while, without locking
    /// anything - for seeing it from Settings.
    func preview(for seconds: Double = 3) {
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
        showTask?.cancel()
        hide()
    }

    // MARK: - Windows

    private func show() {
        guard !isShowing else { return }
        isShowing = true
        if card == nil { card = makeWindow(LockScreenCardView(), interactive: true) }
        if backdrop == nil { backdrop = makeWindow(LockScreenBackdropView(), interactive: false) }

        layout(animated: false)
        if Defaults[.lockScreenExpanded] { present(backdrop) }
        present(card)

        // Opening out or folding back: the backdrop comes and goes, the card
        // moves to its place for either.
        expandedWatcher = Defaults.publisher(.lockScreenExpanded, options: [])
            .receive(on: RunLoop.main)
            .sink { [weak self] change in
                guard let self, self.isShowing else { return }
                change.newValue ? self.present(self.backdrop) : self.dismiss(self.backdrop)
                self.layout(animated: true)
            }
    }

    private func hide() {
        guard isShowing else { return }
        isShowing = false
        expandedWatcher?.cancel()
        expandedWatcher = nil
        dismiss(card)
        dismiss(backdrop)
    }

    private func present(_ window: NSWindow?) {
        guard let window else { return }
        window.orderFrontRegardless()
        (window as? VornyxNotchSkyLightWindow)?.enableSkyLight()
    }

    private func dismiss(_ window: NSWindow?) {
        guard let window else { return }
        (window as? VornyxNotchSkyLightWindow)?.disableSkyLight()
        window.orderOut(nil)
    }

    private func makeWindow<Content: View>(_ content: Content, interactive: Bool) -> NSWindow {
        let window = VornyxNotchSkyLightWindow(
            contentRect: NSRect(origin: .zero, size: Self.cardWindowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = !interactive
        window.contentView = NSHostingView(rootView: content)
        // The card over its backdrop.
        window.level = interactive ? NSWindow.Level(NSWindow.Level.screenSaver.rawValue + 1) : .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.hasShadow = false
        return window
    }

    /// The backdrop over the whole screen; the card centred, compact above the
    /// user's picture or low with the layout open.
    private func layout(animated: Bool) {
        guard let screen = NSScreen.notched ?? NSScreen.main else { return }
        let frame = screen.frame
        backdrop?.setFrame(frame, display: true)

        let offset = LockScreenBackdropView.cardOffset(
            expanded: Defaults[.lockScreenExpanded], screenHeight: frame.height)
        let size = Self.cardWindowSize
        let cardFrame = NSRect(
            x: frame.midX - size.width / 2,
            y: frame.midY - offset - size.height / 2,
            width: size.width, height: size.height)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.45
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                card?.animator().setFrame(cardFrame, display: true)
            }
        } else {
            card?.setFrame(cardFrame, display: true)
        }
    }
}
