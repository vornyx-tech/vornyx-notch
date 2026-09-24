import Foundation
import Cocoa
import AsyncXPCConnection

final class XPCHelperClient: NSObject {
    nonisolated static let shared = XPCHelperClient()
    
    private let serviceName = "tech.vornyx.notch.VornyxNotchXPCHelper"
    
    private var remoteService: RemoteXPCService<VornyxNotchXPCHelperProtocol>?
    private var connection: NSXPCConnection?
    private var lastKnownAuthorization: Bool?
    private var monitoringTask: Task<Void, Never>?
    
    deinit {
        connection?.invalidate()
        stopMonitoringAccessibilityAuthorization()
    }
    
    // MARK: - Connection Management (Main Actor Isolated)
    
    @MainActor
    private func ensureRemoteService() -> RemoteXPCService<VornyxNotchXPCHelperProtocol> {
        if let existing = remoteService {
            return existing
        }
        
        let conn = NSXPCConnection(serviceName: serviceName)
        
        conn.interruptionHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
                self?.remoteService = nil
            }
        }
        
        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
                self?.remoteService = nil
            }
        }
        
        conn.resume()
        
        let service = RemoteXPCService<VornyxNotchXPCHelperProtocol>(
            connection: conn,
            remoteInterface: VornyxNotchXPCHelperProtocol.self
        )
        
        connection = conn
        remoteService = service
        return service
    }
    
    @MainActor
    private func getRemoteService() -> RemoteXPCService<VornyxNotchXPCHelperProtocol>? {
        remoteService
    }
    
    @MainActor
    private func notifyAuthorizationChange(_ granted: Bool) {
        guard lastKnownAuthorization != granted else { return }
        lastKnownAuthorization = granted
        NotificationCenter.default.post(
            name: .accessibilityAuthorizationChanged,
            object: nil,
            userInfo: ["granted": granted]
        )
    }

    // MARK: - Monitoring
    nonisolated func startMonitoringAccessibilityAuthorization(every interval: TimeInterval = 3.0) {
        // Ensure only one monitor exists
        stopMonitoringAccessibilityAuthorization()
        monitoringTask = Task.detached { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                // Call the helper method periodically which will notify on change
                _ = await self.isAccessibilityAuthorized()
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch { break }
            }
        }
    }

    nonisolated func stopMonitoringAccessibilityAuthorization() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    // Expose whether the client is actively monitoring (useful for tests/debug)
    var isMonitoring: Bool {
        return monitoringTask != nil
    }
    
    // MARK: - Accessibility
    
    nonisolated func requestAccessibilityAuthorization() {
        Task {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            try? await service.withService { service in
                service.requestAccessibilityAuthorization()
            }
        }
    }
    
    nonisolated func isAccessibilityAuthorized() async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: Bool = try await service.withContinuation { service, continuation in
                service.isAccessibilityAuthorized { authorized in
                    continuation.resume(returning: authorized)
                }
            }
            await MainActor.run {
                notifyAuthorizationChange(result)
            }
            return result
        } catch {
            return false
        }
    }
    
    nonisolated func ensureAccessibilityAuthorization(promptIfNeeded: Bool) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: Bool = try await service.withContinuation { service, continuation in
                service.ensureAccessibilityAuthorization(promptIfNeeded) { authorized in
                    continuation.resume(returning: authorized)
                }
            }
            await MainActor.run {
                notifyAuthorizationChange(result)
            }
            return result
        } catch {
            return false
        }
    }
    
    // MARK: - Keyboard Brightness
    
    nonisolated func isKeyboardBrightnessAvailable() async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.isKeyboardBrightnessAvailable { available in
                    continuation.resume(returning: available)
                }
            }
        } catch {
            return false
        }
    }
    
    nonisolated func currentKeyboardBrightness() async -> Float? {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: NSNumber? = try await service.withContinuation { service, continuation in
                service.currentKeyboardBrightness { value in
                    continuation.resume(returning: value)
                }
            }
            return result?.floatValue
        } catch {
            return nil
        }
    }
    
    nonisolated func setKeyboardBrightness(_ value: Float) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.setKeyboardBrightness(value) { success in
                    continuation.resume(returning: success)
                }
            }
        } catch {
            return false
        }
    }
    
    // MARK: - Screen Brightness
    
    nonisolated func isScreenBrightnessAvailable() async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.isScreenBrightnessAvailable { available in
                    continuation.resume(returning: available)
                }
            }
        } catch {
            return false
        }
    }
    
    nonisolated func currentScreenBrightness() async -> Float? {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: NSNumber? = try await service.withContinuation { service, continuation in
                service.currentScreenBrightness { value in
                    continuation.resume(returning: value)
                }
            }
            return result?.floatValue
        } catch {
            return nil
        }
    }
    
    nonisolated func setScreenBrightness(_ value: Float) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.setScreenBrightness(value) { success in
                    continuation.resume(returning: success)
                }
            }
        } catch {
            return false
        }
    }

    // MARK: - Focus

    /// What the helper read off Control Center's menu bar. Nil when the
    /// helper could not be reached at all.
    nonisolated func focusStatus() async -> FocusStatus? {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: NSNumber? = try await service.withContinuation { service, continuation in
                service.isFocusMenuExtraShowing { value in
                    continuation.resume(returning: value)
                }
            }
            return result.flatMap { FocusStatus(rawValue: $0.intValue) }
        } catch {
            return nil
        }
    }
}

extension XPCHelperClient {
    /// The Focus file's answer. Nil when the helper could not be reached.
    nonisolated func focusAssertionState() async -> FocusAssertion? {
        do {
            let service = await MainActor.run { ensureRemoteService() }
            let result: NSString? = try await service.withContinuation { service, continuation in
                service.focusAssertionState { value in
                    continuation.resume(returning: value)
                }
            }
            switch result as String? {
            case nil, "unreadable": return .unreadable
            case "off": return .off
            case let mode?: return .on(mode: mode)
            }
        } catch {
            return nil
        }
    }
}

extension XPCHelperClient {
    /// The connected VPN, or nil when there is none or the helper could not
    /// be reached.
    nonisolated func connectedVPN() async -> ConnectedVPN? {
        do {
            let service = await MainActor.run { ensureRemoteService() }
            let result: NSDictionary? = try await service.withContinuation { service, continuation in
                service.connectedVPN { value in
                    continuation.resume(returning: value)
                }
            }
            guard let info = result as? [String: Any], let id = info["id"] as? String else { return nil }
            return ConnectedVPN(
                id: id,
                name: info["name"] as? String ?? "VPN",
                bundleID: info["bundleID"] as? String,
                connectedAt: (info["connectedAt"] as? Double).map(Date.init(timeIntervalSince1970:)))
        } catch {
            return nil
        }
    }
}

struct ConnectedVPN: Equatable {
    let id: String
    let name: String
    let bundleID: String?
    let connectedAt: Date?
}

enum FocusAssertion: Equatable {
    /// No Full Disk Access.
    case unreadable
    case off
    case on(mode: String)
}

/// The helper's answer about Focus; the raw values are its wire format.
enum FocusStatus: Int {
    case off = 0
    case on = 1
    /// This build has no Accessibility grant, which ad-hoc builds lose on
    /// every rebuild.
    case noAccessibility = 2
    /// Control Center's menu bar could not be read.
    case noMenuBar = 3
}

extension Notification.Name {
    static let accessibilityAuthorizationChanged = Notification.Name("accessibilityAuthorizationChanged")
}


