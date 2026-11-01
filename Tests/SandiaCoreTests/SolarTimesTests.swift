import XCTest
@testable import SandiaCore

final class SolarTimesTests: XCTestCase {
    private let paris = TimeZone(identifier: "Europe/Paris")!

    // MARK: Helpers

    private func timeZone(named identifier: String) -> TimeZone {
        TimeZone(identifier: identifier)!
    }

    /// Local noon, so the day is unambiguous even on a DST change.
    private func localNoon(_ year: Int, _ month: Int, _ day: Int, in zone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    /// Minutes since local midnight.
    private func minutes(_ date: Date, in zone: TimeZone) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return date.timeIntervalSince(calendar.startOfDay(for: date)) / 60
    }

    private func times(_ latitude: Double, _ longitude: Double,
                       _ year: Int, _ month: Int, _ day: Int,
                       in zone: TimeZone) -> SolarTimes {
        solarTimes(latitude: latitude, longitude: longitude,
                   date: localNoon(year, month, day, in: zone), timeZone: zone)
    }

    /// NOAA equation of time in minutes at 00:00 UT, used only to locate the
    /// true solar noon independently of the production event code.
    private func equationOfTime(_ date: Date, in zone: TimeZone) -> Double {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = zone
        let parts = local.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = timeZone(named: "UTC")
        let midnight = utc.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day))!

        let julianDay = midnight.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let t = (julianDay - 2_451_545.0) / 36_525.0
        let degrees = Double.pi / 180

        let meanLongitude = (280.46646 + t * (36_000.76983 + t * 0.0003032))
            .truncatingRemainder(dividingBy: 360) * degrees
        let anomaly = (357.52911 + t * (35_999.05029 - 0.0001537 * t)) * degrees
        let eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let omega = (125.04 - 1934.136 * t) * degrees
        let meanObliquity = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let obliquity = (meanObliquity + 0.00256 * cos(omega)) * degrees
        let y = pow(tan(obliquity / 2), 2)

        let raw = y * sin(2 * meanLongitude)
            - 2 * eccentricity * sin(anomaly)
            + 4 * eccentricity * y * sin(anomaly) * cos(2 * meanLongitude)
            - 0.5 * y * y * sin(4 * meanLongitude)
            - 1.25 * eccentricity * eccentricity * sin(2 * anomaly)
        return 4 * (180 / Double.pi) * raw
    }

    /// Instant of true solar noon for the local date of `date`.
    private func solarNoon(_ date: Date, longitude: Double, in zone: TimeZone) -> Date {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = zone
        let parts = local.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = timeZone(named: "UTC")
        let midnight = utc.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day))!
        let solarNoonMinutes = 720 - 4 * longitude - equationOfTime(date, in: zone)
        return midnight.addingTimeInterval(solarNoonMinutes * 60)
    }

    // MARK: Paris

    func testParisSummerMatchesReference() throws {
        let result = times(48.8566, 2.3522, 2026, 6, 21, in: paris)
        let sunrise = try XCTUnwrap(result.sunrise)
        let sunset = try XCTUnwrap(result.sunset)
        let dawn = try XCTUnwrap(result.civilDawn)
        let dusk = try XCTUnwrap(result.civilDusk)

        // Published for Paris: 05:47, 21:58, civil 05:04 – 22:40 (CEST).
        XCTAssertEqual(minutes(sunrise, in: paris), 5 * 60 + 47, accuracy: 3)
        XCTAssertEqual(minutes(sunset, in: paris), 21 * 60 + 58, accuracy: 3)
        XCTAssertEqual(minutes(dawn, in: paris), 5 * 60 + 4, accuracy: 3)
        XCTAssertEqual(minutes(dusk, in: paris), 22 * 60 + 40, accuracy: 3)
        XCTAssertEqual(sunset.timeIntervalSince(sunrise) / 60, 16 * 60 + 11, accuracy: 3)
    }

    func testParisWinterMatchesReference() throws {
        let result = times(48.8566, 2.3522, 2026, 12, 21, in: paris)
        let sunrise = try XCTUnwrap(result.sunrise)
        let sunset = try XCTUnwrap(result.sunset)
        let dawn = try XCTUnwrap(result.civilDawn)
        let dusk = try XCTUnwrap(result.civilDusk)

        // Published for Paris: 08:41, 16:56, civil 08:04 – 17:33 (CET).
        XCTAssertEqual(minutes(sunrise, in: paris), 8 * 60 + 41, accuracy: 3)
        XCTAssertEqual(minutes(sunset, in: paris), 16 * 60 + 56, accuracy: 3)
        XCTAssertEqual(minutes(dawn, in: paris), 8 * 60 + 4, accuracy: 3)
        XCTAssertEqual(minutes(dusk, in: paris), 17 * 60 + 33, accuracy: 3)
        XCTAssertEqual(sunset.timeIntervalSince(sunrise) / 60, 8 * 60 + 15, accuracy: 3)
    }

    func testTwilightBracketsDaylight() throws {
        for month in [1, 4, 7, 10] {
            let result = times(48.8566, 2.3522, 2026, month, 15, in: paris)
            let dawn = try XCTUnwrap(result.civilDawn)
            let sunrise = try XCTUnwrap(result.sunrise)
            let sunset = try XCTUnwrap(result.sunset)
            let dusk = try XCTUnwrap(result.civilDusk)
            XCTAssertLessThan(dawn, sunrise)
            XCTAssertLessThan(sunrise, sunset)
            XCTAssertLessThan(sunset, dusk)
        }
    }

    // MARK: Equator

    func testEquatorHasTwelveHoursOfDay() throws {
        let utc = timeZone(named: "UTC")
        // 2026-03-20, equinox: the equation of time shifts noon, not the length.
        let result = times(0, 0, 2026, 3, 20, in: utc)
        let sunrise = try XCTUnwrap(result.sunrise)
        let sunset = try XCTUnwrap(result.sunset)

        XCTAssertEqual(minutes(sunrise, in: utc), 6 * 60 + 4, accuracy: 5)
        XCTAssertEqual(minutes(sunset, in: utc), 18 * 60 + 11, accuracy: 5)
        XCTAssertEqual(sunset.timeIntervalSince(sunrise) / 60, 12 * 60, accuracy: 8)
    }

    // MARK: High latitudes

    func testArcticPolarNightHasNoSunriseButCivilTwilight() throws {
        let oslo = timeZone(named: "Europe/Oslo")
        let result = times(69.6492, 18.9553, 2026, 12, 21, in: oslo) // Tromsø

        XCTAssertNil(result.sunrise)
        XCTAssertNil(result.sunset)

        // The sun stays below the horizon but still climbs above −6° near noon.
        let dawn = try XCTUnwrap(result.civilDawn)
        let dusk = try XCTUnwrap(result.civilDusk)
        XCTAssertLessThan(dawn, dusk)
        XCTAssertEqual(minutes(dawn, in: oslo), 9 * 60 + 31, accuracy: 5)
        XCTAssertEqual(minutes(dusk, in: oslo), 13 * 60 + 53, accuracy: 5)
    }

    func testArcticMidnightSunHasNoEvents() {
        let oslo = timeZone(named: "Europe/Oslo")
        let result = times(69.6492, 18.9553, 2026, 6, 21, in: oslo)

        XCTAssertNil(result.sunrise)
        XCTAssertNil(result.sunset)
        XCTAssertNil(result.civilDawn)
        XCTAssertNil(result.civilDusk)
    }

    func testSunriseAndTwilightAreIndependentlyOptional() throws {
        let oslo = timeZone(named: "Europe/Oslo")
        // Trondheim in June: the sun sets, but never drops to −6°.
        let result = times(63.43, 10.4, 2026, 6, 21, in: oslo)

        XCTAssertNotNil(try XCTUnwrap(result.sunrise))
        XCTAssertNotNil(try XCTUnwrap(result.sunset))
        XCTAssertNil(result.civilDawn)
        XCTAssertNil(result.civilDusk)
    }

    func testArcticCircleSolsticeIsHandledOnBothSides() {
        let helsinki = timeZone(named: "Europe/Helsinki")
        let summer = times(66.56, 25.0, 2026, 6, 21, in: helsinki)
        let winter = times(66.56, 25.0, 2026, 12, 21, in: helsinki)

        // Refraction still lifts the sun over the horizon in summer.
        XCTAssertNil(summer.sunrise)
        XCTAssertNil(summer.sunset)
        // In winter it rises only for a couple of hours.
        XCTAssertNotNil(winter.sunrise)
        XCTAssertNotNil(winter.sunset)
    }

    // MARK: Symmetry around solar noon

    func testEventsAreSymmetricAroundSolarNoon() throws {
        let cases: [(Double, Double, TimeZone, (Int, Int, Int))] = [
            (48.8566, 2.3522, paris, (2026, 6, 21)),
            (48.8566, 2.3522, paris, (2026, 12, 21)),
            (0, 0, timeZone(named: "UTC"), (2026, 3, 20)),
            (69.6492, 18.9553, timeZone(named: "Europe/Oslo"), (2026, 3, 20)),
        ]

        for (latitude, longitude, timeZone, components) in cases {
            let date = localNoon(components.0, components.1, components.2, in: timeZone)
            let result = solarTimes(latitude: latitude, longitude: longitude,
                                    date: date, timeZone: timeZone)
            let sunrise = try XCTUnwrap(result.sunrise)
            let sunset = try XCTUnwrap(result.sunset)
            let midpoint = sunrise.addingTimeInterval(sunset.timeIntervalSince(sunrise) / 2)
            let noon = solarNoon(date, longitude: longitude, in: timeZone)

            XCTAssertEqual(midpoint.timeIntervalSince(noon) / 60, 0, accuracy: 2,
                           "asymmetry at \(latitude), \(longitude) on \(components)")
        }
    }

    // MARK: Sunset over the year

    func testSunsetGetsLaterFromJanuaryToTheJuneSolstice() throws {
        var previous: Double?
        for offset in 0...175 { // Jan 1 … Jun 25
            let date = localNoon(2026, 1, 1, in: paris).addingTimeInterval(Double(offset) * 86_400)
            let result = solarTimes(latitude: 48.8566, longitude: 2.3522, date: date, timeZone: paris)
            let minutes = self.minutes(try XCTUnwrap(result.sunset), in: paris)
            if let previous {
                XCTAssertGreaterThanOrEqual(minutes, previous, "sunset went backwards on day \(offset)")
            }
            previous = minutes
        }
    }

    func testSunsetGetsEarlierFromTheJuneSolsticeToDecember() throws {
        var previous: Double?
        for offset in 176...344 { // Jun 26 … Dec 11
            let date = localNoon(2026, 1, 1, in: paris).addingTimeInterval(Double(offset) * 86_400)
            let result = solarTimes(latitude: 48.8566, longitude: 2.3522, date: date, timeZone: paris)
            let minutes = self.minutes(try XCTUnwrap(result.sunset), in: paris)
            if let previous {
                XCTAssertLessThanOrEqual(minutes, previous, "sunset went forwards on day \(offset)")
            }
            previous = minutes
        }
    }

    // MARK: Injected time zone

    func testTimeZoneChoosesTheCalendarDay() throws {
        // 20:00 UTC is still June 21 in Paris but already June 22 in Tokyo.
        let instant = localNoon(2026, 6, 21, in: timeZone(named: "UTC")).addingTimeInterval(8 * 3_600)
        let tokyo = timeZone(named: "Asia/Tokyo")
        let onParisDay = solarTimes(latitude: 35.6762, longitude: 139.6503,
                                    date: instant, timeZone: paris)
        let onTokyoDay = solarTimes(latitude: 35.6762, longitude: 139.6503,
                                    date: instant, timeZone: tokyo)
        let fromParis = try XCTUnwrap(onParisDay.sunrise)
        let fromTokyo = try XCTUnwrap(onTokyoDay.sunrise)

        var japanese = Calendar(identifier: .gregorian)
        japanese.timeZone = tokyo
        XCTAssertEqual(japanese.component(.day, from: fromParis), 21)
        XCTAssertEqual(japanese.component(.day, from: fromTokyo), 22)
        XCTAssertEqual(fromTokyo.timeIntervalSince(fromParis) / 3_600, 24, accuracy: 0.1)
    }

    func testSameInputsGiveSameInstants() {
        let date = localNoon(2026, 5, 1, in: paris)
        let first = solarTimes(latitude: 48.8566, longitude: 2.3522, date: date, timeZone: paris)
        let second = solarTimes(latitude: 48.8566, longitude: 2.3522, date: date, timeZone: paris)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.latitude, 48.8566)
        XCTAssertEqual(first.longitude, 2.3522)
    }
}
