//
//  Constants.swift
//  VornyxNotch
//
//  Created by Richard Kunkli on 2024. 10. 17..
//

import SwiftUI
import Defaults

private let availableDirectories = FileManager
    .default
    .urls(for: .documentDirectory, in: .userDomainMask)
let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
let bundleIdentifier = Bundle.main.bundleIdentifier!
let appVersion = "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))"

let temporaryDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
let spacing: CGFloat = 16

struct CustomVisualizer: Codable, Hashable, Equatable, Defaults.Serializable {
    let UUID: UUID
    var name: String
    var url: URL
    var speed: CGFloat = 1.0
}

enum CalendarSelectionState: Codable, Defaults.Serializable {
    case all
    case selected(Set<String>)
}

/// Which of the dashboard's left-hand pages is showing.
///
/// The drawer of things you glance at rather than work in. Order is the order
/// you swipe through them.
enum DashboardLeftPage: String, CaseIterable, Defaults.Serializable {
    case calendar
    case weather
    case timer
    case stats

    var name: String {
        switch self {
        case .calendar: return "Calendar"
        case .weather: return "Weather"
        case .timer: return "Timer"
        case .stats: return "Stats"
        }
    }

    var symbol: String {
        switch self {
        case .calendar: return "calendar"
        case .weather: return "cloud.sun.fill"
        case .timer: return "timer"
        case .stats: return "chart.bar.fill"
        }
    }
}

/// Units for the weather page.
///
/// `automatic` follows the locale, which is right for almost everybody; the
/// other two are for people whose Mac is set to one country and whose head is
/// set to another.
enum WeatherUnit: String, CaseIterable, Identifiable, Defaults.Serializable {
    case automatic
    case celsius
    case fahrenheit

    var id: String { rawValue }

    var name: String {
        switch self {
        case .automatic: return "Automatic"
        case .celsius: return "Celsius"
        case .fahrenheit: return "Fahrenheit"
        }
    }

    private var isFahrenheit: Bool {
        switch self {
        case .celsius: return false
        case .fahrenheit: return true
        case .automatic: return Locale.current.measurementSystem == .us
        }
    }

    var apiValue: String { isFahrenheit ? "fahrenheit" : "celsius" }
    var windAPIValue: String { isFahrenheit ? "mph" : "kmh" }
    var degreeSuffix: String { isFahrenheit ? "F" : "C" }
    var windSuffix: String { isFahrenheit ? "mph" : "km/h" }
}

enum HideNotchOption: String, Defaults.Serializable {
    case always
    case nowPlayingOnly
    case never
}

// Define notification names at file scope
extension Notification.Name {
    static let mediaControllerChanged = Notification.Name("mediaControllerChanged")
}

// Media controller types for selection in settings
enum MediaControllerType: String, CaseIterable, Identifiable, Defaults.Serializable {
    case nowPlaying = "Now Playing"
    case appleMusic = "Apple Music"
    case spotify = "Spotify"
    case youtubeMusic = "YouTube Music"
    
    var id: String { self.rawValue }
}

/// How the home page's artwork changes over to the next track.
enum TrackChangeAnimation: String, CaseIterable, Identifiable, Defaults.Serializable {
    case blur = "Blur"
    case flip = "Flip and shine"

    var id: String { rawValue }
}

// Sneak peek styles for selection in settings
enum SneakPeekStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case standard = "Default"
    case inline = "Inline"
    
    var id: String { self.rawValue }
}

// Action to perform when Option (⌥) is held while pressing media keys
enum OptionKeyAction: String, CaseIterable, Identifiable, Defaults.Serializable {
    case openSettings = "Open System Settings"
    case showHUD = "Show HUD"
    case none = "No Action"

    var id: String { self.rawValue }
}

extension Defaults.Keys {
    // MARK: General
    // Off by default: the notch carries its own Settings and Quit, so the
    // status item only takes room in the menu bar.
    static let menubarIcon = Key<Bool>("menubarIcon", default: false)
    static let showOnAllDisplays = Key<Bool>("showOnAllDisplays", default: false)
    static let automaticallySwitchDisplay = Key<Bool>("automaticallySwitchDisplay", default: true)
    static let releaseName = Key<String>("releaseName", default: "Flying Rabbit 🐇🪽")
    
