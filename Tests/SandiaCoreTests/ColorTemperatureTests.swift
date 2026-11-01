import XCTest
@testable import SandiaCore

final class ColorTemperatureTests: XCTestCase {
    func testDaylightIsNeutral() {
        let rgb = ColorTemperature.rgb(kelvin: 6500)
        XCTAssertEqual(rgb.red, 1, accuracy: 1e-9)
        XCTAssertEqual(rgb.green, 1, accuracy: 1e-9)
        XCTAssertEqual(rgb.blue, 1, accuracy: 1e-9)
    }

    func testBlueFallsMonotonicallyAsKelvinDrops() {
        var previousBlue = 2.0
        var kelvin = 6500.0
        while kelvin >= 1000 {
            let blue = ColorTemperature.rgb(kelvin: kelvin).blue
            XCTAssertLessThanOrEqual(blue, previousBlue, "blue rose at \(kelvin)K")
            previousBlue = blue
            kelvin -= 100
        }
    }

    func testGreenFallsMonotonicallyAsKelvinDrops() {
        var previousGreen = 2.0
        var kelvin = 6500.0
        while kelvin >= 1000 {
            let green = ColorTemperature.rgb(kelvin: kelvin).green
            XCTAssertLessThanOrEqual(green, previousGreen, "green rose at \(kelvin)K")
            previousGreen = green
            kelvin -= 100
        }
    }

    func testRedStaysFullWhileWarming() {
        for kelvin in stride(from: 1000.0, through: 6500.0, by: 250) {
            XCTAssertEqual(ColorTemperature.rgb(kelvin: kelvin).red, 1, accuracy: 1e-9)
        }
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
        XCTAssertEqual(ColorTemperature.rgb(kelvin: 9000), RGB.neutral)
        XCTAssertEqual(ColorTemperature.rgb(kelvin: 100_000), RGB.neutral)
    }

    func testAllChannelsStayInUnitRange() {
        for kelvin in stride(from: 0.0, through: 10_000, by: 50) {
            let rgb = ColorTemperature.rgb(kelvin: kelvin)
            for value in [rgb.red, rgb.green, rgb.blue] {
                XCTAssertGreaterThanOrEqual(value, 0)
                XCTAssertLessThanOrEqual(value, 1)
            }
        }
    }
}
