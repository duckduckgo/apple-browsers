//
//  TabSwitcherStaticButtonTests.swift
//  DuckDuckGo
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

import XCTest
@testable import DuckDuckGo

class TabSwitcherStaticButtonTests: XCTestCase {

    func testInitialState() {
        let button = TabSwitcherStaticButton(showMenuOnLongPress: false)
        XCTAssertEqual(0, button.tabCount)
        XCTAssertFalse(button.hasUnread)
        XCTAssertNil(button.text)
    }

    func testWhenInitializedThenAccessibilityLabelIsTabSwitcher() {
        let button = TabSwitcherStaticButton(showMenuOnLongPress: false)
        XCTAssertEqual(UserText.tabSwitcherAccessibilityLabel, button.accessibilityLabel)
    }

    func testWhenAnimateCalledThenCountIsNotIncremented() {
        let button = TabSwitcherStaticButton(showMenuOnLongPress: false)
        button.animateUpdate { }
        XCTAssertEqual(0, button.tabCount)
        XCTAssertNil(button.text)
    }

    func testWhenCountSetBackToZeroThenTextIsBlank() {
        let button = TabSwitcherStaticButton(showMenuOnLongPress: false)
        button.tabCount = 1
        XCTAssertNotNil(button.text)
        button.tabCount = 0
        XCTAssertNil(button.text)
    }

    func testWhenExceedsMaxThenLabelIsSetAppropriately() {
        let button = TabSwitcherStaticButton(showMenuOnLongPress: false)
        button.tabCount = 100
        XCTAssertEqual("∞", button.text)
    }


    func testWhenCountIsUpdatedThenLabelIsUpdated() {
        let button = TabSwitcherStaticButton(showMenuOnLongPress: false)
        button.tabCount = 99
        XCTAssertEqual("99", button.text)
    }

    func testWhenResizedDuringCountAnimationThenIconRemainsCentered() throws {
        let button = TabSwitcherStaticButton(showMenuOnLongPress: false)
        let icon = try XCTUnwrap(button.subviews.first { $0 is TabSwitcherStaticView })
        button.layoutIfNeeded()

        for _ in 0..<3 {
            icon.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
            button.bounds.size = CGSize(width: 44, height: 0)
            button.layoutIfNeeded()
            button.bounds.size = CGSize(width: 34, height: 44)
            button.layoutIfNeeded()
            icon.transform = .identity
            button.layoutIfNeeded()

            XCTAssertEqual(icon.center.x, button.bounds.midX, accuracy: 0.001)
            XCTAssertEqual(icon.center.y, button.bounds.midY, accuracy: 0.001)
            XCTAssertEqual(icon.bounds.size, button.bounds.size)
        }
    }

    func testWhenNewChatAvailableThenLongPressMenuStartsWithNewChat() {
        XCTAssertEqual(newTabLongPressMenuTitles(isNewChatAvailable: true),
                       [UserText.actionNewAIChat, UserText.actionNewFireTab, UserText.actionNewTab])
    }

    func testWhenNewChatUnavailableThenLongPressMenuHasOnlyTabItems() {
        XCTAssertEqual(newTabLongPressMenuTitles(isNewChatAvailable: false),
                       [UserText.actionNewFireTab, UserText.actionNewTab])
    }

    func testLongPressMenuPixelsKeepTheirNamesAndCarryMenuSource() {
        let sources: [(NewTabLongPressMenu.Source, String)] = [(.toolbar, "toolbar"), (.tabSwitcher, "tab_switcher"), (.tabsBar, "tabs_bar")]
        for (source, expected) in sources {
            let pixels: [(NewTabLongPressMenuPixel, String)] = [
                (.displayed(source: source), "m_tab_long_press_menu_displayed"),
                (.newFireTab(source: source), "m_tab_long_press_menu_new_fire_tab"),
                (.newNormalTab(source: source), "m_tab_long_press_menu_new_normal_tab"),
                (.newChat(source: source), "tab_long_press_menu_new_chat")
            ]
            for (pixel, name) in pixels {
                XCTAssertEqual(pixel.name, name)
                XCTAssertEqual(pixel.parameters, ["source": expected])
            }
        }
    }

    private func newTabLongPressMenuTitles(isNewChatAvailable: Bool) -> [String] {
        let actions = NewTabLongPressMenu.Actions(onNewFireTab: {},
                                                  onNewTab: {},
                                                  onNewChat: {},
                                                  isNewChatAvailable: { isNewChatAvailable })
        return NewTabLongPressMenu.items(source: .toolbar, actions: actions, pixelFiring: nil).map(\.title)
    }

}
