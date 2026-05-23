import Foundation

/// Detects a likely *unrecorded* night: it's morning, but barely any night sleep is on record for the
/// period that just ended (less than ~2 hours). That's the signature of a genuine user who didn't log
/// the night fully — not a real near-sleepless night. We assume a full baseline night (so the first
/// nap isn't wrongly shortened, see NapPredictor.nightQualityAdjustment) and surface a nudge to log
/// the real times. A reasonably-recorded night — even a slightly short one like 10 of 12h — is trusted
/// and produces no nudge.
struct MissingNightInference: Equatable {
    /// Prefilled "assumed" night for the log sheet — a baseline-length night ending around now.
    let suggestedStart: Date
    let suggestedEnd: Date
    /// The age-typical night length we're assuming, in hours (shown in the nudge copy).
    let assumedHours: Double
}

enum MissingNightDetector {
    /// Below this many hours of *recorded* recent night sleep, we treat last night as unrecorded.
    static let minRecordedNightHours = 2.0

    /// `recentNightSeconds` is the total **recorded** night sleep that ended in roughly the last
    /// half-day (i.e. last night). `lastSleepEnd` is the most recent completed sleep (nil if the user
    /// has no history at all).
    static func detect(
        recentNightSeconds: TimeInterval,
        lastSleepEnd: Date?,
        now: Date,
        profile: AgeProfile,
        calendar: Calendar = .current
    ) -> MissingNightInference? {
        // Only nudge in the morning — "did you record last night?" makes no sense in the afternoon.
        let hour = calendar.component(.hour, from: now)
        guard (5..<12).contains(hour) else { return nil }
        // Need some history; don't nudge a brand-new user with nothing logged.
        guard lastSleepEnd != nil else { return nil }
        // A reasonable amount of night sleep is on record → trust it, no nudge. Only an almost-empty
        // night (< ~2h) means it wasn't really recorded.
        guard recentNightSeconds < minRecordedNightHours * 3600 else { return nil }

        let band = profile.totalNightSleepHours
        let assumedHours = (band.lowerBound + band.upperBound) / 2
        let suggestedEnd = now
        let suggestedStart = now.addingTimeInterval(-assumedHours * 3600)
        return MissingNightInference(suggestedStart: suggestedStart, suggestedEnd: suggestedEnd, assumedHours: assumedHours)
    }
}
