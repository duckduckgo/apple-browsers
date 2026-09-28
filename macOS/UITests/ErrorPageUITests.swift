//
//  ErrorPageUITests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import Foundation
import SharedTestUtilities
import Utilities
import XCTest

class ErrorPageUITests: UITestCase {

    private var addressBarTextField: XCUIElement { app.addressBar }
    private var webView: XCUIElement!

    override func setUpWithError() throws {
        try super.setUpWithError()
        app = XCUIApplication.setUp(featureFlags: ["debugURLScheme": true])
        app.enforceSingleWindow()
        webView = app.webViews.firstMatch
        removePinnedTabsForTestCleanup()

        app.enforceSingleWindow()
        // wait for the New Tab page to load
        XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
    }

    override func tearDown() {
        webView = nil
        app = nil
        super.tearDown()
    }

    // MARK: - Unreachable host

    /// Invalid TLD → host-not-found error UI, tab title, navigation chrome, Save As disabled, address bar shows failing URL (uses real DNS).
    func testErrorPage_UnreachableHost_ShowsErrorMessage() throws {
        let invalidURL = URL(string: "https://thisdomaindoesnotexist.invalidtld")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(invalidURL, pressingEnter: true)

        assertUnreachableHostErrorPageVisible()
        assertSelectedTabTitleEquals(Self.tabErrorTitle)
        assertNavigationChromeMatchesHostNotFoundCase()
        assertSaveAsMenuItemEnabled(false)

        XCTAssertEqual(app.addressBarValueActivatingIfNeeded(), "https://thisdomaindoesnotexist.invalidtld/")

        // Same back stack shape as `testWhenPageFailsToLoad_errorPageShown` (`backHistoryItems.count == 1`, prior entry is new tab).
        XCTAssertEqual(
            navigationHistoryMenuTitlesFromRightClicking(app.backButton),
            [Self.backForwardMenuLabel(forCommittedURL: invalidURL), "New Tab"],
            "Back menu should list the error row then the new-tab history entry"
        )
    }

