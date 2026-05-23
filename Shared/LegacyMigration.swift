import Foundation
import CoreData
import SQLite3

/// Migrates pre-CloudKit data (the old SwiftData store) into the new Core Data + CloudKit store.
///
/// We read the old store's SQLite directly rather than via SwiftData: the old @Model classes were
/// named `Baby`/`NapSession`, and those names now belong to the Core Data NSManagedObject classes,
/// so we can't re-declare matching SwiftData models. Core Data / SwiftData persist to a stable
/// `Z`-prefixed SQLite schema (table `ZBABY`, columns `ZNAME` etc.; dates = seconds since the 2001
/// reference date), which we can read with sqlite3 regardless of model-version hashes.
///
/// Strictly non-destructive: the old store file is only ever read, never modified or deleted, so a
/// later migration version can recover anything an earlier (buggy) one missed.
enum LegacyMigration {
    // v2 — v1 read the wrong entity names and imported nothing; v2 re-runs to recover that data.
    private static let didMigrateKey = "perfectnap.didMigrateToCoreData.v2"
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: CoreDataStack.appGroupID) ?? .standard
    }

    struct LegacyBabyRow: Equatable { let name: String; let birthDate: Date; let createdAt: Date; let factor: Double; let confidence: Double }
    struct LegacyNapRow: Equatable { let startedAt: Date; let endedAt: Date?; let kindRaw: String; let note: String }

    @MainActor
    static func runIfNeeded(into context: NSManagedObjectContext) {
        guard !defaults.bool(forKey: didMigrateKey) else { return }

        // Only import into a fresh store — never duplicate onto data the user already has.
        let existingBabies = (try? context.count(for: Baby.fetchRequest())) ?? 0
        let existingNaps = (try? context.count(for: NapSession.fetchRequest())) ?? 0
        guard existingBabies == 0, existingNaps == 0 else {
            defaults.set(true, forKey: didMigrateKey)
            return
        }

        guard let storeURL = legacyStoreURL(), FileManager.default.fileExists(atPath: storeURL.path) else {
            defaults.set(true, forKey: didMigrateKey)
            return
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            defaults.set(true, forKey: didMigrateKey)
            return
        }
        defer { sqlite3_close(db) }

        let babies = readBabies(db)
        let naps = readNaps(db)
        guard !babies.isEmpty || !naps.isEmpty else {
            defaults.set(true, forKey: didMigrateKey)
            return
        }

        var firstBabyID: UUID?
        for b in babies {
            let baby = Baby.create(in: context, name: b.name, birthDate: b.birthDate, createdAt: b.createdAt)
            baby.adaptationFactor = b.factor
            baby.adaptationConfidence = b.confidence
            if firstBabyID == nil { firstBabyID = baby.id }
        }
        for n in naps {
            NapSession.create(in: context, startedAt: n.startedAt, endedAt: n.endedAt,
                              kind: SleepKind(rawValue: n.kindRaw) ?? .nap, note: n.note, babyID: firstBabyID)
        }
        try? context.save()
        defaults.set(true, forKey: didMigrateKey)
    }

    /// SwiftData's default store location (the pre-CloudKit app used the default container).
    private static func legacyStoreURL() -> URL? {
        NSPersistentContainer.defaultDirectoryURL().appendingPathComponent("default.store")
    }

    private static func date(_ stmt: OpaquePointer?, _ col: Int32) -> Date? {
        guard sqlite3_column_type(stmt, col) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSinceReferenceDate: sqlite3_column_double(stmt, col))
    }
    private static func text(_ stmt: OpaquePointer?, _ col: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, col) else { return "" }
        return String(cString: c)
    }

    static func readBabies(_ db: OpaquePointer?, table: String = "ZBABY") -> [LegacyBabyRow] {
        var rows: [LegacyBabyRow] = []
        var stmt: OpaquePointer?
        let sql = "SELECT ZNAME, ZBIRTHDATE, ZCREATEDAT, ZADAPTATIONFACTOR, ZADAPTATIONCONFIDENCE FROM \(table)"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(LegacyBabyRow(
                name: text(stmt, 0),
                birthDate: date(stmt, 1) ?? .now,
                createdAt: date(stmt, 2) ?? .now,
                factor: sqlite3_column_double(stmt, 3),
                confidence: sqlite3_column_double(stmt, 4)
            ))
        }
        return rows
    }

    static func readNaps(_ db: OpaquePointer?, table: String = "ZNAPSESSION") -> [LegacyNapRow] {
        var rows: [LegacyNapRow] = []
        var stmt: OpaquePointer?
        let sql = "SELECT ZSTARTEDAT, ZENDEDAT, ZKINDRAW, ZNOTE FROM \(table)"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let started = date(stmt, 0) else { continue }
            rows.append(LegacyNapRow(
                startedAt: started,
                endedAt: date(stmt, 1),
                kindRaw: text(stmt, 2),
                note: text(stmt, 3)
            ))
        }
        return rows
    }
}

enum DefaultSettings {
    private static let bedtimeKey = "perfectnap.didApplyDefaultBedtime.v1"
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: CoreDataStack.appGroupID) ?? .standard
    }

    /// One-time: turn bedtime optimisation on (7 PM) for babies that pre-date the feature.
    @MainActor
    static func applyDefaultBedtimeIfNeeded(in context: NSManagedObjectContext) {
        guard !defaults.bool(forKey: bedtimeKey) else { return }
        if let babies = try? context.fetch(Baby.fetchRequest()) {
            for baby in babies where baby.targetBedtimeMinutes == 0 { baby.targetBedtimeMinutes = 19 * 60 }
            try? context.save()
        }
        defaults.set(true, forKey: bedtimeKey)
    }

    /// Safety net: any nap missing a babyID gets attached to the earliest baby.
    @MainActor
    static func assignOrphanNapsIfNeeded(in context: NSManagedObjectContext) {
        let babyReq = Baby.fetchRequest()
        babyReq.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        guard let baby = (try? context.fetch(babyReq))?.first, let babyID = baby.id else { return }
        let napReq = NapSession.fetchRequest()
        napReq.predicate = NSPredicate(format: "babyID == nil")
        if let orphans = try? context.fetch(napReq), !orphans.isEmpty {
            for nap in orphans { nap.babyID = babyID }
            try? context.save()
        }
    }
}

extension Baby {
    static func fetchRequest() -> NSFetchRequest<Baby> { NSFetchRequest<Baby>(entityName: "Baby") }
}

extension NapSession {
    static func fetchRequest() -> NSFetchRequest<NapSession> { NSFetchRequest<NapSession>(entityName: "NapSession") }
}

extension Trip {
    static func fetchRequest() -> NSFetchRequest<Trip> { NSFetchRequest<Trip>(entityName: "Trip") }
}
