import Foundation
import AppKit

@MainActor
final class MemoryCleaner {
    static let shared = MemoryCleaner()
    private init() {}

    // MARK: - System Cache Purge (requires admin password via system dialog)

    /// Runs `purge` via osascript — triggers macOS native admin password prompt.
    func purgeSystemCache(completion: (@Sendable (Bool) -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            let src = "do shell script \"purge\" with administrator privileges"
            guard let script = NSAppleScript(source: src) else {
                DispatchQueue.main.async {
                    completion?(false)
                }
                return
            }
            var err: NSDictionary?
            script.executeAndReturnError(&err)
            let ok = (err == nil)
            DispatchQueue.main.async {
                completion?(ok)
            }
        }
    }

    // MARK: - Allocator Pressure Relief (no privileges needed)

    /// Asks the default malloc zone to release unused free pages back to the OS.
    func freeAllocatorMemory() {
        malloc_zone_pressure_relief(nil, 0)
    }

    // MARK: - Process Control

    /// Sends SIGTERM then SIGKILL after 3 s.
    func killProcess(pid: Int32) {
        kill(pid, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            kill(pid, SIGKILL)
        }
    }

    /// Pauses a process (frees CPU; memory stays allocated but won't grow).
    func suspendProcess(pid: Int32) {
        kill(pid, SIGSTOP)
    }

    /// Resumes a previously suspended process.
    func resumeProcess(pid: Int32) {
        kill(pid, SIGCONT)
    }

    // MARK: - Convenience

    /// Quick clean: allocator relief (instant, no prompt).
    /// Full clean: purge disk + file cache (requires admin password).
    func quickClean() {
        freeAllocatorMemory()
    }

    func fullClean(completion: (@Sendable (Bool) -> Void)? = nil) {
        freeAllocatorMemory()
        purgeSystemCache(completion: completion)
    }
}