    /// Same back-stack shape as `testWhenPageFailsToLoad_errorPageShown`: new tab → unreachable host error → Back returns to the new tab surface (not the error page).
    func testErrorPage_FromNewTab_UnreachableHost_BackReturnsToNewTabSurface() throws {
        let invalidURL = URL(string: "https://error-page-newtab-back.invalid/")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(invalidURL, pressingEnter: true)
        assertUnreachableHostErrorPageVisible()
        XCTAssertTrue(app.backButton.isEnabled, "Host-not-found error should keep Back enabled toward the prior new tab entry")

        app.backButton.click()
        XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence), "Back should restore the new tab page")
        let errorHeader = webView.staticTexts.containing(\.value, containing: Self.errorPageHeader).firstMatch
        XCTAssertFalse(errorHeader.exists, "Error page should be dismissed after Back to the new tab history entry")
    }

    // MARK: - Redirect then fail

    /// HTTP redirect from the local test server to an unreachable host; final load fails with host-not-found error UI.
    func testErrorPage_RedirectFromTestServer_ToUnreachableHost_ShowsErrorPage() throws {
        let finalURLString = "https://redirect-final.invalid/error-path"
        let redirectURL = URL.testsServer.appendingTestParameters(
            status: 302,
            reason: "Found",
            data: Data(),
            headers: ["Location": finalURLString]
        )

        app.activateAddressBar()
        addressBarTextField.pasteURL(redirectURL, pressingEnter: true)

        assertUnreachableHostErrorPageVisible()
        assertSelectedTabTitleEquals(Self.tabErrorTitle)
        assertNavigationChromeMatchesHostNotFoundCase()
        assertSaveAsMenuItemEnabled(false)

        let finalFailedURL = URL(string: finalURLString)!
        XCTAssertEqual(
            navigationHistoryMenuTitlesFromRightClicking(app.backButton),
            [Self.backForwardMenuLabel(forCommittedURL: finalFailedURL), "New Tab"],
            "Redirect→fail should keep a single prior back entry (new tab), matching the single-step back stack"
        )

        // Final failed URL may be normalized; assert host substring only.
        let address = app.addressBarValueActivatingIfNeeded() ?? ""
        XCTAssertTrue(
            address.contains("redirect-final.invalid"),
            "Address bar should reflect the failed navigation target after redirect, got: \(address)"
        )
    }

    // MARK: - Tab switch: host-not-found should not auto-recover

    /// After host-not-found on tab A, load a real site on tab B, then select tab A again — error UI must remain (no silent recovery).
    func testErrorPage_SecondTab_SwitchBackToUnreachableHost_DoesNotClearError() throws {
        // Tab A: host-not-found error.
        let unreachableURL = URL(string: "https://tab-switch-no-autoreload.invalid/")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(unreachableURL, pressingEnter: true)
        assertUnreachableHostErrorPageVisible()

        // Tab B: successful load so tab strip has mixed success/error.
        app.openNewTab()
        let privacyTestPagesContent = webView.staticTexts.containing(\.value, containing: Self.privacyTestPagesHomeBodyText).firstMatch
        app.activateAddressBar()
        addressBarTextField.pasteURL(Self.privacyTestPagesHomeURL, pressingEnter: true)
        XCTAssertTrue(privacyTestPagesContent.waitForExistence(timeout: UITests.Timeouts.navigation), "Second tab should load privacy-test-pages.site")

        // Re-select tab A: host-not-found error should still be shown (connection-style failures can behave differently).
        selectUnpinnedTab(at: 0)

        assertUnreachableHostErrorPageVisible()
        assertSelectedTabTitleEquals(Self.tabErrorTitle)
        assertSaveAsMenuItemEnabled(false)
        XCTAssertEqual(app.addressBarValueActivatingIfNeeded(), "https://tab-switch-no-autoreload.invalid/")

        assertNavigationChromeMatchesHostNotFoundCase()
        XCTAssertEqual(
            navigationHistoryMenuTitlesFromRightClicking(app.backButton),
            [Self.backForwardMenuLabel(forCommittedURL: unreachableURL), "New Tab"],
            "Host-not-found after tab reselect should keep the same back list as a fresh error navigation"
        )
    }

    /// Aligned with `testWhenTabWithNoConnectionErrorActivated_reloadTriggered`: transient `debug://failure` error, other tab loads, simulate off, re-selecting tab 0 reloads successfully into demo HTML.
    func testErrorPage_NoConnectionStyle_TabSwitch_ReactivationLoadsSuccess_WithFailureScheme() throws {
        app.closeAllWindows()

        // Tab 1: Debug simulate ON, open debug://failure → connection-style error (not real network).
        ensureSimulateFailureURLSchemeOn()
        openFailureURLSchemeDemoViaDebugMenu()
        assertGenericErrorPageVisible()
        assertFailureSchemeSimulatedConnectionErrorDescriptionVisible()

        // Tab 2: load a real page from the tests server so we can switch away and back.
        app.openNewTab()
        let servedTitle = "Error Page NoConn Recovery"
        let recoveryURL = UITests.simpleServedPage(titled: servedTitle)
        app.activateAddressBar()
        addressBarTextField.pasteURL(recoveryURL, pressingEnter: true)
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: servedTitle).firstMatch
                .waitForExistence(timeout: UITests.Timeouts.localTestServer),
            "Second tab should load from the tests server"
        )

        // Turning simulate OFF before re-selecting tab 0 lets reactivation reload into the handler’s demo HTML.
        ensureSimulateFailureURLSchemeOff()
        selectUnpinnedTab(at: 0)
        assertFailureSchemeDemoPageBodyVisible()

        // `testWhenTabWithNoConnectionErrorActivated_reloadTriggered`: recovered tab has no forward stack; back is disabled
        // because debug://failure was the first navigation in this window (no prior New Tab entry committed).
        XCTAssertTrue(app.forwardButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertFalse(app.forwardButton.isEnabled, "After recovery, tab should not expose forward history")
        XCTAssertFalse(app.backButton.isEnabled, "debug://failure was the first navigation — no prior page to go back to")
    }

    /// Aligned with `testWhenTabWithConnectionLostErrorActivatedAndReloadFailsAgain_errorPageIsUpdated`: first simulated `debug://failure` failure, another tab, return — second handler invocation surfaces **different** connection-style copy (alternating simulated URLError descriptions on the error page).
    func testErrorPage_FailureScheme_TabSwitch_SecondSimulatedErrorUpdatesDescription() throws {
        app.closeAllWindows()

        // Reset then enable simulate so alternating failure passes start from a known state.
        ensureSimulateFailureURLSchemeOff()
        ensureSimulateFailureURLSchemeOn()

        // First load: alternatingFailures URL → first simulated URLError + attempt 1.
        openFailureURLSchemeAlternatingFailuresViaDebugMenu()
        assertGenericErrorPageVisible()
        assertFailureSchemeSimulatedConnectionErrorDescriptionVisible()

        // Second tab: real page so tab 0’s web view is deactivated (reactivation will run the load again).
        app.openNewTab()
        let privacyTestPagesContent = webView.staticTexts.containing(\.value, containing: Self.privacyTestPagesHomeBodyText).firstMatch
        app.activateAddressBar()
        addressBarTextField.pasteURL(Self.privacyTestPagesHomeURL, pressingEnter: true)
        XCTAssertTrue(privacyTestPagesContent.waitForExistence(timeout: UITests.Timeouts.navigation), "Second tab should load privacy-test-pages.site")

        // Back to tab 0: second handler pass should show the other connection-style line and bump the attempt counter.
        selectUnpinnedTab(at: 0)
        assertGenericErrorPageVisible()
        let alternateDescription = webView.staticTexts.containing(\.value, containing: Self.failureSchemeSimulatedNotConnectedDescription).firstMatch
        XCTAssertTrue(
            alternateDescription.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Reactivation should show the second simulated URLError description"
        )
        let firstDescription = webView.staticTexts.containing(\.value, containing: Self.failureSchemeSimulatedConnectionLostDescription).firstMatch
        XCTAssertFalse(
            firstDescription.exists,
            "Error surface should update away from the first simulated failure description"
        )
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: Self.failureSchemeSimulateAttemptSuffix(2)).firstMatch.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Second handler pass should surface attempt 2 in the error copy (visible reload counter)"
        )

        // No further automatic load should advance to attempt 3 (`testWhenTabWithConnectionLostErrorActivatedAndReloadFailsAgain…`).
        let attempt3Label = webView.staticTexts.containing(\.value, containing: Self.failureSchemeSimulateAttemptSuffix(3)).firstMatch
        XCTAssertFalse(attempt3Label.waitForExistence(timeout: 0.6), "Attempt 3 should not appear from an extra simulated load after reactivation")
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: Self.failureSchemeSimulateAttemptSuffix(2)).firstMatch.exists,
            "Error copy should remain on the second attempt"
        )

        assertNavigationChromeMatchesTransientConnectionErrorNoBackCase()
    }

    /// `debug://failure?simulatedError=notConnected` with simulate on always uses `URLError.notConnectedToInternet` (literal code path), not only when `alternatingFailures` is enabled.
    func testErrorPage_FailureScheme_SimulatedErrorQuery_NotConnected_UsesNotConnectedToInternet() throws {
        app.closeAllWindows()

        ensureSimulateFailureURLSchemeOff()
        ensureSimulateFailureURLSchemeOn()

        openFailureURLSchemeNotConnectedQueryViaDebugMenu()
        assertGenericErrorPageVisible()
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: Self.failureSchemeSimulatedNotConnectedDescription).firstMatch
                .waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Query should force not-connected copy on every load"
        )
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: Self.failureSchemeSimulateAttemptSuffix(1)).firstMatch.exists,
            "First load should report attempt 1 from the scheme handler"
        )
        XCTAssertFalse(
            webView.staticTexts.containing(\.value, containing: Self.failureSchemeSimulateAttemptSuffix(2)).firstMatch.exists,
            "Single navigation should not advance to attempt 2"
        )
        assertNavigationChromeMatchesTransientConnectionErrorNoBackCase()
    }

    // MARK: - Connection-style tab switch

    /// Connection-refused URL, second tab loads successfully, revisit failing tab — still on error; other tab stays intact.
    func testErrorPage_TabSwitch_AfterConnectionRefused_ReactivationDoesNotBreakOtherTab() throws {
        let refusedURL = URL(string: "http://127.0.0.1:13311/retry-loaded-page")!

        app.activateAddressBar()
        addressBarTextField.pasteURL(refusedURL, pressingEnter: true)
        assertGenericErrorPageVisible()
        assertSelectedTabTitleEquals(Self.tabErrorTitle)

        // Second tab loads from local test server.
        app.openNewTab()
        let recoveryPageTitle = "Recovery After Refused Page"
        let recoveryURL = UITests.simpleServedPage(titled: recoveryPageTitle)
        app.activateAddressBar()
        addressBarTextField.pasteURL(recoveryURL, pressingEnter: true)
        let recoveryContent = webView.staticTexts.containing(\.value, containing: recoveryPageTitle).firstMatch
        XCTAssertTrue(recoveryContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Second tab should load from tests server")

        // Back to error tab: still broken, browser usable.
        selectUnpinnedTab(at: 0)

        assertGenericErrorPageVisible()
        XCTAssertTrue(
            app.addressBarValueActivatingIfNeeded()?.contains("127.0.0.1") == true,
            "Address bar should still show the failing URL"
        )

        // Recovery tab unchanged after visiting failing tab again.
        selectUnpinnedTab(at: 1)
        XCTAssertTrue(recoveryContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Other tab content should still be intact")
    }

    // MARK: - debug://failure (Tab ErrorPageTests scenarios; no tests-server gating)

    /// Aligned with `testWhenGoingBackToFailingPage_reloadIsTriggered`: served A; `debug://failure` with simulate on fails; Back; simulate off; Forward shows demo HTML.
    func testErrorPage_FailureScheme_AfterDisablingSimulate_BackThenForward_LoadsDemo() throws {
        let aTitle = "FailureScheme Back Forward Page A"
        let pageA = UITests.simpleServedPage(titled: aTitle)

        app.activateAddressBar()
        addressBarTextField.pasteURL(pageA, pressingEnter: true)
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: aTitle).firstMatch
                .waitForExistence(timeout: UITests.Timeouts.localTestServer)
        )

        ensureSimulateFailureURLSchemeOn()
        openFailureURLSchemeDemoViaDebugMenu()
        assertGenericErrorPageVisible()
        assertFailureSchemeSimulatedConnectionErrorDescriptionVisible()

        XCTAssertTrue(app.backButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(app.backButton.isEnabled)
        app.backButton.click()
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: aTitle).firstMatch
                .waitForExistence(timeout: UITests.Timeouts.localTestServer)
        )

        ensureSimulateFailureURLSchemeOff()

        XCTAssertTrue(app.forwardButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(app.forwardButton.isEnabled)
        XCTAssertEqual(
            navigationHistoryMenuTitlesFromRightClicking(app.forwardButton),
            [aTitle, Self.failureSchemeCommittedHostMenuLabel],
            "Forward stack should preserve the failed debug://failure commit ahead of the success page"
        )
        app.forwardButton.click()
        assertFailureSchemeDemoPageBodyVisible()
    }

    /// Aligned with reload-after-recovery: Cmd+R after turning simulate off loads demo HTML for the committed `debug://failure` URL.
    func testErrorPage_FailureScheme_CmdR_AfterDisablingSimulate_LoadsDemo() throws {
        ensureSimulateFailureURLSchemeOn()
        openFailureURLSchemeDemoViaDebugMenu()
        assertGenericErrorPageVisible()

        ensureSimulateFailureURLSchemeOff()
        app.typeKey("r", modifierFlags: [.command])
        assertFailureSchemeDemoPageBodyVisible()
    }

    /// Aligned with `testWhenReloadingBySubmittingSameURL…`: repeated opens of the same `debug://failure` URL stay on error while simulate is on; after off, demo HTML loads.
    func testErrorPage_FailureScheme_ResubmitSameURL_AfterDisablingSimulate_LoadsDemo() throws {
        ensureSimulateFailureURLSchemeOn()
        openFailureURLSchemeAlternatingFailuresViaDebugMenu()
        assertGenericErrorPageVisible()
        assertFailureSchemeSimulatedConnectionErrorDescriptionVisible()

        // Cmd+R re-invokes the URL scheme handler (debug-menu click on the same URL only triggers reload()
        // which reuses the cached simulated response and does not advance the alternating counter).
        app.typeKey("r", modifierFlags: [.command])
        assertGenericErrorPageVisible()
        let notConnectedAfterResubmit = webView.staticTexts.containing(\.value, containing: Self.failureSchemeSimulatedNotConnectedDescription).firstMatch
        XCTAssertTrue(
            notConnectedAfterResubmit.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Second navigation to alternating-failures demo should advance the alternating failure copy"
        )

        // Same committed URL with simulate off loads real demo HTML.
        ensureSimulateFailureURLSchemeOff()
        openFailureURLSchemeDemoViaDebugMenu()
        assertFailureSchemeDemoPageBodyVisible()
    }

    /// Aligned with `testWhenReloadingBySubmittingSameURL_errorPageRemainsSame`: two failing `debug://failure` submits on the same URL; Forward still reaches B.
    ///
    /// Structure: debug://failure?alt error → B → Back (forward: [B]) → Cmd+R (second submit, advances alternating) → Forward reaches B.
    /// The alternating-failures URL is the *first* navigation so that B can be added on top and Back preserves it in forward.
    func testErrorPage_FailureScheme_ResubmitSameURL_Twice_ThenForwardToB() throws {
        let bTitle = "FailureScheme Resubmit Seq B"
        let urlB = UITests.simpleServedPage(titled: bTitle)

        // First submit: alternating-failures URL with simulate on → error (attempt 1, connectionLost).
        ensureSimulateFailureURLSchemeOn()
        openFailureURLSchemeAlternatingFailuresViaDebugMenu()
        assertGenericErrorPageVisible()
        assertFailureSchemeSimulatedConnectionErrorDescriptionVisible()

        // Navigate to B then back so forward holds B.
        app.activateAddressBar()
        addressBarTextField.pasteURL(urlB, pressingEnter: true)
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: bTitle).firstMatch
                .waitForExistence(timeout: UITests.Timeouts.localTestServer)
        )

        app.backButton.click()
        assertGenericErrorPageVisible()

        // Back re-invokes the scheme handler (attempt 2 → not-connected); Cmd+R advances to attempt 3 (connection-lost).
        app.typeKey("r", modifierFlags: [.command])
        assertGenericErrorPageVisible()
        let connectionLostSecondSubmit = webView.staticTexts.containing(\.value, containing: Self.failureSchemeSimulatedConnectionLostDescription).firstMatch
        XCTAssertTrue(
            connectionLostSecondSubmit.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Cmd+R after back (attempt 3) should show the connection-lost simulated description (alternating failure chain)"
        )

        XCTAssertTrue(app.forwardButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(app.forwardButton.isEnabled)
        XCTAssertEqual(
            navigationHistoryMenuTitlesFromRightClicking(app.forwardButton),
            [Self.failureSchemeCommittedHostMenuLabel, bTitle],
            "Forward history should still list page B after two failing navigations on the same failure URL"
        )
        XCTAssertEqual(
            navigationHistoryMenuTitlesFromRightClicking(app.backButton),
            [Self.failureSchemeCommittedHostMenuLabel, "New Tab"],
            "Back list: error row then new tab (debug://failure was opened from the fresh New Tab window)"
        )
        // Forward should still reach B after two failing submits on the failure URL.
        app.forwardButton.click()
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: bTitle).firstMatch
                .waitForExistence(timeout: UITests.Timeouts.localTestServer)
        )
    }

    /// Aligned with forward history after error + recovery: `debug://failure` error → B → Back → simulate off + reload → Forward still reaches B.
    ///
    /// Structure: open new window → debug://failure error → B → Back (forward: [B]) → sim off Cmd+R → demo → Forward still has B.
    /// The debug://failure URL is the first navigation so that navigating to B and coming back keeps B in the forward stack.
    func testErrorPage_HistoryChain_FailureScheme_SimulateOffReload_ShowsDemo_ForwardToB() throws {
        let bTitle = "History FailureScheme Page B"
        let urlB = UITests.simpleServedPage(titled: bTitle)

        // Navigate to debug://failure with simulate on → error.
        ensureSimulateFailureURLSchemeOn()
        openFailureURLSchemeDemoViaDebugMenu()
        assertGenericErrorPageVisible()

        // Navigate to B then back so forward holds B.
        app.activateAddressBar()
        addressBarTextField.pasteURL(urlB, pressingEnter: true)
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: bTitle).firstMatch
                .waitForExistence(timeout: UITests.Timeouts.localTestServer)
        )

        app.backButton.click()
        assertGenericErrorPageVisible()

        // Simulate off + reload should serve demo HTML; B stays in forward history.
        ensureSimulateFailureURLSchemeOff()
        app.typeKey("r", modifierFlags: [.command])
        assertFailureSchemeDemoPageBodyVisible()

        // Menus should list recovered demo with B still ahead; then Forward reaches B.
        XCTAssertTrue(app.forwardButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(app.forwardButton.isEnabled)
        XCTAssertEqual(
            navigationHistoryMenuTitlesFromRightClicking(app.forwardButton),
            [Self.failureSchemeDocumentTitle, bTitle],
            "Recovered demo should have B ahead in forward history"
        )
        XCTAssertEqual(
            navigationHistoryMenuTitlesFromRightClicking(app.backButton),
            [Self.failureSchemeDocumentTitle, "New Tab"],
            "Recovered demo: single prior back entry (New Tab committed before debug://failure navigation)"
        )
        app.forwardButton.click()
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: bTitle).firstMatch
                .waitForExistence(timeout: UITests.Timeouts.localTestServer)
        )
    }

    /// Aligned with `testWhenGoingBackToFailingPageAndItFailsAgain…`: simulated failure, success page, Back still shows connection error; Forward returns to success.
    func testErrorPage_FailureScheme_BackFromSuccessStillShowsError_ForwardStillWorks() throws {
        app.closeAllWindows()

        let okTitle = "FailureScheme Back Success Title"
        let urlOk = UITests.simpleServedPage(titled: okTitle)

        // Start on simulated debug://failure error, then load a real page on top.
        ensureSimulateFailureURLSchemeOn()
        openFailureURLSchemeDemoViaDebugMenu()
        assertGenericErrorPageVisible()

        app.activateAddressBar()
        addressBarTextField.pasteURL(urlOk, pressingEnter: true)
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: okTitle).firstMatch
                .waitForExistence(timeout: UITests.Timeouts.localTestServer)
        )

        // Back should restore the error commit; forward should still reach the success page.
        app.backButton.click()
        assertGenericErrorPageVisible()
        assertFailureSchemeSimulatedConnectionErrorDescriptionVisible()
        XCTAssertFalse(app.backButton.isEnabled) // NewTabPage 
        XCTAssertEqual(
            navigationHistoryMenuTitlesFromRightClicking(app.forwardButton),
            [Self.failureSchemeCommittedHostMenuLabel, okTitle],
            "Error entry should be current with the success page as the sole forward item"
        )

        XCTAssertTrue(app.forwardButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(app.forwardButton.isEnabled)
        app.forwardButton.click()
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: okTitle).firstMatch
                .waitForExistence(timeout: UITests.Timeouts.localTestServer)
        )
    }

    /// Aligned with `testWhenPageLoadedAndFailsOnRefreshAndOnConsequentRefresh…`: two Cmd+R while simulate is on stay on error; Forward reaches B.
    ///
    /// Structure: open new window → debug://failure?alt error → B → Back (forward: [B]) → Cmd+R x2 (alternating copy) → Forward reaches B.
    func testErrorPage_FailureScheme_HistoryBack_ReloadTwice_ForwardToB() throws {
        let bTitle = "FailureScheme Reload Chain B"
        let urlB = UITests.simpleServedPage(titled: bTitle)

        // Navigate to alternating-failures URL with simulate on → error (attempt 1, connectionLost).
        ensureSimulateFailureURLSchemeOn()
        openFailureURLSchemeAlternatingFailuresViaDebugMenu()
        assertGenericErrorPageVisible()

        // Navigate to B then back so forward holds B.
        app.activateAddressBar()
        addressBarTextField.pasteURL(urlB, pressingEnter: true)
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: bTitle).firstMatch
                .waitForExistence(timeout: UITests.Timeouts.localTestServer)
        )

        app.backButton.click()
        assertGenericErrorPageVisible()

        // Back navigation re-invokes the URL scheme handler (attempt 2 → not-connected copy).
        // Two subsequent Cmd+R advance: attempt 3 → connection-lost, attempt 4 → not-connected.
        let connectionLostLine = webView.staticTexts.containing(\.value, containing: Self.failureSchemeSimulatedConnectionLostDescription).firstMatch
        let notConnectedLine = webView.staticTexts.containing(\.value, containing: Self.failureSchemeSimulatedNotConnectedDescription).firstMatch
        XCTAssertTrue(
            notConnectedLine.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Back re-invokes the scheme handler (attempt 2) → not-connected copy should be visible"
        )
        XCTAssertFalse(connectionLostLine.exists, "Back (attempt 2) should not show connection-lost copy")

        // First reload: connection-lost (attempt 3).
        app.typeKey("r", modifierFlags: [.command])
        XCTAssertTrue(
            connectionLostLine.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "First reload (attempt 3) should surface the alternating connection-lost copy"
        )
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: Self.errorPageHeader).firstMatch.exists,
            "Error page header should stay visible after first reload"
        )
        XCTAssertFalse(notConnectedLine.exists, "First reload (attempt 3) should move off the not-connected line of copy")

        // Second reload: back to not-connected (attempt 4).
        app.typeKey("r", modifierFlags: [.command])
        XCTAssertTrue(
            notConnectedLine.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Second reload (attempt 4) should return to the not-connected line of copy"
        )
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: Self.errorPageHeader).firstMatch.exists,
            "Error page header should stay visible after second reload"
        )
        XCTAssertFalse(connectionLostLine.exists, "Second reload (attempt 4) should move off the connection-lost line of copy")

        assertNavigationChromeMatchesErrorWithBackAndForwardCase()

        XCTAssertEqual(
            navigationHistoryMenuTitlesFromRightClicking(app.backButton),
            [Self.failureSchemeCommittedHostMenuLabel, "New Tab"],
            "Back list: error row then New Tab (debug://failure was opened from the fresh New Tab window, no prior demo)"
        )
        XCTAssertEqual(
            navigationHistoryMenuTitlesFromRightClicking(app.forwardButton),
            [Self.failureSchemeCommittedHostMenuLabel, bTitle],
            "Forward should still reach page B after two failed reloads"
        )

        // Forward menu read above requires an enabled control; no second wait before click.
        XCTAssertTrue(app.forwardButton.isEnabled)
        app.forwardButton.click()
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: bTitle).firstMatch
                .waitForExistence(timeout: UITests.Timeouts.localTestServer)
        )
    }

    /// Aligned with `testWhenPageLoadedAndFailsOnRefreshAndSucceedsOnConsequentRefresh…`: reload fails with simulate on; simulate off + reload restores demo; Forward to B.
    ///
    /// Structure: open new window → debug://failure?alt error → B → Back (forward: [B]) → sim off Cmd+R → demo → Forward reaches B.
    func testErrorPage_FailureScheme_HistoryBack_ReloadFailThenSimulateOff_ReloadSuccess_ForwardToB() throws {
        let bTitle = "FailureScheme Reload Recover B"
        let urlB = UITests.simpleServedPage(titled: bTitle)

        // Navigate to alternating-failures URL with simulate on → error (attempt 1, connectionLost).
        ensureSimulateFailureURLSchemeOn()
        openFailureURLSchemeAlternatingFailuresViaDebugMenu()
        assertGenericErrorPageVisible()
        assertFailureSchemeSimulatedConnectionErrorDescriptionVisible()

        // Navigate to B then back so forward holds B.
        app.activateAddressBar()
        addressBarTextField.pasteURL(urlB, pressingEnter: true)
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: bTitle).firstMatch
                .waitForExistence(timeout: UITests.Timeouts.localTestServer)
        )

        app.backButton.click()
        assertGenericErrorPageVisible()

        // Simulate off + reload succeeds; B stays in forward history.
        ensureSimulateFailureURLSchemeOff()
        app.typeKey("r", modifierFlags: [.command])
        assertFailureSchemeDemoPageBodyVisible()

        XCTAssertEqual(
            navigationHistoryMenuTitlesFromRightClicking(app.forwardButton),
            [Self.failureSchemeDocumentTitle, bTitle],
            "Recovered demo should keep B ahead in forward history"
        )
        XCTAssertEqual(
            navigationHistoryMenuTitlesFromRightClicking(app.backButton),
            [Self.failureSchemeDocumentTitle, "New Tab"],
            "Back from recovered demo: New Tab committed before debug://failure navigation"
        )
        app.forwardButton.click()
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: bTitle).firstMatch
                .waitForExistence(timeout: UITests.Timeouts.localTestServer)
        )
    }

    /// Aligned with `testWhenGoingToAnotherUrlFails_newBackForwardHistoryItemIsAdded`: after `debug://failure` error, a second failing URL clears forward.
    func testErrorPage_FailureScheme_AfterFailure_SecondRefusedURL_DisablesForward() throws {
        let aTitle = "FailureScheme Another Fail A"
        let bTitle = "FailureScheme Another Fail B"
        let urlA = UITests.simpleServedPage(titled: aTitle)
        let urlB = UITests.simpleServedPage(titled: bTitle)
        let urlRefused = URL(string: "http://127.0.0.1:13312/failure-scheme-chain")!

        // Served A → B, Back to A, then stack debug://failure error and a second refused URL (forward cleared).
        app.activateAddressBar()
        addressBarTextField.pasteURL(urlA, pressingEnter: true)
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: aTitle).firstMatch
                .waitForExistence(timeout: UITests.Timeouts.localTestServer)
        )

        app.activateAddressBar()
        addressBarTextField.pasteURL(urlB, pressingEnter: true)
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: bTitle).firstMatch
                .waitForExistence(timeout: UITests.Timeouts.localTestServer)
        )

        app.backButton.click()
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: aTitle).firstMatch
                .waitForExistence(timeout: UITests.Timeouts.localTestServer)
        )

        ensureSimulateFailureURLSchemeOn()
        openFailureURLSchemeDemoViaDebugMenu()
        assertGenericErrorPageVisible()

        app.activateAddressBar()
        addressBarTextField.pasteURL(urlRefused, pressingEnter: true)
        assertGenericErrorPageVisible()

        XCTAssertTrue(app.forwardButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertFalse(app.forwardButton.isEnabled)
        XCTAssertTrue(app.backButton.isEnabled)

        XCTAssertEqual(
            navigationHistoryMenuTitlesFromRightClicking(app.backButton),
            [
                Self.backForwardMenuLabel(forCommittedURL: urlRefused),
                Self.failureSchemeCommittedHostMenuLabel,
                aTitle,
                "New Tab"
            ],
            "Current refused error, prior `debug://failure` error, then served page A and home (`BackForwardListItemViewModel` titles)"
        )
    }

    /// Aligned with `testWhenGoingToAnotherUrlSucceeds…`: after `debug://failure` error, a served page loads; forward remains disabled.
    func testErrorPage_FailureScheme_AfterFailure_SecondServedURL_ForwardStillDisabled() throws {
        let aTitle = "FailureScheme Another Ok A"
        let bTitle = "FailureScheme Another Ok B"
        let dTitle = "FailureScheme Another Ok D"
        let urlA = UITests.simpleServedPage(titled: aTitle)
        let urlB = UITests.simpleServedPage(titled: bTitle)
        let urlD = UITests.simpleServedPage(titled: dTitle)

        // Same A → B → Back, then debug://failure with simulate on; simulate off and navigate to D (forward still off).
        app.activateAddressBar()
        addressBarTextField.pasteURL(urlA, pressingEnter: true)
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: aTitle).firstMatch
                .waitForExistence(timeout: UITests.Timeouts.localTestServer)
        )

        app.activateAddressBar()
        addressBarTextField.pasteURL(urlB, pressingEnter: true)
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: bTitle).firstMatch
                .waitForExistence(timeout: UITests.Timeouts.localTestServer)
        )

        app.backButton.click()
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: aTitle).firstMatch
                .waitForExistence(timeout: UITests.Timeouts.localTestServer)
        )

        ensureSimulateFailureURLSchemeOn()
        openFailureURLSchemeDemoViaDebugMenu()
        assertGenericErrorPageVisible()

        ensureSimulateFailureURLSchemeOff()
        app.activateAddressBar()
        addressBarTextField.pasteURL(urlD, pressingEnter: true)
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: dTitle).firstMatch
                .waitForExistence(timeout: UITests.Timeouts.localTestServer)
        )

        XCTAssertTrue(app.forwardButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertFalse(app.forwardButton.isEnabled)
        XCTAssertTrue(app.backButton.isEnabled)

        XCTAssertEqual(
            navigationHistoryMenuTitlesFromRightClicking(app.backButton),
            [dTitle, Self.failureSchemeCommittedHostMenuLabel, aTitle, "New Tab"],
            "Served page D after `debug://failure` error: back through error row, page A, then home"
        )
    }

    // MARK: - Try again / reload

    /// Cmd+R on an unreachable-host error page should keep showing the error page and leave the same URL in the address bar
    /// (user-visible reload of a failing navigation).
    func testErrorPage_TryAgainButton_ReloadsPage() throws {
        let unreachableURL = URL(string: "https://nonexistent.example.invalid")!
        // Initial navigation fails → error page.
        app.activateAddressBar()
        addressBarTextField.pasteURL(unreachableURL, pressingEnter: true)

        // Wait for error page chrome + copy.
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: Self.errorPageHeader).firstMatch
                .waitForExistence(timeout: UITests.Timeouts.navigation),
            "Error page should appear for unreachable URL"
        )

        // Cmd+R reloads failing navigation; should remain on error with same URL.
        app.typeKey("r", modifierFlags: [.command])

        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: Self.errorPageHeader).firstMatch
                .waitForExistence(timeout: UITests.Timeouts.localTestServer),
            "Error page should appear again after reload"
        )

        XCTAssertEqual(app.addressBarValueActivatingIfNeeded(), "https://nonexistent.example.invalid/", "Address bar should keep failing URL after reload")
    }

    /// Builds history: served test page, then an unreachable URL. Back from the error page returns to the served page and
    /// address bar shows that page’s URL (back stack preserved across error).
    func testErrorPage_BackNavigation_WorksCorrectly() throws {
        // Build history: success page first.
        let workingURL = UITests.simpleServedPage(titled: "Working Test Page")
        app.activateAddressBar()
        addressBarTextField.pasteURL(workingURL, pressingEnter: true)

        let workingContent = webView.staticTexts.containing(\.value, containing: "Working Test Page").firstMatch
        XCTAssertTrue(workingContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Working page should load first")

        // Then failing navigation; back should restore working page.
        let errorURL = URL(string: "https://failingdomain.invalid")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(errorURL, pressingEnter: true)

        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: Self.errorPageHeader).firstMatch
                .waitForExistence(timeout: UITests.Timeouts.navigation),
            "Error page should appear for failing domain"
        )

        XCTAssertTrue(app.backButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Back button should be available")
        XCTAssertTrue(app.backButton.isEnabled, "Back button should be enabled after error")
        app.backButton.click()

        XCTAssertTrue(workingContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Should navigate back to working page from error page")

        let addressBarValue = app.addressBarValueActivatingIfNeeded() ?? ""
        XCTAssertEqual(addressBarValue, workingURL.absoluteString, "Should be back on working local page")
    }

    // MARK: - Connection recovery

    /// From a generic error page, navigates to a reachable site; verifies normal load and address bar. Covers “recover by
    /// entering a good URL” without relying on scheme middleware.
    func testErrorPage_NavigateToValidURL_AfterError_LoadsSuccessfully() throws {
        let networkErrorURL = URL(string: "https://temporaryerror.invalid")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(networkErrorURL, pressingEnter: true)

        // Error state first.
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: Self.errorPageHeader).firstMatch
                .waitForExistence(timeout: UITests.Timeouts.navigation),
            "Error page should appear for temporary error"
        )

        // User navigates to a reachable site from the address bar.
        let recoveredURL = Self.privacyTestPagesHomeURL
        app.activateAddressBar()
        addressBarTextField.pasteURL(recoveredURL, pressingEnter: true)

        let recoveredContent = webView.staticTexts.containing(\.value, containing: Self.privacyTestPagesHomeBodyText).firstMatch
        XCTAssertTrue(recoveredContent.waitForExistence(timeout: UITests.Timeouts.navigation), "Should load successfully after navigating to a valid URL")

        XCTAssertEqual(app.addressBarValueActivatingIfNeeded(), Self.privacyTestPagesHomeAddressBarValue, "Should successfully navigate to privacy-test-pages.site")
    }

    // MARK: - Reload failing page

    /// Reload (Cmd+R) on a stable failing URL keeps the user on the error page with the same URL. Does not assert updated
    /// NSError strings; see `testErrorPage_SecondFailure_UpdatesErrorDescription` for a different error kind on second navigation.
    func testErrorPage_ReloadFailingPage_ShowsUpdatedError() throws {
        let failingURL = URL(string: "https://reloaderror.invalid")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(failingURL, pressingEnter: true)

        // Initial load fails.
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: Self.errorPageHeader).firstMatch
                .waitForExistence(timeout: UITests.Timeouts.navigation),
            "Error page should appear for reload error test"
        )

        XCTAssertEqual(app.addressBarValueActivatingIfNeeded(), "https://reloaderror.invalid/", "Should show initial failing URL in address bar")

        // Second load attempt (reload) still fails; URL unchanged.
        app.typeKey("r", modifierFlags: [.command])

        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: Self.errorPageHeader).firstMatch
                .waitForExistence(timeout: UITests.Timeouts.localTestServer),
            "Error page should appear again after reload"
        )

        XCTAssertEqual(app.addressBarValueActivatingIfNeeded(), "https://reloaderror.invalid/", "Failing URL should remain after reload attempt")
    }

    /// Second navigation shows a different error description (host-not-found, then connection failure).
    func testErrorPage_SecondFailure_UpdatesErrorDescription() throws {
        // First navigation: DNS / host-not-found copy.
        let nxDomainURL = URL(string: "https://first-failure-kind.invalid/")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(nxDomainURL, pressingEnter: true)
        assertUnreachableHostErrorPageVisible()
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: Self.unreachableHostMessage).firstMatch.exists,
            "First failure should present host-not-found copy"
        )
        assertSaveAsMenuItemEnabled(false)

        // Second navigation: connection error — description must not stay host-not-found.
        let refusedURL = URL(string: "http://127.0.0.1:13311/second-failure")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(refusedURL, pressingEnter: true)
        assertGenericErrorPageVisible()
        XCTAssertFalse(
            webView.staticTexts.containing(\.value, containing: Self.unreachableHostMessage).firstMatch.exists,
            "Connection failure should not reuse host-not-found description text"
        )
    }

    // MARK: - Forward navigation with error in history

    /// Success → error → privacy-test-pages.site; back twice then forward twice. Forward stack keeps the error entry; menu row count is current + forward entries.
    func testErrorPage_ForwardNavigationAfterError_PreservesHistory() throws {
        // Step 1: Successful load (test server).
        let firstURL = UITests.simpleServedPage(titled: "First Error Test Page")
        app.activateAddressBar()
        addressBarTextField.pasteURL(firstURL, pressingEnter: true)

        let firstPageContent = webView.staticTexts.containing(\.value, containing: "First Error Test Page").firstMatch
        XCTAssertTrue(firstPageContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "First page should load")

        // Step 2: Error page in history.
        let errorURL = URL(string: "https://forwardtesterror.invalid")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(errorURL, pressingEnter: true)

        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: Self.errorPageHeader).firstMatch
                .waitForExistence(timeout: UITests.Timeouts.navigation),
            "Error page should appear for forward test error"
        )

        // Step 3: Another successful page so forward stack includes the error entry.
        let thirdURL = Self.privacyTestPagesHomeURL
        app.activateAddressBar()
        addressBarTextField.pasteURL(thirdURL, pressingEnter: true)

        let thirdPageContent = webView.staticTexts.containing(\.value, containing: Self.privacyTestPagesHomeBodyText).firstMatch
        XCTAssertTrue(thirdPageContent.waitForExistence(timeout: UITests.Timeouts.navigation), "Third page should load")

        // Step 4: Back twice — to error, then to first page.
        XCTAssertTrue(app.backButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Back button should be available")
        app.backButton.click()

        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: Self.errorPageHeader).firstMatch
                .waitForExistence(timeout: UITests.Timeouts.localTestServer),
            "Should be back on error page"
        )

        app.backButton.click()
        XCTAssertTrue(firstPageContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Should be back on first page")

        let errorHistoryTitle = try XCTUnwrap(errorURL.host, "Invalid URL should have a host for history title fallback")
        XCTAssertEqual(
            navigationHistoryMenuTitlesFromRightClicking(app.forwardButton),
            ["First Error Test Page", errorHistoryTitle, Self.privacyTestPagesHomeDocumentTitle],
            "Forward popup: current row plus error and privacy-test-pages home ahead"
        )

        // Step 5: Forward twice — error page, then privacy-test-pages.site.
        XCTAssertTrue(app.forwardButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Forward button should be available")
        XCTAssertTrue(app.forwardButton.isEnabled, "Forward button should be enabled")
        app.forwardButton.click()

        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: Self.errorPageHeader).firstMatch
                .waitForExistence(timeout: UITests.Timeouts.localTestServer),
            "Should go forward to error page"
        )

        app.forwardButton.click()
        XCTAssertTrue(thirdPageContent.waitForExistence(timeout: UITests.Timeouts.navigation), "Should go forward to third page")

        XCTAssertEqual(app.addressBarValueActivatingIfNeeded(), Self.privacyTestPagesHomeAddressBarValue, "Final URL after forward through error")
    }

    // MARK: - Local history: back, reload, forward

    /// Two test-server pages, back to the first, reload, forward still reaches the second; right-click menus reflect back/forward stack.
    func testErrorPage_LocalPages_BackThenReloadThenForward_PreservesForwardHistory() throws {
        let pageA = UITests.simpleServedPage(titled: "Reload Page A Title")
        let pageB = UITests.simpleServedPage(titled: "Reload Page B Title")

        // A → B in history.
        app.activateAddressBar()
        addressBarTextField.pasteURL(pageA, pressingEnter: true)
        let contentA = webView.staticTexts.containing(\.value, containing: "Reload Page A Title").firstMatch
        XCTAssertTrue(contentA.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Page A should load")

        app.activateAddressBar()
        addressBarTextField.pasteURL(pageB, pressingEnter: true)
        let contentB = webView.staticTexts.containing(\.value, containing: "Reload Page B Title").firstMatch
        XCTAssertTrue(contentB.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Page B should load")

        // Back to A, reload A, forward should still reach B.
        XCTAssertTrue(app.backButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Back button should be available")
        app.backButton.click()
        XCTAssertTrue(contentA.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Back should show page A")

        let reloadButton = app.reloadButton
        XCTAssertTrue(reloadButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Reload button should exist")
        XCTAssertTrue(reloadButton.isEnabled, "Reload should stay enabled on real page")
        reloadButton.click()
        XCTAssertTrue(contentA.waitForExistence(timeout: UITests.Timeouts.navigation), "Page A should render after reload")

        XCTAssertEqual(
            navigationHistoryMenuTitlesFromRightClicking(app.forwardButton),
            ["Reload Page A Title", "Reload Page B Title"],
            "Forward popup: current + one forward entry (page B)"
        )
        XCTAssertEqual(
            navigationHistoryMenuTitlesFromRightClicking(app.backButton),
            ["Reload Page A Title", "New Tab"],
            "Back popup: current row then new-tab entry"
        )

        XCTAssertTrue(app.forwardButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Forward button should exist")
        XCTAssertTrue(app.forwardButton.isEnabled, "Forward should remain available after reload")
        app.forwardButton.click()
        XCTAssertTrue(contentB.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Forward should still reach page B")
    }

    // MARK: - Submit same URL again on error page

    /// Paste the same bad URL again from the address bar while on the error page — still host-not-found and tab error title.
    func testErrorPage_ResubmitSameUnreachableURLFromAddressBar_KeepsErrorState() throws {
        let failingURL = URL(string: "https://resubmit-same.invalid/page")!
        // First navigation to bad host.
        app.activateAddressBar()
        addressBarTextField.pasteURL(failingURL, pressingEnter: true)
        assertUnreachableHostErrorPageVisible()

        // Submit the same URL again from the address bar while still on the error surface.
        app.activateAddressBar()
        addressBarTextField.pasteURL(failingURL, pressingEnter: true)

        assertUnreachableHostErrorPageVisible()
        assertSelectedTabTitleEquals(Self.tabErrorTitle)
        assertSaveAsMenuItemEnabled(false)
        XCTAssertEqual(app.addressBarValueActivatingIfNeeded(), "https://resubmit-same.invalid/page")
    }

    // MARK: - Navigate from error to another URL

    /// Back through served pages, then two user-entered bad URLs; second failure clears forward; back still works.
    func testErrorPage_FromServedPage_BackThenUnreachable_ThenAnotherUnreachable_ForwardDisabled() throws {
        let pageA = UITests.simpleServedPage(titled: "Hist Chain Page A")
        let pageB = UITests.simpleServedPage(titled: "Hist Chain Page B")
        // Successful chain A → B, back to A.
        app.activateAddressBar()
        addressBarTextField.pasteURL(pageA, pressingEnter: true)
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: "Hist Chain Page A").firstMatch
                .waitForExistence(timeout: UITests.Timeouts.localTestServer),
            "Page A loads"
        )
        app.activateAddressBar()
        addressBarTextField.pasteURL(pageB, pressingEnter: true)
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: "Hist Chain Page B").firstMatch
                .waitForExistence(timeout: UITests.Timeouts.localTestServer),
            "Page B loads"
        )
        XCTAssertTrue(app.backButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Back button should be available")
        app.backButton.click()
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: "Hist Chain Page A").firstMatch
                .waitForExistence(timeout: UITests.Timeouts.localTestServer),
            "Back to A"
        )

        // User-entered failures: second replaces forward stack (forward disabled, back still works).
        let firstBad = URL(string: "https://another-fail-one.invalid/")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(firstBad, pressingEnter: true)
        assertUnreachableHostErrorPageVisible()

        let secondBad = URL(string: "https://another-fail-two.invalid/")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(secondBad, pressingEnter: true)
        assertUnreachableHostErrorPageVisible()

        XCTAssertTrue(app.forwardButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Forward button should exist")
        XCTAssertFalse(app.forwardButton.isEnabled, "Forward history should be cleared after navigating to a new user-entered failure URL")
        XCTAssertTrue(app.backButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Back button should exist")
        XCTAssertTrue(app.backButton.isEnabled, "Back through stack should still be available")
        XCTAssertEqual(
            app.addressBarValueActivatingIfNeeded(),
            "https://another-fail-two.invalid/",
            "Address bar should track the latest failed navigation target"
        )
        assertSaveAsMenuItemEnabled(false)
    }

    /// From host-not-found, navigate to a served page; forward stays off; back returns to the error URL and UI.
    func testErrorPage_FromUnreachable_ThenValidPage_LoadsAndShowsPageTitle() throws {
        let bad = URL(string: "https://recover-from-second-nav.invalid/")!
        app.activateAddressBar()
        addressBarTextField.pasteURL(bad, pressingEnter: true)
        assertUnreachableHostErrorPageVisible()

        // Navigate to real content from error page.
        let good = UITests.simpleServedPage(titled: "Recovery Title After Two Step")
        app.activateAddressBar()
        addressBarTextField.pasteURL(good, pressingEnter: true)

        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: "Recovery Title After Two Step").firstMatch
                .waitForExistence(timeout: UITests.Timeouts.localTestServer),
            "Valid page should replace error content"
        )
        assertSelectedTabTitleEquals("Recovery Title After Two Step")
        XCTAssertTrue(app.forwardButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Forward button should exist")
        XCTAssertFalse(app.forwardButton.isEnabled, "New successful navigation from error should not enable forward")

        XCTAssertTrue(app.backButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Back button should be available")
        app.backButton.click()
        assertUnreachableHostErrorPageVisible()
        assertSelectedTabTitleEquals(Self.tabErrorTitle)
        assertSaveAsMenuItemEnabled(false)
        XCTAssertEqual(app.addressBarValueActivatingIfNeeded(), "https://recover-from-second-nav.invalid/")
    }

    // MARK: - Pinned tab

    /// Pinned tab: `debug://failure` connection error with simulate on, then simulate off + toolbar reload shows demo HTML; still one pinned tab.
    func testErrorPage_PinnedTab_FailureScheme_ReloadClearsError_StillSingleTab() throws {
        app.disableWarnBeforeClosingPinnedTabs(closeSettings: true)

        // Load a real page, pin it, then drive the same tab to debug://failure error via Debug menu.
        let pageURL = UITests.simpleServedPage(titled: "Pinned Before Failure Scheme Title")
        app.activateAddressBar()
        addressBarTextField.pasteURL(pageURL, pressingEnter: true)
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: "Pinned Before Failure Scheme Title").firstMatch
                .waitForExistence(timeout: UITests.Timeouts.localTestServer),
            "Page should load before pinning"
        )

        app.pinCurrentTab()

        ensureSimulateFailureURLSchemeOn()
        openFailureURLSchemeDemoViaDebugMenu()
        assertGenericErrorPageVisible()
        assertFailureSchemeSimulatedConnectionErrorDescriptionVisible()
        XCTAssertTrue(app.reloadButton.isEnabled, "Reload should stay available on the error surface (`testPinnedTabDoesNotNavigateAway` / `canReload`)")

        // Simulate off + toolbar reload should clear the error without adding tabs.
        ensureSimulateFailureURLSchemeOff()

        let reloadButton = app.reloadButton
        XCTAssertTrue(reloadButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Reload control should exist")
        XCTAssertTrue(reloadButton.isEnabled)
        reloadButton.click()
        assertFailureSchemeDemoPageBodyVisible()

        XCTAssertEqual(
            app.windows.firstMatch.tabs.count,
            0,
            "Pinned failure-scheme recovery must not spawn extra unpinned tabs"
        )
        XCTAssertEqual(
            app.windows.firstMatch.pinnedTabs.count,
            1,
            "Pinned tab should remain pinned after reload clears the error"
        )
    }

    /// Pinned tab: toolbar reload on a test-server page succeeds; tab strip unchanged.
    func testErrorPage_PinnedTab_ToolbarReload_StillSingleTab() throws {
        app.disableWarnBeforeClosingPinnedTabs(closeSettings: true)

        let pageURL = UITests.simpleServedPage(titled: "Pinned Reload Smoke Title")
        app.activateAddressBar()
        addressBarTextField.pasteURL(pageURL, pressingEnter: true)
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: "Pinned Reload Smoke Title").firstMatch
                .waitForExistence(timeout: UITests.Timeouts.localTestServer),
            "Page should load before pinning"
        )

        app.pinCurrentTab()

        let reloadButton = app.reloadButton
        XCTAssertTrue(reloadButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Reload control should exist")
        reloadButton.click()
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: "Pinned Reload Smoke Title").firstMatch
                .waitForExistence(timeout: UITests.Timeouts.navigation),
            "Reload on pinned page should succeed when server responds"
        )

        XCTAssertEqual(
            app.windows.firstMatch.tabs.count,
            0,
            "Pinned reload should not open additional tabs"
        )
        XCTAssertEqual(
            app.windows.firstMatch.pinnedTabs.count,
            1,
            "Pinned tab should remain pinned after reload"
        )
    }

    // MARK: - Session restoration after error

    /// Session restore on; history from URLs (middle → forward → back), then **`debug://failure` + simulate connection error** (reliable
    /// failure without tests-server gating). After restart: new tab, **simulate off** immediately before **select tab 0** so
    /// reactivation loads demo HTML. Back/Forward menus follow the same shape as before.
    func testErrorPage_SessionRestoration_FailureScheme_NewTabSelectRecover() {
        app.disableWarnBeforeQuitting()

        let sessionHistoryMiddleURL = UITests.simpleServedPage(titled: "Session Restore Middle")
        let sessionHistoryForwardURL = UITests.simpleServedPage(titled: "Session Restore Forward")

        // Turn on “restore previous session” so the next restart restores tabs and history.
        // This preference is persisted across UI-test launches, so restore the default before finishing.
        app.openPreferencesWindow()
        app.preferencesSetRestorePreviousSession(to: .restoreLastSession)
        app.closePreferencesWindow()
        defer {
            app.openPreferencesWindow()
            app.preferencesSetRestorePreviousSession(to: .newWindow)
            app.closePreferencesWindow()
        }
        app.enforceSingleWindow()

        XCTAssertTrue(addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Build history: middle page, then forward page, then Back to middle (forward stack still has “Forward”).
        app.activateAddressBar()
        addressBarTextField.pasteURL(sessionHistoryMiddleURL, pressingEnter: true)
        let middleContent = webView.staticTexts.containing(\.value, containing: "Session Restore Middle").firstMatch
        XCTAssertTrue(middleContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Middle page should load")

        app.activateAddressBar()
        addressBarTextField.pasteURL(sessionHistoryForwardURL, pressingEnter: true)
        let forwardContent = webView.staticTexts.containing(\.value, containing: "Session Restore Forward").firstMatch
        XCTAssertTrue(forwardContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Forward page should load")

        XCTAssertTrue(app.backButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(app.backButton.isEnabled, "Back should return to middle page")
        app.backButton.click()
        XCTAssertTrue(middleContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Should be on middle page with forward to second page")

        XCTAssertEqual(
            navigationHistoryMenuTitlesFromRightClicking(app.forwardButton),
            ["Session Restore Middle", "Session Restore Forward"],
            "Forward menu should list current row then Session Restore Forward"
        )

        // Replace current entry with debug://failure + simulated error (session will restore to this state).
        ensureSimulateFailureURLSchemeOn()
        openFailureURLSchemeDemoViaDebugMenu()
        assertGenericErrorPageVisible()
        assertFailureSchemeSimulatedConnectionErrorDescriptionVisible()
        let addressBeforeQuit = app.addressBarValueActivatingIfNeeded() ?? ""
        XCTAssertTrue(
            addressBeforeQuit.lowercased().contains("failure"),
            "Address bar should reference debug://failure, got: \(addressBeforeQuit)"
        )

        // Session restore should reopen on the same failing debug://failure tab.
        app.restart()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: UITests.Timeouts.elementExistence))

        assertGenericErrorPageVisible()
        assertFailureSchemeSimulatedConnectionErrorDescriptionVisible()
        XCTAssertEqual(app.windows.firstMatch.tabs.count, 1)
        XCTAssertTrue(app.reloadButton.isEnabled, "Restored failing tab should keep reload enabled before recovery")

        let addressAfterRestore = app.addressBarValueActivatingIfNeeded() ?? ""
        XCTAssertTrue(
            addressAfterRestore.lowercased().contains("failure"),
            "Restored navigation should keep debug://failure in the address bar, got: \(addressAfterRestore)"
        )

        // Open a fresh tab first, then select the restored tab (reload on activation succeeds once simulate is off).
        app.openNewTab()
        let newTabChrome = webView.popUpButtons["Customize"]
        XCTAssertTrue(newTabChrome.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Fresh tab should show the new tab page")
        XCTAssertEqual(app.windows.firstMatch.tabs.count, 2)

        ensureSimulateFailureURLSchemeOff()
        selectUnpinnedTab(at: 0)
        assertFailureSchemeDemoPageBodyVisible()

        let reloadButton = app.reloadButton
        XCTAssertTrue(reloadButton.isEnabled, "Reload should remain available after recovery")
        // Cmd+R on recovered demo should stay on demo HTML.
        app.typeKey("r", modifierFlags: [.command])
        assertFailureSchemeDemoPageBodyVisible()

        XCTAssertEqual(
            navigationHistoryMenuTitlesFromRightClicking(app.backButton),
            [
                Self.failureSchemeDocumentTitle,
                "Session Restore Middle",
                "New Tab"
            ],
            "Back menu: recovered debug://failure document title, prior middle, new tab (no duplicate error-only row)"
        )

        // Jump back through history via Back menu, then walk Forward to the recovered demo.
        // The recovery reload (sim-off Cmd+R) replaces the error history entry in-place, so there is
        // only ONE forward hop from "Session Restore Middle" to the recovered demo page — no separate
        // error-state entry in the forward stack.
        clickNavigationHistoryMenuItem(on: app.backButton, itemIndex: 1)
        XCTAssertTrue(
            app.windows.webViews["Session Restore Middle"].waitForExistence(timeout: UITests.Timeouts.localTestServer),
            "History jump should land on the earlier middle page"
        )
        XCTAssertEqual(
            navigationHistoryMenuTitlesFromRightClicking(app.forwardButton),
            [
                "Session Restore Middle",
                Self.failureSchemeDocumentTitle
            ],
            "Forward from middle should reach the recovered demo (error entry replaced by recovery reload)"
        )

        XCTAssertTrue(app.forwardButton.isEnabled)
        app.forwardButton.click()
        assertFailureSchemeDemoPageBodyVisible()

        // Switch to the fresh tab and back — history shape on tab 0 should be unchanged.
        selectUnpinnedTab(at: 1)
        XCTAssertTrue(
            newTabChrome.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The other tab should still be the new tab page"
        )

        selectUnpinnedTab(at: 0)
        assertFailureSchemeDemoPageBodyVisible()

        XCTAssertEqual(
            navigationHistoryMenuTitlesFromRightClicking(app.backButton),
            [
                Self.failureSchemeDocumentTitle,
                "Session Restore Middle",
                "New Tab"
            ],
            "After tab round-trip, back list should match post-recovery shape"
        )
    }

    // MARK: - Toolbar reload on success page

    /// Toolbar reload on privacy-test-pages.site keeps content and URL.
    func testErrorPage_ToolbarReloadButton_ReloadsCurrentURL() throws {
        let url = Self.privacyTestPagesHomeURL
        app.activateAddressBar()
        addressBarTextField.pasteURL(url, pressingEnter: true)

        // Baseline happy path: `app.reloadButton` on a working page.
        let privacyTestPagesContent = webView.staticTexts.containing(\.value, containing: Self.privacyTestPagesHomeBodyText).firstMatch
        XCTAssertTrue(privacyTestPagesContent.waitForExistence(timeout: UITests.Timeouts.navigation), "Privacy Test Pages home should load")

        XCTAssertEqual(app.addressBarValueActivatingIfNeeded(), Self.privacyTestPagesHomeAddressBarValue, "Precondition: privacy-test-pages.site is loaded")

        let reloadButton = app.reloadButton
        XCTAssertTrue(reloadButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Reload button should exist")
        reloadButton.click()

        XCTAssertTrue(privacyTestPagesContent.waitForExistence(timeout: UITests.Timeouts.navigation), "Content should be visible after reload")

        XCTAssertEqual(app.addressBarValueActivatingIfNeeded(), Self.privacyTestPagesHomeAddressBarValue, "URL should remain on privacy-test-pages.site after reload")
    }

    // MARK: - debug://failure scheme (DuckURLSchemeHandler; Debug submenu)

    /// `debug://failure` connection error, switch to another tab and back while simulate stays **on** — still the same error surface.
    func testErrorPage_FailureScheme_ReactivationWithSimulateOn_StillShowsError() throws {
        // Warm up: demo with simulate off, then close so the next tab starts clean.
        ensureSimulateFailureURLSchemeOff()
        openFailureURLSchemeDemoViaDebugMenu()
        assertFailureSchemeDemoPageBodyVisible()
        try app.closeTab()

        // Fresh tab: simulate on → error; switch away and back → same error (reactivation does not “heal”).
        ensureSimulateFailureURLSchemeOn()
        openFailureURLSchemeDemoViaDebugMenu()
        assertGenericErrorPageVisible()
        assertFailureSchemeSimulatedConnectionErrorDescriptionVisible()

        app.openNewTab()
        let privacyTestPagesContent = webView.staticTexts.containing(\.value, containing: Self.privacyTestPagesHomeBodyText).firstMatch
        app.activateAddressBar()
        addressBarTextField.pasteURL(Self.privacyTestPagesHomeURL, pressingEnter: true)
        XCTAssertTrue(privacyTestPagesContent.waitForExistence(timeout: UITests.Timeouts.navigation), "Second tab should load privacy-test-pages.site")

        selectUnpinnedTab(at: 0)
        assertGenericErrorPageVisible()
        assertFailureSchemeSimulatedConnectionErrorDescriptionVisible()
        assertSelectedTabTitleEquals(Self.tabErrorTitle)
    }

    /// Simulated `debug://failure` error, simulate **off**, load privacy-test-pages.site, **Back** — handler serves demo HTML again.
    func testErrorPage_GoingBackToFailureScheme_AfterDisablingSimulate_ReloadSucceeds() throws {
        // Error first, then privacy-test-pages.site on top; turn simulate off before Back so the debug://failure commit reloads as demo.
        ensureSimulateFailureURLSchemeOn()
        openFailureURLSchemeDemoViaDebugMenu()
        assertGenericErrorPageVisible()
        assertFailureSchemeSimulatedConnectionErrorDescriptionVisible()

        app.activateAddressBar()
        addressBarTextField.pasteURL(Self.privacyTestPagesHomeURL, pressingEnter: true)
        let privacyTestPagesContent = webView.staticTexts.containing(\.value, containing: Self.privacyTestPagesHomeBodyText).firstMatch
        XCTAssertTrue(privacyTestPagesContent.waitForExistence(timeout: UITests.Timeouts.navigation), "privacy-test-pages.site should load")

        XCTAssertTrue(app.backButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Back should return to the debug://failure commit")
        XCTAssertTrue(app.backButton.isEnabled, "Back should be enabled with privacy-test-pages.site above the failed scheme load")
        ensureSimulateFailureURLSchemeOff()
        app.backButton.click()
        assertFailureSchemeDemoPageBodyVisible()
        XCTAssertFalse(
            webView.staticTexts.containing(\.value, containing: Self.errorPageHeader).firstMatch.exists,
            "Back to debug://failure should show the demo document, not the generic error header"
        )
    }

    /// `debug://failure` opened with simulate **on** (error), then privacy-test-pages.site, then **Back** — still the simulated connection error, not demo HTML.
    ///
    /// The back-forward item must come from an initial **failed** load. If the first load is the successful demo (simulate off),
    /// **Back** can restore WebKit’s cached document without re-invoking the scheme handler, so toggling simulate on afterward
    /// does not reliably reproduce the error path.
    func testErrorPage_GoingBackToFailureScheme_WithSimulateOn_ShowsConnectionError() throws {
        // Same stack as above but simulate stays on: Back must show connection error, not cached demo HTML.
        ensureSimulateFailureURLSchemeOn()
        openFailureURLSchemeDemoViaDebugMenu()
        assertGenericErrorPageVisible()
        assertFailureSchemeSimulatedConnectionErrorDescriptionVisible()

        app.activateAddressBar()
        addressBarTextField.pasteURL(Self.privacyTestPagesHomeURL, pressingEnter: true)
        let privacyTestPagesContent = webView.staticTexts.containing(\.value, containing: Self.privacyTestPagesHomeBodyText).firstMatch
        XCTAssertTrue(privacyTestPagesContent.waitForExistence(timeout: UITests.Timeouts.navigation), "privacy-test-pages.site should load")

        XCTAssertTrue(app.backButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Back should be available")
        app.backButton.click()

        assertGenericErrorPageVisible()
        assertFailureSchemeSimulatedConnectionErrorDescriptionVisible()
        let demoBody = webView.staticTexts.containing(\.value, containing: Self.failureSchemeDemoPageBody).firstMatch
        XCTAssertFalse(
            demoBody.waitForExistence(timeout: 1.0),
            "Simulated connection failure should replace the demo HTML, not keep the handler page body visible"
        )
    }

    /// **Debug → debug:// URL scheme:** simulate on, open demo → error; second tab loads a real page; tab A reloads on
    /// reselect; simulate off + tab switch shows demo HTML again. Includes two failed **Cmd+R** reloads on the error page.
    /// Requires the Debug menu.
    func testFailureURLScheme_DebugMenuTogglesSimulatedConnectionError() throws {
        // Tab 0: simulate OFF → demo (`debug://failure` in the address bar is treated as search; use Debug menu).
        ensureSimulateFailureURLSchemeOff()
        openFailureURLSchemeDemoViaDebugMenu()
        assertFailureSchemeDemoPageBodyVisible()

        // Close the successfully loaded tab so the simulated connection error runs on a fresh tab, not by reloading the demo WebView in place.
        try app.closeTab()

        // New tab: simulate ON, open demo → connection-style error page.
        ensureSimulateFailureURLSchemeOn()
        openFailureURLSchemeDemoViaDebugMenu()
        assertGenericErrorPageVisible()
        assertFailureSchemeSimulatedConnectionErrorDescriptionVisible()

        app.typeKey("r", modifierFlags: [.command])
        assertGenericErrorPageVisible()
        assertFailureSchemeSimulatedConnectionErrorDescriptionVisible()
        app.typeKey("r", modifierFlags: [.command])
        assertGenericErrorPageVisible()
        assertFailureSchemeSimulatedConnectionErrorDescriptionVisible()

        // Tab 1: load a real page so we can switch away from the failing web view.
        app.openNewTab()
        let privacyTestPagesContent = webView.staticTexts.containing(\.value, containing: Self.privacyTestPagesHomeBodyText).firstMatch
        app.activateAddressBar()
        addressBarTextField.pasteURL(Self.privacyTestPagesHomeURL, pressingEnter: true)
        XCTAssertTrue(privacyTestPagesContent.waitForExistence(timeout: UITests.Timeouts.navigation), "Second tab should load privacy-test-pages.site")

        // Tab 0: reactivation reloads the failed navigation; simulate still ON → error page again.
        selectUnpinnedTab(at: 0)
        assertGenericErrorPageVisible()
        assertFailureSchemeSimulatedConnectionErrorDescriptionVisible()

        selectUnpinnedTab(at: 1)
        XCTAssertTrue(privacyTestPagesContent.waitForExistence(timeout: UITests.Timeouts.navigation), "Other tab should still show privacy-test-pages.site")

        ensureSimulateFailureURLSchemeOff()
        selectUnpinnedTab(at: 0)
        assertFailureSchemeDemoPageBodyVisible()
    }

    /// Aligned with `testWhenTabWithOtherErrorActivated_reloadNotTriggered`: `debug://failure?simulatedError=hostNotFound` fails with
    /// `URLError.cannotFindHost` — outside `Tab.shouldReload`'s connection-error auto-reload list. Unlike real-DNS variants of this
    /// scenario, the handler's attempt counter makes "no reload happened" observable: after switching away and back, the error copy
    /// must still read attempt 1.
    func testErrorPage_FailureScheme_HostNotFoundQuery_TabSwitch_DoesNotAutoReload() throws {
        app.closeAllWindows()

        // Toggling simulate resets the attempt counter, so the first load reports attempt 1.
        ensureSimulateFailureURLSchemeOff()
        ensureSimulateFailureURLSchemeOn()

        openFailureURLSchemeHostNotFoundQueryViaDebugMenu()
        assertGenericErrorPageVisible()
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: Self.failureSchemeSimulatedHostNotFoundDescription).firstMatch
                .waitForExistence(timeout: UITests.Timeouts.localTestServer),
            "Error page should show the simulated host-not-found copy"
        )
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: Self.failureSchemeSimulateAttemptSuffix(1)).firstMatch.exists,
            "First load should report attempt 1 from the scheme handler"
        )
        assertNavigationChromeMatchesTransientConnectionErrorNoBackCase()

        // Second tab so tab 0's web view is deactivated (reactivation would run the load again if this error kind auto-reloaded).
        app.openNewTab()
        let servedTitle = "HostNotFound No Autoreload Other Tab"
        let otherTabURL = UITests.simpleServedPage(titled: servedTitle)
        app.activateAddressBar()
        addressBarTextField.pasteURL(otherTabURL, pressingEnter: true)
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: servedTitle).firstMatch
                .waitForExistence(timeout: UITests.Timeouts.localTestServer),
            "Second tab should load from the tests server"
        )

        // Reselect tab 0: unlike connection-style errors, host-not-found must NOT re-invoke the scheme handler.
        selectUnpinnedTab(at: 0)
        assertGenericErrorPageVisible()
        let attempt2Label = webView.staticTexts.containing(\.value, containing: Self.failureSchemeSimulateAttemptSuffix(2)).firstMatch
        XCTAssertFalse(
            attempt2Label.waitForExistence(timeout: 2.0),
            "Tab reactivation must not reload a host-not-found error (attempt counter stays at 1)"
        )
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: Self.failureSchemeSimulateAttemptSuffix(1)).firstMatch.exists,
            "Error copy should still read attempt 1 after reselection"
        )
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: Self.failureSchemeSimulatedHostNotFoundDescription).firstMatch.exists,
            "Host-not-found copy should remain after reselection"
        )
    }

    /// Debug menu opens `debug://failure` as an actual page (simulate off): demo HTML renders, Save As is enabled (real document,
    /// not an error surface), and both Cmd+R and toolbar reload keep serving the demo. Finally, turning simulate on and reloading
    /// must surface the error — proving reload re-invokes the scheme handler rather than repainting a cached document.
    func testErrorPage_FailureScheme_DemoPageViaDebugMenu_ReloadWorks() throws {
        ensureSimulateFailureURLSchemeOff()
        openFailureURLSchemeDemoViaDebugMenu()
        assertFailureSchemeDemoPageBodyVisible()
        assertSelectedTabTitleEquals(Self.failureSchemeDocumentTitle)
        assertSaveAsMenuItemEnabled(true)

        // Cmd+R on the successfully loaded scheme page keeps the demo document.
        app.typeKey("r", modifierFlags: [.command])
        assertFailureSchemeDemoPageBodyVisible()
        assertSelectedTabTitleEquals(Self.failureSchemeDocumentTitle)

        // Toolbar reload does too.
        let reloadButton = app.reloadButton
        XCTAssertTrue(reloadButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Reload control should exist")
        XCTAssertTrue(reloadButton.isEnabled)
        reloadButton.click()
        assertFailureSchemeDemoPageBodyVisible()

        // Reload is a real navigation through the handler: with simulate on, the same Cmd+R now fails.
        ensureSimulateFailureURLSchemeOn()
        app.typeKey("r", modifierFlags: [.command])
        assertGenericErrorPageVisible()
        assertFailureSchemeSimulatedConnectionErrorDescriptionVisible()
    }
}

