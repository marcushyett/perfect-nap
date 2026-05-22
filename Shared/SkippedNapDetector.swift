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

        // Infer: nap started ~one typical window after the last wake, lasted a typical nap.
        let typicalWW = Double(profile.window.typicalMinutes) * adapt
        let napLen = BedtimePlanner.typicalNapMinutes(profile)
        var start = lastWake.addingTimeInterval(typicalWW * 60)
        var end = start.addingTimeInterval(napLen * 60)
        // Keep the inferred slot in the past, leaving a plausible post-nap window before now.
        let latestEnd = now.addingTimeInterval(-Double(profile.window.lowMinutes) * adapt * 60)
        if end > latestEnd {
            end = latestEnd
            start = min(start, end.addingTimeInterval(-napLen * 60))
        }
        guard end > start else { return nil }
        return SkippedNapInference(likelyStart: start, likelyEnd: end)
    }
}
