# Perfect Nap — project guide

iOS baby nap-timing app. SwiftUI + Core Data (NSPersistentCloudKitContainer) + WidgetKit + ActivityKit + App Intents. The Xcode project is generated from `project.yml` via **xcodegen** — edit `project.yml`, not the `.xcodeproj`.

## Per-feature workflow (REQUIRED for every new feature or fix)

Do all of these before considering a feature done:

1. **Build it** for the simulator and fix every build error/warning you introduced.
2. **Test it in the simulator** — actually launch the app and exercise the feature (golden path + the obvious edge cases). Don't claim it works from a successful compile alone.
3. **Capture screenshots** of the feature in the simulator (use `xcrun simctl io booted screenshot <file>.png`). Include both light and dark mode where there's any UI.
4. **Regression-test** — run the unit-test suite (`xcodebuild ... test`) and manually re-check the features the change could plausibly affect (start/stop nap, prediction display, Live Activity, history, multi-baby switching, sharing).
5. **Open a PR** with `gh pr create`. The PR body must include:
   - A summary of what changed and why.
   - The **screenshots** from step 3 (drag-drop or `![](url)` after uploading; at minimum attach the files / reference their paths).
   - A **regression-test checklist** — what you tested and the result.
6. Only after the PR is up (and the user is happy) ship to TestFlight.

## Shipping to TestFlight (manual signing — Xcode session-logout workaround)

Bump `CURRENT_PROJECT_VERSION` in `project.yml`, then archive → export with `/tmp/perfectnap-archive/ExportOptionsManual.plist` (signingStyle manual) → `xcrun altool --upload-app` with API key `NJ6XXLDRJK` / issuer `69a6de71-1c6d-47e3-e053-5b8c7c11a4d1`. Team `9DG37ADF64`. Don't rely on Xcode interactive signing (it keeps logging out).

## CloudKit schema changes

TestFlight uses the **Production** CloudKit env; schema must be deployed there explicitly. After any Core Data attribute change: update `CloudKitSchema.ckdb`, `xcrun cktool import-schema ... --environment development`, then CloudKit Console → **Deploy Schema Changes** → Production. (Direct import to production is rejected.) See memory `project_cloudkit_sharing` for the full recipe.

## Conventions

- Simulator builds are unsigned (no CloudKit entitlement) — CloudKit is disabled in the simulator on purpose (`#if targetEnvironment(simulator)` in `CoreDataStack`). Test CloudKit/sharing on device.
- Shared code (models, predictor, Live Activity, intents) lives in `Shared/` and is included in both the app and widget targets.
- Wake-window science is grounded in the two-process model (Process S / Process C); keep predictions and messaging consistent with `NapPredictor`, `BedtimePlanner`, `WakeWindowStatus`.