// MARK: - Helpers

private extension ErrorPageUITests {

    // MARK: - Strings (aligned with app `UserText` / error page template; keep in sync with product copy).

    static var errorPageHeader: String { "DuckDuckGo can’t load this page." }
    static var unreachableHostMessage: String { "A server with the specified hostname could not be found." }
    static var tabErrorTitle: String { "Failed to open page" }

    static var privacyTestPagesHomeURL: URL { URL(string: "https://privacy-test-pages.site/")! }
    static var privacyTestPagesHomeBodyText: String { "Privacy Test Pages" }
    static var privacyTestPagesHomeDocumentTitle: String { "Privacy Test Pages - Home" }
    static var privacyTestPagesHomeAddressBarValue: String { "https://privacy-test-pages.site/" }

    /// Copy from `DuckURLSchemeHandler.failureSchemeDemoHtml` only; simulated connection-error UI includes `debug://failure` in the NSError description, so do not key off that substring alone.
    static var failureSchemeDemoPageBody: String { "This page is served by the app URL scheme handler." }

    /// Prefix of `DuckURLSchemeHandler` `NSLocalizedDescriptionKey` when simulate is enabled (suffix is ` · attempt N`).
    static var failureSchemeSimulatedConnectionLostDescription: String { "Debug simulated connection lost (debug://failure)" }

