import Foundation

/// Blue-light reduction as a software filter strength, expressed for the
/// interface while colour temperature stays the internal detail.
///
/// 0 % leaves the display untouched: it maps to
/// `ColorTemperature.neutralKelvin` (6,504 K, D65), whose multiplier is exactly
/// (1, 1, 1). 100 % is the warmest supported point, 1,000 K. Between the two,
/// the percentage follows the mired (reciprocal kelvin) scale, which spreads
/// the warm range evenly and keeps the whole RGB multiplier moving smoothly:
///
///     fraction(kelvin) = (1/kelvin - 1/6504) / (1/1000 - 1/6504)
///
/// The inverse is the same formula solved for kelvin, so both endpoints are
/// exact and no step sits on a clipped channel or an inversion plateau. The
/// percentage is the strength of this software filter, not a measurement of the
/// blue light removed or of the light reaching the eye.
public enum BlueLightReduction {
    /// Warmest supported temperature: full reduction.
    public static let warmestKelvin = ColorTemperature.minimumKelvin

    /// Untouched display: no reduction, D65.
    public static let neutralKelvin = ColorTemperature.neutralKelvin

    private static let neutralMired = 1 / neutralKelvin
    private static let warmestMired = 1 / warmestKelvin
    private static let miredSpan = warmestMired - neutralMired

    /// Strength of the filter at `kelvin`, 0...1 on the mired scale.
    ///
    /// Out-of-range and non-finite temperatures are safe: anything at or above
    /// neutral, and any non-finite value, reads as no reduction.
    public static func fraction(kelvin: Double) -> Double {
        let clamped = clampedKelvin(kelvin)
        let mired = 1 / clamped
        return min(max((mired - neutralMired) / miredSpan, 0), 1)
    }

    /// Temperature implementing `fraction` of the filter strength, the inverse
    /// of `fraction(kelvin:)` by construction. Non-finite input and values
    /// outside 0...1 clamp to the neutral or full end.
    public static func kelvin(forFraction fraction: Double) -> Double {
        guard fraction.isFinite else { return neutralKelvin }
        let target = min(max(fraction, 0), 1)
        if target <= 0 { return neutralKelvin }
        if target >= 1 { return warmestKelvin }
        return 1 / (neutralMired + target * miredSpan)
    }

    /// Multiplier for a reduction fraction; 0 is exactly `RGB.neutral`.
    public static func rgb(fraction: Double) -> RGB {
        let target = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        guard target > 0 else { return .neutral }
        return ColorTemperature.rgb(kelvin: kelvin(forFraction: target))
    }

    /// Keeps the supported warm range and treats a non-finite temperature as
    /// neutral. This is also the migration rule for saved settings.
    public static func clampedKelvin(_ kelvin: Double) -> Double {
        guard kelvin.isFinite else { return neutralKelvin }
        return min(max(kelvin, warmestKelvin), neutralKelvin)
    }
}
