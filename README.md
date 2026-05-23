# Perfect Nap

A native iOS app that tells you **when to put your baby down** so they fall asleep easily and sleep
well — and quietly learns each baby's individual rhythm over time. It works for one baby or several,
syncs live between two parents over iCloud, and even handles travel across time zones and the
clocks-change weekend.

This document explains every feature twice: once for the **person using the app**, and once for the
**engineer maintaining it** — and, crucially, how the features connect to each other and what
research backs each one.

---

## 1. The problem, and the one idea that solves it

New parents are told to "watch for sleep cues" and "don't let them get overtired," but in the moment
that advice is useless: by the time a baby is rubbing their eyes and screaming, the easy-settle
window has already closed. Put a baby down **too early** and they fight the crib because they aren't
tired enough; put them down **too late** and a stress-hormone "second wind" makes them fight it just
as hard — and the sleep that follows is short and fragmented.

There is a narrow **ideal window** in between. Perfect Nap's entire job is to predict that ideal window
and count you down to it.

### The science spine: the two-process model

Everything in this app hangs off one well-evidenced framework — **Borbély's two-process model of
sleep regulation** (review: PMC9540767):

- **Process S (homeostatic sleep pressure):** adenosine builds up the longer you're awake and
  discharges while you sleep. More time awake → more pressure → easier to fall asleep. A *short* nap
  discharges less pressure than a long one.
- **Process C (circadian rhythm):** an internal ~24h clock that gates *when* sleep pressure can
  actually convert into sleep. It matures around **4 months** — which is exactly why newborns are
  unpredictable and why clock-based schedules only start working in the second half of the first
  year.

The "ideal window" is the moment Process S is high **and** aligned with a Process-C dip. Miss it and
the body fights fatigue with cortisol/adrenaline (the "overtired" second wind). Every prediction,
warning, gauge, and travel adjustment in this app is a different lens on these two processes.

> **Honest caveat (shown in-app):** "wake window" is a consumer-facing term, not a clinical one
> (Dr. Craig Canapari, Yale Pediatric Sleep). The *mechanism* (Process S/C) is clinical; the
> wake-window tables are practitioner consensus. The app frames predictions as a starting point, not
> a prescription.

---

## 2. Architecture at a glance

| Layer | Technology | Where |
|---|---|---|
| UI | SwiftUI, `@Observable` | `PerfectNap/Views/`, `PerfectNap/Models/SleepStore.swift` |
| Persistence + sync | Core Data via `NSPersistentCloudKitContainer` (private + shared stores) | `Shared/CoreDataStack.swift`, `Shared/CoreDataModels.swift` |
| Sharing | CloudKit `CKShare` | `Shared/SharingCoordinator.swift`, `PerfectNap/CloudSharing.swift` |
| Lock screen / Dynamic Island | ActivityKit Live Activities | `Shared/NapLiveActivityManager.swift`, `PerfectNapWidget/` |
| Home-screen widget | WidgetKit | `PerfectNapWidget/NapCountdownWidget.swift` |
| Lock-screen / Siri buttons | App Intents | `Shared/SleepActions.swift`, `Shared/SleepIntents.swift` |
| Local reminders | UserNotifications | `PerfectNap/Notifications/NapNotifier.swift` |

**Two principles make the codebase testable and robust:**

1. **Pure algorithm core.** All sleep science lives in small, dependency-free value types in
   `Shared/` (`NapPredictor`, `BedtimePlanner`, `AdaptiveModel`, `JetLagPlanner`, …). They take
   plain inputs and return plain outputs — no Core Data, no clock, no globals (dates and calendars
   are injected). This is what makes the science unit-testable.
2. **One integration point.** `SleepStore.refresh()` is the single place that reads Core Data, runs
   every pure module in the right order, composes their results, and publishes them to the UI. If
   you want to understand how features connect, read that method (see §5).

