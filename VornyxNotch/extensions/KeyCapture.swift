//
//  KeyCapture.swift
//  VornyxNotch
//
//  Keystrokes for a view living inside the notch.
//

import AppKit
import SwiftUI

/// Hands a view the keys pressed while it is on screen.
///
/// SwiftUI's `onKeyPress` is no use here. It needs a focused responder, and the
/// notch is a non-activating panel: nothing inside it is ever focused unless
/// the panel is deliberately given key status first. A local monitor sees the
/// same events without needing a first responder, for exactly as long as the
/// view asks for them.
///
/// Return `true` from the handler to swallow the key, `false` to let it carry
/// on to whatever would normally get it.
private struct KeyCapture: ViewModifier {
    let isEnabled: Bool
    let handler: (NSEvent) -> Bool

    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear { sync() }
            .onDisappear { stop() }
            .onChange(of: isEnabled) { _, _ in sync() }
    }

    private func sync() {
        isEnabled ? start() : stop()
    }

    private func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handler(event) ? nil : event
        }
    }

    private func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }
}

extension View {
    /// See `KeyCapture`.
    func onKeyDown(enabled: Bool = true, _ handler: @escaping (NSEvent) -> Bool) -> some View {
        modifier(KeyCapture(isEnabled: enabled, handler: handler))
    }
}

// MARK: - Key codes

/// The handful of keys the notch reacts to, named rather than numbered.
enum NotchKey: UInt16 {
    case returnKey = 36
    case tab = 48
    case escape = 53
    case leftArrow = 123
    case rightArrow = 124
    case downArrow = 125
    case upArrow = 126
    case delete = 51
    case forwardDelete = 117
    case enter = 76

    init?(_ event: NSEvent) {
        self.init(rawValue: event.keyCode)
    }
}
