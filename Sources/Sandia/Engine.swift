import AppKit
import Combine
import CoreGraphics
import SandiaCore

/// Resolves the target look once a second, eases toward it, and re-applies it
/// whenever macOS may have reset the gamma tables.
final class Engine {
    let preferences: Preferences
    private let gamma = GammaController()

    /// Called on the main thread after every tick or settings change.
    var onUpdate: ((ResolvedState) -> Void)?
    private(set) var lastResolved: ResolvedState

    private var current = RGB.neutral
    private var lastApplied: RGB?
    private var lastWrite = Date.distantPast

    private var tickTimer: Timer?
    private var animationTimer: Timer?
    private var animationStart = RGB.neutral
    private var animationTarget = RGB.neutral
    private var animationStartTime = Date()

    private var previewKelvin: Double?
    private var previewUntil = Date.distantPast
    private var cancellables = Set<AnyCancellable>()
    private var isShutDown = false

    private static let easeDuration: TimeInterval = 2
    private static let safetyInterval: TimeInterval = 5
    private static let snapThreshold = 0.01

    init(preferences: Preferences) {
        self.preferences = preferences
        lastResolved = preferences.state.resolve(at: Date())
    }

    func start() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common) // keeps ticking while a menu is open
        tickTimer = timer

        preferences.objectWillChange
            .sink { [weak self] _ in DispatchQueue.main.async { self?.tick() } }
            .store(in: &cancellables)

        CGDisplayRegisterReconfigurationCallback(displayReconfigured, Unmanaged.passUnretained(self).toOpaque())

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.reapply()
                // Displays are often not ready right at wake.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.reapply() }
            }
        }

        tick()
    }

    /// Shows `kelvin` for a few seconds regardless of the schedule (slider live preview).
    func preview(kelvin: Double) {
        previewKelvin = kelvin
        previewUntil = Date().addingTimeInterval(3)
        tick()
    }

    func displaysChanged() {
        gamma.refreshDisplays()
        reapply()
    }

    /// Forces the next tick to write even if nothing changed.
    func reapply() {
        guard !isShutDown else { return }
        lastApplied = nil
        tick()
    }

    /// Stops all work and puts the displays back to their normal colours. Safe to call repeatedly.
    func shutdown() {
        isShutDown = true
        tickTimer?.invalidate()
        animationTimer?.invalidate()
        gamma.restore()
    }

    // MARK: - Tick

    private func resolve(now: Date) -> ResolvedState {
        var resolved = preferences.state(at: now).resolve(at: now)
        if let override = preferences.manualOverride {
            resolved = override.applied(to: resolved, at: now)
        }
        if let previewKelvin, now < previewUntil, resolved.mode == .scheduled {
            resolved = ResolvedState(mode: .scheduled, rgb: ColorTemperature.rgb(kelvin: previewKelvin), kelvin: previewKelvin)
        }
        return resolved
    }

    private func tick() {
        guard !isShutDown else { return }
        let now = Date()
        purgeExpiredOverride(now: now)
        let resolved = resolve(now: now)
        lastResolved = resolved
        let target = resolved.rgb

        if current.maxDistance(to: target) < Self.snapThreshold {
            animationTimer?.invalidate()
            animationTimer = nil
            current = target
            writeIfNeeded(now: now)
        } else if animationTimer == nil || animationTarget.maxDistance(to: target) >= Self.snapThreshold {
            startAnimation(to: target, now: now)
        }
        onUpdate?(resolved)
    }

    /// Clears the dated manual temperature once it has run out, so the stored
    /// value does not outlive its own expiry.
    private func purgeExpiredOverride(now: Date) {
        guard let until = preferences.manualUntil, now >= until else { return }
        preferences.manualUntil = nil
        preferences.manualKelvin = nil
    }

    private func startAnimation(to target: RGB, now: Date) {
        animationTimer?.invalidate()
        animationStart = current
        animationTarget = target
        animationStartTime = now
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.animationStep() }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func animationStep() {
        guard !isShutDown else { return }
        let elapsed = Date().timeIntervalSince(animationStartTime)
        let t = min(1, elapsed / Self.easeDuration)
        let eased = t * t * (3 - 2 * t)
        current = animationStart.interpolated(to: animationTarget, fraction: eased)
        writeIfNeeded(now: Date())
        if t >= 1 {
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }

    private func writeIfNeeded(now: Date) {
        let changed = lastApplied != current
        let neutral = current == RGB.neutral
        // The 5 s safety re-apply only matters while a tint is active.
        let stale = !neutral && now.timeIntervalSince(lastWrite) >= Self.safetyInterval
        guard changed || stale else { return }
        if neutral {
            gamma.restore()
        } else {
            gamma.apply(current)
        }
        lastApplied = current
        lastWrite = now
    }
}

private func displayReconfigured(_ display: CGDirectDisplayID,
                                 _ flags: CGDisplayChangeSummaryFlags,
                                 _ userInfo: UnsafeMutableRawPointer?) {
    guard !flags.contains(.beginConfigurationFlag), let userInfo else { return }
    let engine = Unmanaged<Engine>.fromOpaque(userInfo).takeUnretainedValue()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { engine.displaysChanged() }
}
