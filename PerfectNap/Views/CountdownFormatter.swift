import Foundation

enum CountdownFormatter {
    /// Render a TimeInterval as a friendly H:MM string. Negative intervals are rendered as
    /// "-H:MM" so the UI can show overdue values too.
    static func string(from interval: TimeInterval) -> String {
        let abs = Swift.abs(interval)
        let totalSeconds = Int(abs.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let prefix = interval < 0 ? "-" : ""
        if hours > 0 {
            return String(format: "%@%d:%02d", prefix, hours, minutes)
        }
        return String(format: "%@%dm", prefix, minutes)
    }

    static func longString(from interval: TimeInterval) -> String {
        let totalSeconds = Int(Swift.abs(interval).rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}
