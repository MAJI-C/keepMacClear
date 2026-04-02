import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var monitor: MemoryMonitor
    @EnvironmentObject var spawnMonitor: ProcessSpawnMonitor
    @EnvironmentObject var portMonitor: PortMonitor
    @EnvironmentObject var dnsMonitor: DNSMonitor
    @State private var showSettings = false
    @State private var showPortMonitor = false
    @State private var showSpawnTree = false
    @State private var showDNSMonitor = false
    @State private var cleanState: CleanState = .idle

    enum CleanState { case idle, running, done }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if !spawnMonitor.events.isEmpty {
                        spawnAlertsSection
                    }
                    if dnsMonitor.status != .safe && dnsMonitor.status != .unknown {
                        dnsAlertSection
                    }
                    if !portMonitor.statuses.filter(\.isOpen).isEmpty {
                        openPortsSection
                    }
                    usageSection
                    if !monitor.browserGroups.isEmpty {
                        browsersSection
                    }
                    processesSection
                }
                .padding(14)
            }
            Divider()
            footer
        }
        .frame(width: 360, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(monitor)
                .environmentObject(spawnMonitor)
        }
        .sheet(isPresented: $showPortMonitor) {
            PortMonitorView()
                .environmentObject(portMonitor)
        }
        .sheet(isPresented: $showSpawnTree) {
            SpawnTreeView()
                .environmentObject(spawnMonitor)
        }
        .sheet(isPresented: $showDNSMonitor) {
            DNSMonitorView()
                .environmentObject(dnsMonitor)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "memorychip")
                .foregroundColor(.accentColor)
            Text("keepMacClear")
                .font(.headline)
            Spacer()
            Label(monitor.systemMemory.pressureLevel.label,
                  systemImage: monitor.systemMemory.pressureLevel.icon)
                .font(.caption.weight(.medium))
                .foregroundColor(monitor.systemMemory.pressureLevel.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    monitor.systemMemory.pressureLevel.color.opacity(0.15),
                    in: Capsule()
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: - Usage Overview

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "%.0f", monitor.systemMemory.usagePercent))
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundColor(monitor.systemMemory.pressureLevel.color)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.4), value: monitor.systemMemory.usagePercent)
                Text("%")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatBytes(monitor.systemMemory.used))
                        .font(.subheadline.weight(.medium))
                    Text("of \(formatBytes(monitor.systemMemory.total))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            MemoryBreakdownBar(memory: monitor.systemMemory)
                .frame(height: 10)

            // Legend
            HStack(spacing: 0) {
                legendItem(color: .blue,              label: "Active",     bytes: monitor.systemMemory.active)
                legendItem(color: .orange,            label: "Wired",      bytes: monitor.systemMemory.wired)
                legendItem(color: .purple,            label: "Compressed", bytes: monitor.systemMemory.compressed)
                legendItem(color: Color(NSColor.tertiaryLabelColor), label: "Inactive", bytes: monitor.systemMemory.inactive)
            }
        }
    }

    private func legendItem(color: Color, label: String, bytes: UInt64) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 7, height: 7)
            Text("\(label) \(formatBytes(bytes))")
                .foregroundColor(.secondary)
        }
        .font(.system(size: 8.5))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Browsers

    private var browsersSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionHeader("Browsers", icon: "globe")
            ForEach(monitor.browserGroups) { group in
                BrowserGroupRow(group: group, totalMemory: monitor.systemMemory.total)
            }
        }
    }

    // MARK: - Processes

    private var processesSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionHeader("Top Processes", icon: "list.number")
            ForEach(monitor.topProcesses.prefix(12)) { proc in
                ProcessRow(process: proc, totalMemory: monitor.systemMemory.total)
            }
        }
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
    }

    // MARK: - DNS Alert

    private var dnsAlertSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                sectionHeader("DNS Status", icon: "antenna.radiowaves.left.and.right")
                Spacer()
                Text(dnsMonitor.status.label)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(dnsMonitor.status == .unsafe ? Color.red : Color.orange, in: Capsule())
                Button { showDNSMonitor = true } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Open DNS monitor")
            }

            ForEach(dnsMonitor.servers.filter { !$0.provider.isSafe }) { server in
                HStack(spacing: 6) {
                    Circle().fill(.red).frame(width: 6, height: 6)
                    Text(server.address)
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                    Text(server.provider.rawValue)
                        .font(.caption)
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Open Ports

    private var openPortsSection: some View {
        let openPorts = portMonitor.statuses.filter(\.isOpen)
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                sectionHeader("Open Ports", icon: "network.badge.shield.half.filled")
                Spacer()
                Text("\(openPorts.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange, in: Capsule())
                Button { showPortMonitor = true } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Open port monitor")
            }
            ForEach(openPorts.prefix(5)) { status in
                HStack(spacing: 6) {
                    Circle()
                        .fill(portSeverityColor(status.rule.severity))
                        .frame(width: 6, height: 6)
                    Text("\(status.rule.port)")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                    Text(status.rule.name)
                        .font(.caption.weight(.medium))
                    Spacer()
                    Text(status.rule.severity.label)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(portSeverityColor(status.rule.severity))
                }
                .padding(.vertical, 2)
            }
            if openPorts.count > 5 {
                Text("+\(openPorts.count - 5) more")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func portSeverityColor(_ severity: PortRule.Severity) -> Color {
        switch severity {
        case .critical: return .red
        case .high:     return .orange
        case .medium:   return .yellow
        case .low:      return .green
        }
    }

    // MARK: - Spawn Alerts

    private var spawnAlertsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                sectionHeader("Spawn Alerts", icon: "exclamationmark.shield")
                Spacer()
                Text("\(spawnMonitor.events.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red, in: Capsule())
                Button { showSpawnTree = true } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Open spawn monitor")
                Button {
                    spawnMonitor.clearEvents()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Clear all spawn alerts")
            }

            ForEach(spawnMonitor.events.prefix(5)) { event in
                SpawnAlertRow(event: event, onDismiss: {
                    spawnMonitor.dismissEvent(event)
                }, onBlock: {
                    spawnMonitor.blockEvent(event)
                })
            }
            if spawnMonitor.events.count > 5 {
                Button { showSpawnTree = true } label: {
                    Text("View all \(spawnMonitor.events.count) events...")
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Toggle("", isOn: $monitor.isAutoCleanEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .accessibilityLabel("Auto-clean")
                Text("Auto-clean")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            Spacer(minLength: 4)

            // Quick clean (no prompt)
            Button(action: quickClean) {
                Label("Quick", systemImage: "bolt.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Free unused allocator memory instantly (no password needed)")

            // Full clean (sudo purge)
            Button(action: fullClean) {
                Group {
                    if cleanState == .running {
                        ProgressView().controlSize(.small)
                    } else if cleanState == .done {
                        Label("Done!", systemImage: "checkmark")
                    } else {
                        Label("Full Clean", systemImage: "wand.and.sparkles")
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(cleanState == .running)
            .help("Purge disk cache (requires admin password)")

            Button { showSpawnTree = true } label: {
                Image(systemName: "exclamationmark.shield")
            }
            .buttonStyle(.borderless)
            .help("Spawn Monitor")

            Button { showPortMonitor = true } label: {
                Image(systemName: "network.badge.shield.half.filled")
            }
            .buttonStyle(.borderless)
            .help("Port Monitor")

            Button { showDNSMonitor = true } label: {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundColor(dnsMonitor.status == .safe || dnsMonitor.status == .unknown ? .secondary : .red)
            }
            .buttonStyle(.borderless)
            .help("DNS Monitor")

            Button { showSettings = true } label: {
                Image(systemName: "gear")
            }
            .buttonStyle(.borderless)
            .help("Settings")

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Quit keepMacClear")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: - Actions

    private func quickClean() {
        MemoryCleaner.shared.quickClean()
        cleanState = .done
        Task {
            try? await Task.sleep(for: .seconds(2))
            cleanState = .idle
        }
        monitor.refresh()
    }

    private func fullClean() {
        cleanState = .running
        MemoryCleaner.shared.fullClean { _ in
            Task { @MainActor in
                cleanState = .done
                monitor.refresh()
                try? await Task.sleep(for: .seconds(2))
                cleanState = .idle
            }
        }
    }
}
