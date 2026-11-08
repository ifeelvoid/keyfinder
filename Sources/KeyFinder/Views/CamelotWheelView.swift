import SwiftUI

/// Camelot wheel: outer ring B (major), inner ring A (minor). The selected key is filled,
/// harmonic moves from it are outlined in their Camelot hue, and keys present in the
/// library read brighter than empty ones.
struct CamelotWheelView: View {
    let selected: String?
    let compatible: Set<String>
    let counts: [String: Int]
    var centerKey: String? = nil
    @EnvironmentObject var theme: ThemeManager

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let badge = min(34, max(24, size * 0.1))
            let outer = size / 2 - badge / 2 - 2
            let inner = outer - badge * 1.25
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

            ZStack {
                Circle()
                    .strokeBorder(theme.textColor.opacity(0.12), lineWidth: 1)
                    .frame(width: (inner - badge * 0.9) * 2, height: (inner - badge * 0.9) * 2)
                    .position(center)
                VStack(spacing: 1) {
                    Text(selected ?? "--")
                        .font(.system(size: badge * 0.62, weight: .bold, design: .monospaced))
                        .foregroundColor(theme.textColor)
                    if let centerKey {
                        Text(centerKey)
                            .font(.system(size: badge * 0.34, weight: .medium, design: .monospaced))
                            .foregroundColor(theme.secondaryTextColor)
                    }
                }
                .position(center)

                ForEach(1...12, id: \.self) { number in
                    // 12 sits at the top, numbers run clockwise.
                    let angle = Double(number % 12) * 30 - 90
                    badgeView("\(number)B", size: badge).position(point(center, outer, angle))
                    badgeView("\(number)A", size: badge).position(point(center, inner, angle))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func point(_ center: CGPoint, _ radius: CGFloat, _ degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: center.x + radius * cos(radians), y: center.y + radius * sin(radians))
    }

    private func badgeView(_ camelot: String, size: CGFloat) -> some View {
        let isSelected = camelot == selected
        let isMove = !isSelected && compatible.contains(camelot)
        let count = counts[camelot] ?? 0
        let hue = KF.camelotColor(camelot)
        return Text(camelot)
            .font(.system(size: max(9, size * 0.34), weight: isSelected || isMove ? .bold : .medium, design: .monospaced))
            .foregroundColor(isSelected ? theme.backgroundColor
                             : isMove ? hue
                             : count > 0 ? theme.textColor : theme.tertiaryTextColor)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: size, height: size)
            .background(Circle().fill(isSelected ? theme.accentColor
                                      : isMove ? hue.opacity(0.16)
                                      : theme.textColor.opacity(count > 0 ? 0.07 : 0.03)))
            .overlay(Circle().strokeBorder(isSelected ? theme.accentColor
                                           : isMove ? hue.opacity(0.9)
                                           : theme.textColor.opacity(0.1), lineWidth: isMove ? 1.5 : 1))
            .help(count == 0 ? camelot : "\(camelot): \(count) track\(count == 1 ? "" : "s")")
    }

    private var accessibilitySummary: String {
        guard let selected else { return "Camelot wheel" }
        let moves = compatible.subtracting([selected]).sorted().joined(separator: ", ")
        return "Camelot wheel. Selected \(selected). Harmonic moves: \(moves)"
    }
}
