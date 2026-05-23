import XCTest

/// End-to-end UI tests for the core flows. Each test launches the app with `-uiTesting` (a clean
/// in-memory store + reset TrackingState, so every test starts deterministic) plus seed flags.
/// These cover the *interaction* surface that the unit suite can't — including the multi-baby
/// settings-staleness bug that previously slipped through.
final class CoreFlowsUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch(_ args: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + args
        app.launch()
        return app
    }

    // MARK: - onboarding

    func testOnboardingCreatesFirstBaby() {
        let app = launch()   // empty store → onboarding flow
        let cont = app.buttons["onboarding.continue"]

        XCTAssertTrue(cont.waitForExistence(timeout: 10), "Welcome screen should appear.")
        cont.tap()   // welcome → about baby

        let name = app.textFields["onboarding.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "Name field should appear.")
        name.tap(); name.typeText("Luna")
        cont.tap()   // about baby → struggle

        // Struggle + method are tap-to-advance choice cards.
        app.buttons["Short naps"].tap()
        XCTAssertTrue(app.buttons["Mostly guessing"].waitForExistence(timeout: 5))
        app.buttons["Mostly guessing"].tap()

        // "Building profile" auto-advances (~2.2s) to the value carousel.
        XCTAssertTrue(cont.waitForExistence(timeout: 10), "Value screen should appear after the loading beat.")
        cont.tap()   // value → science
        XCTAssertTrue(cont.waitForExistence(timeout: 5)); cont.tap()   // science → reveal
        XCTAssertTrue(cont.waitForExistence(timeout: 5)); cont.tap()   // reveal → paywall

        // Take the free version out of the paywall.
        let free = app.buttons["paywall.continueFree"]
        XCTAssertTrue(free.waitForExistence(timeout: 10), "Paywall should appear.")
        free.tap()

        XCTAssertTrue(app.buttons["home.primaryButton"].waitForExistence(timeout: 10), "Should land on home.")
        XCTAssertTrue(app.staticTexts["Luna"].waitForExistence(timeout: 5), "Home shows the new baby's name.")
    }

    // MARK: - start / stop a nap

    func testStartAndStopNap() {
        let app = launch("-seedSampleData")
        let start = app.buttons["home.primaryButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Start nap"].exists, "Awake baby → button reads Start nap.")
        start.tap()
        // Active label is "Pause nap" by day, "Wake up" at night — either means tracking started.
        let active = app.buttons["Pause nap"].waitForExistence(timeout: 5) || app.buttons["Wake up"].exists
        XCTAssertTrue(active, "After tapping, the sleep is being tracked.")
        app.buttons["home.primaryButton"].tap()
        XCTAssertTrue(app.buttons["Start nap"].waitForExistence(timeout: 5), "After stopping, back to awake.")
    }

    // MARK: - multi-baby switch updates the home screen

    func testSwitchingBabyUpdatesHome() {
        let app = launch("-seedSampleData", "-seedSecondBaby")   // Rosie 9mo + Theo 4mo
        XCTAssertTrue(app.staticTexts["Rosie"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["9 months old"].exists, "Rosie's age shows.")
        app.buttons["home.babySwitcher"].tap()
        app.buttons["babyMenu.Theo"].tap()
        XCTAssertTrue(app.staticTexts["Theo"].waitForExistence(timeout: 5), "Switched to Theo.")
        XCTAssertTrue(app.staticTexts["4 months old"].waitForExistence(timeout: 5), "Theo's (different) age shows.")
    }

    // MARK: - prematurity is per-baby (regression for the stale-settings bug)

    func testPrematurityIsPerBabyAndPersists() {
        let app = launch("-seedSampleData", "-seedSecondBaby")
        app.buttons["home.settings"].tap()
        let stepper = app.steppers["settings.prematurityStepper"]
        XCTAssertTrue(stepper.waitForExistence(timeout: 10))
        XCTAssertEqual(stepper.value as? String, "0", "Rosie starts at 0 weeks.")

        // SwiftUI stepper +/− buttons don't carry stable identifiers; tap the increment (right) side.
        let increment = stepper.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5))
        increment.tap()
        increment.tap()
        XCTAssertEqual(stepper.value as? String, "2", "Rosie is now 2 weeks early.")

        // Switch to Theo *within Settings* — the previously-stale field must now reflect Theo (0).
        app.buttons["settingsBaby.Theo"].tap()
        XCTAssertEqual(stepper.value as? String, "0", "Theo must NOT inherit Rosie's 2 weeks (the bug).")

        // Back to Rosie — her value persisted.
        app.buttons["settingsBaby.Rosie"].tap()
        XCTAssertEqual(stepper.value as? String, "2", "Rosie's value persisted per-baby.")
    }

    // MARK: - navigation to the major screens

    func testHistoryOpens() {
        let app = launch("-seedSampleData")
        app.buttons["home.history"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["home.primaryButton"].waitForExistence(timeout: 5))
    }

    func testBedtimeEditorOpens() {
        let app = launch("-seedSampleData")
        app.buttons["home.bedtime"].tap()
        XCTAssertTrue(app.navigationBars["Bedtime"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.switches["Optimise naps for a bedtime"].exists)
        app.buttons["Cancel"].tap()
    }

    func testSettingsOpensWithBabyList() {
        let app = launch("-seedSampleData", "-seedSecondBaby")
        app.buttons["home.settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["settingsBaby.Rosie"].exists)
        XCTAssertTrue(app.buttons["settingsBaby.Theo"].exists)
        app.buttons["Done"].tap()
    }

    // MARK: - jet-lag trip setup

    func testTripSetupSheetOpens() {
        let app = launch("-seedSampleData", "-showTripSheet")
        XCTAssertTrue(app.navigationBars["Plan a trip"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.switches["We've already arrived"].exists, "Trip setup shows the already-arrived toggle.")
        app.buttons["Cancel"].tap()
    }

    // MARK: - sharing opens a share sheet (smoke test; the device-only hijack isn't reproducible here)

    /// Smoke test: tapping "Invite partner" resolves a link and presents the ordinary share sheet
    /// without crashing. NOTE: the real bug — iOS hijacking a CKShare *`URL`* into its "Create Link →
    /// add people" collaboration sheet — only happens on a device with a genuine CKShare URL; the
    /// simulator uses a fake demo URL and shows the normal sheet regardless, so this test passes for
    /// both the buggy and fixed code and is NOT a regression guard for the hijack. It only guards
    /// against the share sheet failing to present.
    func testInvitePartnerShowsPlainShareSheet() {
        let app = launch("-seedSampleData")
        app.buttons["home.settings"].tap()

        let invite = app.buttons["settings.invitePartner"]
        var swipes = 0
        while !invite.isHittable && swipes < 8 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(invite.waitForExistence(timeout: 10), "Invite partner button should be reachable.")
        invite.tap()

        // The ordinary share sheet exposes the "ActivityListView" element; the collaboration sheet
        // (the thing we're avoiding) shows a "Create Link" title + "Add People" / "Share Link".
        let activityList = app.otherElements["ActivityListView"]
        XCTAssertTrue(activityList.waitForExistence(timeout: 10),
                      "Tapping invite should open the normal share sheet, not the collaboration flow.")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "share-sheet"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertFalse(app.staticTexts["Create Link"].exists, "Must not show the 'Create Link' collaboration sheet.")
        XCTAssertFalse(app.buttons["Share Link"].exists, "Must not show the collaboration 'Share Link' step.")
        XCTAssertFalse(app.buttons["Add People"].exists, "Must not require adding people before sharing.")
    }

    // MARK: - "didn't record the night?" nudge

    func testMissingNightNudgeOpensLogSheet() {
        let app = launch("-seedSampleData", "-forceMissingNight")
        let banner = app.buttons["home.missingNightBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "Missing-night nudge should show when last night wasn't recorded.")
        banner.tap()
        let sheetTitle = app.navigationBars["Log last night"]
        XCTAssertTrue(sheetTitle.waitForExistence(timeout: 5), "Tapping the nudge opens the log-night sheet.")
        XCTAssertTrue(app.buttons["Add night"].exists, "Sheet offers to add the assumed night.")
        app.buttons["Add night"].tap()
        XCTAssertFalse(sheetTitle.waitForExistence(timeout: 3), "Saving the night dismisses the sheet.")
    }

    // MARK: - resettle suggestion (seeded short early-wake)

    func testResettleSuggestionShows() {
        let app = launch("-seedSampleData", "-seedResettle")
        XCTAssertTrue(app.staticTexts["Try to resettle"].waitForExistence(timeout: 10),
                      "A short, recent nap should surface the resettle suggestion.")
    }
}
