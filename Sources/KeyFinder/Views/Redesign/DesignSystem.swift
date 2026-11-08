import SwiftUI

/// Shared look for the redesigned screens (docs/briefs/0009-app-redesign/design-reference.pdf).
/// Colours come from ThemeManager so every theme still works; these helpers only add the
/// mockup's type scale, card surfaces and Camelot hues.
enum KF {
    /// Uppercase, letter-spaced monospaced label ("NOW SELECTED", "TEMPO").
    static func label(_ text: String, size: CGFloat = 10) -> Text {
        Text(text.uppercased())
            .font(.system(size: size, weight: .medium, design: .monospaced))
            .kerning(1.6)
    }

    /// Numbers such as "170.7" with the decimal part smaller and dimmer.
    static func splitNumber(_ value: String, size: CGFloat, theme: ThemeManager) -> Text {
        let parts = display(value).split(separator: ".", maxSplits: 1)
        let whole = Text(String(parts.first ?? "--"))
            .font(.system(size: size, weight: .semibold, design: .monospaced))
            .foregroundColor(theme.textColor)
        guard parts.count == 2 else { return whole }
        return whole + Text("." + parts[1])
            .font(.system(size: size * 0.6, weight: .medium, design: .monospaced))
            .foregroundColor(theme.tertiaryTextColor)
    }

    /// Hue per Camelot number so compatible keys read as neighbours around the wheel.
    static func camelotColor(_ camelot: String?) -> Color {
        guard let camelot, let number = Int(camelot.dropLast()), (1...12).contains(number) else {
            return Color(white: 0.6)
        }
        // 4A/4B (F minor / A-flat major) land on the mockup's indigo.
        let hue = (Double(number - 1) / 12 + 0.42).truncatingRemainder(dividingBy: 1)
        return Color(hue: hue, saturation: 0.55, brightness: 1.0)
    }

    /// Engine placeholders read as an em dash instead of two heavy hyphens at display sizes.
    static func display(_ value: String?) -> String {
        guard let value, !value.isEmpty, value != "--" else { return "—" }
        return value
    }

    static func initials(_ name: String) -> String {
        let words = name.split { !$0.isLetter && !$0.isNumber }.prefix(2)
        let letters = words.compactMap(\.first).map { String($0).uppercased() }
        return letters.isEmpty ? "♪" : letters.joined()
    }
}

/// Rounded card used for the library table, panel cards and drop zone.
struct KFCard: ViewModifier {
    @EnvironmentObject var theme: ThemeManager
    var padding: CGFloat = 0
    var dashed = false
    var highlighted = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 10).fill(theme.textColor.opacity(dashed ? 0 : 0.025)))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(highlighted ? theme.accentColor : theme.textColor.opacity(0.09),
                                  style: StrokeStyle(lineWidth: 1, dash: dashed ? [5, 4] : []))
            )
    }
}

extension View {
    func kfCard(padding: CGFloat = 0, dashed: Bool = false, highlighted: Bool = false) -> some View {
        modifier(KFCard(padding: padding, dashed: dashed, highlighted: highlighted))
    }
}

/// "Fm 4A" pill tinted by the Camelot hue.
struct KeyPill: View {
    let key: String?
    let camelot: String?
    var large = false
    @EnvironmentObject var theme: ThemeManager

    var body: some View {
        let tint = KF.camelotColor(camelot)
        HStack(spacing: 6) {
            if let key { Text(key) }
            if let camelot { Text(camelot) }
            if key == nil && camelot == nil { Text("--") }
        }
        .font(.system(size: large ? 15 : 11, weight: .semibold, design: .monospaced))
        .foregroundColor(tint)
        .padding(.horizontal, large ? 10 : 8)
        .padding(.vertical, large ? 6 : 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(tint.opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(tint.opacity(0.35), lineWidth: 1))
    }
}

/// Outlined or filled top-bar / action button in the mockup's style.
struct KFButtonStyle: ButtonStyle {
    enum Kind { case primary, outline }
    var kind: Kind = .outline
    @EnvironmentObject var theme: ThemeManager
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(kind == .primary ? theme.backgroundColor : theme.textColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(kind == .primary ? theme.accentColor : theme.textColor.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(kind == .primary ? Color.clear : theme.textColor.opacity(0.14), lineWidth: 1)
            )
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }
}

/// Logo mark: ring with a centre dot, plus the tracked wordmark.
struct KFLogo: View {
    @EnvironmentObject var theme: ThemeManager

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().strokeBorder(theme.accentColor, lineWidth: 1.6)
                Circle().fill(theme.accentColor).frame(width: 7, height: 7)
            }
            .frame(width: 22, height: 22)
            Text("KEYFINDER")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .kerning(2.4)
                .foregroundColor(theme.textColor)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("KeyFinder")
    }
}
