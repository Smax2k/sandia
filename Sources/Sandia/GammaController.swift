import CoreGraphics
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

    init() {
        // A previous crashed run may have left a tint behind; never capture that as "original".
        CGDisplayRestoreColorSyncSettings()
        refreshDisplays()
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
        let active = activeDisplays()
        originals = originals.filter { active.contains($0.key) }
        for id in active where originals[id] == nil {
            if let tables = capture(id) { originals[id] = tables }
        }
    }

    private func capture(_ display: CGDirectDisplayID) -> Tables? {
        var red = [CGGammaValue](repeating: 0, count: Int(Self.capacity))
        var green = red
        var blue = red
        var samples: UInt32 = 0
        guard CGGetDisplayTransferByTable(display, Self.capacity, &red, &green, &blue, &samples) == .success,
              samples > 0 else { return nil }
        let n = Int(samples)
        return Tables(red: Array(red.prefix(n)), green: Array(green.prefix(n)), blue: Array(blue.prefix(n)))
    }

    func apply(_ rgb: RGB) {
        let factors = (red: Float(rgb.red), green: Float(rgb.green), blue: Float(rgb.blue))
        for id in activeDisplays() {
            if originals[id] == nil, let tables = capture(id) { originals[id] = tables }
            guard let original = originals[id] else { continue }
            var red = original.red.map { $0 * factors.red }
            var green = original.green.map { $0 * factors.green }
            var blue = original.blue.map { $0 * factors.blue }
            CGSetDisplayTransferByTable(id, UInt32(red.count), &red, &green, &blue)
        }
    }

    func restore() {
        CGDisplayRestoreColorSyncSettings()
    }
}
