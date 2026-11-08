import SwiftUI

final class ThemeManager: ObservableObject {
    enum Theme: String, CaseIterable {
        // Keep existing stored values compatible with earlier releases.
        case system = "System"
        case light = "Light"
        case dark = "Dark"
        case midnight = "Midnight"
        case ember = "Ember"
        case forest = "Forest"
        case paper = "Paper"

        var icon: String {
            switch self {
            case .system: return "circle.lefthalf.filled"
            case .light: return "sun.max.fill"
            case .dark: return "moon.fill"
            case .midnight: return "moon.stars.fill"
            case .ember: return "flame.fill"
            case .forest: return "leaf.fill"
            case .paper: return "doc.text.fill"
            }
        }
    }

    private let defaults: UserDefaults
    @Published var currentTheme: Theme {
        didSet { defaults.set(currentTheme.rawValue, forKey: "selectedTheme") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        currentTheme = defaults.string(forKey: "selectedTheme")
            .flatMap(Theme.init(rawValue:)) ?? .dark
    }

    var colorScheme: ColorScheme? {
        switch currentTheme {
        case .system: return nil
        case .light, .paper: return .light
        case .dark, .midnight, .ember, .forest: return .dark
        }
    }

    var backgroundColor: Color {
        switch currentTheme {
        case .system: return Color(nsColor: .windowBackgroundColor)
        case .light: return .white
        case .dark: return Color(red: 0.035, green: 0.03, blue: 0.05)
        case .midnight: return Color(red: 0.035, green: 0.065, blue: 0.12)
        case .ember: return Color(red: 0.105, green: 0.055, blue: 0.045)
        case .forest: return Color(red: 0.035, green: 0.085, blue: 0.065)
        case .paper: return Color(red: 0.96, green: 0.94, blue: 0.89)
        }
    }

    var textColor: Color {
        switch currentTheme {
        case .system: return Color(nsColor: .labelColor)
        case .light: return Color(white: 0.10)
        case .paper: return Color(red: 0.18, green: 0.16, blue: 0.13)
        default: return Color(white: 0.95)
        }
    }

    var secondaryTextColor: Color {
        currentTheme == .system ? Color(nsColor: .secondaryLabelColor) : textColor.opacity(0.75)
    }

    var tertiaryTextColor: Color { textColor.opacity(0.60) }
    var surfaceColor: Color { textColor.opacity(0.06) }
    var borderColor: Color { textColor.opacity(0.22) }

    var accentColor: Color {
        switch currentTheme {
        case .system: return Color(nsColor: .controlAccentColor)
        case .light: return Color(red: 0.46, green: 0.24, blue: 0.72)
        case .dark: return Color(red: 0.72, green: 0.55, blue: 0.98)
        case .midnight: return Color(red: 0.37, green: 0.76, blue: 0.98)
        case .ember: return Color(red: 1.0, green: 0.65, blue: 0.36)
        case .forest: return Color(red: 0.48, green: 0.83, blue: 0.63)
        case .paper: return Color(red: 0.46, green: 0.27, blue: 0.16)
        }
    }

    var textOnAccentColor: Color {
        switch currentTheme {
        case .system: return Color(nsColor: .selectedMenuItemTextColor)
        case .light, .paper: return .white
        default: return Color(white: 0.08)
        }
    }

    var accentColorSubtle: Color { accentColor.opacity(0.22) }
}
