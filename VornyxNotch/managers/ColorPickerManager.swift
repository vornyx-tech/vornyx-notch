//
//  ColorPickerManager.swift
//  VornyxNotch
//
//  Picks a colour from anywhere on screen and copies it.
//

import AppKit
import Defaults
import SwiftUI

/// The system's own loupe - `NSColorSampler`, what Digital Color Meter and
/// the colour panel's eyedropper use - which needs no permission and works in
/// the sandbox. The pick is copied as hex, kept in a short history, and shown
/// in the notch.
@MainActor
final class ColorPickerManager: ObservableObject {
    static let shared = ColorPickerManager()

    /// Newest first.
    @Published private(set) var recent: [NSColor] = []

    private init() {}

    /// The loupe covers the screen; the notch closes first, or it would be in
    /// the way of whatever sits under it.
    func pick(closingNotch close: () -> Void = {}) {
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NSColorSampler().show { color in
                guard let color else { return }
                Task { @MainActor in ColorPickerManager.shared.picked(color) }
            }
        }
    }

    func picked(_ color: NSColor) {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        recent.removeAll { Self.hex($0) == Self.hex(srgb) }
        recent.insert(srgb, at: 0)
        recent = Array(recent.prefix(6))

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.hex(srgb), forType: .string)
        VornyxViewCoordinator.shared.announceColorPicked()
    }

    /// `#1E90FF`.
    static func hex(_ color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    func copy(_ color: NSColor) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.hex(color), forType: .string)
    }
}
