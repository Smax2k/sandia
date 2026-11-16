import CoreGraphics
import Foundation
import SandiaCore

/// Writes per-display gamma tables: `original * factor`, per channel.
/// Original tables are captured once per display so repeated applies never compound.
final class GammaController {
    private struct Tables {
        var red: [CGGammaValue]
        var green: [CGGammaValue]
        var blue: [CGGammaValue]
    }

    private static let capacity: UInt32 = 256
    private var originals: [CGDirectDisplayID: Tables] = [:]
    /// Tables Sandia itself has written, so a delayed probe can be read apart
    /// from a restore macOS performed on its own.
    private var writeCount = 0

    init() {
        GammaDiagnostics.session(capacity: Self.capacity)
        let displays = activeDisplays()
        GammaDiagnostics.log("gamma.init", [("displays", GammaDiagnostics.ids(displays))])
        probe(displays, phase: "before-restore")
        // A previous crashed run may have left a tint behind; never capture that as "original".
        CGDisplayRestoreColorSyncSettings()
        probe(displays, phase: "after-restore")
        refresh(displays)
        if GammaDiagnostics.isEnabled {
            // Passive re-reads: shows whether a restore lands late, and what is
            // on the display once the opening ease (2 s) is over.
            for delay in [1.0, 5.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self else { return }
                    self.probe(self.activeDisplays(), phase: String(format: "t+%.0fs", delay))
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

    /// Captures originals for displays seen for the first time and forgets unplugged ones.
    func refreshDisplays() {
        refresh(activeDisplays())
    }

    private func refresh(_ active: [CGDirectDisplayID]) {
        originals = originals.filter { active.contains($0.key) }
        for id in active where originals[id] == nil {
            guard let (tables, samples) = readTable(id) else {
                GammaDiagnostics.log("baseline.captured", [("display", "\(id)"), ("result", "read-failed")])
                continue
            }
            originals[id] = tables
            GammaDiagnostics.log("baseline.captured", [
                ("display", "\(id)"),
                ("samples", "\(samples)"),
                ("r", GammaDiagnostics.endpoints(tables.red)),
                ("g", GammaDiagnostics.endpoints(tables.green)),
                ("b", GammaDiagnostics.endpoints(tables.blue))
            ])
        }
    }

    private func readTable(_ display: CGDirectDisplayID) -> (tables: Tables, samples: UInt32)? {
        var red = [CGGammaValue](repeating: 0, count: Int(Self.capacity))
        var green = red
        var blue = red
        var samples: UInt32 = 0
        guard CGGetDisplayTransferByTable(display, Self.capacity, &red, &green, &blue, &samples) == .success,
              samples > 0 else { return nil }
        let n = Int(samples)
        return (Tables(red: Array(red.prefix(n)), green: Array(green.prefix(n)), blue: Array(blue.prefix(n))), samples)
    }

    /// Reads what the display currently holds. Diagnostic only: never writes,
    /// never touches the captured originals.
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
        let displays = activeDisplays()
        writeCount += 1
        GammaDiagnostics.log("apply.intent", [
            ("rgb", GammaDiagnostics.rgb(rgb)),
            ("displays", GammaDiagnostics.ids(displays))
        ])
        for id in displays {
            if originals[id] == nil, let captured = readTable(id) {
                originals[id] = captured.tables
                GammaDiagnostics.log("baseline.captured", [
                    ("display", "\(id)"),
                    ("phase", "apply-late"),
                    ("samples", "\(captured.samples)"),
                    ("r", GammaDiagnostics.endpoints(captured.tables.red)),
                    ("g", GammaDiagnostics.endpoints(captured.tables.green)),
                    ("b", GammaDiagnostics.endpoints(captured.tables.blue))
                ])
            }
            guard let original = originals[id] else {
                GammaDiagnostics.log("apply.skip", [("display", "\(id)"), ("reason", "no-baseline")])
                continue
            }
            var red = original.red.map { $0 * factors.red }
            var green = original.green.map { $0 * factors.green }
            var blue = original.blue.map { $0 * factors.blue }
            if GammaDiagnostics.isEnabled {
                GammaDiagnostics.log("apply.lut", [
                    ("display", "\(id)"),
                    ("n", "\(red.count)"),
                    ("original.r", GammaDiagnostics.endpoints(original.red)),
                    ("original.g", GammaDiagnostics.endpoints(original.green)),
                    ("original.b", GammaDiagnostics.endpoints(original.blue)),
                    ("written.r", GammaDiagnostics.endpoints(red)),
                    ("written.g", GammaDiagnostics.endpoints(green)),
                    ("written.b", GammaDiagnostics.endpoints(blue))
                ])
            }
            let result = CGSetDisplayTransferByTable(id, UInt32(red.count), &red, &green, &blue)
            GammaDiagnostics.log("apply.result", [
                ("display", "\(id)"),
                ("cgSet", "\(result.rawValue)"),
                ("ok", result == .success ? "yes" : "no")
            ])
            if GammaDiagnostics.isEnabled, let (readback, samples) = readTable(id) {
                GammaDiagnostics.log("apply.readback", [
                    ("display", "\(id)"),
                    ("samples", "\(samples)"),
                    ("r", GammaDiagnostics.endpoints(readback.red)),
                    ("g", GammaDiagnostics.endpoints(readback.green)),
                    ("b", GammaDiagnostics.endpoints(readback.blue))
                ])
            }
        }
    }

    func restore() {
        let displays = activeDisplays()
        writeCount += 1
        GammaDiagnostics.log("restore.intent", [("displays", GammaDiagnostics.ids(displays))])
        CGDisplayRestoreColorSyncSettings()
        probe(displays, phase: "after-restore-call")
    }
}

/// Opt-in trace of the gamma pipeline, enabled only with `SANDIA_GAMMA_DIAG=1`
/// (or `true`/`yes`). It writes one append-only log under the user's temporary
/// directory and never changes what Sandia applies. Call it from the main
/// thread, like the rest of the gamma code.
enum GammaDiagnostics {
    static let isEnabled: Bool = {
        let value = ProcessInfo.processInfo.environment["SANDIA_GAMMA_DIAG"]?.lowercased()
        return value == "1" || value == "true" || value == "yes"
    }()

    static var fileURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("SandiaGammaDiagnostic.log")
    }

    private static let clockFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let uptimeAtStart = ProcessInfo.processInfo.systemUptime

    private static let handle: FileHandle? = {
        guard isEnabled else { return nil }
        let manager = FileManager.default
        if !manager.fileExists(atPath: fileURL.path) {
            manager.createFile(atPath: fileURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return nil }
        _ = try? handle.seekToEnd()
        return handle
    }()

    /// One line per event: `t=+1.234s at=... event=name key=value ...`.
    static func log(_ event: String, _ fields: [(String, String)] = []) {
        guard isEnabled, let handle else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - uptimeAtStart
        var line = "t=+\(String(format: "%.3f", elapsed))s"
        line += " at=\(clockFormatter.string(from: Date()))"
        line += " event=\(event)"
        for (key, value) in fields {
            line += " \(key)=\(value)"
        }
        line += "\n"
        if let data = line.data(using: .utf8) {
            try? handle.write(contentsOf: data)
        }
    }

    /// Run header: the app build, the OS and the file being written.
    static func session(capacity: UInt32) {
        guard isEnabled else { return }
        let info = Bundle.main.infoDictionary
        log("session", [
            ("app", info?["CFBundleShortVersionString"] as? String ?? "unknown"),
            ("build", info?["CFBundleVersion"] as? String ?? "unknown"),
            ("macos", ProcessInfo.processInfo.operatingSystemVersionString),
            ("pid", "\(ProcessInfo.processInfo.processIdentifier)"),
            ("capacity", "\(capacity)"),
            ("file", fileURL.path)
        ])
    }

    static func endpoints(_ values: [CGGammaValue]) -> String {
        guard let first = values.first, let last = values.last else { return "none" }
        return String(format: "%.6f..%.6f", Double(first), Double(last))
    }

    static func rgb(_ value: RGB) -> String {
        String(format: "%.6f/%.6f/%.6f", value.red, value.green, value.blue)
    }

    static func ids(_ displays: [CGDirectDisplayID]) -> String {
        displays.isEmpty ? "none" : displays.map(String.init).joined(separator: ",")
    }
}
