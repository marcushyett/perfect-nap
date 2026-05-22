import Foundation

/// Per-baby adaptation. We keep this deliberately small and explainable: a single multiplier on
/// the clinical wake-window baseline, updated by a Bayesian-flavoured exponential moving average.
///
/// Each *completed* nap of acceptable quality is one observation. The observation is the ratio
/// between the time-awake-before-this-nap and the clinical baseline. We pull the multiplier toward
/// that ratio, weighted by an evidence-strength term. With more observations, the multiplier
/// stabilises; the `confidence` field is purely informational for the UI.
struct AdaptiveModel {
    static let minimumFactor = 0.75
    static let maximumFactor = 1.25
    static let baseLearningRate = 0.18

    /// Called when a nap ends successfully. Returns the new factor + confidence.
    static func update(
        baby: Baby,
        endingNap: NapSession,
        previousSleepEnd: Date?,
        napsToday: [NapSession]
    ) -> (factor: Double, confidence: Double)? {
        guard endingNap.kind == .nap, endingNap.endedAt != nil else { return nil }
        guard endingNap.durationMinutes >= 25 else { return (baby.adaptationFactor, baby.adaptationConfidence) }
        guard let prevEnd = previousSleepEnd else { return (baby.adaptationFactor, baby.adaptationConfidence) }

        let awakeBefore = endingNap.start.timeIntervalSince(prevEnd) / 60.0
        guard awakeBefore > 10 else { return (baby.adaptationFactor, baby.adaptationConfidence) }

        let profile = WakeWindowTable.profile(forAgeDays: baby.ageInDays)

        // Don't learn from an implausibly long wake window — it almost always means a nap was
        // forgotten, not that this baby genuinely tolerates a huge window. Letting it through would
        // wrongly stretch the learned factor.
        let maxPlausibleWW = Double(profile.window.highMinutes) * SkippedNapDetector.implausibilityFactor
        guard awakeBefore <= maxPlausibleWW else { return (baby.adaptationFactor, baby.adaptationConfidence) }

        let napCount = napsToday.filter { $0.kind == .nap }.count
        let positionFactor: Double
        if previousWasNightSleep(previousSleepEnd: prevEnd, endingNap: endingNap) {
            positionFactor = profile.firstWindowFactor
        } else if napCount >= max(profile.napsPerDay.upperBound - 1, 1) {
            positionFactor = profile.preBedtimeFactor
        } else {
            positionFactor = 1.0
        }
        let expectedAwake = Double(profile.window.typicalMinutes) * positionFactor
        let ratio = awakeBefore / expectedAwake

        let clampedRatio = min(max(ratio, Self.minimumFactor), Self.maximumFactor)

        let confidence = baby.adaptationConfidence
        let lr = Self.baseLearningRate * (1.0 - confidence * 0.5)
        let newFactor = (1 - lr) * baby.adaptationFactor + lr * clampedRatio
        let bounded = min(max(newFactor, Self.minimumFactor), Self.maximumFactor)
        let newConfidence = min(confidence + 0.05, 1.0)
        return (bounded, newConfidence)
    }

    private static func previousWasNightSleep(previousSleepEnd: Date, endingNap: NapSession) -> Bool {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: previousSleepEnd)
        return hour < 10
    }
}
