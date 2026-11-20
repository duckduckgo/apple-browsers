//
//  DeleteAllChatsUITests.swift
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
import UITestingSupport

final class DeleteAllChatsSeveralChatsUITests: DeleteAllChatsUITestCase {
    func testSeveralChatsShowsBothActionsAndDeletesAllChats() {
        launchApp(normalChats: 3)
        openChat()
        assertFullChatDeleteAllClearedStore(deleteThisChat: true, subtitle: pinnedSubtitle)
    }
}

final class DeleteAllChatsUITests: DeleteAllChatsUITestCase {
    func testOneChatShowsOnlyDeleteAllAndDeletesTheChat() {
        launchApp(normalChats: 1)
        openChat()
        assertFullChatDeleteAllClearedStore(deleteThisChat: false, subtitle: pinnedSubtitle)
    }

    func testFireModeDeletionPreservesNormalChats() throws {
        guard #available(iOS 17, *) else { throw XCTSkip("Fire tabs require iOS 17.") }
        launchApp(normalChats: 3, fireChats: 2)
        openTabSwitcher()
        app.buttons["TabSwitcher.Button.NewTab"].press(forDuration: 1)
        app.buttons["New Fire Tab"].tapWhenHittable(in: app)
        openChat()

        assertFullChatDeleteAllClearedStore(deleteThisChat: true, subtitle: "Deleting all chats won't affect chats outside Fire Tabs.")

        app.navigationBars["Chats"].buttons["Close"].tapWhenHittable(in: app)
        openTabSwitcher()
        app.buttons["TabSwitcher.Button.NewTab"].press(forDuration: 1)
        app.buttons["Browser.NewTabMenu.NewTab"].tapWhenHittable(in: app)
        assertNativeHistoryContainsNormalChats(3)
    }

    func testContextualDeleteAllClearsChatsAndKeepsTheWebsiteOpen() {
        launchApp(normalChats: 3)
        app.openURL(server.websiteURL, expecting: "Offline website")
        app.dismissAddressBarEditing()
        app.buttons["Browser.OmniBar.Button.AIChat"].tapWhenHittable(in: app)

        let sheet = app.otherElements["AIChat.ContextualSheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: timeout))
        let input = sheet.textViews["AIChatNativeInputView.textView"]
        input.tapWhenHittable(in: app)
        input.typeText("An offline question")
        sheet.buttons["AIChatNativeInputView.submitButton"].tapWhenHittable(in: app)
        app.assertPageContains("Offline chat")
        sheet.buttons["AIChat.ContextualSheet.FireButton"].tapWhenHittable(in: app)
        XCTAssertTrue(app.buttons["Fire.Confirmation.Button.Close"].waitForExistence(timeout: timeout))
        checkAndConfirmDeleteAll(deleteThisChat: true, subtitle: pinnedSubtitle)

        XCTAssertTrue(sheet.wait(for: NSPredicate(format: "exists == false"), timeout: timeout))
        app.assertPageContains("Offline website")
        assertNativeHistoryIsEmpty()
    }
}
