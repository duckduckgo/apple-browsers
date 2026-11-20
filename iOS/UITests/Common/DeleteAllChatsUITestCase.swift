//
//  DeleteAllChatsUITestCase.swift
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

class DeleteAllChatsUITestCase: UITestCase {
    private enum ID {
        static let deleteAll = "Fire.Confirmation.Button.DeleteAllChats"
        static let thisChat = "Fire.Confirmation.Button.ThisTab"
        static let close = "Fire.Confirmation.Button.Close"
        static let fire = "Browser.Toolbar.Button.Fire"
    }

    let server = DeleteAllChatsTestServer()
    let timeout: TimeInterval = 30
    let pinnedSubtitle = "Deleting all chats also deletes pinned chats."

    override var launchesAppInSetUp: Bool { false }

    override var additionalLaunchArguments: [String] {
        let flags: [String: Bool] = [
            "fireButtonDeleteAllChats": true, "slideToDelete": false,
            "fireButtonRefinements": true, "fireMode": true,
            "aiChatNativeStorage": true, "aiChatNativeDataAccess": true,
            "aiChatNativeChatHistory": true, "aiChatAddressBarRecentChats": true,
            "aiChatSuggestions": true, "aiChatTabHandoffImprovements": true,
            "aiChatTabHideToggle": true, "aiChatNativeInputIPad": false,
            "contextualDuckAIMode": true, "pageContextFeature": true,
            "aiChatContextualUnifiedToggleInput": false, "aiChatContextualFloatingInput": false,
            "aiChatChromeMenuButtonIPad": false, "aiChatChromeShortcutIPad": true,
            "ipadAIChatContextSidebar": false, "aiChatAutoAttachContextByDefault": false,
            "duckAINativeStoragePathMigration": true
        ]
        return flags.sorted { $0.key < $1.key }.flatMap { ["-ff.\($0.key)", String($0.value)] } + [
            "-aichat.debug.customURL", server.chatURL
        ]
    }

    override var additionalLaunchEnvironment: [String: String] {
        ["BASE_URL": server.baseURL, "PIXEL_BASE_URL": server.baseURL, "UITEST_DISABLE_ANIMATIONS": "1"]
    }

    override func setUpWithError() throws {
        do {
            try server.start()
            try super.setUpWithError()
        } catch {
            server.stop()
            throw error
        }
    }

    override func tearDownWithError() throws {
        defer { server.stop() }
        try super.tearDownWithError()
    }

    func launchApp(normalChats: Int, fireChats: Int = 0) {
        app.launchArguments += ["-duckAiChatsTestSeed", "{\"normal\":\(normalChats),\"fire\":\(fireChats)}"]
        app.launch()
    }

    func openChat() {
        app.openURL(server.chatURL, expecting: "Offline chat")
    }

    func showFire() {
        let heading = app.webViews.staticTexts["Offline chat"]
        if heading.exists { heading.tapWhenHittable(in: app) }
        let fire = UIDevice.current.userInterfaceIdiom == .pad ? app.browserWindow.buttons[ID.fire] : app.buttons["Clear Tabs and Data"]
        fire.tapWhenHittable(in: app)
        XCTAssertTrue(app.buttons[ID.close].waitForExistence(timeout: timeout))
    }

    func checkAndConfirmDeleteAll(deleteThisChat: Bool, subtitle: String) {
        let deleteAll = app.buttons[ID.deleteAll]
        XCTAssertTrue(deleteAll.exists, "Expected Delete All Chats in the Fire confirmation")
        XCTAssertEqual(deleteAll.label, "Delete All Chats")
        XCTAssertTrue(app.staticTexts["Delete chats?"].exists)
        XCTAssertTrue(app.staticTexts[subtitle].exists)
        let thisChat = app.buttons[ID.thisChat]
        if deleteThisChat {
            XCTAssertTrue(thisChat.exists)
            XCTAssertEqual(thisChat.label, "Delete This Chat")
        } else {
            XCTAssertFalse(thisChat.exists)
        }
        deleteAll.tapWhenHittable(in: app)
    }

    func assertFullChatDeleteAllClearedStore(deleteThisChat: Bool, subtitle: String) {
        showFire()
        checkAndConfirmDeleteAll(deleteThisChat: deleteThisChat, subtitle: subtitle)
        XCTAssertTrue(app.buttons[ID.close].wait(for: NSPredicate(format: "exists == false"), timeout: timeout))
        if UIDevice.current.userInterfaceIdiom == .pad {
            assertFireSheetReturnsToSingleChat()
        } else {
            assertNativeHistoryIsEmpty()
        }
    }

    private func assertFireSheetReturnsToSingleChat() {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        let close = app.buttons[ID.close]
        var chatCount: String?
        repeat {
            showFire()
            chatCount = close.value as? String
            if chatCount == "0" {
                XCTAssertFalse(app.buttons[ID.deleteAll].exists)
                XCTAssertTrue(app.staticTexts["Delete this chat?"].exists)
                XCTAssertTrue(app.buttons[ID.thisChat].exists)
                XCTAssertEqual(app.buttons[ID.thisChat].label, "Delete This Chat")
                return
            }
            close.tapWhenHittable(in: app)
        } while ProcessInfo.processInfo.systemUptime < deadline
        XCTAssertEqual(chatCount, "0", "Expected a successful native read of zero chats after deletion")
    }

    func openTabSwitcher() {
        if app.browserWindow.buttons["Browser.Toolbar.Button.TabSwitcher"].exists {
            app.dismissAddressBarEditing()
        }
        let tabSwitcher = app.buttons["Tab Switcher"]
        XCTAssertTrue(tabSwitcher.waitForHittableInAppWindow(in: app, timeout: timeout))
        tabSwitcher.tap()
        XCTAssertTrue(app.buttons["TabSwitcher.Button.Done"].waitForExistence(timeout: timeout))
    }

    func assertNativeHistoryIsEmpty() {
        openNativeHistory()
        XCTAssertTrue(app.staticTexts["No recent chats"].waitForExistence(timeout: timeout))
        XCTAssertFalse(app.staticTexts["Couldn't load chats"].exists)
    }

    func assertNativeHistoryContainsNormalChats(_ count: Int) {
        openNativeHistory()
        XCTAssertTrue(app.staticTexts["Seed normal chat \(count)"].waitForExistence(timeout: timeout))
        let titles = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Seed normal chat "))
        XCTAssertEqual(titles.count, count)
        for index in 1...count {
            XCTAssertTrue(app.staticTexts["Seed normal chat \(index)"].exists)
        }
    }

    private func openNativeHistory() {
        openTabSwitcher()
        app.buttons["TabSwitcher.Button.DuckChat"].tapWhenHittable(in: app)
        app.buttons["View all chats"].tapWhenHittable(in: app)
        XCTAssertTrue(app.navigationBars["Chats"].waitForExistence(timeout: timeout))
    }
}
