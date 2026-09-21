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
/// Stock size of the open notch; the height follows the content.
let defaultOpenNotchSize: CGSize = .init(width: 640, height: 190)

/// Home page width; the shelf and clipboard use the default.
let homeNotchBaseWidth: CGFloat = 560

/// The AirPods panel beside the player, and the gap before it.
let airPodsWidgetWidth: CGFloat = 112
let airPodsWidgetGap: CGFloat = 15

/// Home page width, with or without the AirPods panel.
func homePageWidth(showingAirPods: Bool) -> CGFloat {
    homeNotchBaseWidth + (showingAirPods ? airPodsWidgetWidth + airPodsWidgetGap : 0)
}

/// The widest the home page can get.
var homeNotchWidth: CGFloat {
    homePageWidth(showingAirPods: Defaults[.showAirPodsWidget])
}

/// The dashboard widens the notch while it is open and hands the width back.
let dashboardNotchWidth: CGFloat = 900

/// A six-row month grid does not fit the stock height. Where the dashboard
/// starts; a long AI transcript grows it towards `dashboardNotchMaxHeight`.
let dashboardNotchHeight: CGFloat = 252

/// How tall the dashboard may grow; past this the transcript scrolls instead.
let dashboardNotchMaxHeight: CGFloat = 400

/// The spring every change of the notch's own size runs on.
let notchResizeAnimation = Animation.spring(
    response: 0.52, dampingFraction: 0.78, blendDuration: 0.25
)

/// How long the notch ignores the pointer being outside it after a resize.
let notchResizeGrace: TimeInterval = 3

/// Extra height per row of clipboard cards: one card plus the gap above it.
let clipboardRowGrowth: CGFloat = 137

/// The most rows the clipboard will open out to.
let clipboardMaxRows: Int = 3

/// The clipboard with every row open.
var clipboardMaxHeight: CGFloat {
    defaultOpenNotchSize.height + CGFloat(clipboardMaxRows - 1) * clipboardRowGrowth
}

/// Dead band on the growth, since heights are measured while the spring runs.
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

/// Extra height reserved whenever the mirror is set to stretch the notch down.
var mirrorBigScreenReservedHeight: CGFloat {
    guard Defaults[.showMirror], Defaults[.mirrorDisplayMode] == .bigScreen else { return 0 }
    return Defaults[.mirrorBigScreenHeight].clamped(to: mirrorBigScreenHeightRange)
}

/// The LocalSend strip under the open notch's page.
let localSendStripHeight: CGFloat = 84

/// Room the window keeps for that strip; it cannot resize mid-animation.
var localSendReservedHeight: CGFloat {
    Defaults[.localSendEnabled] ? localSendStripHeight + 8 : 0
}

/// The most the strip stretches down for a long text. Past it the field scrolls.
let localSendComposeMaxGrowth: CGFloat = 72

/// The field's height plus this is the strip's height, once the text overflows.
let localSendComposeMargin: CGFloat = 40

/// How far the pointer may stray past the open notch's sides and bottom edge
/// before it counts as un-hovered. `openNotchSize` grows by the same amount,
/// since the region cannot reach past the window hosting it. Unused when closed.
let openNotchHoverSlack: CGFloat = 28

/// How close a dragged file has to come to the closed notch to open it.
let dragOpenSlack = CGSize(width: 40, height: 32)

