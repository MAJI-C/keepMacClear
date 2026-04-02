import SwiftUI

struct SpawnAlertRow: View {
    let event: SuspiciousSpawnEvent
    var onDismiss: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundColor(.red)
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
                        .foregroundColor(.red)
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
                        Button {
                            MemoryCleaner.shared.killProcess(pid: event.childPid)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                        .help("Kill \(event.childName)")

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
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .onHover { isHovering = $0 }
    }
}
