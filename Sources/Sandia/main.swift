import AppKit
import CoreGraphics

// Recovery path after a crash or `kill -9`: restore colours and exit without any UI.
if CommandLine.arguments.contains("--reset") {
    CGDisplayRestoreColorSyncSettings()
    print("Sandia: display colours restored.")
    exit(0)
}

let application = NSApplication.shared
let delegate = AppDelegate()

application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
