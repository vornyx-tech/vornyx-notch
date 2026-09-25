//
//  LocalSendIdentity.swift
//  VornyxNotch
//
//  The certificate this Mac is known by on the local network.
//

import CryptoKit
import Foundation
import Security

/// The TLS identity LocalSend peers know us by.
///
/// A peer's identity is the SHA-256 of its self-signed certificate, so the
/// certificate has to stay the same across launches. Sending needs it too: a
/// LocalSend receiver demands a client certificate over HTTPS.
///
/// The key is kept in the app's container rather than the keychain, which ties
/// a private key to the exact code signature that made it.
@MainActor
final class LocalSendIdentity {
    static let shared = LocalSendIdentity()

    private(set) var identity: SecIdentity?

    /// Uppercase hex SHA-256 of the DER certificate, no separators.
    private(set) var fingerprint: String = ""

    /// RSA-2048, to match LocalSend.
    private static let keySizeInBits = 2048

    /// The subject LocalSend uses.
    private static let commonName = "LocalSend User"

    private init() {}

    // MARK: - Lifecycle

    /// Load the stored identity, making one the first time.
    @discardableResult
    func load() throws -> SecIdentity {
        if let identity { return identity }

        let stored: (certificate: Data, key: Data)
        if let existing = Self.readStored() {
            stored = existing
        } else {
            stored = try Self.generate()
            try Self.writeStored(certificate: stored.certificate, key: stored.key)
        }

        let identity = try Self.assemble(certificateDER: stored.certificate, keyDER: stored.key)
        self.identity = identity
        fingerprint = Self.fingerprint(ofDER: stored.certificate)
        return identity
    }

    /// Throw the identity away and make a new one. Changes our fingerprint,
    /// so every peer that paired with us forgets the pairing.
    func reset() throws {
        try? FileManager.default.removeItem(at: Self.directory)
        identity = nil
        fingerprint = ""
        try load()
    }

    /// The name a peer computes for a certificate it has just been handed.
    nonisolated static func fingerprint(ofDER der: Data) -> String {
        SHA256.hash(data: der).map { String(format: "%02X", $0) }.joined()
    }

    // MARK: - Storage

    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VornyxNotch/LocalSend", isDirectory: true)
    }

    private static var certificateURL: URL { directory.appendingPathComponent("certificate.der") }
    private static var keyURL: URL { directory.appendingPathComponent("key.der") }

    private static func readStored() -> (certificate: Data, key: Data)? {
        guard let certificate = try? Data(contentsOf: certificateURL),
              let key = try? Data(contentsOf: keyURL)
        else { return nil }
        return (certificate, key)
    }

    private static func writeStored(certificate: Data, key: Data) throws {
        let manager = FileManager.default
        try manager.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        // Owner-only before the key is written, not after.
        for (url, data) in [(certificateURL, certificate), (keyURL, key)] {
            manager.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
            try data.write(to: url)
        }
    }

    // MARK: - Making one

    private static func generate() throws -> (certificate: Data, key: Data) {
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey([
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits: keySizeInBits,
        ] as CFDictionary, &error) else {
            throw LocalSendIdentityError.keyGeneration(error?.takeRetainedValue())
        }
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw LocalSendIdentityError.noPublicKey
        }
        guard let keyDER = SecKeyCopyExternalRepresentation(privateKey, &error) as Data? else {
            throw LocalSendIdentityError.keyGeneration(error?.takeRetainedValue())
        }

        let certificate = try selfSignedCertificate(publicKey: publicKey, privateKey: privateKey)
        return (certificate, keyDER)
    }

    /// Pair the stored certificate and key into an identity, without a keychain.
    ///
    /// `SecIdentityCreate` is exported but not in the public headers, so it is
    /// looked up at runtime; if it ever goes away this throws.
    private static func assemble(certificateDER: Data, keyDER: Data) throws -> SecIdentity {
        guard let certificate = SecCertificateCreateWithData(nil, certificateDER as CFData) else {
            throw LocalSendIdentityError.malformedCertificate
        }

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateWithData(keyDER as CFData, [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits: keySizeInBits,
        ] as CFDictionary, &error) else {
            throw LocalSendIdentityError.keyGeneration(error?.takeRetainedValue())
        }

        typealias Create = @convention(c) (CFAllocator?, SecCertificate, SecKey) -> Unmanaged<SecIdentity>?
        guard let security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOW),
              let symbol = dlsym(security, "SecIdentityCreate")
        else { throw LocalSendIdentityError.identityUnavailable }

        let create = unsafeBitCast(symbol, to: Create.self)
        guard let identity = create(nil, certificate, privateKey)?.takeRetainedValue() else {
            throw LocalSendIdentityError.identityUnavailable
        }
        return identity
    }

    /// Build and sign the certificate: X.509 v3, a single Common Name, no
    /// extensions. Peers check the self-signature and the dates, nothing else.
    private static func selfSignedCertificate(
        publicKey: SecKey,
        privateKey: SecKey
    ) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data?
        else {
            throw LocalSendIdentityError.keyGeneration(error?.takeRetainedValue())
        }

        let name = DER.sequence(of: [
            DER.set(of: [
                DER.sequence(of: [
                    DER.objectIdentifier([2, 5, 4, 3]),
                    DER.utf8String(commonName),
                ])
            ])
        ])

        // Backdated a day, since the two devices' clocks differ.
        let now = Date()
        let validity = DER.sequence(of: [
            DER.time(now.addingTimeInterval(-86_400)),
            DER.time(now.addingTimeInterval(20 * 365.25 * 86_400)),
        ])

        // sha256WithRSAEncryption, with the NULL parameters RSA identifiers carry.
        let signatureAlgorithm = DER.sequence(of: [
            DER.objectIdentifier([1, 2, 840, 113549, 1, 1, 11]),
            DER.null(),
        ])

        let subjectPublicKeyInfo = DER.sequence(of: [
            DER.sequence(of: [
                DER.objectIdentifier([1, 2, 840, 113549, 1, 1, 1]),
                DER.null(),
            ]),
            // `SecKeyCopyExternalRepresentation` gives the PKCS#1 RSAPublicKey body.
            DER.bitString(publicKeyData),
        ])

        let tbs = DER.sequence(of: [
            // Version is [0] EXPLICIT and defaults to v1, so v3 has to say so.
            DER.explicit(tag: 0, DER.integer(2)),
            DER.integer(serialNumber()),
            signatureAlgorithm,
            name,
            validity,
            name,
            subjectPublicKeyInfo,
        ])

        guard let signature = SecKeyCreateSignature(
            privateKey, .rsaSignatureMessagePKCS1v15SHA256, tbs as CFData, &error
        ) as Data? else {
            throw LocalSendIdentityError.signing(error?.takeRetainedValue())
        }

        return DER.sequence(of: [tbs, signatureAlgorithm, DER.bitString(signature)])
    }

    /// A positive 16-byte serial: DER integers are signed, so clear the top bit.
    private static func serialNumber() -> Data {
        var bytes = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        bytes[0] &= 0x7F
        if bytes[0] == 0 { bytes[0] = 1 }
        return bytes
    }
}

