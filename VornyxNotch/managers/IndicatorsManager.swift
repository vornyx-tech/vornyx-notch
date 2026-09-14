//
//  IndicatorsManager.swift
//  VornyxNotch
//
//  The small facts about the machine worth a light in the notch: the camera,
//  the microphone, Focus, and Caps Lock.
//

import AppKit
import Combine
import CoreAudio
import CoreMediaIO
import Defaults
import Foundation
import Intents

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
/// Polled rather than driven by property listeners: each answer costs two
/// HAL property reads, the C callback plumbing for listeners is considerable,
/// and a second's lag on "the camera came on" is not a second anybody notices.
///
/// Every source here works inside the app sandbox. That rules out the way this
/// is usually done for Focus - reading `~/Library/DoNotDisturb/DB` - so Focus
/// comes from `INFocusStatusCenter`, which asks the user once and then answers
/// honestly.
@MainActor
final class IndicatorsManager: ObservableObject {
    static let shared = IndicatorsManager()

    @Published private(set) var indicators = SystemIndicators()
    /// Nil until asked. Focus is the only indicator that needs permission.
    @Published private(set) var focusAuthorized: Bool?

    private var ticker: AnyCancellable?

    private init() {}

    func start() {
        guard ticker == nil else { return }
        requestFocusAuthorizationIfNeeded()
        poll()
        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.poll() }
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
    }

    // MARK: - Polling

    private func poll() {
        var next = SystemIndicators()

        if Defaults[.showPrivacyIndicators] {
            next.camera = Self.cameraInUse()
            next.microphone = Self.microphoneInUse()
        }
        if Defaults[.showFocusIndicator], focusAuthorized == true {
            next.focus = INFocusStatusCenter.default.focusStatus.isFocused ?? false
        }
        if Defaults[.showCapsLockIndicator] {
            // No permission and no monitor: the modifier flags are readable at
            // any time, which is the whole reason this one is free.
            next.capsLock = NSEvent.modifierFlags.contains(.capsLock)
        }

        guard next != indicators else { return }
        indicators = next
    }

    private func requestFocusAuthorizationIfNeeded() {
        guard Defaults[.showFocusIndicator] else { return }

        let current = INFocusStatusCenter.default.authorizationStatus
        switch current {
        case .authorized:
            focusAuthorized = true
        case .denied, .restricted:
            focusAuthorized = false
        default:
            INFocusStatusCenter.default.requestAuthorization { [weak self] status in
                Task { @MainActor in self?.focusAuthorized = status == .authorized }
            }
        }
    }

    /// Ask again after the setting is turned on, since the first request only
    /// happens at start-up.
    func refreshFocusAuthorization() {
        requestFocusAuthorizationIfNeeded()
    }

    // MARK: - Camera

    /// True when any video device is running for anybody - us included.
    ///
    /// `kAudioDevicePropertyDeviceIsRunningSomewhere` is not a typo: the
    /// CoreMediaIO device model is CoreAudio's, and video devices answer the
    /// same selector.
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

        for device in devices where hasInput(device) {
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

    /// Output-only devices answer the running property too, so without this
    /// every speaker playing anything would read as a live microphone.
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
