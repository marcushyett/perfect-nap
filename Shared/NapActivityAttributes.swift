import Foundation
import ActivityKit

public struct NapActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var phase: Phase
        public var sessionStart: Date?
        public var nextNapAt: Date?
        public var babyName: String
        public var sleepKind: String

        public init(phase: Phase, sessionStart: Date?, nextNapAt: Date?, babyName: String, sleepKind: String) {
            self.phase = phase
            self.sessionStart = sessionStart
            self.nextNapAt = nextNapAt
            self.babyName = babyName
            self.sleepKind = sleepKind
        }
    }

    public enum Phase: String, Codable, Hashable {
        case napping
        case awake
    }

    public var babyName: String

    public init(babyName: String) {
        self.babyName = babyName
    }
}
