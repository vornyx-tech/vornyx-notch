//
//  BluetoothDeviceManager.swift
//  VornyxNotch
//
//  Keyboards, mice, trackpads, controllers and other headphones connecting.
//
//  After DynamicNotch's Bluetooth activity by Evgeniy Petrukovich (GPL-3.0),
//  https://github.com/jackson-storm/dynamicnotch
//

import AppKit
import Defaults
import Foundation
import IOBluetooth
import IOKit

/// A Bluetooth device that just connected, as the banner shows it.
struct ConnectedBluetoothDevice: Equatable {
    let name: String
    let symbol: String
    /// 0-100, when the device reports it: the lower ear, for a pair.
    let battery: Int?
    /// A pair's own levels, ear by ear and the case, when it reports them.
    var left: Int? = nil
    var right: Int? = nil
    var caseLevel: Int? = nil
    /// Which pair, for drawing each ear and the case.
    var model: AirPodsModel? = nil

    var hasEars: Bool { left != nil || right != nil }
}

/// Announces every Bluetooth device that connects. AirPods and Beats come in
/// through `announcePair`, since `AirPodsManager` is the one that waits for
/// their levels; everything else is read here.
@MainActor
final class BluetoothDeviceManager: ObservableObject {
    static let shared = BluetoothDeviceManager()

    @Published private(set) var latest: ConnectedBluetoothDevice?

    private let observer = DeviceObserver()
    private var connectNotification: IOBluetoothUserNotification?
    /// Registering also reports the devices already connected.
    private var quietUntil = Date.distantPast
    private var settleTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    private init() {}

    func start() {
        guard connectNotification == nil else { return }
        quietUntil = Date().addingTimeInterval(3)
        // Waking reconnects every device the Mac had before it slept; none of
        // that is news.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                BluetoothDeviceManager.shared.quietUntil = Date().addingTimeInterval(10)
            }
        }
        observer.onConnect = { device in
            Task { @MainActor in BluetoothDeviceManager.shared.connected(device) }
        }
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: observer,
            selector: #selector(DeviceObserver.connected(_:device:)))
    }

    /// Apple and Beats audio, by name, for the moment before a pair reports
    /// its class and levels - which is when it first connects.
    private static func soundsLikePair(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered.contains("airpods") || lowered.contains("beats")
    }

    private func connected(_ device: IOBluetoothDevice) {
        guard Date() >= quietUntil, Defaults[.bluetoothLiveActivity],
              !AirPodsManager.isPair(device),
              !Self.soundsLikePair(device.name ?? "") else { return }
        // No name is no one the user would recognise - a device macOS keeps
        // to itself, or one still identifying - so no banner for it.
        guard let name = device.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return }
        // Phones and computers join over Bluetooth for the hotspot, Handoff
        // and the like, silently and often; that is not something connected.
        guard ![0x01, 0x02].contains(device.deviceClassMajor) else { return }
        let address = device.addressString
        let symbol = Self.symbol(for: device)

        // The level shows up a moment after the connection, if at all - and
        // so does a pair's class. AirPods caught before it did went out here
        // with an antenna and no levels, ahead of their own banner.
        settleTask?.cancel()
        settleTask = Task { @MainActor [weak self] in
            var battery: Int?
            for delay in [300, 1200] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled else { return }
                battery = Self.battery(address: address, name: name, device: device)
                if battery != nil { break }
            }
            guard let self, !Task.isCancelled,
                  !AirPodsManager.isPair(device),
                  AirPodsManager.shared.device?.name != name
            else { return }
            self.latest = ConnectedBluetoothDevice(
                name: name, symbol: symbol == "dot.radiowaves.left.and.right" ? Self.symbol(for: device) : symbol,
                battery: battery)
            VornyxViewCoordinator.shared.announceBluetooth()
        }
    }

    /// A pair `AirPodsManager` has found, with its levels, in the same banner
    /// as any other device.
    func announcePair(_ pair: AirPodsBattery) {
        latest = Self.device(for: pair)
        VornyxViewCoordinator.shared.announceBluetooth()
    }

    static func device(for pair: AirPodsBattery) -> ConnectedBluetoothDevice {
        ConnectedBluetoothDevice(
            name: pair.name, symbol: pair.model.symbol, battery: pair.headline,
            left: pair.left, right: pair.right, caseLevel: pair.caseLevel, model: pair.model)
    }

    // MARK: - Reading

    /// By the device's class: major 0x05 is peripherals, 0x04 audio.
    private static func symbol(for device: IOBluetoothDevice) -> String {
        let minor = device.deviceClassMinor
        switch device.deviceClassMajor {
        case 0x05:
            if minor & 0x10 != 0 && minor & 0x20 == 0 { return "keyboard" }
            if minor & 0x20 != 0 && minor & 0x10 == 0 {
                return (device.name ?? "").localizedCaseInsensitiveContains("trackpad")
                    ? "rectangle.and.hand.point.up.left" : "computermouse"
            }
            if minor & 0x0F == 0x01 || minor & 0x0F == 0x02 { return "gamecontroller" }
            return "keyboard"
        // Audio: minor 0x05 is a loudspeaker; the rest are worn.
        case 0x04: return minor == 0x05 || minor == 0x07 ? "hifispeaker.fill" : "headphones"
        case 0x02: return "iphone"
        case 0x01: return "laptopcomputer"
        default: return "dot.radiowaves.left.and.right"
        }
    }

    /// Audio devices report through IOBluetooth; Apple's keyboards, mice and
    /// trackpads through the IO registry's HID services instead.
    private static func battery(address: String?, name: String, device: IOBluetoothDevice) -> Int? {
        for getter in ["batteryPercentSingle", "batteryPercentCombined"] {
            let selector = NSSelectorFromString(getter)
            guard device.responds(to: selector), let implementation = device.method(for: selector) else { continue }
            typealias Getter = @convention(c) (AnyObject, Selector) -> UInt8
            let value = Int(unsafeBitCast(implementation, to: Getter.self)(device, selector))
            if (1...100).contains(value) { return value }
        }
        return registryBattery(address: address, name: name)
    }

    private static func registryBattery(address: String?, name: String) -> Int? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        let wanted = address?.lowercased().replacingOccurrences(of: ":", with: "-")
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            func property(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue()
            }
            let serviceAddress = (property("DeviceAddress") as? String)?.lowercased()
                .replacingOccurrences(of: ":", with: "-")
            let product = property("Product") as? String
            guard (wanted != nil && serviceAddress == wanted) || product == name,
                  let percent = property("BatteryPercent") as? Int, (1...100).contains(percent)
            else { continue }
            return percent
        }
        return nil
    }
}

/// Target for IOBluetooth's selector-based connect notification.
private final class DeviceObserver: NSObject {
    var onConnect: ((IOBluetoothDevice) -> Void)?

    @objc func connected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        onConnect?(device)
    }
}
