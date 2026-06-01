import Combine
import Foundation
import IOKit

/// Polls CPU and GPU utilization every 2 seconds with debounce,
/// exposing light state (green/red) and raw values.
final class MonitorEngine {

    // MARK: - Configuration

    let cpuBusyThreshold: Double   // 0.0–1.0
    let gpuBusyThreshold: Int      // 0–100
    let debounceCount: Int         // consecutive samples before transition

    // MARK: - Types

    enum Light: String {
        case green = "🟢"
        case red   = "🔴"
    }

    // MARK: - Callback

    /// Called on every polling tick with the current stable light + raw readings.
    var onStatusUpdate: ((Light, Double, Int) -> Void)?

    // MARK: - Published state (for potential SwiftUI use)

    @Published var currentLight: Light = .green
    @Published var cpuUsage: Double = 0
    @Published var gpuUsage: Int = 0

    // MARK: - Internal state

    private var timer: DispatchSourceTimer?
    private var busyStreak = 0
    private var idleStreak = 0
    private var stableLight: Light = .green

    // CPU delta tracking (absolute tick counters)
    private var prevCPUTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?

    // GPU IOKit service handle
    private var gpuService: io_service_t = 0

    // MARK: - Init

    init(cpuBusyThreshold: Double = 0.65,
         gpuBusyThreshold: Int = 70,
         debounceCount: Int = 3) {
        self.cpuBusyThreshold = cpuBusyThreshold
        self.gpuBusyThreshold = gpuBusyThreshold
        self.debounceCount = debounceCount
    }

    deinit { stop() }

    // MARK: - Start / Stop

    func start() {
        gpuService = findGPUService()
        timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer?.schedule(deadline: .now(), repeating: 2.0)
        timer?.setEventHandler { [weak self] in self?.tick() }
        timer?.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        if gpuService != 0 { IOObjectRelease(gpuService); gpuService = 0 }
    }

    // MARK: - Tick

    private func tick() {
        let cpu = sampleCPU()
        let gpu = sampleGPU()

        let systemBusy = (cpu >= cpuBusyThreshold) || (gpu >= gpuBusyThreshold)

        // Debounce streaks
        if systemBusy { busyStreak += 1; idleStreak = 0 }
        else          { idleStreak += 1; busyStreak = 0 }

        // State transition only when debounce threshold is met
        let newLight: Light
        if busyStreak >= debounceCount      { newLight = .red }
        else if idleStreak >= debounceCount { newLight = .green }
        else                                { newLight = stableLight }

        stableLight = newLight

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.cpuUsage = cpu
            self.gpuUsage = gpu
            self.currentLight = newLight
            self.onStatusUpdate?(newLight, cpu, gpu)
        }
    }

    // MARK: - CPU Sampling

    private func sampleCPU() -> Double {
        let count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size
        )
        var size = count
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let ticks = (
            user:   UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle:   UInt64(info.cpu_ticks.2),
            nice:   UInt64(info.cpu_ticks.3)
        )
        defer { prevCPUTicks = ticks }

        guard let prev = prevCPUTicks else { return 0 }

        let userDelta   = ticks.user   - prev.user
        let systemDelta = ticks.system - prev.system
        let idleDelta   = ticks.idle   - prev.idle
        let niceDelta   = ticks.nice   - prev.nice
        let totalDelta  = userDelta + systemDelta + idleDelta + niceDelta

        guard totalDelta > 0 else { return 0 }
        return Double(userDelta + systemDelta + niceDelta) / Double(totalDelta)
    }

    // MARK: - GPU Sampling (IOKit, public API, no root needed)

    /// Iterates IOAccelerator services to find the one with a
    /// "Device Utilization %" key in PerformanceStatistics.
    private func findGPUService() -> io_service_t {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator
        ) == KERN_SUCCESS else { return 0 }

        defer { IOObjectRelease(iterator) }

        var best: io_service_t = 0
        var bestPriority = -1
        var service = IOIteratorNext(iterator)

        while service != 0 {
            if let candidate = retainIfHasUtilization(service) {
                let priority = isAGX(service) ? 10 : 1
                if priority > bestPriority {
                    if best != 0 { IOObjectRelease(best) }
                    best = candidate
                    bestPriority = priority
                } else {
                    IOObjectRelease(candidate)
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return best
    }

    /// Returns a retained service if it has PerformanceStatistics with
    /// "Device Utilization %", otherwise nil.
    private func retainIfHasUtilization(_ service: io_service_t) -> io_service_t? {
        var props: Unmanaged<CFMutableDictionary>? = nil
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any],
              let stats = dict["PerformanceStatistics"] as? [String: Any],
              stats["Device Utilization %"] is Int else {
            return nil
        }
        IOObjectRetain(service)
        return service
    }

    private func isAGX(_ service: io_service_t) -> Bool {
        var props: Unmanaged<CFMutableDictionary>? = nil
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any],
              let ioClass = dict["IOClass"] as? String else { return false }
        return ioClass.hasPrefix("AGX")
    }

    private func sampleGPU() -> Int {
        guard gpuService != 0 else { return 0 }
        var props: Unmanaged<CFMutableDictionary>? = nil
        guard IORegistryEntryCreateCFProperties(gpuService, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any],
              let stats = dict["PerformanceStatistics"] as? [String: Any],
              let deviceUtil = stats["Device Utilization %"] as? Int else {
            return 0
        }
        return deviceUtil
    }
}
