//
//  SubscriptionPromoUITests.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Swifter
import XCTest

/// UI tests for the day-7 subscription promo sheet.
///
/// ## Reset mechanic
/// `-clearAllDefaults` wipes all UserDefaults domains at startup.
/// `-backdateInstallDate` sets the statistics install date to 7 days ago so the promo
/// cooldown is already satisfied.
///
/// ## Network isolation
/// A local Swifter HTTP server intercepts all ATB/stats requests by overriding `BASE_URL`.
/// Its `/atb.js` handler returns a stable ATB version with no `updateVersion` field, so
/// `storeUpdateVersionIfPresent` never clears the variant injected via `VARIANT=ru`.
/// This mirrors the approach used by `AtbIntegrationTests`.
final class SubscriptionPromoUITests: XCTestCase {

    private let app = XCUIApplication()
    private let server = HttpServer()
    private var serverBaseURL: String = ""

    private let presenceTimeout: TimeInterval = 20
    private let absenceTimeout: TimeInterval = 5

    // MARK: - Element queries

    private lazy var promoSheet: XCUIElement = app.descendants(matching: .any).matching(identifier: "subscriptionPromoSheet").firstMatch
    private lazy var noThanksButton: XCUIElement = app.buttons["No thanks"]
    private lazy var closeButton: XCUIElement = app.buttons["subscriptionPromoCloseButton"].firstMatch
    private lazy var daxDismissButton: XCUIElement = app.buttons["onboardingDialogDismissButton"].firstMatch
    private lazy var iveBeenHereBeforeButton: XCUIElement = app.buttons["I\u{2019}ve been here before"]
    private lazy var startBrowsingButton: XCUIElement = app.buttons["Start Browsing"]
    private lazy var gotItButton: XCUIElement = app.buttons["Got it!"].firstMatch
    private lazy var surpriseMeButton: XCUIElement = app.buttons["Surprise me!"].firstMatch
    private lazy var fireButton: XCUIElement = app.buttons["Browser.Toolbar.Button.Fire"].firstMatch
    private lazy var confirmFireButton: XCUIElement = app.buttons["alert.forget-data.confirm"].firstMatch
    private lazy var highFiveButton: XCUIElement = app.buttons["High five!"].firstMatch
    private lazy var letsGoButton: XCUIElement = app.buttons["Let\u{2019}s get started!"]
    private lazy var skipButton: XCUIElement = app.buttons["Skip"].firstMatch
    private lazy var nextButton: XCUIElement = app.buttons["Next"].firstMatch

    /// Matches whichever CTA label appears — "Try it free!" when the user is free-trial eligible,
    /// "Learn More" otherwise. In the simulator test environment with no real subscription products,
    /// `isUserEligibleForFreeTrial()` returns `false`, so "Learn More" is the expected label.
    private lazy var ctaButton: XCUIElement = {
        let predicate = NSPredicate(format: "label IN %@", ["Try it free!", "Learn More"])
        return app.buttons.matching(predicate).firstMatch
    }()

