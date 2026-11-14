import AppKit
import SwiftUI
import SandiaCore

extension View {
    /// Lets a control answer the scroll wheel and the trackpad's two-finger
    /// scroll while the pointer is over it: a proportional move inside `range`,
    /// applied at once like a drag, with the event consumed so nothing scrolls
    /// underneath.
    ///
    /// One behaviour for every slider of the panel; the arithmetic lives in
    /// `ScrollAdjustment`, under test. A slider that stores something else than
    /// its track position (the temperatures store kelvin) passes a binding on
    /// the position and keeps its own conversion.
    func scrollWheelValue(_ value: Binding<Double>,
                          in range: ClosedRange<Double> = 0...1) -> some View {
        modifier(ScrollWheelValueModifier(value: value, range: range))
    }
}

/// The shared behaviour behind `scrollWheelValue(_:in:)`.
///
/// The travel is tracked as a 0...1 position rather than read back from the
/// value each time: several values are quantised (a temperature is stored in
/// steps of 10 K, the backlight in whole percent), and the leftover of a slow
/// trackpad scroll is what lets the value cross that quantisation instead of
/// stalling on it.
private struct ScrollWheelValueModifier: ViewModifier {
    @Binding var value: Double
    let range: ClosedRange<Double>

    /// Position of the run under way, unrounded.
    @State private var travel: Double?
    /// Last position handed to the binding, to notice a change from elsewhere.
    @State private var requested: Double?

    /// How far the stored value may sit from the requested position before the
    /// travel is dropped: above the coarse rounding of a quantised value, far
    /// below a step the eye can see.
    private static let driftTolerance = 0.02

    func body(content: Content) -> some View {
        content.background(
            ScrollWheelProbe { delta, precise in
                scroll(by: ScrollAdjustment.fraction(delta: delta, precise: precise))
            }
        )
    }

    private func scroll(by fraction: Double) {
        let current = position(of: value)
        var base = travel ?? current
        if let requested, abs(requested - current) > Self.driftTolerance {
            // Dragged, or set from elsewhere, since the last scroll: resume
            // here instead of jumping back to the old travel.
            base = current
        }
        let next = ScrollAdjustment.advance(base, by: fraction)
        travel = next
        requested = next
        value = range.lowerBound + next * (range.upperBound - range.lowerBound)
    }

    private func position(of value: Double) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }
}

/// An invisible view that marks the control's frame and consumes the scroll
/// events falling inside it.
///
/// SwiftUI has no scroll-wheel gesture, and an overlay that took the wheel would
/// also take the clicks and break the slider's drag. A local monitor sees the
/// event before the window does, so the probe only needs to know where it is:
/// the slider keeps its own mouse handling, and the event never reaches the
/// panel. Only the control under the pointer reacts, so the sliders of one panel
/// never fight over a scroll.
private struct ScrollWheelProbe: NSViewRepresentable {
    let onScroll: (Double, Bool) -> Void

    func makeNSView(context: Context) -> ScrollWheelProbeView {
        let view = ScrollWheelProbeView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: ScrollWheelProbeView, context: Context) {
        view.onScroll = onScroll
    }
}

private final class ScrollWheelProbeView: NSView {
    var onScroll: ((Double, Bool) -> Void)?

    private var monitor: Any?

    /// Clicks belong to the control in front of the probe.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop() } else { start() }
    }

    deinit {
        stop()
    }

    private func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.consume(scroll: event) else { return event }
            return nil
        }
    }

    private func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    /// True when the event is this control's and must not reach the rest of the
    /// app.
    private func consume(scroll event: NSEvent) -> Bool {
        guard let window, event.window === window,
              !isHiddenOrHasHiddenAncestor else { return false }
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return false }
        // The momentum that follows a lifted two-finger scroll would keep
        // turning the value after the gesture ended. It is swallowed too, so the
        // panel stays still, but it does not move the value.
        guard event.momentumPhase.isEmpty else { return true }
        let delta = event.scrollingDeltaY
        guard delta != 0 else { return true }
        onScroll?(delta, event.hasPreciseScrollingDeltas)
        return true
    }
}
