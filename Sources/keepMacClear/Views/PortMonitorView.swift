import SwiftUI

struct PortMonitorView: View {
    @EnvironmentObject var portMonitor: PortMonitor
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    openPortsSummary
                    portList
                    rulesFileHint
                }
                .padding(14)
            }
            Divider()
            footer
        }
        .frame(width: 400, height: 520)
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

            let openCount = portMonitor.statuses.filter(\.isOpen).count
            if openCount > 0 {
                Text("\(openCount) open")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.red, in: Capsule())
            } else {
                Text("All clear")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.15), in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: - Summary

    private var openPortsSummary: some View {
        Group {
            let openPorts = portMonitor.statuses.filter(\.isOpen)
            if !openPorts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(openPorts) { status in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(severityColor(status.rule.severity))
                                .frame(width: 8, height: 8)
                            Text("\(status.rule.port)")
                                .font(.system(.caption, design: .monospaced).weight(.bold))
                                .frame(width: 50, alignment: .trailing)
                            Text(status.rule.name)
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Text("OPEN")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(severityColor(status.rule.severity), in: Capsule())
                        }
                        .padding(6)
                        .background(severityColor(status.rule.severity).opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }

    // MARK: - Port list with toggles

    private var portList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Monitored Ports", systemImage: "checklist")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.bottom, 4)

            ForEach(portMonitor.rules) { rule in
                portRow(rule)
            }
        }
    }

    private func portRow(_ rule: PortRule) -> some View {
        let status = portMonitor.statuses.first { $0.rule.port == rule.port }
        let isOpen = status?.isOpen ?? false

        return HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { _ in portMonitor.toggleRule(port: rule.port) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()

            Circle()
                .fill(isOpen ? severityColor(rule.severity) : Color(NSColor.tertiaryLabelColor))
                .frame(width: 6, height: 6)

            Text("\(rule.port)")
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .frame(width: 45, alignment: .trailing)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(rule.name)
                        .font(.caption.weight(.semibold))
                    severityBadge(rule.severity)
                    if isOpen {
                        Text("OPEN")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.red)
                    }
                }
                Text(rule.description)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            isOpen
                ? severityColor(rule.severity).opacity(0.06)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 5)
        )
    }

    // MARK: - Rules file hint

    private var rulesFileHint: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider().padding(.vertical, 4)
            Label("Edit rules without rebuilding", systemImage: "doc.text")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            Text("~/Library/Application Support/keepMacClear/port-rules.json")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
                .textSelection(.enabled)
            Text("Add or remove entries, change severity, toggle enabled — then tap Reload.")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
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
            .help("Reload port-rules.json from disk")

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
