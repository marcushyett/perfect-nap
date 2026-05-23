import Foundation

struct NapPrediction: Equatable {
    let recommendedStart: Date
    let earliestStart: Date
    let latestStart: Date
    let usedWindowMinutes: Int
    let baselineMinutes: Int
    let position: WindowPosition
    let rationale: String
    let basedOnNapEnd: Date

    var isOverdue: Bool { recommendedStart <= .now }

    /// Where the baby sits on the sleep-pressure gradient right now.
    func status(at now: Date = .now) -> WakeWindowStatus {
        if now < earliestStart { return .building }
        if now <= latestStart { return .sweetSpot }
        return .overtired
    }

    /// Minutes past the latest healthy nap time (0 until overtired). Never negative.
    func minutesOvertired(at now: Date = .now) -> Int {
        max(0, Int(now.timeIntervalSince(latestStart) / 60))
    }

    /// Minutes until the recommended nap (0 once reached). Never negative.
    func minutesUntilRecommended(at now: Date = .now) -> Int {
        max(0, Int(recommendedStart.timeIntervalSince(now) / 60))
    }

    /// Minutes past the recommended nap time (0 until reached). Never negative. This is the
    /// user-facing "overdue by X" — measured from the recommended time, not the latest.
    func minutesOverdue(at now: Date = .now) -> Int {
        max(0, Int(now.timeIntervalSince(recommendedStart) / 60))
    }
}

/// The sleep-pressure gradient from the two-process model. Process S (homeostatic sleep pressure /
/// adenosine) builds with time awake; once it's high enough *and* aligned with the circadian dip the
/// baby settles easily — the "sweet spot." Stay awake past that and the body fights fatigue with a
/// cortisol/adrenaline "second wind" (overtired), which makes settling harder and fragments the
/// sleep that follows. (Borbély two-process model; Weissbluth; Karp; Taking Cara Babies; Huckleberry.)
enum WakeWindowStatus {
    case building     // not enough sleep pressure yet — too early
    case sweetSpot    // pressure + circadian aligned — easiest settle
    case overtired    // past the window — second-wind risk, hardest settle
}

enum WindowPosition: Equatable {
    case firstOfDay
    case middleOfDay
    case beforeBedtime

    var label: String {
        switch self {
        case .firstOfDay: return "first nap"
        case .middleOfDay: return "midday"
        case .beforeBedtime: return "pre-bedtime"
        }
    }
}

/// Predicts the optimal start time for the next nap given:
///  - baby's age (selects clinical wake window),
///  - last nap end time + duration (recent rest reduces sleep pressure),
///  - position in the day (first wake window is shorter; pre-bedtime is longer),
///  - per-baby adaptation factor learned from history.
struct NapPredictor {
    let baby: Baby
    let now: Date
    let calendar: Calendar

    init(baby: Baby, now: Date = .now, calendar: Calendar = .current) {
        self.baby = baby
        self.now = now
        self.calendar = calendar
    }

