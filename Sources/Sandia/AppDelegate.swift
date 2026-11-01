import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences()
    private lazy var engine = Engine(preferences: preferences)
    private var menuController: MenuController?
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        installSignalHandlers()
        preferences.pausedUntil = nil // a pause never survives a relaunch
        menuController = MenuController(engine: engine, preferences: preferences)
        engine.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.shutdown()
    }

    /// Restore colours on Ctrl-C and `kill -TERM`. (`kill -9` cannot be caught; use `Sandia --reset`.)
    private func installSignalHandlers() {
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                self?.engine.shutdown()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }
}
