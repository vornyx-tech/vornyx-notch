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
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

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

    /// A text sent from LocalSend's "send text", a link from a phone say.
    struct Message: Identifiable, Equatable {
        let id = UUID()
        let senderName: String
        let text: String

        /// The whole text, when it is a single web link.
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
    /// An offer waiting on the user. Only one at a time, since the server has
    /// one session slot.
    @Published private(set) var pendingRequest: LocalSendIncomingRequest?
    @Published private(set) var incoming: Incoming?
    @Published private(set) var message: Message?
    /// Between tearing down and coming back up in `restart`.
    @Published private(set) var isRestarting = false

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
    /// Shelf items the session in progress has put there, to point out at the end.
    private var shelvedIDs: [UUID] = []
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
                    // The window only keeps room for the strip while LocalSend is on.
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

    /// Tear everything down and start again, then look for devices. For when
    /// the sockets have gone stale, after sleep or a move to another network.
    /// The pause gives the old listener time to let go of the port.
    func restart() {
        // Tearing down mid-transfer would cancel it.
        guard Defaults[.localSendEnabled], !isRestarting, availability != .starting, !isTransferring
        else { return }
        isRestarting = true
        Task {
            defer { isRestarting = false }
            stop()
            try? await Task.sleep(for: .milliseconds(600))
            // Switched off meanwhile: the setting's observer has the last word.
            guard Defaults[.localSendEnabled] else { return }
            await start()
            lastRefresh = .distantPast
            refresh()
        }
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

    /// The name others see: the setting, or "Vornyx Notch". Not the Mac's own
    /// name, which LocalSend on the same Mac would also be using.
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

    /// Someone announced themselves. A device is only added once it answers.
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
    /// up, try every address on the local /24. The scan is a couple of hundred
    /// requests, but it is the only thing that works without multicast.
    func refresh() {
        guard isRunning, let client, !isScanning else { return }
        isScanning = true
        lastRefresh = Date()
        discovery.announce(ownInfo(announce: true))

        // The device a transfer is running with is left alone: it may be too
        // busy to answer a hello, and would drop off the list mid-transfer.
        let busy = transferPeerFingerprint
        let known = devices.filter { $0.fingerprint != busy }
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

            // Give announcements a moment to be answered before scanning.
            try? await Task.sleep(for: .seconds(1.5))
            if devices.isEmpty {
                await scanSubnets(client: client, me: me)
            }
            isScanning = false
        }
    }

    /// `refresh`, unless one ran in the last half minute, and never while a
    /// transfer runs. The strip asks for this every time the shelf opens.
    func refreshIfStale() {
        guard Date().timeIntervalSince(lastRefresh) > 30, !isTransferring else { return }
        refresh()
    }

    /// Files moving in either direction right now.
    var isTransferring: Bool {
        if let outgoing, !outgoing.isOver { return true }
        return incoming?.phase == .receiving
    }

    /// The device on the other end of a send in progress.
    private var transferPeerFingerprint: String? {
        guard let outgoing, !outgoing.isOver else { return nil }
        return outgoing.device.fingerprint
    }

    private func scanSubnets(client: LocalSendClient, me: LocalSendInfo) async {
        var hosts: [String] = []
        let interfaces = LocalSendDiscovery.interfaces()
        let ownAddresses = Set(interfaces.map { UInt32(bigEndian: $0.address.s_addr) })

        for interface in interfaces {
            // Always a /24, whatever the real mask.
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

    /// Offer these files to a device. Folders are skipped.
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
            // Said out loud rather than dropped silently.
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

    /// Send text the way LocalSend's "send text" does: one `.txt` offer with the
    /// text itself in `preview`. A receiver that asks for the file gets the same
    /// text as its body.
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
                // Accepted, but nothing selected.
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
            // Let go of the receiver's session slot, or it refuses everyone
            // until it times out.
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
            // Animated, or the banner's opacity transition never runs.
            if outgoing?.id == id {
                withAnimation(.smooth) { outgoing = nil }
            }
        }
    }

    /// Apple's own sounds, played from where macOS keeps them.
    private enum Sound: String {
        case request = "/System/Library/PrivateFrameworks/ToneLibrary.framework/Versions/A/Resources/AlertTones/EncoreInfinitum/Handoff-EncoreInfinitum.caf"
        case sent = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/SentMessage.caf"
        case received = "/System/Library/PrivateFrameworks/ToneLibrary.framework/Versions/A/Resources/AlertTones/EncoreInfinitum/Droplet-EncoreInfinitum.caf"
    }

    private func playSound(_ sound: Sound) {
        guard Defaults[.localSendSounds] else { return }
        // These paths can move between releases; a missing file is silence.
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

    /// A message needs no answer and no session, and is not put on the shelf:
    /// the setting is about received files.
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
            // One session slot means there should be no question open already.
            decision?.resume(returning: nil)
            decision = continuation
            withAnimation(.smooth) { pendingRequest = request }
            // The one banner that waits on you, and times out if you miss it.
            playSound(.request)
        }
    }

    func localSendDidAbandon(_ requestID: UUID) {
        guard pendingRequest?.id == requestID else { return }
        resolveDecision(nil)
    }

    func localSendSessionDidBegin(sessionID: String, request: LocalSendIncomingRequest, accepted: [LocalSendFile]) {
        receivedPerFile = [:]
        shelvedIDs = []
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
            shelvedIDs += ShelfStateViewModel.shared.addReturningIDs([ShelfItem(kind: .file(bookmark: bookmark.data))])
        }
    }

    /// Open the shelf and flash what just landed on it.
    private func revealOnShelf() {
        let ids = shelvedIDs
        shelvedIDs = []
        guard !ids.isEmpty else { return }
        ShelfStateViewModel.shared.highlight(ids)
        NotificationCenter.default.post(name: .localSendRevealShelf, object: nil)
    }

    /// Put the images that arrived on the clipboard.
    ///
    /// Each one as its file and as PNG, in one pasteboard item, so apps that
    /// only know pixels get something. The PNG is made off the main thread.
    private func copyImages(_ urls: [URL]) {
        let images = urls.filter { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true }
        guard !images.isEmpty else { return }

        Task.detached(priority: .userInitiated) {
            let pngs = images.map { Self.pngData(for: $0) }
            await MainActor.run {
                let items = zip(images, pngs).map { url, png in
                    let item = NSPasteboardItem()
                    item.setString(url.absoluteString, forType: .fileURL)
                    if let png { item.setData(png, forType: .png) }
                    return item
                }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.writeObjects(items)
            }
        }
    }

    nonisolated private static func pngData(for url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              // Applies the EXIF orientation, which PNG does not carry.
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 8192,
              ] as CFDictionary)
        else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    func localSendSessionDidEnd(sessionID: String, cancelled: Bool) {
        guard incoming?.sessionID == sessionID else { return }
        incoming?.phase = cancelled ? .cancelled : .finished
        let received = incoming?.receivedFiles ?? []
        if !cancelled, !received.isEmpty {
            playSound(.received)
            revealOnShelf()
            if Defaults[.localSendCopyImages] { copyImages(received) }
        }
        Task {
            try? await Task.sleep(for: .seconds(4))
            if incoming?.sessionID == sessionID {
                withAnimation(.smooth) { incoming = nil }
            }
        }
    }
}
