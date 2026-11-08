import SwiftUI

@main
struct ThemeRoundTrip {
    static func main() {
        let suite = "KeyFinderThemeTest-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = ThemeManager(defaults: defaults)
        precondition(manager.currentTheme == .dark)
        for theme in ThemeManager.Theme.allCases {
            manager.currentTheme = theme
            let restored = ThemeManager(defaults: defaults)
            precondition(restored.currentTheme == theme, "Theme was not persisted")
            switch theme {
            case .system: precondition(restored.colorScheme == nil)
            case .light, .paper: precondition(restored.colorScheme == .light)
            default: precondition(restored.colorScheme == .dark)
            }
        }
        defaults.set("Dark", forKey: "selectedTheme")
        precondition(ThemeManager(defaults: defaults).currentTheme == .dark)
        defaults.set("unknown-future-theme", forKey: "selectedTheme")
        precondition(ThemeManager(defaults: defaults).currentTheme == .dark)
        print("PASS: seven themes, preference round trip, appearance modes and legacy fallback")
    }
}
