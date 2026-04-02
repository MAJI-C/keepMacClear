import Foundation
import Darwin
import UserNotifications

// MARK: - Suspicious Spawn Event

struct SuspiciousSpawnEvent: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let parentPid: Int32
    let parentName: String
    let childPid: Int32
    let childName: String
    let reason: String
    let wasBlocked: Bool

    var timeFormatted: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: timestamp)
    }

    /// Dedup key — same parent+child name pair counts as one event within the dedup window.
    var deduplicationKey: String { "\(parentName)->\(childName)" }

    /// Block rule key (lowercased).
    var blockKey: String { "\(parentName.lowercased())->\(childName.lowercased())" }

    static func == (lhs: SuspiciousSpawnEvent, rhs: SuspiciousSpawnEvent) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Live Process Tree Node

struct ProcessTreeNode: Identifiable, Equatable {
    let id: Int32  // pid
    let pid: Int32
    let name: String
    let parentPid: Int32
    var children: [ProcessTreeNode]
    let isSuspicious: Bool

    static func == (lhs: ProcessTreeNode, rhs: ProcessTreeNode) -> Bool {
        lhs.pid == rhs.pid && lhs.name == rhs.name && lhs.children.map(\.pid) == rhs.children.map(\.pid)
    }
}

// MARK: - Heuristics (file scope so detached scan/tree code stays nonisolated)

private enum ProcessSpawnHeuristics {
    static let suspiciousParents: Set<String> = [
        "microsoft word", "microsoft excel", "microsoft powerpoint",
        "pages", "numbers", "keynote",
        "libreoffice", "openoffice",
        "preview", "adobe acrobat reader", "adobe reader",
        "skim", "pdf expert",
        "photos", "pixelmator", "figma",
        "mail", "microsoft outlook",
        "messages", "slack", "telegram", "whatsapp", "discord",
    ]

    static let suspiciousChildren: Set<String> = [
        "bash", "zsh", "sh", "dash", "fish", "tcsh", "csh", "ksh",
        "python", "python3", "python3.12", "python3.11", "python3.10",
        "ruby", "perl", "node", "osascript",
        "curl", "wget", "nc", "ncat", "socat", "ssh", "scp", "sftp", "ftp",
        "chmod", "chown", "chflags", "xattr",
        "launchctl", "defaults", "dscl", "security",
        "diskutil", "hdiutil",
        "base64", "openssl", "xxd", "tar", "zip", "unzip",
        "screencapture", "say",
        "pmset", "networksetup",
    ]
}

// MARK: - Timer bridge

private final class SpawnMonitorTimerBridge: NSObject {
    weak var monitor: ProcessSpawnMonitor?

    @objc func fire() {
        let m = monitor
        Task { @MainActor in m?.scan() }
    }
}

// MARK: - Process Spawn Monitor

