//
//  LocalSendServer.swift
//  VornyxNotch
//
//  The receiving side: /info, /register, /prepare-upload, /upload, /cancel.
//

import Foundation
import Network
import Security

/// A transfer someone has offered us, waiting on a yes or no.
struct LocalSendIncomingRequest: Identifiable {
    let id: UUID
    let sender: LocalSendInfo
    let host: String
    let files: [LocalSendFile]

    var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }
}

/// The decisions the server cannot make by itself.
@MainActor
protocol LocalSendServerDelegate: AnyObject {
    func localSendOwnInfo() -> LocalSendInfo
    func localSendDidRegister(_ device: LocalSendDevice)
    /// LocalSend's "send text": needs no answer and no session.
    func localSendDidReceiveMessage(_ text: String, from sender: LocalSendInfo)
    /// The ids of the files to take; empty to take none; nil to decline.
    func localSendShouldAccept(_ request: LocalSendIncomingRequest) async -> Set<String>?
    /// The sender gave up before anyone answered.
    func localSendDidAbandon(_ requestID: UUID)
    func localSendSessionDidBegin(sessionID: String, request: LocalSendIncomingRequest, accepted: [LocalSendFile])
    func localSendDestinationDirectory() -> URL
    func localSendDidProgress(sessionID: String, fileID: String, received: Int64)
    func localSendDidReceive(_ url: URL, sessionID: String)
    func localSendSessionDidEnd(sessionID: String, cancelled: Bool)
}

/// The HTTPS server LocalSend peers talk to.
///
/// A client certificate is required, and identifies the sender. There is one
/// session slot for everyone, held from the offer until the transfer ends;
/// anyone else gets 409 meanwhile.
final class LocalSendServer: @unchecked Sendable {
    @MainActor weak var delegate: LocalSendServerDelegate?

    private let queue = DispatchQueue(label: "tech.vornyx.notch.localsend.server")
    private var listener: NWListener?
    private let slot = ReceiveSlot()

    /// Bounds the JSON bodies of everything except uploads.
    private static let jsonLimit = 32 * 1024 * 1024

    // MARK: - Lifecycle

