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
}
