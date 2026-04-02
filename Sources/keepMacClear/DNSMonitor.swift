import Foundation
import SystemConfiguration
import UserNotifications

// MARK: - DNS Provider

enum DNSProvider: String, CaseIterable {
    case cloudflare = "Cloudflare"
    case google = "Google"
    case quad9 = "Quad9"
    case openDNS = "OpenDNS"
    case unknown = "Unknown"

    static func identify(_ address: String) -> DNSProvider {
        switch address {
        // IPv4
        case "1.1.1.1", "1.0.0.1":                          return .cloudflare
        case "8.8.8.8", "8.8.4.4":                          return .google
        case "9.9.9.9", "149.112.112.112":                   return .quad9
        case "208.67.222.222", "208.67.220.220":             return .openDNS
        // IPv6
        case "2606:4700:4700::1111", "2606:4700:4700::1001": return .cloudflare
        case "2001:4860:4860::8888", "2001:4860:4860::8844": return .google
        case "2620:fe::fe", "2620:fe::9":                    return .quad9
        case "2620:119:35::35", "2620:119:53::53":           return .openDNS
        default:                                              return .unknown
        }
    }

    var isSafe: Bool { self != .unknown }

    var icon: String {
        switch self {
        case .cloudflare: return "shield.checkered"
        case .google:     return "g.circle.fill"
        case .quad9:      return "9.circle.fill"
        case .openDNS:    return "lock.shield.fill"
        case .unknown:    return "questionmark.circle.fill"
        }
    }
}

// MARK: - DNS Server Info

struct DNSServerInfo: Identifiable, Equatable {
    let id: String  // the address itself
    let address: String
    let provider: DNSProvider

    init(address: String) {
        self.id = address
        self.address = address
        self.provider = DNSProvider.identify(address)
    }
}

// MARK: - DNS Status

enum DNSStatus: Equatable {
    case safe       // all servers are known-safe providers
    case warning    // mix of known + unknown
    case unsafe     // all unknown
    case unknown    // haven't checked yet

    var label: String {
        switch self {
        case .safe:    return "Secure DNS"
        case .warning: return "Mixed DNS"
        case .unsafe:  return "Unsafe DNS"
        case .unknown: return "Checking..."
        }
    }

    var icon: String {
        switch self {
        case .safe:    return "checkmark.shield.fill"
        case .warning: return "exclamationmark.shield.fill"
        case .unsafe:  return "xmark.shield.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

// MARK: - DNS Change Event

struct DNSChangeEvent: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let previousServers: [String]
    let newServers: [String]
    let wasUnsafe: Bool

    var timeFormatted: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: timestamp)
    }

    static func == (lhs: DNSChangeEvent, rhs: DNSChangeEvent) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - C callback for SCDynamicStore

private func dnsChangeCallback(
    store: SCDynamicStore,
    changedKeys: CFArray,
    info: UnsafeMutableRawPointer?
) {
    guard let info else { return }
    let monitor = Unmanaged<DNSMonitorBridge>.fromOpaque(info).takeUnretainedValue()
    monitor.notifyChange()
}

/// Bridge object to handle the C callback and dispatch to @MainActor DNSMonitor.
private final class DNSMonitorBridge: @unchecked Sendable {
    weak var monitor: DNSMonitor?

    func notifyChange() {
        let m = monitor
        Task { @MainActor in
            m?.handleDNSChange()
        }
    }
}

// MARK: - DNS Monitor

@MainActor
final class DNSMonitor: ObservableObject {
    @Published var servers: [DNSServerInfo] = []
    @Published var status: DNSStatus = .unknown
    @Published var events: [DNSChangeEvent] = []

    nonisolated(unsafe) private var store: SCDynamicStore?
    nonisolated(unsafe) private var runLoopSource: CFRunLoopSource?
    private let bridge = DNSMonitorBridge()

    /// Keep track of previous server list to detect changes.
    private var previousAddresses: [String] = []

    init() {
        bridge.monitor = self
        fetchCurrentDNS()
        startWatching()
    }

    nonisolated deinit {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    // MARK: - Read DNS

    func fetchCurrentDNS() {
        let newServers = Self.readDNSServers()
        let newAddresses = newServers.map(\.address)

        // Detect change
        if !previousAddresses.isEmpty && newAddresses != previousAddresses {
            let hasUnsafe = newServers.contains { !$0.provider.isSafe }
            let event = DNSChangeEvent(
                timestamp: Date(),
                previousServers: previousAddresses,
                newServers: newAddresses,
                wasUnsafe: hasUnsafe
            )
            events.insert(event, at: 0)
            if events.count > 30 { events = Array(events.prefix(30)) }

            if hasUnsafe {
                sendNotification(
                    title: "DNS Changed to Unknown Server",
                    body: "DNS now: \(newAddresses.joined(separator: ", ")) — was: \(previousAddresses.joined(separator: ", "))"
                )
            }
        }

        previousAddresses = newAddresses
        servers = newServers
        status = computeStatus(newServers)
    }

    func handleDNSChange() {
        fetchCurrentDNS()
    }

    private func computeStatus(_ servers: [DNSServerInfo]) -> DNSStatus {
        guard !servers.isEmpty else { return .unknown }
        let safeCount = servers.filter { $0.provider.isSafe }.count
        if safeCount == servers.count { return .safe }
        if safeCount == 0 { return .unsafe }
        return .warning
    }

    // MARK: - Watch for changes (SCDynamicStore)

    private func startWatching() {
        let bridgePtr = Unmanaged.passUnretained(bridge).toOpaque()

        var ctx = SCDynamicStoreContext(
            version: 0,
            info: bridgePtr,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        guard let dynStore = SCDynamicStoreCreate(
            nil,
            "keepMacClear.dns" as CFString,
            dnsChangeCallback,
            &ctx
        ) else { return }

        store = dynStore

        // Watch global DNS key and per-service DNS keys
        let watchKeys = ["State:/Network/Global/DNS"] as CFArray
        let watchPatterns = ["State:/Network/Service/.*/DNS"] as CFArray
        SCDynamicStoreSetNotificationKeys(dynStore, watchKeys, watchPatterns)

        if let source = SCDynamicStoreCreateRunLoopSource(nil, dynStore, 0) {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    // MARK: - Read DNS servers via SystemConfiguration

    nonisolated static func readDNSServers() -> [DNSServerInfo] {
        var ctx = SCDynamicStoreContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        guard let store = SCDynamicStoreCreate(nil, "keepMacClear.dns.read" as CFString, nil, &ctx) else {
            return []
        }

        let key = "State:/Network/Global/DNS" as CFString
        guard let dict = SCDynamicStoreCopyValue(store, key) as? [String: Any],
              let addresses = dict["ServerAddresses"] as? [String]
        else { return [] }

        // Deduplicate while preserving order
        var seen: Set<String> = []
        var result: [DNSServerInfo] = []
        for addr in addresses {
            guard !seen.contains(addr) else { continue }
            seen.insert(addr)
            result.append(DNSServerInfo(address: addr))
        }
        return result
    }

    // MARK: - Notification

    private func sendNotification(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .defaultCritical
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "dns-\(UUID().uuidString)", content: content, trigger: nil)
        )
    }

    func clearEvents() { events.removeAll() }
}