    /// Listen on 53317, or the next free port after it: LocalSend itself may be
    /// running on this Mac. The port travels in every announcement.
    @MainActor
    func start(identity: SecIdentity) async throws -> UInt16 {
        stop()
        var lastError: Error = LocalSendHTTPError.closed
        for port in LocalSendProtocol.port..<(LocalSendProtocol.port + 10) {
            do {
                listener = try await open(identity: identity, port: port)
                return port
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    @MainActor
    func stop() {
        listener?.cancel()
        listener = nil
    }

    func cancelActiveSession() async {
        guard let sessionID = await slot.forceEnd() else { return }
        let delegate = await self.delegate
        await delegate?.localSendSessionDidEnd(sessionID: sessionID, cancelled: true)
    }

    private func open(identity: SecIdentity, port: UInt16) async throws -> NWListener {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        sec_protocol_options_set_local_identity(options, sec_identity_create(identity)!)
        // Ask for the peer's certificate and refuse to go on without one.
        sec_protocol_options_set_peer_authentication_required(options, true)
        // Any certificate is acceptable: there is no authority to check it
        // against, and the handshake proves the peer holds its key.
        sec_protocol_options_set_verify_block(options, { _, _, complete in complete(true) }, queue)
        sec_protocol_options_add_tls_application_protocol(options, "http/1.1")

        // No endpoint reuse: it would steal LocalSend's own connections.
        let listener = try NWListener(using: NWParameters(tls: tls), on: NWEndpoint.Port(rawValue: port)!)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }

        let once = ResumeOnce()
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    once.run { continuation.resume(returning: listener) }
                case .failed(let error):
                    once.run {
                        listener.cancel()
                        continuation.resume(throwing: error)
                    }
                case .waiting(let error):
                    // A taken port shows up here on some systems; anything else
                    // (no network yet) resolves itself.
                    once.run {
                        if case .posix(let code) = error, code == .EADDRINUSE {
                            listener.cancel()
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: listener)
                        }
                    }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                let http = LocalSendHTTPConnection(
                    connection: connection, peerFingerprint: Self.peerFingerprint(of: connection))
                connection.stateUpdateHandler = { state in
                    if case .failed = state {
                        Task { await self.connectionDropped(http) }
                    }
                }
                Task.detached { await self.serve(http) }
            case .failed:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private static func peerFingerprint(of connection: NWConnection) -> String? {
        guard let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata
        else { return nil }
        var result: String?
        sec_protocol_metadata_access_peer_certificate_chain(metadata.securityProtocolMetadata) { certificate in
            guard result == nil else { return }
            let reference = sec_certificate_copy_ref(certificate).takeRetainedValue()
            result = LocalSendIdentity.fingerprint(ofDER: SecCertificateCopyData(reference) as Data)
        }
        return result
    }

    // MARK: - Requests

    private func serve(_ http: LocalSendHTTPConnection) async {
        defer { http.connection.cancel() }
        while let request = try? await http.readRequest() {
            do {
                try await route(request, http)
            } catch {
                return
            }
        }
    }

    private func route(_ request: LocalSendRequest, _ http: LocalSendHTTPConnection) async throws {
        let prefix = LocalSendProtocol.apiPrefix
        switch (request.method, request.path) {
        // v1's info route is still asked by LocalSend 1.17 and older.
        case ("GET", "/api/localsend/v1/info"), ("GET", prefix + "/info"):
            _ = try await http.readBody(of: request, limit: 1024)
            try await http.respond(200, body: await responseInfo())
        case ("POST", prefix + "/register"):
            try await register(request, http)
        case ("POST", prefix + "/prepare-upload"):
            try await prepareUpload(request, http)
        case ("POST", prefix + "/upload"):
            try await upload(request, http)
        case ("POST", prefix + "/cancel"):
            try await cancel(request, http)
        default:
            _ = try await http.readBody(of: request, limit: Self.jsonLimit)
            try await http.respond(404)
        }
    }

    /// Our description as `/info` and `/register` answer with it: no port,
    /// protocol or announce flag, which the caller already knows.
    private func responseInfo() async -> LocalSendInfo {
        let delegate = await self.delegate
        var info = await delegate?.localSendOwnInfo()
            ?? LocalSendInfo(alias: "Vornyx Notch", version: LocalSendProtocol.version, fingerprint: "")
        info.port = nil
        info.protocol = nil
        info.announce = nil
        info.download = false
        return info
    }

    private func register(_ request: LocalSendRequest, _ http: LocalSendHTTPConnection) async throws {
        let body = try await http.readBody(of: request, limit: 64 * 1024)
        guard let info = try? JSONDecoder().decode(LocalSendInfo.self, from: body) else {
            return try await http.respondError(400, "Invalid JSON body")
        }

        // A claimed fingerprint that is not the certificate's is ignored.
        let claimed = info.fingerprint.uppercased()
        if let host = Self.usableHost(http.remoteHost), let port = info.port,
           http.peerFingerprint == nil || http.peerFingerprint == claimed {
            let device = LocalSendDevice(
                fingerprint: http.peerFingerprint ?? claimed, alias: info.alias,
                deviceModel: info.deviceModel, deviceType: info.deviceType, host: host, port: port,
                isHTTPS: (info.protocol ?? "https") == "https", lastSeen: Date())
            let delegate = await self.delegate
            await delegate?.localSendDidRegister(device)
        }

        try await http.respond(200, body: await responseInfo())
    }

    private func prepareUpload(_ request: LocalSendRequest, _ http: LocalSendHTTPConnection) async throws {
        let body = try await http.readBody(of: request, limit: Self.jsonLimit)
        guard var payload = try? JSONDecoder().decode(LocalSendPrepareUploadRequest.self, from: body) else {
            return try await http.respondError(400, "Invalid JSON body")
        }
        guard !payload.files.isEmpty else {
            return try await http.respondError(400, "No files provided")
        }

        // A message: one file, of a text type, with its content in `preview`.
        // Nothing is uploaded for it, so it takes no session slot and is
        // answered 204, LocalSend's "accepted nothing".
        if payload.files.count == 1, let only = payload.files.values.first,
           only.fileType == "text" || only.fileType.hasPrefix("text/"),
           let text = only.preview {
            var sender = payload.info
            if let peer = http.peerFingerprint { sender.fingerprint = peer }
            let delegate = await self.delegate
            await delegate?.localSendDidReceiveMessage(text, from: sender)
            return try await http.respond(204)
        }
        guard let host = Self.usableHost(http.remoteHost) else {
            return try await http.respondError(400, "Invalid JSON body")
        }

        let id = UUID()
        guard await slot.claim(id: id, host: host, connection: ObjectIdentifier(http)) else {
            return try await http.respondError(409, "Blocked by another session")
        }

        // Over TLS the sender is the certificate, whatever the body says.
        if let peer = http.peerFingerprint { payload.info.fingerprint = peer }
        let incoming = LocalSendIncomingRequest(
            id: id, sender: payload.info, host: host,
            files: payload.files.values.sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending })

        let delegate = await self.delegate
        let accepted = await delegate?.localSendShouldAccept(incoming) ?? nil

        if await slot.wasCancelled(id) {
            await slot.release(id)
            return try await http.respondError(403, "Cancelled by sender")
        }
        guard let accepted else {
            await slot.release(id)
            return try await http.respondError(403, "Rejected")
        }

        let files = incoming.files.filter { accepted.contains($0.id) }
        guard let session = await slot.activate(id: id, accepted: files) else {
            return try await http.respond(204)
        }

        await delegate?.localSendSessionDidBegin(sessionID: session.id, request: incoming, accepted: files)
        try await http.respond(200, body: LocalSendPrepareUploadResponse(
            sessionId: session.id, files: session.tokens))
    }

    private func upload(_ request: LocalSendRequest, _ http: LocalSendHTTPConnection) async throws {
        // Every refusal here closes the connection: the body has not been read.
        guard let sessionID = request.query["sessionId"], let fileID = request.query["fileId"],
              let token = request.query["token"]
        else {
            try await http.respondError(400, "Missing parameters")
            throw LocalSendHTTPError.closed
        }
        guard let host = Self.usableHost(http.remoteHost),
              let (file, flag) = await slot.beginUpload(sessionID: sessionID, fileID: fileID, token: token, host: host)
        else {
            try await http.respondError(403, "Invalid token or IP address")
            throw LocalSendHTTPError.closed
        }

        let delegate = await self.delegate
        let directory = await delegate?.localSendDestinationDirectory()
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let destination = await slot.reserve(in: directory, relativePath: Self.safeRelativePath(file.fileName))
        let partial = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).localsend")

        var written: Int64 = 0
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: partial.path, contents: nil)
            let handle = try FileHandle(forWritingTo: partial)
            defer { try? handle.close() }

