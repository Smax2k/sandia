import XCTest
@testable import SandiaCore

final class ScheduleTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ hour: Int, _ minute: Int, _ second: Int = 0, calendar: Calendar? = nil,
                      month: Int = 6, day: Int = 15) -> Date {
        let cal = calendar ?? self.calendar
        let components = DateComponents(year: 2026, month: month, day: day,
                                        hour: hour, minute: minute, second: second)
        return cal.date(from: components)!
    }

    private func kelvin(_ schedule: Schedule, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Double {
        schedule.targetKelvin(at: date(hour, minute, second), calendar: calendar)
    }

    private let accuracy = 0.5

    // MARK: Defaults and midnight-crossing window

    func testDefaultsMatchPlan() {
        let schedule = Schedule()
        XCTAssertEqual(schedule.nightStart, TimeOfDay(hour: 20, minute: 0))
        XCTAssertEqual(schedule.nightEnd, TimeOfDay(hour: 7, minute: 0))
        XCTAssertEqual(schedule.transitionMinutes, 30)
        XCTAssertEqual(schedule.dayKelvin, 6500)
        XCTAssertEqual(schedule.nightKelvin, 2700)
    }

    func testMiddayIsDay() {
        XCTAssertEqual(kelvin(Schedule(), 12, 0), 6500, accuracy: accuracy)
    }

    func testBeforeFadeStartsIsDay() {
        XCTAssertEqual(kelvin(Schedule(), 19, 44), 6500, accuracy: accuracy)
        XCTAssertEqual(kelvin(Schedule(), 19, 45), 6500, accuracy: accuracy)
    }

    func testFadeIsCentredOnNightStart() {
        let schedule = Schedule()
        XCTAssertEqual(kelvin(schedule, 20, 0), 4600, accuracy: accuracy)
        XCTAssertEqual(kelvin(schedule, 19, 52, 30), 5550, accuracy: accuracy) // quarter of the way
        XCTAssertEqual(kelvin(schedule, 20, 15), 2700, accuracy: accuracy)
    }

    func testDeepNightIsNightBeforeAndAfterMidnight() {
        let schedule = Schedule()
        XCTAssertEqual(kelvin(schedule, 23, 0), 2700, accuracy: accuracy)
        XCTAssertEqual(kelvin(schedule, 0, 0), 2700, accuracy: accuracy)
        XCTAssertEqual(kelvin(schedule, 3, 0), 2700, accuracy: accuracy)
    }

    func testFadeIsCentredOnNightEnd() {
        let schedule = Schedule()
        XCTAssertEqual(kelvin(schedule, 6, 44), 2700, accuracy: accuracy)
        XCTAssertEqual(kelvin(schedule, 6, 45), 2700, accuracy: accuracy)
        XCTAssertEqual(kelvin(schedule, 7, 0), 4600, accuracy: accuracy)
        XCTAssertEqual(kelvin(schedule, 7, 15), 6500, accuracy: accuracy)
        XCTAssertEqual(kelvin(schedule, 7, 16), 6500, accuracy: accuracy)
    }

    func testFadeIsMonotonicAcrossNightStart() {
        let schedule = Schedule()
        var previous = 7000.0
        for minute in 0..<31 {
            let value = schedule.targetKelvin(at: date(19, 45) + Double(minute * 60), calendar: calendar)
            XCTAssertLessThanOrEqual(value, previous)
            previous = value
        }
    }

    // MARK: Zero-length fade

    func testZeroFadeSwitchesInstantlyAcrossMidnight() {
        let schedule = Schedule(transitionMinutes: 0)
        XCTAssertEqual(kelvin(schedule, 19, 59, 59), 6500, accuracy: accuracy)
        XCTAssertEqual(kelvin(schedule, 20, 0), 2700, accuracy: accuracy)
        XCTAssertEqual(kelvin(schedule, 6, 59, 59), 2700, accuracy: accuracy)
        XCTAssertEqual(kelvin(schedule, 7, 0), 6500, accuracy: accuracy)
    }

    // MARK: Same-day window

    func testSameDayWindowWithZeroFade() {
        let schedule = Schedule(nightStart: TimeOfDay(hour: 13, minute: 0),
                                nightEnd: TimeOfDay(hour: 15, minute: 0),
                                transitionMinutes: 0)
        XCTAssertEqual(kelvin(schedule, 12, 59), 6500, accuracy: accuracy)
        XCTAssertEqual(kelvin(schedule, 13, 0), 2700, accuracy: accuracy)
        XCTAssertEqual(kelvin(schedule, 14, 59), 2700, accuracy: accuracy)
        XCTAssertEqual(kelvin(schedule, 15, 0), 6500, accuracy: accuracy)
        XCTAssertEqual(kelvin(schedule, 22, 0), 6500, accuracy: accuracy)
        XCTAssertEqual(kelvin(schedule, 2, 0), 6500, accuracy: accuracy)
    }

    func testSameDayWindowWithFade() {
        let schedule = Schedule(nightStart: TimeOfDay(hour: 13, minute: 0),
                                nightEnd: TimeOfDay(hour: 15, minute: 0),
                                transitionMinutes: 20)
        XCTAssertEqual(kelvin(schedule, 12, 50), 6500, accuracy: accuracy)
        XCTAssertEqual(kelvin(schedule, 13, 0), 4600, accuracy: accuracy)
        XCTAssertEqual(kelvin(schedule, 13, 10), 2700, accuracy: accuracy)
        XCTAssertEqual(kelvin(schedule, 14, 0), 2700, accuracy: accuracy)
        XCTAssertEqual(kelvin(schedule, 15, 0), 4600, accuracy: accuracy)
        XCTAssertEqual(kelvin(schedule, 15, 10), 6500, accuracy: accuracy)
    }

    // MARK: Fade wrapping around midnight

    func testFadeBeforeStartCanWrapPastMidnight() {
        let schedule = Schedule(nightStart: TimeOfDay(hour: 0, minute: 5),
                                nightEnd: TimeOfDay(hour: 6, minute: 0),
                                transitionMinutes: 30)
        // 23:55 is 10 minutes before the start: weight = (-10 + 15) / 30
        XCTAssertEqual(kelvin(schedule, 23, 55), 6500 - 3800.0 / 6, accuracy: accuracy)
        XCTAssertEqual(kelvin(schedule, 23, 40), 6500, accuracy: accuracy)
        XCTAssertEqual(kelvin(schedule, 1, 0), 2700, accuracy: accuracy)
    }

    func testFadeAfterEndCanWrapPastMidnight() {
        let schedule = Schedule(nightStart: TimeOfDay(hour: 20, minute: 0),
                                nightEnd: TimeOfDay(hour: 23, minute: 55),
                                transitionMinutes: 30)
        // 00:05 is 10 minutes after the end: weight = 1 - (10 + 15) / 30
        XCTAssertEqual(kelvin(schedule, 0, 5), 6500 - 3800.0 / 6, accuracy: accuracy)
        XCTAssertEqual(kelvin(schedule, 0, 30), 6500, accuracy: accuracy)
    }

    func testEmptyWindowIsAlwaysDay() {
        let t = TimeOfDay(hour: 9, minute: 0)
        let schedule = Schedule(nightStart: t, nightEnd: t, transitionMinutes: 0)
        for hour in [0, 6, 9, 12, 21] {
            XCTAssertEqual(kelvin(schedule, hour, 0), 6500, accuracy: accuracy)
        }
    }

    func testCustomKelvinRange() {
        let schedule = Schedule(dayKelvin: 5000, nightKelvin: 1200)
        XCTAssertEqual(kelvin(schedule, 12, 0), 5000, accuracy: accuracy)
        XCTAssertEqual(kelvin(schedule, 22, 0), 1200, accuracy: accuracy)
    }

    // MARK: DST

    func testUsesWallClockAcrossSpringForwardDST() {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let schedule = Schedule(transitionMinutes: 0)
        // 2026-03-08: clocks jump from 02:00 to 03:00.
        let threeAM = date(3, 0, calendar: newYork, month: 3, day: 8)
        let noon = date(12, 0, calendar: newYork, month: 3, day: 8)
        let evening = date(20, 0, calendar: newYork, month: 3, day: 8)
        let justBefore = date(19, 59, calendar: newYork, month: 3, day: 8)
        XCTAssertEqual(schedule.targetKelvin(at: threeAM, calendar: newYork), 2700, accuracy: accuracy)
        XCTAssertEqual(schedule.targetKelvin(at: noon, calendar: newYork), 6500, accuracy: accuracy)
        XCTAssertEqual(schedule.targetKelvin(at: justBefore, calendar: newYork), 6500, accuracy: accuracy)
        XCTAssertEqual(schedule.targetKelvin(at: evening, calendar: newYork), 2700, accuracy: accuracy)
    }

    func testUsesWallClockAcrossFallBackDST() {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let schedule = Schedule(transitionMinutes: 0)
        // 2026-11-01: 25-hour day; 07:00 wall clock is still the end of night.
        XCTAssertEqual(schedule.targetKelvin(at: date(6, 59, calendar: newYork, month: 11, day: 1),
                                             calendar: newYork), 2700, accuracy: accuracy)
        XCTAssertEqual(schedule.targetKelvin(at: date(7, 0, calendar: newYork, month: 11, day: 1),
                                             calendar: newYork), 6500, accuracy: accuracy)
    }

    func testTimeZoneOfCalendarDecidesWallClock() {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let schedule = Schedule(transitionMinutes: 0)
        let instant = date(12, 0) // 12:00 UTC == 21:00 in Tokyo
        XCTAssertEqual(schedule.targetKelvin(at: instant, calendar: calendar), 6500, accuracy: accuracy)
        XCTAssertEqual(schedule.targetKelvin(at: instant, calendar: tokyo), 2700, accuracy: accuracy)
    }
}