    /// Prefix for `URLError.notConnectedToInternet` simulation (`debug://failure?alternatingFailures=1` on alternating passes, or `simulatedError=notConnected`).
    static var failureSchemeSimulatedNotConnectedDescription: String { "Debug simulated not connected to internet (debug://failure)" }

    /// Prefix for `URLError.cannotFindHost` simulation (`debug://failure?simulatedError=hostNotFound`) — an error kind outside `Tab.shouldReload`'s auto-reload list.
    static var failureSchemeSimulatedHostNotFoundDescription: String { "Debug simulated host not found (debug://failure)" }

    /// Suffix appended to simulated failure descriptions for UI-visible load counting (`DuckURLSchemeHandler`).
    static func failureSchemeSimulateAttemptSuffix(_ attempt: Int) -> String {
        " · attempt \(attempt)"
    }

    /// Same host path as `MainMenuActions.openFailureURLSchemeDemo` (`debug://failure`).
    static var failureDemoNavigationURL: URL { URL(string: "debug://failure")! }

    /// Opt-in alternating simulated errors for successive handler invocations (tab reactivation / reload).
    static var failureDemoAlternatingFailuresURL: URL { URL(string: "debug://failure?alternatingFailures=1")! }

    /// Always `URLError.notConnectedToInternet` when simulate is on (`?simulatedError=notConnected` on `debug://failure`).
    static var failureDemoSimulatedNotConnectedQueryURL: URL { URL(string: "debug://failure?simulatedError=notConnected")! }

