//
//  BluetoothDeviceManager.swift
//  VornyxNotch
//
//  The pair that just connected, as the AirPods banner shows it.
//

import Foundation

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

/// The AirPods banner's data. Other Bluetooth devices are not announced:
/// every Mac, phone and watch nearby joins and leaves over Bluetooth all day,
/// and a banner for each was noise.
@MainActor
final class BluetoothDeviceManager: ObservableObject {
    static let shared = BluetoothDeviceManager()

    @Published private(set) var latest: ConnectedBluetoothDevice?

    private init() {}

    func announcePair(_ pair: AirPodsBattery) {
        latest = Self.device(for: pair)
        VornyxViewCoordinator.shared.announceBluetooth()
    }

    static func device(for pair: AirPodsBattery) -> ConnectedBluetoothDevice {
        ConnectedBluetoothDevice(
            name: pair.name, symbol: pair.model.symbol, battery: pair.headline,
            left: pair.left, right: pair.right, caseLevel: pair.caseLevel, model: pair.model)
    }
}
