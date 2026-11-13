import Foundation

/// Looks a user-facing string up in the localized resources.
///
/// English is the base development language, so the literals in the views are
/// the English wording; `fr.lproj` adds the French translation, which macOS
/// picks automatically on a French system. Use this helper only outside
/// SwiftUI's own localized `Text`/`Button`/`Toggle` initializers, which already
/// resolve their literal keys against the main bundle.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// Same lookup for a format string, with its arguments applied using the
/// current locale.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), locale: Locale.current, arguments: arguments)
}
