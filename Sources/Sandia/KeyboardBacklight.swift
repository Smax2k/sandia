import Foundation

/// Built-in keyboard backlight through CoreBrightness. This is a private API with no public
/// replacement and may break on a future macOS, so every step is optional and falls back to a no-op.
final class KeyboardBacklight {
    private let client: NSObject?
    private let keyboardID: UInt64?

    init() {
        let path = "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
        guard dlopen(path, RTLD_NOW) != nil,
              let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else {
            client = nil
            keyboardID = nil
            return
        }
        let client = type.init()
        let listIDs = Selector(("copyKeyboardBacklightIDs"))
        let ids = client.responds(to: listIDs)
            ? client.perform(listIDs)?.takeRetainedValue() as? [NSNumber]
            : nil
        self.client = client
        keyboardID = ids?.first?.uint64Value
    }

    var isAvailable: Bool { target != nil }

    /// 0...1. Reads 0 and ignores writes when unavailable.
    var brightness: Float {
        get {
            typealias Get = @convention(c) (AnyObject, Selector, UInt64) -> Float
            guard let (client, id) = target, let get: Get = method("brightnessForKeyboard:", on: client) else { return 0 }
            return get(client, Selector(("brightnessForKeyboard:")), id)
        }
        set {
            typealias Set = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
            guard let (client, id) = target, let set: Set = method("setBrightness:forKeyboard:", on: client) else { return }
            _ = set(client, Selector(("setBrightness:forKeyboard:")), min(max(newValue, 0), 1), id)
        }
    }

    /// Dims the backlight in the dark and turns it on in light, the system's own behaviour.
    var isAutoBrightnessEnabled: Bool {
        get {
            typealias Get = @convention(c) (AnyObject, Selector, UInt64) -> Bool
            guard let (client, id) = target, let get: Get = method("isAutoBrightnessEnabledForKeyboard:", on: client) else { return false }
            return get(client, Selector(("isAutoBrightnessEnabledForKeyboard:")), id)
        }
        set {
            typealias Set = @convention(c) (AnyObject, Selector, Bool, UInt64) -> Bool
            guard let (client, id) = target, let set: Set = method("enableAutoBrightness:forKeyboard:", on: client) else { return }
            _ = set(client, Selector(("enableAutoBrightness:forKeyboard:")), newValue, id)
        }
    }

    private var target: (NSObject, UInt64)? {
        guard let client, let keyboardID else { return nil }
        return (client, keyboardID)
    }

    /// The implementation of `name`, or nil if this macOS no longer has it.
    private func method<F>(_ name: String, on client: NSObject) -> F? {
        let selector = Selector((name))
        guard client.responds(to: selector), let imp = client.method(for: selector) else { return nil }
        return unsafeBitCast(imp, to: F.self)
    }
}
