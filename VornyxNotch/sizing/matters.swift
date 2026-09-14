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

/// How far the home page reaches out to the sides.
///
/// Code-only, like `cornerRadiusInsets` and `AlbumArtStyle`: edit and rebuild.
/// Only the home page uses it - the shelf and clipboard keep the stock width,
/// and the dashboard has its own.
let homeNotchBaseWidth: CGFloat = 560

/// The AirPods panel beside the player, and the gap before it.
///
/// The home page is the one tab with a width set in code rather than by its
/// content, so anything added to it has to buy its own room here.
let airPodsWidgetWidth: CGFloat = 112
let airPodsWidgetGap: CGFloat = 15

/// How far the home page reaches out, with or without the AirPods panel.
///
/// The panel only takes its room while a pair is connected. Taking one ear out
/// keeps the pair connected, so the notch widens once per connection rather
/// than with every earbud.
func homePageWidth(showingAirPods: Bool) -> CGFloat {
    homeNotchBaseWidth + (showingAirPods ? airPodsWidgetWidth + airPodsWidgetGap : 0)
}

/// The widest the home page can get - what the window has to be able to hold.
var homeNotchWidth: CGFloat {
    homePageWidth(showingAirPods: Defaults[.showAirPodsWidget])
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
///
/// This is where the dashboard *starts*; a long AI transcript grows it towards
/// `dashboardNotchMaxHeight`.
let dashboardNotchHeight: CGFloat = 252

/// How tall the dashboard may grow to show more of a long AI transcript.
///
/// The notch stretching to fit the chat is the point - reading a reply four
/// lines at a time is miserable - but it has to stop somewhere, or one long
/// answer turns the notch into most of the screen. Past this the transcript
/// scrolls instead.
let dashboardNotchMaxHeight: CGFloat = 400

/// The one spring every change of the notch's own size runs on: growing for a
/// clipboard row, stretching around a long reply, opening the mirror, and
/// widening from one tab to the next.
///
/// One constant rather than a number written out at each site. They were
/// drifting apart - a row opening animated on a different curve from the height
/// it caused - and two springs disagreeing about the same change is exactly
/// what makes a resize look like a stutter instead of a movement.
///
/// Long and softly damped on purpose: the notch travels a long way when it
/// resizes, and a quick spring over that distance reads as a snap. The slight
/// overshoot is what makes the size change noticeable rather than merely done.
let notchResizeAnimation = Animation.spring(
    response: 0.52, dampingFraction: 0.78, blendDuration: 0.25
)

/// How long the notch stays put after resizing itself before it will act on
/// the pointer being outside it. Long enough to walk the pointer back.
let notchResizeGrace: TimeInterval = 3

/// How much taller the notch gets for each extra row of clipboard cards.
///
/// Roughly one card plus the gap above it, so the cards in a two-row clipboard
/// are the same size as the cards in a one-row one - the notch makes room for
/// the new row rather than the new row squeezing the old one.
let clipboardRowGrowth: CGFloat = 137

/// The most rows the clipboard will open out to, one press of the down arrow at
/// a time. Three fills about half a laptop screen with the notch, which is as
/// far as this should ever go.
let clipboardMaxRows: Int = 3

/// The clipboard with every row open. The window has to be able to hold this,
/// so it is worked out here rather than left implicit.
var clipboardMaxHeight: CGFloat {
    defaultOpenNotchSize.height + CGFloat(clipboardMaxRows - 1) * clipboardRowGrowth
}

/// How far the growth has to be off before the notch resizes again.
///
/// Heights are measured while the resize is still springing, so every frame of
/// the animation reports a slightly different shortfall. Without a dead band
/// the notch chases its own animation and never settles.
let notchGrowthDeadBand: CGFloat = 6

/// Height of the open notch for a given tab.
func openNotchHeight(for view: NotchViews) -> CGFloat {
    view == .dashboard ? dashboardNotchHeight : defaultOpenNotchSize.height
}

func openNotchWidth(for view: NotchViews, showingAirPods: Bool) -> CGFloat {
    switch view {
    case .home:
        return homePageWidth(showingAirPods: showingAirPods)
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

/// The LocalSend strip under the open notch's page: devices to drop onto, or
/// the transfer in flight.
let localSendStripHeight: CGFloat = 84

/// Room the window keeps for that strip, the same way it does for the mirror:
/// the window cannot resize mid-animation, so the room has to already be there
/// the moment a drag makes the strip appear.
var localSendReservedHeight: CGFloat {
    Defaults[.localSendEnabled] ? localSendStripHeight + 8 : 0
}

/// Margin of error around the *open* notch: how far the pointer may stray past
/// its sides and bottom edge before the notch counts as un-hovered and closes.
///
/// Turn this up if the notch closes when you clip a corner on the way to a
/// control; turn it down if it lingers. Closed, the notch does not use this at
/// all - its hover region stays exactly the notch, because hover-to-open would
/// otherwise trigger from well outside it.
///
/// `openNotchSize` grows by the same amount, because the region cannot reach
/// past the window that hosts it: on the dashboard the notch is already the
/// full window width, so without the extra room there is nowhere to stray to.
let openNotchHoverSlack: CGFloat = 28

/// Size the window has to be: wide enough for the widest tab, tall enough for
/// the big-screen mirror if that mode is on, plus the hover slack on the sides
/// and bottom.
var openNotchSize: CGSize {
    // The window has to be able to hold the widest tab, so it is sized for the
    // dashboard even while a narrower tab is showing. It is transparent
    // outside the notch shape, so the extra width costs nothing visually.
    .init(
        width: max(homeNotchWidth, defaultOpenNotchSize.width, dashboardNotchWidth)
            + openNotchHoverSlack * 2,
        // The *grown* heights, not the starting ones: the window cannot resize
        // mid-animation, so it has to already hold the tallest the notch is
        // allowed to get - the dashboard stretched around a long reply, or the
        // clipboard opened out to all its rows.
        height: max(defaultOpenNotchSize.height, dashboardNotchMaxHeight, clipboardMaxHeight)
            + mirrorBigScreenReservedHeight
            + localSendReservedHeight
            + openNotchHoverSlack
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
    static let openCornerRadius: CGFloat = 30
    /// Artwork corner radius in the closed-notch live activity.
    static let closedCornerRadius: CGFloat = 6
    /// Corner radius of the small source-app badge on the artwork.
    static let appIconCornerRadius: CGFloat = 9
    /// Size of that badge.
    static let appIconSize: CGFloat = 33

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

/// Tuning for the weather page's glow. Code-only, like `AlbumArtStyle`.
///
/// Same idea as the album art's living glow, with colour standing in for the
/// artwork: a few soft blobs of the condition's palette, blurred past
/// recognition and drifting on periods that share no common multiple, so the
/// motion never lines up into a visible loop.
enum WeatherGlowStyle {
    /// Big, because a blur this heavy is a low-pass filter - anything smaller
    /// than roughly the blur radius simply does not read as movement.
    static let blur: CGFloat = 42
    static let opacity: Double = 0.5
    static let baseScale: CGFloat = 1.0
    static let scaleSwing: CGFloat = 0.22
    static let driftRadius: CGFloat = 26

    /// Where each blob sits, as a fraction of the page. Spread out rather than
    /// stacked, so the colours meet in the middle instead of muddying.
    static let anchors: [(x: Double, y: Double)] = [(0.18, 0.30), (0.62, 0.72), (0.92, 0.22)]

    static let breathePeriod: Double = 4.1
    static let swayPeriod: Double = 5.3
    static let bobPeriod: Double = 6.7

    /// How far in from the page's edges the glow has faded to nothing.
    ///
    /// The dashboard clips this column, and a blurred blob meeting a clip is a
    /// hard straight line - the glow ends up looking boxed in rather than
    /// floating. Fading it out first leaves the clip nothing to cut.
    static let edgeFade: CGFloat = 28

    /// It moves slowly, so it does not need a high frame rate.
    static let frameRate: Double = 12
}

/// Tuning for the falling weather. Code-only, like `WeatherGlowStyle`.
enum WeatherPrecipitationStyle {
    /// How many drops at each intensity.
    ///
    /// Higher than they look like they should be: the page is only ~330x215,
    /// and at fifty drops that is one streak per fifteen hundred square points
    /// - which is drizzle you have to go looking for rather than weather.
    static let dropsLight = 55
    static let dropsMedium = 110
    static let dropsHeavy = 170
    static let flakes = 70

    /// Fractions of the view's height travelled per second.
    static let rainSpeed: ClosedRange<Double> = 0.55...1.15
    static let snowSpeed: ClosedRange<Double> = 0.10...0.22

    /// How far a drop leans as it falls, as a fraction of the view's width.
    /// Rain on a still day is not vertical, and vertical rain looks like a
    /// screensaver.
    static let rainSlant: Double = 0.055
    /// How far a flake wanders either side of its line.
    static let snowSway: Double = 9

    static let rainLength: ClosedRange<Double> = 10...24
    static let flakeRadius: ClosedRange<Double> = 1.0...2.4
    /// Kept down deliberately: the page's own text sits under this, and rain
    /// you have to look for is the point - weather, not a foreground.
    static let opacity: ClosedRange<Double> = 0.22...0.58
    /// Thin enough to read as rain, thick enough to see on a small dark page.
    static let rainWidth: CGFloat = 1.2

    /// Rain needs a real frame rate - at the glow's twelve it stutters visibly,
    /// because a falling drop crosses several of its own lengths per frame.
    static let frameRate: Double = 30

    /// How far in from the top the shower fades out.
    ///
    /// The page clips its contents, so without this a drop is chopped
    /// mid-streak against a dead straight line - which is what gives the whole
    /// thing away as a drawing. Roughly a drop's own length, so a streak is
    /// gone by the time it reaches the cut rather than fading halfway down the
    /// page.
    static let topFade: CGFloat = 22

    /// How far past the bottom of the page the shower is allowed to run.
    ///
    /// The page stops above the dots, and the dots stop above the notch's own
    /// edge, which left the rain ending in a band of flat black with the
    /// weather plainly still going on above it. The shower runs on behind the
    /// dots instead and fades out down there, where there is nothing left to
    /// cut it. The left zone's clip is opened by the same amount to let it.
    static let bottomBleed: CGFloat = 14

    /// Longer than the top's: it has the bleed to fade across, and a shower
    /// thinning out towards the ground reads better than one switched off.
    static let bottomFade: CGFloat = 30
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
