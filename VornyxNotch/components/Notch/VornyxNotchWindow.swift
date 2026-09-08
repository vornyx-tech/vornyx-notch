//
//  VornyxNotchWindow.swift
//  VornyxNotch
//
//  Created by Harsh Vardhan  Goswami  on 06/08/24.
//

import Cocoa

class VornyxNotchWindow: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )
        
        isFloatingPanel = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false
        
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
        
        isReleasedWhenClosed = false
        level = .mainMenu + 3
        hasShadow = false
    }
    
    /// Set while something in the notch needs the keyboard - today, the AI
    /// chat composer.
    ///
    /// The notch is a non-activating panel that deliberately never takes focus,
    /// so a text field inside it can never receive a keystroke. Because the
    /// panel is non-activating it can hold key status *without* activating the
    /// app, so the app you were using stays frontmost while you type here.
    /// Opt-in, and only for as long as the input is on screen.
    var acceptsKeyboardInput: Bool = false {
        didSet {
            guard acceptsKeyboardInput != oldValue, !acceptsKeyboardInput else { return }
            if isKeyWindow { resignKey() }
        }
    }

    override var canBecomeKey: Bool { acceptsKeyboardInput }
    override var canBecomeMain: Bool { false }
}
