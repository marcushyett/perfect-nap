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
    /// Set by the owner to mirror their Premium status. Travels through the CloudKit share so a
    /// partner viewing this baby inherits Premium — one subscription per family. Default false.
    @NSManaged var ownerHasPremium: Bool
    /// This baby's sleep sessions (inverse of NapSession.baby). The relationship — not the babyID
    /// string — is what lets CloudKit include the naps when the baby is shared with a partner.
    @NSManaged var sessions: NSSet?

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
    /// Core Data relationship to the owning baby (inverse of Baby.sessions). Distinct from `babyID`:
    /// this is what CloudKit traverses to include the nap when the baby is shared. Kept in sync with
    /// `babyID` on create + by a launch-time backfill for naps that predate the relationship.
    @NSManaged var baby: Baby?

    @discardableResult
    static func create(
        in context: NSManagedObjectContext,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        kind: SleepKind = .nap,
        note: String = "",
        babyID: UUID? = nil,
        baby: Baby? = nil
    ) -> NapSession {
        let s = NapSession(context: context)
        s.id = UUID()
        s.startedAt = startedAt
        s.endedAt = endedAt
        s.kindRaw = kind.rawValue
        s.note = note
        s.babyID = babyID ?? baby?.id
        s.baby = baby
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

    static func classify(start: Date, bedtimeMinutes: Int? = nil, calendar: Calendar = .current) -> SleepKind {
        SleepKind.classify(start: start, bedtimeMinutes: bedtimeMinutes, calendar: calendar)
    }
}

@objc(Trip)
final class Trip: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var originTZ: String?
    @NSManaged var destinationTZ: String?
    @NSManaged var departureDate: Date?
    @NSManaged var arrivalDate: Date?
    @NSManaged var returnDate: Date?
    @NSManaged var strategyRaw: String?
    /// True when the trip is already underway (arrival is in the past) — drives the "already landed" flow.
    @NSManaged var alreadyLanded: Bool
    @NSManaged var createdAt: Date?

    @discardableResult
    static func create(
        in context: NSManagedObjectContext,
        originTZ: String,
        destinationTZ: String,
        departure: Date,
        arrival: Date,
        returnDate: Date? = nil,
        strategy: TripStrategy = .adaptAfter,
        alreadyLanded: Bool = false,
        createdAt: Date = .now
    ) -> Trip {
        let t = Trip(context: context)
        t.id = UUID()
        t.originTZ = originTZ
        t.destinationTZ = destinationTZ
        t.departureDate = departure
        t.arrivalDate = arrival
        t.returnDate = returnDate
        t.strategyRaw = strategy.rawValue
        t.alreadyLanded = alreadyLanded
        t.createdAt = createdAt
        return t
    }

    var strategy: TripStrategy {
        get { TripStrategy(rawValue: strategyRaw ?? "") ?? .adaptAfter }
        set { strategyRaw = newValue.rawValue }
    }

    var originTimeZone: TimeZone? { originTZ.flatMap(TimeZone.init(identifier:)) }
    var destinationTimeZone: TimeZone? { destinationTZ.flatMap(TimeZone.init(identifier:)) }

    /// The trip is over (no more easing to do) once we're well past the return date, or — for a
    /// one-way trip — long past arrival. Used to stop surfacing a stale trip.
    func isStale(now: Date = .now) -> Bool {
        if let returnDate { return now > returnDate.addingTimeInterval(10 * 86_400) }
        if let arrivalDate { return now > arrivalDate.addingTimeInterval(21 * 86_400) }
        return false
    }
}

// Stable identity for SwiftUI ForEach / sheet(item:). The UUID is always set in `create(...)`.
extension NapSession: Identifiable {}
extension Baby: Identifiable {}
extension Trip: Identifiable {}
