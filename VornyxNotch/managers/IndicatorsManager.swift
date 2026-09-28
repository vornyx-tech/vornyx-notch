//
//  IndicatorsManager.swift
//  VornyxNotch
//
//  The camera, the microphone, Focus and Caps Lock.
//

import AppKit
import Combine
import CoreAudio
import CoreMediaIO
import Defaults
import Foundation

/// Whether each indicator is currently on.
struct SystemIndicators: Equatable {
    var camera = false
    var microphone = false
    var focus = false
    var capsLock = false

    var any: Bool { camera || microphone || focus || capsLock }
}

/// Polls the four indicators.
///
/// Focus comes from the best source that answers, all through the helper,
/// which is not sandboxed: the file macOS writes the active Focus to (Full
/// Disk Access, and it names the mode), then Control Center's menu bar item
/// (Accessibility), then the system's own distributed notifications, which
/// need nothing but on macOS 26 do not always say when a Focus ends.
@MainActor
final class IndicatorsManager: ObservableObject {
    static let shared = IndicatorsManager()

    @Published private(set) var indicators = SystemIndicators()
    /// The helper's last answer about Focus, for Settings to explain a light
    /// that never comes on. Nil until it has answered.
    @Published private(set) var focusStatus: FocusStatus?
    /// The active Focus, when the source can tell which one.
    @Published private(set) var focusMode: FocusMode?
    /// The last mode seen on, so "Off" can say which one ended.
    @Published private(set) var lastFocusMode: FocusMode?
    /// A Focus went on or off a moment ago: after its banner, the closed
    /// notch keeps a slim peek of it - the mode's symbol, On or Off - then
    /// lets it go.
    @Published private(set) var focusJustOn = false
    private var focusJustOnTask: Task<Void, Never>?
    /// The banner's three seconds, then five more as a slim peek.
    static let focusInlineSeconds: Double = 8
    /// Whether the Focus file is readable - the source that needs nothing
    /// else set up.
    @Published private(set) var readsFocusFile = false

    private var ticker: AnyCancellable?
    /// Caps Lock on its own, faster ticker: reading modifier flags costs
    /// nothing, and a second's wait for the light is a second too long.
    private var capsTicker: AnyCancellable?
    /// Last answer from the helper, and the question still out, if any.
    private var focusFromMenuBar = false
    private var focusQuery: Task<Void, Never>?
    /// What the last distributed notification said, for when neither the
    /// file nor the menu bar can be read.
    private var focusFromNotification: Bool?
    private var focusObservers: [NSObjectProtocol] = []
    /// No banner for the state found at launch, only for changes after it.
    private var focusKnown = false

    private init() {}

