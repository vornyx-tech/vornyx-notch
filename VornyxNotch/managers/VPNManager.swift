//
//  VPNManager.swift
//  VornyxNotch
//
//  Whether a VPN is connected, and which.
//

import AppKit
import Defaults
import Foundation
import Network

/// Watches for a VPN connecting or dropping.
///
/// The network path changes whenever a tunnel comes up or goes down, and
/// `NWPathMonitor` hears that inside the sandbox; each change asks the helper,
/// which reads `scutil`, for the details. A slow backstop covers a change the
/// path does not show.
@MainActor
final class VPNManager: ObservableObject {
    static let shared = VPNManager()

    @Published private(set) var connected: ConnectedVPN?
    /// The last one seen, so "Disconnected" can say which.
    @Published private(set) var last: ConnectedVPN?

    private let monitor = NWPathMonitor()
    private var backstop: Timer?
    private var query: Task<Void, Never>?
    /// No banner for the state found at launch.
    private var known = false

    private init() {}

    func start() {
        guard backstop == nil else { return }
        monitor.pathUpdateHandler = { _ in
            Task { @MainActor in VPNManager.shared.refresh(after: .milliseconds(600)) }
        }
        monitor.start(queue: .global(qos: .utility))
        backstop = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in VPNManager.shared.refresh() }
        }
        refresh()
    }

    /// The path changes a moment before `scutil` has the new state, hence the
    /// wait.
    private func refresh(after delay: Duration = .zero) {
        query?.cancel()
        query = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            let vpn = await XPCHelperClient.shared.connectedVPN()
            guard let self, !Task.isCancelled else { return }
            self.apply(vpn)
        }
    }

    private func apply(_ vpn: ConnectedVPN?) {
        let changed = vpn?.id != connected?.id
        connected = vpn
        if let vpn { last = vpn }
        if known, changed, Defaults[.vpnLiveActivity] {
            VornyxViewCoordinator.shared.announceVPN()
        }
        known = true
    }

    /// The VPN app's icon, when there is an app.
    static func icon(for vpn: ConnectedVPN?) -> NSImage? {
        guard let bundleID = vpn?.bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
