import XCTest
import SwiftData
import SQLite3
@testable import PerfectNap

/// A stand-in for the old @Model the pre-CloudKit app used. SwiftData persists `@Model X` to a
/// table `ZX` with columns `Z<UPPERCASE-PROPERTY>` and dates as seconds-since-2001 — exactly what
/// LegacyMigration's sqlite3 reader assumes. This proves that assumption against real output.
@Model final class MigFixtureBaby {
    var name: String = ""
    var birthDate: Date = Date()
    var createdAt: Date = Date()
    var adaptationFactor: Double = 1.0
    var adaptationConfidence: Double = 0.0
    init() {}
}

final class LegacyMigrationTests: XCTestCase {
    func testReaderMatchesSwiftDataOnDiskFormat() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("fixture.store")

        let birth = Date(timeIntervalSince1970: 1_600_000_000)
        let created = Date(timeIntervalSince1970: 1_650_000_000)

        // Write a row the way the old SwiftData app would have.
        do {
            let container = try ModelContainer(for: MigFixtureBaby.self, configurations: ModelConfiguration(url: storeURL))
            let ctx = ModelContext(container)
            let b = MigFixtureBaby()
            b.name = "Rosie"; b.birthDate = birth; b.createdAt = created
            b.adaptationFactor = 1.1; b.adaptationConfidence = 0.5
            ctx.insert(b)
            try ctx.save()
        }

        // Read it back with the production reader (table name = ZMIGFIXTUREBABY for this fixture).
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(storeURL.path, &db, SQLITE_OPEN_READWRITE, nil), SQLITE_OK)
        defer { sqlite3_close(db) }

        let babies = LegacyMigration.readBabies(db, table: "ZMIGFIXTUREBABY")
        XCTAssertEqual(babies.count, 1, "Reader should find the row in the Z-prefixed table.")
        XCTAssertEqual(babies.first?.name, "Rosie", "ZNAME column decoded.")
        XCTAssertEqual(babies.first?.birthDate.timeIntervalSince1970 ?? 0, birth.timeIntervalSince1970, accuracy: 1.0,
                       "Dates must decode as seconds-since-reference-date.")
        XCTAssertEqual(babies.first?.createdAt.timeIntervalSince1970 ?? 0, created.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertEqual(babies.first?.factor ?? 0, 1.1, accuracy: 0.001)
        XCTAssertEqual(babies.first?.confidence ?? 0, 0.5, accuracy: 0.001)
    }
}
