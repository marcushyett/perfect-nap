import Foundation

/// Manual jet-lag easing for travel across time zones — works for a baby, a child, or an adult.
///
/// The science (CDC Yellow Book; Eastman/Burgess light-protocol studies; pediatric sleep consensus):
///  - The body clock re-entrains at roughly an hour a day. **Phase advance** (eastward — destination
///    clock is *ahead*, you must sleep earlier) is the harder direction (~1h/day); **phase delay**
///    (westward — sleep later) is easier (~1.5h/day).
///  - Infants re-entrain fastest (1–2 days), older children and adults slowest.
///  - Light is the strongest lever: morning light advances the clock (eastward), evening light delays
///    it (westward). We surface that as guidance.
///  - For a small shift (≤2h) or a short stay (<3 days) it is gentler to *stay on home time* than to
///    drag everyone across and back.
///
/// Geometry of the offset we hand back (positive = shift the schedule **later**, same convention as
/// `DSTAdjuster`): the body's *progress* toward the destination is a continuous ramp. While still in
/// the origin zone (pre-adapt) the device clock is origin-local, so progress shows up as a schedule
/// shift of `−progress`. Once in the destination zone the device clock has jumped, so the *residual*
/// misalignment shows up as `+residual`. The step between the two at landing is exactly the time-zone
/// jump — the body never teleports, only the wall clock does.
struct JetLagPlan: Equatable {
    enum Phase: String, Equatable {
        case upcoming      // trip soon; no shift yet (adapt-after, or before the pre-adapt window)
        case preAdapt      // shifting the home schedule toward the destination before departure
        case adapting      // landed; ramping the schedule from origin-aligned to destination-aligned
        case stayOnHome    // short trip / tiny shift — keep the home schedule, don't bother adapting
        case settled       // fully adjusted to the destination
        case adaptingHome  // returned home; ramping back to the home schedule
    }

    let phase: Phase
    /// Minutes to add to device-local schedule anchors (positive = later). Composes with DST.
    let scheduleOffsetMinutes: Int
    let daysRemaining: Int
    let destinationName: String
    let originName: String
    /// True when the harder, eastward "sleep earlier" direction governs the active leg.
    let directionIsAdvance: Bool
    let signedShiftMinutes: Int
    let headline: String
    let detail: String
    let lightGuidance: String
}

enum JetLagPlanner {
    static let baseAdvanceMinutesPerDay = 60.0  // eastward, harder
    static let baseDelayMinutesPerDay = 90.0    // westward, easier
    static let maxPreAdaptDays = 3
    static let stayOnHomeShiftCapMinutes = 120  // ≤2h: not worth dragging everyone across
    static let stayOnHomeStayDays = 3
    static let settledThresholdMinutes = 20

