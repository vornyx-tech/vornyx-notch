//
//  LockScreenPlayer.swift
//  VornyxNotch
//
//  The window the lock screen's music is shown in, while the Mac is locked.
//  What is drawn in it is LockScreenRootView, in LockScreenExpanded.swift.
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
