//
//  BrowserToolOpenedTabsTests.swift
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
@testable import AIChat

@MainActor
final class BrowserToolOpenedTabsTests: XCTestCase {

    func testWhenTabsAreAddedThenTheyAreListedOldestFirst() {
        let openedTabs = BrowserToolOpenedTabs()

        openedTabs.add("first", ownerTabID: "chat")
        openedTabs.add("second", ownerTabID: "chat")

        XCTAssertEqual(openedTabs.tabIDs(ownerTabID: "chat"), ["first", "second"])
    }

    /// One chat must never close or silently read a tab another chat opened.
    func testWhenAnotherChatOpenedTheTabThenItIsNotThisChats() {
        let openedTabs = BrowserToolOpenedTabs()

        openedTabs.add("tab", ownerTabID: "chat-a")

        XCTAssertTrue(openedTabs.contains("tab", ownerTabID: "chat-a"))
        XCTAssertFalse(openedTabs.contains("tab", ownerTabID: "chat-b"))
        XCTAssertTrue(openedTabs.contains("tab"))
        XCTAssertTrue(openedTabs.tabIDs(ownerTabID: "chat-b").isEmpty)
    }

    func testWhenATabIsRemovedThenOnlyThatTabIsForgotten() {
        let openedTabs = BrowserToolOpenedTabs()
        openedTabs.add("first", ownerTabID: "chat")
        openedTabs.add("second", ownerTabID: "chat")

        XCTAssertTrue(openedTabs.remove("first"))

        XCTAssertFalse(openedTabs.contains("first"))
        XCTAssertEqual(openedTabs.tabIDs(ownerTabID: "chat"), ["second"])
    }

    func testWhenAnUnknownTabIsRemovedThenNothingChanges() {
        let openedTabs = BrowserToolOpenedTabs()
        openedTabs.add("tab", ownerTabID: "chat")

        XCTAssertFalse(openedTabs.remove("other"))

        XCTAssertEqual(openedTabs.tabIDs(ownerTabID: "chat"), ["tab"])
    }

    func testWhenTheLastTabIsRemovedThenTheChatIsNoLongerListed() {
        let openedTabs = BrowserToolOpenedTabs()
        openedTabs.add("tab", ownerTabID: "chat")

        openedTabs.remove("tab")

        XCTAssertTrue(openedTabs.ownerTabIDs.isEmpty)
    }

    func testWhenAllOfAChatsTabsAreRemovedThenTheyAreReturnedAndOtherChatsKeepTheirs() {
        let openedTabs = BrowserToolOpenedTabs()
        openedTabs.add("a1", ownerTabID: "chat-a")
        openedTabs.add("a2", ownerTabID: "chat-a")
        openedTabs.add("b1", ownerTabID: "chat-b")

        XCTAssertEqual(openedTabs.removeAll(ownerTabID: "chat-a"), ["a1", "a2"])

        XCTAssertTrue(openedTabs.tabIDs(ownerTabID: "chat-a").isEmpty)
        XCTAssertEqual(openedTabs.tabIDs(ownerTabID: "chat-b"), ["b1"])
        XCTAssertEqual(openedTabs.ownerTabIDs, ["chat-b"])
    }

    func testWhenATabIsAddedAgainThenItMovesToTheNewestPosition() {
        let openedTabs = BrowserToolOpenedTabs()
        openedTabs.add("first", ownerTabID: "chat")
        openedTabs.add("second", ownerTabID: "chat")

        openedTabs.add("first", ownerTabID: "chat")

        XCTAssertEqual(openedTabs.tabIDs(ownerTabID: "chat"), ["second", "first"])
    }
}