    static func plan(originTZ: TimeZone,
                     destinationTZ: TimeZone,
                     departure: Date,
                     arrival: Date,
                     returnDate: Date?,
                     strategy: TripStrategy,
                     ageDays: Int,
                     now: Date = .now,
                     calendar: Calendar = .current) -> JetLagPlan? {
        let originName = cityName(originTZ)
        let destinationName = cityName(destinationTZ)

        // Signed shift, normalised to the shorter way round (−12h, +12h]. Positive = destination ahead
        // = eastward = phase advance.
        let rawMinutes = (destinationTZ.secondsFromGMT(for: arrival) - originTZ.secondsFromGMT(for: departure)) / 60
        let signedShift = normalisedShift(rawMinutes)

        // A negligible shift isn't jet lag at all.
        guard abs(signedShift) >= 30 else { return nil }

        let isReturning = returnDate.map { now >= $0 } ?? false
        let inDestination = now >= arrival && !isReturning

        // ----- Return leg: ramp back to the home schedule (device clock is home again) -----
        if isReturning, let returnDate {
            let shift = -signedShift                       // dest → home reverses the direction
            let advance = shift > 0
            let rate = dailyRate(advance: advance, ageDays: ageDays)
            let elapsed = Double(max(0, calendarDaysBetween(returnDate, now, calendar)))
            let residual = max(0, Double(abs(shift)) - rate * elapsed)
            if residual <= Double(settledThresholdMinutes) { return nil }   // home & adjusted → done
            let offset = Int((residual * Double(sign(shift))).rounded())
            let days = Int((residual / rate).rounded(.up))
            return JetLagPlan(
                phase: .adaptingHome,
                scheduleOffsetMinutes: offset,
                daysRemaining: days,
                destinationName: originName, originName: destinationName,
                directionIsAdvance: advance, signedShiftMinutes: shift,
                headline: "Settling back into \(originName)",
                detail: "About \(days) more day\(days == 1 ? "" : "s") to fully reset to home time.",
                lightGuidance: lightGuidance(advance: advance, ageDays: ageDays))
        }

        let advance = signedShift > 0
        let rate = dailyRate(advance: advance, ageDays: ageDays)
        let daysUntilDeparture = calendarDaysBetween(now, departure, calendar)

        // Short trip / tiny shift: gentler to stay on home time than to drag everyone across and back.
        let stayDays = returnDate.map { calendarDaysBetween(arrival, $0, calendar) }
        let stayOnHome = abs(signedShift) <= stayOnHomeShiftCapMinutes || (stayDays ?? Int.max) < stayOnHomeStayDays
        if stayOnHome {
            if inDestination {
                return JetLagPlan(
                    phase: .stayOnHome,
                    scheduleOffsetMinutes: signedShift,       // keep the origin schedule, expressed in dest clock
                    daysRemaining: 0,
                    destinationName: destinationName, originName: originName,
                    directionIsAdvance: advance, signedShiftMinutes: signedShift,
                    headline: "Keeping \(destinationName) on home time",
                    detail: (stayDays ?? Int.max) < stayOnHomeStayDays
                        ? "It's a short trip — staying on home time avoids unsettling everyone twice."
                        : "The time difference is small — staying on home time is gentler than adjusting.",
                    lightGuidance: "No light changes needed — keep your usual day.")
            }
            guard daysUntilDeparture <= 7 else { return nil }
            return upcomingPlan(daysUntilDeparture: daysUntilDeparture, stayOnHome: true,
                                strategy: strategy, advance: advance, signedShift: signedShift,
                                destinationName: destinationName, originName: originName, ageDays: ageDays)
        }

        // Unified ramp anchor: the body re-entrains from a single start date, so pre-departure progress
        // carries continuously through landing (the displayed offset jumps only because the clock does).
        let preAdaptDays = min(maxPreAdaptDays, Int((Double(abs(signedShift)) / rate).rounded(.up)))
        let adaptStart = strategy == .adaptBefore
            ? (calendar.date(byAdding: .day, value: -preAdaptDays, to: departure) ?? departure)
            : arrival
        let elapsed = Double(max(0, calendarDaysBetween(adaptStart, now, calendar)))
        let progress = min(Double(abs(signedShift)), rate * elapsed)
        let residual = Double(abs(signedShift)) - progress

        // ----- Landed: residual misalignment shows as a shift back toward origin, ramping to zero -----
        if inDestination {
            if residual <= Double(settledThresholdMinutes) {
                return JetLagPlan(
                    phase: .settled, scheduleOffsetMinutes: 0, daysRemaining: 0,
                    destinationName: destinationName, originName: originName,
                    directionIsAdvance: advance, signedShiftMinutes: signedShift,
                    headline: "Adjusted to \(destinationName)",
                    detail: "Body clock has caught up to local time. Enjoy the trip!",
                    lightGuidance: lightGuidance(advance: advance, ageDays: ageDays))
            }
            let offset = Int((residual * Double(sign(signedShift))).rounded())
            let days = Int((residual / rate).rounded(.up))
            return JetLagPlan(
                phase: .adapting, scheduleOffsetMinutes: offset, daysRemaining: days,
                destinationName: destinationName, originName: originName,
                directionIsAdvance: advance, signedShiftMinutes: signedShift,
                headline: "Adjusting to \(destinationName)",
                detail: "Shifting \(advance ? "earlier" : "later") about an hour a day — \(days) day\(days == 1 ? "" : "s") to go.",
                lightGuidance: lightGuidance(advance: advance, ageDays: ageDays))
        }

        // ----- Pre-arrival: optionally pre-shift the home schedule toward the destination -----
        if strategy == .adaptBefore && now >= adaptStart && progress > 0 {
            let offset = Int((-progress * Double(sign(signedShift))).rounded())   // device=origin → shift toward dest
            return JetLagPlan(
                phase: .preAdapt, scheduleOffsetMinutes: offset,
                daysRemaining: max(0, daysUntilDeparture),
                destinationName: destinationName, originName: originName,
                directionIsAdvance: advance, signedShiftMinutes: signedShift,
                headline: "Prepping for \(destinationName)",
                detail: "Easing the schedule \(advance ? "earlier" : "later") before you fly so the change lands gently.",
                lightGuidance: lightGuidance(advance: advance, ageDays: ageDays))
        }

        guard daysUntilDeparture <= 7 else { return nil }   // heads-up only within a week
        return upcomingPlan(daysUntilDeparture: daysUntilDeparture, stayOnHome: false,
                            strategy: strategy, advance: advance, signedShift: signedShift,
                            destinationName: destinationName, originName: originName, ageDays: ageDays)
    }

