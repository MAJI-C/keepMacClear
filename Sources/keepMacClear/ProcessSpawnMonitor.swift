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

    var timeFormatted: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: timestamp)
    }

    /// Dedup key — same parent+child name pair counts as one event within the dedup window.
    var deduplicationKey: String { "\(parentName)->\(childName)" }

    static func == (lhs: SuspiciousSpawnEvent, rhs: SuspiciousSpawnEvent) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Process Spawn Monitor

final class ProcessSpawnMonitor: ObservableObject {
    @Published var events: [SuspiciousSpawnEvent] = []
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "spawnMonitorEnabled") }
    }

    private var timer: Timer?

    /// PIDs we have already seen, so we only flag *new* processes.
    private var knownPids: Set<Int32> = []

    /// Recently reported dedup keys with their last-reported time.
    private var recentKeys: [String: Date] = [:]

    /// Minimum seconds between duplicate alerts for the same parent→child pair.
    private let dedupInterval: TimeInterval = 60

    // ──────────────────────────────────────────────
    // Suspicious-pattern rules
    // ──────────────────────────────────────────────

    /// Parent process names (lowercased) that should NOT spawn shells / net tools.
    private let suspiciousParents: Set<String> = [
        // Office / productivity
        "microsoft word", "microsoft excel", "microsoft powerpoint",
        "pages", "numbers", "keynote",
        "libreoffice", "openoffice",
        // PDF / media viewers
        "preview", "adobe acrobat reader", "adobe reader",
        "skim", "pdf expert",
        // Image / design
        "photos", "pixelmator", "figma",
        // Mail
        "mail", "microsoft outlook",
        // Messaging
        "messages", "slack", "telegram", "whatsapp", "discord",
    ]

    /// Child process names (lowercased) considered suspicious when spawned by the above parents.
    private let suspiciousChildren: Set<String> = [
        // Shells
        "bash", "zsh", "sh", "dash", "fish", "tcsh", "csh", "ksh",
        // Scripting runtimes
        "python", "python3", "python3.12", "python3.11", "python3.10",
        "ruby", "perl", "node", "osascript",
        // Network tools
        "curl", "wget", "nc", "ncat", "socat", "ssh", "scp", "sftp", "ftp",
        // System manipulation
        "chmod", "chown", "chflags", "xattr",
        "launchctl", "defaults", "dscl", "security",
        "diskutil", "hdiutil",
        // Post-exploitation
        "base64", "openssl", "xxd", "tar", "zip", "unzip",
        "screencapture", "say",
        "pmset", "networksetup",
    ]

    // ──────────────────────────────────────────────
    // Lifecycle
    // ──────────────────────────────────────────────

    init() {
        isEnabled = UserDefaults.standard.object(forKey: "spawnMonitorEnabled") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "spawnMonitorEnabled")

        // Seed known PIDs so we don't alert on everything already running.
        knownPids = Self.allCurrentPids()

        if isEnabled { startMonitoring() }
    }

    deinit { stopMonitoring() }

    func startMonitoring() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.scan()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func toggleEnabled() {
        isEnabled.toggle()
        if isEnabled {
            // Re-seed so existing processes don't trigger alerts.
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

    // ──────────────────────────────────────────────
    // Scanning
    // ──────────────────────────────────────────────

    private func scan() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }

            let currentPids = Self.allCurrentPids()
            let newPids = currentPids.subtracting(self.knownPids)

            var newEvents: [SuspiciousSpawnEvent] = []

            for pid in newPids {
                guard let (childName, ppid) = Self.processInfo(pid: pid) else { continue }
                guard ppid > 0 else { continue }

                // Look up parent name
                guard let (parentName, _) = Self.processInfo(pid: ppid) else { continue }

                if let event = self.checkSuspicious(
                    parentPid: ppid, parentName: parentName,
                    childPid: pid, childName: childName
                ) {
                    newEvents.append(event)
                }
            }

            DispatchQueue.main.async {
                // Update known PIDs — also prune dead ones to avoid unbounded growth.
                self.knownPids = currentPids

                for event in newEvents {
                    self.events.insert(event, at: 0)
                    self.sendNotification(for: event)
                }

                // Keep only the last 50 events.
                if self.events.count > 50 {
                    self.events = Array(self.events.prefix(50))
                }
            }
        }
    }

    private func checkSuspicious(
        parentPid: Int32, parentName: String,
        childPid: Int32, childName: String
    ) -> SuspiciousSpawnEvent? {
        let parentLower = parentName.lowercased()
        let childLower = childName.lowercased()

        // Check if the parent is in our suspicious-parents list
        let matchedParent = suspiciousParents.contains(parentLower)
        guard matchedParent else { return nil }

        // Check if the child is a suspicious process
        let matchedChild = suspiciousChildren.contains(childLower)
        guard matchedChild else { return nil }

        // Dedup check
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
            reason: reason
        )
    }

    // MARK: - Notification

    private func sendNotification(for event: SuspiciousSpawnEvent) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "Suspicious Process Spawn"
        content.body = "\(event.parentName) (PID \(event.parentPid)) spawned \(event.childName) (PID \(event.childPid))"
        content.sound = .defaultCritical
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: event.id.uuidString, content: content, trigger: nil)
        )
    }

    // MARK: - Low-level helpers

    /// Returns (processName, parentPid) for a given pid, or nil if unreadable.
    static func processInfo(pid: Int32) -> (name: String, ppid: Int32)? {
        // Get process name
        var nameBuf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        proc_name(pid, &nameBuf, UInt32(nameBuf.count))
        let name = String(cString: nameBuf)
        guard !name.isEmpty else { return nil }

        // Get parent PID via BSD info
        var bsdInfo = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let ret = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, size)
        guard ret > 0 else { return nil }

        return (name, Int32(bsdInfo.pbi_ppid))
    }

    /// Returns the set of all currently running PIDs.
    static func allCurrentPids() -> Set<Int32> {
        let pidCount = proc_listallpids(nil, 0)
        guard pidCount > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(pidCount) + 16)
        let actual = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard actual > 0 else { return [] }
        return Set(pids.prefix(Int(actual)).filter { $0 > 0 })
    }
}
