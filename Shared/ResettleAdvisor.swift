import Foundation

/// When a baby wakes early from a nap (before linking enough sleep cycles), the restorative value is
/// low and the next wake window would start under-rested. Practitioner guidance (Taking Cara Babies,
/// Precious Little Sleep "crib hour" short-nap extension) is to give the baby a short
/// chance to resettle and connect the next ~50-min cycle before ending the nap. After that window,
/// accept the nap is over and fall back to the normal (shortened-for-a-short-nap) prediction.
struct ResettleWindow: Equatable {
    /// Resettle attempts are worth it until this time; afterwards, go to the normal next-nap prediction.
    let until: Date
    let napMinutes: Int
}

enum ResettleAdvisor {
    /// How long to keep suggesting a resettle after the early wake.
    static let windowMinutes: Double = 20
    /// A nap shorter than this fraction of the age-typical nap counts as "short / incomplete".
    static let shortNapFraction = 0.65

    static func suggestion(
        lastNapEnd: Date?,
        lastNapMinutes: Double?,
        lastNapKind: SleepKind?,
        profile: AgeProfile,
        now: Date
    ) -> ResettleWindow? {
        guard lastNapKind == .nap, let end = lastNapEnd, let minutes = lastNapMinutes else { return nil }
        // Ignore mis-taps (sub-5-min) — those aren't real naps to resettle from.
        guard minutes >= 5 else { return nil }
        let typical = BedtimePlanner.typicalNapMinutes(profile)
        guard typical > 0, minutes < typical * shortNapFraction else { return nil }
        let until = end.addingTimeInterval(windowMinutes * 60)
        guard now < until else { return nil } // window passed → caller uses the normal prediction
        return ResettleWindow(until: until, napMinutes: Int(minutes.rounded()))
    }
}