    private static func upcomingPlan(daysUntilDeparture: Int, stayOnHome: Bool, strategy: TripStrategy,
                                     advance: Bool, signedShift: Int, destinationName: String,
                                     originName: String, ageDays: Int) -> JetLagPlan {
        let d = max(0, daysUntilDeparture)
        return JetLagPlan(
            phase: .upcoming, scheduleOffsetMinutes: 0, daysRemaining: d,
            destinationName: destinationName, originName: originName,
            directionIsAdvance: advance, signedShiftMinutes: signedShift,
            headline: "\(destinationName) in \(d) day\(d == 1 ? "" : "s")",
            detail: stayOnHome ? "Short trip — we'll suggest staying on home time."
                : strategy == .adaptBefore ? "We'll start easing the schedule a few days out."
                : "We'll start adjusting once you land.",
            lightGuidance: lightGuidance(advance: advance, ageDays: ageDays))
    }

    // MARK: - Helpers

    static func dailyRate(advance: Bool, ageDays: Int) -> Double {
        let base = advance ? baseAdvanceMinutesPerDay : baseDelayMinutesPerDay
        return base * ageFactor(ageDays: ageDays)
    }

    /// Infants re-entrain fastest; older children and adults slowest.
    static func ageFactor(ageDays: Int) -> Double {
        switch ageDays {
        case ..<366: return 1.2
        case ..<731: return 1.05
        case ..<(365 * 5): return 0.95
        default: return 0.85
        }
    }

    static func lightGuidance(advance: Bool, ageDays: Int) -> String {
        let infant = ageDays < 365
        if advance {
            return infant
                ? "Open the curtains for bright morning light and keep evenings calm and dim."
                : "Get bright light in the morning and dim the lights in the evening to shift earlier."
        } else {
            return infant
                ? "Let in bright afternoon light and keep mornings dim and quiet."
                : "Get bright light in the late afternoon/evening and keep mornings dim to shift later."
        }
    }

    static func normalisedShift(_ minutes: Int) -> Int {
        var m = minutes
        while m > 720 { m -= 1440 }
        while m <= -720 { m += 1440 }
        return m
    }

    private static func sign(_ x: Int) -> Int { x > 0 ? 1 : (x < 0 ? -1 : 0) }

    private static func calendarDaysBetween(_ a: Date, _ b: Date, _ calendar: Calendar) -> Int {
        let from = calendar.startOfDay(for: a)
        let to = calendar.startOfDay(for: b)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    /// "America/New_York" → "New York"; falls back to the abbreviation.
    static func cityName(_ tz: TimeZone) -> String {
        if let last = tz.identifier.split(separator: "/").last {
            return last.replacingOccurrences(of: "_", with: " ")
        }
        return tz.abbreviation() ?? tz.identifier
    }
}

enum TripStrategy: String, Equatable, CaseIterable {
    case adaptBefore
    case adaptAfter
}
