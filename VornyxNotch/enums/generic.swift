//
//  generic.swift
//  VornyxNotch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Foundation
import AppKit
import Defaults

public enum Style {
    case notch
    case floating
}

public enum ContentType: Int, Codable, Hashable, Equatable {
    case normal
    case menu
    case settings
}

public enum NotchState {
    case closed
    case open
}

public enum NotchViews {
    case home
    case shelf
    case calendar
    case clipboard
    case ai
}

enum SettingsEnum {
    case general
    case about
    case charge
    case download
    case mediaPlayback
    case hud
    case shelf
    case extensions
}

enum DownloadIndicatorStyle: String, Defaults.Serializable {
    case progress = "Progress"
    case percentage = "Percentage"
}

enum DownloadIconStyle: String, Defaults.Serializable {
    case onlyAppIcon = "Only app icon"
    case onlyIcon = "Only download icon"
    case iconAndAppIcon = "Icon and app icon"
}

enum MirrorShapeEnum: String, Defaults.Serializable {
    case rectangle = "Rectangular"
    case circle = "Circular"
}

/// Where the mirror shows up when you tap its header icon.
enum MirrorDisplayMode: String, CaseIterable, Identifiable, Defaults.Serializable {
    /// Squeezed onto the home page beside the player, as it has always been.
    case inline = "On the home page"
    /// A large panel that stretches the notch downwards below whatever tab
    /// is open.
    case bigScreen = "Big screen below"

    var id: String { rawValue }
}

/// How hard the trackpad thumps when a swipe changes page.
///
/// macOS only offers a handful of fixed patterns, and `.alignment` - the one
/// used for scroll detents - is deliberately faint. `.levelChange` is the
/// firmest single pattern available, and repeating it lands harder still.
enum HapticStrength: String, CaseIterable, Identifiable, Defaults.Serializable {
    case light = "Light"
    case medium = "Medium"
    case strong = "Strong"
    case heavy = "Heavy"

    var id: String { rawValue }

    fileprivate var pattern: NSHapticFeedbackManager.FeedbackPattern {
        self == .light ? .alignment : .levelChange
    }

    fileprivate var pulses: Int {
        switch self {
        case .light, .medium: return 1
        case .strong: return 2
        case .heavy: return 3
        }
    }

    /// Gap between pulses. Long enough that the taps read as separate, short
    /// enough that they still feel like one event.
    fileprivate var interval: Duration { .milliseconds(38) }

    @MainActor
    func perform() {
        guard Defaults[.enableHaptics] else { return }

        let performer = NSHapticFeedbackManager.defaultPerformer
        performer.perform(pattern, performanceTime: .now)

        guard pulses > 1 else { return }
        Task { @MainActor in
            for _ in 1..<pulses {
                try? await Task.sleep(for: interval)
                performer.perform(pattern, performanceTime: .now)
            }
        }
    }
}

enum WindowHeightMode: String, Defaults.Serializable {
    case matchMenuBar = "Match menubar height"
    case matchRealNotchSize = "Match real notch height"
    case custom = "Custom height"
}

enum SliderColorEnum: String, CaseIterable, Defaults.Serializable {
    case white = "White"
    case albumArt = "Match album art"
    case accent = "Accent color"
}
