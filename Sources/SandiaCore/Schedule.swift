import Foundation

/// A wall-clock time of day (no date, no time zone).
public struct TimeOfDay: Equatable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public var minutesSinceMidnight: Int { hour * 60 + minute }
}

/// Fixed clock-time schedule: warm between `nightStart` and `nightEnd`, with a
/// linear fade of `transitionMinutes` centred on each boundary.
public struct Schedule: Equatable, Sendable {
    public var nightStart: TimeOfDay
    public var nightEnd: TimeOfDay
    public var transitionMinutes: Int
    public var dayKelvin: Double
    public var nightKelvin: Double

    public init(nightStart: TimeOfDay = TimeOfDay(hour: 20, minute: 0),
                nightEnd: TimeOfDay = TimeOfDay(hour: 7, minute: 0),
                transitionMinutes: Int = 30,
                dayKelvin: Double = 6500,
                nightKelvin: Double = 2700) {
        self.nightStart = nightStart
        self.nightEnd = nightEnd
        self.transitionMinutes = transitionMinutes
        self.dayKelvin = dayKelvin
        self.nightKelvin = nightKelvin
    }

    private static let minutesPerDay = 1440.0

    /// 0 = full day, 1 = full night.
    public func nightWeight(at date: Date, calendar: Calendar = .current) -> Double {
        let parts = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let now = Double(parts.hour ?? 0) * 60
            + Double(parts.minute ?? 0)
            + Double(parts.second ?? 0) / 60
            + Double(parts.nanosecond ?? 0) / 60e9

        let start = Double(nightStart.minutesSinceMidnight)
        let end = Double(nightEnd.minutesSinceMidnight)
        guard start != end else { return 0 }

        let inside = start < end ? (now >= start && now < end) : (now >= start || now < end)
        let fade = Double(max(0, transitionMinutes))
        guard fade > 0 else { return inside ? 1 : 0 }

        let half = fade / 2
        let sinceStart = Self.circularDifference(now - start)
        let sinceEnd = Self.circularDifference(now - end)
        let nearStart = abs(sinceStart) < half
        let nearEnd = abs(sinceEnd) < half

        let rampUp = (sinceStart + half) / fade
        let rampDown = 1 - (sinceEnd + half) / fade
        switch (nearStart, nearEnd) {
        case (true, true): return min(rampUp, rampDown)
        case (true, false): return rampUp
        case (false, true): return rampDown
        case (false, false): return inside ? 1 : 0
        }
    }

    public func targetKelvin(at date: Date, calendar: Calendar = .current) -> Double {
        let weight = nightWeight(at: date, calendar: calendar)
        return dayKelvin + (nightKelvin - dayKelvin) * weight
    }

    /// Wraps a minute difference into [-720, 720).
    private static func circularDifference(_ difference: Double) -> Double {
        let half = minutesPerDay / 2
        var wrapped = (difference + half).truncatingRemainder(dividingBy: minutesPerDay)
        if wrapped < 0 { wrapped += minutesPerDay }
        return wrapped - half
    }
}
