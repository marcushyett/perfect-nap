import Foundation

struct WakeWindow {
    let lowMinutes: Int
    let typicalMinutes: Int
    let highMinutes: Int
}

struct AgeProfile {
    let label: String
    let maxAgeDays: Int
    let napsPerDay: ClosedRange<Int>
    let totalDaySleepHours: ClosedRange<Double>
    let totalNightSleepHours: ClosedRange<Double>
    let window: WakeWindow

    /// Multiplier on the typical window for the *first* wake window of the day.
    /// Multi-nap babies: first WW is the shortest (≈0.85).
    /// One-nap toddlers: first WW becomes the longest of the day (≈1.05–1.10).
    let firstWindowFactor: Double

    /// Multiplier for the last awake stretch before bedtime.
    /// Older babies (≥4mo): pre-bedtime WW is the longest of the day (≈1.15).
    /// Newborns (<3mo): the "witching hour" means pre-bedtime WW should be *shorter*, not longer (≈0.90).
    let preBedtimeFactor: Double

    /// True for ages where the single nap is in the middle of the day.
    /// Used to flip the meaning of `firstWindowFactor` / `preBedtimeFactor` for one-nap toddlers.
    let isSingleNapStage: Bool

    let notes: String
    let citation: String
}

/// Wake windows by age, grounded in pediatric sleep literature and the major consumer programs.
///
/// Sources (full URLs in `SleepSources.swift`):
///  - AAP / AASM Consensus (Paruthi et al. 2016, *J Clin Sleep Med* 12:785–6): 24-hr totals guardrail.
///  - Iglowstein et al. 2003 (*Pediatrics* 111:302–7): normative percentile curves.
///  - Borbély two-process model (review: Skeldon & Dijk, PMC9540767): why short naps shorten the
///    next window, why circadian gating only kicks in ~4 months.
///  - Weissbluth, *Healthy Sleep Habits, Happy Child* 5e.
///  - Mindell & Owens, *A Clinical Guide to Pediatric Sleep*.
///  - Practitioner consensus across Taking Cara Babies, Happiest Baby (Karp), Cleveland Clinic
///    pediatric sleep team (Barrett), Huckleberry SweetSpot®, Precious Little Sleep (Dubief).
///
/// Low/high are the *union* of source ranges; `typicalMinutes` is the practical algorithmic prior
/// before per-baby adaptation.
enum WakeWindowTable {
    static let profiles: [AgeProfile] = [
        AgeProfile(
            label: "Newborn (0–4 wks)",
            maxAgeDays: 28,
            napsPerDay: 4...6,
            totalDaySleepHours: 7.0...9.0,
            totalNightSleepHours: 8.0...9.0,
            window: WakeWindow(lowMinutes: 30, typicalMinutes: 45, highMinutes: 60),
            firstWindowFactor: 0.95,
            preBedtimeFactor: 0.90,
            isSingleNapStage: false,
            notes: "Polyphasic. Watch the baby, not the clock. Witching hour: pre-bed WW shortens.",
            citation: "Karp; Taking Cara Babies; Cleveland Clinic"
        ),
        AgeProfile(
            label: "1–2 months",
            maxAgeDays: 60,
            napsPerDay: 4...5,
            totalDaySleepHours: 6.0...8.0,
            totalNightSleepHours: 8.5...10.0,
            window: WakeWindow(lowMinutes: 45, typicalMinutes: 70, highMinutes: 90),
            firstWindowFactor: 0.90,
            preBedtimeFactor: 0.95,
            isSingleNapStage: false,
            notes: "Circadian rhythm beginning to consolidate. Bedtime still late (9–11pm).",
            citation: "Karp; Weissbluth; Huckleberry"
        ),
        AgeProfile(
            label: "2–3 months",
            maxAgeDays: 90,
            napsPerDay: 4...4,
            totalDaySleepHours: 5.0...7.0,
            totalNightSleepHours: 9.0...10.0,
            window: WakeWindow(lowMinutes: 60, typicalMinutes: 80, highMinutes: 105),
            firstWindowFactor: 0.90,
            preBedtimeFactor: 1.00,
            isSingleNapStage: false,
            notes: "Last WW lengthening as witching hour fades.",
            citation: "Taking Cara Babies; Huckleberry; Polly Moore (BRAC)"
        ),
        AgeProfile(
            label: "3–4 months",
            maxAgeDays: 120,
            napsPerDay: 3...4,
            totalDaySleepHours: 4.0...6.0,
            totalNightSleepHours: 10.0...11.0,
            window: WakeWindow(lowMinutes: 75, typicalMinutes: 100, highMinutes: 120),
            firstWindowFactor: 0.90,
            preBedtimeFactor: 1.10,
            isSingleNapStage: false,
            notes: "4-month regression. Sleep cycles mature to ~50 min. Process C begins to gate.",
            citation: "Karp; Cleveland Clinic; PMC9540767"
        ),
        AgeProfile(
            label: "4–5 months",
            maxAgeDays: 150,
            napsPerDay: 3...4,
            totalDaySleepHours: 3.5...5.0,
            totalNightSleepHours: 10.5...11.5,
            window: WakeWindow(lowMinutes: 90, typicalMinutes: 110, highMinutes: 135),
            firstWindowFactor: 0.88,
            preBedtimeFactor: 1.15,
            isSingleNapStage: false,
            notes: "Cap day sleep at ~4h to protect nights.",
            citation: "Huckleberry; Karp; Weissbluth"
        ),
        AgeProfile(
            label: "5–6 months",
            maxAgeDays: 180,
            napsPerDay: 3...3,
            totalDaySleepHours: 3.0...4.0,
            totalNightSleepHours: 11.0...12.0,
            window: WakeWindow(lowMinutes: 105, typicalMinutes: 130, highMinutes: 150),
            firstWindowFactor: 0.88,
            preBedtimeFactor: 1.15,
            isSingleNapStage: false,
            notes: "Most babies on 3 naps. 3rd nap is a short 'bridge' nap.",
            citation: "Taking Cara Babies; Huckleberry"
        ),
        AgeProfile(
            label: "6–8 months",
            maxAgeDays: 240,
            napsPerDay: 2...3,
            totalDaySleepHours: 2.5...3.5,
            totalNightSleepHours: 11.0...12.0,
            window: WakeWindow(lowMinutes: 135, typicalMinutes: 160, highMinutes: 210),
            firstWindowFactor: 0.88,
            preBedtimeFactor: 1.20,
            isSingleNapStage: false,
            notes: "3→2 nap transition window. Bedtime drifts to 7–8pm.",
            citation: "Huckleberry; Taking Cara Babies"
        ),
        AgeProfile(
            label: "8–10 months",
            maxAgeDays: 300,
            napsPerDay: 2...2,
            totalDaySleepHours: 2.0...3.5,
            totalNightSleepHours: 11.0...12.0,
            window: WakeWindow(lowMinutes: 150, typicalMinutes: 180, highMinutes: 240),
            firstWindowFactor: 0.90,
            preBedtimeFactor: 1.25,
            isSingleNapStage: false,
            notes: "Solid two-nap rhythm. Classic 3 / 3.5 / 4 hour wake-window shape.",
            citation: "Karp; Huckleberry"
        ),
        AgeProfile(
            label: "10–12 months",
            maxAgeDays: 365,
            napsPerDay: 2...2,
            totalDaySleepHours: 2.0...3.0,
            totalNightSleepHours: 11.0...12.0,
            window: WakeWindow(lowMinutes: 180, typicalMinutes: 210, highMinutes: 240),
            firstWindowFactor: 0.90,
            preBedtimeFactor: 1.25,
            isSingleNapStage: false,
            notes: "False readiness to drop to 1 nap; usually wait until 14–18 months.",
            citation: "Taking Cara Babies; Pampers Smart Sleep"
        ),
        AgeProfile(
            label: "12–15 months",
            maxAgeDays: 460,
            napsPerDay: 1...2,
            totalDaySleepHours: 2.0...3.0,
            totalNightSleepHours: 11.0...12.0,
            window: WakeWindow(lowMinutes: 210, typicalMinutes: 240, highMinutes: 270),
            firstWindowFactor: 0.95,
            preBedtimeFactor: 1.15,
            isSingleNapStage: false,
            notes: "2→1 transition (often 13–18m). If 2nd nap fights, push 1st nap later.",
            citation: "Huckleberry; Taking Cara Babies"
        ),
        AgeProfile(
            label: "15–18 months",
            maxAgeDays: 550,
            napsPerDay: 1...1,
            totalDaySleepHours: 1.5...2.5,
            totalNightSleepHours: 10.5...12.0,
            window: WakeWindow(lowMinutes: 240, typicalMinutes: 285, highMinutes: 330),
            firstWindowFactor: 1.05,
            preBedtimeFactor: 0.95,
            isSingleNapStage: true,
            notes: "Single midday nap. First WW is now the longest of the day.",
            citation: "Karp; Taking Cara Babies"
        ),
        AgeProfile(
            label: "18–24 months",
            maxAgeDays: 730,
            napsPerDay: 1...1,
            totalDaySleepHours: 1.0...2.0,
            totalNightSleepHours: 10.5...12.0,
            window: WakeWindow(lowMinutes: 300, typicalMinutes: 330, highMinutes: 360),
            firstWindowFactor: 1.05,
            preBedtimeFactor: 0.95,
            isSingleNapStage: true,
            notes: "Cap nap at ~2h, end by 3pm to protect bedtime.",
            citation: "Karp; Cleveland Clinic"
        ),
        AgeProfile(
            label: "2–3 years",
            maxAgeDays: 1095,
            napsPerDay: 0...1,
            totalDaySleepHours: 0.0...1.5,
            totalNightSleepHours: 10.0...12.0,
            window: WakeWindow(lowMinutes: 300, typicalMinutes: 360, highMinutes: 390),
            firstWindowFactor: 1.05,
            preBedtimeFactor: 0.95,
            isSingleNapStage: true,
            notes: "Some children drop the nap. If nap >1h, push bedtime later.",
            citation: "AAP/AASM; Iglowstein 2003"
        ),
        AgeProfile(
            label: "3+ years",
            maxAgeDays: 365 * 6,
            napsPerDay: 0...1,
            totalDaySleepHours: 0.0...1.5,
            totalNightSleepHours: 10.0...11.0,
            window: WakeWindow(lowMinutes: 360, typicalMinutes: 420, highMinutes: 480),
            firstWindowFactor: 1.0,
            preBedtimeFactor: 1.0,
            isSingleNapStage: true,
            notes: "Many drop the nap entirely. Bedtime 7–8pm.",
            citation: "AAP/AASM; Iglowstein 2003"
        )
    ]

    static func profile(forAgeDays days: Int) -> AgeProfile {
        for profile in profiles where days <= profile.maxAgeDays { return profile }
        return profiles.last!
    }
}

extension AgeProfile {
    /// Approximate sleep-cycle length for the age. Infant cycles run ~50 min and lengthen toward the
    /// adult ~90 min through early childhood; babies surface and wake most easily at a cycle
    /// boundary, so wake predictions and wake suggestions snap to these. (Grigg-Damberger 2016 on
    /// infant sleep architecture; Jenni & Carskadon; Mindell & Owens.)
    var sleepCycleMinutes: Int {
        switch maxAgeDays {
        case ..<91: return 50      // 0–3 months
        case ..<366: return 55     // 3–12 months
        case ..<731: return 65     // 12–24 months
        case ..<1096: return 75    // 2–3 years
        default: return 85         // 3+ years
        }
    }
}
