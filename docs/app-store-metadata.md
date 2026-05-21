# Perfect Nap — App Store Connect metadata

Paste these into App Store Connect → My Apps → Perfect Nap → the matching field.
Limits in brackets are Apple's hard caps.

---

## App name [30 chars]

```
Perfect Nap
```
(11/30)

## Subtitle [30 chars — appears under the name on the App Store]

```
Smart nap timing for babies
```
(27/30)

Alternative:

```
Find your baby's sweet spot
```
(27/30)

## Promotional text [170 chars — editable any time without resubmitting]

```
Perfect Nap learns when your baby is ready to sleep. Tap play, tap stop. The Lock Screen counts down to the next nap. All on device, no accounts, no ads.
```
(154/170)

## Description [4000 chars]

```
Perfect Nap finds the sweet-spot between naps — that narrow window when your baby is tired enough to fall asleep, but not so overtired that the nap is short.

It is built on the published research that pediatric sleep specialists already use, and it learns your baby's own pattern over time.

ONE SCREEN, ONE BUTTON
Press play when the nap starts. Press stop when it ends. That is the entire interaction.

A COUNTDOWN TO THE NEXT NAP
Between naps, Perfect Nap shows a countdown to the predicted next sleep time — both on the home screen and as a Live Activity on the Lock Screen and Dynamic Island. No more "is it time yet?".

LEARNS YOUR BABY
Every completed nap nudges a personalised multiplier. After a few days the predictions match the baby's actual rhythm, not the average baby's. The current factor and confidence are visible in Settings.

GROUNDED IN THE LITERATURE
The age-based wake-window baselines come from the AAP/AASM consensus (Paruthi et al. 2016), Iglowstein et al. 2003 normative data, Weissbluth, Mindell & Owens, and the practitioner programs (Taking Cara Babies, Happiest Baby, Cleveland Clinic, Huckleberry, Precious Little Sleep). The "Why this time?" sheet shows exactly which factors shaped the current prediction.

WORKS OVERNIGHT
Sleep started after 7pm is automatically logged as a night, not a nap.

EVERYTHING ON DEVICE
Perfect Nap makes no network calls. No accounts. No analytics. No ads. Your data lives only on your phone — and goes with it when you delete the app.

WHAT'S INCLUDED
• Big play / stop primary action
• Predicted countdown with earliest and latest window
• "Why this time?" rationale sheet
• History with per-day grouping and swipe-to-delete
• Charts for today's rhythm and the last 7 days
• Personalisation factor visible in Settings
• Live Activity on the Lock Screen and Dynamic Island
• Local notifications at the start and end of the recommended window
• Source list with deep links to the underlying research

A NOTE FROM THE LITERATURE
"Wake window" is a consumer-facing term. The underlying mechanism — the Borbély two-process model of sleep pressure and circadian gating — is well evidenced, and the consumer programs that publish wake-window tables agree closely with each other. But babies are individuals. Treat predictions as a starting point, not a prescription.

Perfect Nap is built by one parent. Feedback is welcome at marc.hyett@gmail.com.
```

## Keywords [100 chars, comma-separated, no spaces after commas to maximise]

```
baby,sleep,nap,wake,window,newborn,infant,toddler,bedtime,schedule,tracker,timer,parent,routine
```
(99/100)

## Support URL

```
https://marcushyett.github.io/perfect-nap/
```
*(replace `marcushyett` with your actual GitHub username if different — set in the same screen as Marketing URL)*

## Marketing URL [optional]

```
https://marcushyett.github.io/perfect-nap/
```

## Privacy Policy URL [required]

```
https://marcushyett.github.io/perfect-nap/privacy.html
```

---

## App Privacy questionnaire answers

When App Store Connect asks "Do you or your third-party partners collect data?", the answer is **No**. Perfect Nap makes no network requests; all data stays on device.

- Data Collection: **No**
- Tracking: **No**

---

## Age rating

- Made for Kids: **No** (this is for parents)
- Rating questionnaire: all "None" — no objectionable content of any kind
- Expected rating: **4+**

---

## Category

- Primary: **Health & Fitness**
- Secondary: **Lifestyle**

(Alternatives if Health & Fitness review is strict about medical claims: Primary **Lifestyle**, Secondary **Health & Fitness**.)

---

## What's New in This Version [4000 chars, for v1.0]

```
The first release of Perfect Nap.

• Predicts the next nap from an age-based wake-window baseline, personalised to your baby over time
• Live Activity on the Lock Screen and Dynamic Island
• "Why this time?" rationale sheet showing the factors behind each prediction
• History with charts of today's rhythm and the last 7 days
• Everything on device — no accounts, no analytics

Thanks for trying it. Feedback to marc.hyett@gmail.com is read by the person who built it.
```

---

## TestFlight test information

### What to test

```
Two main flows:

1. Open the app, complete onboarding with the baby's birth date, and press play on the big button. Press stop after a few seconds. Check that the countdown updates and that the Lock Screen widget shows a Live Activity.

2. Log a few past naps via the History → + button (or via the main play/stop flow). Look at the patterns tab. Check that the personalisation factor in Settings moves with each completed nap.

Please report anything that feels off, especially predictions that don't match what your baby actually does.
```

### Beta App Description

```
Perfect Nap predicts your baby's next nap window using clinical wake-window baselines and a small on-device learning model. All data stays on the phone.
```

### Feedback email

```
marc.hyett@gmail.com
```

---

## Screenshots required

App Store Connect requires screenshots at **6.7" iPhone** (1290×2796) and optionally **6.1"** and **5.5"** sizes. Take them with `xcrun simctl io booted screenshot` from the iPhone 16 Pro simulator, or use Xcode → Window → Devices and Simulators → take screenshot.

Suggested set (5 max submitted):

1. **Home — countdown** ("47 min until next nap")
2. **Home — nap in progress** (timer running)
3. **Why this time?** sheet (shows the factors)
4. **History / Patterns** tab with charts
5. **Lock Screen Live Activity** (use Apple's framing tool or take a real device screenshot)
