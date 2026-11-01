import AppKit
import SandiaCore
import SwiftUI

/// Owns the status item and its popover. The popover is the only settings surface.
final class MenuController: NSObject, NSPopoverDelegate {
    private let engine: Engine
    private let preferences: Preferences
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let model: PanelModel
    private let backlight = KeyboardBacklight()

    /// A click on the status item closes a transient popover before the button action runs,
    /// so ignore the action that follows that close instead of reopening it.
    private var reopenSuppressedUntil = Date.distantPast

    init(engine: Engine, preferences: Preferences) {
        self.engine = engine
        self.preferences = preferences
        model = PanelModel(resolved: engine.lastResolved)
        super.init()

        configurePopover()
        configureStatusItem()

        engine.onUpdate = { [weak self] resolved in self?.refresh(resolved) }
        refresh(engine.lastResolved)
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.delegate = self
        let host = NSHostingController(rootView: PanelView(preferences: preferences,
                                                          model: model,
                                                          actions: makeActions()))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
    }

    private func configureStatusItem() {
        // No statusItem.menu: the button's action opens the popover instead.
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover)
    }

    private func makeActions() -> PanelActions {
        PanelActions(
            setNightKelvin: { [weak self] kelvin in self?.setNightKelvin(kelvin) },
            setDarkroom: { [weak self] on in self?.setDarkroom(on) },
            togglePause: { [weak self] in self?.togglePause() },
            setBacklight: { [weak self] percent in self?.setBacklight(percent) },
            toggleBacklightAuto: { [weak self] in self?.toggleBacklightAuto() },
            setLaunchAtLogin: { [weak self] enabled in self?.setLaunchAtLogin(enabled) },
            quit: { [weak self] in self?.quit() }
        )
    }

    // MARK: - Popover

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard Date() >= reopenSuppressedUntil else { return }
        showPopover()
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        // Under LSUIElement the app is not active; activate first so the controls take the focus.
        NSApp.activate()
        syncPanel()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        // Without this the first text field (the time picker) opens selected in blue.
        popover.contentViewController?.view.window?.makeFirstResponder(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        reopenSuppressedUntil = Date().addingTimeInterval(0.2)
    }

    /// Re-read the live system state each time the panel opens.
    private func syncPanel() {
        model.resolved = engine.lastResolved

        let backlightAvailable = backlight.isAvailable
        model.backlightAvailable = backlightAvailable
        if backlightAvailable {
            let percent = Int((backlight.brightness * 100).rounded())
            model.backlightPercent = Double(percent)
            model.backlightAuto = backlight.isAutoBrightnessEnabled
        }

        syncLoginItem()
    }

    private func syncLoginItem() {
        model.launchAtLogin = LoginItem.isEnabled
        model.launchAtLoginAvailable = LoginItem.isSupportedLocation
        model.launchAtLoginNeedsApproval = LoginItem.needsApproval
    }

    // MARK: - Refresh

    private func refresh(_ resolved: ResolvedState) {
        model.resolved = resolved

        // Follows the clock schedule only, so disabling or pausing never changes the icon.
        let night = preferences.state.schedule.nightWeight(at: Date()) >= 0.5
        let symbol = resolved.mode == .darkroom || night ? "moon" : "sun.max"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Sandia")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.imagePosition = .imageLeading
        // While paused, a countdown sits beside the unchanged icon.
        let countdown = pausedMinutesLeft.map { " \($0)m" } ?? ""
        statusItem.button?.attributedTitle = NSAttributedString(
            string: countdown,
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)])
    }

    /// Whole minutes left in the pause, rounded up so it never shows 0m while still paused.
    private var pausedMinutesLeft: Int? {
        guard let until = preferences.pausedUntil, preferences.isEnabled else { return nil }
        let remaining = until.timeIntervalSinceNow
        return remaining > 0 ? Int((remaining / 60).rounded(.up)) : nil
    }

    private var isPaused: Bool {
        preferences.pausedUntil.map { $0 > Date() } ?? false
    }

    // MARK: - Actions

    private func setNightKelvin(_ raw: Double) {
        let kelvin = (raw / 10).rounded() * 10
        preferences.pausedUntil = nil // touching the slider means "show me", so end any pause
        preferences.nightKelvin = kelvin
        engine.preview(kelvin: kelvin)
    }

    private func setDarkroom(_ on: Bool) {
        preferences.pausedUntil = nil
        preferences.isDarkroom = on
    }

    private func togglePause() {
        preferences.pausedUntil = isPaused ? nil : Date().addingTimeInterval(3600)
    }

    private func setBacklight(_ percent: Double) {
        let rounded = Int(percent.rounded())
        backlight.brightness = Float(rounded) / 100
        model.backlightPercent = Double(rounded)
    }

    private func toggleBacklightAuto() {
        backlight.isAutoBrightnessEnabled.toggle()
        model.backlightAuto = backlight.isAutoBrightnessEnabled
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        LoginItem.setEnabled(enabled)
        syncLoginItem()
    }

    private func quit() {
        engine.shutdown()
        NSApp.terminate(nil)
    }
}
