import Foundation

/// Estimates how long the next nap will last. Starts from the age-typical nap length and, as the
/// baby accumulates logged naps, leans toward their own recent average — so the number personalises
/// over time rather than staying a generic age figure.
enum NapLengthEstimator {
    /// `recentNapMinutes` should be this baby's most-recent completed *nap* (not night) durations,
    /// newest first. Returns minutes.
    static func estimate(recentNapMinutes: [Double], profile: AgeProfile) -> Int {
        let ageTypical = BedtimePlanner.typicalNapMinutes(profile)
        // Ignore catnaps / mis-logs so a 4-minute false start doesn't drag the estimate down.
        let sample = Array(recentNapMinutes.filter { $0 >= 15 }.prefix(6))
        guard !sample.isEmpty else { return Int(ageTypical.rounded()) }

        let avg = sample.reduce(0, +) / Double(sample.count)
        // Trust the baby's own data more as the sample grows (0.4 → 0.8).
        let weight = min(0.8, 0.3 + 0.1 * Double(sample.count))
        let blended = avg * weight + ageTypical * (1 - weight)
        return max(15, Int(blended.rounded()))
    }
}
