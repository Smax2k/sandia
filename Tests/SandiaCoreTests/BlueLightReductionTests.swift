import XCTest
@testable import SandiaCore

final class BlueLightReductionTests: XCTestCase {
    func testEndpointsAreExact() {
        XCTAssertEqual(BlueLightReduction.neutralKelvin, 6504)
        XCTAssertEqual(BlueLightReduction.warmestKelvin, 1000)

        XCTAssertEqual(BlueLightReduction.fraction(kelvin: 6504), 0, accuracy: 1e-12)
        XCTAssertEqual(BlueLightReduction.fraction(kelvin: 1000), 1, accuracy: 1e-12)

        XCTAssertEqual(BlueLightReduction.kelvin(forFraction: 0), 6504)
        XCTAssertEqual(BlueLightReduction.kelvin(forFraction: 1), 1000)
        XCTAssertEqual(BlueLightReduction.rgb(fraction: 0), .neutral)
    }

    /// D65 is exactly neutral, so 0 % leaves every channel untouched.
    func testNeutralMultiplierIsExactlyOne() {
        let rgb = ColorTemperature.rgb(kelvin: BlueLightReduction.neutralKelvin)
        XCTAssertEqual(rgb, .neutral)
    }

    /// The percentage is the filter's position on the mired scale, not a share
    /// of the blue channel.
    func testFractionUsesTheMiredScale() {
        let expected = (1 / 2700.0 - 1 / 6504.0) / (1 / 1000.0 - 1 / 6504.0)
        XCTAssertEqual(BlueLightReduction.fraction(kelvin: 2700), expected,
                       accuracy: 1e-12)

        let fraction = BlueLightReduction.fraction(kelvin: 2700)
        XCTAssertGreaterThan(fraction, 0.2)
        XCTAssertLessThan(fraction, 0.35)
    }

    func testKelvinUsesTheMiredInverse() {
        let expected = 1 / (1 / 6504.0 + 0.4 * (1 / 1000.0 - 1 / 6504.0))
        XCTAssertEqual(BlueLightReduction.kelvin(forFraction: 0.4), expected,
                       accuracy: 1e-9)
    }

    /// The migration rule for saved day, night and manual values: warm settings
    /// are kept, cooler ones become the neutral end, never a destructive reset.
    func testClampingKeepsWarmSettingsAndMovesCoolOnesToNeutral() {
        XCTAssertEqual(BlueLightReduction.clampedKelvin(2700), 2700)
        XCTAssertEqual(BlueLightReduction.clampedKelvin(6500), 6500)
        XCTAssertEqual(BlueLightReduction.clampedKelvin(6504), 6504)
        XCTAssertEqual(BlueLightReduction.clampedKelvin(7000), 6504)
        XCTAssertEqual(BlueLightReduction.clampedKelvin(12_000), 6504)
        XCTAssertEqual(BlueLightReduction.clampedKelvin(500), 1000)
        XCTAssertEqual(BlueLightReduction.clampedKelvin(.nan), 6504)
    }

    func testNonFiniteAndOutOfRangeInputsAreSafe() {
        XCTAssertEqual(BlueLightReduction.fraction(kelvin: .nan), 0)
        XCTAssertEqual(BlueLightReduction.fraction(kelvin: .infinity), 0)
        XCTAssertEqual(BlueLightReduction.fraction(kelvin: -.infinity), 0)
        XCTAssertEqual(BlueLightReduction.fraction(kelvin: 0), 1)
        XCTAssertEqual(BlueLightReduction.fraction(kelvin: 12_000), 0)

        XCTAssertEqual(BlueLightReduction.kelvin(forFraction: .nan), 6504)
        XCTAssertEqual(BlueLightReduction.kelvin(forFraction: -.infinity), 6504)
        XCTAssertEqual(BlueLightReduction.kelvin(forFraction: -1), 6504)
        XCTAssertEqual(BlueLightReduction.kelvin(forFraction: 2), 1000)
        XCTAssertEqual(BlueLightReduction.rgb(fraction: .nan), .neutral)
    }