    /// Predict next nap start using the most recent completed sleep session and today's naps.
    /// `lastNightTotalSeconds` is the sum of all overnight sleep segments preceding this morning's
    /// wake-up; when the prediction is for the first wake window of the day, a short night shrinks
    /// it and a long night stretches it slightly. Pass nil if not known.
    func predict(
        lastSleep: NapSession?,
        napsToday: [NapSession],
        lastNightTotalSeconds: TimeInterval? = nil
    ) -> NapPrediction? {
        let profile = WakeWindowTable.profile(forAgeDays: baby.ageInDays)

        let anchorEnd: Date
        let position: WindowPosition
        let napQualityFactor: Double
        let isSynthetic: Bool

        if let last = lastSleep, let endedAt = last.endedAt {
            // Always anchor from the real last wake — so an overdue/overtired baby is reported as
            // such, not hidden behind an assumed nap. If a nap really was missed, the user backdates
            // it via the "did you forget to log a nap?" nudge (SkippedNapDetector powers that
            // separately), which then re-anchors from real data.
            anchorEnd = endedAt
            position = currentPosition(lastSleep: last, napsToday: napsToday, profile: profile)
            napQualityFactor = napQualityAdjustment(lastSleep: last, profile: profile)
            isSynthetic = false
        } else {
            // No prior sleep recorded — anchor the first wake window from now so the user always
            // sees a countdown. Position defaults to mid-day so age-typical baseline applies.
            anchorEnd = now
            position = .middleOfDay
            napQualityFactor = 1.0
            isSynthetic = true
        }

        let baselineMinutes = profile.window.typicalMinutes
        let positionFactor = position.factor(profile: profile)
        let nightFactor = nightQualityAdjustment(
            position: position,
            profile: profile,
            lastNightTotalSeconds: lastNightTotalSeconds
        )
        let adaptation = clampedAdaptation(baby.adaptationFactor)
        let dayLoad = dayLoadFactor(napsToday: napsToday, profile: profile)
        let sleepDebt = sleepDebtFactor(napsToday: napsToday, profile: profile)

        let combined = positionFactor * napQualityFactor * nightFactor * adaptation * dayLoad * sleepDebt

        let adjustedMinutes = Double(baselineMinutes) * combined
        let recommended = anchorEnd.addingTimeInterval(adjustedMinutes * 60)
        let lowRange = Double(profile.window.lowMinutes) * combined
        let highRange = Double(profile.window.highMinutes) * combined
        let earliest = anchorEnd.addingTimeInterval(lowRange * 60)
        let latest = anchorEnd.addingTimeInterval(highRange * 60)

        var rationale = buildRationale(
            profile: profile,
            position: position,
            positionFactor: positionFactor,
            napQualityFactor: napQualityFactor,
            nightFactor: nightFactor,
            adaptation: adaptation,
            baseline: baselineMinutes,
            adjusted: Int(adjustedMinutes.rounded()),
            lastNightTotalSeconds: lastNightTotalSeconds,
            isSynthetic: isSynthetic,
            dayLoad: dayLoad,
            sleepDebt: sleepDebt
        )

        var finalRecommended = recommended
        var finalEarliest = earliest
        var finalLatest = latest

        // When a target bedtime is set, plan backward from it — the bedtime anchor overrides the
        // pure forward wake-window for the *recommended* time, while the forward window stays as the
        // outer earliest/latest guardrail.
        if !isSynthetic,
           let targetBedtime = baby.targetBedtime(on: now),
           let plan = BedtimePlanner.plan(
               targetBedtime: targetBedtime,
               now: now,
               lastWake: anchorEnd,
               profile: profile,
               adaptationFactor: baby.adaptationFactor,
               completedNapsToday: napsToday.filter { $0.kind == .nap && $0.endedAt != nil }.count
           ) {
            finalRecommended = plan.recommendedNapStart
            finalEarliest = min(earliest, plan.recommendedNapStart)
            finalLatest = max(latest, plan.recommendedNapStart)
            let bedFmt = clockString(targetBedtime)
            if plan.isLastNapBeforeBed {
                rationale += " Bedtime-optimised: this is the last nap before your \(bedFmt) target — ending it ~\(Int((Double(profile.window.typicalMinutes) * profile.preBedtimeFactor).rounded())) min before bed hits the sweet spot."
            } else {
                rationale += " Bedtime-optimised for your \(bedFmt) target: \(plan.napsRemaining) naps to go, spaced to land at the bedtime sweet spot."
            }
            if plan.clampedToLimits {
                rationale += " (Adjusted to stay within a healthy wake window.)"
            }
        }

        return NapPrediction(
            recommendedStart: finalRecommended,
            earliestStart: finalEarliest,
            latestStart: finalLatest,
            usedWindowMinutes: Int(adjustedMinutes.rounded()),
            baselineMinutes: baselineMinutes,
            position: position,
            rationale: rationale,
            basedOnNapEnd: anchorEnd
        )
    }

