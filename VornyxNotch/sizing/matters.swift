//
//  sizeMatters.swift
//  VornyxNotch
//
//  Created by Harsh Vardhan  Goswami  on 05/08/24.
//

import Defaults
import Foundation
import SwiftUI

let downloadSneakSize: CGSize = .init(width: 65, height: 1)
let batterySneakSize: CGSize = .init(width: 160, height: 1)

let shadowPadding: CGFloat = 20
/// Stock size of the open notch; the width is user-adjustable from Appearance
/// settings, the height follows the content.
let defaultOpenNotchSize: CGSize = .init(width: 640, height: 190)

/// How far the open notch may be stretched or shrunk to the sides.
let openNotchWidthRange: ClosedRange<CGFloat> = 380...900

/// The configured home-page width.
var configuredHomeNotchWidth: CGFloat {
    Defaults[.openNotchWidth].clamped(to: openNotchWidthRange)
}

/// Width of the open notch for a given tab. Only the home page follows the
/// width setting - the shelf and calendar keep the full width, because
/// shrinking them would squeeze content that needs the room.
func openNotchWidth(for view: NotchViews) -> CGFloat {
    switch view {
    case .home:
        return configuredHomeNotchWidth
    case .shelf, .calendar, .clipboard, .ai:
        return defaultOpenNotchSize.width
    }
}

/// How tall the big-screen mirror panel may be.
let mirrorBigScreenHeightRange: ClosedRange<CGFloat> = 120...420

/// Extra height the notch needs when the mirror is set to stretch it downwards.
/// Reserved on the window whenever the mode is active, so opening the mirror
/// does not have to resize the window mid-animation.
var mirrorBigScreenReservedHeight: CGFloat {
    guard Defaults[.showMirror], Defaults[.mirrorDisplayMode] == .bigScreen else { return 0 }
    return Defaults[.mirrorBigScreenHeight].clamped(to: mirrorBigScreenHeightRange)
}

/// Size the window has to be: wide enough for the widest tab, and tall enough
/// for the big-screen mirror if that mode is on.
var openNotchSize: CGSize {
    .init(
        width: max(configuredHomeNotchWidth, defaultOpenNotchSize.width),
        height: defaultOpenNotchSize.height + mirrorBigScreenReservedHeight
    )
}

var windowSize: CGSize {
    .init(width: openNotchSize.width, height: openNotchSize.height + shadowPadding)
}
typealias NotchCornerRadiusInsets = (
    opened: (top: CGFloat, bottom: CGFloat),
    closed: (top: CGFloat, bottom: CGFloat)
)

/// Stock notch corner radii. Used as the factory defaults for the user-facing
/// corner radius settings and by the "Reset" button in Appearance settings.
let defaultCornerRadiusInsets: NotchCornerRadiusInsets = (
    opened: (top: 19, bottom: 24),
    closed: (top: 6, bottom: 14)
)

/// Allowed slider ranges for each corner radius. `NotchShape` additionally
/// caps them against the notch it is drawing into, so a value that is too large
/// for the current notch height simply stops having an effect.
enum NotchCornerRadiusRange {
    static let openedTop: ClosedRange<CGFloat> = 0...60
    static let openedBottom: ClosedRange<CGFloat> = 0...60
    static let closedTop: ClosedRange<CGFloat> = 0...20
    static let closedBottom: ClosedRange<CGFloat> = 0...30
}

/// The corner radii currently configured by the user. Reads live from `Defaults`
/// so changing a slider in settings updates the notch immediately.
var cornerRadiusInsets: NotchCornerRadiusInsets {
    (
        opened: (
            top: Defaults[.openedTopCornerRadius].clamped(to: NotchCornerRadiusRange.openedTop),
            bottom: Defaults[.openedBottomCornerRadius].clamped(to: NotchCornerRadiusRange.openedBottom)
        ),
        closed: (
            top: Defaults[.closedTopCornerRadius].clamped(to: NotchCornerRadiusRange.closedTop),
            bottom: Defaults[.closedBottomCornerRadius].clamped(to: NotchCornerRadiusRange.closedBottom)
        )
    )
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// Code-only styling for the player artwork.
///
/// Deliberately NOT surfaced in Settings - these are developer knobs. Change a
/// value here and rebuild; nothing in the UI exposes them.
enum AlbumArtStyle {
    /// Artwork corner radius on the open notch's home page.
    static let openCornerRadius: CGFloat = 13
    /// Artwork corner radius in the closed-notch live activity.
    static let closedCornerRadius: CGFloat = 4
    /// Corner radius of the small source-app badge on the artwork.
    static let appIconCornerRadius: CGFloat = 7
    /// Size of that badge.
    static let appIconSize: CGFloat = 30
}

enum MusicPlayerImageSizes {
    static let cornerRadiusInset: (opened: CGFloat, closed: CGFloat) = (opened: 13.0, closed: 4.0)
    static let size = (opened: CGSize(width: 90, height: 90), closed: CGSize(width: 20, height: 20))
}

@MainActor func getScreenFrame(_ screenUUID: String? = nil) -> CGRect? {
    var selectedScreen = NSScreen.main

    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }
    
    if let screen = selectedScreen {
        return screen.frame
    }
    
    return nil
}

@MainActor func getClosedNotchSize(screenUUID: String? = nil) -> CGSize {
    // Default notch size, to avoid using optionals
    var notchHeight: CGFloat = Defaults[.nonNotchHeight]
    var notchWidth: CGFloat = 185

    var selectedScreen = NSScreen.main

    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }

    // Check if the screen is available
    if let screen = selectedScreen {
        // Calculate and set the exact width of the notch
        if let topLeftNotchpadding: CGFloat = screen.auxiliaryTopLeftArea?.width,
           let topRightNotchpadding: CGFloat = screen.auxiliaryTopRightArea?.width
        {
            notchWidth = screen.frame.width - topLeftNotchpadding - topRightNotchpadding + 4
        }

        // Check if the Mac has a notch
        if screen.safeAreaInsets.top > 0 {
            // This is a display WITH a notch - use notch height settings
            notchHeight = Defaults[.notchHeight]
            if Defaults[.notchHeightMode] == .matchRealNotchSize {
                notchHeight = screen.safeAreaInsets.top
            } else if Defaults[.notchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            }
        } else {
            // This is a display WITHOUT a notch - use non-notch height settings
            notchHeight = Defaults[.nonNotchHeight]
            if Defaults[.nonNotchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            }
        }
    }

    return .init(width: notchWidth, height: notchHeight)
}