The Xcode project is **generated from `project.yml` via [XcodeGen](https://github.com/yonaskolb/XcodeGen)** —
edit `project.yml`, never the `.xcodeproj`. Code in `Shared/` is compiled into both the app and the
widget extension.

---

## 3. The features

Each feature below lists: **the problem**, **what the user sees**, **how it works**, **what it
connects to**, and **the research**.

### 3.1 Wake-window nap prediction *(the core)*

- **Problem:** "When is the next nap?"
- **User sees:** A big "Next nap in 3:37" countdown on the home screen, with an earliest/latest
  window, and a "Why this time?" sheet that explains every factor that moved the number.
- **How it works** (`Shared/NapPredictor.swift` + `Shared/WakeWindowTable.swift`): the next wake
  window is a clinical age baseline multiplied by a chain of factors:

  ```
  window = baseline(age)
         × positionFactor        // first nap shortest; pre-bed longest (reversed for newborns)
         × napQualityFactor      // short last nap → shorter next window (Process S)
         × nightFactor           // only for the first window: short night → shorter morning window
         × adaptationFactor      // per-baby learned multiplier (§3.3)
         × dayLoadFactor         // lots of day sleep banked → stretch toward bedtime
         × sleepDebtFactor       // naps running short today → pull the window (and overtired) earlier
  ```

  The recommended nap time is `lastWakeTime + window`; `earliest`/`latest` come from the low/high
  ends of the age band. Predictions always anchor from the **real last wake**, never an assumed nap,
  so an overdue baby is reported as overdue (not hidden).
- **Connects to:** feeds the Live Activity, the home countdown, notifications, the timeline chart's
  forecast, and is the fallback the schedule blend (§3.11) and bedtime planner (§3.7) adjust.
- **Research:** AAP/AASM (Paruthi 2016) for 24h totals; Iglowstein 2003 percentile curves;
  Weissbluth; Taking Cara Babies; Happiest Baby (Karp); Cleveland Clinic. 15 age bands
  in `WakeWindowTable`.

### 3.2 Ideal-window gradient & overtired warning

- **Problem:** a single countdown doesn't convey *urgency* — is it fine to be 10 minutes late?
- **User sees:** the screen shifts from calm ("building") → ready ("ideal window") → a red "Overtired"
  state past the window, with copy that's sharper right before bedtime.
- **How it works:** `WakeWindowStatus` (`building` / `ideal` / `overtired`) is derived from where
  *now* sits between `earliestStart` and `latestStart`. `minutesOverdue`/`minutesOvertired` are
  clamped to never go negative (this fixed an early "-0 min" flicker bug).
- **Connects to:** the home background color, the Live Activity, and is pulled *earlier* by the
  sleep-debt factor so the warning reflects accumulated pressure, not just the clock.
- **Research:** the two-process "second wind" — cortisol release past the ideal window (Weissbluth;
  two-process model).

### 3.3 Per-baby adaptation *(the personalization engine)*

- **Problem:** the clinical baseline is an average; every baby differs.
- **User sees:** predictions silently get more accurate over a few days; Settings shows an "adapted
  factor ×1.08" and a confidence %.
- **How it works** (`Shared/AdaptiveModel.swift`): every completed nap ≥25 min is one observation.
  It computes how long the baby was *actually* awake before the nap vs. the clinical
  baseline×position, forms a ratio, clamps it to [0.75, 1.25], and pulls the stored
  `adaptationFactor` toward it with an exponential moving average (learning rate ~0.18, **decaying as
  confidence grows** so early naps move it more than later ones). Confidence climbs +0.05 per
  observation toward 1.0. **Guardrails:** implausibly long wake windows (likely a forgotten nap) are
  excluded so they can't wrongly stretch the factor.
- **Connects to:** the learned factor multiplies into *every* prediction (§3.1) and into the bedtime
  planner. It uses corrected age (§3.13) when selecting the baseline.
- **Research:** the recent-history personalisation idea "last ~5 days of sleep" personalization, implemented as an
  EMA. Bounded so personalization can never override clinical safety ranges.

### 3.4 Sleep-total gauges (day & night)

- **Problem:** "has she had enough day sleep? enough night sleep?"
- **User sees:** two rings around the start/stop button — an amber day-sleep gauge (with a sun) and
  an indigo night gauge (with a moon), filling toward the age-appropriate budget.
- **How it works** (`Shared/SleepTotals.swift`): aggregates completed sessions into "most recent
  night" and "day sleep since that night." Night persists from the previous night until the next
  night begins; day persists from the previous day until a new day's first nap — so the gauges never
  blank out. The live elapsed time of an in-progress sleep is added on top in the view.
- **Connects to:** the same day-sleep total drives the `dayLoadFactor` (§3.1) and the nap cap (§3.8).
- **Research:** AAP/AASM 24h totals as the gauge ceilings.

### 3.5 Nap-quality, sleep-debt & day-load adjustments

- **Problem:** a fixed window ignores how the day is actually going.
- **User sees:** the countdown subtly shortens after a catnap, stretches after a long nap or a
  sleep-heavy day, and the overtired point arrives sooner on a short-nap day.
- **How it works:** three factors inside `NapPredictor` — `napQualityFactor` (last nap vs. age-
  typical, graduated), `sleepDebtFactor` (today's average nap running short pulls everything earlier),
  `dayLoadFactor` (day sleep > 60% of budget stretches the window toward bedtime).
- **Connects to:** all three are part of the §3.1 product; sleep-debt specifically reshapes the
  overtired warning (§3.2).
- **Research:** Process S discharge proportional to sleep obtained (Karp short-nap rule; two-process
  model).

### 3.6 Sleep-cycle-aware wake suggestions

- **Problem:** waking a baby mid-cycle leaves them groggy and cranky.
- **User sees:** during a nap, "Suggested wake by ~2:45" — landing on a sleep-cycle boundary.
- **How it works** (`Shared/NapCapPlanner.swift` + `AgeProfile.sleepCycleMinutes`): nap duration is
  rounded down to whole sleep cycles (50 min in infancy → 85 min by school age) within the cap.
- **Connects to:** the nap cap (§3.8) and the low-confidence path of the length estimate (§3.9).
- **Research:** infant sleep architecture (Grigg-Damberger 2016; Jenni & Carskadon); Polly Moore's
  BRAC ~90-min cycle.

### 3.7 Bedtime optimization (backward planning)

- **Problem:** parents care most about *bedtime* landing well; nap timing should serve it.
- **User sees:** set a target bedtime; the last nap is timed so the baby ends it the right gap before
  bed.
- **How it works** (`Shared/BedtimePlanner.swift`): plans backward from the target bedtime using the
  age's pre-bedtime wake window, clamped to stay within healthy limits. When set, this **overrides**
  the forward-prediction recommended time while the forward window stays as the outer guardrail.
- **Connects to:** layered on top of §3.1 inside `NapPredictor.predict`; the "Why this time?"
  rationale explains when bedtime planning fired.
- **Research:** protect early/consistent bedtimes (Weissbluth; AAP).

### 3.8 Nap cap (don't let a nap wreck bedtime)

- **Problem:** a 3-hour late-afternoon nap destroys bedtime.
- **User sees:** "Time to wake — protect bedtime" once a nap has run long enough.
- **How it works** (`Shared/NapCapPlanner.swift`): caps a single nap at the smaller of a per-nap
  share of the remaining day-sleep budget and a hard ceiling, never letting a nap run past
  `bedtime − preBedWindow`, and cycle-aligns the result.
- **Connects to:** uses the day-sleep total (§3.4) and bedtime (§3.7); validated by realism tests so
  it can never suggest a wake time after bedtime.

### 3.9 Nap-length estimate

- **Problem:** "how long will this nap be?"
- **User sees:** "Usually naps ~1h 10m · 70% confident."
- **How it works** (`Shared/NapLengthEstimator.swift`): a time-of-day-weighted average of past naps
  near the same clock time, plus a confidence score (more samples + more consistency = higher). Only
  cycle-snaps when confidence is low.
- **Connects to:** shown during an active nap and used to project the chart's forecast tail (§3.10).

### 3.10 Day forecast on the timeline chart

- **Problem:** parents want to see the shape of the rest of the day.
- **User sees:** the history timeline chart projects the remaining naps as ghost blocks with
  **widening error bars** further into the future, plus the live tail of the current nap.
- **How it works** (`Shared/DayForecast.swift`): chains predicted naps toward bedtime, growing
  uncertainty per step.
- **Connects to:** built from the same predictor + bedtime planner the live countdown uses.

### 3.11 Clock-schedule blend & custom schedule editor

- **Problem:** older babies settle onto a clock schedule; pure reactive wake windows feel jittery.
- **User sees:** from ~4 months, predictions gently bias toward a daily rhythm; Settings lets you
  view, set, or fully customize the nap schedule (with an age warning under 4 months).
- **How it works** (`Shared/DaySchedule.swift`, `Shared/ScheduleLearner.swift`, `ScheduleBlend`):
  `ScheduleLearner` derives anchor times per nap index from recent history; `ScheduleBlend.weight`
  ramps from 0 at ~4 months to a 0.7 cap by ~9 months. The blend is **gradual** (never fully
  overrides) so a baby who isn't following the schedule still gets adjusted. A custom schedule
  (stored CSV of minutes-from-midnight on the `Baby`) takes precedence over the learned one.
- **Connects to:** blended into the §3.1 recommendation; receives the DST (§3.12) and jet-lag (§3.14)
  offsets so travel/clock-change shift the schedule too.
- **Research:** Process C maturation ~4 months; practitioner schedule guidance (Taking Cara Babies,
  Taking Cara Babies).

### 3.12 Daylight-saving auto-easing *(fully automatic)*

- **Problem:** the clocks-change hour jolts a baby's schedule.
- **User sees:** in the 3 days before a DST change, a banner — "Clocks change Sunday — easing Rosie's
  schedule ~40 min earlier" — and the schedule quietly shifts so the jump lands gently. No setup.
- **How it works** (`Shared/DSTAdjuster.swift`): reads the device time zone's next DST transition,
  ramps a shift to a full hour by the transition (earlier for spring-forward, the harder direction;
  later for fall-back), then realigns once the clock itself changes.
- **Connects to:** the shift is applied to the schedule anchors (§3.11) in `SleepStore.refresh`,
  composing with jet-lag.
- **Research:** circadian phase-shift direction asymmetry (advances are harder than delays).

### 3.13 Prematurity correction

- **Problem:** a baby born 8 weeks early sleeps like their corrected age, not their birthday.
- **User sees:** set "born X weeks early" in Settings; predictions use a corrected age (shown), the
  displayed age stays chronological.
- **How it works** (`Baby.adjustedAgeInDays`): subtracts prematurity fully through ~12 months, then
  tapers linearly to zero by ~24 months. **Defaults to 0 for all existing users** — the schema
  change was additive and safe.
- **Connects to:** corrected age feeds *every* age-based lookup — wake windows, sleep cycles, schedule
  blend weight, resettle thresholds, jet-lag rate.
- **Research:** AAP corrected-age practice; the 12→24 month taper reflects when the gap stops
  mattering.

### 3.14 Jet-lag travel mode *(manual)*

- **Problem:** crossing time zones desyncs a baby's body clock from local time for days.
- **User sees:** Settings → Travel & jet lag → set origin/destination time zones, dates, optional
  return, and an "ease in before / adjust after landing" choice (or "we've already arrived"). The
  home screen then shows "Adjusting to London — shifting earlier ~1h/day, 6 days to go" plus light
  guidance.
- **How it works** (`Shared/JetLagPlanner.swift` + the `Trip` entity): the body re-entrains at an
  age-scaled rate (advance ~60 min/day eastward — the harder direction; delay ~90 min/day westward;
  infants faster). A single "progress" ramp drives the schedule offset; while still in the origin
  zone the offset shows as a pre-shift, and once in the destination zone it shows as the residual
  misalignment — the discontinuity at landing is exactly the clock jump. Small shifts (≤2h) or short
  stays (<3 days) recommend *staying on home time*. The return leg ramps back.
- **Connects to:** the offset is applied to schedule anchors (§3.11) alongside DST; the `Trip` is
  CloudKit-synced so both parents see it; uses corrected age (§3.13) for the rate.
- **Research:** CDC Yellow Book; Eastman/Burgess pre-flight light-shift studies; pediatric jet-lag
  consensus (~1h/day, eastward harder, light is the lever, short trips not worth adapting).

### 3.15 Resettle advisor (early-wake recovery)

- **Problem:** a baby wakes 30 minutes into a nap — start a fresh long wake window and they'll be a
  wreck.
- **User sees:** "Short nap · 30m → Try to resettle. Rosie may link another cycle — give it 13m
  before starting the wake window." After the window passes, it returns to the normal (shortened)
  prediction.
- **How it works** (`Shared/ResettleAdvisor.swift`): if the last nap was under ~65% of age-typical
  and ended within the last 20 minutes, suggest resettling. **Independent of the paused/"stop
  tracking" state** — it's advice about the nap that just ended, so ending a nap via "Stop tracking"
  still surfaces it (a guarded regression).
- **Connects to:** takes priority over the normal countdown in the home view; after the window, §3.1
  resumes (with the short nap shortening the next window via `napQualityFactor`).
- **Research:** "crib hour" / short-nap extension (Precious Little Sleep, Taking Cara Babies,
  Taking Cara Babies); cycle-linking.

### 3.16 Skipped-nap detection

- **Problem:** parents forget to log naps; an implausibly long wake window then breaks predictions.
- **User sees:** "Did you forget to log a nap? Tap to add one around 11:20–12:00."
- **How it works** (`Shared/SkippedNapDetector.swift`): if time since last wake exceeds the age's
  high window × an implausibility factor (1.5), it infers a likely missed nap from fixed anchors
  (stable as the clock advances — fixed an earlier "drifting banner" bug). It's opt-in; the
  prediction itself still anchors from real data.
- **Connects to:** the same implausibility factor guards the adaptive model (§3.3) from learning off
  forgotten naps.

### 3.17 Multi-baby support

- **Problem:** families have more than one child.
- **User sees:** a baby switcher on the home screen and in Settings; add/remove babies; each shows
  its own age (or "Shared by …"); each napping baby gets its own Live Activity.
- **How it works:** every `NapSession` carries a `babyID`; all fetches and predictions are scoped to
  the selected baby (`TrackingState.selectedBabyID`, persisted in the app group). `SleepStore`
  resolves the selected baby and isolates its data.
- **Connects to:** scoping touches every feature; the Live Activity manager reconciles one activity
  per napping baby.

### 3.18 Two-parent sharing *(live, link-based)*

- **Problem:** both parents need to see and log the same baby's sleep, in real time.
- **User sees:** Settings → "Invite partner" produces a link (shareable over *any* channel, e.g.
  WhatsApp — no Apple ID required); the partner taps it and both see live updates.
- **How it works** (`Shared/SharingCoordinator.swift` on `NSPersistentCloudKitContainer`): the owner
  creates a `CKShare` for the `Baby` record (its sessions follow in the same zone) with
  `publicPermission = .readWrite` so the link itself is the access control. The partner accepts into
  their local **shared** persistent store. Real-time sync is via CloudKit push + remote-change
  notifications that trigger `SleepStore.refresh`. Conflict policy:
  `NSMergeByPropertyObjectTrumpMergePolicy`.
- **Connects to:** rides the multi-baby model (§3.17); a shared baby shows "Shared by <owner>" and
  offers "leave" instead of "delete."
- **Note:** TestFlight uses the **Production** CloudKit environment, so Core Data schema changes must
  be deployed to Production explicitly (see `CLAUDE.md`).

### 3.19 Lock screen, Dynamic Island, widget & Siri

- **User sees:** a Live Activity counting down to the next nap (or up during a nap) on the Lock
  Screen and Dynamic Island; a home-screen widget; start/stop from the lock screen and Siri.
- **How it works:** `NapLiveActivityManager` reconciles activities from `SleepStore`; App Intents
  (`SleepActions`) mutate Core Data headlessly and post a change notification that refreshes the app.
  Starting a nap from any surface clears the paused state.

### 3.20 Notifications, onboarding, legacy migration

- Local notifications fire at the recommended start and the end of the window (`NapNotifier`).
- Onboarding captures the birth date.
- `LegacyMigration` reads the old SwiftData store once (non-destructive) and copies it into Core
  Data, so existing users keep their history.

---

## 4. Data model & sync

- **Entities** (`Shared/CoreDataModels.swift`, programmatic model in `CoreDataStack.swift`):
  `Baby` (name, birthDate, adaptationFactor/confidence, targetBedtimeMinutes, weeksPremature,
  customScheduleMinutes), `NapSession` (startedAt, endedAt, kindRaw nap/night, babyID),
  `Trip` (origin/destination TZ, dates, strategy, alreadyLanded). **Every attribute is optional or
  defaulted** — a CloudKit requirement and the reason schema changes don't break existing data.
- **Stores:** a `private` store (this user's data, synced across their devices) and a `shared` store
  (data shared *to* them). One container, two scopes.
- **Simulator:** CloudKit is disabled on purpose (`#if targetEnvironment(simulator)`), because the
  unsigned simulator build has no CloudKit entitlement. Test sharing/sync on device.

---

## 5. How it all composes: `SleepStore.refresh()`

This is the heartbeat and the clearest map of how features connect. On every change it:

1. Fetches babies, resolves the **selected** baby (§3.17), fetches its sessions (scoped by `babyID`).
2. Computes day/night **totals** and gauge bases (§3.4).
3. If the baby is **awake**:
   - Always computes the **resettle** suggestion (§3.15) — *independent of paused state*.
   - If tracking isn't paused, builds the schedule **anchors** (custom → learned → generic, §3.11),
     applies the **DST** offset (§3.12) and the **jet-lag** offset (§3.14), then runs the
     **predictor** (§3.1, which internally layers bedtime planning §3.7 and the schedule blend),
     plus **skipped-nap** inference (§3.16).
4. Computes the **nap-length estimate** (§3.9).
5. If **napping**, computes the **wake suggestion / cap** (§3.6, §3.8).
6. Computes the **day forecast** (§3.10) and reconciles **Live Activities** (§3.19).

Reading this method top-to-bottom is the fastest way to see why, say, a forgotten nap, a time-zone
change, and a custom schedule all end up in the same countdown.

---

## 6. Testing philosophy

- The pure modules in `Shared/` are the test surface; the science is verified there without Core
  Data or the clock (dates/calendars are injected).
- Tests aim to be **behavioral, not brittle**: assert *what the math should do* and realistic
  per-age bounds, but avoid pinning exact magic numbers that harmless tuning would break.
- `PredictionRealismTests` sweeps every age band to ensure no prediction is ever absurd (a nap after
  bedtime, a negative window, a wake suggestion past bedtime).
- Regression bugs get a named test (e.g. `SleepStoreResettleTests`, the "-0 min" flicker, the
  drifting skipped-nap banner).

Run the suite:

```bash
xcodegen generate
xcodebuild -project PerfectNap.xcodeproj -scheme PerfectNap \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

---

## 7. Build & ship

```bash
brew install xcodegen        # once
xcodegen generate            # regenerate the .xcodeproj from project.yml
open PerfectNap.xcodeproj
```

- Set your Apple Developer team under *Signing & Capabilities* for both targets, or use the manual-
  signing TestFlight pipeline documented in `CLAUDE.md`.
- For headless simulator screenshots, launch with `-seedSampleData` (and `-forceJetLag` /
  `-seedResettle` to exercise those banners). These are `#if DEBUG` only.

---

## 8. Research sources

Surfaced in-app under Settings → Sources (`PerfectNap/Sleep/SleepSources.swift`):

- **AAP / AASM** pediatric sleep duration consensus (Paruthi et al. 2016) — 24h total guardrails.
- **Iglowstein et al. 2003** (*Pediatrics* 111:302–307) — normative percentile curves, n=493.
- **Two-process model review** (PMC9540767, Skeldon & Dijk et al.) — Process S × Process C; the spine.
- **Weissbluth**, *Healthy Sleep Habits, Happy Child* (5th ed.).
- **Taking Cara Babies** (Cara Dumaplin) — wake windows, witching hour.
- **Happiest Baby** (Dr. Harvey Karp) — short-nap rule.
- **Cleveland Clinic** (Dr. Vaishal Shah) — clinical practitioner ranges.
- **Recent-history personalisation** — first-year expectations + personalization (the EMA idea).
- **Dr. Polly Moore** — 90-minute BRAC cycle.
- **Precious Little Sleep** (Alexis Dubief) — pragmatic ranges; crib-hour resettle.
- **Dr. Craig Canapari** (Yale) — the "wake window isn't a clinical term" caveat.
- **CDC Yellow Book** + Eastman/Burgess light-shift studies — jet-lag protocol.
- Infant sleep architecture: **Grigg-Damberger 2016**, **Jenni & Carskadon**, **Mindell & Owens**.

> Babies are individuals. Perfect Nap is a research-grounded starting point, not medical advice.
