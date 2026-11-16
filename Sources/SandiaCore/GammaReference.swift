import Foundation

/// A per-channel gamma table, kept as plain floats so the reference policy can
/// be exercised without a display.
public struct GammaTable: Equatable, Sendable {
    public var red: [Float]
    public var green: [Float]
    public var blue: [Float]

    public init(red: [Float], green: [Float], blue: [Float]) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Same table up to storage rounding. Different lengths never match.
    public func isClose(to other: GammaTable, tolerance: Float = 0.001) -> Bool {
        Self.isClose(red, other.red, tolerance: tolerance)
            && Self.isClose(green, other.green, tolerance: tolerance)
            && Self.isClose(blue, other.blue, tolerance: tolerance)
    }

    private static func isClose(_ a: [Float], _ b: [Float], tolerance: Float) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) <= tolerance }
    }
}

/// Decides which table may become a display's gamma reference.
///
/// The only table Sandia refuses is the one it installed itself: a reference
/// read while our own tint is still on the display would bake the tint in.
/// A tint left by another process looks like a calibrated baseline here and is
/// deliberately not guessed at.
///
/// References are keyed by a display identity that survives re-enumeration
/// (the display UUID, not the transient numeric id), so a reconfiguration or a
/// replug finds the known reference instead of reading the display again.
public struct GammaReferencePolicy: Sendable {
    public enum ReferenceOutcome: Equatable, Sendable {
        /// A reference was already known and was kept.
        case known(GammaTable)
        /// The read table became the reference.
        case adopted(GammaTable)
        /// The read table is the tint this policy recorded as installed.
        case rejectedOwnTint
    }

    public enum RestoreOutcome: Equatable, Sendable {
        /// The restore left our tint in place: the read is not a baseline.
        case stillOwnTint
        /// Our tint is gone and the read table became the reference.
        case adoptedReference(GammaTable)
        /// Our tint is gone; a reference was already known.
        case cleared
    }

    private var references: [String: GammaTable] = [:]
    private var installed: [String: GammaTable] = [:]
    private let tolerance: Float

    public init(tolerance: Float = 0.001) {
        self.tolerance = tolerance
    }

    /// The known reference for a display key, if any.
    public func reference(for key: String) -> GammaTable? {
        references[key]
    }

    /// The table this process last installed for a display key, if any.
    public func installedTable(for key: String) -> GammaTable? {
        installed[key]
    }

    /// Reference for `key`, adopting `current` only when it cannot be our tint.
    public mutating func reference(for key: String, read current: GammaTable) -> ReferenceOutcome {
        if let known = references[key] {
            return .known(known)
        }
        if let own = installed[key], own.isClose(to: current, tolerance: tolerance) {
            return .rejectedOwnTint
        }
        references[key] = current
        return .adopted(current)
    }

    /// Records the outcome of a write. A failed write changes nothing, so the
    /// previous installed table keeps protecting the reference.
    public mutating func recordWrite(_ table: GammaTable, for key: String, succeeded: Bool) {
        guard succeeded else { return }
        if let known = references[key], known.isClose(to: table, tolerance: tolerance) {
            // A no-op write leaves the baseline in place: it is not a tint.
            installed[key] = nil
        } else {
            installed[key] = table
        }
    }

    /// Records a read taken right after a ColorSync restore.
    public mutating func recordRestore(read current: GammaTable, for key: String) -> RestoreOutcome {
        if let own = installed[key], own.isClose(to: current, tolerance: tolerance) {
            return .stillOwnTint
        }
        installed[key] = nil
        guard references[key] == nil else { return .cleared }
        references[key] = current
        return .adoptedReference(current)
    }
}
