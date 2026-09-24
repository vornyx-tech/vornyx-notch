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
    /// 0-100, when the device reports it.
    let battery: Int?
}

/// Announces every Bluetooth device that connects, except the pairs
/// `AirPodsManager` already announces with their own, richer banner.
@MainActor
final class BluetoothDeviceManager: ObservableObject {
    static let shared = BluetoothDeviceManager()

    @Published private(set) var latest: ConnectedBluetoothDevice?

    private let observer = DeviceObserver()
    private var connectNotification: IOBluetoothUserNotification?
    /// Registering also reports the devices already connected.
    private var quietUntil = Date.distantPast
    private var settleTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard connectNotification == nil else { return }
        quietUntil = Date().addingTimeInterval(3)
        observer.onConnect = { device in
            Task { @MainActor in BluetoothDeviceManager.shared.connected(device) }
        }
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: observer,
            selector: #selector(DeviceObserver.connected(_:device:)))
    }

    private func connected(_ device: IOBluetoothDevice) {
        guard Date() >= quietUntil, Defaults[.bluetoothLiveActivity],
              !AirPodsManager.isPair(device) else { return }
        let address = device.addressString
        let name = device.name ?? "Bluetooth device"
        let symbol = Self.symbol(for: device)

        // The level shows up a moment after the connection, if at all.
        settleTask?.cancel()
        settleTask = Task { @MainActor [weak self] in
            var battery: Int?
            for delay in [300, 1200] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled else { return }
                battery = Self.battery(address: address, name: name, device: device)
                if battery != nil { break }
            }
            guard let self, !Task.isCancelled else { return }
            self.latest = ConnectedBluetoothDevice(name: name, symbol: symbol, battery: battery)
            VornyxViewCoordinator.shared.announceBluetooth()
        }
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
        case 0x04: return "headphones"
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