    // MARK: Behavior
    static let minimumHoverDuration = Key<TimeInterval>("minimumHoverDuration", default: 0.3)
    static let enableHaptics = Key<Bool>("enableHaptics", default: true)
    static let hapticStrength = Key<HapticStrength>(
        "hapticStrength", default: HapticStrength.strong)
    static let openNotchOnHover = Key<Bool>("openNotchOnHover", default: true)
    static let extendHoverArea = Key<Bool>("extendHoverArea", default: false)
    static let notchHeightMode = Key<WindowHeightMode>(
        "notchHeightMode",
        default: WindowHeightMode.matchRealNotchSize
    )
    static let nonNotchHeightMode = Key<WindowHeightMode>(
        "nonNotchHeightMode",
        default: WindowHeightMode.matchMenuBar
    )
    static let nonNotchHeight = Key<CGFloat>("nonNotchHeight", default: 32)
    static let notchHeight = Key<CGFloat>("notchHeight", default: 32)
    //static let openLastTabByDefault = Key<Bool>("openLastTabByDefault", default: false)
    static let showOnLockScreen = Key<Bool>("showOnLockScreen", default: false)
    static let hideFromScreenRecording = Key<Bool>("hideFromScreenRecording", default: false)
    
    // MARK: Appearance
    static let showEmojis = Key<Bool>("showEmojis", default: false)
    //static let alwaysShowTabs = Key<Bool>("alwaysShowTabs", default: true)
    static let showMirror = Key<Bool>("showMirror", default: true)
    static let mirrorShape = Key<MirrorShapeEnum>("mirrorShape", default: MirrorShapeEnum.rectangle)
    static let settingsIconInNotch = Key<Bool>("settingsIconInNotch", default: true)
    static let lightingEffect = Key<Bool>("lightingEffect", default: true)
    static let enableShadow = Key<Bool>("enableShadow", default: true)
    /// The open notch as Liquid Glass under a black band. macOS 26 and later;
    /// earlier systems keep the black notch whatever this says.
    static let liquidGlassNotch = Key<Bool>("liquidGlassNotch", default: true)


    static let showNotHumanFace = Key<Bool>("showNotHumanFace", default: false)
    static let tileShowLabels = Key<Bool>("tileShowLabels", default: false)
    static let showCalendar = Key<Bool>("showCalendar", default: false)
    /// Website shortcuts shown in the middle of the dashboard tab.
    static let webShortcuts = Key<[WebShortcut]>("webShortcuts", default: [])

    // MARK: Audio
    /// A sound-output menu in the open notch's header.
    static let showAudioPicker = Key<Bool>("showAudioPicker", default: true)

    // MARK: Indicators
    /// A light while the camera or the microphone is in use by anything.
    static let showPrivacyIndicators = Key<Bool>("showPrivacyIndicators", default: true)
    /// A light while a Focus is on. Read from Control Center's menu bar item.
    static let showFocusIndicator = Key<Bool>("showFocusIndicator", default: false)
    static let showCapsLockIndicator = Key<Bool>("showCapsLockIndicator", default: true)
    /// Say it under the closed notch as it happens, as well as lighting the edge.
    static let capsLockSneakPeek = Key<Bool>("capsLockSneakPeek", default: true)
    /// The notch outlining itself while the camera or microphone is in use.
    static let recordingGlow = Key<Bool>("recordingGlow", default: true)
    /// The outline filling as a LocalSend transfer or the timer runs.
    static let notchEdgeProgress = Key<Bool>("notchEdgeProgress", default: true)
    /// The outline colouring when the battery fills or runs low.
    static let notchEdgeBattery = Key<Bool>("notchEdgeBattery", default: true)
    /// The closed notch lit in the current cover's colour while music plays.
    static let notchEdgeAmbient = Key<Bool>("notchEdgeAmbient", default: true)

