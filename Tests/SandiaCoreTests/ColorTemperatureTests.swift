import XCTest
@testable import SandiaCore

final class ColorTemperatureTests: XCTestCase {
    func testNeutralIsD65() {
        let rgb = ColorTemperature.rgb(kelvin: 6504)
        XCTAssertEqual(rgb.red, 1, accuracy: 1e-9)
        XCTAssertEqual(rgb.green, 1, accuracy: 1e-9)
        XCTAssertEqual(rgb.blue, 1, accuracy: 1e-9)
    }

    func testRangeMatchesSpecification() {
        XCTAssertEqual(ColorTemperature.minimumKelvin, 1000)
        XCTAssertEqual(ColorTemperature.maximumKelvin, 12000)
        XCTAssertEqual(ColorTemperature.neutralKelvin, 6504)
    }

    /// The regression behind the request: just below the D65 neutral point the
    /// blue channel must stay essentially untouched instead of dropping at once.
    func testBlueStaysNeutralJustBelowD65() {
        for kelvin in stride(from: 6480.0, through: 6504.0, by: 1) {
            let rgb = ColorTemperature.rgb(kelvin: kelvin)
            XCTAssertEqual(rgb.red, 1, accuracy: 1e-9, "red moved at \(kelvin)K")
            XCTAssertGreaterThan(rgb.blue, 0.99, "blue collapsed at \(kelvin)K")
        }
        XCTAssertLessThan(1 - ColorTemperature.rgb(kelvin: 6490).blue, 0.005)
    }

    /// Every step of the slider lands on a neighbouring colour: no visible jump
    /// anywhere in the range.
    func testTintChangesContinuously() {
        var previous = ColorTemperature.rgb(kelvin: 2000)
        for kelvin in stride(from: 2001.0, through: 12000.0, by: 1) {
            let current = ColorTemperature.rgb(kelvin: kelvin)
            XCTAssertLessThan(current.maxDistance(to: previous), 0.001,
                              "jump at \(kelvin)K")
            previous = current
        }

        previous = ColorTemperature.rgb(kelvin: 1000)
        for kelvin in stride(from: 1010.0, through: 2000.0, by: 10) {
            let current = ColorTemperature.rgb(kelvin: kelvin)
            XCTAssertLessThan(current.maxDistance(to: previous), 0.01,
                              "jump at \(kelvin)K")
            previous = current
        }
    }

    func testBlueFallsMonotonicallyAsKelvinDrops() {
        var previousBlue = 2.0
        var kelvin = 6504.0
        while kelvin >= 1000 {
            let blue = ColorTemperature.rgb(kelvin: kelvin).blue
            XCTAssertLessThanOrEqual(blue, previousBlue, "blue rose at \(kelvin)K")
            previousBlue = blue
            kelvin -= 100
        }
    }

    func testGreenFallsMonotonicallyAsKelvinDrops() {
        var previousGreen = 2.0
        var kelvin = 6504.0
        while kelvin >= 1000 {
            let green = ColorTemperature.rgb(kelvin: kelvin).green
            XCTAssertLessThanOrEqual(green, previousGreen, "green rose at \(kelvin)K")
            previousGreen = green
            kelvin -= 100
        }
    }

    func testRedStaysFullWhileWarming() {
        for kelvin in stride(from: 1000.0, through: 6504.0, by: 250) {
            XCTAssertEqual(ColorTemperature.rgb(kelvin: kelvin).red, 1, accuracy: 1e-9)
        }
    }

    func testCoolerThanD65CutsRedProgressively() {
        let warm = ColorTemperature.rgb(kelvin: 8000)
        let cool = ColorTemperature.rgb(kelvin: 12000)
        XCTAssertEqual(warm.blue, 1, accuracy: 1e-9)
        XCTAssertEqual(cool.blue, 1, accuracy: 1e-9)
        XCTAssertLessThan(warm.red, 0.95)
        XCTAssertLessThan(cool.red, warm.red)
        XCTAssertLessThan(cool.red, 0.85)
    }

    func testWarmValueIsOrdered() {
        let rgb = ColorTemperature.rgb(kelvin: 2700)
        XCTAssertGreaterThan(rgb.red, rgb.green)
        XCTAssertGreaterThan(rgb.green, rgb.blue)
        XCTAssertGreaterThan(rgb.blue, 0)
    }

    func testClampsBelowMinimum() {
        XCTAssertEqual(ColorTemperature.rgb(kelvin: 100), ColorTemperature.rgb(kelvin: 1000))
        XCTAssertEqual(ColorTemperature.rgb(kelvin: -5), ColorTemperature.rgb(kelvin: 1000))
    }

