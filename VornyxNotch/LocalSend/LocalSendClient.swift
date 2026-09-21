//
//  LocalSendClient.swift
//  VornyxNotch
//
//  The sending side: register, prepare-upload, upload, cancel.
//

import Foundation
import Security

enum LocalSendClientError: LocalizedError {
    case declined
    case busy
    case pinRequired
    case tooManyAttempts
    case status(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .declined: return String(localized: "Declined")
        case .busy: return String(localized: "The device is busy with another transfer")
        case .pinRequired: return String(localized: "The device asks for a PIN")
        case .tooManyAttempts: return String(localized: "Too many attempts")
        case .status(let code, let message): return message.isEmpty ? "HTTP \(code)" : message
        case .invalidResponse: return String(localized: "Unexpected response")
        }
    }
}

/// Talks to peers the way LocalSend requires: always present our own
/// certificate, and only speak to a peer whose certificate hashes to the
/// fingerprint we expect. One session per peer, since a reused connection
/// skips the handshake.
actor LocalSendClient {
    private let identity: SecIdentity
    private var sessions: [String: URLSession] = [:]

    init(identity: SecIdentity) {
        self.identity = identity
    }

    // MARK: - Discovery

    /// Say hello to a device and learn what it is. Unpinned when probing a bare
    /// address, where the identity is the certificate it presented.
    func register(
        host: String, port: Int, https: Bool, expectedFingerprint: String?,
        info: LocalSendInfo, timeout: TimeInterval
    ) async throws -> LocalSendDevice {
        let hostPart = host.contains(":") ? "[\(host)]" : host
        guard let url = URL(string:
            "\(https ? "https" : "http")://\(hostPart):\(port)\(LocalSendProtocol.apiPrefix)/register")
        else { throw LocalSendClientError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(info)

        let delegate = TrustDelegate(identity: identity, expectedFingerprint: https ? expectedFingerprint : nil)
        let session: URLSession
        if let expectedFingerprint {
            session = self.session(for: expectedFingerprint)
        } else {
            // Its own session: an unpinned probe leaves no connection to reuse.
            session = Self.makeSession()
        }
        defer { if expectedFingerprint == nil { session.finishTasksAndInvalidate() } }

        let (data, response) = try await session.data(for: request, delegate: delegate)
        try Self.check(response, data, prepare: false)

        let theirs = try JSONDecoder().decode(LocalSendInfo.self, from: data)
        let fingerprint = (https ? delegate.observedFingerprint : nil) ?? theirs.fingerprint
        return LocalSendDevice(
            fingerprint: fingerprint, alias: theirs.alias, deviceModel: theirs.deviceModel,
            deviceType: theirs.deviceType, host: host, port: port, isHTTPS: https, lastSeen: Date())
    }

    // MARK: - Sending

    /// Ask the device to take these files. No timeout: it waits on a person.
    /// Nil when the device accepted nothing, which is not an error.
    func prepareUpload(
        to device: LocalSendDevice, info: LocalSendInfo, files: [LocalSendFile]
    ) async throws -> LocalSendPrepareUploadResponse? {
        var request = try makeRequest(device, path: "/prepare-upload")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(LocalSendPrepareUploadRequest(
            info: info,
            files: Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })))

        let (data, response) = try await session(for: device.fingerprint)
            .data(for: request, delegate: delegate(for: device))
        if (response as? HTTPURLResponse)?.statusCode == 204 { return nil }
        try Self.check(response, data, prepare: true)

        let decoded = try JSONDecoder().decode(LocalSendPrepareUploadResponse.self, from: data)
        return decoded.files.isEmpty ? nil : decoded
    }

    func upload(
        to device: LocalSendDevice, sessionId: String, fileId: String, token: String,
        from fileURL: URL, progress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        var request = try makeRequest(device, path: "/upload", query: [
            ("sessionId", sessionId), ("fileId", fileId), ("token", token),
        ])
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session(for: device.fingerprint)
            .upload(for: request, fromFile: fileURL, delegate: delegate(for: device, progress: progress))
        try Self.check(response, data, prepare: false)
    }

    /// Tell the device to stop. Best effort, but worth trying: the receiver
    /// has one session slot, and an abandoned session blocks every sender.
    func cancel(on device: LocalSendDevice, sessionId: String?) async {
        guard var request = try? makeRequest(
            device, path: "/cancel", query: sessionId.map { [("sessionId", $0)] } ?? [])
        else { return }
        request.timeoutInterval = 5
        _ = try? await session(for: device.fingerprint).data(for: request, delegate: delegate(for: device))
    }

    /// Drop the connection pool for a device that has gone, letting whatever
    /// is still running on it finish.
    func forget(_ fingerprint: String) {
        sessions.removeValue(forKey: fingerprint)?.finishTasksAndInvalidate()
    }

    // MARK: - Plumbing

    private func session(for fingerprint: String) -> URLSession {
        if let existing = sessions[fingerprint] { return existing }
        let session = Self.makeSession()
        sessions[fingerprint] = session
        return session
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        // An idle limit, not a total one: a prepare-upload waits on a person.
        configuration.timeoutIntervalForRequest = 3600
        configuration.timeoutIntervalForResource = 7 * 24 * 3600
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.urlCache = nil
        // A proxy would sit between us and the certificate being checked.
        configuration.connectionProxyDictionary = [:]
        return URLSession(configuration: configuration)
    }

    private func delegate(
        for device: LocalSendDevice, progress: (@Sendable (Int64) -> Void)? = nil
    ) -> TrustDelegate {
        TrustDelegate(
            identity: identity,
            expectedFingerprint: device.isHTTPS ? device.fingerprint : nil,
            progress: progress)
    }

    private func makeRequest(
        _ device: LocalSendDevice, path: String, query: [(String, String)] = []
    ) throws -> URLRequest {
        guard let base = device.baseURL,
              var components = URLComponents(string: base.absoluteString + LocalSendProtocol.apiPrefix + path)
        else { throw LocalSendClientError.invalidResponse }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        }
        guard let url = components.url else { throw LocalSendClientError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        return request
    }

    /// 403 means "declined" only for prepare-upload; on an upload it means a
    /// bad token or the wrong address.
    private static func check(_ response: URLResponse, _ data: Data, prepare: Bool) throws {
        guard let http = response as? HTTPURLResponse else { throw LocalSendClientError.invalidResponse }
        guard !(200..<300).contains(http.statusCode) else { return }

        let message = (try? JSONDecoder().decode(LocalSendErrorBody.self, from: data).message)
            ?? String(decoding: data, as: UTF8.self)
        switch http.statusCode {
        case 401 where prepare: throw LocalSendClientError.pinRequired
        case 403 where prepare: throw LocalSendClientError.declined
        case 409: throw LocalSendClientError.busy
        case 429: throw LocalSendClientError.tooManyAttempts
        default: throw LocalSendClientError.status(http.statusCode, message)
        }
    }
}

