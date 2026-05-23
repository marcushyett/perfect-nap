import Foundation
import CoreData

@objc(Baby)
final class Baby: NSManagedObject, BabyProfileProviding {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var birthDate: Date?
    @NSManaged var createdAt: Date?
    @NSManaged var adaptationFactor: Double
    @NSManaged var adaptationConfidence: Double
    /// Target bedtime as minutes-from-midnight (e.g. 19*60+30 = 1170 for 7:30 PM). 0 = unset.
    @NSManaged var targetBedtimeMinutes: Int64
    /// Weeks born before due date. Drives corrected age for prematurity. 0 = full term.
    @NSManaged var weeksPremature: Int64
    /// User-set custom nap schedule as comma-separated minutes-from-midnight (e.g. "570,840" =
    /// 9:30 & 14:00). Empty/nil = automatic (learned-from-history / age schedule).
    @NSManaged var customScheduleMinutes: String?

    @discardableResult
    static func create(
        in context: NSManagedObjectContext,
        name: String = "Baby",
        birthDate: Date,
        createdAt: Date = .now
    ) -> Baby {
        let b = Baby(context: context)
        b.id = UUID()
        b.name = name
        b.birthDate = birthDate
        b.createdAt = createdAt
        b.adaptationFactor = 1.0
        b.adaptationConfidence = 0.0
        return b
    }

    var displayName: String { name ?? "Baby" }

    /// Custom schedule nap start times as minutes-from-midnight (sorted), or [] for automatic.
    var customNapMinutes: [Int] {
        get { (customScheduleMinutes ?? "").split(separator: ",").compactMap { Int($0) }.sorted() }
        set { customScheduleMinutes = newValue.isEmpty ? nil : newValue.sorted().map(String.init).joined(separator: ",") }
    }

    /// Target bedtime as a time-of-day today, or nil if unset.
    func targetBedtime(on day: Date = .now, calendar: Calendar = .current) -> Date? {
        guard targetBedtimeMinutes > 0 else { return nil }
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .minute, value: Int(targetBedtimeMinutes), to: start)
    }

    var ageInDays: Int {
        guard let birthDate else { return 0 }
        return Calendar.current.dateComponents([.day], from: birthDate, to: .now).day ?? 0
    }
    var ageInWeeks: Int { ageInDays / 7 }

    /// Corrected age for prematurity. Per AAP practice, correction applies fully through ~12 months
    /// and then tapers to zero by ~24 months (the difference matters hugely at 4 months, negligibly
    /// by 2 years). All sleep predictions use this; the displayed age stays chronological.
    var adjustedAgeInDays: Int {
        let chrono = ageInDays
        guard weeksPremature > 0 else { return chrono }
        let fullCorrection = Int(weeksPremature) * 7
        if chrono <= 365 { return max(0, chrono - fullCorrection) }      // full correction ≤12mo
        if chrono >= 730 { return chrono }                               // none ≥24mo
        let remaining = 1.0 - Double(chrono - 365) / 365.0               // linear taper 12→24mo
        return max(0, chrono - Int(Double(fullCorrection) * remaining))
    }
    var ageInMonths: Int {
        guard let birthDate else { return 0 }
        return Calendar.current.dateComponents([.month], from: birthDate, to: .now).month ?? 0
    }

    var ageDescription: String {
        let months = ageInMonths
        if months < 1 {
            let weeks = ageInWeeks
            return weeks <= 1 ? "\(ageInDays) days old" : "\(weeks) weeks old"
        }
        if months < 24 { return "\(months) month\(months == 1 ? "" : "s") old" }
        let years = months / 12
        let remainderMonths = months % 12
        if remainderMonths == 0 { return "\(years) year\(years == 1 ? "" : "s") old" }
        return "\(years)y \(remainderMonths)m old"
    }
}

@objc(NapSession)
final class NapSession: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var startedAt: Date?
    @NSManaged var endedAt: Date?
    @NSManaged var kindRaw: String?
    @NSManaged var note: String?
    /// The baby this sleep belongs to (matches Baby.id). Enables multiple babies per account.
    @NSManaged var babyID: UUID?

    @discardableResult
    static func create(
        in context: NSManagedObjectContext,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        kind: SleepKind = .nap,
        note: String = "",
        babyID: UUID? = nil
    ) -> NapSession {
        let s = NapSession(context: context)
        s.id = UUID()
        s.startedAt = startedAt
        s.endedAt = endedAt
        s.kindRaw = kind.rawValue
        s.note = note
        s.babyID = babyID
        return s
    }

    var kind: SleepKind {
        get { SleepKind(rawValue: kindRaw ?? "") ?? .nap }
        set { kindRaw = newValue.rawValue }
    }

    var start: Date { startedAt ?? .now }

    var isActive: Bool { endedAt == nil }

    var duration: TimeInterval {
        (endedAt ?? .now).timeIntervalSince(start)
    }

    var durationMinutes: Int { Int(duration / 60) }

    static func classify(start: Date, calendar: Calendar = .current) -> SleepKind {
        SleepKind.classify(start: start, calendar: calendar)
    }
}

// Stable identity for SwiftUI ForEach / sheet(item:). The UUID is always set in `create(...)`.
extension NapSession: Identifiable {}
extension Baby: Identifiable {}
