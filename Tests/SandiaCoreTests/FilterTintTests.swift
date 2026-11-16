import XCTest
@testable import SandiaCore

final class FilterTintTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 15,
                                           hour: hour, minute: minute))!
    }

    private var warm: RGB { ColorTemperature.rgb(kelvin: 2700) }

    // MARK: - Identity

    /// The default is 0 and changes nothing: an existing install keeps exactly
    /// the rendering it had.
    func testDefaultIsIdentity() {
        XCTAssertEqual(FilterTint.neutral, 0)
        for kelvin in stride(from: 1000.0, through: 12_000.0, by: 250) {
            let base = ColorTemperature.rgb(kelvin: kelvin)
            XCTAssertEqual(FilterTint.applied(to: base, tint: FilterTint.neutral), base,
                           "changed at \(kelvin)K")
        }
    }

    func testTintIsClampedAndNonFiniteFallsBackToNeutral() {
        XCTAssertEqual(FilterTint.clamped(-5), FilterTint.minimum)
        XCTAssertEqual(FilterTint.clamped(5), FilterTint.maximum)
        XCTAssertEqual(FilterTint.clamped(.nan), FilterTint.neutral)
        XCTAssertEqual(FilterTint.clamped(.infinity), FilterTint.neutral)

        XCTAssertEqual(FilterTint.applied(to: warm, tint: 2),
                       FilterTint.applied(to: warm, tint: 1))
        XCTAssertEqual(FilterTint.applied(to: warm, tint: -2),
                       FilterTint.applied(to: warm, tint: -1))
        XCTAssertEqual(FilterTint.applied(to: warm, tint: .nan), warm)
    }

    // MARK: - Neutral and untouched channels

    /// A neutral look has no blue headroom, so no tint can move it.
    func testNeutralIsInvariantAtEveryTint() {
        for tint in stride(from: -1.0, through: 1.0, by: 0.01) {
            XCTAssertEqual(FilterTint.applied(to: .neutral, tint: tint), .neutral,
                           "moved at \(tint)")
        }
        for tint in [-Double.infinity, .nan, 2, -2] {
            XCTAssertEqual(FilterTint.applied(to: .neutral, tint: tint), .neutral)
        }
    }

    func testRedAndBlueAreUnchanged() {
        for kelvin in stride(from: 1000.0, through: 12_000.0, by: 500) {
            let base = ColorTemperature.rgb(kelvin: kelvin)
            for tint in stride(from: -1.0, through: 1.0, by: 0.05) {
                let result = FilterTint.applied(to: base, tint: tint)
                XCTAssertEqual(result.red, base.red, accuracy: 1e-12, "red at \(tint)")
                XCTAssertEqual(result.blue, base.blue, accuracy: 1e-12, "blue at \(tint)")
            }
        }
    }

    // MARK: - Green axis

    func testGreenStaysInUnitRange() {
        for kelvin in stride(from: 1000.0, through: 12_000.0, by: 500) {
            let base = ColorTemperature.rgb(kelvin: kelvin)
            for tint in stride(from: -1.5, through: 1.5, by: 0.05) {
                let result = FilterTint.applied(to: base, tint: tint)
                for value in [result.red, result.green, result.blue] {
                    XCTAssertGreaterThanOrEqual(value, 0, "below 0 at \(tint)")
                    XCTAssertLessThanOrEqual(value, 1, "above 1 at \(tint)")
                }
            }
        }
    }

    func testGreenRisesMonotonicallyWithTint() {
        var previous = -Double.infinity
        for tint in stride(from: -1.0, through: 1.0, by: 0.01) {
            let green = FilterTint.applied(to: warm, tint: tint).green
            XCTAssertGreaterThanOrEqual(green, previous, "green fell at \(tint)")
            previous = green
        }
    }

    func testRedSideRemovesGreenAndAmberSideLiftsIt() {
        let red = FilterTint.applied(to: warm, tint: -1)
        let amber = FilterTint.applied(to: warm, tint: 1)
        XCTAssertLessThan(red.green, warm.green)
        XCTAssertGreaterThanOrEqual(red.green, 0)
        XCTAssertEqual(amber.green, 1, accuracy: 1e-12)
        XCTAssertGreaterThan(amber.green, warm.green)
    }

    func testNonFiniteChannelsStayBounded() {
        let result = FilterTint.applied(
            to: RGB(red: .infinity, green: .nan, blue: -.infinity),
            tint: 0.5)
        for value in [result.red, result.green, result.blue] {
            XCTAssertTrue(value.isFinite)
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThanOrEqual(value, 1)
        }
    }

    // MARK: - Resolved states

    func testScheduledLookCarriesTheTint() {
        let base = SandiaState().resolve(at: date(23), calendar: calendar)
        XCTAssertEqual(base.mode, .scheduled)

        let tinted = base.applyingFilterTint(-1)
        XCTAssertEqual(tinted.mode, .scheduled)
        XCTAssertEqual(tinted.kelvin, base.kelvin)
        XCTAssertLessThan(tinted.rgb.green, base.rgb.green)
        XCTAssertNotEqual(tinted.rgb, base.rgb)
        XCTAssertEqual(tinted.rgb.blue, base.rgb.blue)
        XCTAssertEqual(tinted.rgb.red, base.rgb.red)
    }

    /// Disabled, paused and darkroom keep their priority: the advanced tint is
    /// never applied to them.
    func testDisabledPausedAndDarkroomAreNeverTinted() {
        var disabled = SandiaState()
        disabled.isEnabled = false

        var paused = SandiaState()
        paused.pausedUntil = date(23, 30)

        var darkroom = SandiaState()
        darkroom.isDarkroom = true

        for state in [disabled, paused, darkroom] {
            let resolved = state.resolve(at: date(23), calendar: calendar)
            for tint in [-1.0, 1.0] {
                XCTAssertEqual(resolved.applyingFilterTint(tint), resolved,
                               "\(resolved.mode) was tinted at \(tint)")
            }
        }
    }

    func testDefaultTintLeavesEveryModeUntouched() {
        var disabled = SandiaState()
        disabled.isEnabled = false
        var darkroom = SandiaState()
        darkroom.isDarkroom = true

        for state in [SandiaState(), disabled, darkroom] {
            let resolved = state.resolve(at: date(23), calendar: calendar)
            XCTAssertEqual(resolved.applyingFilterTint(FilterTint.neutral), resolved)
        }
    }
}
