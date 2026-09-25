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
import IOKit.ps

struct AudioDevice: Identifiable, Equatable {
    let id: AudioObjectID
    let name: String
    let transport: UInt32

    var isBluetooth: Bool {
        transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    /// The glyph for this output, by transport and then by name.
    /// `AudioDeviceManager.symbol(for:)` refines it with the pair's own model.
    var symbol: String {
        let lowered = name.lowercased()
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:
            return Self.macSymbol
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            // Product names are not translated, whatever the language.
            if lowered.contains("airpods") || lowered.contains("beats") {
                return AirPodsModel(productID: nil, name: name, hasEars: lowered.contains("airpods")).symbol
            }
            return "headphones"
        case kAudioDeviceTransportTypeUSB:
            return "hifispeaker.fill"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            return "tv.fill"
        case kAudioDeviceTransportTypeAirPlay:
            return lowered.contains("homepod") ? "homepod.fill" : "airplayaudio"
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate:
            return "waveform"
        default:
            return "speaker.wave.2.fill"
        }
    }

    /// This Mac, as a laptop or a desktop. Told apart by an internal battery:
    /// the model identifier no longer says "MacBook".
    private static let macSymbol: String = {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return "desktopcomputer" }
        let hasBattery = sources.contains { source in
            let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any]
            return info?[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
        }
        return hasBattery ? "laptopcomputer" : "desktopcomputer"
    }()
}

/// The output devices available, and which one is in use. CoreAudio's HAL is
/// readable and writable from inside the sandbox, so this needs no entitlement.
@MainActor
final class AudioDeviceManager: ObservableObject {
    static let shared = AudioDeviceManager()

    @Published private(set) var devices: [AudioDevice] = []
    @Published private(set) var currentID: AudioObjectID?

    private var listening = false

    /// The output the notch has already announced, set on the first read.
    private var announcedID: AudioObjectID?

    private init() {}

    // MARK: - Watching

    func start() {
        refresh(announce: false)
        guard !listening else { return }
        listening = true

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

    /// Re-read the list and the default. Both listeners land here, but only a
    /// different default output is worth a banner.
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

    /// The glyph for an output, used by the menu, the route banner and the
    /// volume HUD. A Bluetooth output matching the connected pair gets that
    /// pair's model symbol; built-in output is the Mac, or the headphone jack
    /// when that data source is in use.
    func symbol(for device: AudioDevice) -> String {
        if device.isBluetooth, let pair = AirPodsManager.shared.device,
           device.name.localizedCaseInsensitiveContains(pair.name) {
            return pair.model.symbol
        }
        if device.transport == kAudioDeviceTransportTypeBuiltIn,
           Self.dataSource(device.id) == Self.headphonesDataSource {
            return "headphones"
        }
        return device.symbol
    }

    /// What the volume HUD shows.
    var currentSymbol: String {
        if devices.isEmpty { start() }
        return current.map(symbol(for:)) ?? "speaker.wave.2.fill"
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
        // Picked by hand, so nothing to announce; the listener confirms it.
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
            // The list holds inputs too, so require output channels.
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

    /// 'hdpn': the jack, on a built-in device that also drives the speakers.
    private static let headphonesDataSource: UInt32 = 0x6864_706E

    private static func dataSource(_ device: AudioObjectID) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSource,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr
        else { return nil }
        return value
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
