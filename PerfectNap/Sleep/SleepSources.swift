import Foundation

struct SleepSource: Identifiable {
    let id = UUID()
    let title: String
    let author: String
    let url: URL
    let note: String
}

enum SleepSources {
    static let all: [SleepSource] = [
        SleepSource(
            title: "AAP-endorsed Pediatric Sleep Duration Recommendations (Paruthi et al. 2016)",
            author: "American Academy of Pediatrics / AASM",
            url: URL(string: "https://aasm.org/advocacy/position-statements/child-sleep-duration-health-advisory/")!,
            note: "24-hour total sleep guardrails by age. Used as the safety envelope."
        ),
        SleepSource(
            title: "Iglowstein et al. 2003, Pediatrics 111:302–307",
            author: "Zurich Longitudinal Studies",
            url: URL(string: "https://pubmed.ncbi.nlm.nih.gov/12563055/")!,
            note: "Normative day/night/total sleep percentile curves, ages 1 month to 16 years (n=493). Basis for percentile-style priors."
        ),
        SleepSource(
            title: "Two-process model of sleep regulation (review)",
            author: "PMC9540767 (Skeldon & Dijk and others)",
            url: URL(string: "https://pmc.ncbi.nlm.nih.gov/articles/PMC9540767/")!,
            note: "Borbély's Process S (homeostatic) × Process C (circadian). Explains why short naps shorten the next window and why circadian gating only matures around 4 months."
        ),
        SleepSource(
            title: "Healthy Sleep Habits, Happy Child (5th ed.)",
            author: "Dr. Marc Weissbluth",
            url: URL(string: "https://www.weissbluthpediatrics.com/the-weissbluth-method")!,
            note: "Brief intervals of wakefulness between naps; protect early bedtimes."
        ),
        SleepSource(
            title: "Wake Windows by Age",
            author: "Taking Cara Babies (Cara Dumaplin)",
            url: URL(string: "https://www.takingcarababies.com/blogs/sleep-basics/wake-windows-and-baby-sleep")!,
            note: "Wake windows lengthen across the day; first WW is shortest in multi-nap babies; longest is before bedtime."
        ),
        SleepSource(
            title: "Wake Windows by Age",
            author: "Happiest Baby (Dr. Harvey Karp)",
            url: URL(string: "https://www.happiestbaby.com/blogs/baby/wake-windows")!,
            note: "Short-nap rule: a nap under an hour shrinks the next wake window."
        ),
        SleepSource(
            title: "Wake Windows by Age (Cleveland Clinic Health)",
            author: "Dr. Vaishal Shah / Cleveland Clinic",
            url: URL(string: "https://health.clevelandclinic.org/wake-windows-by-age")!,
            note: "Clinical practitioner ranges concordant with the practitioner-program consensus."
        ),
        SleepSource(
            title: "First Year of Sleep Expectations",
            author: "Huckleberry Labs",
            url: URL(string: "https://huckleberrycare.com/blog/first-year-of-sleep-expectations")!,
            note: "Large-n consumer dataset; foundation for SweetSpot® personalised predictions."
        ),
        SleepSource(
            title: "SweetSpot® personalised sleep timing",
            author: "Huckleberry Labs",
            url: URL(string: "https://huckleberrycare.com/blog/sweetspot-your-smart-sleep-timing-companion")!,
            note: "Uses last ~5 days of logged sleep to refine personal predictions. Perfect Nap follows the same idea via exponential moving average."
        ),
        SleepSource(
            title: "Critique of 'wake windows' as a clinical term",
            author: "Dr. Craig Canapari, Yale Pediatric Sleep",
            url: URL(string: "https://drcraigcanapari.com/wake-windows")!,
            note: "Important caveat: 'wake window' is consumer-facing, not a PubMed term. The Process S mechanism is what's actually clinical."
        ),
        SleepSource(
            title: "Witching Hour for Babies",
            author: "Taking Cara Babies",
            url: URL(string: "https://www.takingcarababies.com/blogs/newborn/witching-hour-for-babies")!,
            note: "Newborn pre-bedtime WW shortens, not lengthens — opposite of older babies."
        ),
        SleepSource(
            title: "The 90-Minute Baby Sleep Program",
            author: "Dr. Polly Moore",
            url: URL(string: "https://www.amazon.com/90-Minute-Baby-Sleep-Program-Natural/dp/0761143114")!,
            note: "BRAC cycle: ~90-minute alertness cycles in young infants."
        ),
        SleepSource(
            title: "Precious Little Sleep",
            author: "Alexis Dubief",
            url: URL(string: "https://www.preciouslittlesleep.com/")!,
            note: "Practitioner reference; pragmatic ranges that match the research consensus."
        )
    ]
}