    func testKelvinFallsMonotonicallyAlongTheFraction() {
        var previous = Double.infinity
        for fraction in stride(from: 0.0, through: 1.0, by: 0.001) {
            let kelvin = BlueLightReduction.kelvin(forFraction: fraction)
            XCTAssertLessThanOrEqual(kelvin, previous + 1e-9,
                                     "not falling at \(fraction)")
            previous = kelvin
        }
    }

    /// The inverse is what the slider stores, so it must survive a round trip
    /// from fraction to kelvin and back.
    func testFractionRoundTrip() {
        for fraction in stride(from: 0.0, through: 1.0, by: 0.001) {
            let kelvin = BlueLightReduction.kelvin(forFraction: fraction)
            XCTAssertEqual(BlueLightReduction.fraction(kelvin: kelvin), fraction,
                           accuracy: 1e-6, "round trip at \(fraction)")
        }
    }

    /// No visible jump along the track, including near the neutral end where the
    /// curve is shallow.
    func testInverseIsContinuous() {
        var previous = BlueLightReduction.kelvin(forFraction: 0)
        var fraction = 0.0005
        while fraction <= 1 {
            let kelvin = BlueLightReduction.kelvin(forFraction: fraction)
            XCTAssertLessThan(previous - kelvin, 100,
                              "jump at fraction \(fraction)")
            previous = kelvin
            fraction += 0.0005
        }
    }

    /// The whole RGB multiplier, not just blue, must keep moving monotonically
    /// and without a step.
    func testRGBFallsMonotonicallyWithTheFilterStrength() {
        var previous = BlueLightReduction.rgb(fraction: 0)
        for step in 1...1000 {
            let fraction = Double(step) / 1000
            let current = BlueLightReduction.rgb(fraction: fraction)
            XCTAssertLessThanOrEqual(current.red, previous.red + 1e-12,
                                     "red rose at \(fraction)")
            XCTAssertLessThanOrEqual(current.green, previous.green + 1e-12,
                                     "green rose at \(fraction)")
            XCTAssertLessThanOrEqual(current.blue, previous.blue + 1e-12,
                                     "blue rose at \(fraction)")
            XCTAssertLessThan(current.maxDistance(to: previous), 0.02,
                              "jump at \(fraction)")
            previous = current
        }
    }

    /// The regression behind the mired mapping: 99.9, 99.99, 99.999 and 100 %
    /// must all be neighbouring full-RGB values. A blue-only plateau could jump
    /// on green at the very last step.
    func testRGBHasNoJumpAtFullReduction() {
        let fractions = [0.999, 0.9999, 0.99999, 1.0]
        for (before, after) in zip(fractions, fractions.dropFirst()) {
            let first = BlueLightReduction.rgb(fraction: before)
            let second = BlueLightReduction.rgb(fraction: after)
            XCTAssertLessThan(first.maxDistance(to: second), 1e-3,
                              "jump from \(before) to \(after)")
            XCTAssertEqual(second.red, 1, accuracy: 1e-9)
        }
    }

    /// Same check at the neutral end: 0, 0.1 % and 1 % stay neighbouring, with
    /// small intermediate steps, on every channel.
    func testRGBHasNoJumpNearNeutral() {
        let fractions = (0...10).map { Double($0) / 1000 }
        for (before, after) in zip(fractions, fractions.dropFirst()) {
            let first = BlueLightReduction.rgb(fraction: before)
            let second = BlueLightReduction.rgb(fraction: after)
            XCTAssertLessThan(first.maxDistance(to: second), 0.01,
                              "jump from \(before) to \(after)")
        }
    }

    func testRGBMatchesTheKelvinMultiplier() {
        for fraction in [0.1, 0.25, 0.5, 0.75, 0.9] {
            let kelvin = BlueLightReduction.kelvin(forFraction: fraction)
            XCTAssertEqual(BlueLightReduction.rgb(fraction: fraction),
                           ColorTemperature.rgb(kelvin: kelvin))
        }
    }
}