    func start() {
        guard ticker == nil else { return }
        observeFocusNotifications()
        poll()
        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.poll() }
        capsTicker = Timer.publish(every: 0.2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.pollCapsLock() }
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        capsTicker?.cancel()
        capsTicker = nil
        focusQuery?.cancel()
        focusQuery = nil
        focusObservers.forEach(DistributedNotificationCenter.default().removeObserver)
        focusObservers = []
    }

    // MARK: - Polling

    private func pollCapsLock() {
        let on = Defaults[.showCapsLockIndicator] && NSEvent.modifierFlags.contains(.capsLock)
        guard on != indicators.capsLock else { return }
        var next = indicators
        next.capsLock = on
        indicators = next

        if Defaults[.capsLockSneakPeek] {
            VornyxViewCoordinator.shared.toggleSneakPeek(
                status: true, type: .capsLock, duration: 1.4, value: on ? 1 : 0)
        }
    }

    private func poll() {
        var next = SystemIndicators()

        if Defaults[.showPrivacyIndicators] {
            next.camera = Self.cameraInUse()
            next.microphone = Self.microphoneInUse()
        }
        if Defaults[.showFocusIndicator] {
            next.focus = focusFromMenuBar
            refreshFocus()
        }
        if Defaults[.showCapsLockIndicator] {
            // Modifier flags are readable without permission or a monitor.
            next.capsLock = NSEvent.modifierFlags.contains(.capsLock)
        }

        guard next != indicators else { return }
        indicators = next
    }

    /// Asks the helper, and publishes the answer without waiting for the next
    /// tick.
    private func refreshFocus() {
        guard focusQuery == nil else { return }
        focusQuery = Task { [weak self] in
            let client = XPCHelperClient.shared
            let file = await client.focusAssertionState()
            var focused: Bool
            var mode: FocusMode?
            var menuBarStatus: FocusStatus?

            switch file {
            case .on(let identifier, let name, let symbol, let tint)?:
                focused = true
                // The mode's own name, symbol and colour when macOS gives
                // them; the identifier's reading otherwise.
                mode = name.map { FocusMode.configured(name: $0, symbol: symbol, tintName: tint, identifier: identifier) }
                    ?? FocusMode(identifier: identifier)
            case .off?:
                focused = false
            case .unreadable?, nil:
                menuBarStatus = await client.focusStatus()
                switch menuBarStatus {
                case .on?:
                    focused = true
                    // The item's own words name the mode, when the file
                    // that would say it exactly is out of reach.
                    if let title = await client.focusMenuExtraTitle() {
                        mode = FocusMode(menuTitle: title)
                    }
                case .off?: focused = false
                default: focused = false
                }
            }

            guard let self, !Task.isCancelled else { return }
            self.focusQuery = nil

            let readsFile = file == .off || { if case .on = file { return true }; return false }()
            if readsFile != self.readsFocusFile { self.readsFocusFile = readsFile }
            if menuBarStatus != self.focusStatus, !readsFile { self.focusStatus = menuBarStatus }
            // Neither source readable: the notifications are all there is.
            if !readsFile, menuBarStatus != .on, menuBarStatus != .off {
                focused = self.focusFromNotification ?? false
            }
            self.apply(focused: focused, mode: mode)
        }
    }

    private func apply(focused: Bool, mode: FocusMode?) {
        let changed = focused != focusFromMenuBar
        let modeChanged = focused && mode != nil && mode != focusMode
        focusFromMenuBar = focused
        if focusMode != (focused ? mode : nil) { focusMode = focused ? mode : nil }
        if focused, let mode, mode != lastFocusMode { lastFocusMode = mode }

        var next = indicators
        next.focus = focused && Defaults[.showFocusIndicator]
        if next != indicators { indicators = next }

        // The banner, then a slim peek for a few seconds, on or off.
        if focusKnown, changed || modeChanged, Defaults[.showFocusIndicator], Defaults[.focusLiveActivity] {
            VornyxViewCoordinator.shared.announceFocus()
            holdFocusInline()
        }
        focusKnown = true
    }

    /// Keeps the Focus in the closed notch for a while after it comes on.
    func holdFocusInline() {
        focusJustOnTask?.cancel()
        focusJustOn = true
        focusJustOnTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.focusInlineSeconds))
            guard !Task.isCancelled else { return }
            self?.focusJustOn = false
        }
    }

    /// `_NSDoNotDisturbEnabledNotification` and its opposite: posted by the
    /// system, delivered to a sandboxed app, and immediate - so each one also
    /// asks the helper at once rather than waiting for the next tick.
    private func observeFocusNotifications() {
        guard focusObservers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        for (name, on) in [("_NSDoNotDisturbEnabledNotification", true),
                           ("_NSDoNotDisturbDisabledNotification", false)] {
            focusObservers.append(center.addObserver(
                forName: .init(name), object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, Defaults[.showFocusIndicator] else { return }
                    self.focusFromNotification = on
                    self.refreshFocus()
                }
            })
        }
    }

    // MARK: - Camera

    /// True when any video device is running, this app included.
    /// `kAudioDevicePropertyDeviceIsRunningSomewhere` is not a typo: the
    /// CoreMediaIO device model is CoreAudio's and answers the same selector.
    private static func cameraInUse() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(
            CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &dataSize
        ) == OSStatus(kCMIOHardwareNoError), dataSize > 0 else { return false }

        let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, dataSize, &used, &devices
        ) == OSStatus(kCMIOHardwareNoError) else { return false }

        var running = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kAudioDevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
        )

        for device in devices {
            var isRunning: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            var got: UInt32 = 0
            let status = CMIOObjectGetPropertyData(
                device, &running, 0, nil, size, &got, &isRunning
            )
            _ = size
            if status == OSStatus(kCMIOHardwareNoError), isRunning != 0 { return true }
        }
        return false
    }

    // MARK: - Microphone

    private static func microphoneInUse() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize
        ) == noErr, dataSize > 0 else { return false }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var devices = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &devices
        ) == noErr else { return false }

        // The visualizer's own private device takes the tap's audio in, so it
        // reads as an input running - the notch lit orange for a microphone
        // that nobody was using. It is not a microphone.
        let own = SystemAudioLevels.shared.ownDeviceID
        for device in devices where device != own && hasInput(device) {
            var running = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var isRunning: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(device, &running, 0, nil, &size, &isRunning) == noErr,
               isRunning != 0 {
                return true
            }
        }
        return false
    }

    /// Output-only devices answer the running property too, so they have to be
    /// filtered out.
    private static func hasInput(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &dataSize) == noErr,
              dataSize > 0 else { return false }

        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { buffer.deallocate() }

        guard AudioObjectGetPropertyData(device, &address, 0, nil, &dataSize, buffer) == noErr
        else { return false }

        let list = UnsafeMutableAudioBufferListPointer(
            buffer.assumingMemoryBound(to: AudioBufferList.self)
        )
        return list.contains { $0.mNumberChannels > 0 }
    }
}