    func testClampsAboveMaximum() {
        XCTAssertEqual(ColorTemperature.rgb(kelvin: 12_000), ColorTemperature.rgb(kelvin: 12_001))
        XCTAssertEqual(ColorTemperature.rgb(kelvin: 100_000), ColorTemperature.rgb(kelvin: 12_000))
        XCTAssertLessThan(ColorTemperature.rgb(kelvin: 12_000).red, 1)
    }

    func testAllChannelsStayInUnitRange() {
        for kelvin in stride(from: 0.0, through: 20_000, by: 50) {
            let rgb = ColorTemperature.rgb(kelvin: kelvin)
            for value in [rgb.red, rgb.green, rgb.blue] {
                XCTAssertGreaterThanOrEqual(value, 0)
                XCTAssertLessThanOrEqual(value, 1)
            }
        }
    }

    // MARK: - Slider travel

    /// The request: the cold stretch only takes 10–20 % of the bar, so the
    /// neutral point sits at 85 % from the warm (left) end.
    func testColdStretchKeepsAShortShareOfTheTrack() {
        XCTAssertEqual(ColorTemperature.position(forKelvin: 1000), 0, accuracy: 1e-12)
        XCTAssertEqual(ColorTemperature.position(forKelvin: 12000), 1, accuracy: 1e-12)
        XCTAssertEqual(ColorTemperature.position(forKelvin: 6504),
                       ColorTemperature.neutralPosition, accuracy: 1e-12)

        let coldShare = ColorTemperature.position(forKelvin: 12000)
            - ColorTemperature.position(forKelvin: 6504)
        XCTAssertGreaterThanOrEqual(coldShare, 0.10)
        XCTAssertLessThanOrEqual(coldShare, 0.20)
        XCTAssertEqual(coldShare, 0.15, accuracy: 1e-12)
    }

    func testPositionRoundTripsThroughKelvin() {
        for position in stride(from: 0.0, through: 1.0, by: 0.001) {
            let kelvin = ColorTemperature.kelvin(forPosition: position)
            XCTAssertEqual(ColorTemperature.position(forKelvin: kelvin), position,
                           accuracy: 1e-9, "round trip at \(position)")
        }
        for kelvin in stride(from: 1000.0, through: 12000.0, by: 25) {
            let position = ColorTemperature.position(forKelvin: kelvin)
            XCTAssertEqual(ColorTemperature.kelvin(forPosition: position), kelvin,
                           accuracy: 1e-6, "round trip at \(kelvin)K")
        }
    }

    func testKelvinRisesMonotonicallyWithPosition() {
        var previous = -Double.infinity
        for position in stride(from: 0.0, through: 1.0, by: 0.001) {
            let kelvin = ColorTemperature.kelvin(forPosition: position)
            XCTAssertGreaterThan(kelvin, previous, "not rising at \(position)")
            previous = kelvin
        }
    }

    /// No jump anywhere on the track, including across the neutral point where
    /// the two pieces of the mapping meet.
    func testKelvinIsContinuousAlongTheTrack() {
        let step = 0.0005
        var previous = ColorTemperature.kelvin(forPosition: 0)
        var position = step
        while position <= 1 {
            let current = ColorTemperature.kelvin(forPosition: position)
            XCTAssertLessThan(current - previous, 40, "jump at \(position)")
            previous = current
            position += step
        }

        let before = ColorTemperature.kelvin(
            forPosition: ColorTemperature.neutralPosition - 1e-9)
        let after = ColorTemperature.kelvin(
            forPosition: ColorTemperature.neutralPosition + 1e-9)
        XCTAssertEqual(before, after, accuracy: 1e-4)
    }

    func testBothEndsClamp() {
        XCTAssertEqual(ColorTemperature.position(forKelvin: 0), 0)
        XCTAssertEqual(ColorTemperature.position(forKelvin: 50_000), 1)
        XCTAssertEqual(ColorTemperature.kelvin(forPosition: -1), 1000)
        XCTAssertEqual(ColorTemperature.kelvin(forPosition: 2), 12000)
        XCTAssertEqual(ColorTemperature.kelvin(forPosition: 0),
                       ColorTemperature.minimumKelvin)
        XCTAssertEqual(ColorTemperature.kelvin(forPosition: 1),
                       ColorTemperature.maximumKelvin)
    }

    /// The untouched defaults stay in kelvin and land where the new track
    /// expects them: day just before neutral, night well inside the warm run.
    func testDefaultTemperaturesSitOnTheWarmRun() {
        let day = ColorTemperature.position(forKelvin: 6500)
        let night = ColorTemperature.position(forKelvin: 2700)
        XCTAssertGreaterThan(day, 0.8)
        XCTAssertLessThan(day, ColorTemperature.neutralPosition)
        XCTAssertGreaterThan(night, 0.1)
        XCTAssertLessThan(night, day)
    }
}
