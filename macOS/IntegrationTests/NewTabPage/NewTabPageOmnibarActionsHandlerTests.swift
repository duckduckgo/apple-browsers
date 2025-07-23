//
//  NewTabPageOmnibarActionsHandlerTests.swift
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
@testable import DuckDuckGo_Privacy_Browser
import NewTabPage
import AIChat
import Common
import Combine

final class NewTabPageOmnibarActionsHandlerTests: XCTestCase {

    private var handler: NewTabPageOmnibarActionsHandler!
    private var promptHandler: AIChatPromptHandler!
    private var windowControllersManager: WindowControllersManager!
    private var tabsPreferences: TabsPreferences!
    private var tab: Tab!
    private var window: MainWindow!

    @MainActor
    override func setUp() {
        autoreleasepool {
            promptHandler = AIChatPromptHandler.shared
            windowControllersManager = Application.appDelegate.windowControllersManager
            tabsPreferences = TabsPreferences()
            handler = NewTabPageOmnibarActionsHandler(
                promptHandler: promptHandler,
                windowControllersManager: windowControllersManager,
                tabsPreferences: tabsPreferences,
                isShiftPressed: { false },
                isCommandPressed: { false }
            )
            tab = Tab(content: .newtab)
            window = WindowsManager.openNewWindow(with: tab)!

            windowControllersManager.lastKeyMainWindowController = window.windowController as? MainWindowController
        }
    }

    override func tearDown() {
        autoreleasepool {
            promptHandler = nil
            windowControllersManager = nil
            tabsPreferences = nil
            handler = nil
            tab = nil
            window?.close()
            window = nil
        }
    }

    @MainActor
    func testWhenSubmitSearchOnSameTab_ThenSearchURLOpens() {
        let target: NewTabPageDataModel.OpenTarget = .sameTab

        handler.submitSearch("duckduckgo", target: target)

        XCTAssertEqual(windowControllersManager.lastKeyMainWindowController?.activeTab?.url?.absoluteString, "https://duckduckgo.com/?q=duckduckgo")
    }

    @MainActor
    func testWhenSubmitSearchOnNewTab_ThenNewTabOpensWithSearchURL() {
        let target: NewTabPageDataModel.OpenTarget = .newTab

        handler.submitSearch("duckduckgo", target: target)

        XCTAssertEqual(windowControllersManager.lastKeyMainWindowController?.mainViewController.tabCollectionViewModel.tabs.last?.url?.absoluteString, "https://duckduckgo.com/?q=duckduckgo")
        XCTAssertEqual(windowControllersManager.lastKeyMainWindowController?.mainViewController.tabCollectionViewModel.tabs.count, 2)
    }

    @MainActor
    func testWhenSubmitSearchContainsURL_ThenTabNavigatesDirectlyURL() {
        let target: NewTabPageDataModel.OpenTarget = .sameTab

        handler.submitSearch("wikipedia.org", target: target)

        XCTAssertEqual(windowControllersManager.lastKeyMainWindowController?.mainViewController.tabCollectionViewModel.tabs.last?.url?.absoluteString, "http://wikipedia.org")
        XCTAssertEqual(windowControllersManager.lastKeyMainWindowController?.mainViewController.tabCollectionViewModel.tabs.count, 1)
    }

    @MainActor
    func testWhenSubmitAIChatOnSameTab_ThenAIChatOpens() {
        let target: NewTabPageDataModel.OpenTarget = .sameTab

        handler.submitChat("duckduckgo", target: target)

        XCTAssert(windowControllersManager.lastKeyMainWindowController?.mainViewController.tabCollectionViewModel.tabs.last?.url?.isDuckAIURL ?? false)
        XCTAssertEqual(windowControllersManager.lastKeyMainWindowController?.mainViewController.tabCollectionViewModel.tabs.count, 1)
    }

    @MainActor
    func testWhenSubmitAIChatOnNewTab_ThenNewTabOpensWithAIChat() {
        let target: NewTabPageDataModel.OpenTarget = .newTab

        handler.submitChat("duckduckgo", target: target)

        XCTAssert(windowControllersManager.lastKeyMainWindowController?.mainViewController.tabCollectionViewModel.tabs.last?.url?.isDuckAIURL ?? false)
        XCTAssertEqual(windowControllersManager.lastKeyMainWindowController?.mainViewController.tabCollectionViewModel.tabs.count, 2)
    }

 }
