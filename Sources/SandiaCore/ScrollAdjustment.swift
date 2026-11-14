import Foundation

/// Turns a scroll wheel or trackpad scroll into a change of slider value.
///
/// The panel's sliders all run on a 0...1 track, so a scroll is expressed as a
/// share of that track: `fraction(delta:precise:)` converts AppKit's delta and
/// `advance(_:by:)` moves the position without ever leaving the track. The two
/// are pure arithmetic, so the feel can be tested without a mouse or a slider.
///
/// A positive delta raises the value: `NSEvent.scrollingDeltaY` is already in
/// the system's scrolling direction, so natural scrolling and a wheel both keep
/// the sense the user chose in System Settings.
public enum ScrollAdjustment {
    /// Points of scroll that sweep the whole track. Long enough that a mouse
    /// notch is a fine step rather than a jump, short enough that two or three
    /// swipes cross the panel.
    public static let travelPoints = 480.0

    /// Points a line-based notch stands for. Mice report whole lines, trackpads
    /// report points; without this a notch would move the value by a thousandth.
    public static let pointsPerLine = 10.0

    /// Share of the track covered by one scroll event, signed like the delta.
    ///
    /// `precise` is `NSEvent.hasPreciseScrollingDeltas`: precise deltas are
    /// already in points, the others count lines and are converted here so both
    /// devices move the value by a comparable amount.
    public static func fraction(delta: Double, precise: Bool) -> Double {
        let points = precise ? delta : delta * pointsPerLine
        return points / travelPoints
    }

    /// The track position reached from `position`, clamped to 0...1.
    public static func advance(_ position: Double, by fraction: Double) -> Double {
        min(max(position + fraction, 0), 1)
    }

    /// The track position reached from `position` by one scroll event.
    public static func advance(_ position: Double, byScroll delta: Double, precise: Bool) -> Double {
        advance(position, by: fraction(delta: delta, precise: precise))
    }
}