    // MARK: Timer
    /// Seconds the last countdown was set to, so the same one is one tap away.
    static let timerLastDuration = Key<Double>("timerLastDuration", default: 5 * 60)
    /// Show the countdown in the closed notch while it runs.
    static let timerLiveActivity = Key<Bool>("timerLiveActivity", default: true)
    static let timerSound = Key<Bool>("timerSound", default: true)

    // MARK: Stats
    /// How often the machine is measured, in seconds. Cheap, but not free.
    static let statsInterval = Key<Double>("statsInterval", default: 2)

    // MARK: Clipboard
    static let clipboardEnabled = Key<Bool>("clipboardEnabled", default: false)
    static let clipboardHistoryLimit = Key<Int>("clipboardHistoryLimit", default: 30)
    static let clipboardPersistHistory = Key<Bool>("clipboardPersistHistory", default: true)
    /// Double-tapping right Option opens the clipboard tab.
    static let clipboardDoubleTapRightOption = Key<Bool>("clipboardDoubleTapRightOption", default: true)

    // MARK: AI
    static let aiEnabled = Key<Bool>("aiEnabled", default: false)
    /// Which keychain accounts actually hold something. Not a secret - it only
    /// records presence, so the app can answer "no key saved" without making a
    /// keychain call and provoking an access prompt.
    static let keychainAccountsInUse = Key<Set<String>>("keychainAccountsInUse", default: [])
    /// Grace period before the notch closes while the AI tab is open. Reading a
    /// reply means looking away from the notch, which would normally close it.
    static let aiTabCloseDelay = Key<Double>("aiTabCloseDelay", default: 8)
    static let geminiModel = Key<String>("geminiModel", default: GeminiClient.newestModel)
    /// Gemini 3 thinks before answering, which costs seconds of silence on
    /// questions that never needed it. Off by default - the notch has room for
    /// short answers, and waiting is worse here than in a full chat window.
    /// Gemini 3 cannot stop thinking entirely, so "off" means the lowest level.
    static let aiThinking = Key<Bool>("aiThinking", default: false)
    /// Model ids the app itself shipped as a default. A stale one gets bumped
    /// to the current model once, so upgrading users are not left on an old
    /// model they never chose. Anything typed by hand is left alone.
    static let supersededGeminiModels: Set<String> = ["gemini-2.5-flash"]
    static let didUpgradeGeminiModel = Key<Bool>("didUpgradeGeminiModel", default: false)
    static let aiSystemPrompt = Key<String>(
        "aiSystemPrompt",
        default: "You are a helpful assistant living in a small notch window on a Mac. Answer briefly and directly.")
    static let mirrorDisplayMode = Key<MirrorDisplayMode>(
        "mirrorDisplayMode", default: MirrorDisplayMode.bigScreen)
    static let mirrorBigScreenHeight = Key<CGFloat>("mirrorBigScreenHeight", default: 300)
    static let hideCompletedReminders = Key<Bool>("hideCompletedReminders", default: true)
    static let sliderColor = Key<SliderColorEnum>(
        "sliderUseAlbumArtColor",
        default: SliderColorEnum.white
    )
    static let playerColorTinting = Key<Bool>("playerColorTinting", default: true)
    /// Glow behind the played portion of the music slider, like the HUD's.
    static let sliderGlow = Key<Bool>("sliderGlow", default: false)
    static let useMusicVisualizer = Key<Bool>("useMusicVisualizer", default: true)
    /// Drive the visualizer from the audio actually playing. Off by default:
    /// it needs the system audio permission, and the bars work without it.
    static let realAudioSpectrum = Key<Bool>("realAudioSpectrum", default: false)
    static let customVisualizers = Key<[CustomVisualizer]>("customVisualizers", default: [])
    static let selectedVisualizer = Key<CustomVisualizer?>("selectedVisualizer", default: nil)
    
