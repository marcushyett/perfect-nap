import Foundation

/// Learns the baby's own daily nap schedule from recent history: for each nap-of-day slot (0,1,2…)
/// it averages the start time-of-day across recent days, giving today's clock anchors. Slots without
/// enough history fall back to the generic age schedule (anchored to the morning wake). This is the
/// "dynamic schedule based on historic schedule" the prediction blends toward as the baby matures.
enum ScheduleLearner {
    static func anchors(
        history: [(start: Date, kind: SleepKind)],
        today: Date,
        morningWake: Date,
        profile: AgeProfile,
        calendar: Calendar = .current,
        minDays: Int = 3,
        lookbackDays: Int = 14
    ) -> [Date] {
        let cutoff = calendar.date(byAdding: .day, value: -lookbackDays, to: today) ?? today
        let naps = history.filter { $0.kind == .nap && $0.start >= cutoff && $0.start < calendar.startOfDay(for: today) }

        var byDay: [Date: [Date]] = [:]
        for n in naps { byDay[calendar.startOfDay(for: n.start), default: []].append(n.start) }

        var samplesByIndex: [Int: [Double]] = [:]
        for (_, starts) in byDay {
            for (i, s) in starts.sorted().enumerated() {
                let c = calendar.dateComponents([.hour, .minute], from: s)
                samplesByIndex[i, default: []].append(Double((c.hour ?? 0) * 60 + (c.minute ?? 0)))
            }
        }

        let typicalNaps = max(1, (profile.napsPerDay.lowerBound + profile.napsPerDay.upperBound) / 2)
        let dayStart = calendar.startOfDay(for: today)
        return (0..<typicalNaps).map { i in
            if let s = samplesByIndex[i], s.count >= minDays {
                return dayStart.addingTimeInterval((s.reduce(0, +) / Double(s.count)) * 60)
            }
            return DaySchedule.scheduledNapStart(napIndex: i, morningWake: morningWake, profile: profile)
        }
    }
}
