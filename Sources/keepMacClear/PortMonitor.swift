import Foundation
import Darwin
import UserNotifications

// MARK: - Port Rule (JSON-decodable)

struct PortRule: Codable, Identifiable, Equatable {
    var id: UInt16 { port }
    let port: UInt16
    let name: String
    let description: String
    let severity: Severity
    var enabled: Bool

    enum Severity: String, Codable, CaseIterable {
        case low, medium, high, critical
    }
}

// MARK: - Port Status (runtime)

struct PortStatus: Identifiable, Equatable {
    var id: UInt16 { rule.port }
    let rule: PortRule
    let isOpen: Bool
    /// Name of the process listening on this port, if we can determine it.
    let processName: String?
}

// MARK: - Timer bridge

private final class PortMonitorTimerBridge: NSObject {
    weak var monitor: PortMonitor?

    @objc func fire() {
        let m = monitor
        Task { @MainActor in m?.scan() }
    }
}

// MARK: - Port Monitor

@MainActor
final class PortMonitor: ObservableObject {
    @Published var statuses: [PortStatus] = []
    @Published var rules: [PortRule] = []

    nonisolated(unsafe) private var timer: Timer?
    nonisolated(unsafe) private let timerBridge = PortMonitorTimerBridge()
    let rulesURL: URL

    /// Public accessor for the view.
    var rulesFileURL: URL { rulesURL }

    /// Ports that were already notified as open — reset when port closes.
    private var notifiedPorts: Set<UInt16> = []

    // ──────────────────────────────────────────────
    // Lifecycle
    // ──────────────────────────────────────────────

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("keepMacClear", isDirectory: true)
        rulesURL = dir.appendingPathComponent("port-rules.json")

