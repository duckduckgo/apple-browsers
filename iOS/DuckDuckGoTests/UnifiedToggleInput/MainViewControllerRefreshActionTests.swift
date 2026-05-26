//
//  MainViewControllerRefreshActionTests.swift
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
@testable import DuckDuckGo

final class MainViewControllerRefreshActionTests: XCTestCase {

    // MARK: - Bug regression: omnibar session + tab loading

    /// JL1 regression: chained server redirects (cnn.com → www.cnn.com → edition.cnn.com) reassign
    /// `tab.url` while `isLoading == true`, firing `tabLoadingStateDidChange` and routing through
    /// `refreshAction`. Before the fix the action collapsed back to `.refreshNonAITab` because the
    /// guard required `!tab.isLoading`, tearing down the UTI the user had just reopened mid-load.
    func test_nonAITab_omnibarSession_loading_preservesSession() {
        let inputs = makeInputs(
            tabIsAITab: false,
            tabIsLoading: true,
            coordinatorIsActive: true,
            coordinatorIsOmnibarSession: true
        )
        XCTAssertEqual(MainViewController.decideRefreshAction(for: inputs), .preserveOmnibarSession)
    }

    func test_nonAITab_omnibarSession_notLoading_preservesSession() {
        let inputs = makeInputs(
            tabIsAITab: false,
            tabIsLoading: false,
            coordinatorIsActive: true,
            coordinatorIsOmnibarSession: true
        )
        XCTAssertEqual(MainViewController.decideRefreshAction(for: inputs), .preserveOmnibarSession)
    }

    // MARK: - Non-AI tab paths

    func test_nonAITab_coordinatorInactive_chatHeaderHidden_unbinds() {
        let inputs = makeInputs(
            tabIsAITab: false,
            coordinatorIsActive: false,
            coordinatorIsOmnibarSession: false,
            isAITabChatHeaderContainerHidden: true
        )
        XCTAssertEqual(MainViewController.decideRefreshAction(for: inputs), .unbindInactiveNonAITab)
    }

    func test_nonAITab_coordinatorActive_notOmnibarSession_refreshesNonAITab() {
        let inputs = makeInputs(
            tabIsAITab: false,
            tabIsLoading: false,
            coordinatorIsActive: true,
            coordinatorIsOmnibarSession: false
        )
        XCTAssertEqual(MainViewController.decideRefreshAction(for: inputs), .refreshNonAITab)
    }

    // Submitting from the UTI deactivates the coordinator *before* the new nav reaches us,
    // so by the time `decideRefreshAction` runs after a real user submission `isOmnibarSession`
    // is already false and the bar collapses normally.
    func test_nonAITab_postUserSubmit_loading_refreshesNonAITab() {
        let inputs = makeInputs(
            tabIsAITab: false,
            tabIsLoading: true,
            coordinatorIsActive: true,
            coordinatorIsOmnibarSession: false
        )
        XCTAssertEqual(MainViewController.decideRefreshAction(for: inputs), .refreshNonAITab)
    }

    // MARK: - AI tab paths

    /// During a fresh AI-tab navigation the link briefly goes nil and `isAITab` flips false;
    /// the guard at the top of `decideRefreshAction` keeps the AI presentation in place.
    func test_nilLink_coordinatorInAITabState_preservesAIPresentation() {
        let inputs = makeInputs(
            tabHasLink: false,
            tabIsAITab: false,
            coordinatorIsAITabState: true
        )
        XCTAssertEqual(
            MainViewController.decideRefreshAction(for: inputs),
            .refreshAITab(.preserveCurrentPresentation(allowsEarlyReturn: true))
        )
    }

    func test_aiTab_coordinatorInAITabState_chromeHidden_preservesWithEarlyReturn() {
        let inputs = makeInputs(
            tabIsAITab: true,
            coordinatorIsAITabState: true,
            isNavigationChromeHidden: true
        )
        XCTAssertEqual(
            MainViewController.decideRefreshAction(for: inputs),
            .refreshAITab(.preserveCurrentPresentation(allowsEarlyReturn: true))
        )
    }

    func test_aiTab_freshChat_showsCollapsedAndExpandsAfterRefresh() {
        let inputs = makeInputs(
            tabIsAITab: true,
            tabURL: URL(string: "https://duckduckgo.com/?q=hello&ia=chat&duckai=2"),
            coordinatorIsAITabState: false,
            coordinatorHasSubmittedPrompt: false
        )
        XCTAssertEqual(
            MainViewController.decideRefreshAction(for: inputs),
            .refreshAITab(.showCollapsed(expandAfterRefresh: true))
        )
    }

    func test_aiTab_voiceModeRequested_showsCollapsedWithoutExpand() {
        let inputs = makeInputs(
            tabIsAITab: true,
            tabIsVoiceModeRequested: true,
            coordinatorIsAITabState: false,
            coordinatorHasSubmittedPrompt: false
        )
        XCTAssertEqual(
            MainViewController.decideRefreshAction(for: inputs),
            .refreshAITab(.showCollapsed(expandAfterRefresh: false))
        )
    }

    // MARK: - Helpers

    private func makeInputs(
        tabHasLink: Bool = true,
        tabIsAITab: Bool = false,
        tabIsLoading: Bool = false,
        tabURL: URL? = URL(string: "https://example.com/"),
        tabLinkURL: URL? = URL(string: "https://example.com/"),
        tabIsVoiceModeRequested: Bool = false,
        coordinatorIsAITabState: Bool = false,
        coordinatorIsActive: Bool = false,
        coordinatorIsOmnibarSession: Bool = false,
        coordinatorHasSubmittedPrompt: Bool = false,
        isAITabChatHeaderContainerHidden: Bool = true,
        isNavigationChromeHidden: Bool = false
    ) -> UnifiedToggleInputRefreshActionInputs {
        UnifiedToggleInputRefreshActionInputs(
            tabHasLink: tabHasLink,
            tabIsAITab: tabIsAITab,
            tabIsLoading: tabIsLoading,
            tabURL: tabURL,
            tabLinkURL: tabLinkURL,
            tabIsVoiceModeRequested: tabIsVoiceModeRequested,
            coordinatorIsAITabState: coordinatorIsAITabState,
            coordinatorIsActive: coordinatorIsActive,
            coordinatorIsOmnibarSession: coordinatorIsOmnibarSession,
            coordinatorHasSubmittedPrompt: coordinatorHasSubmittedPrompt,
            isAITabChatHeaderContainerHidden: isAITabChatHeaderContainerHidden,
            isNavigationChromeHidden: isNavigationChromeHidden
        )
    }
}
