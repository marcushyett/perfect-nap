import Foundation

/// Detects a likely *unlogged* nap: if the baby has been "awake" far longer than the age-typical
/// maximum wake window and no nap is on record, the most probable explanation (for a baby who still
/// naps) is that a nap happened and wasn't logged. We then (a) anchor predictions from the inferred
/// nap rather than the stale last-wake, and (b) nudge the user to backdate it.
struct SkippedNapInference: Equatable {
    /// Best-guess slot for the missed nap.
    let likelyStart: Date
    let likelyEnd: Date
}

enum SkippedNapDetector {
    /// Multiple of the age max wake window beyond which an unlogged nap is the likely explanation.
    static let implausibilityFactor = 1.5

    static func detect(
        lastWake: Date,
        now: Date,
        profile: AgeProfile,
        adaptationFactor: Double
    ) -> SkippedNapInference? {
        // Only meaningful where napping is still *expected* (lower bound ≥ 1). For toddlers/children
        // whose schedule allows zero naps, a long wake window is normal — don't cry "missed nap".
        guard profile.napsPerDay.lowerBound >= 1 else { return nil }

        let adapt = min(max(adaptationFactor, 0.75), 1.25)
        let maxWW = Double(profile.window.highMinutes) * adapt
        let elapsedMin = now.timeIntervalSince(lastWake) / 60.0
        guard elapsedMin > maxWW * implausibilityFactor else { return nil }

        // Infer: nap started ~one typical window after the last wake, lasted a typical nap. These are
        // anchored to the (fixed) last wake — NOT clamped to `now` — so the inferred slot, and the
        // prediction that re-anchors from it, stay put as the clock ticks instead of drifting with
        // `now` (which made the home screen flicker between "next nap in 0m" and "overdue by 0 min").
        let typicalWW = Double(profile.window.typicalMinutes) * adapt
        let napLen = BedtimePlanner.typicalNapMinutes(profile)
        let start = lastWake.addingTimeInterval(typicalWW * 60)
        let end = start.addingTimeInterval(napLen * 60)
        // Only infer a nap that has plausibly already happened (ended in the past).
        guard end < now, end > start else { return nil }
        return SkippedNapInference(likelyStart: start, likelyEnd: end)
    }
}
