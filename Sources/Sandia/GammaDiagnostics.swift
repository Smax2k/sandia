import CoreGraphics
import Foundation
import SandiaCore

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
