import SwiftUI

struct BrowserGroupRow: View {
    let group: BrowserGroup
    let totalMemory: UInt64

    @State private var expanded = false

    private var fraction: Double {
        guard totalMemory > 0 else { return 0 }
        return min(1, Double(group.totalMemory) / Double(totalMemory))
    }

    var body: some View {
        VStack(spacing: 4) {
            // Summary row
            HStack(spacing: 6) {
                Image(systemName: group.browserIcon)
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)
                    .frame(width: 14)

                Text(group.name)
                    .font(.system(size: 11, weight: .medium))
                Text("·  \(group.processCount) process\(group.processCount == 1 ? "" : "es")")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Text(group.memoryFormatted)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }

            // Combined bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.1))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(fraction > 0.2 ? Color.red.opacity(0.7) : Color.accentColor.opacity(0.5))
                        .frame(width: geo.size.width * fraction)
                        .animation(.easeInOut(duration: 0.4), value: fraction)
                }
            }
            .frame(height: 3)

            // Expanded sub-processes
            if expanded {
                VStack(spacing: 2) {
                    ForEach(group.processes) { proc in  // pre-sorted at model build time
                        HStack {
                            Text(proc.name)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Text(proc.memoryFormatted)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 20)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 3)
    }
}
