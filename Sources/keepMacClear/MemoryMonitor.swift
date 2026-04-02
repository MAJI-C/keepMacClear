import Foundation
import Darwin
import UserNotifications
import Combine

// MARK: - MemoryMonitor

final class MemoryMonitor: ObservableObject {
    @Published var systemMemory: SystemMemoryInfo = .empty
    @Published var topProcesses: [ProcessMemoryInfo] = []
    @Published var browserGroups: [BrowserGroup] = []
    @Published var isAutoCleanEnabled: Bool = false

    // User-configurable limits (stored in UserDefaults)
    @Published var alertThresholdPercent: Double {
        didSet { UserDefaults.standard.set(alertThresholdPercent, forKey: "alertThresholdPercent") }
    }
    @Published var processLimitMB: Double {
        didSet { UserDefaults.standard.set(processLimitMB, forKey: "processLimitMB") }
    }
    @Published var autoKillEnabled: Bool {
        didSet { UserDefaults.standard.set(autoKillEnabled, forKey: "autoKillEnabled") }
    }

    private var systemTimer: Timer?
    private var processTimer: Timer?
    private var lastAlertDate: Date = .distantPast

    // Known browser process name prefixes, keyed by display name
    private let browserMap: [String: [String]] = [
        "Google Chrome": ["Google Chrome", "Google Chrome Helper"],
        "Safari":        ["Safari", "Safari Web Content", "com.apple.WebKit.WebContent",
                          "com.apple.WebKit.GPU", "com.apple.WebKit.Networking"],
        "Firefox":       ["firefox", "Firefox", "Web Content", "RDD Process"],
        "Microsoft Edge":["Microsoft Edge", "Microsoft Edge Helper"],
        "Arc":           ["Arc", "Arc Helper"],
        "Brave Browser": ["Brave Browser", "Brave Browser Helper"],
        "Opera":         ["Opera", "opera"],
        "Vivaldi":       ["Vivaldi", "Vivaldi Helper"],
    ]

    init() {
        alertThresholdPercent = UserDefaults.standard.double(forKey: "alertThresholdPercent").nonZero ?? 85
        if UserDefaults.standard.object(forKey: "processLimitMB") == nil {
            processLimitMB = 0
        } else {
            processLimitMB = UserDefaults.standard.double(forKey: "processLimitMB")
        }
        autoKillEnabled       = UserDefaults.standard.bool(forKey: "autoKillEnabled")
        startMonitoring()
    }

    deinit { stopMonitoring() }

    // MARK: - Control

    func startMonitoring() {
        refresh()

        systemTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshSystem()
        }
        processTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refreshProcesses()
        }
        RunLoop.main.add(systemTimer!, forMode: .common)
        RunLoop.main.add(processTimer!, forMode: .common)
    }

    func stopMonitoring() {
        systemTimer?.invalidate()
        processTimer?.invalidate()
    }

    func refresh() {
        refreshSystem()
        refreshProcesses()
    }

    // MARK: - Refresh

    private func refreshSystem() {
        // host_statistics64 is a mach syscall — always read off the main thread.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let info = Self.readSystemMemory()
            DispatchQueue.main.async {
                guard let self else { return }
                self.systemMemory = info
                self.checkThreshold(info)
            }
        }
    }

    private func refreshProcesses() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let all = Self.readProcessList()
            let top = Array(all.prefix(15))
            let browsers = self.buildBrowserGroups(from: all)
            DispatchQueue.main.async {
                self.topProcesses = top
                self.browserGroups = browsers
                if self.autoKillEnabled {
                    self.enforceProcessLimit(all)
                }
            }
        }
    }

    // MARK: - Threshold / Limit Checks

    private func checkThreshold(_ info: SystemMemoryInfo) {
        guard info.usagePercent >= alertThresholdPercent else { return }
        // Debounce: at most one alert per 5 minutes
        let now = Date()
        guard now.timeIntervalSince(lastAlertDate) > 300 else { return }
        lastAlertDate = now

        notify(
            title: "High Memory Pressure",
            body: String(format: "RAM at %.0f%% — consider cleaning memory.", info.usagePercent)
        )

        if isAutoCleanEnabled {
            MemoryCleaner.shared.freeAllocatorMemory()
        }
    }

    private func enforceProcessLimit(_ processes: [ProcessMemoryInfo]) {
        guard processLimitMB > 0 else { return }
        let limitBytes = UInt64(processLimitMB) * 1_048_576
        for proc in processes where proc.memoryBytes > limitBytes {
            notify(
                title: "Process Over Limit",
                body: "\(proc.name) is using \(proc.memoryFormatted) — over your \(Int(processLimitMB)) MB limit."
            )
            MemoryCleaner.shared.killProcess(pid: proc.pid)
            break // handle one at a time
        }
    }

    // MARK: - Browser Grouping

    private func buildBrowserGroups(from processes: [ProcessMemoryInfo]) -> [BrowserGroup] {
        browserMap.compactMap { browserName, prefixes -> BrowserGroup? in
            let matching = processes.filter { proc in
                prefixes.contains { proc.name.hasPrefix($0) }
            }
            guard !matching.isEmpty else { return nil }
            let sorted = matching.sorted { $0.memoryBytes > $1.memoryBytes }
            return BrowserGroup(
                name: browserName,
                processes: sorted,
                totalMemory: sorted.reduce(0) { $0 + $1.memoryBytes }
            )
        }
        .sorted { $0.totalMemory > $1.totalMemory }
    }

    // MARK: - Notifications

    private func notify(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return } // needs .app bundle
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    // MARK: - System Memory Reading

    static func readSystemMemory() -> SystemMemoryInfo {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
        )
        let kern = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kern == KERN_SUCCESS else { return .empty }

        let page   = UInt64(vm_kernel_page_size)
        let total  = ProcessInfo.processInfo.physicalMemory
        return SystemMemoryInfo(
            total:      total,
            active:     UInt64(stats.active_count)         * page,
            wired:      UInt64(stats.wire_count)           * page,
            compressed: UInt64(stats.compressor_page_count) * page,
            inactive:   UInt64(stats.inactive_count)       * page,
            free:       UInt64(stats.free_count)           * page
        )
    }

    // MARK: - Process List Reading

    static func readProcessList() -> [ProcessMemoryInfo] {
        let pidCount = proc_listallpids(nil, 0)
        guard pidCount > 0 else { return [] }

        var pids = [pid_t](repeating: 0, count: Int(pidCount) + 16)
        let actual = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard actual > 0 else { return [] }

        var result: [ProcessMemoryInfo] = []
        result.reserveCapacity(Int(actual))

        for i in 0..<Int(actual) {
            let pid = pids[i]
            guard pid > 0 else { continue }

            // Process name
            var nameBuf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            proc_name(pid, &nameBuf, UInt32(nameBuf.count))
            let name = String(cString: nameBuf)
            guard !name.isEmpty else { continue }

            // Task / memory info
            var info = proc_taskinfo()
            let ret = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info,
                                   Int32(MemoryLayout<proc_taskinfo>.size))
            guard ret > 0, info.pti_resident_size > 1_048_576 else { continue } // >1 MB

            result.append(ProcessMemoryInfo(pid: pid, name: name, memoryBytes: info.pti_resident_size))
        }

        return result.sorted { $0.memoryBytes > $1.memoryBytes }
    }
}

// MARK: - Helpers

private extension Double {
    /// Returns nil when the value is 0 (so we can fall back to a default).
    var nonZero: Double? { self == 0 ? nil : self }
}