enum LocalSendIdentityError: Error {
    case keyGeneration(CFError?)
    case signing(CFError?)
    case noPublicKey
    case malformedCertificate
    case identityUnavailable
}

// MARK: - Just enough DER

/// The sliver of ASN.1 a certificate needs. Definite-length DER only.
private enum DER {
    static func encode(tag: UInt8, _ contents: Data) -> Data {
        var out = Data([tag])
        out.append(length(contents.count))
        out.append(contents)
        return out
    }

    /// Short form up to 127 bytes, then a big-endian length with a byte count.
    private static func length(_ value: Int) -> Data {
        if value < 0x80 { return Data([UInt8(value)]) }
        var bytes: [UInt8] = []
        var remaining = value
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0xFF), at: 0)
            remaining >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }

    static func sequence(of parts: [Data]) -> Data { encode(tag: 0x30, parts.reduce(Data(), +)) }
    static func set(of parts: [Data]) -> Data { encode(tag: 0x31, parts.reduce(Data(), +)) }
    static func explicit(tag: UInt8, _ content: Data) -> Data { encode(tag: 0xA0 | tag, content) }
    static func null() -> Data { Data([0x05, 0x00]) }
    static func integer(_ value: Int) -> Data { encode(tag: 0x02, Data([UInt8(value)])) }
    static func integer(_ bytes: Data) -> Data { encode(tag: 0x02, bytes) }

    /// Unused-bits count is always zero: everything wrapped is whole bytes.
    static func bitString(_ bytes: Data) -> Data { encode(tag: 0x03, Data([0x00]) + bytes) }
    static func utf8String(_ string: String) -> Data { encode(tag: 0x0C, Data(string.utf8)) }

    /// The first two arcs share a byte, every later arc is base-128.
    static func objectIdentifier(_ arcs: [UInt]) -> Data {
        var body = Data([UInt8(arcs[0] * 40 + arcs[1])])
        for arc in arcs.dropFirst(2) {
            var septets: [UInt8] = [UInt8(arc & 0x7F)]
            var remaining = arc >> 7
            while remaining > 0 {
                septets.insert(UInt8(remaining & 0x7F) | 0x80, at: 0)
                remaining >>= 7
            }
            body.append(contentsOf: septets)
        }
        return encode(tag: 0x06, body)
    }

    /// UTCTime through 2049, GeneralizedTime from 2050, as X.509 requires.
    static func time(_ date: Date) -> Data {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")

        if calendar.component(.year, from: date) < 2050 {
            formatter.dateFormat = "yyMMddHHmmss'Z'"
            return encode(tag: 0x17, Data(formatter.string(from: date).utf8))
        }
        formatter.dateFormat = "yyyyMMddHHmmss'Z'"
        return encode(tag: 0x18, Data(formatter.string(from: date).utf8))
    }
}