    /// Only applies to the first wake window of the day. Compares last-night total sleep to the
    /// age-expected band; short night → shorter first WW, long night → slight stretch.
    /// Mid-day and pre-bedtime windows are unaffected (sleep pressure has already discharged).
    private func nightQualityAdjustment(
        position: WindowPosition,
        profile: AgeProfile,
        lastNightTotalSeconds: TimeInterval?
    ) -> Double {
        guard position == .firstOfDay, let seconds = lastNightTotalSeconds, seconds > 0 else { return 1.0 }
        let nightHours = seconds / 3600.0
        let lower = profile.totalNightSleepHours.lowerBound
        let upper = profile.totalNightSleepHours.upperBound
        let deficit = lower - nightHours
        let surplus = nightHours - upper
        if deficit >= 2.0 { return 0.80 }
        if deficit >= 1.0 { return 0.88 }
        if deficit > 0.25 { return 0.93 }
        if surplus >= 0.5 { return 1.05 }
        return 1.0
    }

    private func currentPosition(
        lastSleep: NapSession,
        napsToday: [NapSession],
        profile: AgeProfile
    ) -> WindowPosition {
        if lastSleep.kind == .night { return .firstOfDay }
        let napCount = napsToday.filter { $0.kind == .nap && $0.endedAt != nil }.count
        let expectedMaxNaps = profile.napsPerDay.upperBound
        if napCount >= max(expectedMaxNaps - 1, 1) { return .beforeBedtime }
        return .middleOfDay
    }

    /// A short nap releases less Process-S sleep pressure → shorter next window. A long nap allows
    /// the next window to stretch. Bands match consensus from Karp / Taking Cara Babies / Huckleberry:
    ///  - nap < 30 min: subtract ~30–45 min (≈ 0.75×)
    ///  - nap 30–45 min: subtract ~20–30 min (≈ 0.85×)
    ///  - nap 45–90 min: use age midpoint (1.00×)
    ///  - nap > 90 min: add ~15–30 min (≈ 1.10×)
    /// How the last nap's length shifts the next wake window. Sleep pressure (Process S) discharges
    /// in proportion to how much was slept: a short nap leaves more pressure → the next window
    /// shrinks; a long nap discharges more → it stretches. Graduated and age-relative (compared to
    /// the age-typical nap length), not a fixed absolute threshold.
    private func napQualityAdjustment(lastSleep: NapSession, profile: AgeProfile) -> Double {
        guard lastSleep.kind == .nap else { return 1.0 }
        let typical = BedtimePlanner.typicalNapMinutes(profile)
        guard typical > 0 else { return 1.0 }
        let ratio = Double(lastSleep.durationMinutes) / typical
        return min(max(1.0 + 0.3 * (ratio - 1.0), 0.75), 1.2)
    }

    /// Sleep-pressure / debt: if today's naps have run short (cumulative day sleep is low for the
    /// number of naps taken), the baby carries higher residual sleep pressure and tires faster, so
    /// the whole window — including the overtired (latest) edge — pulls earlier. This makes the
    /// overtired warning reflect sleep debt, not just time since the last nap.
    private func sleepDebtFactor(napsToday: [NapSession], profile: AgeProfile) -> Double {
        let naps = napsToday.filter { $0.kind == .nap && $0.endedAt != nil }
        guard !naps.isEmpty else { return 1.0 }
        let avgNap = naps.reduce(0.0) { $0 + Double($1.durationMinutes) } / Double(naps.count)
        let typical = BedtimePlanner.typicalNapMinutes(profile)
        guard typical > 0 else { return 1.0 }
        let ratio = avgNap / typical
        guard ratio < 0.8 else { return 1.0 }
        return max(0.85, 1.0 - (0.8 - ratio) * 0.4)
    }

    /// Stretches the window as the day's nap total fills the age day-sleep budget — once most of the
    /// needed day sleep is banked, sleep pressure rebuilds slower and the day should wind toward
    /// bedtime rather than over-napping (complements BedtimePlanner / NapCapPlanner).
    private func dayLoadFactor(napsToday: [NapSession], profile: AgeProfile) -> Double {
        let dayMinutes = napsToday.filter { $0.kind == .nap }.reduce(0.0) { $0 + Double($1.durationMinutes) }
        let budget = profile.totalDaySleepHours.upperBound * 60
        guard budget > 0 else { return 1.0 }
        let ratio = dayMinutes / budget
        guard ratio > 0.6 else { return 1.0 }
        return min(1.15, 1.0 + (ratio - 0.6) * 0.3)
    }

