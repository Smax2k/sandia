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

/// Kelvin to a per-channel display multiplier, computed colorimetrically.
///
/// Planckian radiation at the requested temperature is integrated against the
/// CIE 1931 2° observer, converted to linear sRGB with the D65 white point, and
/// divided channel by channel by the same value at `neutralKelvin`. 6504 K is
/// D65's correlated colour temperature, so it maps to exactly (1, 1, 1): the
/// display is untouched there and the tint grows continuously on either side.
///
/// The result is clamped to 0...1 because a gamma table can only attenuate,
/// never brighten, a channel.
public enum ColorTemperature {
    public static let minimumKelvin = 1000.0
    public static let maximumKelvin = 12_000.0
    /// D65's correlated colour temperature: the filter's zero point.
    public static let neutralKelvin = 6504.0

    public static func rgb(kelvin: Double) -> RGB {
        let clamped = min(max(kelvin, minimumKelvin), maximumKelvin)
        let value = linearSRGB(kelvin: clamped)
        let reference = neutralReference
        return RGB(red: unit(value.red / reference.red),
                   green: unit(value.green / reference.green),
                   blue: unit(value.blue / reference.blue))
    }

    private static func unit(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    // MARK: - Slider travel

    /// Share of the track given to the cold stretch, `neutralKelvin` to
    /// `maximumKelvin`. 15 % keeps the blue side short and leaves the other
    /// 85 % to the warm range, where the tint changes the most.
    public static let coldPositionSpan = 0.15

    /// Track position of `neutralKelvin`, measured from the warm end: the
    /// slider runs from 1000 K at 0 to 12000 K at 1, so the neutral point
    /// sits at 85 %.
    public static var neutralPosition: Double { 1 - coldPositionSpan }

    /// Track position, 0 at `minimumKelvin` and 1 at `maximumKelvin`, for a
    /// colour temperature.
    ///
    /// Each side of the neutral point is linear in mired (reciprocal kelvin),
    /// which follows perception far better than kelvin itself, and the two
    /// pieces meet exactly at `neutralKelvin`: the mapping is continuous, so
    /// dragging the slider never jumps, and the warm range gets the wider part
    /// of the track.
    public static func position(forKelvin kelvin: Double) -> Double {
        let clamped = min(max(kelvin, minimumKelvin), maximumKelvin)
        if clamped <= neutralKelvin {
            return miredRatio(from: minimumKelvin, to: neutralKelvin, kelvin: clamped)
                * neutralPosition
        }
        return neutralPosition
            + miredRatio(from: neutralKelvin, to: maximumKelvin, kelvin: clamped)
            * coldPositionSpan
    }

    /// Colour temperature for a track position, clamped to the supported
    /// range: the inverse of `position(forKelvin:)`.
    public static func kelvin(forPosition position: Double) -> Double {
        let clamped = min(max(position, 0), 1)
        let kelvin: Double
        if clamped <= neutralPosition {
            kelvin = temperature(miredRatio: clamped / neutralPosition,
                                 from: minimumKelvin, to: neutralKelvin)
        } else {
            kelvin = temperature(miredRatio: (clamped - neutralPosition) / coldPositionSpan,
                                 from: neutralKelvin, to: maximumKelvin)
        }
        return min(max(kelvin, minimumKelvin), maximumKelvin)
    }

    /// Where `kelvin` sits between two bounds on the mired scale, 0...1.
    private static func miredRatio(from start: Double, to end: Double,
                                   kelvin: Double) -> Double {
        (1 / start - 1 / kelvin) / (1 / start - 1 / end)
    }

    /// A temperature for a 0...1 position on the mired scale, the inverse of
    /// `miredRatio(from:to:kelvin:)`.
    private static func temperature(miredRatio ratio: Double,
                                    from start: Double, to end: Double) -> Double {
        let mired = 1 / start + (1 / end - 1 / start) * ratio
        return 1 / mired
    }

    // MARK: - Colorimetry

    private struct CMF {
        var x: Double
        var y: Double
        var z: Double
    }

    private struct Sample {
        var wavelength: Double
        var cmf: CMF
    }

    /// Linear sRGB channels for a blackbody at `kelvin`, normalised to Y = 1.
    private static func linearSRGB(kelvin: Double) -> (red: Double, green: Double, blue: Double) {
        var X = 0.0
        var Y = 0.0
        var Z = 0.0
        for sample in samples {
            let radiance = planck(wavelength: sample.wavelength, kelvin: kelvin)
            X += radiance * sample.cmf.x
            Y += radiance * sample.cmf.y
            Z += radiance * sample.cmf.z
        }

        // Chromaticity only: a common scale cancels in the ratio to the reference.
        let x = X / Y
        let z = Z / Y
        return (3.2406 * x - 1.5372 - 0.4986 * z,
                -0.9689 * x + 1.8758 + 0.0415 * z,
                0.0557 * x - 0.2040 + 1.0570 * z)
    }

    /// Planck's law up to a constant factor; only ratios are used.
    private static func planck(wavelength: Double, kelvin: Double) -> Double {
        // Second radiation constant, in nm·K.
        let c2 = 1.438_776_877e7
        return 1 / (pow(wavelength, 5) * (exp(c2 / (wavelength * kelvin)) - 1))
    }

    /// CIE 1931 2° colour matching functions, Wyman–Sloan–Shirley multi-lobe fit.
    private static func matchingFunctions(at wavelength: Double) -> CMF {
        CMF(x: 1.056 * lobe(wavelength, 599.8, 37.9, 31.0)
              + 0.362 * lobe(wavelength, 442.0, 16.0, 26.7)
              - 0.065 * lobe(wavelength, 501.1, 20.4, 26.2),
            y: 0.821 * lobe(wavelength, 568.8, 46.9, 40.5)
              + 0.286 * lobe(wavelength, 530.9, 16.3, 31.1),
            z: 1.217 * lobe(wavelength, 437.0, 11.8, 36.0)
              + 0.681 * lobe(wavelength, 459.0, 26.0, 13.8))
    }

    /// A Gaussian lobe with distinct widths below and above its centre.
    private static func lobe(_ wavelength: Double, _ center: Double,
                             _ below: Double, _ above: Double) -> Double {
        let width = wavelength < center ? below : above
        let offset = (wavelength - center) / width
        return exp(-0.5 * offset * offset)
    }

    /// The visible spectrum sampled every 5 nm, a smooth enough quadrature for
    /// a broad spectrum such as a blackbody's.
    private static let samples: [Sample] = stride(from: 380.0, through: 780.0, by: 5).map {
        Sample(wavelength: $0, cmf: matchingFunctions(at: $0))
    }

    private static let neutralReference = linearSRGB(kelvin: neutralKelvin)
}