            var lastReport = Date.distantPast
            try await http.readBody(of: request) { piece in
                if flag.isCancelled { throw CancellationError() }
                written += Int64(piece.count)
                // More than was promised is refused, not truncated.
                guard written <= file.size else { throw LocalSendHTTPError.tooLarge }
                try handle.write(contentsOf: piece)

                let now = Date()
                if now.timeIntervalSince(lastReport) > 0.1 {
                    lastReport = now
                    let received = written
                    Task { @MainActor in
                        delegate?.localSendDidProgress(sessionID: sessionID, fileID: fileID, received: received)
                    }
                }
            }
            guard written == file.size else { throw LocalSendHTTPError.malformed }

            try handle.close()
            try FileManager.default.moveItem(at: partial, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            await slot.unreserve(destination)
            if await slot.finishUpload(sessionID: sessionID, fileID: fileID, succeeded: false) {
                await delegate?.localSendSessionDidEnd(sessionID: sessionID, cancelled: flag.isCancelled)
            }
            try? await http.respondError(500, "Status code: 500 Internal Server Error")
            throw error
        }

        await slot.unreserve(destination)
        await delegate?.localSendDidProgress(sessionID: sessionID, fileID: fileID, received: written)
        await delegate?.localSendDidReceive(destination, sessionID: sessionID)
        if await slot.finishUpload(sessionID: sessionID, fileID: fileID, succeeded: true) {
            await delegate?.localSendSessionDidEnd(sessionID: sessionID, cancelled: false)
        }
        try await http.respond(200)
    }

    private func cancel(_ request: LocalSendRequest, _ http: LocalSendHTTPConnection) async throws {
        _ = try await http.readBody(of: request, limit: 1024)
        let delegate = await self.delegate

        if let host = Self.usableHost(http.remoteHost) {
            if let sessionID = request.query["sessionId"] {
                if await slot.cancelActive(sessionID: sessionID, host: host) {
                    await delegate?.localSendSessionDidEnd(sessionID: sessionID, cancelled: true)
                }
            } else if let id = await slot.cancelPending(host: host) {
                // No session id yet: a sender that stopped waiting for an answer.
                await delegate?.localSendDidAbandon(id)
            }
        }
        // Always 200, even when nothing matched.
        try await http.respond(200)
    }

    private func connectionDropped(_ http: LocalSendHTTPConnection) async {
        guard let id = await slot.cancelPending(connection: ObjectIdentifier(http)) else { return }
        let delegate = await self.delegate
        await delegate?.localSendDidAbandon(id)
    }

    // MARK: - Helpers

    /// IPv4 as-is, IPv4-mapped IPv6 unwrapped, scoped IPv6 dropped: a scoped
    /// address cannot be dialled back through a URL.
    private static func usableHost(_ host: String?) -> String? {
        guard var host else { return nil }
        if host.hasPrefix("::ffff:") { host.removeFirst("::ffff:".count) }
        return host.contains("%") ? nil : host
    }

    /// A sender's file name, made safe to write under Downloads. Folders arrive
    /// as relative paths and are kept, but never absolute and never with dots.
    static func safeRelativePath(_ name: String) -> String {
        let parts = name.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.allSatisfy { $0 == "." } }
        return parts.isEmpty ? "file" : parts.joined(separator: "/")
    }
}

