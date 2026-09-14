//
//  StatsManager.swift
//  VornyxNotch
//
//  What the machine is doing: processor, memory, disk and network.
//

import Combine
import Darwin
import Defaults
import Foundation

/// One reading of the machine.
struct MachineStats: Equatable {
    /// 0...1 across all cores.
    var cpu: Double = 0
    /// 0...1 of physical memory in use - not counting what the OS is only
    /// holding on to, which is memory you can have back for the asking.
    var memory: Double = 0
    var memoryUsedBytes: UInt64 = 0
    var memoryTotalBytes: UInt64 = 0

    var disk: Double = 0
    var diskUsedBytes: UInt64 = 0
    var diskTotalBytes: UInt64 = 0

    /// Bytes per second since the last reading.
    var networkDown: Double = 0
    var networkUp: Double = 0

    /// Standing facts about the machine, cheap enough to re-read every tick.
    var cores: Int = 0
    var loadAverage: Double = 0
    var swapUsed: UInt64 = 0
    var uptime: TimeInterval = 0
    var thermal: ProcessInfo.ThermalState = .nominal

    var thermalLabel: String {
        switch thermal {
        case .nominal: return "Cool"
        case .fair: return "Warm"
        case .serious: return "Hot"
        case .critical: return "Throttling"
        @unknown default: return "—"
        }
    }
}

/// Samples the machine on a timer while something is watching.
///
/// All of it comes from Mach and BSD calls that need no entitlement and no
/// permission, which is what makes it possible at all here - the usual route
/// of shelling out to `top` or `netstat` is not open to a sandboxed app.
@MainActor
final class StatsManager: ObservableObject {
    static let shared = StatsManager()

    @Published private(set) var stats = MachineStats()

    /// Recent history, kept here rather than in the view so switching away
    /// from the page and back does not start the graphs from nothing.
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var networkHistory: [(down: Double, up: Double)] = []
    private let historyLength = 60

    private var ticker: AnyCancellable?
    /// How many views want readings. The sampler runs while this is above zero
    /// and stops when the last one goes away - the dashboard is closed far more
    /// of the time than it is open.
    private var watchers = 0

    private var lastCPUTicks: (used: UInt64, total: UInt64)?
    private var lastNetwork: (received: UInt64, sent: UInt64, at: Date)?

    private init() {}

    // MARK: - Lifecycle

    func addWatcher() {
        watchers += 1
        guard watchers == 1 else { return }
        sample()
        ticker = Timer.publish(every: Defaults[.statsInterval], on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.sample() }
    }

