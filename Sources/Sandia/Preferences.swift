import Foundation
import SandiaCore

/// UserDefaults-backed settings. Observable so SwiftUI and the engine react to edits.
final class Preferences: ObservableObject {
    private let defaults: UserDefaults

    @Published var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: Key.enabled) } }
    @Published var isDarkroom: Bool { didSet { defaults.set(isDarkroom, forKey: Key.darkroom) } }
    @Published var pausedUntil: Date? {
        didSet {
            if let pausedUntil {
                defaults.set(pausedUntil, forKey: Key.pausedUntil)
            } else {
                defaults.removeObject(forKey: Key.pausedUntil)
            }
        }
    }
    @Published var nightStart: TimeOfDay { didSet { defaults.set(nightStart.minutesSinceMidnight, forKey: Key.nightStart) } }
    @Published var nightEnd: TimeOfDay { didSet { defaults.set(nightEnd.minutesSinceMidnight, forKey: Key.nightEnd) } }
    @Published var transitionMinutes: Int { didSet { defaults.set(transitionMinutes, forKey: Key.transition) } }
    @Published var dayKelvin: Double { didSet { defaults.set(dayKelvin, forKey: Key.dayKelvin) } }
    @Published var nightKelvin: Double { didSet { defaults.set(nightKelvin, forKey: Key.nightKelvin) } }
    @Published var darkroomBrightness: Double { didSet { defaults.set(darkroomBrightness, forKey: Key.darkroomBrightness) } }

    /// Fixed hours or civil twilight. Stored as its raw value.
    @Published var scheduleMode: ScheduleMode {
        didSet { defaults.set(scheduleMode.rawValue, forKey: Key.scheduleMode) }
    }
    /// Hand-entered location, only meaningful in `.solar` mode.
    @Published var latitude: Double? { didSet { write(latitude, forKey: Key.latitude) } }
    @Published var longitude: Double? { didSet { write(longitude, forKey: Key.longitude) } }

    /// Dated manual temperature: stacks on the curve until `manualUntil`.
    @Published var manualKelvin: Double? { didSet { write(manualKelvin, forKey: Key.manualKelvin) } }
    @Published var manualUntil: Date? { didSet { write(manualUntil, forKey: Key.manualUntil) } }

    /// Solar events change once a day at most; `resolve` runs every second.
    private var solarCache = SolarScheduleCache()

    private enum Key {
        static let enabled = "enabled"
        static let darkroom = "darkroom"
        static let pausedUntil = "pausedUntil"
        static let nightStart = "nightStartMinutes"
        static let nightEnd = "nightEndMinutes"
        static let transition = "transitionMinutes"
        static let dayKelvin = "dayKelvin"
        static let nightKelvin = "nightKelvin"
        static let darkroomBrightness = "darkroomBrightness"
        static let scheduleMode = "scheduleMode"
        static let latitude = "latitude"
        static let longitude = "longitude"
        static let manualKelvin = "manualKelvin"
        static let manualUntil = "manualUntil"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let fallback = Schedule()

        func timeOfDay(_ key: String, default value: TimeOfDay) -> TimeOfDay {
            guard let minutes = defaults.object(forKey: key) as? Int else { return value }
            let clamped = min(max(minutes, 0), 1439)
            return TimeOfDay(hour: clamped / 60, minute: clamped % 60)
        }

        isEnabled = defaults.object(forKey: Key.enabled) as? Bool ?? true
        isDarkroom = defaults.object(forKey: Key.darkroom) as? Bool ?? false
        pausedUntil = defaults.object(forKey: Key.pausedUntil) as? Date
        nightStart = timeOfDay(Key.nightStart, default: fallback.nightStart)
        nightEnd = timeOfDay(Key.nightEnd, default: fallback.nightEnd)
        transitionMinutes = defaults.object(forKey: Key.transition) as? Int ?? fallback.transitionMinutes
        dayKelvin = defaults.object(forKey: Key.dayKelvin) as? Double ?? fallback.dayKelvin
        nightKelvin = defaults.object(forKey: Key.nightKelvin) as? Double ?? fallback.nightKelvin
        darkroomBrightness = defaults.object(forKey: Key.darkroomBrightness) as? Double ?? 0.7
        scheduleMode = (defaults.string(forKey: Key.scheduleMode)).flatMap(ScheduleMode.init(rawValue:)) ?? .fixed
        latitude = defaults.object(forKey: Key.latitude) as? Double
        longitude = defaults.object(forKey: Key.longitude) as? Double
        manualKelvin = defaults.object(forKey: Key.manualKelvin) as? Double
        manualUntil = defaults.object(forKey: Key.manualUntil) as? Date
    }

    private func write(_ value: Double?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func write(_ value: Date?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// The user's own hours, used in `.fixed` mode and as the fallback whenever
    /// the sun gives no usable event.
    var fixedSchedule: Schedule {
        Schedule(nightStart: nightStart,
                 nightEnd: nightEnd,
                 transitionMinutes: transitionMinutes,
                 dayKelvin: dayKelvin,
                 nightKelvin: nightKelvin)
    }

    /// Coordinates only when both were entered and are in range.
    var solarCoordinates: SolarCoordinates? {
        guard let latitude, let longitude else { return nil }
        let coordinates = SolarCoordinates(latitude: latitude, longitude: longitude)
        return coordinates.isUsable ? coordinates : nil
    }

    /// Effective schedule at `date`; cached solar computation.
    func schedule(at date: Date) -> Schedule {
        solarCache.schedule(mode: scheduleMode,
                            coordinates: solarCoordinates,
                            fixed: fixedSchedule,
                            at: date)
    }

    /// The manual temperature, only while it is armed.
    var manualOverride: ManualOverride? {
        guard let manualKelvin, let manualUntil else { return nil }
        return ManualOverride(kelvin: manualKelvin, until: manualUntil)
    }

    /// Effective state at `date`, schedule included.
    func state(at date: Date) -> SandiaState {
        SandiaState(isEnabled: isEnabled,
                  pausedUntil: pausedUntil,
                  isDarkroom: isDarkroom,
                  darkroomBrightness: darkroomBrightness,
                  schedule: schedule(at: date))
    }

    var state: SandiaState {
        state(at: Date())
    }
}
