import Foundation

struct NapLengthEstimate: Equatable {
    let minutes: Int
    /// 0…1 — how much to trust the estimate, from sample size near the target time and consistency.
    let confidence: Double
    var confidencePercent: Int { Int((confidence * 100).rounded()) }
}

/// Estimates how long the *next* nap will last, by time of day. A baby's morning nap and late
/// afternoon nap are usually different lengths, so we weight past naps by how close their start time
/// was to the upcoming nap's time of day. Confidence reflects how much relevant data we have and how
/// consistent it is. Needs at least a day of history before it will produce a number.
enum NapLengthEstimator {
    private static func minutesOfDay(_ date: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
    }

    /// Circular distance between two times-of-day, in minutes (0…720).
    private static func todDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b)
        return min(d, 1440 - d)
    }

    /// `naps`: this baby's completed *nap* (not night) history as (start, durationMinutes).
    /// `targetStart`: when the upcoming nap will begin (we match its time of day).
    static func estimate(naps: [(start: Date, minutes: Double)], targetStart: Date, now: Date, profile: AgeProfile) -> NapLengthEstimate? {
        let valid = naps.filter { $0.minutes >= 15 }
        // Gate: need at least ~1 day of data — i.e. some nap logged more than 24h ago.
        guard valid.contains(where: { $0.start < now.addingTimeInterval(-24 * 3600) }) else { return nil }

        let target = minutesOfDay(targetStart)
        let sigma = 90.0 // naps within ~1.5h of the target time-of-day weigh strongly
        var wSum = 0.0, wDur = 0.0
        var weighted: [(w: Double, m: Double)] = []
        for nap in valid {
            let w = exp(-pow(todDistance(minutesOfDay(nap.start), target) / sigma, 2))
            wSum += w; wDur += w * nap.minutes
            weighted.append((w, nap.minutes))
        }
        guard wSum > 0 else { return nil }
        let mean = wDur / wSum

        // Effective sample size near the target time → more relevant naps = higher confidence.
        let sampleFactor = min(1.0, wSum / 4.0)
        // Consistency: weighted coefficient of variation of the relevant durations.
        let variance = weighted.reduce(0.0) { $0 + $1.w * pow($1.m - mean, 2) } / wSum
        let cv = mean > 0 ? sqrt(variance) / mean : 1
        let consistencyFactor = max(0.0, 1.0 - cv)
        let confidence = min(0.95, max(0.1, sampleFactor * consistencyFactor))

        // With a strong observed pattern, trust it (even a habitual mid-cycle short-napper). With
        // little data, lean on the cycle-aligned prior — babies surface/wake at cycle ends, so a
        // natural nap is ~1, 2 or 3 cycles.
        guard confidence < 0.5 else {
            return NapLengthEstimate(minutes: max(15, Int(mean.rounded())), confidence: confidence)
        }
        let cycle = Double(profile.sleepCycleMinutes)
        let cycles = max(1, (mean / cycle).rounded())
        return NapLengthEstimate(minutes: max(15, Int((cycles * cycle).rounded())), confidence: confidence)
    }
}
