import SwiftUI

struct SpawnAlertRow: View {
    let event: SuspiciousSpawnEvent
    var onDismiss: () -> Void
    var onBlock: (() -> Void)? = nil

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: event.wasBlocked ? "shield.slash.fill" : "exclamationmark.shield.fill")
                .foregroundColor(event.wasBlocked ? .orange : .red)
                .font(.system(size: 12))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(event.parentName)
                        .font(.caption.weight(.semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                    Text(event.childName)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(event.wasBlocked ? .orange : .red)
                    if event.wasBlocked {
                        Text("BLOCKED")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange, in: Capsule())
                    }
                }
                Text(event.reason)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(event.timeFormatted)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)

                if isHovering {
                    HStack(spacing: 4) {
                        if !event.wasBlocked {
                            Button {
                                MemoryCleaner.shared.killProcess(pid: event.childPid)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.borderless)
                            .help("Kill \(event.childName)")

                            if let onBlock {
                                Button(action: onBlock) {
                                    Image(systemName: "shield.slash.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.orange)
                                }
                                .buttonStyle(.borderless)
                                .help("Block \(event.parentName) → \(event.childName)")
                            }
                        }

                        Button(action: onDismiss) {
                            Image(systemName: "eye.slash")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Dismiss alert")
                    }
                }
            }
        }
        .padding(6)
        .background(
            (event.wasBlocked ? Color.orange : Color.red).opacity(0.08),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .onHover { isHovering = $0 }
    }
}
