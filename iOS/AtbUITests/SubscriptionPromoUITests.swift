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

import XCTest

/// UI tests for the day-7 subscription promo sheet.
///
/// ## Reset mechanic
/// The Xcode scheme's Test → Pre-Actions script runs
/// `xcrun simctl uninstall booted "$PRODUCT_BUNDLE_IDENTIFIER"` before each run, ensuring a
/// fully clean app container. As a belt-and-suspenders fallback, `-clearAllDefaults` wipes
/// all UserDefaults domains at startup. The `-backdateInstallDate` launch argument then sets
/// the statistics install date to 7 days ago so the promo cooldown is already satisfied.
final class SubscriptionPromoUITests: XCTestCase {

    private let app = XCUIApplication()

    private let presenceTimeout: TimeInterval = 20
    private let absenceTimeout: TimeInterval = 5

    // MARK: - Class-level element queries

    private lazy var promoSheet: XCUIElement = app.descendants(matching: .any).matching(identifier: "subscriptionPromoSheet").firstMatch
    private lazy var noThanksButton: XCUIElement = app.buttons["No thanks"]
    private lazy var daxDismissButton: XCUIElement = app.buttons["onboardingDialogDismissButton"].firstMatch

    // MARK: - Setup

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }

    // MARK: - Tests

    /// Reinstaller / skipped-onboarding path (`subscriptionPromoForReinstallers`).
    ///
    /// Uses the returning-user variant (`VARIANT=ru`) which reduces onboarding to two taps:
    /// "I've been here before" → "Start Browsing". The promo fires on the first foreground event
    /// after the onboarding modal is dismissed.
    func testPromoSheetAppearsOnceAfterOnboarding() {
        configureReinstaller()
        app.launch()

        // ── Step 1: skip the linear onboarding ──────────────────────────────────
        let skipButton = app.buttons["I\u{2019}ve been here before"]
        XCTAssertTrue(skipButton.waitForExistence(timeout: presenceTimeout), "Onboarding intro must appear.")
        skipButton.tap()

        let startBrowsingButton = app.buttons["Start Browsing"]
        XCTAssertTrue(startBrowsingButton.waitForExistence(timeout: presenceTimeout), "Skip confirmation must appear.")
        startBrowsingButton.tap()

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

        XCTAssertTrue(
            promoSheet.waitForNonExistence(timeout: absenceTimeout),
            "Promo sheet must not reappear after it has been dismissed."
        )
    }

    /// Existing-user / 7-day promo path (`subscriptionPromoForExistingUsers`), search-only variant.
    ///
    /// Taps through the full new-user linear onboarding (contextual dax dialogs suppressed by
    /// default — `isDismissed` stays true because `primeForUse()` is never called when ATB keys
    /// are present), then verifies the promo sheet appears on the next foreground event and does
    /// not reappear after dismissal.
    func testExistingUserPromoSheetAppearsAfterOnboarding() {
        configureExistingUser()
        app.launch()

        completeNewUserLinearOnboarding()

        // ── background → foreground triggers presentModalPromptIfNeeded ──────────
        XCUIDevice.shared.press(.home)
        app.activate()

        // ── promo sheet must appear ───────────────────────────────────────────────
        XCTAssertTrue(
            promoSheet.waitForExistence(timeout: presenceTimeout),
            "Subscription promo sheet must appear on first foreground after onboarding."
        )

        // ── dismiss and verify it goes away ──────────────────────────────────────
        XCTAssertTrue(noThanksButton.exists, "'No thanks' button must be visible.")
        noThanksButton.tap()

        XCTAssertTrue(
            promoSheet.waitForNonExistence(timeout: absenceTimeout),
            "Promo sheet must disappear after dismissal."
        )

        // ── background → foreground again — sheet must NOT reappear ──────────────
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertTrue(
            promoSheet.waitForNonExistence(timeout: absenceTimeout),
            "Promo sheet must not reappear after it has been dismissed."
        )
    }

    /// Existing-user / 7-day promo path with contextual dax dialogs enabled.
    ///
    /// Uses `-setDaxNotDismissed` to set `isDismissed = false` at launch so the "Try a Search"
    /// dax dialog surfaces after the linear onboarding completes. Verifies the promo sheet
    /// appears after the dialog is dismissed and does not reappear after its own dismissal.
    func testExistingUserPromoSheetAfterDismissingTrySearchDialog() {
        configureExistingUserWithDax()
        app.launch()

        completeNewUserLinearOnboarding()

        // ── dismiss the "Try a search" contextual dax dialog ─────────────────────
        XCTAssertTrue(daxDismissButton.waitForExistence(timeout: presenceTimeout), "Try-a-Search dax dialog dismiss button must appear.")
        daxDismissButton.tap()

        // ── background → foreground — promo must NOT appear yet ─────────────────
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(promoSheet.waitForExistence(timeout: absenceTimeout),
                       "Promo sheet must not appear before the browsing dax dialog is dismissed.")

        // ── make a search while the address bar is active ────────────────────────
        app.typeText("privacy\n")

        // ── "That's a DuckDuckGo search" browsing dax dialog must appear ─────────
        XCTAssertTrue(daxDismissButton.waitForExistence(timeout: presenceTimeout),
                      "'That's a DuckDuckGo search' dax dialog must appear.")

        // ── hide/show — promo must NOT appear while dax dialog is on screen ──────
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(promoSheet.waitForExistence(timeout: absenceTimeout),
                       "Promo sheet must not appear while the dax browsing dialog is visible.")

        // ── dismiss the browsing dax dialog ──────────────────────────────────────
        daxDismissButton.tap()

        // ── hide/show — promo must now appear ────────────────────────────────────
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertTrue(
            promoSheet.waitForExistence(timeout: presenceTimeout),
            "Subscription promo sheet must appear after dismissing the dax browsing dialog."
        )

        // ── dismiss and verify it goes away ──────────────────────────────────────
        XCTAssertTrue(noThanksButton.exists, "'No thanks' button must be visible.")
        noThanksButton.tap()

        XCTAssertTrue(
            promoSheet.waitForNonExistence(timeout: absenceTimeout),
            "Promo sheet must disappear after dismissal."
        )

        // ── hide/show again — sheet must NOT reappear ─────────────────────────────
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertFalse(
            promoSheet.waitForExistence(timeout: absenceTimeout),
            "Promo sheet must not reappear after it has been dismissed."
        )
    }

    // MARK: - Helpers

    /// Configures for `SubscriptionPromoCoordinator` (reinstaller / skipped-onboarding path).
    private func configureReinstaller() {
        app.launchArguments = [
            "-clearAllDefaults",
            "-backdateInstallDate",
            "-ff.subscriptionPromoForReinstallers", "true",
            "-ff.privacyProOnboardingPromotion", "true",
            "isRunningUITests",
        ]
        app.launchEnvironment = [
            "UITEST_MODE": "1",
            "VARIANT": "ru",   // returning-user path: sets onboarding flow + persisted to statisticsStore.variant
        ]
    }

    /// Configures for `SubscriptionPromoExistingUserCoordinator` (new-user / 7-day cooldown path).
    /// Contextual dax dialogs remain suppressed (`isDismissed` stays true).
    private func configureExistingUser() {
        app.launchArguments = [
            "-clearAllDefaults",
            "-backdateInstallDate",
            "-ff.subscriptionPromoForExistingUsers", "true",
            "-ff.privacyProOnboardingPromotion", "true",
            "isRunningUITests",
        ]
        app.launchEnvironment = [
            "UITEST_MODE": "1",
            // No VARIANT override → new-user linear onboarding
        ]
    }

    /// Same as `configureExistingUser` but also passes `-setDaxNotDismissed` so the "Try a
    /// Search" contextual dax dialog surfaces after the linear onboarding completes.
    private func configureExistingUserWithDax() {
        app.launchArguments = [
            "-clearAllDefaults",
            "-backdateInstallDate",
            "-setDaxNotDismissed",
            "-ff.subscriptionPromoForExistingUsers", "true",
            "-ff.privacyProOnboardingPromotion", "true",
            "isRunningUITests",
        ]
        app.launchEnvironment = [
            "UITEST_MODE": "1",
        ]
    }

    /// Taps through the full new-user linear onboarding (search-only path).
    private func completeNewUserLinearOnboarding() {
        let letsGoButton = app.buttons["Let\u{2019}s get started!"]
        XCTAssertTrue(letsGoButton.waitForExistence(timeout: presenceTimeout), "Onboarding intro must appear.")
        letsGoButton.tap()

        // Browser comparison → Skip
        let skipBrowserComparison = app.buttons["Skip"].firstMatch
        XCTAssertTrue(skipBrowserComparison.waitForExistence(timeout: presenceTimeout), "Browser comparison skip must appear.")
        skipBrowserComparison.tap()

        // Add to Dock promo → Skip
        let skipAddToDock = app.buttons["Skip"].firstMatch
        XCTAssertTrue(skipAddToDock.waitForExistence(timeout: presenceTimeout), "Add-to-Dock skip must appear.")
        skipAddToDock.tap()

        // App icon selection → Next
        let nextAfterIcon = app.buttons["Next"].firstMatch
        XCTAssertTrue(nextAfterIcon.waitForExistence(timeout: presenceTimeout), "App-icon Next must appear.")
        nextAfterIcon.tap()

        // Address bar position → Next
        let nextAfterBar = app.buttons["Next"].firstMatch
        XCTAssertTrue(nextAfterBar.waitForExistence(timeout: presenceTimeout), "Address-bar Next must appear.")
        nextAfterBar.tap()

        // Search experience → select "Search only" then Next
        let searchOnly = app.buttons["Search only"].firstMatch
        XCTAssertTrue(searchOnly.waitForExistence(timeout: presenceTimeout), "Search-only option must appear.")
        searchOnly.tap()

        let nextAfterSearch = app.buttons["Next"].firstMatch
        XCTAssertTrue(nextAfterSearch.waitForExistence(timeout: presenceTimeout), "Search-experience Next must appear.")
        nextAfterSearch.tap()
    }
}
