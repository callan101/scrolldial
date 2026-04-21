// Entry point — accessory (menu bar only, no Dock icon). See Info.plist LSUIElement.

import AppKit

private let kSmoothDialBundleID = Bundle.main.bundleIdentifier ?? "callan.SmoothDial"

// Avoid duplicate CGEvent taps on cghidEventTap (same idea as BoDial).
let others = NSRunningApplication.runningApplications(withBundleIdentifier: kSmoothDialBundleID)
    .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
if !others.isEmpty {
    fputs("SmoothDial: already running (pid \(others[0].processIdentifier)). Exiting.\n", stderr)
    exit(0)
}

// Ctrl+C (SIGINT) must tear down the event tap before exit.
// Without this, the zombie tap on cghidEventTap can persist and block scroll events.
signal(SIGINT) { _ in
    SmoothDialCore.shared.stop()
    fputs("\nSmoothDial: stopped (SIGINT).\n", stderr)
    _Exit(0)
}
signal(SIGTERM) { _ in
    SmoothDialCore.shared.stop()
    fputs("\nSmoothDial: stopped (SIGTERM).\n", stderr)
    _Exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = SmoothDialAppDelegate()
app.delegate = delegate
app.run()
