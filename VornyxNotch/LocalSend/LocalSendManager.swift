//
//  LocalSendManager.swift
//  VornyxNotch
//
//  Everything the notch shows about LocalSend, and the buttons it presses.
//

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

/// Owns discovery, the server and the client, and turns them into state a view
/// can read: who is around, what we are sending, and what someone is offering.
@MainActor
final class LocalSendManager: ObservableObject {
    static let shared = LocalSendManager()

    enum Availability: Equatable {
        case off
        case starting
        case running(port: UInt16)
        case failed(String)
    }

    struct Outgoing: Identifiable, Equatable {
        enum Phase: Equatable {
            case waitingForAcceptance
            case sending
            case finished
            case declined
            case busy
            case cancelled
            case failed(String)
        }

        let id = UUID()
        let device: LocalSendDevice
        let fileCount: Int
        let totalBytes: Int64
        var sentBytes: Int64 = 0
        var phase: Phase = .waitingForAcceptance
        /// Text rather than files, which changes only what the rows say.
        var isMessage = false

        var isOver: Bool {
            switch phase {
            case .waitingForAcceptance, .sending: return false
            default: return true
            }
        }

        var fraction: Double { totalBytes > 0 ? min(1, Double(sentBytes) / Double(totalBytes)) : 0 }
    }

    struct Incoming: Equatable {
        enum Phase: Equatable { case receiving, finished, cancelled }

        let sessionID: String
        let senderName: String
        let fileCount: Int
        let totalBytes: Int64
        var receivedBytes: Int64 = 0
        var receivedFiles: [URL] = []
        var phase: Phase = .receiving

        var fraction: Double { totalBytes > 0 ? min(1, Double(receivedBytes) / Double(totalBytes)) : 0 }
    }

    /// A text sent from LocalSend's "send text" - a link from a phone, say.
    struct Message: Identifiable, Equatable {
        let id = UUID()
        let senderName: String
        let text: String