    // MARK: Gestures
    static let enableGestures = Key<Bool>("enableGestures", default: true)
    static let closeGestureEnabled = Key<Bool>("closeGestureEnabled", default: true)
    /// A horizontal swipe across the closed notch skips tracks.
    static let mediaSwipeGesture = Key<Bool>("mediaSwipeGesture", default: true)
    static let gestureSensitivity = Key<CGFloat>("gestureSensitivity", default: 200.0)
    
    // MARK: Media playback
    static let coloredSpectrogram = Key<Bool>("coloredSpectrogram", default: true)
    static let enableSneakPeek = Key<Bool>("enableSneakPeek", default: true)
    static let sneakPeekStyles = Key<SneakPeekStyle>("sneakPeekStyles", default: .standard)
    static let waitInterval = Key<Double>("waitInterval", default: 3)
    /// How long a sneak peek stays on screen before it hides itself.
    static let sneakPeekDuration = Key<Double>("sneakPeekDuration", default: 2.0)
    static let showShuffleAndRepeat = Key<Bool>("showShuffleAndRepeat", default: false)
    static let enableLyrics = Key<Bool>("enableLyrics", default: false)
    /// How the artwork changes when the track does.
    static let trackChangeAnimation = Key<TrackChangeAnimation>("trackChangeAnimation", default: .flip)
    static let musicControlSlots = Key<[MusicControlButton]>(
        "musicControlSlots",
        default: MusicControlButton.defaultLayout
    )
    static let musicControlSlotLimit = Key<Int>(
        "musicControlSlotLimit",
        default: MusicControlButton.defaultLayout.count
    )
    
    // MARK: Battery
    static let showPowerStatusNotifications = Key<Bool>("showPowerStatusNotifications", default: true)
    static let showBatteryIndicator = Key<Bool>("showBatteryIndicator", default: true)
    static let showBatteryPercentage = Key<Bool>("showBatteryPercentage", default: true)
    static let showPowerStatusIcons = Key<Bool>("showPowerStatusIcons", default: true)

    // MARK: AirPods
    /// Announce a pair connecting in the closed notch.
    static let airPodsSneakPeek = Key<Bool>("airPodsSneakPeek", default: true)
    /// Show the levels beside the player on the home page while a pair is
    /// connected. Off by default: it widens the home notch, which is not
    /// something to do uninvited.
    static let showAirPodsWidget = Key<Bool>("showAirPodsWidget", default: false)

    // MARK: Sound output
    /// Announce in the closed notch when sound moves to another output - a pair
    /// connecting, or dropping back to the built-in speakers.
    static let audioRouteSneakPeek = Key<Bool>("audioRouteSneakPeek", default: true)
    
    // MARK: Weather
    /// Remembered so the dashboard opens on whichever of the two you left it on.
    static let dashboardLeftPage = Key<DashboardLeftPage>("dashboardLeftPage", default: .calendar)
    /// A place name typed in Settings. Empty means "use where this Mac is".
    static let weatherPlace = Key<String>("weatherPlace", default: "")
    static let weatherUnit = Key<WeatherUnit>("weatherUnit", default: .automatic)

    // MARK: Downloads
    static let enableDownloadListener = Key<Bool>("enableDownloadListener", default: true)
    static let enableSafariDownloads = Key<Bool>("enableSafariDownloads", default: true)
    static let selectedDownloadIndicatorStyle = Key<DownloadIndicatorStyle>("selectedDownloadIndicatorStyle", default: DownloadIndicatorStyle.progress)
    static let selectedDownloadIconStyle = Key<DownloadIconStyle>("selectedDownloadIconStyle", default: DownloadIconStyle.onlyAppIcon)
    
    // MARK: HUD
    static let hudReplacement = Key<Bool>("hudReplacement", default: false)
    static let inlineHUD = Key<Bool>("inlineHUD", default: false)
    static let enableGradient = Key<Bool>("enableGradient", default: false)
    static let systemEventIndicatorShadow = Key<Bool>("systemEventIndicatorShadow", default: false)
    static let systemEventIndicatorUseAccent = Key<Bool>("systemEventIndicatorUseAccent", default: false)
    static let showOpenNotchHUD = Key<Bool>("showOpenNotchHUD", default: true)
    static let showOpenNotchHUDPercentage = Key<Bool>("showOpenNotchHUDPercentage", default: true)
    static let showClosedNotchHUDPercentage = Key<Bool>("showClosedNotchHUDPercentage", default: false)
    // Option key modifier behaviour for media keys
    static let optionKeyAction = Key<OptionKeyAction>("optionKeyAction", default: OptionKeyAction.openSettings)
    
