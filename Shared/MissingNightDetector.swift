import Foundation

/// Detects a likely *unrecorded* night: it's morning, but the most recent logged sleep ended long
/// enough ago that a whole night has since passed without being recorded. Without a logged night the
/// app can't see that the day reset (it would anchor the morning from yesterday's last nap), so we
/// surface a nudge to log it. The prediction meanwhile assumes the baseline amount of night sleep
/// (see NapPredictor.nightQualityAdjustment, which treats a missing/implausible night as neutral).
struct MissingNightInference: Equatable {
    /// Prefilled "assumed" night for the log sheet — a baseline-length night ending around now.
    let suggestedStart: Date
    let suggestedEnd: Date
    /// The age-typical night length we're assuming, in hours (shown in the nudge copy).
    let assumedHours: Double
}

enum MissingNightDetector {
    /// `lastSleepKind` / `lastSleepEnd` describe the most recent *completed* sleep (nil if none logged).
    static func detect(
        lastSleepKind: SleepKind?,
        lastSleepEnd: Date?,
        now: Date,
        profile: AgeProfile,
        calendar: Calendar = .current
    ) -> MissingNightInference? {
        // Only nudge in the morning — "did you record last night?" makes no sense in the afternoon.
        let hour = calendar.component(.hour, from: now)
        guard (5..<12).contains(hour) else { return nil }
        // Need some history; don't nudge a brand-new user mid-onboarding.
        guard let kind = lastSleepKind, let end = lastSleepEnd else { return nil }
        // A night that ended within the last few hours means last night *is* recorded → nothing to do.
        if kind == .night, now.timeIntervalSince(end) < 6 * 3600 { return nil }
        // Otherwise the most recent logged sleep ended long enough ago that a full night has since
        // passed unrecorded (e.g. the last thing on file is yesterday afternoon's nap).
        guard now.timeIntervalSince(end) >= 8 * 3600 else { return nil }

        let band = profile.totalNightSleepHours
        let assumedHours = (band.lowerBound + band.upperBound) / 2
        let suggestedEnd = now
        let suggestedStart = now.addingTimeInterval(-assumedHours * 3600)
        return MissingNightInference(suggestedStart: suggestedStart, suggestedEnd: suggestedEnd, assumedHours: assumedHours)
    }
}
