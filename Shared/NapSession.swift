import Foundation
import SwiftData

enum SleepKind: String, Codable, CaseIterable {
    case nap
    case night
}

@Model
final class NapSession {
    var startedAt: Date
    var endedAt: Date?
    var kind: SleepKind
    var note: String

    init(startedAt: Date = .now, endedAt: Date? = nil, kind: SleepKind = .nap, note: String = "") {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.kind = kind
        self.note = note
    }

    var isActive: Bool { endedAt == nil }

    var duration: TimeInterval {
        (endedAt ?? .now).timeIntervalSince(startedAt)
    }

    var durationMinutes: Int { Int(duration / 60) }

    static func classify(start: Date, calendar: Calendar = .current) -> SleepKind {
        let hour = calendar.component(.hour, from: start)
        return (hour >= 19 || hour < 5) ? .night : .nap
    }
}
