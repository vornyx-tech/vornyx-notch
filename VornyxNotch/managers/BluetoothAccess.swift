//
//  BluetoothAccess.swift
//  VornyxNotch
//
//  Runs Bluetooth work only once the app may use Bluetooth.
//

import CoreBluetooth
import Foundation

/// IOBluetooth's connect notifications block the calling thread until the
/// Bluetooth permission is answered - on the main thread, at launch, that
/// froze the whole app behind the prompt, and every new build asks again.
///
/// So the question goes through CoreBluetooth first, which asks without
/// blocking, and the work waits for a yes.
@MainActor
final class BluetoothAccess: NSObject, CBCentralManagerDelegate {
    static let shared = BluetoothAccess()

    private var central: CBCentralManager?
    private var waiting: [() -> Void] = []

    /// Runs `work` now if Bluetooth is allowed, after the answer if it has
    /// not been asked yet, and never if it was refused.
    func whenAllowed(_ work: @escaping () -> Void) {
        switch CBManager.authorization {
        case .allowedAlways:
            work()
        case .notDetermined:
            waiting.append(work)
            // Creating a manager is what asks; its delegate hears the answer.
            if central == nil {
                central = CBCentralManager(delegate: self, queue: .main, options: [
                    CBCentralManagerOptionShowPowerAlertKey: false
                ])
            }
        default:
            break
        }
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            let access = BluetoothAccess.shared
            guard CBManager.authorization != .notDetermined else { return }
            let work = access.waiting
            access.waiting = []
            access.central = nil
            if CBManager.authorization == .allowedAlways { work.forEach { $0() } }
        }
    }
}
