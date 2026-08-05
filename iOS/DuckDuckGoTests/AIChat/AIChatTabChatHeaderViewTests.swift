//
//  AIChatTabChatHeaderViewTests.swift
//  DuckDuckGoTests
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

import UIKit
import XCTest
@testable import DuckDuckGo

final class AIChatTabChatHeaderViewTests: XCTestCase {

    private var header: AIChatTabChatHeaderView!

    override func setUp() {
        super.setUp()
        header = AIChatTabChatHeaderView(frame: CGRect(x: 0, y: 0, width: 390, height: 60))
        header.configure(isSubscriptionActive: true)
    }

    override func tearDown() {
        header = nil
        super.tearDown()
    }

    func testVoiceSessionActive_hidesCloseButtonChatListPillAndTitle() {
        header.setVoiceSessionActive(true)

        XCTAssertTrue(header.closeButtonPill.isHidden, "Close button pill must hide while voice session is active")
        XCTAssertTrue(header.chatListButtonPill.isHidden, "Chat-list pill must hide while voice session is active")
        XCTAssertTrue(header.titleHolder.isHidden, "Title holder must hide while voice session is active")
    }

    func testVoiceSessionInactive_restoresCloseButtonChatListPillAndTitle() {
        header.setVoiceSessionActive(true)
        header.setVoiceSessionActive(false)

        XCTAssertFalse(header.closeButtonPill.isHidden, "Close button pill must reappear when voice session ends")
        XCTAssertFalse(header.chatListButtonPill.isHidden, "Chat-list pill must reappear when voice session ends")
        XCTAssertFalse(header.titleHolder.isHidden, "Title holder must reappear when voice session ends")
    }

    func testSetTabIconState_zeroCount_clearsLabel() {
        header.setTabIconState(count: 0, hasUnread: false, isFireMode: false)
        XCTAssertNil(header.tabSwitcherView.label.text, "Count zero must render as a blank label")
    }

    func testSetTabIconState_countBelowThreshold_rendersAsNumber() {
        header.setTabIconState(count: 12, hasUnread: false, isFireMode: false)
        XCTAssertEqual(header.tabSwitcherView.label.text, "12")
    }

    func testSetTabIconState_countAtThreshold_rendersAsInfinitySymbol() {
        header.setTabIconState(count: TabSwitcherStaticView.maxTextTabs, hasUnread: false, isFireMode: false)
        XCTAssertEqual(header.tabSwitcherView.label.text, "∞")
    }

    func testSetTabIconState_hasUnread_propagatesToRenderer() {
        header.setTabIconState(count: 3, hasUnread: true, isFireMode: false)
        XCTAssertTrue(header.tabSwitcherView.hasUnread, "Unread state must flow through to the renderer")
    }

    func testSetTabIconState_fireMode_propagatesToRenderer() {
        header.setTabIconState(count: 3, hasUnread: false, isFireMode: true)
        XCTAssertTrue(header.tabSwitcherView.isFireMode, "Fire-mode state must flow through to the renderer")
    }

    func testSetOnboardingLocked_true_dimsTheEnclosingPills() {
        header.setOnboardingLocked(true)

        XCTAssertEqual(header.closeButtonPill.alpha, 0.5, accuracy: 0.001,
                       "Close button pill (not just the icon) must dim when locked so the glass background fades too")
        XCTAssertEqual(header.chatListButtonPill.alpha, 0.5, accuracy: 0.001,
                       "Chat-list pill (not just the icon) must dim when locked so the glass background fades too")
    }

    func testSetOnboardingLocked_false_restoresPillAlpha() {
        header.setOnboardingLocked(true)
        header.setOnboardingLocked(false)

        XCTAssertEqual(header.closeButtonPill.alpha, 1, accuracy: 0.001)
        XCTAssertEqual(header.chatListButtonPill.alpha, 1, accuracy: 0.001)
    }

    // MARK: - Upgrade plate impressions

    /// Fresh header with an unresolved subscription state and a hidden container — the state the view is
    /// in right after construction, before either the coordinator or the feature check has said anything.
    private func makeHeaderWithSpyDelegate() -> (AIChatTabChatHeaderView, SpyAIChatTabChatHeaderViewDelegate) {
        let header = AIChatTabChatHeaderView(frame: CGRect(x: 0, y: 0, width: 390, height: 60))
        let delegate = SpyAIChatTabChatHeaderViewDelegate()
        header.delegate = delegate
        return (header, delegate)
    }

    func testUpgradePlate_becomesVisible_notifiesDelegateOnce() {
        let (header, delegate) = makeHeaderWithSpyDelegate()

        header.setContainerVisible(true)
        header.configure(isSubscriptionActive: false)

        XCTAssertEqual(delegate.upgradePlateDidBecomeVisibleCount, 1)
    }

    func testUpgradePlate_repeatedStateRefreshes_doNotNotifyAgain() {
        let (header, delegate) = makeHeaderWithSpyDelegate()
        header.setContainerVisible(true)
        header.configure(isSubscriptionActive: false)

        // Stands in for what a session actually does: prompt submissions and navigations re-run the
        // subscription refresh and the tab-icon refresh without changing effective visibility.
        header.configure(isSubscriptionActive: false)
        header.setContainerVisible(true)
        header.setTabIconState(count: 4, hasUnread: true, isFireMode: false)
        header.configure(isSubscriptionActive: false)

        XCTAssertEqual(delegate.upgradePlateDidBecomeVisibleCount, 1,
                       "Repeated writes that leave effective visibility unchanged must not re-fire the impression")
    }

