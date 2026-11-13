// Renders the real panel with English strings to a PNG, for the README.
//
// It is not part of the app target: `swift build` never sees this file. The
// panel is hosted in an off-screen NSWindow and drawn through AppKit, so the
// controls, the Canvas curve and the system fonts render exactly as in the
// popover. English is the base language, and this harness has no localization
// bundle, so its literals stay English even on a French Mac.
//
//   swiftc -swift-version 5 \
//       Sources/SandiaCore/*.swift \
//       Sources/Sandia/Preferences.swift \
//       Sources/Sandia/PanelView.swift \
//       Sources/Sandia/CurveView.swift \
//       Sources/Sandia/Localization.swift \
//       scripts/screenshot.swift -o .build/screenshot
//   .build/screenshot docs/screenshot.png

import AppKit
import SwiftUI
import SandiaCore

@main
struct Screenshot {
    @MainActor
    static func main() throws {
        let output = CommandLine.arguments.dropFirst().first ?? "docs/screenshot.png"

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: .darkAqua)

        // A throwaway defaults suite: rendering the panel must not touch the
        // settings of the Sandia installed on this Mac.
        let suite = "fr.jbahu.sandia.screenshot"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let preferences = Preferences(defaults: defaults)
        preferences.isEnabled = true
        preferences.isDarkroom = false
        preferences.nightStart = TimeOfDay(hour: 20, minute: 0)
        preferences.nightEnd = TimeOfDay(hour: 8, minute: 0)
        preferences.transitionMinutes = 45
        preferences.dayKelvin = 6500
        preferences.nightKelvin = 2300
        preferences.darkroomBrightness = 0.7

        let now = Date()
        let model = PanelModel(resolved: preferences.state.resolve(at: now))
        model.backlightAvailable = true
        model.backlightPercent = 38
        model.backlightAuto = true
        model.launchAtLogin = true
        model.launchAtLoginAvailable = true

        let actions = PanelActions(
            setNightKelvin: { _ in },
            setDarkroom: { _ in },
            togglePause: {},
            setBacklight: { _ in },
            toggleBacklightAuto: {},
            setLaunchAtLogin: { _ in },
            quit: {}
        )

        let panel = PanelView(preferences: preferences, model: model, actions: actions)
        let hosting = NSHostingView(rootView: panel)
        hosting.layoutSubtreeIfNeeded()
        let panelSize = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: panelSize)
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = 12
        hosting.layer?.masksToBounds = true
        hosting.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // The popover's own material, in a rounded card with a soft shadow.
        let padding: CGFloat = 36
        let canvas = NSView(frame: NSRect(x: 0, y: 0,
                                          width: panelSize.width + padding * 2,
                                          height: panelSize.height + padding * 2))
        canvas.wantsLayer = true
        let gradient = CAGradientLayer()
        gradient.frame = canvas.bounds
        gradient.colors = [
            NSColor(calibratedRed: 0.16, green: 0.11, blue: 0.27, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.42, green: 0.15, blue: 0.24, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.66, green: 0.32, blue: 0.12, alpha: 1).cgColor,
        ]
        gradient.startPoint = CGPoint(x: 0.1, y: 1)
        gradient.endPoint = CGPoint(x: 0.9, y: 0)
        canvas.layer?.addSublayer(gradient)

        hosting.layer?.shadowColor = NSColor.black.cgColor
        hosting.layer?.shadowOpacity = 0.45
        hosting.layer?.shadowRadius = 24
        hosting.layer?.shadowOffset = CGSize(width: 0, height: -6)
        canvas.addSubview(hosting)
        hosting.frame.origin = CGPoint(x: padding, y: padding)

        let window = NSWindow(contentRect: canvas.bounds,
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = canvas
        window.layoutIfNeeded()

        // Draw at 2x regardless of the display's scale, so text stays crisp.
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(canvas.bounds.width * scale),
                                         pixelsHigh: Int(canvas.bounds.height * scale),
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0) else {
            throw NSError(domain: "SandiaScreenshot", code: 1)
        }
        rep.size = canvas.bounds.size
        canvas.cacheDisplay(in: canvas.bounds, to: rep)

        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "SandiaScreenshot", code: 2)
        }
        try png.write(to: URL(fileURLWithPath: output))
        print("Wrote \(output) — \(Int(rep.size.width))×\(Int(rep.size.height)) pt")
    }
}
