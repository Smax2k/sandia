import Foundation

/// Which clock drives the nightly window.
///
/// `.fixed` is the historical behaviour: the user's wall-clock hours.
/// `.solar` follows civil twilight at the coordinates entered by hand; when no
/// usable coordinate is stored, callers must fall back to `.fixed`.
public enum ScheduleMode: String, CaseIterable, Equatable, Sendable {
    case fixed
    case solar
}

/// A location entered by hand. Deliberately no CoreLocation: Sandia never asks
/// the system where it is.
public struct SolarCoordinates: Equatable, Sendable {
    /// Positive north.
    public var latitude: Double
    /// Positive east of Greenwich.
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// In range and finite. Anything else cannot drive a solar computation and
    /// falls back to fixed hours.
    public var isUsable: Bool {
        latitude.isFinite && longitude.isFinite
            && latitude >= -90 && latitude <= 90
            && longitude >= -180 && longitude <= 180
    }
}

/// The nightly window read from civil twilight: dusk to the next morning's dawn,
/// the shape `Schedule` understands.
public struct SolarWindow: Equatable, Sendable {
    public let nightStart: TimeOfDay
    public let nightEnd: TimeOfDay

    public init(nightStart: TimeOfDay, nightEnd: TimeOfDay) {
        self.nightStart = nightStart
        self.nightEnd = nightEnd
    }
}

/// Turns solar events into a nightly window, and composes the final `Schedule`.
///
/// The window is always "this evening's dusk → the next morning's dawn", never
/// this morning's dawn: a dawn already past would make every resolution after
/// midnight point at the wrong boundary.
public enum SolarSchedule {
    /// Signature of the solar computation, injectable so a caller (and a test)
    /// can count or replace it.
    public typealias Solver = @Sendable (Date, SolarCoordinates, TimeZone) -> SolarTimes

    /// The real NOAA computation from `SolarTimes.swift`.
    public static let defaultSolver: Solver = { date, coordinates, timeZone in
        solarTimes(latitude: coordinates.latitude,
                   longitude: coordinates.longitude,
                   date: date,
                   timeZone: timeZone)
    }

    /// The window for the calendar day holding `date`, or nil when an event is
    /// missing (polar day or night) or the pair is not a coherent night.
    public static func window(at date: Date,
                              coordinates: SolarCoordinates,
                              calendar: Calendar = .current,
                              solver: Solver = defaultSolver) -> SolarWindow? {
        guard coordinates.isUsable else { return nil }

        let timeZone = calendar.timeZone
        guard let dusk = solver(date, coordinates, timeZone).civilDusk else { return nil }
        guard let tomorrow = calendar.date(byAdding: .day, value: 1,
                                           to: calendar.startOfDay(for: date)) else { return nil }
        guard let nextDawn = solver(tomorrow, coordinates, timeZone).civilDawn else { return nil }
        // A dusk after the following dawn is not a night the clock can express.
        guard nextDawn > dusk else { return nil }

        return SolarWindow(nightStart: timeOfDay(dusk, in: calendar),
                           nightEnd: timeOfDay(nextDawn, in: calendar))
    }

    /// Solar window when there is one, the user's hours otherwise. The fade and
    /// both temperatures are always the user's choice.
    static func compose(_ window: SolarWindow?, fixed: Schedule) -> Schedule {
        guard let window else { return fixed }
        return Schedule(nightStart: window.nightStart,
                        nightEnd: window.nightEnd,
                        transitionMinutes: fixed.transitionMinutes,
                        dayKelvin: fixed.dayKelvin,
                        nightKelvin: fixed.nightKelvin)
    }

    /// Truncates to the minute. Rounding up would turn 23:59:40 into 00:00 and
    /// break the wrap-around ordering the schedule relies on.
    private static func timeOfDay(_ date: Date, in calendar: Calendar) -> TimeOfDay {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = min(max(parts.hour ?? 0, 0), 23)
        let minute = min(max(parts.minute ?? 0, 0), 59)
        return TimeOfDay(hour: hour, minute: minute)
    }
}

/// Keeps the solar computation out of the per-second path.
///
/// `resolve` runs every second; the solar events only change when the calendar
/// day or the coordinates change, so the window is computed once per
/// (day, coordinates) pair. A day without a usable window is remembered too:
/// polar night must not retry the computation on every tick.
public struct SolarScheduleCache: Sendable {
    private struct Key: Equatable {
        let day: Date
        let coordinates: SolarCoordinates
    }

    private struct Entry {
        let key: Key
        let window: SolarWindow?
    }

    private var entry: Entry?

    /// Number of solar computations performed, i.e. cache refreshes. Read by
    /// tests to prove `resolve` does not recompute.
    public private(set) var refreshCount = 0

    public init() {}

    /// Effective schedule for `date`: solar twilight in `.solar` mode with
    /// usable coordinates, the user's fixed hours in every other case.
    public mutating func schedule(mode: ScheduleMode,
                                  coordinates: SolarCoordinates?,
                                  fixed: Schedule,
                                  at date: Date,
                                  calendar: Calendar = .current,
                                  solver: SolarSchedule.Solver = SolarSchedule.defaultSolver) -> Schedule {
        guard mode == .solar, let coordinates, coordinates.isUsable else { return fixed }

        let key = Key(day: calendar.startOfDay(for: date), coordinates: coordinates)
        let window: SolarWindow?
        if let entry, entry.key == key {
            window = entry.window
        } else {
            refreshCount += 1
            window = SolarSchedule.window(at: date, coordinates: coordinates,
                                          calendar: calendar, solver: solver)
            entry = Entry(key: key, window: window)
        }
        return SolarSchedule.compose(window, fixed: fixed)
    }
}

/// A dated manual temperature. It stacks on the curve for a while and never
/// edits the schedule itself: `dayKelvin` and `nightKelvin` stay untouched.
public struct ManualOverride: Equatable, Sendable {
    public var kelvin: Double
    /// The instant the override stops applying; it is active strictly before it.
    public var until: Date

    public init(kelvin: Double, until: Date) {
        self.kelvin = kelvin
        self.until = until
    }

    public func isActive(at date: Date) -> Bool {
        date < until
    }

    /// Applies on a scheduled look only: disabled, paused and darkroom keep the
    /// priority they already have in `SandiaState.resolve`.
    public func applied(to state: ResolvedState, at date: Date) -> ResolvedState {
        guard state.mode == .scheduled, isActive(at: date), kelvin.isFinite else { return state }
        return ResolvedState(mode: .scheduled,
                             rgb: ColorTemperature.rgb(kelvin: kelvin),
                             kelvin: kelvin)
    }
}
