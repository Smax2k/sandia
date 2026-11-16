import Foundation

/// The advanced red–amber axis, layered on top of the scheduled look.
///
/// `tint` runs from -1 (red) through 0 (untouched) to 1 (amber), so its default
/// is exact identity: the temperature rendering stays exactly as it was. The
/// axis only moves green; red and blue are returned unchanged.
///
/// `headroom` is how much blue the temperature has already removed. A neutral
/// look (blue at 1) has no headroom and is invariant at every tint, and the
/// correction fades out on its own as the tint lightens, so the filter never
/// fights the main slider's intensity.
public enum FilterTint {
    public static let minimum = -1.0
    public static let maximum = 1.0
    /// The default, and the identity: the temperature's colours are preserved.
    public static let neutral = 0.0

    /// Clamps a tint parameter to `minimum...maximum`; a non-finite value falls
    /// back to `neutral`.
    public static func clamped(_ tint: Double) -> Double {
        guard tint.isFinite else { return neutral }
        return min(max(tint, minimum), maximum)
    }

    /// The display multiplier for `base` with the advanced tint applied.
    public static func applied(to base: RGB, tint: Double) -> RGB {
        let t = clamped(tint)
        let red = unit(base.red)
        let green = unit(base.green)
        let blue = unit(base.blue)
        guard t != 0 else {
            return RGB(red: red, green: green, blue: blue)
        }

        let headroom = unit(1 - blue)
        let adjusted: Double
        if t < 0 {
            // Red side: remove green in proportion to the blue the tint has
            // already taken, so a neutral look is left alone.
            adjusted = green * (1 + t * headroom)
        } else {
            // Amber side: raise green toward full by the tint amount.
            adjusted = green + (1 - green) * t
        }
        return RGB(red: red, green: unit(adjusted), blue: blue)
    }

    /// Keeps a channel in 0...1; a non-finite value falls back to 0.
    private static func unit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

extension ResolvedState {
    /// Applies the advanced tint to the scheduled look only. Disabled, paused
    /// and darkroom keep the colours they resolved to.
    public func applyingFilterTint(_ tint: Double) -> ResolvedState {
        guard mode == .scheduled else { return self }
        var result = self
        result.rgb = FilterTint.applied(to: rgb, tint: tint)
        return result
    }
}