        ensureDefaultRules(directory: dir)
        rules = loadRules()
        startMonitoring()
    }

    nonisolated deinit {
        DispatchQueue.main.sync {
            timer?.invalidate()
        }
        timerBridge.monitor = nil
    }

    func startMonitoring() {
        timerBridge.monitor = self
        scan() // immediate first scan
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(
            timeInterval: 10.0,
            target: timerBridge,
            selector: #selector(PortMonitorTimerBridge.fire),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    /// Reload rules from disk (user edited the JSON).
    func reloadRules() {
        rules = loadRules()
        scan()
    }

    /// Toggle a rule on/off and persist to disk.
    func toggleRule(port: UInt16) {
        guard let idx = rules.firstIndex(where: { $0.port == port }) else { return }
        rules[idx].enabled.toggle()
        saveRules()
        scan()
    }

    // ──────────────────────────────────────────────
    // Scanning
    // ──────────────────────────────────────────────

    fileprivate func scan() {
        let currentRules = rules
        Task { [weak self] in
            guard let self else { return }
            let results = await Task.detached(priority: .utility) {
                PortMonitor.buildStatuses(for: currentRules)
            }.value

            self.statuses = results

            for status in results where status.isOpen {
                if !self.notifiedPorts.contains(status.rule.port) {
                    self.notifiedPorts.insert(status.rule.port)
                    self.sendNotification(for: status)
                }
            }
            let openPorts = Set(results.filter(\.isOpen).map(\.rule.port))
            self.notifiedPorts = self.notifiedPorts.intersection(openPorts)
        }
    }

    nonisolated private static func buildStatuses(for rules: [PortRule]) -> [PortStatus] {
        let enabledRules = rules.filter(\.enabled)
        var results: [PortStatus] = []

        for rule in enabledRules {
            let open = Self.isPortListening(rule.port)
            results.append(PortStatus(rule: rule, isOpen: open, processName: nil))
        }

        results.sort { lhs, rhs in
            if lhs.isOpen != rhs.isOpen { return lhs.isOpen }
            if lhs.rule.severity != rhs.rule.severity {
                return lhs.rule.severity.sortOrder < rhs.rule.severity.sortOrder
            }
            return lhs.rule.port < rhs.rule.port
        }
        return results
    }

    // MARK: - Port Check (POSIX bind probe)

    nonisolated static func isPortListening(_ port: UInt16) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        // Allow address reuse so our probe doesn't block anything
        var reuse: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = UInt32(INADDR_ANY).bigEndian

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if result < 0 && errno == EADDRINUSE {
            return true  // something is already listening
        }
        // bind succeeded → port was free, nothing listening
        return false
    }

    // MARK: - macOS system service commands (requires admin via osascript)

    /// Maps ports to the launchctl/system command needed to disable them.
    /// These are macOS-managed services that can't be killed with SIGTERM.
    private static let systemServiceCommands: [UInt16: (name: String, disable: String)] = [
        5900: ("Screen Sharing (VNC)",
               "launchctl disable system/com.apple.screensharing"),
        22:   ("Remote Login (SSH)",
               "systemsetup -setremotelogin off"),
        445:  ("File Sharing (SMB)",
               "launchctl unload -w /System/Library/LaunchDaemons/com.apple.smbd.plist"),
        631:  ("CUPS (Printing)",
               "cupsctl --no-remote-any --no-share-printers && launchctl unload /System/Library/LaunchDaemons/org.cups.cupsd.plist"),
        548:  ("AFP File Sharing",
               "launchctl unload -w /System/Library/LaunchDaemons/com.apple.AppleFileServer.plist"),
        3689: ("DAAP (iTunes Sharing)",
               "defaults write com.apple.iTunes disableSharedMusic -bool YES"),
    ]

    // MARK: - Close Port

    /// Closes a port — uses system commands for macOS services, lsof+kill for regular processes.
    func closePort(_ port: UInt16) async -> (success: Bool, message: String) {
        // Check if this is a known macOS system service
        if let service = Self.systemServiceCommands[port] {
            return await closeSystemService(port: port, service: service)
        }

        // Regular process: find via lsof and kill
        return await closeRegularProcess(port: port)
    }

    /// Disables a macOS system service via admin-privileged shell command.
    private func closeSystemService(
        port: UInt16,
        service: (name: String, disable: String)
    ) async -> (success: Bool, message: String) {
        let cmd = service.disable
        let svcName = service.name
        let result = await Task.detached(priority: .userInitiated) { () -> (Bool, String) in
            // Use osascript to run with admin privileges (triggers system password prompt)
            let script = "do shell script \"\(cmd)\" with administrator privileges"
            guard let appleScript = NSAppleScript(source: script) else {
                return (false, "Could not create script to disable \(svcName)")
            }
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error {
                let msg = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                // User cancelled the admin prompt
                if msg.contains("User canceled") || msg.contains("-128") {
                    return (false, "Admin permission required to disable \(svcName)")
                }
                return (false, "\(svcName): \(msg)")
            }
            return (true, "Disabled \(svcName) — turn it back on in System Settings if needed")
        }.value

        try? await Task.sleep(nanoseconds: 2_000_000_000)
        scan()
        return result
    }

    /// Finds the process listening on a port via lsof and kills it.
    private func closeRegularProcess(port: UInt16) async -> (success: Bool, message: String) {
        let result = await Task.detached(priority: .userInitiated) { () -> (Bool, String) in
            // First try lsof
            let pipe = Pipe()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            process.arguments = ["-iTCP:\(port)", "-sTCP:LISTEN", "-nP", "-t"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return (false, "Could not run lsof")
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard !output.isEmpty else {
                // lsof found nothing — might be a launchd-managed socket
                // Try to find via launchctl
                return Self.tryLaunchctlDisable(port: port)
            }

            let pids = output.split(separator: "\n").compactMap { Int32($0) }
            var killedNames: [String] = []

            for pid in pids {
                var nameBuf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
                proc_name(pid, &nameBuf, UInt32(nameBuf.count))
                let name = ProcStrings.processName(from: nameBuf)
                killedNames.append(name.isEmpty ? "PID \(pid)" : name)
                kill(pid, SIGTERM)
            }

            usleep(2_000_000)
            for pid in pids { kill(pid, SIGKILL) }

            let desc = killedNames.joined(separator: ", ")
            return (true, "Killed: \(desc)")
        }.value

        try? await Task.sleep(nanoseconds: 1_000_000_000)
        scan()
        return result
    }

    /// Fallback: try to find the launchd service holding the port and disable it with admin privileges.
    nonisolated private static func tryLaunchctlDisable(port: UInt16) -> (Bool, String) {
        // Use lsof without -t to get more info (including launchd-managed sockets)
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-i", ":\(port)", "-nP"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (false, "Port \(port) is held by a system service — disable it in System Settings")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        if output.contains("launchd") {
            return (false, "Port \(port) is managed by launchd — disable the service in System Settings → Sharing")
        }

        if !output.isEmpty {
            // Extract process name from lsof output
            let firstLine = output.split(separator: "\n").dropFirst().first ?? ""
            let processName = firstLine.split(separator: " ").first.map(String.init) ?? "unknown"
            return (false, "Port \(port) held by \(processName) — may need admin privileges to close")
        }

        return (false, "Port \(port) appears bound at kernel level — disable via System Settings → Sharing")
    }

    // MARK: - Notification

    private func sendNotification(for status: PortStatus) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "Vulnerable Port Open"
        content.body = "Port \(status.rule.port) (\(status.rule.name)) is listening — \(status.rule.description)"
        content.sound = status.rule.severity == .critical ? .defaultCritical : .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "port-\(status.rule.port)", content: content, trigger: nil)
        )
    }

    // MARK: - Rule Persistence

    private func loadRules() -> [PortRule] {
        guard let data = try? Data(contentsOf: rulesURL),
              let decoded = try? JSONDecoder().decode([PortRule].self, from: data)
        else { return Self.defaultRules }
        return decoded
    }

    private func saveRules() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(rules) else { return }
        try? data.write(to: rulesURL, options: .atomic)
    }

    private func ensureDefaultRules(directory: URL) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: rulesURL.path) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(Self.defaultRules) {
                try? data.write(to: rulesURL, options: .atomic)
            }
        }
    }

    // MARK: - Default Rules

    static let defaultRules: [PortRule] = [
        // Critical
        PortRule(port: 23,    name: "Telnet",        description: "Unencrypted remote access — credentials sent in plaintext",                  severity: .critical, enabled: true),
        PortRule(port: 445,   name: "SMB",           description: "Windows file sharing — frequent target of worms (EternalBlue)",              severity: .critical, enabled: true),
        PortRule(port: 3389,  name: "RDP",           description: "Remote Desktop Protocol — top target for brute-force attacks",               severity: .critical, enabled: true),
        PortRule(port: 1433,  name: "MSSQL",         description: "Microsoft SQL Server — database exposed to network",                        severity: .critical, enabled: true),

        // High
        PortRule(port: 21,    name: "FTP",           description: "File Transfer Protocol — plaintext credentials, bounce attacks",             severity: .high,    enabled: true),
        PortRule(port: 22,    name: "SSH",           description: "Secure Shell — safe if key-only, risky if password auth enabled",            severity: .high,    enabled: true),
        PortRule(port: 25,    name: "SMTP",          description: "Mail relay — can be abused for spam if misconfigured",                      severity: .high,    enabled: true),
        PortRule(port: 3306,  name: "MySQL",         description: "MySQL database — should not be network-exposed",                            severity: .high,    enabled: true),
        PortRule(port: 5432,  name: "PostgreSQL",    description: "PostgreSQL database — should not be network-exposed",                       severity: .high,    enabled: true),
        PortRule(port: 5900,  name: "VNC",           description: "Screen sharing / VNC — often weakly authenticated",                         severity: .high,    enabled: true),
        PortRule(port: 6379,  name: "Redis",         description: "Redis — no auth by default, remote code execution risk",                    severity: .high,    enabled: true),
        PortRule(port: 27017, name: "MongoDB",       description: "MongoDB — no auth by default, data exfiltration risk",                      severity: .high,    enabled: true),
        PortRule(port: 11211, name: "Memcached",     description: "Memcached — no auth, amplification attack vector",                          severity: .high,    enabled: true),

        // Medium
        PortRule(port: 53,    name: "DNS",           description: "DNS server — cache poisoning risk if unneeded",                             severity: .medium,  enabled: true),
        PortRule(port: 80,    name: "HTTP",          description: "Unencrypted web server — check if intentional",                             severity: .medium,  enabled: true),
        PortRule(port: 443,   name: "HTTPS",         description: "Web server (TLS) — verify it's expected",                                  severity: .medium,  enabled: false),
        PortRule(port: 8080,  name: "HTTP Alt",      description: "Alternate HTTP — often dev servers left running",                           severity: .medium,  enabled: true),
        PortRule(port: 8443,  name: "HTTPS Alt",     description: "Alternate HTTPS — often dev servers left running",                          severity: .medium,  enabled: true),
        PortRule(port: 9200,  name: "Elasticsearch", description: "Elasticsearch — no auth by default, data exposure risk",                    severity: .medium,  enabled: true),
        PortRule(port: 2375,  name: "Docker",        description: "Docker API (unencrypted) — full host compromise if exposed",                severity: .high,    enabled: true),
        PortRule(port: 2376,  name: "Docker TLS",    description: "Docker API (TLS) — verify cert auth is enforced",                           severity: .medium,  enabled: true),

        // Low
        PortRule(port: 5353,  name: "mDNS",          description: "Bonjour/mDNS — normal on macOS, low risk",                                 severity: .low,     enabled: false),
        PortRule(port: 631,   name: "CUPS/IPP",      description: "Printing service — normal on macOS",                                       severity: .low,     enabled: false),
    ]
}

// MARK: - Severity helpers

extension PortRule.Severity {
    var sortOrder: Int {
        switch self {
        case .critical: return 0
        case .high:     return 1
        case .medium:   return 2
        case .low:      return 3
        }
    }

    var label: String { rawValue.capitalized }
}
