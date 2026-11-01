import XCTest
@testable import SandiaCore

final class SolarScheduleTests: XCTestCase {
    private let paris: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    private let oslo: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo")!
        return calendar
    }()

    private let parisCoordinates = SolarCoordinates(latitude: 48.8566, longitude: 2.3522)
    private let tromso = SolarCoordinates(latitude: 69.6492, longitude: 18.9553)

    // MARK: Helpers

    private func moment(_ year: Int, _ month: Int, _ day: Int,
                        _ hour: Int, _ minute: Int = 0,
                        calendar: Calendar? = nil) -> Date {
        let cal = calendar ?? paris
        return cal.date(from: DateComponents(year: year, month: month, day: day,
                                             hour: hour, minute: minute))!
    }

    private func timeOfDay(_ date: Date, in calendar: Calendar) -> TimeOfDay {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    private func civilDusk(_ date: Date, _ coordinates: SolarCoordinates,
                           in calendar: Calendar) throws -> Date {
        try XCTUnwrap(solarTimes(latitude: coordinates.latitude,
                                 longitude: coordinates.longitude,
                                 date: date,
                                 timeZone: calendar.timeZone).civilDusk)
    }

    private func civilDawn(_ date: Date, _ coordinates: SolarCoordinates,
                           in calendar: Calendar) throws -> Date {
        try XCTUnwrap(solarTimes(latitude: coordinates.latitude,
                                 longitude: coordinates.longitude,
                                 date: date,
                                 timeZone: calendar.timeZone).civilDawn)
    }

    /// A solver that can be counted and scripted, without the real sun.
    private final class ScriptedSolver: @unchecked Sendable {
        private var responses: [SolarTimes]
        private(set) var callCount = 0

        init(_ responses: [SolarTimes]) {
            self.responses = responses
        }

        func next(_ coordinates: SolarCoordinates) -> SolarTimes {
            defer { callCount += 1 }
            guard !responses.isEmpty else { return SolarTimes(latitude: coordinates.latitude,
                                                              longitude: coordinates.longitude) }
            return responses.removeFirst()
        }

        var solver: SolarSchedule.Solver {
            { [self] _, coordinates, _ in next(coordinates) }
        }
    }

    // MARK: Dusk to the next morning's dawn

    func testWindowIsThisEveningsDuskAndTomorrowsDawn() throws {
        let window = try XCTUnwrap(SolarSchedule.window(at: moment(2026, 6, 21, 12),
                                                        coordinates: parisCoordinates,
                                                        calendar: paris))

        // Published for Paris on 21 June: civil dusk 22:40, civil dawn 05:04.
        XCTAssertEqual(Double(window.nightStart.minutesSinceMidnight), 22 * 60 + 40, accuracy: 1)
        XCTAssertEqual(Double(window.nightEnd.minutesSinceMidnight), 5 * 60 + 4, accuracy: 1)

        let nextDawn = try civilDawn(moment(2026, 6, 22, 12), parisCoordinates, in: paris)
        XCTAssertEqual(window.nightEnd, timeOfDay(nextDawn, in: paris))
    }

    /// Civil twilight moves by several minutes a day at high latitude, so today's
    /// dawn and tomorrow's dawn are distinguishable there.
    func testNightEndIsTomorrowsDawnNotTheOneAlreadyPast() throws {
        let day = moment(2026, 3, 1, 12, calendar: oslo)
        let window = try XCTUnwrap(SolarSchedule.window(at: day, coordinates: tromso, calendar: oslo))

        let todayDawn = timeOfDay(try civilDawn(day, tromso, in: oslo), in: oslo)
        let tomorrowDawn = timeOfDay(try civilDawn(moment(2026, 3, 2, 12, calendar: oslo), tromso, in: oslo),
                                     in: oslo)
        XCTAssertEqual(window.nightEnd, tomorrowDawn)
        XCTAssertNotEqual(window.nightEnd, todayDawn)

        // The night that began on 1 March still holds after midnight.
        let schedule = SolarSchedule.compose(window, fixed: Schedule(transitionMinutes: 0,
                                                                     dayKelvin: 6400,
                                                                     nightKelvin: 1900))
        XCTAssertEqual(schedule.targetKelvin(at: moment(2026, 3, 1, 23, 0, calendar: oslo),
                                             calendar: oslo), 1900, accuracy: 0.5)
        XCTAssertEqual(schedule.targetKelvin(at: moment(2026, 3, 2, 1, 0, calendar: oslo),
                                             calendar: oslo), 1900, accuracy: 0.5)
        XCTAssertEqual(schedule.targetKelvin(at: moment(2026, 3, 2, 12, 0, calendar: oslo),
                                             calendar: oslo), 6400, accuracy: 0.5)
    }

    func testNoonIsDayAndLateEveningIsNight() throws {
        let window = try XCTUnwrap(SolarSchedule.window(at: moment(2026, 12, 21, 12),
                                                        coordinates: parisCoordinates,
                                                        calendar: paris))
        let schedule = SolarSchedule.compose(window, fixed: Schedule(transitionMinutes: 30))
        let accuracy = 0.5

        XCTAssertEqual(schedule.targetKelvin(at: moment(2026, 12, 21, 12), calendar: paris),
                       6500, accuracy: accuracy)
        XCTAssertEqual(schedule.targetKelvin(at: moment(2026, 12, 21, 23), calendar: paris),
                       2700, accuracy: accuracy)
        XCTAssertEqual(schedule.targetKelvin(at: moment(2026, 12, 22, 3), calendar: paris),
                       2700, accuracy: accuracy)
        XCTAssertEqual(schedule.targetKelvin(at: moment(2026, 12, 22, 12), calendar: paris),
                       6500, accuracy: accuracy)
    }

    // MARK: Fallbacks

    func testFallsBackToFixedHoursWhenCivilTwilightNeverHappens() {
        // Tromsø at midsummer: no civil twilight at all, and no night to build.
        let fixed = Schedule(nightStart: TimeOfDay(hour: 22, minute: 30),
                             nightEnd: TimeOfDay(hour: 6, minute: 15),
                             transitionMinutes: 45,
                             dayKelvin: 6100,
                             nightKelvin: 1800)
        var cache = SolarScheduleCache()
        let noon = moment(2026, 6, 21, 12, calendar: oslo)

        XCTAssertEqual(cache.schedule(mode: .solar, coordinates: tromso, fixed: fixed,
                                      at: noon, calendar: oslo), fixed)
        // The missing window is remembered for the day: no retry every second.
        XCTAssertEqual(cache.schedule(mode: .solar, coordinates: tromso, fixed: fixed,
                                      at: noon.addingTimeInterval(3_600), calendar: oslo), fixed)
        XCTAssertEqual(cache.refreshCount, 1)
    }

    func testFallsBackWhenTheNextMorningHasNoDawn() {
        let coordinates = SolarCoordinates(latitude: 48.8566, longitude: 2.3522)
        let dusk = moment(2026, 6, 21, 22, 40)
        let scripted = ScriptedSolver([
            SolarTimes(latitude: coordinates.latitude, longitude: coordinates.longitude, civilDusk: dusk),
            SolarTimes(latitude: coordinates.latitude, longitude: coordinates.longitude)
        ])
        let fixed = Schedule(nightStart: TimeOfDay(hour: 21, minute: 15))
        var cache = SolarScheduleCache()

        let schedule = cache.schedule(mode: .solar, coordinates: coordinates, fixed: fixed,
                                      at: moment(2026, 6, 21, 12), calendar: paris,
                                      solver: scripted.solver)
        XCTAssertEqual(schedule, fixed)
    }

    func testFallsBackWhenThePairIsNotANight() {
        let coordinates = SolarCoordinates(latitude: 48.8566, longitude: 2.3522)
        let scripted = ScriptedSolver([
            SolarTimes(latitude: coordinates.latitude, longitude: coordinates.longitude,
                       civilDusk: moment(2026, 6, 21, 22, 0)),
            SolarTimes(latitude: coordinates.latitude, longitude: coordinates.longitude,
                       civilDawn: moment(2026, 6, 21, 5, 0))
        ])
        let fixed = Schedule()
        var cache = SolarScheduleCache()

        XCTAssertEqual(cache.schedule(mode: .solar, coordinates: coordinates, fixed: fixed,
                                      at: moment(2026, 6, 21, 12), calendar: paris,
                                      solver: scripted.solver), fixed)
    }

    func testFadeAndKelvinsAlwaysComeFromTheUsersHours() {
        let coordinates = SolarCoordinates(latitude: 48.8566, longitude: 2.3522)
        let dusk = moment(2026, 6, 21, 22, 40)
        let dawn = moment(2026, 6, 22, 5, 4)
        let scripted = ScriptedSolver([
            SolarTimes(latitude: coordinates.latitude, longitude: coordinates.longitude, civilDusk: dusk),
            SolarTimes(latitude: coordinates.latitude, longitude: coordinates.longitude, civilDawn: dawn)
        ])
        let fixed = Schedule(transitionMinutes: 42, dayKelvin: 5200, nightKelvin: 2100)
        var cache = SolarScheduleCache()

        let schedule = cache.schedule(mode: .solar, coordinates: coordinates, fixed: fixed,
                                      at: moment(2026, 6, 21, 12), calendar: paris,
                                      solver: scripted.solver)

        XCTAssertEqual(schedule.nightStart, TimeOfDay(hour: 22, minute: 40))
        XCTAssertEqual(schedule.nightEnd, TimeOfDay(hour: 5, minute: 4))
        XCTAssertEqual(schedule.transitionMinutes, 42)
        XCTAssertEqual(schedule.dayKelvin, 5200)
        XCTAssertEqual(schedule.nightKelvin, 2100)
    }

    // MARK: Cache

    func testSolarComputationHappensOncePerDayAndCoordinates() {
        var cache = SolarScheduleCache()
        let fixed = Schedule()
        let startOfDay = moment(2026, 6, 21, 0)

        let first = cache.schedule(mode: .solar, coordinates: parisCoordinates, fixed: fixed,
                                   at: startOfDay, calendar: paris)
        XCTAssertEqual(cache.refreshCount, 1)

        // `resolve` runs every second: the same day must reuse the cached window.
        for second in 0..<600 {
            let instant = startOfDay.addingTimeInterval(Double(second))
            let schedule = cache.schedule(mode: .solar, coordinates: parisCoordinates, fixed: fixed,
                                          at: instant, calendar: paris)
            XCTAssertEqual(schedule, first)
        }
        XCTAssertEqual(cache.refreshCount, 1)

        // A new calendar day recomputes once, then stays cached.
        let nextDay = startOfDay.addingTimeInterval(24 * 3_600)
        _ = cache.schedule(mode: .solar, coordinates: parisCoordinates, fixed: fixed,
                           at: nextDay, calendar: paris)
        _ = cache.schedule(mode: .solar, coordinates: parisCoordinates, fixed: fixed,
                           at: nextDay.addingTimeInterval(600), calendar: paris)
        XCTAssertEqual(cache.refreshCount, 2)

        // New coordinates recompute, and so do the previous ones afterwards
        // (a single entry is kept on purpose).
        _ = cache.schedule(mode: .solar, coordinates: tromso, fixed: fixed,
                           at: nextDay, calendar: paris)
        XCTAssertEqual(cache.refreshCount, 3)
    }

    // MARK: Mode switch

    func testUsableCoordinatesDecideBetweenSolarAndFixedHours() {
        let fixed = Schedule()
        let noon = moment(2026, 6, 21, 12)
        var cache = SolarScheduleCache()

        let solar = cache.schedule(mode: .solar, coordinates: parisCoordinates, fixed: fixed,
                                   at: noon, calendar: paris)
        XCTAssertEqual(solar.nightStart, TimeOfDay(hour: 22, minute: 40))
        let solarRefresh = cache.refreshCount

        XCTAssertEqual(cache.schedule(mode: .fixed, coordinates: parisCoordinates, fixed: fixed,
                                      at: noon, calendar: paris), fixed)
        XCTAssertEqual(cache.schedule(mode: .solar, coordinates: nil, fixed: fixed,
                                      at: noon, calendar: paris), fixed)
        XCTAssertEqual(cache.schedule(mode: .solar,
                                      coordinates: SolarCoordinates(latitude: 95, longitude: 2),
                                      fixed: fixed, at: noon, calendar: paris), fixed)
        XCTAssertEqual(cache.schedule(mode: .solar,
                                      coordinates: SolarCoordinates(latitude: .nan, longitude: 2),
                                      fixed: fixed, at: noon, calendar: paris), fixed)
        XCTAssertEqual(cache.refreshCount, solarRefresh,
                       "a fixed or unusable location must not compute the sun")

        // Back to solar within the same day: still the cached computation.
        XCTAssertEqual(cache.schedule(mode: .solar, coordinates: parisCoordinates, fixed: fixed,
                                      at: noon, calendar: paris), solar)
        XCTAssertEqual(cache.refreshCount, solarRefresh)
    }

    func testCoordinateRanges() {
        XCTAssertTrue(SolarCoordinates(latitude: 0, longitude: 0).isUsable)
        XCTAssertTrue(SolarCoordinates(latitude: 90, longitude: -180).isUsable)
        XCTAssertTrue(SolarCoordinates(latitude: -90, longitude: 180).isUsable)
        XCTAssertFalse(SolarCoordinates(latitude: 90.1, longitude: 0).isUsable)
        XCTAssertFalse(SolarCoordinates(latitude: 0, longitude: 180.5).isUsable)
        XCTAssertFalse(SolarCoordinates(latitude: .infinity, longitude: 0).isUsable)
        XCTAssertFalse(SolarCoordinates(latitude: 0, longitude: .nan).isUsable)
    }

    // MARK: Dated manual override

    func testManualOverrideAppliesThenExpires() {
        let schedule = Schedule(transitionMinutes: 0, dayKelvin: 6400, nightKelvin: 2200)
        let state = SandiaState(schedule: schedule)
        let base = state.resolve(at: moment(2026, 6, 21, 23))
        XCTAssertEqual(base.kelvin ?? 0, 2200, accuracy: 0.5)

        let until = moment(2026, 6, 22, 1)
        let override = ManualOverride(kelvin: 3400, until: until)

        let applied = override.applied(to: base, at: moment(2026, 6, 22, 0, 30))
        XCTAssertEqual(applied.mode, .scheduled)
        XCTAssertEqual(applied.kelvin ?? 0, 3400, accuracy: 0.5)
        XCTAssertEqual(applied.rgb, ColorTemperature.rgb(kelvin: 3400))

        // At the deadline it is over.
        XCTAssertFalse(override.isActive(at: until))
        XCTAssertEqual(override.applied(to: base, at: until), base)

        // The stored curve is never edited by an override.
        XCTAssertEqual(schedule.dayKelvin, 6400)
        XCTAssertEqual(schedule.nightKelvin, 2200)
    }

    func testManualOverrideKeepsTheHigherPriorities() {
        let override = ManualOverride(kelvin: 3400, until: moment(2026, 6, 22, 1))
        let evening = moment(2026, 6, 21, 23)
        var state = SandiaState()

        state.isEnabled = false
        XCTAssertEqual(override.applied(to: state.resolve(at: evening), at: evening).mode, .disabled)

        state.isEnabled = true
        state.pausedUntil = evening.addingTimeInterval(3_600)
        XCTAssertEqual(override.applied(to: state.resolve(at: evening), at: evening).mode, .paused)

        state.pausedUntil = nil
        state.isDarkroom = true
        XCTAssertEqual(override.applied(to: state.resolve(at: evening), at: evening).mode, .darkroom)
    }
}
