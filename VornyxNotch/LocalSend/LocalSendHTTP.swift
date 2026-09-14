//
//  LocalSendHTTP.swift
//  VornyxNotch
//
//  Just enough HTTP/1.1 to be a LocalSend receiver.
//

import Foundation
import Network

/// One request's head. The body is read separately, because an upload is
/// streamed to disk rather than held in memory.
struct LocalSendRequest {
    let method: String
    let path: String
    let query: [String: String]
    /// Keyed by lowercased name.
    let headers: [String: String]

    var isChunked: Bool {
        headers["transfer-encoding"]?.lowercased().contains("chunked") == true
    }

    var contentLength: Int64 {
        headers["content-length"].flatMap { Int64($0.trimmingCharacters(in: .whitespaces)) } ?? 0
    }
}

enum LocalSendHTTPError: Error {
    case closed
    case malformed
    case tooLarge
}

/// A keep-alive HTTP/1.1 connection, read one request at a time.
///
/// Hand-written rather than pulled in from a server framework: the whole
/// surface is five routes, and the one hard part - an upload - has to stream
/// straight to disk anyway. Two body framings have to be understood.
/// `Content-Length` is the ordinary one. `Transfer-Encoding: chunked` is the
/// one that matters: LocalSend's Rust client streams a file without announcing
/// its size, so every upload from a real LocalSend arrives chunked.
final class LocalSendHTTPConnection: @unchecked Sendable {
    let connection: NWConnection
    /// The fingerprint of the certificate the peer presented during the
    /// handshake. Over HTTPS this is the peer's identity; anything it claims
    /// in a request body is only a claim.
    let peerFingerprint: String?

    private var buffer = Data()

    /// A head bigger than this is not a LocalSend client.
    private static let maxHeadBytes = 64 * 1024
    private static let maxLineBytes = 8 * 1024

    init(connection: NWConnection, peerFingerprint: String?) {
        self.connection = connection
        self.peerFingerprint = peerFingerprint
    }

    /// The address the request came from - what an upload is checked against.
    var remoteHost: String? {
        guard case .hostPort(let host, _) = connection.endpoint else { return nil }
        switch host {
        case .ipv4(let address): return "\(address)"
        case .ipv6(let address): return "\(address)"
        case .name(let name, _): return name
        @unknown default: return nil
        }
    }

    // MARK: - Reading

    /// The next request's head, or nil when the peer closed between requests.
    func readRequest() async throws -> LocalSendRequest? {
        let separator = Data("\r\n\r\n".utf8)
        while buffer.range(of: separator) == nil {
            guard buffer.count < Self.maxHeadBytes else { throw LocalSendHTTPError.tooLarge }
            guard try await receive() else {
                if buffer.isEmpty { return nil }
                throw LocalSendHTTPError.closed
            }
        }

        let range = buffer.range(of: separator)!
        let head = String(decoding: buffer[buffer.startIndex..<range.lowerBound], as: UTF8.self)
        buffer = Data(buffer[range.upperBound...])

        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { throw LocalSendHTTPError.malformed }

        let target = requestLine[1]
        let path: Substring
        var query: [String: String] = [:]
        if let mark = target.firstIndex(of: "?") {
            path = target[..<mark]
            query = Self.parseQuery(target[target.index(after: mark)...])
        } else {
            path = target
        }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        return LocalSendRequest(
            method: String(requestLine[0]), path: String(path), query: query, headers: headers)
    }

    /// Hand the request body to `consume` a piece at a time, whichever framing
    /// it arrives in.
    func readBody(of request: LocalSendRequest, _ consume: (Data) throws -> Void) async throws {
        guard request.isChunked else {
            try await take(Int(request.contentLength), consume)
            return
        }

        while true {
            // A size in hex, optionally followed by extensions nobody uses.
            let line = try await readLine()
            let field = line.split(separator: ";", maxSplits: 1).first
                .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            guard let size = Int(field, radix: 16), size >= 0 else {
                throw LocalSendHTTPError.malformed
            }

            if size == 0 {
                // Trailers, if any, up to the blank line that ends the message.
                while try await !readLine().isEmpty {}
                return
            }

            try await take(size, consume)
            guard try await readLine().isEmpty else { throw LocalSendHTTPError.malformed }
        }
    }

    /// The whole body, for the small JSON ones.
    func readBody(of request: LocalSendRequest, limit: Int) async throws -> Data {
        var body = Data()
        try await readBody(of: request) { piece in
            body.append(piece)
            guard body.count <= limit else { throw LocalSendHTTPError.tooLarge }
        }
        return body
    }

    private func take(_ count: Int, _ consume: (Data) throws -> Void) async throws {
        var remaining = count
        while remaining > 0 {
            if buffer.isEmpty {
                guard try await receive() else { throw LocalSendHTTPError.closed }
            }
            // The common case during an upload: the whole buffer belongs to
            // the body, so it is handed over without copying a byte.
            if buffer.count <= remaining {
                let piece = buffer
                buffer = Data()
                remaining -= piece.count
                try consume(piece)
            } else {
                let piece = Data(buffer.prefix(remaining))
                buffer = Data(buffer.dropFirst(remaining))
                remaining = 0
                try consume(piece)
            }
        }
    }

    private func readLine() async throws -> String {
        let crlf = Data("\r\n".utf8)
        while buffer.range(of: crlf) == nil {
            guard buffer.count < Self.maxLineBytes else { throw LocalSendHTTPError.tooLarge }
            guard try await receive() else { throw LocalSendHTTPError.closed }
        }
        let range = buffer.range(of: crlf)!
        let line = String(decoding: buffer[buffer.startIndex..<range.lowerBound], as: UTF8.self)
        buffer = Data(buffer[range.upperBound...])
        return line
    }

    /// Wait for more bytes. False once the peer has finished sending.
    private func receive() async throws -> Bool {
        while true {
            let (data, isComplete): (Data?, Bool) = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 512 * 1024) {
                    data, _, isComplete, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: (data, isComplete))
                    }
                }
            }
            if let data, !data.isEmpty {
                buffer.append(data)
                return true
            }
            if isComplete { return false }
        }
    }

    // MARK: - Writing

    func respond(_ status: Int, json: Data? = nil) async throws {
        var head = "HTTP/1.1 \(status) \(Self.reason(for: status))\r\n"
        if json != nil { head += "Content-Type: application/json\r\n" }
        head += "Content-Length: \(json?.count ?? 0)\r\n\r\n"

        var out = Data(head.utf8)
        if let json { out.append(json) }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: out, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    func respond<Body: Encodable>(_ status: Int, body: Body) async throws {
        try await respond(status, json: JSONEncoder().encode(body))
    }

    /// The `{"message": ...}` body LocalSend sends with every error, and the
    /// only shape its client parses for one.
    func respondError(_ status: Int, _ message: String) async throws {
        try await respond(status, body: LocalSendErrorBody(message: message))
    }

    // MARK: - Helpers

    /// `+` and `%20` both mean a space, as they do for LocalSend's own server.
    private static func parseQuery(_ string: Substring) -> [String: String] {
        var result: [String: String] = [:]
        for pair in string.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            let decode = { (part: Substring) -> String in
                let spaced = part.replacingOccurrences(of: "+", with: " ")
                return spaced.removingPercentEncoding ?? spaced
            }
            result[decode(parts[0])] = parts.count > 1 ? decode(parts[1]) : ""
        }
        return result
    }

    private static func reason(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 409: return "Conflict"
        case 429: return "Too Many Requests"
        default: return "Internal Server Error"
        }
    }
}