/// Size the window has to be: the widest tab, the big-screen mirror if that mode
/// is on, plus the hover slack. Transparent outside the notch shape.
var openNotchSize: CGSize {
    .init(
        width: max(homeNotchWidth, defaultOpenNotchSize.width, dashboardNotchWidth)
            + openNotchHoverSlack * 2,
        // The grown heights, since the window cannot resize mid-animation.
        height: max(
            defaultOpenNotchSize.height + (Defaults[.localSendEnabled] ? localSendComposeMaxGrowth : 0),
            dashboardNotchMaxHeight, clipboardMaxHeight)
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

/// The notch's corner radii. `top` is the outward flare where the notch meets
/// the screen edge, `bottom` its lower corners.
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
var openNotchCornerRadius: CGFloat { cornerRadiusInsets.opened.bottom }

/// Gap between the notch's inner edge and the panels drawn inside it.
let notchContentInset: CGFloat = 12

/// Corner radius for a panel sitting directly inside the open notch. Apple's
/// concentric rule: inner radius is the outer radius minus the gap between them.
var innerPanelCornerRadius: CGFloat {
    max(6, openNotchCornerRadius - notchContentInset)
}

/// One level deeper again: a tile inside one of those panels. `cap` keeps the
/// notch-derived radius from eating the corners of a small tile.
func nestedCornerRadius(inset: CGFloat, cap: CGFloat = .infinity) -> CGFloat {
    min(max(4, innerPanelCornerRadius - inset), cap)
}

/// Styling for the player artwork.
enum AlbumArtStyle {
    /// Artwork corner radius on the open notch's home page.
    static let openCornerRadius: CGFloat = 30
    /// Artwork corner radius in the closed-notch live activity.
    static let closedCornerRadius: CGFloat = 6
    /// Corner radius of the small source-app badge on the artwork.
    static let appIconCornerRadius: CGFloat = 9
    /// Size of that badge.
    static let appIconSize: CGFloat = 33

    /// Tuning for the living glow behind the artwork.
    enum Glow {
        static let blur: CGFloat = 45
        static let baseScale: (x: CGFloat, y: CGFloat) = (1.3, 1.4)
        static let baseRotation: Double = 92
        static let baseOpacity: Double = 0.5

        /// How far each property wanders. Large: a blur this heavy erases
        /// anything subtler than its own radius.
        static let scaleSwing: CGFloat = 0.22
        static let rotationSwing: Double = 30
        static let driftRadius: CGFloat = 28
        static let opacitySwing: Double = 0.22

        /// Glow strength on Liquid Glass; 1 is the black look.
        static let liquidGlassIntensity: Double = 2.5

        /// Seconds per cycle, sharing no common multiple.
        static let breathePeriod: Double = 3.7
        static let rotatePeriod: Double = 6.1
        static let swayPeriod: Double = 4.3
        static let bobPeriod: Double = 5.9
        static let shimmerPeriod: Double = 2.9

        /// Low: each frame re-blurs a full-size image.
        static let frameRate: Double = 12
    }
}

/// Tuning for the weather page's glow: blurred blobs of the condition's palette.
enum WeatherGlowStyle {
    /// Big: anything smaller than the blur radius does not read as movement.
    static let blur: CGFloat = 42
    static let opacity: Double = 0.5
    /// Stronger on glass, where the value above reads as a faint stain.
    static let glassOpacity: Double = 0.85
    static let baseScale: CGFloat = 1.0
    static let scaleSwing: CGFloat = 0.22
    static let driftRadius: CGFloat = 26

    /// Where each blob sits, as a fraction of the page.
    static let anchors: [(x: Double, y: Double)] = [(0.18, 0.30), (0.62, 0.72), (0.92, 0.22)]

    static let breathePeriod: Double = 4.1
    static let swayPeriod: Double = 5.3
    static let bobPeriod: Double = 6.7

    /// How far in from the page's edges the glow has faded to nothing.
    static let edgeFade: CGFloat = 28

    static let frameRate: Double = 12
}

/// Tuning for the falling weather.
enum WeatherPrecipitationStyle {
    /// How many drops at each intensity, over a page of roughly 330x215.
    static let dropsLight = 55
    static let dropsMedium = 110
    static let dropsHeavy = 170
    static let flakes = 70

    /// Fractions of the view's height travelled per second.
    static let rainSpeed: ClosedRange<Double> = 0.55...1.15
    static let snowSpeed: ClosedRange<Double> = 0.10...0.22

    /// How far a drop leans as it falls, as a fraction of the view's width.
    static let rainSlant: Double = 0.055
    /// How far a flake wanders either side of its line.
    static let snowSway: Double = 9

    static let rainLength: ClosedRange<Double> = 10...24
    static let flakeRadius: ClosedRange<Double> = 1.0...2.4
    /// Kept low: the page's own text sits under this.
    static let opacity: ClosedRange<Double> = 0.22...0.58
    static let rainWidth: CGFloat = 1.2

    /// Higher than the glow's: a drop crosses several of its own lengths per frame.
    static let frameRate: Double = 30

    /// How far in from the top the shower fades out; roughly a drop's length.
    static let topFade: CGFloat = 22

    /// How far past the page's bottom the shower runs, behind the page dots.
    static let bottomBleed: CGFloat = 14

    /// Longer than the top's: it has the bleed to fade across.
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
    var notchHeight: CGFloat = Defaults[.nonNotchHeight]
    var notchWidth: CGFloat = 185

    var selectedScreen = NSScreen.main

    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }

    if let screen = selectedScreen {
        if let topLeftNotchpadding: CGFloat = screen.auxiliaryTopLeftArea?.width,
           let topRightNotchpadding: CGFloat = screen.auxiliaryTopRightArea?.width
        {
            notchWidth = screen.frame.width - topLeftNotchpadding - topRightNotchpadding + 4
        }

        if screen.safeAreaInsets.top > 0 {
            notchHeight = Defaults[.notchHeight]
            if Defaults[.notchHeightMode] == .matchRealNotchSize {
                notchHeight = screen.safeAreaInsets.top
            } else if Defaults[.notchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            }
        } else {
            notchHeight = Defaults[.nonNotchHeight]
            if Defaults[.nonNotchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            }
        }
    }

    return .init(width: notchWidth, height: notchHeight)
}
