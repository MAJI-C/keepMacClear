import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // Hide from Dock

let delegate = AppDelegate()
app.delegate = delegate
app.run()
