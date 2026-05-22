import Foundation
import ActivityKit

public struct NapActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var phase: Phase
        public var sessionStart: Date?
        public var nextNapAt: Date?
        public var babyName: String
        public var sleepKind: String
        /// When the most recent sleep ended — shown in the awake phase ("last woke 2:15 PM").
        public var lastEndedAt: Date?
        /// Latest healthy nap time — once `now` passes it the baby is overtired (shown as a warning).
        public var latestNapAt: Date?

        public init(phase: Phase, sessionStart: Date?, nextNapAt: Date?, babyName: String, sleepKind: String, lastEndedAt: Date? = nil, latestNapAt: Date? = nil) {
            self.phase = phase
            self.sessionStart = sessionStart
            self.nextNapAt = nextNapAt
            self.babyName = babyName
            self.sleepKind = sleepKind
            self.lastEndedAt = lastEndedAt
            self.latestNapAt = latestNapAt
        }
    }

    public enum Phase: String, Codable, Hashable {
        case napping
        case awake
    }

    public var babyName: String
    /// Identifies which baby this activity belongs to (Baby.id UUID string) so multiple babies can
    /// each have their own Live Activity.
    public var babyID: String

    public init(babyName: String, babyID: String = "") {
        self.babyName = babyName
        self.babyID = babyID
    }
}
