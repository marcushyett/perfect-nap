import Foundation

struct BedtimeSuggestion {
    let recommendedBedtime: Date
    let totalDaySleepMinutes: Int
    let targetNightHours: Double
    let rationale: String
}

/// Suggests an evening bedtime by combining:
///  - the age profile's pre-bedtime wake window (longest of the day for ≥4mo, shorter for newborns),
///  - the AAP/AASM 24-hour total-sleep guardrail,
///  - today's accumulated daytime sleep.
///
/// Returns nil when there isn't enough data yet (no completed sleep today) or when the baby is
/// currently napping — in that case the next prediction handles it.
enum BedtimeAdvisor {
    static func suggest(baby: Baby, lastSleep: NapSession?, napsToday: [NapSession], now: Date = .now) -> BedtimeSuggestion? {
        guard let last = lastSleep, last.endedAt != nil else { return nil }
        let profile = WakeWindowTable.profile(forAgeDays: baby.ageInDays)
        let completedNaps = napsToday.filter { $0.kind == .nap && $0.endedAt != nil }.count
        guard completedNaps >= profile.napsPerDay.lowerBound else { return nil }

        let typical = Double(profile.window.typicalMinutes)
        let factor = profile.preBedtimeFactor * clamp(baby.adaptationFactor)
        let preBedMinutes = typical * factor
        let endedAt = last.endedAt ?? now
        let rawBedtime = endedAt.addingTimeInterval(preBedMinutes * 60)

        let totalDayMinutes = napsToday
            .filter { $0.kind == .nap && $0.endedAt != nil }
            .reduce(0.0) { $0 + $1.duration } / 60.0

        let totalTarget24h = (profile.totalDaySleepHours.upperBound + profile.totalNightSleepHours.upperBound)
        let targetNightHours = max(profile.totalNightSleepHours.lowerBound,
                                   min(profile.totalNightSleepHours.upperBound,
                                       totalTarget24h - (totalDayMinutes / 60.0)))

        let calendar = Calendar.current
        let earliestBedtimeHour = profile.isSingleNapStage ? 18 : 18
        let latestBedtimeHour = profile.isSingleNapStage ? 21 : 21
        let dayStart = calendar.startOfDay(for: now)
        let earliest = calendar.date(byAdding: .hour, value: earliestBedtimeHour, to: dayStart) ?? rawBedtime
        let latest = calendar.date(byAdding: .hour, value: latestBedtimeHour, to: dayStart) ?? rawBedtime

        let bedtime = min(max(rawBedtime, earliest), latest)

        let rationale = """
        Last wake at \(short(endedAt)). Pre-bedtime window ≈ \(Int(preBedMinutes.rounded())) min for \(profile.label) (×\(String(format: "%.2f", factor))). \
        Today's daytime sleep so far: \(Int(totalDayMinutes)) min. AAP/AASM total target: \(Int(totalTarget24h)) h. \
        Targeting ~\(String(format: "%.1f", targetNightHours)) h overnight.
        """

        return BedtimeSuggestion(
            recommendedBedtime: bedtime,
            totalDaySleepMinutes: Int(totalDayMinutes),
            targetNightHours: targetNightHours,
            rationale: rationale
        )
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0.75), 1.25)
    }

    private static func short(_ date: Date) -> String {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f.string(from: date)
    }
}
