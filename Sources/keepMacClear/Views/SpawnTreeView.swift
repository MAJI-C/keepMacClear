import SwiftUI

struct SpawnTreeView: View {
    @EnvironmentObject var spawnMonitor: ProcessSpawnMonitor
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            // Tab picker
            Picker("", selection: $selectedTab) {
                Text("Event Log").tag(0)
                Text("Live Tree").tag(1)
                Text("Block Rules").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            switch selectedTab {
            case 0:  eventLogTab
            case 1:  liveTreeTab
            case 2:  blockRulesTab
            default: EmptyView()
            }

            Divider()
            footer
        }
        .frame(width: 440, height: 540)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear { spawnMonitor.refreshProcessTree() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundColor(.red)
            Text("Process Spawn Monitor")
                .font(.headline)
            Spacer()
            if !spawnMonitor.events.isEmpty {
                Text("\(spawnMonitor.events.count) events")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.red, in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: - Tab 1: Event Log (Table)

    private var eventLogTab: some View {
        ScrollView(showsIndicators: false) {
            if spawnMonitor.events.isEmpty {
                emptyState(
                    icon: "checkmark.shield",
                    title: "No suspicious spawns detected",
                    subtitle: "Events will appear here when a monitored app spawns an unexpected process."
                )
            } else {
                // Table header
                VStack(spacing: 0) {
                    tableHeader
                    ForEach(Array(spawnMonitor.events.enumerated()), id: \.element.id) { index, event in
                        eventRow(event, isEven: index % 2 == 0)
                    }
                }
            }
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 0) {
            Text("Time")
                .frame(width: 55, alignment: .leading)
            Text("Parent")
                .frame(width: 100, alignment: .leading)
            Text("")
                .frame(width: 20)
            Text("Child")
                .frame(width: 80, alignment: .leading)
            Text("Status")
                .frame(width: 65, alignment: .center)
            Spacer()
            Text("Actions")
                .frame(width: 80, alignment: .trailing)
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundColor(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func eventRow(_ event: SuspiciousSpawnEvent, isEven: Bool) -> some View {
        HStack(spacing: 0) {
            Text(event.timeFormatted)
                .font(.system(size: 10, design: .monospaced))
                .frame(width: 55, alignment: .leading)

            Text(event.parentName)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .frame(width: 100, alignment: .leading)

            Image(systemName: "arrow.right")
                .font(.system(size: 8))
                .foregroundColor(.secondary)
                .frame(width: 20)

            Text(event.childName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(event.wasBlocked ? .orange : .red)
                .lineLimit(1)
                .frame(width: 80, alignment: .leading)

            // Status badge
            Group {
                if event.wasBlocked {
                    Text("BLOCKED")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.orange, in: Capsule())
                } else {
                    Text("ALERT")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.red, in: Capsule())
                }
            }
            .frame(width: 65, alignment: .center)

            Spacer()

            // Action buttons
            HStack(spacing: 4) {
                if !event.wasBlocked {
                    // Kill child
                    Button {
                        MemoryCleaner.shared.killProcess(pid: event.childPid)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("Kill \(event.childName)")

                    // Block this pair
                    if !spawnMonitor.isBlocked(parentName: event.parentName, childName: event.childName) {
                        Button {
                            spawnMonitor.blockEvent(event)
                        } label: {
                            Image(systemName: "shield.slash.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                        }
                        .buttonStyle(.borderless)
                        .help("Block \(event.parentName) from spawning \(event.childName)")
                    } else {
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                            .help("Already blocked")
                    }
                }

                // Dismiss
                Button {
                    spawnMonitor.dismissEvent(event)
                } label: {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Dismiss")
            }
            .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isEven ? Color.clear : Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Tab 2: Live Tree

    private var liveTreeTab: some View {
        ScrollView(showsIndicators: false) {
            if spawnMonitor.processTree.isEmpty {
                emptyState(
                    icon: "tree",
                    title: "No processes with children found",
                    subtitle: "Processes that spawn child processes will appear here."
                )
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(spawnMonitor.processTree.count) apps with child processes")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 6)

                    ForEach(spawnMonitor.processTree) { parent in
                        treeParentRow(parent)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
        .onAppear { spawnMonitor.refreshProcessTree() }
    }

    private func isMonitoredApp(_ name: String) -> Bool {
        spawnMonitor.isMonitoredParent(name)
    }

    private func treeParentRow(_ node: ProcessTreeNode) -> some View {
        let monitored = isMonitoredApp(node.name)
        let hasSuspiciousChild = node.children.contains { $0.isSuspicious }

        return VStack(alignment: .leading, spacing: 0) {
            // Parent row
            HStack(spacing: 6) {
                Image(systemName: monitored ? "shield.lefthalf.filled" : "app.fill")
                    .font(.system(size: 11))
                    .foregroundColor(monitored ? .orange : .accentColor)
                Text(node.name)
                    .font(.system(size: 11, weight: .semibold))
                Text("PID \(node.pid)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                if monitored {
                    Text("WATCHED")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange, in: Capsule())
                }
                Spacer()
                Text("\(node.children.count)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .background(
                (hasSuspiciousChild ? Color.red.opacity(0.08) : Color(NSColor.controlBackgroundColor)),
                in: RoundedRectangle(cornerRadius: 5)
            )

            // Children
            if !node.children.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(node.children) { child in
                        treeChildRow(child, parentName: node.name)
                    }
                }
                .padding(.leading, 20)
            }
        }
        .padding(.bottom, 8)
    }

    private func treeChildRow(_ child: ProcessTreeNode, parentName: String) -> some View {
        HStack(spacing: 6) {
            // Tree branch line
            HStack(spacing: 2) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 1, height: 20)
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 1)
            }

            Circle()
                .fill(child.isSuspicious ? Color.red : Color.green)
                .frame(width: 6, height: 6)

            Text(child.name)
                .font(.system(size: 10, weight: child.isSuspicious ? .semibold : .regular))
                .foregroundColor(child.isSuspicious ? .red : .primary)

            Text("PID \(child.pid)")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.secondary)

            Spacer()

            if child.isSuspicious {
                HStack(spacing: 4) {
                    Button {
                        kill(child.pid, SIGKILL)
                        spawnMonitor.refreshProcessTree()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("Kill process")

                    if !spawnMonitor.isBlocked(parentName: parentName, childName: child.name) {
                        Button {
                            spawnMonitor.blockPair(parentName: parentName, childName: child.name)
                        } label: {
                            Image(systemName: "shield.slash.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.orange)
                        }
                        .buttonStyle(.borderless)
                        .help("Auto-block this spawn pair")
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - Tab 3: Block Rules

    private var blockRulesTab: some View {
        ScrollView(showsIndicators: false) {
            if spawnMonitor.blockedPairs.isEmpty {
                emptyState(
                    icon: "shield.slash",
                    title: "No block rules set",
                    subtitle: "When you block a parent→child pair, it will appear here. Blocked spawns are auto-killed instantly."
                )
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    // Header
                    HStack(spacing: 0) {
                        Text("Parent")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("")
                            .frame(width: 24)
                        Text("Child")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("")
                            .frame(width: 40)
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)

                    ForEach(Array(spawnMonitor.blockedPairs.sorted()), id: \.self) { key in
                        blockRuleRow(key)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
    }

    private func blockRuleRow(_ key: String) -> some View {
        let parts = key.split(separator: ">", maxSplits: 1)
        let parent = parts.count > 0 ? String(parts[0].dropLast()) : key  // drop trailing "-"
        let child = parts.count > 1 ? String(parts[1]) : "?"

        return HStack(spacing: 0) {
            Image(systemName: "shield.slash.fill")
                .font(.system(size: 10))
                .foregroundColor(.orange)
                .padding(.trailing, 6)

            Text(parent)
                .font(.system(size: 10, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.right")
                .font(.system(size: 8))
                .foregroundColor(.secondary)
                .frame(width: 24)

            Text(child)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                spawnMonitor.unblockKey(key)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Remove block rule")
            .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if selectedTab == 0 && !spawnMonitor.events.isEmpty {
                Button {
                    spawnMonitor.clearEvents()
                } label: {
                    Label("Clear All", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if selectedTab == 1 {
                Button {
                    spawnMonitor.refreshProcessTree()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if selectedTab == 2 && !spawnMonitor.blockedPairs.isEmpty {
                Button {
                    spawnMonitor.blockedPairs.removeAll()
                } label: {
                    Label("Clear All Rules", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Spacer()

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: - Empty State

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.5))
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}