    func removeWatcher() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        ticker?.cancel()
        ticker = nil
        // Rates are differences between readings; a gap makes the next one a
        // lie, so the baselines go with them.
        lastCPUTicks = nil
        lastNetwork = nil
    }

    /// A tuple array is not `Equatable`, so `@Published` alone would not tell
    /// SwiftUI the graph moved. This is what the views watch instead.
    var networkPeak: Double {
        networkHistory.reduce(0) { max($0, max($1.down, $1.up)) }
    }

    // MARK: - Sampling

    private func sample() {
        var next = stats
        if let cpu = Self.cpuLoad(since: &lastCPUTicks) { next.cpu = cpu }

        let memory = Self.memoryUse()
        next.memory = memory.fraction
        next.memoryUsedBytes = memory.used
        next.memoryTotalBytes = memory.total

        let disk = Self.diskUse()
        next.disk = disk.fraction
        next.diskUsedBytes = disk.used
        next.diskTotalBytes = disk.total

        if let rates = Self.networkRates(since: &lastNetwork) {
            next.networkDown = rates.down
            next.networkUp = rates.up
        }

        next.cores = ProcessInfo.processInfo.activeProcessorCount
        next.loadAverage = Self.loadAverage()
        next.swapUsed = Self.swapUsed()
        next.uptime = ProcessInfo.processInfo.systemUptime
        next.thermal = ProcessInfo.processInfo.thermalState

        stats = next

        cpuHistory.append(next.cpu)
        if cpuHistory.count > historyLength { cpuHistory.removeFirst() }

        networkHistory.append((next.networkDown, next.networkUp))
        if networkHistory.count > historyLength { networkHistory.removeFirst() }
    }

    /// The one-minute load average: how many things wanted a core at once.
    private static func loadAverage() -> Double {
        var loads = [Double](repeating: 0, count: 3)
        guard getloadavg(&loads, 3) == 3 else { return 0 }
        return loads[0]
    }

    /// Swap in use. A machine that is swapping is out of memory whatever the
    /// memory gauge says, so it is worth its own line.
    private static func swapUsed() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return usage.xsu_used
    }

    /// Days and hours; minutes stop mattering after the first one.
    static func uptime(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval))
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// Processor time spent working, as a share of all processor time since the
    /// last reading.
    ///
    /// A difference between two readings, not an instantaneous figure: the
    /// counters are totals since boot, so a single reading only ever tells you
    /// the average since the machine started.
    private static func cpuLoad(since last: inout (used: UInt64, total: UInt64)?) -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)

        let used = user + system + nice
        let total = used + idle

        defer { last = (used, total) }
        guard let previous = last else { return nil }

        let usedDelta = Double(used &- previous.used)
        let totalDelta = Double(total &- previous.total)
        guard totalDelta > 0 else { return nil }
        return (usedDelta / totalDelta).clamped(to: 0...1)
    }

    /// Memory genuinely spoken for.
    ///
    /// Active, wired and compressed - not the file cache. macOS fills spare
    /// memory with cached files on purpose and hands it straight back when
    /// anything wants it, so counting that would report a machine at 99% doing
    /// nothing at all.
    private static func memoryUse() -> (fraction: Double, used: UInt64, total: UInt64) {
        let total = ProcessInfo.processInfo.physicalMemory

        var info = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS, total > 0 else { return (0, 0, total) }

        let pageSize = UInt64(vm_kernel_page_size)
        let used = (UInt64(info.active_count)
                    + UInt64(info.wire_count)
                    + UInt64(info.compressor_page_count)) * pageSize

        return (Double(used) / Double(total), used, total)
    }

    /// The boot volume. Read through `URLResourceValues`, which a sandboxed app
    /// is allowed to ask about even for a volume it cannot list.
    private static func diskUse() -> (fraction: Double, used: UInt64, total: UInt64) {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]),
            let total = values.volumeTotalCapacity,
            let available = values.volumeAvailableCapacityForImportantUsage
        else { return (0, 0, 0) }

        let totalBytes = UInt64(max(0, total))
        let freeBytes = UInt64(max(0, available))
        let used = totalBytes > freeBytes ? totalBytes - freeBytes : 0
        guard totalBytes > 0 else { return (0, 0, 0) }
        return (Double(used) / Double(totalBytes), used, totalBytes)
    }

    /// Bytes per second in and out, summed over every real interface.
    ///
    /// Loopback is skipped - traffic a machine sends to itself is not network
    /// activity, and on a Mac running any kind of local server it dwarfs
    /// everything that actually leaves the box.
    private static func networkRates(
        since last: inout (received: UInt64, sent: UInt64, at: Date)?
    ) -> (down: Double, up: Double)? {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return nil }
        defer { freeifaddrs(pointer) }

        var received: UInt64 = 0
        var sent: UInt64 = 0

        for interface in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard interface.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let name = String(cString: interface.pointee.ifa_name)
            guard !name.hasPrefix("lo") else { continue }
            guard let data = interface.pointee.ifa_data?
                .assumingMemoryBound(to: if_data.self) else { continue }
            received += UInt64(data.pointee.ifi_ibytes)
            sent += UInt64(data.pointee.ifi_obytes)
        }

        let now = Date()
        defer { last = (received, sent, now) }
        guard let previous = last else { return nil }

        let elapsed = now.timeIntervalSince(previous.at)
        guard elapsed > 0.05 else { return nil }

        return (
            down: Double(received &- previous.received) / elapsed,
            up: Double(sent &- previous.sent) / elapsed
        )
    }

    // MARK: - Formatting

    /// Bytes as a person reads them. Two significant figures is as much as
    /// anyone takes off a gauge at a glance.
    static func bytes(_ value: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        return formatter.string(fromByteCount: Int64(value))
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        let value = max(0, bytesPerSecond)
        if value < 1000 { return "0 KB/s" }
        if value < 1_000_000 { return String(format: "%.0f KB/s", value / 1000) }
        return String(format: "%.1f MB/s", value / 1_000_000)
    }
}