    private func clampedAdaptation(_ factor: Double) -> Double {
        min(max(factor, 0.75), 1.25)
    }

    private func clockString(_ date: Date) -> String {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
        return f.string(from: date)
    }

    private func buildRationale(
        profile: AgeProfile,
        position: WindowPosition,
        positionFactor: Double,
        napQualityFactor: Double,
        nightFactor: Double,
        adaptation: Double,
        baseline: Int,
        adjusted: Int,
        lastNightTotalSeconds: TimeInterval?,
        isSynthetic: Bool = false,
        dayLoad: Double = 1.0,
        sleepDebt: Double = 1.0
    ) -> String {
        var parts: [String] = []
        if isSynthetic {
            parts.append("No prior nap logged yet — using the age-typical baseline.")
        }
        parts.append("Baseline for \(profile.label): ~\(baseline) min awake.")
        if abs(positionFactor - 1.0) > 0.01 {
            let explanation = positionExplanation(profile: profile, position: position, factor: positionFactor)
            parts.append("\(explanation) (×\(String(format: "%.2f", positionFactor))).")
        }
        if napQualityFactor < 1.0 {
            parts.append("Last nap was short → next window shortened (×\(String(format: "%.2f", napQualityFactor))).")
        } else if napQualityFactor > 1.0 {
            parts.append("Last nap was long → next window stretched (×\(String(format: "%.2f", napQualityFactor))).")
        }
        if dayLoad > 1.01 {
            parts.append("Lots of day sleep banked already → window stretched toward bedtime (×\(String(format: "%.2f", dayLoad))).")
        }
        if sleepDebt < 0.99 {
            parts.append("Naps have run short today → sleep debt building, so the window (and overtired point) pull earlier (×\(String(format: "%.2f", sleepDebt))).")
        }
        if abs(nightFactor - 1.0) > 0.01, let seconds = lastNightTotalSeconds {
            let hours = seconds / 3600.0
            if nightFactor < 1.0 {
                parts.append("Last night was short (\(String(format: "%.1f", hours))h) → morning window shortened (×\(String(format: "%.2f", nightFactor))).")
            } else {
                parts.append("Last night was long (\(String(format: "%.1f", hours))h) → morning window stretched (×\(String(format: "%.2f", nightFactor))).")
            }
        }
        if abs(adaptation - 1.0) > 0.02 {
            let direction = adaptation > 1.0 ? "longer" : "shorter"
            parts.append("Personalised: this baby tends toward \(direction) windows (×\(String(format: "%.2f", adaptation))).")
        }
        parts.append("Recommended: ~\(adjusted) min after last wake.")
        return parts.joined(separator: " ")
    }

    private func positionExplanation(profile: AgeProfile, position: WindowPosition, factor: Double) -> String {
        switch position {
        case .firstOfDay:
            if profile.isSingleNapStage {
                return factor > 1.0 ? "Morning stretch is the longest of the day" : "Morning stretch is calibrated"
            }
            return "First wake window is typically the shortest of the day"
        case .middleOfDay:
            return "Mid-day window"
        case .beforeBedtime:
            if factor < 1.0 {
                return "Newborn witching-hour: last window shortens, not lengthens"
            }
            if profile.isSingleNapStage {
                return "Afternoon stretch to bedtime is shorter than the morning"
            }
            return "Pre-bedtime window is typically the longest of the day"
        }
    }
}

private extension WindowPosition {
    func factor(profile: AgeProfile) -> Double {
        switch self {
        case .firstOfDay: return profile.firstWindowFactor
        case .middleOfDay: return 1.0
        case .beforeBedtime: return profile.preBedtimeFactor
        }
    }
}
