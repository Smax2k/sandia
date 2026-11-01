import Foundation

/// A per-channel colour multiplier in the 0...1 range.
public struct RGB: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// No tint: leaves the display untouched.
    public static let neutral = RGB(red: 1, green: 1, blue: 1)

    public func scaled(by factor: Double) -> RGB {
        RGB(red: red * factor, green: green * factor, blue: blue * factor)
    }

    /// Largest per-channel difference between two values.
    public func maxDistance(to other: RGB) -> Double {
        max(abs(red - other.red), abs(green - other.green), abs(blue - other.blue))
    }

    public func interpolated(to other: RGB, fraction: Double) -> RGB {
        RGB(red: red + (other.red - red) * fraction,
            green: green + (other.green - green) * fraction,
            blue: blue + (other.blue - blue) * fraction)
    }
}

/// Kelvin to RGB multiplier, using Tanner Helland's blackbody approximation,
/// normalised so that 6500K is exactly neutral (1, 1, 1).
public enum ColorTemperature {
    public static let minimumKelvin = 1000.0
    public static let maximumKelvin = 6500.0

    public static func rgb(kelvin: Double) -> RGB {
        let clamped = min(max(kelvin, minimumKelvin), maximumKelvin)
        let value = raw(kelvin: clamped)
        let reference = raw(kelvin: maximumKelvin)
        return RGB(red: unit(value.red / reference.red),
                   green: unit(value.green / reference.green),
                   blue: unit(value.blue / reference.blue))
    }

    private static func unit(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    /// Un-normalised channels on a 0...255 scale.
    private static func raw(kelvin: Double) -> (red: Double, green: Double, blue: Double) {
        let t = kelvin / 100

        let red: Double
        let green: Double
        if t <= 66 {
            red = 255
            green = 99.4708025861 * log(t) - 161.1195681661
        } else {
            red = 329.698727446 * pow(t - 60, -0.1332047592)
            green = 288.1221695283 * pow(t - 60, -0.0755148492)
        }

        let blue: Double
        if t >= 66 {
            blue = 255
        } else if t <= 19 {
            blue = 0
        } else {
            blue = 138.5177312231 * log(t - 10) - 305.0447927307
        }

        return (max(0, min(255, red)), max(0, min(255, green)), max(0, min(255, blue)))
    }
}
