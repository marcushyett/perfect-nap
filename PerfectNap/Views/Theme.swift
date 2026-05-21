import SwiftUI

enum Theme {
    static let asleepGradient = LinearGradient(
        colors: [Color(red: 0.10, green: 0.13, blue: 0.30), Color(red: 0.20, green: 0.18, blue: 0.45)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let awakeGradient = LinearGradient(
        colors: [Color(red: 1.00, green: 0.90, blue: 0.72), Color(red: 1.00, green: 0.78, blue: 0.65)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let overdueGradient = LinearGradient(
        colors: [Color(red: 1.00, green: 0.62, blue: 0.40), Color(red: 0.95, green: 0.42, blue: 0.30)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static func background(for mode: HomeMode) -> LinearGradient {
        switch mode {
        case .napping: return asleepGradient
        case .overdue: return overdueGradient
        case .countingDown, .noPrediction: return awakeGradient
        }
    }

    static func foreground(for mode: HomeMode) -> Color {
        mode == .napping ? .white : Color(red: 0.20, green: 0.15, blue: 0.10)
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
