import AppKit
import SwiftUI
import UserNotifications

private final class IconTimerBridge: NSObject {
    weak var delegate: AppDelegate?

    @objc func fire() {
        let d = delegate
        Task { @MainActor in d?.updateStatusBarIcon() }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    let monitor = MemoryMonitor()
    let spawnMonitor = ProcessSpawnMonitor()
    let portMonitor = PortMonitor()
    let dnsMonitor = DNSMonitor()
    nonisolated(unsafe) private var iconUpdateTimer: Timer?
    nonisolated(unsafe) private let iconTimerBridge = IconTimerBridge()

    private let statusBarFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)

    nonisolated deinit {
        DispatchQueue.main.sync {
            iconUpdateTimer?.invalidate()
        }
        iconTimerBridge.delegate = nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestNotificationPermission()
        setupStatusBar()
        setupPopover()
    }

    private func setupStatusBar() {
        iconTimerBridge.delegate = self
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.action = #selector(togglePopover(_:))
            button.target = self
            updateStatusBarIcon()
        }

        iconUpdateTimer = Timer.scheduledTimer(
            timeInterval: 2.0,
            target: iconTimerBridge,
            selector: #selector(IconTimerBridge.fire),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(iconUpdateTimer!, forMode: .common)
    }

    fileprivate func updateStatusBarIcon() {
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

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 500)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: DashboardView()
                .environmentObject(monitor)
                .environmentObject(spawnMonitor)
                .environmentObject(portMonitor)
                .environmentObject(dnsMonitor)
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

    private func requestNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
