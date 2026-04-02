import AppKit
import SwiftUI
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    let monitor = MemoryMonitor()
    let spawnMonitor = ProcessSpawnMonitor()
    let portMonitor = PortMonitor()
    private var iconUpdateTimer: Timer?

    // Cached once — font object is constant, no need to re-allocate every 2 s.
    private let statusBarFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestNotificationPermission()
        setupStatusBar()
        setupPopover()
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.action = #selector(togglePopover(_:))
            button.target = self
            updateStatusBarIcon()
        }

        iconUpdateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateStatusBarIcon()
        }
        RunLoop.main.add(iconUpdateTimer!, forMode: .common)
    }

    private func updateStatusBarIcon() {
        guard let button = statusItem.button else { return }
        let info = monitor.systemMemory
        let pct = info.usagePercent

        let nsColor: NSColor
        switch info.pressureLevel {
        case .normal:   nsColor = NSColor.systemGreen
        case .warning:  nsColor = NSColor.systemYellow
        case .critical: nsColor = NSColor.systemRed
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: statusBarFont,
            .foregroundColor: nsColor
        ]
        button.attributedTitle = NSAttributedString(
            string: String(format: "RAM %.0f%%", pct),
            attributes: attrs
        )
    }

    // MARK: - Popover

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 500)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: DashboardView()
                .environmentObject(monitor)
                .environmentObject(spawnMonitor)
                .environmentObject(portMonitor)
        )
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            popover.performClose(sender)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return } // needs .app bundle
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
