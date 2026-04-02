import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var monitor: MemoryMonitor
    @EnvironmentObject var spawnMonitor: ProcessSpawnMonitor
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.title2.weight(.bold))

            GroupBox("Alerts") {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Notify when RAM exceeds")
                            Spacer()
                            Text("\(Int(monitor.alertThresholdPercent))%")
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $monitor.alertThresholdPercent, in: 50...98, step: 5)
                    }
                }
                .padding(6)
            }

            GroupBox("Process Limiting") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Auto-kill processes that exceed limit", isOn: $monitor.autoKillEnabled)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Single process limit")
                            Spacer()
                            Text(monitor.processLimitMB == 0 ? "Off" : "\(Int(monitor.processLimitMB)) MB")
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $monitor.processLimitMB, in: 0...30720, step: 256)
                        Text("Processes using more than this will trigger an alert (or be auto-killed if enabled).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(6)
            }

            GroupBox("Spawn Detection") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Monitor suspicious process spawns", isOn: Binding(
                        get: { spawnMonitor.isEnabled },
                        set: { _ in spawnMonitor.toggleEnabled() }
                    ))
                    Text("Alerts when apps like Office, Mail, or Preview spawn shells, scripts, or network tools — a common sign of exploitation.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(6)
            }

            GroupBox("About") {
                VStack(alignment: .leading, spacing: 6) {
                    infoRow(label: "Physical RAM",
                            value: formatBytes(ProcessInfo.processInfo.physicalMemory))
                    infoRow(label: "CPU Cores",
                            value: "\(ProcessInfo.processInfo.processorCount)")
                    infoRow(label: "macOS",
                            value: ProcessInfo.processInfo.operatingSystemVersionString)
                }
                .padding(6)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360, height: 540)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
        .font(.caption)
    }
}
