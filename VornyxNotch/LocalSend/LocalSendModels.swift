//
//  LocalSendModels.swift
//  VornyxNotch
//
//  What goes over the wire.
//

import Foundation
import UniformTypeIdentifiers

/// Fixed by the LocalSend protocol.
enum LocalSendProtocol {
    static let version = "2.2"
    static let port: UInt16 = 53317
    static let multicastGroup = "224.0.0.167"
    static let apiPrefix = "/api/localsend/v2"
}

/// The self-description every device sends: in a multicast announcement, a
/// register request, and at the top of a transfer request.
struct LocalSendInfo: Codable, Equatable {
    var alias: String
    var version: String
    var deviceModel: String?
    var deviceType: String?
    var fingerprint: String
    var port: Int?
    var `protocol`: String?
    var download: Bool?
    /// Only in multicast announcements.
    var announce: Bool?
}

/// One file offered in a transfer request.
///
/// `fileType` is a MIME type, but older peers send a bare word instead
/// (`image`, `video`, `pdf`, `text`, `apk`, `other`), so it stays a string.
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

/// The only error body shape LocalSend sends or parses.
struct LocalSendErrorBody: Codable {
    var message: String
}

/// A peer we can send to, identified by fingerprint rather than address.
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
        // IPv6 literals need brackets in a URL.
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