    // MARK: Shelf
    static let shelfEnabled = Key<Bool>("shelfEnabled", default: true)
    /// Off: opening the notch lands on home even when the shelf holds files.
    /// Anything left on the shelf otherwise hijacks every open.
    static let openShelfByDefault = Key<Bool>("openShelfByDefault", default: false)
    static let shelfTapToOpen = Key<Bool>("shelfTapToOpen", default: true)
    static let quickShareProvider = Key<String>("quickShareProvider", default: QuickShareProvider.defaultProvider.id)
    static let copyOnDrag = Key<Bool>("copyOnDrag", default: false)
    static let autoRemoveShelfItems = Key<Bool>("autoRemoveShelfItems", default: false)
    static let expandedDragDetection = Key<Bool>("expandedDragDetection", default: true)

    // MARK: LocalSend
    /// Off by default: turning it on starts a server on the local network and
    /// raises macOS's local network prompt, neither of which should happen to
    /// someone who never asked for it.
    static let localSendEnabled = Key<Bool>("localSendEnabled", default: false)
    /// The name other devices see. Empty means "Vornyx Notch".
    static let localSendAlias = Key<String>("localSendAlias", default: "")
    /// Take incoming files without asking. Off: anyone on the network can
    /// offer a file, and saying yes should be a decision.
    static let localSendAutoAccept = Key<Bool>("localSendAutoAccept", default: false)
    /// Put received files on the shelf as well as in Downloads.
    static let localSendAddToShelf = Key<Bool>("localSendAddToShelf", default: true)
    /// A short sound when a send goes through and when something arrives.
    static let localSendSounds = Key<Bool>("localSendSounds", default: true)
    /// Put received images on the clipboard, ready to paste anywhere.
    static let localSendCopyImages = Key<Bool>("localSendCopyImages", default: true)
    
    // MARK: Calendar
    static let calendarSelectionState = Key<CalendarSelectionState>("calendarSelectionState", default: .all)
    static let hideAllDayEvents = Key<Bool>("hideAllDayEvents", default: false)
    static let showFullEventTitles = Key<Bool>("showFullEventTitles", default: false)
    static let autoScrollToNextEvent = Key<Bool>("autoScrollToNextEvent", default: true)
    
    // MARK: Fullscreen Media Detection
    static let hideNotchOption = Key<HideNotchOption>("hideNotchOption", default: .nowPlayingOnly)
    
    // MARK: Media Controller
    /// A second player watched alongside `mediaController`. Nil for one
    /// source, which is how it was before. Never `nowPlaying`: that one already
    /// answers for whatever the system plays, so pairing it with a single app
    /// would have both reporting the same track.
    static let secondaryMediaController = Key<MediaControllerType?>(
        "secondaryMediaController", default: nil)
    static let mediaController = Key<MediaControllerType>("mediaController", default: defaultMediaController)
    
    // MARK: Advanced Settings
    static let useCustomAccentColor = Key<Bool>("useCustomAccentColor", default: false)
    static let customAccentColorData = Key<Data?>("customAccentColorData", default: nil)
    // Show or hide the title bar
    static let hideTitleBar = Key<Bool>("hideTitleBar", default: true)
    
    // Helper to determine the default media controller based on NowPlaying deprecation status
    static var defaultMediaController: MediaControllerType {
        if MusicManager.shared.isNowPlayingDeprecated {
            return .appleMusic
        } else {
            return .nowPlaying
        }
    }

    static let didClearLegacyURLCacheV1 = Key<Bool>("didClearLegacyURLCache_v1", default: false)
}
