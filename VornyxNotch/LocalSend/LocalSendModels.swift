//
//  LocalSendModels.swift
//  VornyxNotch
//
//  What goes over the wire, spelled the way LocalSend spells it.
//

import Foundation
import UniformTypeIdentifiers

/// Protocol constants. Every one of these is compared against what other
/// implementations send, so none of them is ours to tune.
enum LocalSendProtocol {
    static let version = "2.2"
    static let port: UInt16 = 53317
    static let multicastGroup = "224.0.0.167"
    static let apiPrefix = "/api/localsend/v2"
}

/// The self-description every device sends: in a multicast announcement, a
/// register request, and at the top of a transfer request.
///
/// `deviceModel` and `deviceType` are omitted rather than sent as null when
/// unknown, which is what the reference implementation does. `port` and
/// `protocol` are absent from `/info` and register *responses*, so they are
/// optional here too.
struct LocalSendInfo: Codable, Equatable {
    var alias: String
    var version: String
    var deviceModel: String?
    var deviceType: String?
    var fingerprint: String
    var port: Int?
    var `protocol`: String?
    var download: Bool?
    /// Only in multicast announcements. Always `true` when we send it, and
    /// ignored when we read it - modern LocalSend treats both values alike.
    var announce: Bool?
}

/// One file offered in a transfer request.
///
/// `fileType` is a MIME type derived from the extension, falling back to
/// `application/octet-stream`. Older peers send one of a handful of bare
/// words instead (`image`, `video`, `pdf`, `text`, `apk`, `other`), which only
/// matters for display, so it is kept as a plain string.
struct LocalSendFile: Codable, Equatable {
    var id: String
    var fileName: String
    var size: Int64
    var fileType: String
    var sha256: String?
    /// Doubles as the payload for text messages sent from a phone.
    var preview: String?
    var metadata: Metadata?

    struct Metadata: Codable, Equatable {
        var modified: String?
        var accessed: String?
    }

    static func mimeType(forFileName name: String) -> String {
        let ext = (name as NSString).pathExtension
        return UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
    }
}

struct LocalSendPrepareUploadRequest: Codable {
    var info: LocalSendInfo
    var files: [String: LocalSendFile]
}

struct LocalSendPrepareUploadResponse: Codable {
    var sessionId: String
    var files: [String: String]
}

/// Every error body LocalSend sends, and the only shape it parses.
struct LocalSendErrorBody: Codable {
    var message: String
}

/// A peer we can send to.
///
/// Identified by fingerprint, not address: the same phone moves between
/// addresses, and over HTTPS the fingerprint is what the handshake proves.
struct LocalSendDevice: Identifiable, Equatable {
    var id: String { fingerprint }
    var fingerprint: String
    var alias: String
    var deviceModel: String?
    var deviceType: String?
    var host: String
    var port: Int
    var isHTTPS: Bool
    var lastSeen: Date

    var baseURL: URL? {
        // IPv6 literals need brackets in a URL, and link-local ones a scope
        // that `URL` will not take - so those peers are skipped upstream.
        let hostPart = host.contains(":") ? "[\(host)]" : host
        return URL(string: "\(isHTTPS ? "https" : "http")://\(hostPart):\(port)")
    }

    /// The glyph for the kind of device it says it is.
    var symbol: String {
        switch deviceType {
        case "mobile": return "iphone"
        case "web": return "globe"
        case "headless", "server": return "server.rack"
        default:
            switch deviceModel?.lowercased() {
            case let model? where model.contains("windows"): return "pc"
            case let model? where model.contains("linux"): return "desktopcomputer"
            default: return "laptopcomputer"
            }
        }
    }
}
