import Foundation

/// Sunrise, sunset and civil twilight for one calendar day, computed locally
/// with the NOAA solar position algorithm. Nothing here touches the network or
/// a system location API.
///
/// Every event is optional. At high latitudes the sun can stay above the
/// horizon all day (midnight sun) or below it all day (polar night): that is
/// `|declination| > 90° − |latitude|`, and the NOAA hour angle then has no
/// solution. The affected events are `nil` — each one independently, since
/// civil twilight can still exist on a day without sunrise. Callers are
/// expected to fall back to fixed clock hours in that case.
public struct SolarTimes: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    /// Sun centre crossing the horizon, refraction included (zenith 90.833°).
    public let sunrise: Date?
    public let sunset: Date?

    /// Sun centre at −6°, the civil twilight boundaries (zenith 96°).
    public let civilDawn: Date?
    public let civilDusk: Date?

    public init(latitude: Double,
                longitude: Double,
                sunrise: Date? = nil,
                sunset: Date? = nil,
                civilDawn: Date? = nil,
                civilDusk: Date? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.sunrise = sunrise
        self.sunset = sunset
        self.civilDawn = civilDawn
        self.civilDusk = civilDusk
    }
}

/// Pure and stateless: the same inputs always give the same instants.
///
/// `timeZone` decides which calendar day `date` belongs to; the Gregorian
/// calendar used for that is built from it, never from `TimeZone.current`.
/// `longitude` is positive east of Greenwich.
public func solarTimes(latitude: Double,
                       longitude: Double,
                       date: Date,
                       timeZone: TimeZone) -> SolarTimes {
    let dayStart = SolarMath.startOfDayJulianDay(for: date, timeZone: timeZone)
    return SolarTimes(
        latitude: latitude,
        longitude: longitude,
        sunrise: SolarMath.event(zenith: 90.833, rising: true,
                                 dayStartJulianDay: dayStart,
                                 latitude: latitude, longitude: longitude),
        sunset: SolarMath.event(zenith: 90.833, rising: false,
                                dayStartJulianDay: dayStart,
                                latitude: latitude, longitude: longitude),
        civilDawn: SolarMath.event(zenith: 96, rising: true,
                                   dayStartJulianDay: dayStart,
                                   latitude: latitude, longitude: longitude),
        civilDusk: SolarMath.event(zenith: 96, rising: false,
                                   dayStartJulianDay: dayStart,
                                   latitude: latitude, longitude: longitude)
    )
}

// MARK: - NOAA solar position

private enum SolarMath {
    static let radiansPerDegree = Double.pi / 180
    static let degreesPerRadian = 180 / Double.pi

    /// Julian day at 00:00 UT of the local calendar date holding `date`.
    static func startOfDayJulianDay(for date: Date, timeZone: TimeZone) -> Double {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        let parts = local.dateComponents([.year, .month, .day], from: date)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              let midnight = utc.date(from: DateComponents(year: year, month: month, day: day)) else {
            return date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        }
        return midnight.timeIntervalSince1970 / 86_400 + 2_440_587.5
    }

    struct SunPosition {
        /// Radians.
        let declination: Double
        /// Minutes; apparent solar time minus mean solar time.
        let equationOfTime: Double
    }

    /// NOAA solar position at a Julian day (UT).
    static func position(julianDay: Double) -> SunPosition {
        let t = (julianDay - 2_451_545.0) / 36_525.0

        let meanLongitude = normalize(280.46646 + t * (36_000.76983 + t * 0.0003032))
        let meanAnomaly = 357.52911 + t * (35_999.05029 - 0.0001537 * t)
        let eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let anomaly = meanAnomaly * radiansPerDegree

        let center = sin(anomaly) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(2 * anomaly) * (0.019993 - 0.000101 * t)
            + sin(3 * anomaly) * 0.000289

        let omega = (125.04 - 1934.136 * t) * radiansPerDegree
        let apparentLongitude = (meanLongitude + center - 0.00569 - 0.00478 * sin(omega)) * radiansPerDegree
        let meanObliquity = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let obliquity = (meanObliquity + 0.00256 * cos(omega)) * radiansPerDegree

        let declination = asin(sin(obliquity) * sin(apparentLongitude))

        let y = pow(tan(obliquity / 2), 2)
        let l0 = meanLongitude * radiansPerDegree
        let equationOfTime = 4 * degreesPerRadian * (
            y * sin(2 * l0)
            - 2 * eccentricity * sin(anomaly)
            + 4 * eccentricity * y * sin(anomaly) * cos(2 * l0)
            - 0.5 * y * y * sin(4 * l0)
            - 1.25 * eccentricity * eccentricity * sin(2 * anomaly)
        )

        return SunPosition(declination: declination, equationOfTime: equationOfTime)
    }

    /// Hour angle in degrees, or `nil` when the sun stays above or below the
    /// requested zenith for the whole day.
    static func hourAngle(zenith: Double, latitude: Double, declination: Double) -> Double? {
        let lat = latitude * radiansPerDegree
        let denominator = cos(lat) * cos(declination)
        guard abs(denominator) > 1e-12 else { return nil }

        let cosH = (cos(zenith * radiansPerDegree) - sin(lat) * sin(declination)) / denominator
        guard cosH >= -1, cosH <= 1 else { return nil }
        return acos(cosH) * degreesPerRadian
    }

    /// Julian day of an event, or `nil` when it does not happen that day.
    ///
    /// The sun position is re-evaluated at the estimate: using the day's noon
    /// alone leaves up to two minutes of error, because the declination moves
    /// while the event approaches.
    static func event(zenith: Double,
                      rising: Bool,
                      dayStartJulianDay: Double,
                      latitude: Double,
                      longitude: Double) -> Date? {
        var estimate = dayStartJulianDay + 0.5
        for _ in 0..<2 {
            let sun = position(julianDay: estimate)
            guard let hourAngle = hourAngle(zenith: zenith,
                                            latitude: latitude,
                                            declination: sun.declination) else { return nil }
            let solarNoonMinutes = 720 - 4 * longitude - sun.equationOfTime
            let eventMinutes = solarNoonMinutes + (rising ? -4 : 4) * hourAngle
            estimate = dayStartJulianDay + eventMinutes / 1_440
        }
        return Date(timeIntervalSince1970: (estimate - 2_440_587.5) * 86_400)
    }

    /// Wraps an angle in degrees into [0, 360).
    static func normalize(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value < 0 { value += 360 }
        return value
    }
}
