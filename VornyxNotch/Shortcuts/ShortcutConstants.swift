//
//  Constants.swift
//  VornyxNotch
//
//  Created by Richard Kunkli on 16/08/2024.
//

import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    /// Opens the notch straight onto the clipboard tab.
    ///
    /// No default: a global hotkey the user never asked for is one that
    /// collides with whatever they had that combination bound to. Set it in
    /// Settings > Shortcuts.
    static let showClipboard = Self("showClipboard")
    static let toggleMicrophone = Self("toggleMicrophone", default: .init(.f5, modifiers: [.function]))
    static let decreaseBacklight = Self("decreaseBacklight", default: .init(.f1, modifiers: [.command]))
    static let increaseBacklight = Self("increaseBacklight", default: .init(.f2, modifiers: [.command]))
    static let toggleSneakPeek = Self("toggleSneakPeek", default: .init(.h, modifiers: [.command, .shift]))
    static let toggleNotchOpen = Self("toggleNotchOpen", default: .init(.i, modifiers: [.command, .shift]))
    /// Control-Option-S: S for shelf, and unlike Command-Shift-S it is not
    /// every app's Save As.
    static let openShelf = Self("openShelf", default: .init(.s, modifiers: [.control, .option]))
}
