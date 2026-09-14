//
//  AudioDeviceManager.swift
//  VornyxNotch
//
//  Where the sound is going, and switching it.
//

import Combine
import CoreAudio
import Defaults
import Foundation

struct AudioDevice: Identifiable, Equatable {
    let id: AudioObjectID
    let name: String
    let transport: UInt32

    var isBluetooth: Bool {
        transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    /// The glyph that matches how it is plugged in. Transport type rather than
    /// a guess from the name: "MacBook Pro Speakers" and "Vania's AirPods" are
    /// only distinguishable by name in English.
    var symbol: String {
        switch transport {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return "airpods.gen3"
        case kAudioDeviceTransportTypeUSB:
            return "hifispeaker.fill"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            return "tv.fill"
        case kAudioDeviceTransportTypeAirPlay:
            return "airplayaudio"
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate:
            return "waveform"
        default:
            return "laptopcomputer"
        }
    }
}

/// The output devices available, and which one is in use.
///
/// CoreAudio's HAL is readable and writable from inside the sandbox, so this
/// needs no entitlement - switching output is the one piece of audio routing
/// that comes for free.
@MainActor
final class AudioDeviceManager: ObservableObject {
    static let shared = AudioDeviceManager()

    @Published private(set) var devices: [AudioDevice] = []
    @Published private(set) var currentID: AudioObjectID?

    private var listening = false

    /// The output the notch has already announced. Set on the first read, so
    /// whatever was in use at launch is never announced as a change.
    private var announcedID: AudioObjectID?

    private init() {}

    // MARK: - Watching

    func start() {
        refresh(announce: false)
        guard !listening else { return }
        listening = true

        // The list changes when anything is plugged in or paired, and the
        // default changes when anything - including macOS itself - switches it.
        for selector in [kAudioHardwarePropertyDevices,
                         kAudioHardwarePropertyDefaultOutputDevice] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, .main
            ) { [weak self] _, _ in
                Task { @MainActor in self?.refresh(announce: true) }
            }
        }
    }

    func refresh() {
        refresh(announce: false)
    }

    /// Re-read the list and the default, and - when asked - let the notch say
    /// so if the default has actually moved.
    ///
    /// Both listeners land here, and the device list changing on its own (a
    /// cable in, a pair pairing) is not a route change: only a different
    /// default output is worth a banner.
    private func refresh(announce: Bool) {
        devices = Self.outputDevices()
        let newID = Self.defaultOutputDevice()
        let moved = newID != currentID
        currentID = newID

        guard let newID, moved || announcedID == nil else { return }

        // The first read is the baseline, not news.
        guard announce, announcedID != nil, announcedID != newID else {
            announcedID = newID
            return
        }
        announcedID = newID

        guard Defaults[.audioRouteSneakPeek],
              devices.contains(where: { $0.id == newID }) else { return }
        VornyxViewCoordinator.shared.announceAudioRoute()
    }

    var current: AudioDevice? {
        devices.first { $0.id == currentID }
    }

    // MARK: - Switching

    @discardableResult
    func select(_ device: AudioDevice) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = device.id
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioObjectID>.size),
            &id
        )
        guard status == noErr else { return false }
        // Picked by hand, from the notch's own menu: the listener will confirm
        // it in a moment, and there is nothing to announce back to whoever
        // just chose it.
        currentID = device.id
        announcedID = device.id
        return true
    }

    // MARK: - Reading

    private static func defaultOutputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id
        ) == noErr, id != 0 else { return nil }
        return id
    }

    private static func outputDevices() -> [AudioDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize
        ) == noErr, dataSize > 0 else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &ids
        ) == noErr else { return [] }

        return ids.compactMap { id in
            // Output channels are what makes it an output: every microphone is
            // in this list too.
            guard channelCount(id, scope: kAudioObjectPropertyScopeOutput) > 0,
                  let name = string(id, selector: kAudioObjectPropertyName)
            else { return nil }
            return AudioDevice(id: id, name: name, transport: transport(id))
        }
    }

    private static func channelCount(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &dataSize) == noErr,
              dataSize > 0 else { return 0 }

        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { buffer.deallocate() }

        guard AudioObjectGetPropertyData(device, &address, 0, nil, &dataSize, buffer) == noErr
        else { return 0 }

        let list = UnsafeMutableAudioBufferListPointer(
            buffer.assumingMemoryBound(to: AudioBufferList.self)
        )
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func string(
        _ device: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr
        else { return nil }
        let name = value as String
        return name.isEmpty ? nil : name
    }

    private static func transport(_ device: AudioObjectID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr
        else { return 0 }
        return value
    }
}
