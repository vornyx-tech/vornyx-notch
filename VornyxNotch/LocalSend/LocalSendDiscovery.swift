//
//  LocalSendDiscovery.swift
//  VornyxNotch
//
//  Finding LocalSend devices on the network, and being found.
//

import Darwin
import Foundation
import Network

/// Multicast discovery, the way LocalSend does it.
///
/// Announcements go to 224.0.0.167:53317 and nobody answers them over UDP. A
/// device that hears one answers by calling `/register` on the announcer - so
/// being findable depends on our server running, and finding someone else
/// means calling *their* `/register` when their announcement arrives.
///
/// BSD sockets rather than `NWConnectionGroup`, to copy the reference socket
/// options exactly: address and port reuse, so LocalSend itself can run on the
/// same Mac; a TTL of one, so announcements stay on the local network; and
/// loopback left on, with our own messages recognised by fingerprint.
final class LocalSendDiscovery: @unchecked Sendable {
    /// An announcement from another device, and the address it came from.
    /// The address is the datagram's source, never anything in the payload.
    var onAnnouncement: (@MainActor (LocalSendInfo, String) -> Void)?

    private let queue = DispatchQueue(label: "tech.vornyx.notch.localsend.discovery")
    private var descriptor: Int32 = -1
    private var source: DispatchSourceRead?
    private var pathMonitor: NWPathMonitor?
    private var ownFingerprint = ""

    struct Interface {
        let name: String
        let address: in_addr
        let netmask: in_addr
    }

    func start(ownFingerprint: String) throws {
        stop()
        self.ownFingerprint = ownFingerprint

        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))

        // The wildcard address, not an interface's: that is what makes the
        // socket receive datagrams addressed to the group.
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = LocalSendProtocol.port.bigEndian
        address.sin_addr = in_addr(s_addr: INADDR_ANY)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EADDRINUSE
            close(fd)
            throw POSIXError(code)
        }

        var ttl: UInt8 = 1
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, 1)
        var loop: UInt8 = 1
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_LOOP, &loop, 1)
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        descriptor = fd
        joinGroups()

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.drain() }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source

        // Wi-Fi to Ethernet, a new network, a VPN: membership is per interface,
        // so it has to be taken out again on whatever is new.
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] _ in
            self?.queue.async { self?.joinGroups() }
        }
        monitor.start(queue: queue)
        pathMonitor = monitor
    }

    func stop() {
        pathMonitor?.cancel()
        pathMonitor = nil
        source?.cancel()
        source = nil
        descriptor = -1
    }

    /// Three sends at roughly 100 ms, 600 ms and 2.6 s - the reference cadence.
    ///
    /// LocalSend never re-announces on a timer either. A device that turns up
    /// later finds us when it announces itself, which makes us register with it.
    func announce(_ info: LocalSendInfo) {
        guard let payload = try? JSONEncoder().encode(info) else { return }
        var elapsed = 0.0
        for delay in [0.1, 0.5, 2.0] {
            elapsed += delay
            queue.asyncAfter(deadline: .now() + elapsed) { [weak self] in
                self?.send(payload)
            }
        }
    }

    // MARK: - Internals

    private func joinGroups() {
        guard descriptor >= 0 else { return }
        for interface in Self.interfaces() {
            var membership = ip_mreq(
                imr_multiaddr: in_addr(s_addr: inet_addr(LocalSendProtocol.multicastGroup)),
                imr_interface: interface.address)
            // Fails with EADDRINUSE on an interface we already joined, which is
            // the expected answer after a path change, not a problem.
            setsockopt(descriptor, IPPROTO_IP, IP_ADD_MEMBERSHIP, &membership,
                       socklen_t(MemoryLayout<ip_mreq>.size))
        }
    }

    private func send(_ payload: Data) {
        guard descriptor >= 0 else { return }

        var group = sockaddr_in()
        group.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        group.sin_family = sa_family_t(AF_INET)
        group.sin_port = LocalSendProtocol.port.bigEndian
        group.sin_addr = in_addr(s_addr: inet_addr(LocalSendProtocol.multicastGroup))

        let fd = descriptor
        for interface in Self.interfaces() {
            // A multicast datagram leaves by a single interface, so each one is
            // picked in turn - otherwise only the default route's network hears.
            var outgoing = interface.address
            setsockopt(fd, IPPROTO_IP, IP_MULTICAST_IF, &outgoing, socklen_t(MemoryLayout<in_addr>.size))
            payload.withUnsafeBytes { bytes in
                withUnsafePointer(to: &group) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        _ = sendto(fd, bytes.baseAddress, bytes.count, 0, $0,
                                   socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }
    }

    private func drain() {
        let fd = descriptor
        guard fd >= 0 else { return }
        var buffer = [UInt8](repeating: 0, count: 65536)

        while true {
            var from = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = buffer.withUnsafeMutableBytes { bytes in
                withUnsafeMutablePointer(to: &from) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        recvfrom(fd, bytes.baseAddress, bytes.count, 0, $0, &length)
                    }
                }
            }
            guard count > 0 else { return }

            guard let info = try? JSONDecoder().decode(LocalSendInfo.self, from: Data(buffer[0..<count])),
                  info.fingerprint.uppercased() != ownFingerprint.uppercased()
            else { continue }

            let host = String(cString: inet_ntoa(from.sin_addr))
            let handler = onAnnouncement
            Task { @MainActor in handler?(info, host) }
        }
    }

    /// IPv4 interfaces that are up, can multicast, and are not loopback.
    static func interfaces() -> [Interface] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var result: [Interface] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let flags = Int32(entry.ifa_flags)
            guard let address = entry.ifa_addr, let mask = entry.ifa_netmask,
                  address.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_MULTICAST != 0, flags & IFF_LOOPBACK == 0
            else { continue }

            result.append(Interface(
                name: String(cString: entry.ifa_name),
                address: address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr },
                netmask: mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }))
        }
        return result
    }
}