        /// The whole text, when it is a single web link, so it can be opened
        /// rather than only copied.
        var url: URL? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.contains(where: \.isWhitespace), let url = URL(string: trimmed),
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
            else { return nil }
            return url
        }
    }

    @Published private(set) var availability: Availability = .off
    @Published private(set) var devices: [LocalSendDevice] = []
    @Published private(set) var isScanning = false
    @Published private(set) var outgoing: Outgoing?
    /// An offer waiting on the user. Only one at a time: the server's single
    /// session slot turns everyone else away with 409 meanwhile.
    @Published private(set) var pendingRequest: LocalSendIncomingRequest?
    @Published private(set) var incoming: Incoming?
    @Published private(set) var message: Message?

    var isRunning: Bool {
        if case .running = availability { return true }
        return false
    }

    private let discovery = LocalSendDiscovery()
    private let server = LocalSendServer()
    private var client: LocalSendClient?
    private var port: UInt16 = LocalSendProtocol.port

    private var decision: CheckedContinuation<Set<String>?, Never>?
    private var sendTask: Task<Void, Never>?
    private var receivedPerFile: [String: Int64] = [:]
    private var observations: Set<AnyCancellable> = []
    private var lastRefresh: Date = .distantPast

    private init() {}

    // MARK: - Lifecycle

    /// Follow the setting from now on. Starts straight away if it is on.
    func activate() {
        guard observations.isEmpty else { return }

        Defaults.publisher(.localSendEnabled)
            .sink { [weak self] change in
                Task { @MainActor in
                    guard let self else { return }
                    change.newValue ? await self.start() : self.stop()
                    // The window keeps room for the strip only while LocalSend
                    // is on, and is sized once - so ask for it to be sized again.
                    if change.oldValue != change.newValue {
                        NotificationCenter.default.post(name: .notchHeightChanged, object: nil)
                    }
                }
            }
            .store(in: &observations)

        // A new name should reach devices that already know the old one.
        Defaults.publisher(.localSendAlias, options: [])
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isRunning else { return }
                    self.discovery.announce(self.ownInfo(announce: true))
                }
            }
            .store(in: &observations)
    }

    private func start() async {
        guard !isRunning, availability != .starting else { return }
        availability = .starting

        do {
            let identity = try LocalSendIdentity.shared.load()
            client = LocalSendClient(identity: identity)
            server.delegate = self
            port = try await server.start(identity: identity)

            discovery.onAnnouncement = { [weak self] info, host in
                self?.answerAnnouncement(info, from: host)
            }
            try discovery.start(ownFingerprint: LocalSendIdentity.shared.fingerprint)

            availability = .running(port: port)
            discovery.announce(ownInfo(announce: true))
        } catch {
            NSLog("LOCALSEND: failed to start - \(error)")
            teardown()
            availability = .failed(error.localizedDescription)
        }
    }

    private func stop() {
        teardown()
        availability = .off
    }

    private func teardown() {
        sendTask?.cancel()
        resolveDecision(nil)
        discovery.stop()
        server.stop()
        client = nil
        devices = []
        isScanning = false
    }

    // MARK: - Who we are

    /// The name others see: the setting, or "Vornyx Notch".
    ///
    /// Not the Mac's own name. A Mac with Vornyx Notch often runs LocalSend
    /// too, and both would then show up on the phone under the same computer
    /// name, with no way to tell which one a file is going to.
    var alias: String {
        let custom = Defaults[.localSendAlias].trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? "Vornyx Notch" : custom
    }

    var fingerprint: String { LocalSendIdentity.shared.fingerprint }

    private func ownInfo(announce: Bool) -> LocalSendInfo {
        LocalSendInfo(
            alias: alias,
            version: LocalSendProtocol.version,
            // What LocalSend's own macOS build reports.
            deviceModel: "macOS",
            deviceType: "desktop",
            fingerprint: fingerprint,
            port: Int(port),
            protocol: "https",
            download: false,
            announce: announce ? true : nil)
    }

    // MARK: - Finding devices

    /// Someone announced themselves. Answering is what gets them on our list:
    /// a device is only added once it has actually answered.
    private func answerAnnouncement(_ info: LocalSendInfo, from host: String) {
        guard let client, let theirPort = info.port else { return }
        let https = (info.protocol ?? "https") == "https"
        let me = ownInfo(announce: false)

        Task {
            guard let device = try? await client.register(
                host: host, port: theirPort, https: https,
                expectedFingerprint: info.fingerprint, info: me, timeout: 3)
            else { return }
            upsert(device)
        }
    }

    /// Look again: announce, re-check who we know, and if nobody at all turns
    /// up, try every address on the local /24.
    ///
    /// The same ladder LocalSend climbs. The subnet scan is last because it is
    /// a couple of hundred requests - but it is also the only thing that works
    /// on networks that drop multicast, which is a lot of office and hotel Wi-Fi.
    func refresh() {
        guard isRunning, let client, !isScanning else { return }
        isScanning = true
        lastRefresh = Date()
        discovery.announce(ownInfo(announce: true))

        let known = devices
        let me = ownInfo(announce: false)

        Task {
            await withTaskGroup(of: (String, LocalSendDevice?).self) { group in
                for device in known {
                    group.addTask {
                        let answer = try? await client.register(
                            host: device.host, port: device.port, https: device.isHTTPS,
                            expectedFingerprint: device.fingerprint, info: me, timeout: 2)
                        return (device.fingerprint, answer)
                    }
                }
                for await (fingerprint, answer) in group {
                    if let answer {
                        upsert(answer)
                    } else {
                        devices.removeAll { $0.fingerprint == fingerprint }
                        await client.forget(fingerprint)
                    }
                }
            }

            // The reference grace period: give announcements a moment to be
            // answered before resorting to the scan.
            try? await Task.sleep(for: .seconds(1.5))
            if devices.isEmpty {
                await scanSubnets(client: client, me: me)
            }
            isScanning = false
        }
    }

    /// `refresh`, unless one ran in the last half minute. The strip asks for
    /// this every time the shelf opens, and the subnet scan behind a refresh is
    /// too many requests to fire on every glance at the shelf.
    func refreshIfStale() {
        guard Date().timeIntervalSince(lastRefresh) > 30 else { return }
        refresh()
    }

    private func scanSubnets(client: LocalSendClient, me: LocalSendInfo) async {
        var hosts: [String] = []
        let interfaces = LocalSendDiscovery.interfaces()
        let ownAddresses = Set(interfaces.map { UInt32(bigEndian: $0.address.s_addr) })

        for interface in interfaces {
            // Always a /24, whatever the real mask: a /16 would be 65,000
            // requests, and the reference caps it the same way.
            let network = UInt32(bigEndian: interface.address.s_addr) & 0xFFFF_FF00
            for last in 1...254 {
                let candidate = network | UInt32(last)
                guard !ownAddresses.contains(candidate) else { continue }
                hosts.append("\(candidate >> 24).\((candidate >> 16) & 0xFF).\((candidate >> 8) & 0xFF).\(candidate & 0xFF)")
            }
        }
        let knownHosts = Set(devices.map(\.host))
        hosts.removeAll { knownHosts.contains($0) }

        let probe: @Sendable (String) async -> LocalSendDevice? = { host in
            try? await client.register(
                host: host, port: Int(LocalSendProtocol.port), https: true,
                expectedFingerprint: nil, info: me, timeout: 0.5)
        }

        // Fifty at a time, like the reference.
        await withTaskGroup(of: LocalSendDevice?.self) { group in
            var next = 0
            while next < min(50, hosts.count) {
                let host = hosts[next]
                group.addTask { await probe(host) }
                next += 1
            }
            for await answer in group {
                if let answer { upsert(answer) }
                if next < hosts.count {
                    let host = hosts[next]
                    group.addTask { await probe(host) }
                    next += 1
                }
            }
        }
    }

    private func upsert(_ device: LocalSendDevice) {
        guard device.fingerprint != fingerprint else { return }
        if let index = devices.firstIndex(where: { $0.fingerprint == device.fingerprint }) {
            devices[index] = device
        } else {
            devices.append(device)
            devices.sort { $0.alias.localizedStandardCompare($1.alias) == .orderedAscending }
        }
    }

    // MARK: - Sending

    /// Offer these files to a device. Folders are skipped: LocalSend sends a
    /// folder as its files with relative names, which is not done yet.
    func send(_ urls: [URL], to device: LocalSendDevice) {
        NSLog("LOCALSEND: drop on \(device.alias) with \(urls.count) file URL(s)")
        guard let client else {
            NSLog("LOCALSEND: drop ignored, LocalSend is not running")
            return
        }
        guard outgoing.map(\.isOver) ?? true else {
            NSLog("LOCALSEND: drop ignored, a send to \(outgoing?.device.alias ?? "?") is still in progress")
            return
        }

        let accessing = urls.filter { $0.startAccessingSecurityScopedResource() }
        var entries: [(file: LocalSendFile, url: URL)] = []
        for url in urls {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .contentModificationDateKey])
            guard values?.isDirectory != true, let size = values?.fileSize else { continue }
            entries.append((
                LocalSendFile(
                    id: UUID().uuidString,
                    fileName: url.lastPathComponent,
                    size: Int64(size),
                    fileType: LocalSendFile.mimeType(forFileName: url.lastPathComponent),
                    metadata: values?.contentModificationDate.map {
                        .init(modified: ISO8601DateFormatter().string(from: $0))
                    }),
                url))
        }
        guard !entries.isEmpty else {
            accessing.forEach { $0.stopAccessingSecurityScopedResource() }
            // Said out loud rather than dropped: this used to return silently,
            // and a drop that does nothing looks exactly like a broken feature.
            NSLog("LOCALSEND: none of \(urls.map(\.path)) could be read - folders, or no access")
            withAnimation(.smooth) {
                outgoing = Outgoing(device: device, fileCount: 0, totalBytes: 0)
            }
            let reason = urls.isEmpty
                ? String(localized: "Nothing that can be sent was dropped")
                : String(localized: "The file could not be read. Folders are not supported yet.")
            finishOutgoing(.failed(reason))
            return
        }

        withAnimation(.smooth) {
            outgoing = Outgoing(
                device: device, fileCount: entries.count,
                totalBytes: entries.reduce(0) { $0 + $1.file.size })
        }
        let me = ownInfo(announce: false)

        sendTask = Task {
            defer { accessing.forEach { $0.stopAccessingSecurityScopedResource() } }
            await runSend(entries, to: device, client: client, me: me)
        }
    }

    /// Send text the way LocalSend's own "send text" does: one `.txt` offer with
    /// the text itself in `preview`. A LocalSend receiver shows it and answers
    /// 204 without asking for the file; a receiver that does ask for it is sent
    /// the same text as the file's body.
    func sendText(_ text: String, to device: LocalSendDevice) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let client else {
            NSLog("LOCALSEND: text ignored, LocalSend is not running")
            return
        }
        guard outgoing.map(\.isOver) ?? true else {
            NSLog("LOCALSEND: text ignored, a send to \(outgoing?.device.alias ?? "?") is still in progress")
            return
        }

        let body = Data(text.utf8)
        let file = LocalSendFile(
            id: UUID().uuidString, fileName: "\(UUID().uuidString).txt",
            size: Int64(body.count), fileType: "text/plain", preview: text)
        withAnimation(.smooth) {
            outgoing = Outgoing(device: device, fileCount: 1, totalBytes: Int64(body.count), isMessage: true)
        }
        let me = ownInfo(announce: false)

        sendTask = Task {
            var remoteSession: String?
            do {
                if let response = try await client.prepareUpload(to: device, info: me, files: [file]),
                   let token = response.files[file.id] {
                    remoteSession = response.sessionId
                    outgoing?.phase = .sending
                    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(file.fileName)
                    try body.write(to: temporary)
                    defer { try? FileManager.default.removeItem(at: temporary) }
                    try await client.upload(
                        to: device, sessionId: response.sessionId, fileId: file.id, token: token,
                        from: temporary) { _ in }
                }
                finishOutgoing(.finished)
            } catch LocalSendClientError.declined {
                finishOutgoing(.declined)
            } catch LocalSendClientError.busy {
                finishOutgoing(.busy)
            } catch {
                await client.cancel(on: device, sessionId: remoteSession)
                let cancelled = Task.isCancelled || (error as? URLError)?.code == .cancelled
                finishOutgoing(cancelled ? .cancelled : .failed(error.localizedDescription))
            }
        }
    }

    func cancelSending() {
        sendTask?.cancel()
    }

    private func runSend(
        _ entries: [(file: LocalSendFile, url: URL)], to device: LocalSendDevice,
        client: LocalSendClient, me: LocalSendInfo
    ) async {
        var remoteSession: String?
        do {
            guard let response = try await client.prepareUpload(to: device, info: me, files: entries.map(\.file))
            else {
                // Accepted, but nothing selected - not a failure.
                return finishOutgoing(.finished)
            }
            remoteSession = response.sessionId
            outgoing?.phase = .sending

            var completed: Int64 = 0
            var lastPublished = Date.distantPast
            for entry in entries {
                guard let token = response.files[entry.file.id] else { continue }
                try Task.checkCancellation()

                let base = completed
                try await client.upload(
                    to: device, sessionId: response.sessionId, fileId: entry.file.id, token: token,
                    from: entry.url
                ) { [weak self] sent in
                    Task { @MainActor in
                        // Ten updates a second is plenty for a progress bar.
                        guard let self, Date().timeIntervalSince(lastPublished) > 0.1 else { return }
                        lastPublished = Date()
                        self.outgoing?.sentBytes = base + sent
                    }
                }
                completed += entry.file.size
                outgoing?.sentBytes = completed
            }
            finishOutgoing(.finished)
        } catch LocalSendClientError.declined {
            finishOutgoing(.declined)
        } catch LocalSendClientError.busy {
            finishOutgoing(.busy)
        } catch {
            // Stopped by us or failed: either way the receiver's single session
            // slot has to be let go, or it refuses everyone until it times out.
            await client.cancel(on: device, sessionId: remoteSession)
            let cancelled = Task.isCancelled || (error as? URLError)?.code == .cancelled
            finishOutgoing(cancelled ? .cancelled : .failed(error.localizedDescription))
        }
    }

    private func finishOutgoing(_ phase: Outgoing.Phase) {
        guard let id = outgoing?.id else { return }
        outgoing?.phase = phase
        if phase == .finished { playSound(.sent) }
        Task {
            try? await Task.sleep(for: .seconds(4))
            // Animated, like every other banner leaving: without a transaction
            // the banner's opacity transition never runs and it just blinks out.
            if outgoing?.id == id {
                withAnimation(.smooth) { outgoing = nil }
            }
        }
    }

    /// Apple's own sounds, played from where macOS keeps them rather than
    /// copied into the app: Messages' send for a send that went through, the
    /// Droplet tone for something arriving.
    private enum Sound: String {
        case sent = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/SentMessage.caf"
        case received = "/System/Library/PrivateFrameworks/ToneLibrary.framework/Versions/A/Resources/AlertTones/EncoreInfinitum/Droplet-EncoreInfinitum.caf"
    }

    private func playSound(_ sound: Sound) {
        guard Defaults[.localSendSounds] else { return }
        // These paths can move between releases: a missing file is silence, not a crash.
        NSSound(contentsOfFile: sound.rawValue, byReference: true)?.play()
    }

    // MARK: - Receiving

    func acceptPendingRequest() {
        resolveDecision(pendingRequest.map { Set($0.files.map(\.id)) })
    }

    func declinePendingRequest() {
        resolveDecision(nil)
    }

    func copyMessage() {
        guard let text = message?.text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func openMessageLink() {
        guard let url = message?.url else { return }
        NSWorkspace.shared.open(url)
    }

    func cancelReceiving() {
        Task { await server.cancelActiveSession() }
    }

    private func resolveDecision(_ accepted: Set<String>?) {
        decision?.resume(returning: accepted)
        decision = nil
        withAnimation(.smooth) { pendingRequest = nil }
    }
}