    func testUpgradePlate_stateChurnWhileContainerHidden_thenShown_notifiesOnce() {
        let (header, delegate) = makeHeaderWithSpyDelegate()

        // Each of these changes the view state while the plate stays off screen, so none of them is an
        // appearance. Only the container showing up is.
        header.configure(isSubscriptionActive: false)
        header.setVoiceSessionActive(true)
        header.setVoiceSessionActive(false)
        header.setOnboardingLocked(true)
        header.setOnboardingLocked(false)
        XCTAssertEqual(delegate.upgradePlateDidBecomeVisibleCount, 0)

        header.setContainerVisible(true)

        XCTAssertEqual(delegate.upgradePlateDidBecomeVisibleCount, 1)
    }

    func testUpgradePlate_containerHiddenThenShown_notifiesAgain() {
        let (header, delegate) = makeHeaderWithSpyDelegate()
        header.setContainerVisible(true)
        header.configure(isSubscriptionActive: false)

        header.setContainerVisible(false)
        header.setContainerVisible(true)

        XCTAssertEqual(delegate.upgradePlateDidBecomeVisibleCount, 2,
                       "Leaving and re-entering the Duck.ai tab is a second appearance")
    }

    func testUpgradePlate_voiceSession_suppressesThenReNotifiesOnExit() {
        let (header, delegate) = makeHeaderWithSpyDelegate()
        header.setContainerVisible(true)
        header.configure(isSubscriptionActive: false)

        header.setVoiceSessionActive(true)
        XCTAssertEqual(delegate.upgradePlateDidBecomeVisibleCount, 1, "Entering voice must not fire")

        header.setVoiceSessionActive(false)
        XCTAssertEqual(delegate.upgradePlateDidBecomeVisibleCount, 2, "Leaving voice re-shows the plate")
    }

    func testUpgradePlate_titleHolderHidden_neverNotifiesEvenWhenContainerVisible() {
        let (header, delegate) = makeHeaderWithSpyDelegate()

        header.setVoiceSessionActive(true)
        header.setContainerVisible(true)
        header.configure(isSubscriptionActive: false)

        XCTAssertTrue(header.titleHolder.isHidden)
        XCTAssertEqual(delegate.upgradePlateDidBecomeVisibleCount, 0,
                       "The container flag alone must not fire while nothing is on screen")
    }

    func testUpgradePlate_unresolvedSubscriptionState_doesNotNotify_thenNotifiesOnceOnResolvingInactive() {
        let (header, delegate) = makeHeaderWithSpyDelegate()

        header.setContainerVisible(true)
        XCTAssertEqual(delegate.upgradePlateDidBecomeVisibleCount, 0,
                       "An unresolved subscription state renders a blank slot, not the plate")

        header.configure(isSubscriptionActive: false)

        XCTAssertEqual(delegate.upgradePlateDidBecomeVisibleCount, 1)
    }

    func testUpgradePlate_subscriptionResolvesActive_doesNotNotify() {
        let (header, delegate) = makeHeaderWithSpyDelegate()

        header.setContainerVisible(true)
        header.configure(isSubscriptionActive: true)

        XCTAssertEqual(delegate.upgradePlateDidBecomeVisibleCount, 0)
    }

    func testUpgradePlate_onboardingLocked_doesNotNotify_thenNotifiesOnceOnUnlock() {
        let (header, delegate) = makeHeaderWithSpyDelegate()

        header.setOnboardingLocked(true)
        header.setContainerVisible(true)
        header.configure(isSubscriptionActive: false)
        XCTAssertEqual(delegate.upgradePlateDidBecomeVisibleCount, 0,
                       "The fire onboarding step hides the plate, so there is nothing to count")

        header.setOnboardingLocked(false)

        XCTAssertEqual(delegate.upgradePlateDidBecomeVisibleCount, 1,
                       "Finishing onboarding reveals the plate — that is its first appearance")
    }

    func testUpgradePlate_subscriptionResolvesBeforeContainerAppears_notifiesOnce() {
        let (header, delegate) = makeHeaderWithSpyDelegate()

        header.configure(isSubscriptionActive: false)
        header.setContainerVisible(true)

        XCTAssertEqual(delegate.upgradePlateDidBecomeVisibleCount, 1,
                       "Which of the two arrives first must not change the count — the subscription check is async")
    }
}

private final class SpyAIChatTabChatHeaderViewDelegate: AIChatTabChatHeaderViewDelegate {

    private(set) var upgradePlateDidBecomeVisibleCount = 0

    func aiChatTabChatHeaderUpgradePlateDidBecomeVisible() {
        upgradePlateDidBecomeVisibleCount += 1
    }

    func aiChatTabChatHeaderDidTapChatList() {}
    func aiChatTabChatHeaderDidTapUpgrade() {}
    func aiChatTabChatHeaderDidTapClose() {}
    func aiChatTabChatHeaderDidTapNewChat() {}
    func aiChatTabChatHeaderDidTapNewVoiceChat() {}
    func aiChatTabChatHeaderDidTapNewImage() {}
    func aiChatTabChatHeaderDidTapNewTab() {}
    func aiChatTabChatHeaderDidTapNewSearch() {}
    func aiChatTabChatHeaderDidTapNewFireTab() {}
    func aiChatTabChatHeaderDidTapTabSwitcher() {}
}
