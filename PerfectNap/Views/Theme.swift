import SwiftUI

enum Theme {
    // Asleep gradient: always dim regardless of system color scheme.
    // Its job is to signal "baby is sleeping" — never blasts bright, safe to view at 3 a.m.
    static let asleepGradient = LinearGradient(
        colors: [Color(red: 0.10, green: 0.13, blue: 0.30), Color(red: 0.20, green: 0.18, blue: 0.45)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    private static let awakeGradientLight = LinearGradient(
        colors: [Color(red: 1.00, green: 0.90, blue: 0.72), Color(red: 1.00, green: 0.78, blue: 0.65)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    private static let awakeGradientDark = LinearGradient(
        colors: [Color(red: 0.09, green: 0.07, blue: 0.04), Color(red: 0.16, green: 0.12, blue: 0.07)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    private static let overdueGradientLight = LinearGradient(
        colors: [Color(red: 1.00, green: 0.62, blue: 0.40), Color(red: 0.95, green: 0.42, blue: 0.30)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    private static let overdueGradientDark = LinearGradient(
        colors: [Color(red: 0.20, green: 0.10, blue: 0.05), Color(red: 0.28, green: 0.14, blue: 0.07)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static func background(for mode: HomeMode, colorScheme: ColorScheme) -> LinearGradient {
        switch mode {
        case .napping: return asleepGradient
        case .overdue: return colorScheme == .dark ? overdueGradientDark : overdueGradientLight
        case .countingDown, .noPrediction: return colorScheme == .dark ? awakeGradientDark : awakeGradientLight
        }
    }

    static func awakeBackground(for colorScheme: ColorScheme) -> LinearGradient {
        colorScheme == .dark ? awakeGradientDark : awakeGradientLight
    }

    static func foreground(for mode: HomeMode, colorScheme: ColorScheme) -> Color {
        switch mode {
        case .napping:
            return Color(red: 0.93, green: 0.94, blue: 1.00)
        default:
            return colorScheme == .dark
                ? Color(red: 0.96, green: 0.91, blue: 0.82)
                : Color(red: 0.20, green: 0.15, blue: 0.10)
        }
    }
}

enum HomeMode {
    case napping
    case countingDown
    case overdue
    case noPrediction
}

struct PressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
