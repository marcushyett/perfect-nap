# Browser-Claude prompt: App Store Connect setup

Paste the block below into a Claude session that is **already signed in to
App Store Connect** in your browser.

---

```
You're already signed into my App Store Connect account in this browser. Please set up
a new iOS app called "Perfect Nap" and fill in everything that can be filled in without
uploading a build yet. Work carefully — these settings affect a real paid Apple
Developer Program account.

Start at: https://appstoreconnect.apple.com/apps

== Step 1. Create the app ==
- Click the blue "+" button → New App
- Platforms: iOS (only)
- Name: Perfect Nap
- Primary Language: English (U.K.)
- Bundle ID: pick `com.marcushyett.perfectnap` from the dropdown (it should be there;
  it was registered earlier today)
- SKU: perfectnap-001
- User Access: Full Access
- Create

== Step 2. App Information (left sidebar → App Information) ==
- Subtitle: Smart nap timing for babies
- Privacy Policy URL: https://marcushyett.github.io/perfect-nap/privacy.html
- Category → Primary: Health & Fitness
- Category → Secondary: Lifestyle
- Content Rights: tick "No, it does not contain, show, or access third-party content"
- Age Rating: click Edit. Answer "None" to every question on every section.
  The result should be 4+.
- Save

== Step 3. Pricing and Availability ==
- Price Schedule: Free (Tier 0 / no charge)
- Availability: All territories (leave default)
- Save

== Step 4. App Privacy ==
- Data Collection: "No, we do not collect data from this app"
  (App makes no network requests; all data is local on the user's device. SwiftData
  is local-only storage and the App Group container is on-device only.)
- Tracking: No tracking
- Save

== Step 5. Version 1.0 metadata ==
Click "1.0 Prepare for Submission" in the sidebar.

- Promotional Text:
Perfect Nap learns when your baby is ready to sleep. Tap play, tap stop. The Lock Screen counts down to the next nap. All on device, no accounts, no ads.

- Description (paste exactly, blank lines preserved):
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

- Keywords (comma-separated, no spaces):
baby,sleep,nap,wake,window,newborn,infant,toddler,bedtime,schedule,tracker,timer,parent,routine

- Support URL: https://marcushyett.github.io/perfect-nap/
- Marketing URL: https://marcushyett.github.io/perfect-nap/

- Copyright: 2026 Marcus Hyett

- Version: 1.0
- What's New in This Version: (this field appears only for updates after the first
  release — skip it if it's not shown for v1.0)

DO NOT upload screenshots (I'll do that locally from the simulator).
DO NOT add a build (no build exists yet — I'll archive and upload from Xcode).
DO NOT click "Submit for Review".

Save.

== Step 6. TestFlight (left sidebar → TestFlight) ==
- Test Information:
  - Beta App Description:
Perfect Nap predicts your baby's next nap window using clinical wake-window baselines and a small on-device learning model. All data stays on the phone.
  - Feedback Email: marc.hyett@gmail.com
  - Marketing URL: https://marcushyett.github.io/perfect-nap/
  - Privacy Policy URL: https://marcushyett.github.io/perfect-nap/privacy.html
- Internal Testing group: leave the default "App Store Connect Users" group; don't
  add testers yet.
- DO NOT create an External Testing group yet (external testing requires a Beta App
  Review submission, which we'll do after the first build is uploaded).

Save.

== When done ==
Report back with:
(a) the App Store Connect URL of the new app (the URL bar after creation)
(b) any field that wouldn't accept the value I gave (Apple sometimes silently
    truncates or rejects characters)
(c) anything that was already filled in differently from what I asked
(d) any required field that's still showing as missing or red

Do not change any global account settings, payment information, or banking. Do not
agree to any new contracts that appear unless they're the standard "Paid Apps" or
"Free Apps" contract Apple makes you accept before submission — and if you encounter
one, tell me what it says before clicking.
```

---

## Notes for Marcus (don't paste these)

**About contracts:** App Store Connect won't let you submit anything until the
"Paid Apps" contract is accepted in *Agreements, Tax, and Banking*. Even for a
free app, you need this contract because of in-app purchase support (which the
template includes by default — harmless). Browser-Claude can probably navigate
this but it asks for tax forms and banking info; you may want to handle that
yourself once it's surfaced.

**About what's left after this prompt:**
1. Open Xcode → both targets → Signing & Capabilities → pick your paid team
2. Connect a real device or use Generic iOS Device
3. Product → Archive → Distribute App → App Store Connect → Upload
4. After ~5–15 minutes the build appears in TestFlight
5. Add yourself / friends as Internal Testers in App Store Connect → TestFlight
6. Take screenshots locally and upload to App Store Connect (only needed before
   public release, not for TestFlight internal testing)
