import Foundation

/// What the display should currently look like.
public struct ResolvedState: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case disabled
        case paused
        case darkroom
        case scheduled
    }

    public var mode: Mode
    /// Final per-channel multiplier, brightness included.
    public var rgb: RGB
    /// Colour temperature in effect; nil for disabled, paused and darkroom.
    public var kelvin: Double?

    public init(mode: Mode, rgb: RGB, kelvin: Double? = nil) {
        self.mode = mode
        self.rgb = rgb
        self.kelvin = kelvin
    }
}

/// User intent. `resolve` applies the priority:
/// disabled, then paused, then darkroom, then the schedule.
public struct SandiaState: Equatable, Sendable {
    public var isEnabled: Bool
    public var pausedUntil: Date?
    public var isDarkroom: Bool
    public var darkroomBrightness: Double
    public var schedule: Schedule

    public init(isEnabled: Bool = true,
                pausedUntil: Date? = nil,
                isDarkroom: Bool = false,
                darkroomBrightness: Double = 0.7,
                schedule: Schedule = Schedule()) {
        self.isEnabled = isEnabled
        self.pausedUntil = pausedUntil
        self.isDarkroom = isDarkroom
        self.darkroomBrightness = darkroomBrightness
        self.schedule = schedule
    }

    public func resolve(at date: Date, calendar: Calendar = .current) -> ResolvedState {
        guard isEnabled else {
            return ResolvedState(mode: .disabled, rgb: .neutral, kelvin: nil)
        }
        if let pausedUntil, date < pausedUntil {
            return ResolvedState(mode: .paused, rgb: .neutral, kelvin: nil)
        }
        if isDarkroom {
            let brightness = min(max(darkroomBrightness, 0), 1)
            return ResolvedState(mode: .darkroom,
                                 rgb: RGB(red: 1, green: 0, blue: 0).scaled(by: brightness),
                                 kelvin: nil)
        }
        let kelvin = schedule.targetKelvin(at: date, calendar: calendar)
        return ResolvedState(mode: .scheduled, rgb: ColorTemperature.rgb(kelvin: kelvin), kelvin: kelvin)
    }
}
