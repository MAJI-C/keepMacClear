import Foundation
import Darwin
import UserNotifications
import Combine

private final class MemoryMonitorTimerBridge: NSObject {
    weak var monitor: MemoryMonitor?

    @objc func fireSystem() {
        let m = monitor
        Task { @MainActor in m?.refreshSystem() }
    }

    @objc func fireProcesses() {
        let m = monitor
        Task { @MainActor in m?.refreshProcesses() }
    }
}

@MainActor
final class MemoryMonitor: ObservableObject {
    @Published var systemMemory: SystemMemoryInfo = .empty
    @Published var topProcesses: [ProcessMemoryInfo] = []
    @Published var browserGroups: [BrowserGroup] = []
    @Published var isAutoCleanEnabled: Bool = false

    @Published var alertThresholdPercent: Double {
        didSet { UserDefaults.standard.set(alertThresholdPercent, forKey: "alertThresholdPercent") }
    }
    @Published var processLimitMB: Double {
        didSet { UserDefaults.standard.set(processLimitMB, forKey: "processLimitMB") }
    }
    @Published var autoKillEnabled: Bool {
        didSet { UserDefaults.standard.set(autoKillEnabled, forKey: "autoKillEnabled") }
    }

    nonisolated(unsafe) private var systemTimer: Timer?
    nonisolated(unsafe) private var processTimer: Timer?
    private var lastAlertDate: Date = .distantPast
    nonisolated(unsafe) private let timerBridge = MemoryMonitorTimerBridge()

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
        autoKillEnabled = UserDefaults.standard.bool(forKey: "autoKillEnabled")
        startMonitoring()
    }

    nonisolated deinit {
        DispatchQueue.main.sync {
            systemTimer?.invalidate()
            processTimer?.invalidate()
        }
        timerBridge.monitor = nil
    }

    func startMonitoring() {
        timerBridge.monitor = self
        refresh()

        systemTimer = Timer.scheduledTimer(
            timeInterval: 2.0,
            target: timerBridge,
            selector: #selector(MemoryMonitorTimerBridge.fireSystem),
            userInfo: nil,
            repeats: true
        )
        processTimer = Timer.scheduledTimer(
            timeInterval: 5.0,
            target: timerBridge,
            selector: #selector(MemoryMonitorTimerBridge.fireProcesses),
            userInfo: nil,
            repeats: true
        )
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

    fileprivate func refreshSystem() {
        Task { [weak self] in
            guard let self else { return }
            let info = await Task.detached(priority: .userInitiated) {
                MemoryMonitor.readSystemMemory()
            }.value
            self.systemMemory = info
            self.checkThreshold(info)
        }
    }

    fileprivate func refreshProcesses() {
        Task { [weak self] in
            guard let self else { return }
            let all = await Task.detached(priority: .userInitiated) {
                MemoryMonitor.readProcessList()
            }.value
            let top = Array(all.prefix(15))
            let browsers = self.buildBrowserGroups(from: all)
            self.topProcesses = top
            self.browserGroups = browsers
            if self.autoKillEnabled {
                self.enforceProcessLimit(all)
            }
        }
    }

    private func checkThreshold(_ info: SystemMemoryInfo) {
        guard info.usagePercent >= alertThresholdPercent else { return }
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
            break
        }
    }

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

    private func notify(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    nonisolated static func readSystemMemory() -> SystemMemoryInfo {
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

        let page  = UInt64(getpagesize())
        let total = ProcessInfo.processInfo.physicalMemory
        return SystemMemoryInfo(
            total:      total,
            active:     UInt64(stats.active_count)         * page,
            wired:      UInt64(stats.wire_count)           * page,
            compressed: UInt64(stats.compressor_page_count) * page,
            inactive:   UInt64(stats.inactive_count)       * page,
            free:       UInt64(stats.free_count)           * page
        )
    }

    nonisolated static func readProcessList() -> [ProcessMemoryInfo] {
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

            var nameBuf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            proc_name(pid, &nameBuf, UInt32(nameBuf.count))
            let name = ProcStrings.processName(from: nameBuf)
            guard !name.isEmpty else { continue }

            var info = proc_taskinfo()
            let ret = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info,
                                   Int32(MemoryLayout<proc_taskinfo>.size))
            guard ret > 0, info.pti_resident_size > 1_048_576 else { continue }

            result.append(ProcessMemoryInfo(pid: pid, name: name, memoryBytes: info.pti_resident_size))
        }

        return result.sorted { $0.memoryBytes > $1.memoryBytes }
    }
}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
