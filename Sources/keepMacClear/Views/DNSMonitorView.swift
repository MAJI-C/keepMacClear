import SwiftUI

struct DNSMonitorView: View {
    @EnvironmentObject var dnsMonitor: DNSMonitor
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    statusBanner
                    currentDNSSection
                    if !dnsMonitor.events.isEmpty {
                        changeHistorySection
                    }
                    recommendationSection
                }
                .padding(14)
            }
            Divider()
            footer
        }
        .frame(width: 420, height: 480)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundColor(.accentColor)
            Text("DNS Monitor")
                .font(.headline)
            Spacer()

            Label(dnsMonitor.status.label, systemImage: dnsMonitor.status.icon)
                .font(.caption.weight(.bold))
                .foregroundColor(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(statusColor.opacity(0.15), in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: - Status Banner

    private var statusBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: dnsMonitor.status.icon)
                .font(.system(size: 24))
                .foregroundColor(statusColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.caption.weight(.bold))
                Text(statusSubtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(statusColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private var statusTitle: String {
        switch dnsMonitor.status {
        case .safe:    return "DNS is secure"
        case .warning: return "DNS has unknown servers"
        case .unsafe:  return "DNS is using unknown servers"
        case .unknown: return "Checking DNS configuration..."
        }
    }

    private var statusSubtitle: String {
        switch dnsMonitor.status {
        case .safe:    return "All DNS servers belong to trusted providers."
        case .warning: return "Some DNS servers are unrecognized — could be your ISP or something malicious."
        case .unsafe:  return "No recognized DNS providers found. Your DNS may have been hijacked."
        case .unknown: return "Reading DNS configuration..."
        }
    }

    // MARK: - Current DNS Servers

    private var currentDNSSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Active DNS Servers", systemImage: "server.rack")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            if dnsMonitor.servers.isEmpty {
                Text("No DNS servers found")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(8)
            } else {
                ForEach(dnsMonitor.servers) { server in
                    dnsServerRow(server)
                }
            }
        }
    }

    private func dnsServerRow(_ server: DNSServerInfo) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(server.provider.isSafe ? Color.green : Color.red)
                .frame(width: 10, height: 10)

            Text(server.address)
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .frame(minWidth: 120, alignment: .leading)

            Image(systemName: server.provider.icon)
                .font(.system(size: 12))
                .foregroundColor(server.provider.isSafe ? .green : .red)

            Text(server.provider.rawValue)
                .font(.caption.weight(.medium))
                .foregroundColor(server.provider.isSafe ? .primary : .red)

            Spacer()

            if server.provider.isSafe {
                Text("TRUSTED")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)
            } else {
                Text("UNKNOWN")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.red, in: Capsule())
            }
        }
        .padding(8)
        .background(
            (server.provider.isSafe ? Color.green : Color.red).opacity(0.06),
            in: RoundedRectangle(cornerRadius: 6)
        )
    }

    // MARK: - Change History

    private var changeHistorySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Change History", systemImage: "clock.arrow.circlepath")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    dnsMonitor.clearEvents()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Clear history")
            }

            ForEach(dnsMonitor.events.prefix(10)) { event in
                changeEventRow(event)
            }
        }
    }

    private func changeEventRow(_ event: DNSChangeEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: event.wasUnsafe ? "exclamationmark.triangle.fill" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 10))
                    .foregroundColor(event.wasUnsafe ? .red : .orange)

                Text(event.timeFormatted)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)

                if event.wasUnsafe {
                    Text("SUSPICIOUS")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.red, in: Capsule())
                }
                Spacer()
            }

            HStack(spacing: 4) {
                Text(event.previousServers.joined(separator: ", "))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Image(systemName: "arrow.right")
                    .font(.system(size: 7))
                    .foregroundColor(.secondary)
                Text(event.newServers.joined(separator: ", "))
                    .font(.system(size: 9, design: .monospaced).weight(.medium))
                    .foregroundColor(event.wasUnsafe ? .red : .primary)
                    .lineLimit(1)
            }
        }
        .padding(6)
        .background(
            (event.wasUnsafe ? Color.red : Color.orange).opacity(0.06),
            in: RoundedRectangle(cornerRadius: 5)
        )
    }

    // MARK: - Recommendation

    private var recommendationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().padding(.vertical, 2)
            Label("Recommended DNS Servers", systemImage: "star.fill")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cloudflare")
                        .font(.caption.weight(.semibold))
                    Text("1.1.1.1 / 1.0.0.1")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Google")
                        .font(.caption.weight(.semibold))
                    Text("8.8.8.8 / 8.8.4.4")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quad9")
                        .font(.caption.weight(.semibold))
                    Text("9.9.9.9")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }

            Text("Set in System Settings → Network → Wi-Fi → Details → DNS")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                dnsMonitor.fetchCurrentDNS()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch dnsMonitor.status {
        case .safe:    return .green
        case .warning: return .orange
        case .unsafe:  return .red
        case .unknown: return .secondary
        }
    }
}
