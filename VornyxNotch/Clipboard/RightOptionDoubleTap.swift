//
//  RightOptionDoubleTap.swift
//  VornyxNotch
//

import AppKit

/// Calls back on a double tap of the right Option key. Left Option is left
/// alone, being half of every special-character chord.
///
/// Modifier presses only arrive as `flagsChanged` events, which a global
/// monitor receives once the app is trusted for Accessibility. Without it the
/// monitor stays silent.
final class RightOptionDoubleTap {
    private static let rightOptionKeyCode: UInt16 = 61
    /// NX_DEVICERALTKEYMASK: set only while the right Option key is down.
    private static let rightOptionMask: UInt = 0x40
    /// Longest press that still counts as a tap rather than a hold.
    private static let maxPress: TimeInterval = 0.3
    /// Longest time from the first release to the second.
    private static let maxGap: TimeInterval = 0.45

    private let action: () -> Void
    private var monitors: [Any] = []
    private var pressStart: TimeInterval?
    private var lastTap: TimeInterval?

    init(action: @escaping () -> Void) {
        self.action = action
    }

    deinit {
        stop()
    }

    func start() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]

        // The global monitor misses events aimed at this app, so a local one
        // covers them.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event)
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        reset()
    }

    private func reset() {
        pressStart = nil
        lastTap = nil
    }

    private func handle(_ event: NSEvent) {
        // Anything else in between means Option was part of a chord.
        guard event.type == .flagsChanged, event.keyCode == Self.rightOptionKeyCode else {
            reset()
            return
        }

        if event.modifierFlags.rawValue & Self.rightOptionMask != 0 {
            let others = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .subtracting([.option, .capsLock, .function])
            if others.isEmpty {
                pressStart = event.timestamp
            } else {
                reset()
            }
            return
        }

        guard let start = pressStart, event.timestamp - start <= Self.maxPress else {
            reset()
            return
        }
        pressStart = nil

        if let last = lastTap, event.timestamp - last <= Self.maxGap {
            lastTap = nil
            action()
        } else {
            lastTap = event.timestamp
        }
    }
}
