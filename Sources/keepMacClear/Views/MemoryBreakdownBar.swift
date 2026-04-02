import SwiftUI

/// Horizontal segmented bar showing active / wired / compressed / inactive / free.
struct MemoryBreakdownBar: View {
    let memory: SystemMemoryInfo

    private struct Segment: Identifiable {
        let label: String   // stable, human-readable key
        var id: String { label }
        let fraction: Double
        let color: Color
    }

    private var segments: [Segment] {
        [
            Segment(label: "Active",     fraction: memory.activeFraction,     color: .blue),
            Segment(label: "Wired",      fraction: memory.wiredFraction,      color: .orange),
            Segment(label: "Compressed", fraction: memory.compressedFraction, color: .purple),
            Segment(label: "Inactive",   fraction: memory.inactiveFraction,   color: Color(NSColor.quaternaryLabelColor)),
            // Free is the remainder
            Segment(
                label: "Free",
                fraction: max(
                    0,
                    1 - memory.activeFraction - memory.wiredFraction
                    - memory.compressedFraction - memory.inactiveFraction
                ),
                color: Color(NSColor.separatorColor).opacity(0.3)
            ),
        ]
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(segments) { seg in
                    if seg.fraction > 0 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(seg.color)
                            .frame(width: max(1, geo.size.width * seg.fraction))
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.2), lineWidth: 0.5))
    }
}
