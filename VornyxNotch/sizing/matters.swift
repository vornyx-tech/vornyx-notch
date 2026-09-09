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
/// The dashboard holds a month, a shortcut grid and a chat side by side, so it
/// widens the notch while it is open and hands the width back on the way out.
let dashboardNotchWidth: CGFloat = 900

/// A six-row month grid does not fit the stock 190pt, so the dashboard is
/// taller too. Without this the content overflows its frame and SwiftUI
/// centres the overflow, lifting the header off the top of the screen.
let dashboardNotchHeight: CGFloat = 252

/// Height of the open notch for a given tab.
func openNotchHeight(for view: NotchViews) -> CGFloat {
    view == .dashboard ? dashboardNotchHeight : defaultOpenNotchSize.height
}

func openNotchWidth(for view: NotchViews) -> CGFloat {
    switch view {
    case .home:
        return configuredHomeNotchWidth
    case .dashboard:
        return dashboardNotchWidth
    case .shelf, .clipboard:
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
    // The window has to be able to hold the widest tab, so it is sized for the
    // dashboard even while a narrower tab is showing. It is transparent
    // outside the notch shape, so the extra width costs nothing visually.
    .init(
        width: max(configuredHomeNotchWidth, defaultOpenNotchSize.width, dashboardNotchWidth),
        height: max(defaultOpenNotchSize.height, dashboardNotchHeight)
            + mirrorBigScreenReservedHeight
    )
}

var windowSize: CGSize {
    .init(width: openNotchSize.width, height: openNotchSize.height + shadowPadding)
}
typealias NotchCornerRadiusInsets = (
    opened: (top: CGFloat, bottom: CGFloat),
    closed: (top: CGFloat, bottom: CGFloat)
)

/// The notch's corner radii.
///
/// Code-only, like `AlbumArtStyle`: deliberately NOT surfaced in Settings.
/// Edit the numbers here and rebuild.
///
/// - `top` is the radius where the notch meets the screen edge - the outward
///   flare at the top corners.
/// - `bottom` is the radius of its lower corners.
/// - The `opened` pair is used only while `Defaults[.cornerRadiusScaling]` is
///   on; with it off the notch keeps the `closed` values in both states.
///
/// `NotchShape` caps whatever it is given against the box it draws into, so a
/// value too large for the current notch height simply stops having an effect
/// rather than folding the shape in on itself.
let cornerRadiusInsets: NotchCornerRadiusInsets = (
    opened: (top: 26, bottom: 57),
    closed: (top: 6, bottom: 14)
)

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// The open notch's own outer corner radius, as actually drawn.
var openNotchCornerRadius: CGFloat {
    Defaults[.cornerRadiusScaling]
        ? cornerRadiusInsets.opened.bottom
        : cornerRadiusInsets.closed.bottom
}

/// Gap between the notch's inner edge and the panels drawn inside it.
let notchContentInset: CGFloat = 12

/// Corner radius for a panel sitting directly inside the open notch.
///
/// Apple's concentric rule: an inner radius is the outer radius minus the gap
/// between them, which keeps the two curves parallel all the way round.
/// Matching the outer number instead makes the inner corner look too tight;
/// picking an unrelated number - which is what a hardcoded 16 was - makes the
/// curves visibly disagree. Follows the user's own corner radius setting.
var innerPanelCornerRadius: CGFloat {
    max(6, openNotchCornerRadius - notchContentInset)
}

/// One level deeper again: a tile inside one of those panels.
///
/// `cap` matters on small tiles: concentric rounding is derived from the notch,
/// and on a card only ~110pt tall an unbounded radius eats the corners and
/// pushes content into the curve. Past roughly an eighth of the shorter side a
/// rounded rectangle stops reading as a rectangle at all.
func nestedCornerRadius(inset: CGFloat, cap: CGFloat = .infinity) -> CGFloat {
    min(max(4, innerPanelCornerRadius - inset), cap)
}

/// Code-only styling for the player artwork.
/// 
/// Deliberately NOT surfaced in Settings - these are developer knobs. Change a
/// value here and rebuild; nothing in the UI exposes them.
enum AlbumArtStyle {
    /// Artwork corner radius on the open notch's home page.
    static let openCornerRadius: CGFloat = 29
    /// Artwork corner radius in the closed-notch live activity.
    static let closedCornerRadius: CGFloat = 6
    /// Corner radius of the small source-app badge on the artwork.
    static let appIconCornerRadius: CGFloat = 9
    /// Size of that badge.
    static let appIconSize: CGFloat = 29

    /// Tuning for the living glow behind the artwork. Also code-only.
    enum Glow {
        static let blur: CGFloat = 45
        static let baseScale: (x: CGFloat, y: CGFloat) = (1.3, 1.4)
        static let baseRotation: Double = 92
        static let baseOpacity: Double = 0.5

        /// How far each property wanders from its resting value.
        ///
        /// These have to be large. A 40pt blur is a low-pass filter: it erases
        /// exactly the small movements that would read as motion on a sharp
        /// image, so anything subtler than roughly the blur radius simply is
        /// not visible.
        static let scaleSwing: CGFloat = 0.22
        static let rotationSwing: Double = 30
        static let driftRadius: CGFloat = 28
        static let opacitySwing: Double = 0.22

        /// Seconds per cycle. Deliberately not multiples of one another, so
        /// the combined motion takes minutes to repeat and never reads as a
        /// loop.
        static let breathePeriod: Double = 3.7
        static let rotatePeriod: Double = 6.1
        static let swayPeriod: Double = 4.3
        static let bobPeriod: Double = 5.9
        static let shimmerPeriod: Double = 2.9

        /// The glow moves slowly, so it does not need a high frame rate, and
        /// each frame re-blurs a full-size image - the expensive part.
        static let frameRate: Double = 12
    }
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
