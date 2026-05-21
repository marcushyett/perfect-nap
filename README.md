# Perfect Nap

A native iOS app that finds the sweet-spot between naps for a baby — backed by clinical sleep
data and a small on-device adaptive model.

- One screen, one button. Play when nap starts, stop when it ends.
- Live Activity on the Lock Screen + Dynamic Island shows the countdown to the next nap or the
  duration of the current nap.
- Works overnight (a sleep that begins after 7pm is automatically marked as "night").
- All data stays on device. No accounts, no servers, no tracking.
- Predictions are personalised per baby through a Bayesian-style exponential moving average over
  recent naps.

## Requirements

- Xcode 15.4 or newer (the project targets iOS 17 for SwiftData + ActivityKit Live Activities)
- An iOS 17+ device or simulator
- A real device is needed to see Live Activities on the Lock Screen and Dynamic Island; the
  simulator can show the in-app UI

## Build & Run

This project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the `.xcodeproj` can be
regenerated deterministically from `project.yml`.

```bash
# 1. Install XcodeGen (once)
brew install xcodegen

# 2. Generate the Xcode project
xcodegen generate

# 3. Open in Xcode
open PerfectNap.xcodeproj
```

In Xcode:
1. Select the `PerfectNap` target.
2. Set your Apple Developer team under *Signing & Capabilities* for both `PerfectNap` and
   `PerfectNapWidget` targets.
3. Build (`⌘B`) and run (`⌘R`).

## Project layout

```
PerfectNap/
├── PerfectNapApp.swift        # @main, SwiftData container, RootView
├── Models/
│   ├── Baby.swift             # @Model: name, birthDate, adaptationFactor, adaptationConfidence
│   ├── NapSession.swift       # @Model: startedAt, endedAt, kind (nap / night)
│   └── SleepStore.swift       # Observable coordinator: fetch, predict, start/stop, refresh
├── Sleep/
│   ├── WakeWindowTable.swift  # Clinical wake-window ranges by age (cited inline)
│   ├── NapPredictor.swift     # Predicts the optimal next-nap start time
│   ├── AdaptiveModel.swift    # Per-baby EMA learning over recent naps
│   └── SleepSources.swift     # Citation list for the in-app Sources screen
├── Views/                     # SwiftUI (Onboarding, Home, History, Settings)
├── LiveActivity/              # ActivityKit manager
└── Notifications/             # UNNotification scheduling

PerfectNapWidget/
├── PerfectNapWidgetBundle.swift
├── NapCountdownWidget.swift   # Home/Lock screen widget tile
└── NapLockScreenLiveActivity.swift  # Dynamic Island + Live Activity layouts

Shared/
└── NapActivityAttributes.swift  # ActivityKit attributes, compiled into both targets
```

## How the prediction works

For every prediction, Perfect Nap composes four multipliers on a clinical baseline:

```
nextWakeWindow = baseline(age)
              × positionFactor(first / middle / pre-bed)
              × napQualityFactor(based on last nap length)
              × adaptationFactor(personalised, 0.75 — 1.25)
```

1. **`baseline(age)`** — taken from `WakeWindowTable.swift`. The values are the practical union of
   ranges reported by:
   - American Academy of Pediatrics / AASM consensus (Paruthi et al. 2016)
   - Iglowstein et al. 2003 normative percentile data (Pediatrics 111:302–7)
   - Weissbluth, *Healthy Sleep Habits, Happy Child* (5th ed.)
   - Mindell & Owens, *A Clinical Guide to Pediatric Sleep*
   - Practitioner programs: Taking Cara Babies (Dumaplin), Happiest Baby (Karp), Cleveland
     Clinic, Huckleberry SweetSpot, Precious Little Sleep (Dubief)
2. **`positionFactor`** — first wake window of the day is usually the shortest (multi-nap babies)
   or the longest (single-nap toddlers). Pre-bedtime is the longest stretch for ≥4-month-olds and
   the *shortest* for newborns under 3 months (the witching-hour effect).
3. **`napQualityFactor`** — derived from the consensus rule that a short nap doesn't release as
   much sleep pressure, so the next window shrinks (and the inverse for very long naps):
   - <30 min → 0.75×
   - 30–45 min → 0.85×
   - 45–90 min → 1.00×
   - \>90 min → 1.10×
4. **`adaptationFactor`** — a per-baby multiplier learned by `AdaptiveModel.update()`. Every
   completed nap of ≥25 min is one observation. We compare the *actual* time the baby was awake
   before the nap against the clinical baseline at their age × position, and pull the multiplier
   toward that ratio using an exponential moving average (learning rate ~0.18, decaying with
   confidence). The factor is clamped to [0.75, 1.25].

The Borbély two-process model (Process S × Process C, review PMC9540767) is the formal basis for
this approach. Under ~4 months Process C is immature, so prediction is purely based on time-since-
last-wake. From ~4 months the position factors approximate circadian gating; a future version may
add explicit clock anchoring.

## What ships in v1

- Onboarding with birth date capture
- Big play/stop primary action
- Predicted countdown with earliest/latest window
- "Why this time?" rationale sheet showing exactly which multipliers fired
- History list with per-day grouping and swipe-to-delete
- Personalisation factor visible in Settings
- Live Activity on the Lock Screen and Dynamic Island (compact, expanded, minimal states)
- Local notifications at the recommended start time and at the end of the window
- Source list with deep links to the underlying clinical references

## What's intentionally not in v1

- Multi-child support (one baby at a time)
- Cloud sync (the user explicitly wanted no backend)
- Apple Watch companion
- Bedtime suggestion (only nap windows are predicted; bedtime emerges from the pre-bedtime window
  rule). Easy to add later — would need explicit daytime-cap logic from the AAP/AASM totals.

## Privacy

All data is persisted in SwiftData on the local device. The widget extension and main app share
data through the standard ActivityKit and SwiftData mechanisms. The app does no network requests.

## Caveat from the literature

Dr. Craig Canapari, director of the Yale Pediatric Sleep Center, has pointed out that "wake
window" is a consumer-facing term and that PubMed contains no entries for the phrase. The
underlying mechanism is well-evidenced (the two-process model), and the consumer programs that
publish wake-window tables agree closely with each other — but parents should treat the
predictions as a starting point, not a prescription. Babies are individuals.
