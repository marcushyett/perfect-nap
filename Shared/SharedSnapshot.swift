import Foundation

/// A small Codable snapshot persisted to the shared App Group container.
/// The main app writes it after every state change; the widget extension reads it on each timeline
/// refresh so widgets can show real countdowns without needing access to the SwiftData store.
public struct SharedSnapshot: Codable, Equatable {
    public var babyName: String
    public var ageDescription: String
    public var activeStartedAt: Date?
    public var activeKind: String?
    public var nextNapAt: Date?
    public var earliestNapAt: Date?
    public var latestNapAt: Date?
    public var napsTodayCount: Int
    public var lastNapEndedAt: Date?
    public var lastNapDurationMinutes: Int
    public var generatedAt: Date

    public init(
        babyName: String,
        ageDescription: String,
        activeStartedAt: Date?,
        activeKind: String?,
        nextNapAt: Date?,
        earliestNapAt: Date?,
        latestNapAt: Date?,
        napsTodayCount: Int,
        lastNapEndedAt: Date?,
        lastNapDurationMinutes: Int,
        generatedAt: Date = .now
    ) {
        self.babyName = babyName
        self.ageDescription = ageDescription
        self.activeStartedAt = activeStartedAt
        self.activeKind = activeKind
        self.nextNapAt = nextNapAt
        self.earliestNapAt = earliestNapAt
        self.latestNapAt = latestNapAt
        self.napsTodayCount = napsTodayCount
        self.lastNapEndedAt = lastNapEndedAt
        self.lastNapDurationMinutes = lastNapDurationMinutes
        self.generatedAt = generatedAt
    }
}

public enum SharedSnapshotStore {
    public static let appGroupID = "group.com.marcushyett.perfectnap.shared"
    private static let filename = "snapshot.json"

    public static func write(_ snapshot: SharedSnapshot) {
        guard let url = fileURL() else { return }
        do {
            let data = try JSONEncoder.iso.encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            #if DEBUG
            print("SharedSnapshotStore write failed: \(error)")
            #endif
        }
    }

    public static func read() -> SharedSnapshot? {
        guard let url = fileURL(), FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder.iso.decode(SharedSnapshot.self, from: data)
        } catch {
            return nil
        }
    }

    public static func clear() {
        guard let url = fileURL() else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func fileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(filename)
    }
}

private extension JSONEncoder {
    static let iso: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

private extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
