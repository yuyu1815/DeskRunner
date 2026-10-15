import Darwin
import Foundation
import IOKit
import Observation

struct Metrics {
    var cpu: Double?
    var memory: Double?
    var storage: Double?
    var diskWrite: Double?
    var networkIn: Double?
    var networkOut: Double?
    var isVPN = false
}

private struct InterfaceCounters {
    var received: UInt32
    var sent: UInt32
    var isVPN: Bool
}

@MainActor
@Observable
final class MetricsSampler {
    private(set) var metrics = Metrics()

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastCPUTicks: (busy: UInt64, total: UInt64)?
    @ObservationIgnored private var lastDiskWriteBytes: UInt64?
    @ObservationIgnored private var lastInterfaces: [String: InterfaceCounters] = [:]
    @ObservationIgnored private var lastSampledAt: Date?

    func start() {
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
    }

    private func sample() {
        let now = Date()
        let elapsed = lastSampledAt.map { now.timeIntervalSince($0) } ?? 0
        lastSampledAt = now

        var next = Metrics()
        next.memory = Self.memoryPercentage()
        next.storage = Self.storagePercentage()

        let ticks = Self.cpuTicks()
        if let ticks, let last = lastCPUTicks, ticks.total > last.total {
            next.cpu = Double(ticks.busy - last.busy) / Double(ticks.total - last.total) * 100
        }
        lastCPUTicks = ticks

        let diskBytes = Self.diskWriteBytes()
        if let diskBytes, let last = lastDiskWriteBytes, elapsed > 0, diskBytes >= last {
            next.diskWrite = Double(diskBytes - last) / elapsed
        }
        lastDiskWriteBytes = diskBytes

        let interfaces = Self.interfaceCounters()
        if let interfaces {
            next.isVPN = interfaces.values.contains { $0.isVPN }
            if elapsed > 0 {
                var received: UInt64 = 0
                var sent: UInt64 = 0
                for (name, now) in interfaces where now.isVPN == next.isVPN {
                    guard let last = lastInterfaces[name] else { continue }
                    // 32bit カウンタなので wrap しても差分が正しくなるよう &- で引く
                    received += UInt64(now.received &- last.received)
                    sent += UInt64(now.sent &- last.sent)
                }
                next.networkIn = Double(received) / elapsed
                next.networkOut = Double(sent) / elapsed
            }
        }
        lastInterfaces = interfaces ?? [:]

        metrics = next
    }

    private static func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)
        return (user + system + nice, user + system + idle + nice)
    }

    // アクティビティモニタの「使用済みメモリ」(App メモリ + 確保されているメモリ + 圧縮) に合わせる
    private static func memoryPercentage() -> Double? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let appPages = UInt64(stats.internal_page_count) - UInt64(stats.purgeable_count)
        let usedPages = appPages + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        let used = Double(usedPages) * Double(getpagesize())
        return used / Double(ProcessInfo.processInfo.physicalMemory) * 100
    }

    private static func storagePercentage() -> Double? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity, total > 0,
              let available = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return Double(Int64(total) - available) / Double(total) * 100
    }

    private static func diskWriteBytes() -> UInt64? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var total: UInt64?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let property = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0),
                  let statistics = property.takeRetainedValue() as? [String: Any],
                  let bytes = statistics["Bytes (Write)"] as? UInt64 else { continue }
            total = (total ?? 0) + bytes
        }
        return total
    }

    // VPN は utun 等のうちアドレスを持つもの (アドレスなしの utun は macOS 自身が使う)
    // 物理回線は en* のうちアドレスを持つもの (bridge / vmenet / awdl は二重計上になるので除く)
    private static func interfaceCounters() -> [String: InterfaceCounters]? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var addressed: Set<String> = []
        var links: [String: (received: UInt32, sent: UInt32)] = [:]
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let address = entry.ifa_addr else { continue }
            let name = String(cString: entry.ifa_name)
            switch Int32(address.pointee.sa_family) {
            case AF_LINK:
                guard let data = entry.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
                links[name] = (data.pointee.ifi_ibytes, data.pointee.ifi_obytes)
            case AF_INET:
                addressed.insert(name)
            case AF_INET6:
                let isLinkLocal = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                    $0.pointee.sin6_addr.__u6_addr.__u6_addr8.0 == 0xfe
                        && $0.pointee.sin6_addr.__u6_addr.__u6_addr8.1 & 0xc0 == 0x80
                }
                if !isLinkLocal { addressed.insert(name) }
            default:
                continue
            }
        }

        var result: [String: InterfaceCounters] = [:]
        for (name, counters) in links where addressed.contains(name) {
            let isVPN = ["utun", "ipsec", "ppp"].contains { name.hasPrefix($0) }
            guard isVPN || name.hasPrefix("en") else { continue }
            result[name] = InterfaceCounters(received: counters.received, sent: counters.sent, isVPN: isVPN)
        }
        return result
    }
}
