import SwiftUI

struct ProcessRow: View {
    let process: ProcessMemoryInfo
    let totalMemory: UInt64

    @State private var hovered = false
    @State private var suspended = false

    private var fraction: Double {
        guard totalMemory > 0 else { return 0 }
        return min(1, Double(process.memoryBytes) / Double(totalMemory))
    }

    private var barColor: Color {
        switch fraction {
        case 0.15...: return .red.opacity(0.8)
        case 0.08...: return .orange.opacity(0.8)
        default:      return .accentColor.opacity(0.6)
        }
    }

    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text(process.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text(process.memoryFormatted)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)

                if hovered {
                    actionButtons
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.1))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor)
                        .frame(width: geo.size.width * fraction)
                        .animation(.easeInOut(duration: 0.4), value: fraction)
                }
            }
            .frame(height: 3)
        }
        .padding(.vertical, 3)
        .onHover { hovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: hovered)
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 4) {
            Button {
                withAnimation {
                    suspended.toggle()
                    if suspended {
                        MemoryCleaner.shared.suspendProcess(pid: process.pid)
                    } else {
                        MemoryCleaner.shared.resumeProcess(pid: process.pid)
                    }
                }
            } label: {
                Image(systemName: suspended ? "play.circle" : "pause.circle")
                    .foregroundColor(suspended ? .green : .yellow)
            }
            .buttonStyle(.borderless)
            .help(suspended ? "Resume process" : "Suspend process (freeze memory growth)")

            Button {
                MemoryCleaner.shared.killProcess(pid: process.pid)
            } label: {
                Image(systemName: "xmark.circle")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
            .help("Terminate process")
        }
        .font(.system(size: 13))
    }
}