@MainActor
final class ProcessSpawnMonitor: ObservableObject {
    @Published var events: [SuspiciousSpawnEvent] = []
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "spawnMonitorEnabled") }
    }

    /// Parent→child name pairs (lowercased) that should be auto-killed on sight.
    @Published var blockedPairs: Set<String> = []

    /// Live snapshot of the process tree for the monitored parents.
    @Published var processTree: [ProcessTreeNode] = []

    nonisolated(unsafe) private var timer: Timer?
    nonisolated(unsafe) private let timerBridge = SpawnMonitorTimerBridge()

    /// PIDs we have already seen, so we only flag *new* processes.
    private var knownPids: Set<Int32> = []

    /// Recently reported dedup keys with their last-reported time.
    private var recentKeys: [String: Date] = [:]

    /// Minimum seconds between duplicate alerts for the same parent→child pair.
    private let dedupInterval: TimeInterval = 60

    // ──────────────────────────────────────────────
    // Lifecycle
    // ──────────────────────────────────────────────

    init() {
        isEnabled = UserDefaults.standard.object(forKey: "spawnMonitorEnabled") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "spawnMonitorEnabled")

        // Load persisted block rules
        if let saved = UserDefaults.standard.stringArray(forKey: "blockedSpawnPairs") {
            blockedPairs = Set(saved)
        }

        // Seed known PIDs so we don't alert on everything already running.
        knownPids = Self.allCurrentPids()

        if isEnabled { startMonitoring() }
    }

    nonisolated deinit {
        DispatchQueue.main.sync {
            timer?.invalidate()
        }
        timerBridge.monitor = nil
    }

    func startMonitoring() {
        timerBridge.monitor = self
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(
            timeInterval: 3.0,
            target: timerBridge,
            selector: #selector(SpawnMonitorTimerBridge.fire),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func toggleEnabled() {
        isEnabled.toggle()
        if isEnabled {
            knownPids = Self.allCurrentPids()
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }

    func clearEvents() {
        events.removeAll()
    }

    func dismissEvent(_ event: SuspiciousSpawnEvent) {
        events.removeAll { $0.id == event.id }
    }

    // MARK: - Blocking

    /// Add a parent→child pair to the auto-block list. Future spawns will be killed immediately.
    func blockPair(parentName: String, childName: String) {
        let key = "\(parentName.lowercased())->\(childName.lowercased())"
        blockedPairs.insert(key)
        persistBlockedPairs()
    }

    /// Remove a parent→child pair from the auto-block list.
    func unblockPair(parentName: String, childName: String) {
        let key = "\(parentName.lowercased())->\(childName.lowercased())"
        blockedPairs.remove(key)
        persistBlockedPairs()
    }

    /// Block from an event directly.
    func blockEvent(_ event: SuspiciousSpawnEvent) {
        blockPair(parentName: event.parentName, childName: event.childName)
    }

    func unblockKey(_ key: String) {
        blockedPairs.remove(key)
        persistBlockedPairs()
    }

    func isBlocked(parentName: String, childName: String) -> Bool {
        let key = "\(parentName.lowercased())->\(childName.lowercased())"
        return blockedPairs.contains(key)
    }

    /// Whether a process name is in the watched-parents list.
    nonisolated func isMonitoredParent(_ name: String) -> Bool {
        ProcessSpawnHeuristics.suspiciousParents.contains(name.lowercased())
    }

    private func persistBlockedPairs() {
        UserDefaults.standard.set(Array(blockedPairs), forKey: "blockedSpawnPairs")
    }

    // MARK: - Live Process Tree

    /// Build a tree of monitored parents and their current children.
    func refreshProcessTree() {
        Task { [weak self] in
            guard let self else { return }
            let tree = await Task.detached(priority: .userInitiated) {
                ProcessSpawnMonitor.buildProcessTreeStatic()
            }.value
            self.processTree = tree
        }
    }

    nonisolated private static func buildProcessTreeStatic() -> [ProcessTreeNode] {
        let allPids = Self.allCurrentPids()
        var pidInfo: [Int32: (name: String, ppid: Int32)] = [:]
        for pid in allPids {
            if let info = Self.processInfo(pid: pid) {
                pidInfo[pid] = info
            }
        }

        // Build parent→children map
        var childrenOf: [Int32: [(pid: Int32, name: String)]] = [:]
        for (pid, info) in pidInfo {
            childrenOf[info.ppid, default: []].append((pid, info.name))
        }

        // System daemons / internal processes to skip (not useful to show)
        let skipNames: Set<String> = [
            "launchd", "kernel_task", "syslogd", "configd", "diskarbitrationd",
            "logd", "opendirectoryd", "mds_stores", "mds", "notifyd",
            "powerd", "UserEventAgent", "trustd", "securityd",
        ]

        // Find all processes that have at least one child and are user-facing apps
        // (i.e., they have >1 MB memory and are not system daemons)
        var trees: [ProcessTreeNode] = []
        var seen: Set<Int32> = []

        for (parentPid, parentInfo) in pidInfo {
            // Skip if no children
            guard let kids = childrenOf[parentPid], !kids.isEmpty else { continue }
            // Skip system daemons
            if skipNames.contains(parentInfo.name) { continue }
            // Skip if parent's parent is launchd (pid 1) and name looks like a daemon
            if parentInfo.name.hasPrefix("com.apple.") { continue }
            // Skip very low PIDs (kernel processes)
            if parentPid <= 1 { continue }
            // Only show processes that themselves have a "normal" parent
            // (their ppid should be launchd=1 or another user process)
            // This filters to top-level apps
            guard parentInfo.ppid == 1 || pidInfo[parentInfo.ppid] != nil else { continue }
            // Must be a top-level app (parent is launchd) to avoid showing deep daemon trees
            guard parentInfo.ppid == 1 else { continue }
            // Skip if already seen
            guard !seen.contains(parentPid) else { continue }
            seen.insert(parentPid)

            let isMonitoredParent = ProcessSpawnHeuristics.suspiciousParents.contains(parentInfo.name.lowercased())

            var children: [ProcessTreeNode] = []
            for kid in kids {
                let childIsSuspicious = isMonitoredParent &&
                    ProcessSpawnHeuristics.suspiciousChildren.contains(kid.name.lowercased())
                children.append(ProcessTreeNode(
                    id: kid.pid, pid: kid.pid,
                    name: kid.name,
                    parentPid: parentPid,
                    children: [],
                    isSuspicious: childIsSuspicious
                ))
            }
            children.sort { $0.name < $1.name }

            trees.append(ProcessTreeNode(
                id: parentPid, pid: parentPid,
                name: parentInfo.name,
                parentPid: parentInfo.ppid,
                children: children,
                isSuspicious: false
            ))
        }

        // Sort: monitored parents first, then by name
        return trees.sorted { lhs, rhs in
            let lhsMonitored = ProcessSpawnHeuristics.suspiciousParents.contains(lhs.name.lowercased())
            let rhsMonitored = ProcessSpawnHeuristics.suspiciousParents.contains(rhs.name.lowercased())
            if lhsMonitored != rhsMonitored { return lhsMonitored }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    // ──────────────────────────────────────────────
    // Scanning
    // ──────────────────────────────────────────────

    fileprivate func scan() {
        let knownSnapshot = knownPids
        let blockedSnapshot = blockedPairs
        let recentSnapshot = recentKeys
        let dedup = dedupInterval
        Task { [weak self] in
            guard let self else { return }
            let out = await Task.detached(priority: .utility) {
                ProcessSpawnMonitor.performScan(
                    knownPids: knownSnapshot,
                    blockedPairs: blockedSnapshot,
                    recentKeys: recentSnapshot,
                    dedupInterval: dedup
                )
            }.value

            for pid in out.pidsToKill {
                kill(pid, SIGKILL)
            }

            self.knownPids = out.currentPids
            self.recentKeys = out.updatedRecentKeys

            for event in out.newEvents {
                self.events.insert(event, at: 0)
                self.sendNotification(for: event)
            }

            if self.events.count > 50 {
                self.events = Array(self.events.prefix(50))
            }
        }
    }

    nonisolated private static func performScan(
        knownPids: Set<Int32>,
        blockedPairs: Set<String>,
        recentKeys: [String: Date],
        dedupInterval: TimeInterval
    ) -> (
        currentPids: Set<Int32>,
        newEvents: [SuspiciousSpawnEvent],
        pidsToKill: [Int32],
        updatedRecentKeys: [String: Date]
    ) {
        var recent = recentKeys
        let currentPids = Self.allCurrentPids()
        let newPids = currentPids.subtracting(knownPids)
        var newEvents: [SuspiciousSpawnEvent] = []
        var pidsToKill: [Int32] = []

        for pid in newPids {
            guard let (childName, ppid) = Self.processInfo(pid: pid) else { continue }
            guard ppid > 0 else { continue }

            guard let (parentName, _) = Self.processInfo(pid: ppid) else { continue }

            let blockKey = "\(parentName.lowercased())->\(childName.lowercased())"
            if blockedPairs.contains(blockKey) {
                pidsToKill.append(pid)
                let event = SuspiciousSpawnEvent(
                    timestamp: Date(),
                    parentPid: ppid,
                    parentName: parentName,
                    childPid: pid,
                    childName: childName,
                    reason: "BLOCKED: \"\(parentName)\" tried to spawn \"\(childName)\" — auto-killed",
                    wasBlocked: true
                )
                newEvents.append(event)
                continue
            }

            if let event = checkSuspiciousStatic(
                parentPid: ppid,
                parentName: parentName,
                childPid: pid,
                childName: childName,
                recentKeys: &recent,
                dedupInterval: dedupInterval
            ) {
                newEvents.append(event)
            }
        }

        return (currentPids, newEvents, pidsToKill, recent)
    }

    nonisolated private static func checkSuspiciousStatic(
        parentPid: Int32,
        parentName: String,
        childPid: Int32,
        childName: String,
        recentKeys: inout [String: Date],
        dedupInterval: TimeInterval
    ) -> SuspiciousSpawnEvent? {
        let parentLower = parentName.lowercased()
        let childLower = childName.lowercased()

        guard ProcessSpawnHeuristics.suspiciousParents.contains(parentLower) else { return nil }
        guard ProcessSpawnHeuristics.suspiciousChildren.contains(childLower) else { return nil }

        let key = "\(parentLower)->\(childLower)"
        let now = Date()
        if let lastTime = recentKeys[key], now.timeIntervalSince(lastTime) < dedupInterval {
            return nil
        }
        recentKeys[key] = now

        let reason = "\"\(parentName)\" spawned \"\(childName)\" — unexpected for this app type"

        return SuspiciousSpawnEvent(
            timestamp: now,
            parentPid: parentPid,
            parentName: parentName,
            childPid: childPid,
            childName: childName,
            reason: reason,
            wasBlocked: false
        )
    }

    // MARK: - Notification

    private func sendNotification(for event: SuspiciousSpawnEvent) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        if event.wasBlocked {
            content.title = "Spawn Blocked"
            content.body = "Auto-killed \(event.childName) spawned by \(event.parentName)"
        } else {
            content.title = "Suspicious Process Spawn"
            content.body = "\(event.parentName) (PID \(event.parentPid)) spawned \(event.childName) (PID \(event.childPid))"
        }
        content.sound = .defaultCritical
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: event.id.uuidString, content: content, trigger: nil)
        )
    }

    // MARK: - Low-level helpers

    /// Returns (processName, parentPid) for a given pid, or nil if unreadable.
    nonisolated static func processInfo(pid: Int32) -> (name: String, ppid: Int32)? {
        var nameBuf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        proc_name(pid, &nameBuf, UInt32(nameBuf.count))
        let name = ProcStrings.processName(from: nameBuf)
        guard !name.isEmpty else { return nil }

        var bsdInfo = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let ret = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, size)
        guard ret > 0 else { return nil }

        return (name, Int32(bsdInfo.pbi_ppid))
    }

    /// Returns the set of all currently running PIDs.
    nonisolated static func allCurrentPids() -> Set<Int32> {
        let pidCount = proc_listallpids(nil, 0)
        guard pidCount > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(pidCount) + 16)
        let actual = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard actual > 0 else { return [] }
        return Set(pids.prefix(Int(actual)).filter { $0 > 0 })
    }
}