// MARK: - Server delegate

extension LocalSendManager: LocalSendServerDelegate {
    func localSendOwnInfo() -> LocalSendInfo {
        ownInfo(announce: false)
    }

    func localSendDidRegister(_ device: LocalSendDevice) {
        upsert(device)
    }

    /// A message needs no answer and no session: LocalSend itself takes one by
    /// "accepting nothing". It is shown with Copy and Open, and not put on the
    /// shelf: the setting says received *files*, and a link left there kept the
    /// notch opening on the shelf with "open shelf by default" on.
    func localSendDidReceiveMessage(_ text: String, from sender: LocalSendInfo) {
        let received = Message(senderName: sender.alias, text: text)
        withAnimation(.smooth) { message = received }
        playSound(.received)

        Task {
            try? await Task.sleep(for: .seconds(8))
            if message?.id == received.id {
                withAnimation(.smooth) { message = nil }
            }
        }
    }

    func localSendShouldAccept(_ request: LocalSendIncomingRequest) async -> Set<String>? {
        if Defaults[.localSendAutoAccept] {
            return Set(request.files.map(\.id))
        }
        return await withCheckedContinuation { continuation in
            // A previous question still open cannot happen with one session
            // slot, but never leave a continuation dangling if it does.
            decision?.resume(returning: nil)
            decision = continuation
            withAnimation(.smooth) { pendingRequest = request }
        }
    }

