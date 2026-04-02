import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var monitor: MemoryMonitor
    @State private var showSettings = false
    @State private var cleanState: CleanState = .idle

    enum CleanState { case idle, running, done }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
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
        .frame(width: 330, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(monitor)
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

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Toggle("Auto-clean", isOn: $monitor.isAutoCleanEnabled)
                .toggleStyle(.switch)
                .controlSize(.mini)
            Text("Auto-clean")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

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
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { cleanState = .idle }
        monitor.refresh()
    }

    private func fullClean() {
        cleanState = .running
        MemoryCleaner.shared.fullClean { _ in
            cleanState = .done
            monitor.refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { cleanState = .idle }
        }
    }
}