    // MARK: - Setup

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        try startServer()
    }

    override func tearDown() {
        super.tearDown()
        server.stop()
    }

    private func startServer() throws {
        server["/atb.js"] = { _ in
            .ok(.json([
                "version": "v77-5",
                "majorVersion": 77,
                "minorVersion": 5
            ]))
        }
        server["/exti/"] = { _ in .accepted }
        server["/t/:pixelName"] = { _ in .accepted }
        server["/"] = { _ in .ok(.html("")) }

        try server.start(0, forceIPv4: true, priority: .userInitiated)
        serverBaseURL = "http://127.0.0.1:\(try server.port())"
    }

    // MARK: - Tests


    // MARK: - A: Search-only path

    /// A.1 "Try a Search" dialog visible; hide app, restore; cold launch — no promo both times.
    ///
    /// After linear onboarding the NTP shows the initial "Try a Search" contextual dialog.
    /// Without tapping any chip, `isShowingContextualOnboardingDialog = true` blocks the promo
    /// on every foreground. A state-preserving cold relaunch keeps `tryAnonymousSearchShown = false`
    /// so the dialog is still pending and the promo is still blocked.
    func testPromoNotShownWhenTrySearchDialogIsActiveOrPending() {
        configure()
        app.launch()

        completeNewUserLinearOnboarding()

        // ── verify "Try a Search" dialog is showing — do NOT tap any chip ─────────
        XCTAssertTrue(
            surpriseMeButton.waitForExistence(timeout: presenceTimeout),
            "'Try a Search' dialog must be visible after linear onboarding."
        )

        // ── foreground — dialog active → no promo ────────────────────────────────
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Promo sheet must not appear while the 'Try a Search' dialog is active."
        )

        // ── cold relaunch — tryAnonymousSearchShown still false → dialog still pending
        relaunchPreservingState()

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Promo sheet must not appear on cold launch while the 'Try a Search' dialog is still pending."
        )

        // ── tap ✕ on the initial dialog — no search was ever completed ────────────
        // After cold relaunch tryAnonymousSearchShown is still false; the initial dialog
        // is still the active NTP spec. Tapping ✕ sets isDismissed = true but the promo
        // coordinator requires the user to have at least started a search, so no promo fires.
        XCTAssertTrue(
            daxDismissButton.waitForExistence(timeout: presenceTimeout),
            "Initial 'Try a Search' dialog must have a ✕ button after cold relaunch."
        )
        daxDismissButton.tap()

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Promo must not appear after ✕ on the initial 'Try a Search' dialog when no search was completed."
        )
    }

    /// A.2 Contextual onboarding at "Try Visiting a Site": foreground suppresses promo, but a
    /// subsequent cold launch shows it because `tryVisitASiteShown` was persisted.
    ///
    /// `tryAnonymousSearchShown = true` on launch makes the NTP return the `.subsequent`
    /// ("Try Visiting a Site") spec. Its `onFirstAppear` calls `setTryVisitSiteMessageSeen()`
    /// which persists `tryVisitASiteShown = true`. On the first bg→fg the promo is suppressed
    /// (`isShowingContextualOnboardingDialog = true`). After a state-preserving cold relaunch,
    /// `tryVisitASiteShown = true` means the NTP returns `nil` — no dialog — so
    /// `isShowingContextualOnboardingDialog = false` and the promo fires.
    func testTryVisitSiteDialogFgSuppressesPromoThenColdLaunchPromoAppears() {
        configure()
        app.launch()

        completeNewUserLinearOnboarding()

        // ── search chip → SERP → "Got it!" → "Try Visiting a Site" NTP dialog ──────
        // onFirstAppear persists tryVisitASiteShown = true.
        completeThroughSERPDialog()

        // ── first foreground: dialog active → no promo ────────────────────────────
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Promo sheet must not appear while the 'Try Visiting a Site' NTP dialog is active."
        )

        // ── state-preserving cold relaunch — tryVisitASiteShown = true persisted ──
        // NTP now returns nil (no dialog), so isShowingContextualOnboardingDialog = false.
        relaunchPreservingState()

        // ── foreground: no active dialog → promo fires ────────────────────────────
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertTrue(
            promoSheet.waitForExistence(timeout: presenceTimeout),
            "Promo sheet must appear on cold relaunch once tryVisitASiteShown is persisted and no NTP dialog is active."
        )

        // ── dismiss and verify it doesn't reappear ────────────────────────────────
        noThanksButton.tap()
        XCTAssertTrue(
            promoSheet.waitForNonExistence(timeout: absenceTimeout),
            "Promo sheet must disappear after dismissal."
        )

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Promo sheet must not reappear after it has been dismissed."
        )
    }

    /// A.3 Tapping the ✕ button on the "Try Visiting a Site" NTP dialog skips contextual onboarding
    /// (`isDismissed = true`). A subsequent cold launch must show the promo.
    ///
    /// After `completeThroughSERPDialog()` the NTP shows the `.subsequent` spec. Tapping
    /// `onboardingDialogDismissButton` triggers `onManualDismiss()` which calls
    /// `disableContextualDaxDialogs()` → `isDismissed = true`. On a state-preserving cold
    /// relaunch, `hasSeenOnboarding = true` satisfies `isEligibleToPresent` and the promo fires.
    func testPromoAppearsAfterSkippingContextualOnboardingViaXButton() {
        configure()
        app.launch()

        completeNewUserLinearOnboarding()

        // ── search chip → SERP → "Got it!" → "Try Visiting a Site" NTP dialog ──────
        completeThroughSERPDialog()

        // ── tap ✕ — skips contextual onboarding (isDismissed = true) ─────────────
        daxDismissButton.tap()

        relaunchPreservingState()

        // ── foreground: onboarding dismissed → promo fires ────────────────────────
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertTrue(
            promoSheet.waitForExistence(timeout: presenceTimeout),
            "Promo sheet must appear after skipping contextual onboarding via the ✕ button."
        )

        // ── dismiss and verify no reappearance ────────────────────────────────────
        noThanksButton.tap()
        XCTAssertTrue(
            promoSheet.waitForNonExistence(timeout: absenceTimeout),
            "Promo sheet must disappear after dismissal."
        )

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Promo sheet must not reappear after it has been dismissed."
        )
    }

    /// A.4 Fire-tutorial NTP dialog is active → no promo on foreground
    ///
    /// When `nonDDGBrowsingMessageSeen = true` (any of `browsingWithTrackersShown`,
    /// `browsingWithoutTrackersShown`, or `browsingMajorTrackingSiteShown` is set),
    /// `peekNextHomeScreenMessageExperiment()` calls `setFireEducationMessageSeen()` and returns
    /// `.final`. That sets `currentHomeSpec = .final`, so
    /// `isShowingContextualOnboardingDialog = true` and `isEligibleToPresent` returns `false`.
    func testPromoNotShownWhenFireTutorialPending() {
        configure()
        app.launch()

        completeNewUserLinearOnboarding()

        // ── search chip → SERP → "Got it!" → "Try Visiting a Site" dialog ─────────
        completeThroughSERPDialog()

        // ── tap site chip on "Try Visiting a Site" dialog; browsing dialog → "Got it!" ──
        XCTAssertTrue(surpriseMeButton.waitForExistence(timeout: presenceTimeout), "Site chip must appear on 'Try Visiting a Site' dialog.")
        surpriseMeButton.tap()

        XCTAssertTrue(gotItButton.waitForExistence(timeout: presenceTimeout), "Non-DDG browsing dialog must appear.")
        gotItButton.tap()

        // ── tap fire button → confirm → NTP .final ("High five!") dialog ─────────
        XCTAssertTrue(fireButton.waitForExistence(timeout: presenceTimeout), "Fire button must be visible.")
        fireButton.tap()

        XCTAssertTrue(confirmFireButton.waitForExistence(timeout: presenceTimeout), "Fire confirmation button must appear.")
        confirmFireButton.tap()

        XCTAssertTrue(
            highFiveButton.waitForExistence(timeout: presenceTimeout),
            "Fire-tutorial NTP dialog ('High five!') must appear."
        )

        // ── NTP computes .final (nonDDGBrowsingSeen=true) — no promo on foreground ─
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Promo sheet must not appear while the fire-tutorial NTP dialog is pending."
        )
    }

    /// A.5 Contextual subscription promo ("Oh, before I forget...") is pending on the NTP →
    /// no launch promo on foreground or cold relaunch.
    ///
    /// State: `isDismissed = false`, `browsingFinalDialogShown = true`,
    /// `subscriptionPromotionDialogShown = false`. `subscriptionPromotionPending = true` causes
    /// the NTP to set `currentHomeSpec = .subscriptionPromotion`, so
    /// `isShowingContextualOnboardingDialog = true` → `isEligibleToPresent` returns `false`.
    func testPromoNotShownWhenContextualSubscriptionPromoIsPending() {
        configure()
        app.launch()

        completeNewUserLinearOnboarding()

        // ── full onboarding flow → contextual subscription promo now on NTP ─────────
        completeContextualOnboardingToSubscriptionPromo()

        // ── foreground: contextual promo pending → no launch promo ────────────────
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Launch promo must not appear while the contextual subscription promo is pending."
        )

        // ── cold relaunch preserving state — still pending → no launch promo ──────
        relaunchPreservingState()

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Launch promo must not appear on cold relaunch while the contextual subscription promo is still pending."
        )
    }

    /// A.6 Tap "Try it free!" / "Learn More" on "Oh, before I forget..."; cold launch →
    /// no Day-7 promo sheet. `subscriptionPromotionDialogShown` is set when the contextual promo
    /// is shown; the launch-promo coordinator treats the same key as "already seen", so the
    /// Day-7 sheet is permanently suppressed.
    func testPromoNotShownAfterContextualSubscriptionPromoDismissedViaCTA() {
        configure()
        app.launch()

        completeNewUserLinearOnboarding()
        completeContextualOnboardingToSubscriptionPromo()

        // ── contextual promo: tap CTA ("Learn More" in simulator) ─────────────
        XCTAssertTrue(ctaButton.waitForExistence(timeout: presenceTimeout), "Contextual subscription promo CTA must appear.")
        ctaButton.tap()

        // ── cold relaunch ─────────────────────────────────────────────────────
        relaunchPreservingState()

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Day-7 launch promo must not appear after the contextual subscription promo was already shown."
        )
    }

    /// A.7 Tap "No thanks" on "Oh, before I forget..."; cold launch →
    /// no Day-7 promo sheet. Same `subscriptionPromotionDialogShown` gate as A.6.
    func testPromoNotShownAfterContextualSubscriptionPromoDismissedViaNoThanks() {
        configure()
        app.launch()

        completeNewUserLinearOnboarding()
        completeContextualOnboardingToSubscriptionPromo()

        // ── contextual promo: tap "No thanks" ─────────────────────────────────
        XCTAssertTrue(noThanksButton.waitForExistence(timeout: presenceTimeout), "'No thanks' must appear on contextual promo.")
        noThanksButton.tap()

        // ── cold relaunch ─────────────────────────────────────────────────────
        relaunchPreservingState()

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Day-7 launch promo must not appear after the contextual subscription promo was already shown."
        )
    }


    // MARK: - B: Search-chip path

    /// B.8 "Try Visiting a Site" NTP dialog is active → no promo on foreground
    ///
    /// Simulates the state that exists after the user selected a search chip from the
    /// "Try a search or AI chat" NTP dialog, saw "That's DuckDuckGo Search", and advanced to the
    /// "Try Visiting a Site" prompt — without actually driving that UI. Setting
    /// `tryAnonymousSearchShown = true` makes `peekNextHomeScreenMessageExperiment()` skip
    /// the `.initial` spec and return `.subsequent` ("Try Visiting a Site"). That NTP spec sets
    /// `currentHomeSpec`, so `isShowingContextualOnboardingDialog = true` and the launch promo
    /// coordinator's `isEligibleToPresent` gate returns `false`.
    ///
    /// Note: once the `.subsequent` dialog appears its `onFirstAppear` persists
    /// `tryVisitASiteShown = true`. A subsequent cold launch therefore shows no contextual
    /// NTP dialog and the promo fires (see `testTryVisitSiteDialogFgSuppressesPromoThenColdLaunchPromoAppears`).
    func testPromoNotShownWhenTryVisitSiteDialogIsActive() {
        configure()
        app.launch()

        completeNewUserLinearOnboarding()

        // ── search chip → SERP → "Got it!" → "Try Visiting a Site" NTP dialog ──────
        completeThroughSERPDialog()

        // ── NTP shows "Try Visiting a Site" (.subsequent) — foreground triggers no promo ──
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Promo sheet must not appear while the 'Try Visiting a Site' NTP dialog is active."
        )
    }

    /// SERP browsing dialog ("That's DuckDuckGo Search!") is visible — foreground → no promo.
    ///
    /// Tapping the search chip navigates to the SERP and `nextBrowsingMessageExperiment()`
    /// returns the `.afterSearch` spec, setting `lastShownDaxDialogType = .afterSearch`.
    /// That makes `isShowingContextualOnboardingDialog = true` so `isEligibleToPresent`
    /// returns `false` and the launch promo is blocked — without the user dismissing the dialog.
    func testPromoNotShownWhenSERPBrowsingDialogIsActive() {
        configure()
        app.launch()

        completeNewUserLinearOnboarding()

        // ── tap search chip → SERP loads with "That's DuckDuckGo Search!" dialog ──────
        XCTAssertTrue(surpriseMeButton.waitForExistence(timeout: presenceTimeout), "'Try a Search' chip must appear.")
        surpriseMeButton.tap()

        // Confirm the SERP browsing dialog is visible — do NOT tap "Got it!"
        XCTAssertTrue(gotItButton.waitForExistence(timeout: presenceTimeout), "SERP 'Got it!' must appear.")

        // ── background → foreground: lastShownDaxDialogType = .afterSearch → promo blocked ──
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Promo sheet must not appear while the SERP browsing dialog is active."
        )
    }

    /// Non-DDG browsing dialog (e.g. "No tracking attempts") is visible — foreground → no promo.
    ///
    /// Tapping the site chip navigates to a non-DDG site and `nextBrowsingMessageExperiment()`
    /// returns a browsing spec (e.g. `.withoutTrackers`), setting `lastShownDaxDialogType`.
    /// That makes `isShowingContextualOnboardingDialog = true` so `isEligibleToPresent`
    /// returns `false` and the launch promo is blocked — without the user dismissing the dialog.
    func testPromoNotShownWhenNonDDGBrowsingDialogIsActive() {
        configure()
        app.launch()

        completeNewUserLinearOnboarding()

        // ── search chip → SERP → "Got it!" → "Try Visiting a Site" dialog ─────────
        completeThroughSERPDialog()

        // ── tap site chip → non-DDG site with browsing dialog ───────────────────
        XCTAssertTrue(surpriseMeButton.waitForExistence(timeout: presenceTimeout), "Site chip must appear on 'Try Visiting a Site' dialog.")
        surpriseMeButton.tap()

        // Confirm the browsing dialog is visible — do NOT tap "Got it!"
        XCTAssertTrue(gotItButton.waitForExistence(timeout: presenceTimeout), "Non-DDG browsing dialog must appear.")

        // ── background → foreground: lastShownDaxDialogType set → promo blocked ──
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Promo sheet must not appear while a non-DDG browsing dialog is active."
        )
    }

    /// Search-chip path: tapping ✕ on "That's DuckDuckGo Search!" SERP dialog (search-only path)
    /// → promo fires on next foreground.
    ///
    /// Tapping ✕ on the SERP browsing dialog calls `disableContextualDaxDialogs()` →
    /// `isDismissed = true`. The search chip was already tapped so the search intent has been
    /// registered; the promo coordinator considers onboarding sufficiently started and the promo
    /// fires without requiring a cold relaunch.
    func testPromoAppearsAfterXButtonOnSERPDialogSearchOnlyPath() {
        configure()
        app.launch()

        completeNewUserLinearOnboarding()

        // ── tap search chip → SERP loads ─────────────────────────────────────────
        XCTAssertTrue(surpriseMeButton.waitForExistence(timeout: presenceTimeout), "'Try a Search' chip must appear.")
        surpriseMeButton.tap()

        // ── "That's DuckDuckGo Search!" browsing dialog is showing ───────────────
        XCTAssertTrue(gotItButton.waitForExistence(timeout: presenceTimeout), "'That's DuckDuckGo Search!' dialog must appear.")

        // ── tap ✕ instead of "Got it!" ───────────────────────────────────────────
        XCTAssertTrue(
            daxDismissButton.waitForExistence(timeout: presenceTimeout),
            "'That's DuckDuckGo Search!' dialog must have a ✕ button."
        )
        daxDismissButton.tap()

        // ── bg/fg → promo fires ──────────────────────────────────────────────────
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertTrue(
            promoSheet.waitForExistence(timeout: presenceTimeout),
            "Promo must appear after ✕ on 'That's DuckDuckGo Search!' dialog (search-only path)."
        )

        noThanksButton.tap()
        XCTAssertTrue(promoSheet.waitForNonExistence(timeout: absenceTimeout), "Promo must disappear after dismissal.")

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(promoSheet.waitForExistence(timeout: 2), "Promo must not reappear after dismissal.")
    }


    // MARK: - C: Duck.ai-chip path

    /// C.11 Promo appears when contextual onboarding is mid-way and no NTP dialog is currently blocking (Duck.ai dialog dismissed via ✕, cold launch).
    ///
    /// Models the state after a user on the Duck.ai path dismissed the contextual Duck.ai
    /// browsing dialog via ✕ and force-quit before reaching the fire step. Both
    /// `tryAnonymousSearchShown` and `tryVisitASiteShown` are `true`, which causes
    /// `peekNextHomeScreenMessageExperiment()` to fall through to `return nil` — no NTP dialog
    /// is shown. With `isShowingContextualOnboardingDialog = false` and
    /// `subscriptionPromotionDialogSeen = false`, `isEligibleToPresent` returns `true` and the
    /// promo appears despite `isDismissed = false` (onboarding still technically in progress).
    func testPromoAppearsWhenContextualOnboardingPausedBeforeNonDDGBrowsing() {
        configure()
        app.launch()

        completeDuckAIOnboarding(selecting: .duckAI)

        // ── Duck.ai contextual dialog appears: verify promo is blocked ────────────
        XCTAssertTrue(gotItButton.waitForExistence(timeout: presenceTimeout), "Duck.ai 'Got it!' dialog must appear.")

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Promo must not appear while Duck.ai contextual dialog is active."
        )

        // ── "Got it!" → "Try Visiting a Site" dialog appears ─────────────────────
        gotItButton.tap()

        XCTAssertTrue(
            daxDismissButton.waitForExistence(timeout: presenceTimeout),
            "'Try Visiting a Site' dialog must appear after Duck.ai 'Got it!'."
        )

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Promo must not appear while 'Try Visiting a Site' dialog is active."
        )

        // ── dismiss via ✕ — both contextual flags now true, fire step not reached ─
        daxDismissButton.tap()

        // ── NTP returns nil (no dialog) → promo fires on first foreground ─────────
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertTrue(
            promoSheet.waitForExistence(timeout: presenceTimeout),
            "Promo sheet must appear when contextual onboarding is paused with no active NTP dialog."
        )

        // ── dismiss and verify it goes away ──────────────────────────────────────
        XCTAssertTrue(noThanksButton.exists, "'No thanks' button must be visible.")
        noThanksButton.tap()

        XCTAssertTrue(
            promoSheet.waitForNonExistence(timeout: absenceTimeout),
            "Promo sheet must disappear after dismissal."
        )

        // ── second foreground — must NOT reappear ─────────────────────────────────
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Promo sheet must not reappear after it has been dismissed."
        )
    }

    /// Duck.ai path: tapping ✕ on "Try Visiting a Site"; force-quit; cold launch → promo appears.
    ///
    /// Analogous to A.3 but for the Duck.ai chip path. After the Duck.ai "Got it!" dialog is
    /// dismissed and "Try Visiting a Site" appears, tapping ✕ sets `isDismissed = true`.
    /// A state-preserving cold relaunch shows no contextual NTP dialog (`isDismissed = true` →
    /// `peekNextHomeScreenMessageExperiment()` returns nil), so `isShowingContextualOnboardingDialog = false`
    /// and the promo fires on the next foreground.
    func testPromoAppearsAfterXButtonOnTryVisitingSiteDialogDuckAIPathWithColdRelaunch() {
        configure()
        app.launch()

        completeDuckAIOnboarding(selecting: .duckAI)

        // ── Duck.ai "Got it!" → "Try Visiting a Site" dialog ─────────────────────
        XCTAssertTrue(gotItButton.waitForExistence(timeout: presenceTimeout), "Duck.ai browsing dialog must appear.")
        gotItButton.tap()

        XCTAssertTrue(
            daxDismissButton.waitForExistence(timeout: presenceTimeout),
            "'Try Visiting a Site' dialog must appear after Duck.ai 'Got it!'."
        )

        // ── tap ✕ → isDismissed = true ───────────────────────────────────────────
        daxDismissButton.tap()

        // ── cold relaunch ─────────────────────────────────────────────────────────
        relaunchPreservingState()

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertTrue(
            promoSheet.waitForExistence(timeout: presenceTimeout),
            "Promo must appear on cold relaunch after ✕ on 'Try Visiting a Site' (Duck.ai path)."
        )

        noThanksButton.tap()
        XCTAssertTrue(promoSheet.waitForNonExistence(timeout: absenceTimeout), "Promo must disappear after dismissal.")

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(promoSheet.waitForExistence(timeout: 2), "Promo must not reappear after dismissal.")
    }

    /// Duck.ai path: tapping ✕ on the Duck.ai browsing dialog (the "Got it!" overlay on the
    /// Duck.ai page) → `isDismissed = true` → promo fires on next foreground.
    func testPromoAppearsAfterXButtonOnDuckAIBrowsingDialog() {
        configure()
        app.launch()

        completeDuckAIOnboarding(selecting: .duckAI)

        // ── Duck.ai browsing dialog is showing on the Duck.ai page ───────────────
        XCTAssertTrue(gotItButton.waitForExistence(timeout: presenceTimeout), "Duck.ai browsing dialog must appear.")

        // ── tap ✕ instead of "Got it!" ───────────────────────────────────────────
        XCTAssertTrue(
            daxDismissButton.waitForExistence(timeout: presenceTimeout),
            "Duck.ai browsing dialog must have a ✕ dismiss button."
        )
        daxDismissButton.tap()

        // ── bg/fg → promo fires ──────────────────────────────────────────────────
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertTrue(
            promoSheet.waitForExistence(timeout: presenceTimeout),
            "Promo must appear after ✕ on the Duck.ai browsing dialog."
        )

        noThanksButton.tap()
        XCTAssertTrue(promoSheet.waitForNonExistence(timeout: absenceTimeout), "Promo must disappear after dismissal.")

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(promoSheet.waitForExistence(timeout: 2), "Promo must not reappear after dismissal.")
    }

    /// Duck.ai path (search-chip variant): tapping ✕ on the "That's DuckDuckGo Search!" SERP
    /// browsing dialog → `isDismissed = true` → promo fires on next foreground.
    ///
    /// `completeDuckAIOnboarding(selecting: .search)` drives the Duck.ai-capable linear
    /// onboarding then taps the search segment chip, landing on the SERP with the
    /// "That's DuckDuckGo Search!" dialog.
    func testPromoAppearsAfterXButtonOnSERPDialogDuckAISearchPath() {
        configure()
        app.launch()

        completeDuckAIOnboarding(selecting: .search)

        // ── "That's DuckDuckGo Search!" SERP browsing dialog is showing ──────────
        XCTAssertTrue(gotItButton.waitForExistence(timeout: presenceTimeout), "'That's DuckDuckGo Search!' dialog must appear.")

        // ── tap ✕ instead of "Got it!" ───────────────────────────────────────────
        XCTAssertTrue(
            daxDismissButton.waitForExistence(timeout: presenceTimeout),
            "'That's DuckDuckGo Search!' dialog must have a ✕ dismiss button."
        )
        daxDismissButton.tap()

        // ── bg/fg → promo fires ──────────────────────────────────────────────────
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertTrue(
            promoSheet.waitForExistence(timeout: presenceTimeout),
            "Promo must appear after ✕ on 'That's DuckDuckGo Search!' dialog (Duck.ai search path)."
        )

        noThanksButton.tap()
        XCTAssertTrue(promoSheet.waitForNonExistence(timeout: absenceTimeout), "Promo must disappear after dismissal.")

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(promoSheet.waitForExistence(timeout: 2), "Promo must not reappear after dismissal.")
    }

    /// C.12 Duck.ai-chip path: fire tutorial done, "Oh, before I forget..." contextual promo pending →
    /// no launch promo on cold relaunch. Same `subscriptionPromotionPending` gate as A.5/B.9.
    func testPromoNotShownWhenContextualSubscriptionPromoIsPendingDuckAIPath() {
        configure()
        app.launch()

        completeDuckAIOnboarding(selecting: .duckAI)

        // ── Duck.ai onboarding flow → contextual subscription promo now on NTP ──────
        completeDuckAIPathToSubscriptionPromo()

        // ── foreground: contextual promo on NTP → no launch promo ────────────────
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Launch promo must not appear while the contextual subscription promo is pending (Duck.ai path)."
        )

        relaunchPreservingState()

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Launch promo must not appear on cold relaunch while contextual promo is pending (Duck.ai path)."
        )
    }

    /// C.13 Select a Duck.ai chip; complete full contextual onboarding; cold launch →
    /// no Day-7 promo sheet. Same `subscriptionPromotionDialogShown` gate as B.10.
    func testPromoNotShownAfterFullContextualOnboardingCompleteDuckAIPath() {
        configure()
        app.launch()

        completeDuckAIOnboarding(selecting: .duckAI)

        // ── Duck.ai onboarding flow → contextual subscription promo now on NTP ──────
        completeDuckAIPathToSubscriptionPromo()

        // ── dismiss contextual promo via "No thanks" ──────────────────────────────
        XCTAssertTrue(noThanksButton.waitForExistence(timeout: presenceTimeout), "'No thanks' must appear on contextual promo.")
        noThanksButton.tap()

        // ── cold relaunch ─────────────────────────────────────────────────────────
        relaunchPreservingState()

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Day-7 launch promo must not appear after the full contextual onboarding (Duck.ai path) was completed."
        )
    }


    /// Duck.ai path: Duck.ai browsing dialog ("Got it!" on the Duck.ai page) is visible —
    /// foreground → no promo.
    ///
    /// After tapping the Duck.ai chip `nextBrowsingMessageExperiment()` sets
    /// `lastShownDaxDialogType` to the Duck.ai browsing spec. That makes
    /// `isShowingContextualOnboardingDialog = true` so `isEligibleToPresent` returns `false`
    /// and the launch promo is blocked — without the user dismissing the dialog.
    func testPromoNotShownWhenDuckAIBrowsingDialogIsActive() {
        configure()
        app.launch()

        completeDuckAIOnboarding(selecting: .duckAI)

        // ── Duck.ai browsing "Got it!" dialog is showing — do NOT tap it ─────────
        XCTAssertTrue(
            gotItButton.waitForExistence(timeout: presenceTimeout),
            "Duck.ai browsing dialog must appear after selecting the Duck.ai chip."
        )

        // ── foreground: lastShownDaxDialogType set → no promo ────────────────────
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Promo sheet must not appear while the Duck.ai browsing dialog is active."
        )
    }

    /// Duck.ai path: "Try Visiting a Site" NTP dialog is visible — foreground → no promo.
    ///
    /// After the Duck.ai "Got it!" dialog is tapped the NTP returns to showing the
    /// `.subsequent` ("Try Visiting a Site") spec, setting `currentHomeSpec = .subsequent`.
    /// `isShowingContextualOnboardingDialog = true` blocks the promo, as in the
    /// search-chip path (B.8).
    func testPromoNotShownWhenTryVisitSiteDialogIsActiveDuckAIPath() {
        configure()
        app.launch()

        completeDuckAIOnboarding(selecting: .duckAI)

        // ── tap Duck.ai "Got it!" → NTP shows "Try Visiting a Site" ─────────────
        XCTAssertTrue(gotItButton.waitForExistence(timeout: presenceTimeout), "Duck.ai browsing dialog must appear.")
        gotItButton.tap()

        XCTAssertTrue(
            daxDismissButton.waitForExistence(timeout: presenceTimeout),
            "'Try Visiting a Site' dialog must appear after Duck.ai 'Got it!'."
        )

        // ── foreground: currentHomeSpec = .subsequent → no promo ─────────────────
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Promo sheet must not appear while the 'Try Visiting a Site' NTP dialog is active (Duck.ai path)."
        )
    }

    /// Duck.ai path: fire-tutorial NTP dialog ("High five!" / "You've got this!") is visible —
    /// foreground → no promo.
    ///
    /// After the fire tutorial completes `peekNextHomeScreenMessageExperiment()` returns
    /// `.final`, setting `currentHomeSpec = .final`. `isShowingContextualOnboardingDialog = true`
    /// blocks the promo — the same gate as A.4 but reached via the Duck.ai chip path.
    func testPromoNotShownWhenFireTutorialPendingDuckAIPath() {
        configure()
        app.launch()

        completeDuckAIOnboarding(selecting: .duckAI)

        // ── Duck.ai "Got it!" → "Try Visiting a Site" ────────────────────────────
        XCTAssertTrue(gotItButton.waitForExistence(timeout: presenceTimeout), "Duck.ai browsing dialog must appear.")
        gotItButton.tap()

        // ── tap site chip → non-DDG site → browsing dialog → "Got it!" ───────────
        XCTAssertTrue(surpriseMeButton.waitForExistence(timeout: presenceTimeout), "Site chip must appear on 'Try Visiting a Site' dialog.")
        surpriseMeButton.tap()

        XCTAssertTrue(gotItButton.waitForExistence(timeout: presenceTimeout), "Non-DDG browsing dialog must appear.")
        gotItButton.tap()

        // ── fire button → confirm → NTP .final ("High five!") dialog ─────────────
        XCTAssertTrue(fireButton.waitForExistence(timeout: presenceTimeout), "Fire button must be visible.")
        fireButton.tap()

        XCTAssertTrue(confirmFireButton.waitForExistence(timeout: presenceTimeout), "Fire confirmation button must appear.")
        confirmFireButton.tap()

        XCTAssertTrue(
            highFiveButton.waitForExistence(timeout: presenceTimeout),
            "Fire-tutorial NTP dialog ('High five!') must appear (Duck.ai path)."
        )

        // ── foreground: currentHomeSpec = .final → no promo ──────────────────────
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Promo sheet must not appear while the fire-tutorial NTP dialog is pending (Duck.ai path)."
        )
    }


    // MARK: - D: Dismissal & CTA behavior

    /// Reinstaller / skipped-onboarding path (`subscriptionPromoForReinstallers`) — smoke test.
    ///
    /// Uses the returning-user variant (`VARIANT=ru`) which reduces onboarding to two taps:
    /// "I've been here before" → "Start Browsing". The promo fires on the first foreground event
    /// after the onboarding modal is dismissed.
    func testPromoSheetAppearsOnceAfterOnboarding() {
        configure(as: .returningUser)
        app.launch()

        // ── Step 1: skip the linear onboarding ──────────────────────────────────
        completeReturningUserOnboarding()

        // ── Step 2: background → foreground triggers presentModalPromptIfNeeded ──
        XCUIDevice.shared.press(.home)
        app.activate()

        // ── Step 3: promo sheet must appear ─────────────────────────────────────
        XCTAssertTrue(
            promoSheet.waitForExistence(timeout: presenceTimeout),
            "Subscription promo sheet must appear on first foreground after onboarding."
        )

        // ── Step 4: dismiss and verify it goes away ──────────────────────────────
        XCTAssertTrue(noThanksButton.exists, "'No thanks' button must be visible.")
        noThanksButton.tap()

        XCTAssertTrue(
            promoSheet.waitForNonExistence(timeout: absenceTimeout),
            "Promo sheet must disappear after dismissal."
        )

        // ── Step 5: background → foreground again — sheet must NOT reappear ──────
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Promo sheet must not reappear after it has been dismissed."
        )
    }

    /// Existing-user path with contextual dax dialogs — promo appears after "Try Visiting a Site" dismissed via ✕.
    ///
    /// Taps through the full contextual search dialog flow — "Try a Search" chip → SERP →
    /// "That's DuckDuckGo Search!" ("Got it!") → "Try Visiting a Site" (✕) — then verifies
    /// the promo fires on the next foreground and does not reappear after dismissal.
    func testExistingUserPromoSheetAfterDismissingTrySearchDialog() {
        configure()
        app.launch()

        completeNewUserLinearOnboarding()

        // ── "Try a Search" dialog: tap search chip → navigate to SERP ────────────
        XCTAssertTrue(surpriseMeButton.waitForExistence(timeout: presenceTimeout), "'Try a Search' chip must appear.")
        surpriseMeButton.tap()

        // ── "That's DuckDuckGo Search!" browsing dialog appears on SERP ──────────
        XCTAssertTrue(gotItButton.waitForExistence(timeout: presenceTimeout), "'That's DuckDuckGo Search!' dialog must appear.")

        // ── hide/show — promo must NOT appear while dialog is on screen ──────────
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Promo must not appear while 'That's DuckDuckGo Search!' dialog is active."
        )

        // ── tap "Got it!" → "Try Visiting a Site" dialog appears ─────────────────
        gotItButton.tap()

        XCTAssertTrue(
            daxDismissButton.waitForExistence(timeout: presenceTimeout),
            "'Try Visiting a Site' dialog must appear after 'Got it!'."
        )

        // ── hide/show — promo must NOT appear while "Try Visiting a Site" is active
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Promo must not appear while 'Try Visiting a Site' dialog is active."
        )

        // ── dismiss "Try Visiting a Site" via ✕ → isDismissed = true ─────────────
        daxDismissButton.tap()

        // ── hide/show — promo must now appear ────────────────────────────────────
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertTrue(
            promoSheet.waitForExistence(timeout: presenceTimeout),
            "Promo must appear after dismissing 'Try Visiting a Site' dialog."
        )

        // ── dismiss and verify it goes away ──────────────────────────────────────
        noThanksButton.tap()

        XCTAssertTrue(
            promoSheet.waitForNonExistence(timeout: absenceTimeout),
            "Promo must disappear after dismissal."
        )

        // ── hide/show again — sheet must NOT reappear ─────────────────────────────
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Promo must not reappear after dismissal."
        )
    }

    /// D.14 Tap CTA ("Try it free!" / "Learn More"); force-quit; cold launch → no promo sheet.
    ///
    /// After the CTA is tapped `subscriptionPromotionDialogSeen` is set; cold relaunch must not
    /// show the promo again.
    func testExistingUserPromoCTATapDismissesSheetAndPreventsReappearanceOnColdRelaunch() {
        configure(as: .returningUser)
        app.launch()

        completeReturningUserOnboarding()

        // ── background → foreground triggers promo ────────────────────────────────
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertTrue(
            promoSheet.waitForExistence(timeout: presenceTimeout),
            "Subscription promo sheet must appear on first foreground after onboarding."
        )

        // ── tap the CTA button ────────────────────────────────────────────────────
        XCTAssertTrue(ctaButton.waitForExistence(timeout: presenceTimeout), "CTA button must be visible.")
        ctaButton.tap()

        XCTAssertTrue(
            promoSheet.waitForNonExistence(timeout: absenceTimeout),
            "Promo sheet must disappear after tapping the CTA button."
        )

        relaunchPreservingState()

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Promo sheet must not reappear on cold relaunch after CTA was tapped."
        )
    }

    /// D.15 Tap "No thanks"; force-quit; cold launch → no promo sheet (already shown).
    func testNoThanksDismissalPreventsReappearanceOnColdRelaunch() {
        configure(as: .returningUser)
        app.launch()

        completeReturningUserOnboarding()

        // ── background → foreground — promo appears ───────────────────────────────
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertTrue(
            promoSheet.waitForExistence(timeout: presenceTimeout),
            "Subscription promo sheet must appear on first foreground after onboarding."
        )

        // ── dismiss via "No thanks" ───────────────────────────────────────────────
        XCTAssertTrue(noThanksButton.exists, "'No thanks' button must be visible.")
        noThanksButton.tap()

        XCTAssertTrue(
            promoSheet.waitForNonExistence(timeout: absenceTimeout),
            "Promo sheet must disappear after 'No thanks'."
        )

        // ── cold relaunch — must not reappear ─────────────────────────────────────
        relaunchPreservingState()

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Promo sheet must not reappear on cold relaunch after 'No thanks' was tapped."
        )
    }

    /// D.16 Tap ✕; reopen; cold launch → no promo sheet.
    ///
    /// Tapping the close icon dismisses the sheet and sets `subscriptionPromotionDialogSeen`,
    /// preventing reappearance on subsequent foreground events and cold relaunches.
    func testExistingUserPromoSheetDismissedByCloseButton() {
        configure(as: .returningUser)
        app.launch()

        completeReturningUserOnboarding()

        // ── background → foreground — promo appears ───────────────────────────────
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertTrue(
            promoSheet.waitForExistence(timeout: presenceTimeout),
            "Subscription promo sheet must appear on first foreground after onboarding."
        )

        // ── dismiss via the ✕ close button ───────────────────────────────────────
        XCTAssertTrue(closeButton.exists, "Close button (✕) must be visible.")
        closeButton.tap()

        XCTAssertTrue(
            promoSheet.waitForNonExistence(timeout: absenceTimeout),
            "Promo sheet must disappear after tapping the close button."
        )

        // ── background → foreground again — sheet must NOT reappear ──────────────
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Promo sheet must not reappear after it has been closed."
        )
    }

    /// D.17 Background while promo visible; reopen → promo still visible; cold launch → no promo sheet.
    func testPromoRemainsVisibleAfterBackgroundingAndDoesNotReappearOnColdRelaunch() {
        configure(as: .returningUser)
        app.launch()

        completeReturningUserOnboarding()

        // ── background → foreground — promo appears ───────────────────────────────
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertTrue(
            promoSheet.waitForExistence(timeout: presenceTimeout),
            "Subscription promo sheet must appear on first foreground after onboarding."
        )

        // ── background without dismissing the promo ───────────────────────────────
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertTrue(
            promoSheet.waitForExistence(timeout: presenceTimeout),
            "Promo sheet must still be visible after backgrounding and restoring without dismissal."
        )

        // ── cold relaunch preserving state — promo must NOT reappear ─────────────
        relaunchPreservingState()

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Promo sheet must not reappear on cold relaunch after it was already presented."
        )
    }


    // MARK: - E: Guards & gates

    /// E.18 Verifies the promo does not appear when the install-date cooldown has not yet passed.
    ///
    /// Uses the reinstaller path (fast 2-tap onboarding) without `-backdateInstallDate` so the
    /// install date is set to "now" and neither coordinator's cooldown is satisfied.
    func testPromoNotShownWhenCooldownNotPassed() {
        configure(as: .returningUser, backdated: false)
        app.launch()

        completeReturningUserOnboarding()

        // ── background → foreground — cooldown not met, no promo ─────────────────
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Promo sheet must not appear when the install-date cooldown has not passed."
        )
    }

    /// E.19 Verifies the existing-user promo does not appear when the `subscriptionPromoForExistingUsers` feature flag is disabled.
    func testPromoNotShownWhenExistingUserFlagDisabled() {
        configure(flagOverrides: ["subscriptionPromoForExistingUsers": "false", "subscriptionPromoForReinstallers": "false"])
        app.launch()

        completeNewUserLinearOnboarding()

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Promo sheet must not appear when subscriptionPromoForExistingUsers flag is disabled."
        )
    }

    /// E.20 Verifies neither promo appears when the outer `privacyProOnboardingPromotion` gate is disabled.
    func testPromoNotShownWhenPrivacyProGateDisabled() {
        configure(as: .returningUser, flagOverrides: ["privacyProOnboardingPromotion": "false"])
        app.launch()

        completeReturningUserOnboarding()

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Promo sheet must not appear when privacyProOnboardingPromotion gate is disabled."
        )
    }

    /// E.21 Verifies the reinstaller promo does not appear when `subscriptionPromoForReinstallers` is disabled.
    func testReinstallerPromoNotShownWhenFlagDisabled() {
        configure(as: .returningUser, flagOverrides: ["subscriptionPromoForReinstallers": "false"])
        app.launch()

        completeReturningUserOnboarding()

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Reinstaller promo must not appear when subscriptionPromoForReinstallers flag is disabled."
        )
    }

    /// E.22 Reinstaller promo takes priority over the existing-user promo when both coordinators are eligible.
    ///
    /// With `VARIANT=ru`, `hasSkippedOnboarding` is set after completing the returning-user
    /// flow, making `SubscriptionPromoCoordinator` eligible. The existing-user coordinator is
    /// also eligible (backdated install date, `subscriptionPromoForExistingUsers` enabled).
    /// The reinstaller provider sits at a higher position in the queue, so it must fire first
    /// and the sheet must appear exactly once per session.
    func testReinstallerPromoTakesPriorityOverExistingUserPromo() {
        configure(as: .returningUser)
        app.launch()

        // ── complete reinstaller (returning-user) onboarding ─────────────────────
        completeReturningUserOnboarding()

        // ── background → foreground — promo must appear (reinstaller wins) ────────
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertTrue(
            promoSheet.waitForExistence(timeout: presenceTimeout),
            "Subscription promo sheet must appear (reinstaller coordinator takes priority)."
        )

        // ── dismiss it — only one promo per foreground event ──────────────────────
        noThanksButton.tap()
        XCTAssertTrue(
            promoSheet.waitForNonExistence(timeout: absenceTimeout),
            "Promo sheet must disappear after dismissal."
        )

        // ── second foreground — reinstaller is spent; existing-user promo eligible ─
        XCUIDevice.shared.press(.home)
        app.activate()

        // The manager enforces a same-session cooldown (`didPresentModalPromptThisSession`),
        // so the existing-user promo must not appear immediately in this session.
        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "No second promo must appear in the same session after the reinstaller promo was shown."
        )
    }

    // MARK: - G: Upgrade scenarios

    /// G.24 Upgrade from pre-feature build: onboarding fully complete → promo appears on first launch after update.
    ///
    /// Simulates state from commit 0f064b1e66 (before this feature existed) after the user
    /// completed full linear + contextual onboarding: `isDismissed = true` (default when the key
    /// is absent), `browsingFinalDialogShown = true` (EOJ seen). The new
    /// `subscriptionPromotionDialogSeen` key did not exist in that build, so it is `false` by
    /// default. With `hasSeenOnboarding = true` and cooldown satisfied, the promo must appear on
    /// the first background → foreground cycle without going through any onboarding UI.
    func testUpgradeFromPreFeatureBuildWithCompletedOnboardingPromoAppearsOnColdLaunch() {
        configure(onboardingAlreadyCompleted: true, extraArgs: ["-setDaxState.browsingFinalDialogShown"])
        app.launch()

        // ── background → foreground triggers presentModalPromptIfNeeded ──────────
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertTrue(
            promoSheet.waitForExistence(timeout: presenceTimeout),
            "Promo sheet must appear after upgrading from pre-feature build with completed onboarding."
        )

        noThanksButton.tap()
        XCTAssertTrue(
            promoSheet.waitForNonExistence(timeout: absenceTimeout),
            "Promo sheet must disappear after dismissal."
        )

        // ── cold relaunch preserving state — must NOT reappear ────────────────────
        relaunchPreservingState()

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Promo sheet must not reappear on subsequent cold launch after upgrade."
        )
    }

    /// G.25 Upgrade from pre-feature build: linear onboarding complete, contextual still in progress → no promo on cold relaunch.
    ///
    /// Simulates the state from commit 0f064b1e66 after the user completed linear onboarding
    /// but stopped before any contextual dax dialog: `isDismissed = false`,
    /// `tryAnonymousSearchShown = false`. On cold relaunch the NTP re-presents the `.initial`
    /// home spec, making `isShowingContextualOnboardingDialog = true`. The
    /// `isEligibleToPresent` gate therefore returns `false` and no promo appears.
    func testUpgradeFromPreFeatureBuildWithIncompleteOnboardingNoPromoOnColdRelaunch() {
        configure()
        app.launch()

        completeNewUserLinearOnboarding()

        // ── force-quit while contextual dialog is still on screen ─────────────────
        XCUIDevice.shared.press(.home)

        // ── cold relaunch preserving state ────────────────────────────────────────
        relaunchPreservingState()

        // ── NTP re-presents .initial dialog → no promo on foreground ─────────────
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: 2),
            "Promo sheet must not appear when contextual onboarding is still in progress after upgrade."
        )
    }


    // MARK: - Helpers: configuration

    private enum UserType {
        case newUser
        case returningUser
    }

    /// Configures the app for a clean-state launch.
    ///
    /// - Parameters:
    ///   - userType: `.newUser` for full linear onboarding; `.returningUser` (VARIANT=ru) for the
    ///     2-tap reinstaller path.
    ///   - backdated: When `true` the install date is set to 7 days ago so the promo cooldown is
    ///     already satisfied. Pass `false` to test the "cooldown not yet passed" gate.
    ///   - onboardingAlreadyCompleted: When `true`, skips `-setDaxNotDismissed` so `isDismissed`
    ///     keeps its default value of `true`. Use this to simulate a returning user whose onboarding
    ///     was fully completed in a prior build and no onboarding UI should appear on launch.
    ///   - flagOverrides: Optional key/value pairs appended after the defaults, allowing individual
    ///     tests to disable specific feature flags (e.g. `["subscriptionPromoForExistingUsers": "false"]`).
    ///   - extraArgs: Additional raw launch arguments appended last (e.g. dax-state injection for
    ///     upgrade-path tests).
    private func configure(
        as userType: UserType = .newUser,
        backdated: Bool = true,
        onboardingAlreadyCompleted: Bool = false,
        flagOverrides: [String: String] = [:],
        extraArgs: [String] = []
    ) {
        var args = ["-clearAllDefaults", "isRunningUITests"]
        if backdated { args += ["-backdateInstallDate"] }
        args += [
            "-ff.subscriptionPromoForExistingUsers", "true",
            "-ff.subscriptionPromoForReinstallers", "true",
            "-ff.privacyProOnboardingPromotion", "true",
        ]
        // Backdating writes ATB keys (hasInstallStatistics=true) which prevents primeForUse()
        // from running, leaving isDismissed at its default of true. Restore the natural
        // post-install state unless `onboardingAlreadyCompleted` is true (the user already
        // finished onboarding in a prior build, so isDismissed must stay true). For returning
        // users the UI flow ("Start Browsing") sets isDismissed back to true before any promo
        // logic runs.
        if backdated && !onboardingAlreadyCompleted {
            args += ["-setDaxNotDismissed"]
        }
        // LaunchOptionsHandler reads "-isOnboardingCompleted true" from UserDefaults to set
        // hasSeenOnboarding = true, bypassing the linear onboarding entirely.
        if onboardingAlreadyCompleted {
            args += ["-isOnboardingCompleted", "true"]
        }
        for (key, value) in flagOverrides {
            args += ["-ff.\(key)", value]
        }
        args += extraArgs
        app.launchArguments = args
        var env: [String: String] = [
            "UITEST_MODE": "1",
            "BASE_URL": serverBaseURL,
            "PIXEL_BASE_URL": serverBaseURL,
        ]
        if userType == .returningUser { env["VARIANT"] = "ru" }
        app.launchEnvironment = env
    }

    // MARK: - Helpers: app lifecycle

    /// Terminates the app and relaunches without `-clearAllDefaults` or `-backdateInstallDate`,
    /// preserving all UserDefaults written during the previous session (e.g.
    /// `subscriptionPromotionDialogSeen`, `isDismissed`, dax state flags). Feature flags are
    /// re-applied so coordinator eligibility checks still pass on the fresh launch.
    private func relaunchPreservingState() {
        app.terminate()
        app.launchArguments = [
            "-ff.subscriptionPromoForExistingUsers", "true",
            "-ff.subscriptionPromoForReinstallers", "true",
            "-ff.privacyProOnboardingPromotion", "true",
            "isRunningUITests",
        ]
        app.launchEnvironment = [
            "UITEST_MODE": "1",
            "BASE_URL": serverBaseURL,
            "PIXEL_BASE_URL": serverBaseURL,
        ]
        app.launch()
    }

    // MARK: - Helpers: onboarding flows

    /// Taps through the returning-user (reinstaller) onboarding: "I've been here before" → "Start Browsing".
    private func completeReturningUserOnboarding() {
        XCTAssertTrue(iveBeenHereBeforeButton.waitForExistence(timeout: presenceTimeout), "Onboarding intro must appear.")
        iveBeenHereBeforeButton.tap()

        XCTAssertTrue(startBrowsingButton.waitForExistence(timeout: presenceTimeout), "Skip confirmation must appear.")
        startBrowsingButton.tap()
    }

    private enum SearchOrDuckAIPath {
        case search
        case duckAI
    }

    /// Taps through the full new-user linear onboarding selecting "Toggle between Search and Duck.ai",
    /// then taps the specified first chip on the contextual "Try a Search or AI Chat" dialog.
    private func completeDuckAIOnboarding(selecting path: SearchOrDuckAIPath) {
        XCTAssertTrue(letsGoButton.waitForExistence(timeout: presenceTimeout), "Onboarding intro must appear.")
        letsGoButton.tap()

        // Browser comparison → Skip
        XCTAssertTrue(skipButton.waitForExistence(timeout: presenceTimeout), "Browser comparison skip must appear.")
        skipButton.tap()

        // Add to Dock promo → Skip
        XCTAssertTrue(skipButton.waitForExistence(timeout: presenceTimeout), "Add-to-Dock skip must appear.")
        skipButton.tap()

        // App icon selection → Next
        XCTAssertTrue(nextButton.waitForExistence(timeout: presenceTimeout), "App-icon Next must appear.")
        nextButton.tap()

        // Address bar position → Next
        XCTAssertTrue(nextButton.waitForExistence(timeout: presenceTimeout), "Address-bar Next must appear.")
        nextButton.tap()

        // Search experience → select "Toggle between Search and Duck.ai" then Next
        let duckAIOption = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Duck.ai'")).firstMatch
        XCTAssertTrue(duckAIOption.waitForExistence(timeout: presenceTimeout), "Search & Duck.ai option must appear.")
        duckAIOption.tap()

        XCTAssertTrue(nextButton.waitForExistence(timeout: presenceTimeout), "Search-experience Next must appear.")
        nextButton.tap()

        switch path {
        case .search:
            let searchSegment = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Search'")).firstMatch
            XCTAssertTrue(searchSegment.waitForExistence(timeout: presenceTimeout), "Search segment must appear.")
            searchSegment.tap()
        case .duckAI:
            let duckAISegment = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Duck.ai'")).firstMatch
            XCTAssertTrue(duckAISegment.waitForExistence(timeout: presenceTimeout), "Duck.ai segment must appear.")
            duckAISegment.tap()
        }

        XCTAssertTrue(surpriseMeButton.waitForExistence(timeout: presenceTimeout), "Surprise me! chip must appear.")
        surpriseMeButton.tap()
    }

    /// Drives the contextual onboarding from the initial NTP dialog through to the
    /// "Try Visiting a Site" (.subsequent) dialog appearing on the NTP.
    ///
    /// Flow: tap "Surprise me!" search chip → SERP "That's DuckDuckGo Search!" "Got it!" →
    /// NTP shows "Try Visiting a Site" dialog.
    ///
    /// Ends with `daxDismissButton` visible (the "Try Visiting a Site" dialog ✕ button).
    private func completeThroughSERPDialog() {
        XCTAssertTrue(surpriseMeButton.waitForExistence(timeout: presenceTimeout), "'Try a Search' chip must appear.")
        surpriseMeButton.tap()

        XCTAssertTrue(gotItButton.waitForExistence(timeout: presenceTimeout), "SERP browsing dialog must appear.")
        gotItButton.tap()

        XCTAssertTrue(daxDismissButton.waitForExistence(timeout: presenceTimeout), "'Try Visiting a Site' NTP dialog must appear.")
    }

    /// Drives the Duck.ai contextual onboarding path all the way through to the
    /// "Oh, before I forget..." contextual subscription promo dialog appearing on the NTP.
    ///
    /// Precondition: `completeDuckAIOnboarding(selecting: .duckAI)` has already been called,
    /// leaving the app on the Duck.ai chat with the first contextual "Got it!" dialog pending.
    ///
    /// Flow: "Got it!" on Duck.ai dialog → "Try Visiting a Site" dialog → navigate to non-DDG
    /// site → browsing dialog "Got it!" → tap fire button → confirm fire → NTP "High five!" →
    /// contextual subscription promo visible.
    private func completeDuckAIPathToSubscriptionPromo() {
        XCTAssertTrue(gotItButton.waitForExistence(timeout: presenceTimeout), "Duck.ai 'Got it!' dialog must appear.")
        gotItButton.tap()

        XCTAssertTrue(daxDismissButton.waitForExistence(timeout: presenceTimeout), "'Try Visiting a Site' dialog must appear.")

        XCTAssertTrue(surpriseMeButton.waitForExistence(timeout: presenceTimeout), "Site chip must appear on 'Try Visiting a Site' dialog.")
        surpriseMeButton.tap()

        XCTAssertTrue(gotItButton.waitForExistence(timeout: presenceTimeout), "Non-DDG browsing dialog must appear.")
        gotItButton.tap()

        XCTAssertTrue(fireButton.waitForExistence(timeout: presenceTimeout), "Fire button must be visible.")
        fireButton.tap()

        XCTAssertTrue(confirmFireButton.waitForExistence(timeout: presenceTimeout), "Fire confirmation button must appear.")
        confirmFireButton.tap()

        XCTAssertTrue(highFiveButton.waitForExistence(timeout: presenceTimeout), "End-of-journey NTP dialog must appear.")
        highFiveButton.tap()

        // contextual subscription promo ("Oh, before I forget...") now showing
    }

    /// Drives the contextual onboarding from the "Try a Search" NTP dialog all the way through
    /// to the "Oh, before I forget..." contextual subscription promo dialog appearing on the NTP.
    ///
    /// Flow: search chip → SERP "Got it!" → "Try Visiting a Site" → navigate to non-DDG site via
    /// address bar → browsing dialog "Got it!" → tap fire button → confirm fire → NTP end-of-journey
    /// "High five!" → contextual subscription promo visible.
    ///
    /// Callers must assert and interact with the subscription promo themselves.
    private func completeContextualOnboardingToSubscriptionPromo() {
        // ── "Try a Search" dialog: tap search chip → navigate to SERP ────────
        XCTAssertTrue(surpriseMeButton.waitForExistence(timeout: presenceTimeout), "'Try a Search' chip must appear.")
        surpriseMeButton.tap()

        // ── "That's DuckDuckGo Search!" browsing dialog → "Got it!" ──────────
        XCTAssertTrue(gotItButton.waitForExistence(timeout: presenceTimeout), "SERP browsing dialog must appear.")
        gotItButton.tap()

        // ── "Try Visiting a Site" dialog appears on NTP — tap site chip ─────────
        XCTAssertTrue(daxDismissButton.waitForExistence(timeout: presenceTimeout), "'Try Visiting a Site' dialog must appear.")

        XCTAssertTrue(surpriseMeButton.waitForExistence(timeout: presenceTimeout), "Site chip must appear on 'Try Visiting a Site' dialog.")
        surpriseMeButton.tap()

        // ── browsing dialog on non-DDG page → "Got it!" ───────────────────────
        XCTAssertTrue(gotItButton.waitForExistence(timeout: presenceTimeout), "Non-DDG browsing dialog must appear.")
        gotItButton.tap()

        // ── tap the fire button (may be pulsing after non-DDG visit) ─────────
        XCTAssertTrue(fireButton.waitForExistence(timeout: presenceTimeout), "Fire button must be visible.")
        fireButton.tap()

        // ── confirm fire ("Delete All" / "alert.forget-data.confirm") ─────────
        XCTAssertTrue(confirmFireButton.waitForExistence(timeout: presenceTimeout), "Fire confirmation button must appear.")
        confirmFireButton.tap()

        // ── NTP end-of-journey dialog → "High five!" ──────────────────────────
        XCTAssertTrue(highFiveButton.waitForExistence(timeout: presenceTimeout), "End-of-journey NTP dialog must appear.")
        highFiveButton.tap()

        // ── contextual subscription promo ("Oh, before I forget...") now showing
    }

    /// Taps through the full new-user linear onboarding (search-only path).
    private func completeNewUserLinearOnboarding() {
        XCTAssertTrue(letsGoButton.waitForExistence(timeout: presenceTimeout), "Onboarding intro must appear.")
        letsGoButton.tap()

        // Browser comparison → Skip
        XCTAssertTrue(skipButton.waitForExistence(timeout: presenceTimeout), "Browser comparison skip must appear.")
        skipButton.tap()

        // Add to Dock promo → Skip
        XCTAssertTrue(skipButton.waitForExistence(timeout: presenceTimeout), "Add-to-Dock skip must appear.")
        skipButton.tap()

        // App icon selection → Next
        XCTAssertTrue(nextButton.waitForExistence(timeout: presenceTimeout), "App-icon Next must appear.")
        nextButton.tap()

        // Address bar position → Next
        XCTAssertTrue(nextButton.waitForExistence(timeout: presenceTimeout), "Address-bar Next must appear.")
        nextButton.tap()

        // Search experience → select "Search only" then Next
        let searchOnly = app.buttons["Search only"].firstMatch
        XCTAssertTrue(searchOnly.waitForExistence(timeout: presenceTimeout), "Search-only option must appear.")
        searchOnly.tap()

        XCTAssertTrue(nextButton.waitForExistence(timeout: presenceTimeout), "Search-experience Next must appear.")
        nextButton.tap()
    }
}