// MARK: - Session slot

/// Lets exactly one of a listener's state callbacks resume its continuation.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        lock.lock()
        guard !done else {
            lock.unlock()
            return
        }
        done = true
        lock.unlock()
        body()
    }
}

/// Set from outside a stream, read inside it.
private final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

/// The one transfer the server may be part of at a time.
private actor ReceiveSlot {
    struct Session {
        let id: String
        let host: String
        let flag = CancelFlag()
        var files: [String: Entry]

        var tokens: [String: String] { files.mapValues(\.token) }
        var isDone: Bool { files.values.allSatisfy { $0.status == .finished || $0.status == .failed } }
    }

    struct Entry {
        let file: LocalSendFile
        let token: String
        var status: Status
    }

    enum Status { case pending, receiving, finished, failed }

    private enum Phase {
        case idle
        case pending(id: UUID, host: String, connection: ObjectIdentifier, cancelled: Bool)
        case active(Session)
    }

    private var phase: Phase = .idle
    private var reserved: Set<String> = []

    func claim(id: UUID, host: String, connection: ObjectIdentifier) -> Bool {
        guard case .idle = phase else { return false }
        phase = .pending(id: id, host: host, connection: connection, cancelled: false)
        return true
    }

    func cancelPending(host: String) -> UUID? {
        guard case .pending(let id, let pendingHost, let connection, false) = phase, pendingHost == host
        else { return nil }
        phase = .pending(id: id, host: pendingHost, connection: connection, cancelled: true)
        return id
    }

    func cancelPending(connection: ObjectIdentifier) -> UUID? {
        guard case .pending(let id, let host, let pendingConnection, false) = phase,
              pendingConnection == connection
        else { return nil }
        phase = .pending(id: id, host: host, connection: pendingConnection, cancelled: true)
        return id
    }

    func wasCancelled(_ id: UUID) -> Bool {
        if case .pending(let pendingID, _, _, let cancelled) = phase, pendingID == id { return cancelled }
        return false
    }

    func release(_ id: UUID) {
        if case .pending(let pendingID, _, _, _) = phase, pendingID == id { phase = .idle }
    }

    /// Turn a pending offer into a session with a token per accepted file.
    func activate(id: UUID, accepted: [LocalSendFile]) -> Session? {
        guard case .pending(let pendingID, let host, _, _) = phase, pendingID == id else { return nil }
        guard !accepted.isEmpty else {
            phase = .idle
            return nil
        }
        let session = Session(
            id: UUID().uuidString, host: host,
            files: Dictionary(uniqueKeysWithValues: accepted.map {
                ($0.id, Entry(file: $0, token: UUID().uuidString, status: .pending))
            }))
        phase = .active(session)
        return session
    }

    /// Check an upload's credentials and mark its file as arriving.
    func beginUpload(
        sessionID: String, fileID: String, token: String, host: String
    ) -> (LocalSendFile, CancelFlag)? {
        guard case .active(var session) = phase, session.id == sessionID, session.host == host,
              var entry = session.files[fileID], entry.token == token, entry.status == .pending
        else { return nil }
        entry.status = .receiving
        session.files[fileID] = entry
        phase = .active(session)
        return (entry.file, session.flag)
    }

    /// True when that was the session's last file.
    func finishUpload(sessionID: String, fileID: String, succeeded: Bool) -> Bool {
        guard case .active(var session) = phase, session.id == sessionID else { return false }
        session.files[fileID]?.status = succeeded ? .finished : .failed
        if session.isDone {
            phase = .idle
            return true
        }
        phase = .active(session)
        return false
    }

    func cancelActive(sessionID: String, host: String) -> Bool {
        guard case .active(let session) = phase, session.id == sessionID, session.host == host else { return false }
        session.flag.cancel()
        phase = .idle
        return true
    }

    func forceEnd() -> String? {
        guard case .active(let session) = phase else { return nil }
        session.flag.cancel()
        phase = .idle
        return session.id
    }

    /// A name nothing else is using, on disk or by a file arriving in parallel.
    func reserve(in directory: URL, relativePath: String) -> URL {
        let base = directory.appendingPathComponent(relativePath)
        let folder = base.deletingLastPathComponent()
        let stem = base.deletingPathExtension().lastPathComponent
        let ext = base.pathExtension

        var candidate = base
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) || reserved.contains(candidate.path) {
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(stem) (\(number))" : "\(stem) (\(number)).\(ext)")
            number += 1
        }
        reserved.insert(candidate.path)
        return candidate
    }

    func unreserve(_ url: URL) {
        reserved.remove(url.path)
    }
}
