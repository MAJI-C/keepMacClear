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

// MARK: - Port Monitor

final class PortMonitor: ObservableObject {
    @Published var statuses: [PortStatus] = []
    @Published var rules: [PortRule] = []

    private var timer: Timer?
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

    deinit { stopMonitoring() }

    func startMonitoring() {
        scan() // immediate first scan
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.scan()
        }
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

    private func scan() {
        let currentRules = rules
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let enabledRules = currentRules.filter(\.enabled)
            var results: [PortStatus] = []

            for rule in enabledRules {
                let open = Self.isPortListening(rule.port)
                results.append(PortStatus(rule: rule, isOpen: open, processName: nil))
            }

            // Sort: open ports first, then by severity (critical first), then by port number
            results.sort { lhs, rhs in
                if lhs.isOpen != rhs.isOpen { return lhs.isOpen }
                if lhs.rule.severity != rhs.rule.severity {
                    return lhs.rule.severity.sortOrder < rhs.rule.severity.sortOrder
                }
                return lhs.rule.port < rhs.rule.port
            }

            DispatchQueue.main.async {
                self.statuses = results

                // Notify for newly opened ports
                for status in results where status.isOpen {
                    if !self.notifiedPorts.contains(status.rule.port) {
                        self.notifiedPorts.insert(status.rule.port)
                        self.sendNotification(for: status)
                    }
                }
                // Clear notifications for ports that closed
                let openPorts = Set(results.filter(\.isOpen).map(\.rule.port))
                self.notifiedPorts = self.notifiedPorts.intersection(openPorts)
            }
        }
    }

    // MARK: - Port Check (POSIX bind probe)

    static func isPortListening(_ port: UInt16) -> Bool {
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