    /// Document `<title>` from `DuckURLSchemeHandler.failureSchemeDemoHtml` (history / navigation menu rows).
    static var failureSchemeDocumentTitle: String { "debug://failure" }

    /// Menu label for a committed URL when there is no document title (`BackForwardListItemViewModel` falls back to `url.host ?? url.absoluteString`).
    static func backForwardMenuLabel(forCommittedURL url: URL) -> String {
        url.host ?? url.absoluteString
    }

    /// `debug://failure` error commits use the URL host in back/forward menus, not `tabErrorTitle`.
    static var failureSchemeCommittedHostMenuLabel: String {
        backForwardMenuLabel(forCommittedURL: failureDemoNavigationURL)
    }

    // MARK: - Pinned tab cleanup

    /// Pinned tabs survive window close/reopen; unpin via File menu so later tests do not inherit pinned state (same idea as `TabBarTests` / `AIChatTests`).
    func removePinnedTabsForTestCleanup() {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists, "Window should exist for pinned tab cleanup")
        let pinnedTabs = window.pinnedTabs
        while pinnedTabs.count > 0 {
            pinnedTabs.firstMatch.click()
            guard app.mainMenuUnpinTabMenuItem.waitForExistence(timeout: UITests.Timeouts.elementExistence) else {
                break
            }
            app.mainMenuUnpinTabMenuItem.tap()
        }
        app.closeAllWindows()
    }

    // MARK: - debug://failure Debug menu (DuckURLSchemeHandler UI tests)

    /// Opens **Debug → debug:// URL scheme**. Submenu rows open on hover; clicking can dismiss or mis-hit the parent item.
    func openFailureURLSchemeDebugSubmenu() {
        let failureURLSchemeSubmenu = app.debugMenu.menuItems[AccessibilityIdentifiers.DebugMenu.failureURLScheme]
        app.debugMenu.click()
        failureURLSchemeSubmenu.hover()
    }

    private func clickFailureURLSchemeDebugMenuItem(_ accessibilityIdentifier: String) {
        let failureURLSchemeSubmenu = app.debugMenu.menuItems[AccessibilityIdentifiers.DebugMenu.failureURLScheme]
        let item = failureURLSchemeSubmenu.menuItems[accessibilityIdentifier]
        openFailureURLSchemeDebugSubmenu()
        item.click()
    }

    func openFailureURLSchemeDemoViaDebugMenu() {
        clickFailureURLSchemeDebugMenuItem(AccessibilityIdentifiers.DebugMenu.openFailureURLSchemeDemoPage)
    }

    func openFailureURLSchemeAlternatingFailuresViaDebugMenu() {
        clickFailureURLSchemeDebugMenuItem(AccessibilityIdentifiers.DebugMenu.openFailureURLSchemeAlternatingFailuresDemoPage)
    }

    func openFailureURLSchemeNotConnectedQueryViaDebugMenu() {
        clickFailureURLSchemeDebugMenuItem(AccessibilityIdentifiers.DebugMenu.openFailureURLSchemeNotConnectedQueryDemoPage)
    }

    func openFailureURLSchemeHostNotFoundQueryViaDebugMenu() {
        clickFailureURLSchemeDebugMenuItem(AccessibilityIdentifiers.DebugMenu.openFailureURLSchemeHostNotFoundQueryDemoPage)
    }

    /// Idempotent: persisted Debug toggle state is shared across tests—do not assume defaults after `closeAllWindows()`.
    func ensureSimulateFailureURLSchemeOn() {
        let failureURLSchemeSubmenu = app.debugMenu.menuItems[AccessibilityIdentifiers.DebugMenu.failureURLScheme]
        let simulateItem = failureURLSchemeSubmenu.menuItems[AccessibilityIdentifiers.DebugMenu.simulateFailureURLSchemeConnectionError]
        openFailureURLSchemeDebugSubmenu()
        if simulateItem.title == AccessibilityIdentifiers.DebugMenu.failureURLSchemeSimulateConnectionErrorMenuTitleOff {
            simulateItem.click()
        } else {
            app.typeKey(.escape, modifierFlags: [])
        }
    }

    func ensureSimulateFailureURLSchemeOff() {
        let failureURLSchemeSubmenu = app.debugMenu.menuItems[AccessibilityIdentifiers.DebugMenu.failureURLScheme]
        let simulateItem = failureURLSchemeSubmenu.menuItems[AccessibilityIdentifiers.DebugMenu.simulateFailureURLSchemeConnectionError]
        openFailureURLSchemeDebugSubmenu()
        if simulateItem.title == AccessibilityIdentifiers.DebugMenu.failureURLSchemeSimulateConnectionErrorMenuTitleOn {
            simulateItem.click()
        } else {
            app.typeKey(.escape, modifierFlags: [])
        }
    }

    func assertFailureSchemeDemoPageBodyVisible(file: StaticString = #filePath, line: UInt = #line) {
        let demoBody = webView.staticTexts.containing(\.value, containing: Self.failureSchemeDemoPageBody).firstMatch
        XCTAssertTrue(
            demoBody.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "debug://failure HTML should be visible (distinct from error-page copy that also mentions debug://failure)",
            file: file,
            line: line
        )
    }

    func assertFailureSchemeSimulatedConnectionErrorDescriptionVisible(file: StaticString = #filePath, line: UInt = #line) {
        let descriptionLabel = webView.staticTexts.containing(\.value, containing: Self.failureSchemeSimulatedConnectionLostDescription).firstMatch
        XCTAssertTrue(
            descriptionLabel.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Error page should surface the debug simulated connection-lost copy from the scheme handler",
            file: file,
            line: line
        )
    }

    /// Clicks the tab at `index` in the front window’s tab strip (0-based). Fails if there are not enough tabs.
    func selectUnpinnedTab(at index: Int) {
        let tabs = app.windows.firstMatch.tabs
        XCTAssertGreaterThan(tabs.count, index, "Expected at least \(index + 1) tabs")
        tabs.element(boundBy: index).click()
    }

    /// Waits for the generic error page header in the active web view (any failure kind).
    func assertGenericErrorPageVisible(file: StaticString = #filePath, line: UInt = #line) {
        let header = webView.staticTexts.containing(\.value, containing: Self.errorPageHeader).firstMatch
        XCTAssertTrue(
            header.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Error page header should be visible",
            file: file,
            line: line
        )
    }

    /// Generic error page plus host-not-found description text (DNS / NXDOMAIN style failures in UI tests).
    func assertUnreachableHostErrorPageVisible(file: StaticString = #filePath, line: UInt = #line) {
        assertGenericErrorPageVisible(file: file, line: line)
        let description = webView.staticTexts.containing(\.value, containing: Self.unreachableHostMessage).firstMatch
        XCTAssertTrue(
            description.exists,
            "Error page should include host-not-found copy",
            file: file,
            line: line
        )
    }

    /// Asserts the selected tab’s accessibility title contains `title` (partial match; matches how tabs expose long titles).
    func assertSelectedTabTitleEquals(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let tab = app.windows.firstMatch.tabs.element(matching: \.isSelected, equalTo: true)
        XCTAssertTrue(tab.waitForExistence(timeout: UITests.Timeouts.elementExistence), file: file, line: line)
        XCTAssertTrue(
            tab.wait(for: \.title, contains: title, timeout: UITests.Timeouts.elementExistence),
            "Selected tab title should contain \(title), got: \(tab.title)",
            file: file,
            line: line
        )
    }

    /// Right-click Back/Forward: menu row titles from `NavigationButtonMenuDelegate` (current row first, then back or forward
    /// list). Empty if the button is disabled or the delegate hides the menu (only-current case).
    private func navigationHistoryMenuTitlesFromRightClicking(_ button: XCUIElement) -> [String] {
        XCTAssertTrue(button.exists, "Navigation button should exist before reading history menu")
        guard button.isEnabled else {
            XCTFail("Navigation button is disabled")
            return []
        }
        button.rightClick()
        let menu = app.windows.firstMatch.menus.firstMatch
        defer { app.typeKey(.escape, modifierFlags: []) }
        guard menu.waitForExistence(timeout: UITests.Timeouts.elementExistence) else { return [] }
        let count = menu.menuItems.count
        return (0..<count).map { menu.menuItems.element(boundBy: $0).title }
    }

    /// Selects a row from the Back or Forward navigation popup (`NavigationButtonMenuDelegate` tags match `itemIndex`).
    private func clickNavigationHistoryMenuItem(on button: XCUIElement, itemIndex: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(button.exists, file: file, line: line)
        XCTAssertTrue(button.isEnabled, file: file, line: line)
        button.rightClick()
        let menu = app.windows.firstMatch.menus.firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: UITests.Timeouts.elementExistence), file: file, line: line)
        let item = menu.menuItems.element(boundBy: itemIndex)
        XCTAssertTrue(item.exists, file: file, line: line)
        item.click()
    }

    /// Host-not-found error page: back enabled, forward off, reload enabled; **Save As** off (same gate as `TabViewModel.canSaveContent` for error pages).
    func assertNavigationChromeMatchesHostNotFoundCase(file: StaticString = #filePath, line: UInt = #line) {
        let back = app.backButton
        let forward = app.forwardButton
        let reload = app.reloadButton
        XCTAssertTrue(back.waitForExistence(timeout: UITests.Timeouts.elementExistence), file: file, line: line)
        XCTAssertTrue(forward.exists && reload.exists, file: file, line: line)
        XCTAssertTrue(back.isEnabled, "Host-not-found error should allow back navigation", file: file, line: line)
        XCTAssertFalse(forward.isEnabled, "Forward should be disabled with no forward stack", file: file, line: line)
        XCTAssertTrue(reload.isEnabled, "Reload should stay enabled on error page", file: file, line: line)
        assertSaveAsMenuItemEnabled(false, file: file, line: line)
    }

    /// Transient connection-style error where `debug://failure` was the **first** navigation in the window
    /// (no prior page — back is disabled).  Used when the debug-menu action opens a fresh window directly
    /// to the failure URL without committing a New Tab entry first.
    func assertNavigationChromeMatchesTransientConnectionErrorNoBackCase(file: StaticString = #filePath, line: UInt = #line) {
        let back = app.backButton
        let forward = app.forwardButton
        let reload = app.reloadButton
        XCTAssertTrue(back.waitForExistence(timeout: UITests.Timeouts.elementExistence), file: file, line: line)
        XCTAssertTrue(forward.exists && reload.exists, file: file, line: line)
        XCTAssertFalse(back.isEnabled, "Back should be disabled: debug://failure was the first navigation in this window", file: file, line: line)
        XCTAssertFalse(forward.isEnabled, file: file, line: line)
        XCTAssertTrue(reload.isEnabled, file: file, line: line)
        assertSaveAsMenuItemEnabled(false, file: file, line: line)
    }

    /// Error state with both back and forward history preserved (`testWhenPageLoadedAndFailsOnRefreshAndOnConsequentRefresh…` toolbar shape).
    func assertNavigationChromeMatchesErrorWithBackAndForwardCase(file: StaticString = #filePath, line: UInt = #line) {
        let back = app.backButton
        let forward = app.forwardButton
        let reload = app.reloadButton
        XCTAssertTrue(back.waitForExistence(timeout: UITests.Timeouts.elementExistence), file: file, line: line)
        XCTAssertTrue(forward.exists && reload.exists, file: file, line: line)
        XCTAssertTrue(back.isEnabled, file: file, line: line)
        XCTAssertTrue(forward.isEnabled, file: file, line: line)
        XCTAssertTrue(reload.isEnabled, file: file, line: line)
        assertSaveAsMenuItemEnabled(false, file: file, line: line)
    }

    /// Opens File → Save As… and checks enabled state, then dismisses the menu with Escape.
    /// Uses the menu title string (main menu item has no dedicated accessibility identifier in `MainMenu.swift`).
    func assertSaveAsMenuItemEnabled(_ enabled: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let fileMenu = app.menuBars.menuBarItems["File"]
        XCTAssertTrue(fileMenu.waitForExistence(timeout: UITests.Timeouts.elementExistence), file: file, line: line)
        fileMenu.click()
        let saveAs = app.menuItems["Save As…"].firstMatch
        XCTAssertTrue(saveAs.exists, file: file, line: line)
        XCTAssertEqual(saveAs.isEnabled, enabled, "Save As should \(enabled ? "be" : "not be") enabled", file: file, line: line)
        app.typeKey(.escape, modifierFlags: [])
    }
}
