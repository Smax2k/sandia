import ColorSync
import CoreGraphics
import Foundation
import SandiaCore

/// Writes per-display gamma tables: `reference * factor`, per channel.
///
/// References are captured once per display, keyed by the display's stable
/// UUID, and never from a table this process installed itself: reconfiguring
/// or re-enabling a display must not fold the current tint into the next
/// reference. The decision itself lives in `GammaReferencePolicy`, which is
/// pure and tested without a screen.
final class GammaController {
    private struct Target {
        var id: CGDirectDisplayID
        /// Stable across re-enumeration, unlike the numeric display id.
        var key: String
    }

    private static let capacity: UInt32 = 256

    private var policy = GammaReferencePolicy()
    /// Tables Sandia itself has written, so a delayed probe can be read apart
    /// from a restore macOS performed on its own.
    private var writeCount = 0

    init() {
        GammaDiagnostics.session(capacity: Self.capacity)
        let targets = targets()
        GammaDiagnostics.log("gamma.init", [("displays", GammaDiagnostics.ids(targets.map(\.id)))])
        probe(targets.map(\.id), phase: "before-restore")
        // A previous crashed run may have left a tint behind; never capture that as "original".
        CGDisplayRestoreColorSyncSettings()
        probe(targets.map(\.id), phase: "after-restore")
        refresh(targets)
        if GammaDiagnostics.isEnabled {
            // Passive re-reads: shows whether a restore lands late, and what is
            // on the display once the opening ease (2 s) is over.
            for delay in [1.0, 5.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self else { return }
                    self.probe(self.targets().map(\.id), phase: String(format: "t+%.0fs", delay))
                }
            }
        }
    }

    private func activeDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    /// Active displays with a key that survives re-enumeration, so a display
    /// that is reconfigured or re-enabled finds its known reference again.
    private func targets() -> [Target] {
        activeDisplays().map { id in
            let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue()
            let key: String
            if let uuid, let string = CFUUIDCreateString(nil, uuid) {
                key = string as String
            } else {
                key = "id:\(id)"
            }
            return Target(id: id, key: key)
        }
    }

    /// Captures references for displays that do not have one yet.
    func refreshDisplays() {
        refresh(targets())
    }

    private func refresh(_ targets: [Target]) {
        for target in targets {
            guard policy.reference(for: target.key) == nil else {
                GammaDiagnostics.log("baseline.reused", [("display", "\(target.id)")])
                continue
            }
            captureReference(target, phase: "refresh")
        }
    }

    /// Reads a reference unless the table is the tint this process installed.
    @discardableResult
    private func captureReference(_ target: Target, phase: String) -> Bool {
        guard let (tables, samples) = readTable(target.id) else {
            GammaDiagnostics.log("baseline.captured", [
                ("display", "\(target.id)"), ("phase", phase), ("result", "read-failed")
            ])
            return false
        }
        switch policy.reference(for: target.key, read: tables) {
        case .rejectedOwnTint:
            // Our own tint is still installed: it cannot become the baseline.
            GammaDiagnostics.log("baseline.rejected", [
                ("display", "\(target.id)"), ("phase", phase), ("reason", "own-tint")
            ])
            return false
        case .known, .adopted:
            GammaDiagnostics.log("baseline.captured", [
                ("display", "\(target.id)"),
                ("phase", phase),
                ("samples", "\(samples)"),
                ("r", GammaDiagnostics.endpoints(tables.red)),
                ("g", GammaDiagnostics.endpoints(tables.green)),
                ("b", GammaDiagnostics.endpoints(tables.blue))
            ])
            return true
        }
    }

    private func readTable(_ display: CGDirectDisplayID) -> (tables: GammaTable, samples: UInt32)? {
        var red = [CGGammaValue](repeating: 0, count: Int(Self.capacity))
        var green = red
        var blue = red
        var samples: UInt32 = 0
        guard CGGetDisplayTransferByTable(display, Self.capacity, &red, &green, &blue, &samples) == .success,
              samples > 0 else { return nil }
        let n = Int(samples)
        return (GammaTable(red: Array(red.prefix(n)),
                           green: Array(green.prefix(n)),
                           blue: Array(blue.prefix(n))), samples)
    }

    /// Reads what the display currently holds. Diagnostic only: never writes,
    /// never touches the captured references.
    private func probe(_ displays: [CGDirectDisplayID], phase: String) {
        guard GammaDiagnostics.isEnabled else { return }
        for id in displays {
            guard let (tables, samples) = readTable(id) else {
                GammaDiagnostics.log("table", [("phase", phase), ("display", "\(id)"), ("result", "read-failed")])
                continue
            }
            GammaDiagnostics.log("table", [
                ("phase", phase),
                ("display", "\(id)"),
                ("samples", "\(samples)"),
                ("r", GammaDiagnostics.endpoints(tables.red)),
                ("g", GammaDiagnostics.endpoints(tables.green)),
                ("b", GammaDiagnostics.endpoints(tables.blue)),
                ("writes", "\(writeCount)")
            ])
        }
    }

    func apply(_ rgb: RGB) {
        let factors = (red: Float(rgb.red), green: Float(rgb.green), blue: Float(rgb.blue))
        let targets = targets()
        writeCount += 1
        GammaDiagnostics.log("apply.intent", [
            ("rgb", GammaDiagnostics.rgb(rgb)),
            ("displays", GammaDiagnostics.ids(targets.map(\.id)))
        ])
        for target in targets {
            if policy.reference(for: target.key) == nil, !captureReference(target, phase: "apply") {
                GammaDiagnostics.log("apply.skip", [("display", "\(target.id)"), ("reason", "no-reference")])
                continue
            }
            guard let reference = policy.reference(for: target.key) else { continue }
            var red = reference.red.map { $0 * factors.red }
            var green = reference.green.map { $0 * factors.green }
            var blue = reference.blue.map { $0 * factors.blue }
            if GammaDiagnostics.isEnabled {
                GammaDiagnostics.log("apply.lut", [
                    ("display", "\(target.id)"),
                    ("n", "\(red.count)"),
                    ("original.r", GammaDiagnostics.endpoints(reference.red)),
                    ("original.g", GammaDiagnostics.endpoints(reference.green)),
                    ("original.b", GammaDiagnostics.endpoints(reference.blue)),
                    ("written.r", GammaDiagnostics.endpoints(red)),
                    ("written.g", GammaDiagnostics.endpoints(green)),
                    ("written.b", GammaDiagnostics.endpoints(blue))
                ])
            }
            let result = CGSetDisplayTransferByTable(target.id, UInt32(red.count), &red, &green, &blue)
            let succeeded = result == .success
            policy.recordWrite(GammaTable(red: red, green: green, blue: blue),
                               for: target.key, succeeded: succeeded)
            GammaDiagnostics.log("apply.result", [
                ("display", "\(target.id)"),
                ("cgSet", "\(result.rawValue)"),
                ("ok", succeeded ? "yes" : "no")
            ])
            if GammaDiagnostics.isEnabled, let (readback, samples) = readTable(target.id) {
                GammaDiagnostics.log("apply.readback", [
                    ("display", "\(target.id)"),
                    ("samples", "\(samples)"),
                    ("r", GammaDiagnostics.endpoints(readback.red)),
                    ("g", GammaDiagnostics.endpoints(readback.green)),
                    ("b", GammaDiagnostics.endpoints(readback.blue))
                ])
            }
        }
    }

    func restore() {
        let targets = targets()
        writeCount += 1
        GammaDiagnostics.log("restore.intent", [("displays", GammaDiagnostics.ids(targets.map(\.id)))])
        CGDisplayRestoreColorSyncSettings()
        for target in targets {
            guard let (tables, samples) = readTable(target.id) else { continue }
            switch policy.recordRestore(read: tables, for: target.key) {
            case .stillOwnTint:
                // The restore did not displace our tint: this table is not a baseline.
                GammaDiagnostics.log("restore.unchanged", [("display", "\(target.id)")])
            case .adoptedReference(let adopted):
                GammaDiagnostics.log("baseline.captured", [
                    ("display", "\(target.id)"),
                    ("phase", "after-restore-call"),
                    ("samples", "\(samples)"),
                    ("r", GammaDiagnostics.endpoints(adopted.red)),
                    ("g", GammaDiagnostics.endpoints(adopted.green)),
                    ("b", GammaDiagnostics.endpoints(adopted.blue))
                ])
            case .cleared:
                break
            }
        }
        probe(targets.map(\.id), phase: "after-restore-call")
    }
}