    func localSendDidAbandon(_ requestID: UUID) {
        guard pendingRequest?.id == requestID else { return }
        resolveDecision(nil)
    }

    func localSendSessionDidBegin(sessionID: String, request: LocalSendIncomingRequest, accepted: [LocalSendFile]) {
        receivedPerFile = [:]
        withAnimation(.smooth) {
            incoming = Incoming(
                sessionID: sessionID, senderName: request.sender.alias, fileCount: accepted.count,
                totalBytes: accepted.reduce(0) { $0 + $1.size })
        }
    }

    func localSendDestinationDirectory() -> URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    func localSendDidProgress(sessionID: String, fileID: String, received: Int64) {
        guard incoming?.sessionID == sessionID else { return }
        receivedPerFile[fileID] = received
        incoming?.receivedBytes = receivedPerFile.values.reduce(0, +)
    }

    func localSendDidReceive(_ url: URL, sessionID: String) {
        guard incoming?.sessionID == sessionID else { return }
        incoming?.receivedFiles.append(url)

        if Defaults[.localSendAddToShelf], let bookmark = try? Bookmark(url: url) {
            ShelfStateViewModel.shared.add([ShelfItem(kind: .file(bookmark: bookmark.data))])
        }
    }

    func localSendSessionDidEnd(sessionID: String, cancelled: Bool) {
        guard incoming?.sessionID == sessionID else { return }
        incoming?.phase = cancelled ? .cancelled : .finished
        if !cancelled, incoming?.receivedFiles.isEmpty == false { playSound(.received) }
        Task {
            try? await Task.sleep(for: .seconds(4))
            if incoming?.sessionID == sessionID {
                withAnimation(.smooth) { incoming = nil }
            }
        }
    }
}