/// Presents our certificate, and holds the peer to the one it announced.
private final class TrustDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let identity: SecIdentity
    let expectedFingerprint: String?
    let progress: (@Sendable (Int64) -> Void)?

    /// What the peer's certificate hashed to, for when we had no expectation.
    private(set) var observedFingerprint: String?

    init(identity: SecIdentity, expectedFingerprint: String?, progress: (@Sendable (Int64) -> Void)? = nil) {
        self.identity = identity
        self.expectedFingerprint = expectedFingerprint?.uppercased()
        self.progress = progress
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        switch challenge.protectionSpace.authenticationMethod {
        case NSURLAuthenticationMethodServerTrust:
            // No chain, no hostname: the fingerprint is the check.
            guard let trust = challenge.protectionSpace.serverTrust,
                  let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
                  let leaf = chain.first
            else { return completionHandler(.cancelAuthenticationChallenge, nil) }

            let actual = LocalSendIdentity.fingerprint(ofDER: SecCertificateCopyData(leaf) as Data)
            observedFingerprint = actual
            if let expectedFingerprint, expectedFingerprint != actual {
                return completionHandler(.cancelAuthenticationChallenge, nil)
            }
            completionHandler(.useCredential, URLCredential(trust: trust))

        case NSURLAuthenticationMethodClientCertificate:
            completionHandler(.useCredential, URLCredential(
                identity: identity, certificates: nil, persistence: .forSession))

        default:
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64, totalBytesExpectedToSend: Int64
    ) {
        progress?(totalBytesSent)
    }
}
