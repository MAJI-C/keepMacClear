import SwiftUI

struct PortMonitorView: View {
    @EnvironmentObject var portMonitor: PortMonitor
    @Environment(\.dismiss) private var dismiss
    @State private var closingPort: UInt16? = nil
    @State private var closeResult: String? = nil

    private var openPorts: [PortStatus] {
        portMonitor.statuses.filter(\.isOpen)
    }

    private var closedPorts: [PortStatus] {
        portMonitor.statuses.filter { !$0.isOpen }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    legendBox

                    if !openPorts.isEmpty {
                        openSection
                    }

                    portRulesSection

                    rulesFileHint
                }
                .padding(14)
            }
            Divider()
            footer
        }
        .frame(width: 420, height: 540)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "network.badge.shield.half.filled")
                .foregroundColor(.accentColor)
            Text("Port Monitor")
                .font(.headline)
            Spacer()

            if openPorts.isEmpty {
                Label("All Secure", systemImage: "lock.shield.fill")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.15), in: Capsule())
            } else {
                Label("\(openPorts.count) Exposed", systemImage: "exclamationmark.shield.fill")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.red, in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: - Legend

    private var legendBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text("Port is open (exposed)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 8, height: 8)
                    Text("Port is closed (safe)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "switch.2")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text("ON = enforce closed, OFF = ignore")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Open Ports (needs attention)

    private var openSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Exposed Ports — Action Required", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.bold))
                .foregroundColor(.red)

            ForEach(openPorts) { status in
                HStack(spacing: 8) {
                    Circle().fill(.red).frame(width: 10, height: 10)

                    Text("\(status.rule.port)")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .frame(width: 50, alignment: .trailing)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(status.rule.name)
                                .font(.caption.weight(.semibold))
                            severityBadge(status.rule.severity)
                        }
                        Text(status.rule.description)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        closePort(status.rule.port)
                    } label: {
                        if closingPort == status.rule.port {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Close")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.red, in: Capsule())
                        }
                    }
                    .buttonStyle(.borderless)
                    .help("Kill the process listening on port \(status.rule.port)")
                }
                .padding(6)
                .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }

            if let closeResult {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 10))
                    Text(closeResult)
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                }
            }
        }
        .padding(10)
        .background(Color.red.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - All port rules

    private var portRulesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Port Rules", systemImage: "checklist")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            ForEach(portMonitor.rules) { rule in
                portRuleRow(rule)
            }
        }
    }

    private func portRuleRow(_ rule: PortRule) -> some View {
        let status = portMonitor.statuses.first { $0.rule.port == rule.port }
        let isOpen = status?.isOpen ?? false

        return HStack(spacing: 8) {
            // Enforce toggle
            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { _ in portMonitor.toggleRule(port: rule.port) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()

            // Status light
            Circle()
                .fill(statusColor(enabled: rule.enabled, isOpen: isOpen))
                .frame(width: 8, height: 8)

            Text("\(rule.port)")
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .frame(width: 45, alignment: .trailing)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(rule.name)
                        .font(.caption.weight(.medium))
                    severityBadge(rule.severity)
                }
                Text(rule.description)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Status label
            if rule.enabled {
                if isOpen {
                    Text("OPEN")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.red, in: Capsule())
                } else {
                    Text("CLOSED")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.green)
                }
            } else {
                Text("IGNORED")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.5))
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .opacity(rule.enabled ? 1 : 0.5)
    }

    /// Green if closed (safe), red if open (exposed), gray if not monitored.
    private func statusColor(enabled: Bool, isOpen: Bool) -> Color {
        guard enabled else { return Color(NSColor.tertiaryLabelColor) }
        return isOpen ? .red : .green
    }

    // MARK: - Rules file hint

    private var rulesFileHint: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider().padding(.vertical, 2)
            Label("Edit rules without rebuilding", systemImage: "doc.text")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            Text("~/Library/Application Support/keepMacClear/port-rules.json")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
                .textSelection(.enabled)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                portMonitor.reloadRules()
            } label: {
                Label("Reload Rules", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: portMonitor.rulesFileURL.deletingLastPathComponent().path)
            } label: {
                Label("Open Folder", systemImage: "folder")
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

    // MARK: - Actions

    private func closePort(_ port: UInt16) {
        closingPort = port
        closeResult = nil
        Task {
            let result = await portMonitor.closePort(port)
            closingPort = nil
            closeResult = result.message
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            closeResult = nil
        }
    }

    // MARK: - Helpers

    private func severityColor(_ severity: PortRule.Severity) -> Color {
        switch severity {
        case .critical: return .red
        case .high:     return .orange
        case .medium:   return .yellow
        case .low:      return .green
        }
    }

    private func severityBadge(_ severity: PortRule.Severity) -> some View {
        Text(severity.label)
            .font(.system(size: 8, weight: .semibold))
            .foregroundColor(severityColor(severity))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(severityColor(severity).opacity(0.15), in: Capsule())
    }
}
