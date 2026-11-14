import XCTest
@testable import SandiaCore

final class ScrollAdjustmentTests: XCTestCase {
    /// A wheel notch is a fine step, not a jump: under 4 % of the track.
    func testOneWheelNotchIsASmallStep() {
        let step = ScrollAdjustment.fraction(delta: 1, precise: false)
        XCTAssertGreaterThan(step, 0.005)
        XCTAssertLessThan(step, 0.04)
    }

    /// A trackpad reports points, a mouse reports lines: the same physical
    /// gesture must move the value by the same amount on both.
    func testLineAndPointDeltasAgree() {
        let notch = ScrollAdjustment.fraction(delta: 1, precise: false)
        let points = ScrollAdjustment.fraction(delta: ScrollAdjustment.pointsPerLine,
                                               precise: true)
        XCTAssertEqual(notch, points, accuracy: 1e-12)
    }

    /// Proportional: the further the scroll, the bigger the move, and the sign
    /// of the scroll is the sign of the move.
    func testTravelIsProportional() {
        for delta in [0.5, 1.0, 4.0, 12.0, 40.0] {
            let single = ScrollAdjustment.fraction(delta: delta, precise: true)
            let double = ScrollAdjustment.fraction(delta: delta * 2, precise: true)
            XCTAssertEqual(single * 2, double, accuracy: 1e-12)
            XCTAssertEqual(-single, ScrollAdjustment.fraction(delta: -delta, precise: true),
                           accuracy: 1e-12)
        }
        XCTAssertEqual(ScrollAdjustment.fraction(delta: 0, precise: true), 0)
    }

    /// `travelPoints` of scroll sweep the whole track, and repeated small
    /// events add up to the same place as one long one.
    func testFullTravelSweepsTheTrack() {
        var position = 0.0
        for _ in 0..<48 {
            position = ScrollAdjustment.advance(position, byScroll: 10, precise: true)
        }
        XCTAssertEqual(position, 1, accuracy: 1e-9)

        var halved = 0.0
        for _ in 0..<24 {
            halved = ScrollAdjustment.advance(halved, byScroll: 10, precise: true)
        }
        XCTAssertEqual(halved, 0.5, accuracy: 1e-9)
    }

    /// The value never leaves its range, however hard the scroll goes.
    func testStaysInsideTheTrack() {
        XCTAssertEqual(ScrollAdjustment.advance(1, by: 0.02), 1)
        XCTAssertEqual(ScrollAdjustment.advance(1, by: 500), 1)
        XCTAssertEqual(ScrollAdjustment.advance(0, by: -0.02), 0)
        XCTAssertEqual(ScrollAdjustment.advance(0.4, by: -500), 0)
        XCTAssertEqual(ScrollAdjustment.advance(0.4, by: 0.1), 0.5, accuracy: 1e-12)
    }

    /// A positive delta raises the value on both device kinds: the direction
    /// follows the system, the panel never inverts it.
    func testPositiveDeltaRaisesTheValue() {
        let fromMouse = ScrollAdjustment.advance(0.5, byScroll: 1, precise: false)
        let fromTrackpad = ScrollAdjustment.advance(0.5, byScroll: 10, precise: true)
        XCTAssertGreaterThan(fromMouse, 0.5)
        XCTAssertGreaterThan(fromTrackpad, 0.5)
        XCTAssertEqual(fromMouse, fromTrackpad, accuracy: 1e-12)
    }

    /// The temperature sliders store kelvin rounded to 10 K, so a scroll that
    /// is smaller than that rounding must still end up moving the stored value
    /// once a few events have accumulated.
    func testSmallScrollsAccumulatePastTenKelvinRounding() {
        let start = 2700.0
        var position = ColorTemperature.position(forKelvin: start)
        for _ in 0..<5 {
            position = ScrollAdjustment.advance(position, byScroll: 2, precise: true)
        }
        let kelvin = ColorTemperature.kelvin(forPosition: position)
        let stored = (kelvin / 10).rounded() * 10
        XCTAssertGreaterThan(stored, start)
    }
}
