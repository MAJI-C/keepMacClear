import Foundation
import SwiftUI

// MARK: - Memory Pressure

enum MemoryPressureLevel {
    case normal, warning, critical

    var color: Color {
        switch self {
        case .normal:   return Color.green
        case .warning:  return Color.yellow
        case .critical: return Color.red
        }
    }

    var nsColor: NSColor {
        switch self {
        case .normal:   return .systemGreen
        case .warning:  return .systemYellow
        case .critical: return .systemRed
        }
    }

    var label: String {
        switch self {
        case .normal:   return "Normal"
        case .warning:  return "Warning"
        case .critical: return "Critical"
        }
    }

    var icon: String {
        switch self {
        case .normal:   return "checkmark.circle.fill"
        case .warning:  return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }
}

// MARK: - System Memory

struct SystemMemoryInfo {
    let total: UInt64
    let active: UInt64      // in use by apps
    let wired: UInt64       // locked by kernel / drivers
    let compressed: UInt64  // compressed by macOS memory compressor
    let inactive: UInt64    // recently used, reclaimable
    let free: UInt64        // truly free

    var used: UInt64 { active + wired + compressed }

    var usagePercent: Double {
        guard total > 0 else { return 0 }
        return Double(used) / Double(total) * 100
    }

    var pressureLevel: MemoryPressureLevel {
        switch usagePercent {
        case 90...: return .critical
        case 75...: return .warning
        default:    return .normal
        }
    }

    // Fractions for the breakdown bar
    var activeFraction:     Double { guard total > 0 else { return 0 }; return Double(active)     / Double(total) }
    var wiredFraction:      Double { guard total > 0 else { return 0 }; return Double(wired)      / Double(total) }
    var compressedFraction: Double { guard total > 0 else { return 0 }; return Double(compressed) / Double(total) }
    var inactiveFraction:   Double { guard total > 0 else { return 0 }; return Double(inactive)   / Double(total) }

    static var empty: SystemMemoryInfo {
        SystemMemoryInfo(total: 0, active: 0, wired: 0, compressed: 0, inactive: 0, free: 0)
    }
}

// MARK: - Shared formatter (avoids allocating a new one per call)

private let _byteFormatter: ByteCountFormatter = {
    let f = ByteCountFormatter()
    f.countStyle = .memory
    f.allowedUnits = [.useAll]
    return f
}()

// MARK: - Process Memory

/// Uses `pid` as the stable `Identifiable` ID so SwiftUI can diff across refreshes.
struct ProcessMemoryInfo: Identifiable, Equatable {
    var id: Int32 { pid }   // stable — pid doesn't change while the process lives
    let pid: Int32
    let name: String
    let memoryBytes: UInt64

    var memoryFormatted: String {
        _byteFormatter.string(fromByteCount: Int64(memoryBytes))
    }

    func fraction(of total: UInt64) -> Double {
        guard total > 0 else { return 0 }
        return min(1.0, Double(memoryBytes) / Double(total))
    }
}

// MARK: - Browser Group

struct BrowserGroup: Identifiable, Equatable {
    var id: String { name }  // stable — browser name is constant
    let name: String
    /// Pre-sorted descending by memory so views never sort inside `body`.
    let processes: [ProcessMemoryInfo]
    let totalMemory: UInt64

    var processCount: Int { processes.count }

    var memoryFormatted: String {
        _byteFormatter.string(fromByteCount: Int64(totalMemory))
    }

    var browserIcon: String {
        switch name {
        case "Safari":         return "safari.fill"
        case "Google Chrome":  return "globe"
        case "Firefox":        return "flame.fill"
        case "Microsoft Edge": return "e.circle.fill"
        case "Arc":            return "circle.lefthalf.filled"
        case "Brave Browser":  return "shield.fill"
        default:               return "globe"
        }
    }
}

// MARK: - System Memory (Equatable so SwiftUI skips renders when unchanged)

extension SystemMemoryInfo: Equatable {}

// MARK: - Formatting Helpers

func formatBytes(_ bytes: UInt64) -> String {
    _byteFormatter.string(fromByteCount: Int64(bytes))
}
