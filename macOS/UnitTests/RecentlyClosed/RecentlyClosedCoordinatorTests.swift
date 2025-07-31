//
//  RecentlyClosedCoordinatorTests.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Combine
@testable import DuckDuckGo_Privacy_Browser

final class RecentlyClosedCoordinatorTests: XCTestCase {

    let tab1 = RecentlyClosedTab("https://site1.com")
    let tab2 = RecentlyClosedTab("https://site2.com")
    let tab3 = RecentlyClosedTab("https://site2.com")
    let tab4 = RecentlyClosedTab("https://site3.com")

    override var allowedNonNilVariables: Set<String> {
        ["tab1", "tab2", "tab3", "tab4"]
    }

    func testWhenDomainsAreBurnedThenCachedTabsOpenToThemAreRemoved() throws {
        var cache: [RecentlyClosedCacheItem] = [
            tab1,
            tab2,
            RecentlyClosedWindow([
                tab3,
                tab4
            ])
        ]

        cache.burn(for: ["site1.com", "site3.com"], tld: Application.appDelegate.tld)

        XCTAssertEqual(cache.count, 2)
        let tab = try XCTUnwrap(cache[0] as? RecentlyClosedTab)
        XCTAssertEqual(tab.tabContent, .url("https://site2.com".url!, source: .link))

        let window = try XCTUnwrap(cache[1] as? RecentlyClosedWindow)
        XCTAssertEqual(window.tabs.count, 1)
        XCTAssertEqual(window.tabs[0].tabContent, .url("https://site2.com".url!, source: .link))
    }

    func testWhenDomainsAreBurnedThenInteractionDataIsDeleted() throws {
        var cache: [RecentlyClosedCacheItem] = [
            tab1,
            tab2,
            RecentlyClosedWindow([
                tab3,
                tab4
            ])
        ]

        cache.burn(for: ["unrelatedsite1.com", "unrelatedsite2.com"], tld: Application.appDelegate.tld)

        XCTAssertEqual(cache.count, 3)

        let tab1 = try XCTUnwrap(cache[0] as? RecentlyClosedTab)
        XCTAssertNil(tab1.interactionData)

        let tab2 = try XCTUnwrap(cache[1] as? RecentlyClosedTab)
        XCTAssertNil(tab2.interactionData)

        let window = try XCTUnwrap(cache[2] as? RecentlyClosedWindow)
        XCTAssertEqual(window.tabs.count, 2)
        XCTAssertNil(window.tabs[0].interactionData)
        XCTAssertNil(window.tabs[1].interactionData)
    }
}

private extension RecentlyClosedTab {
    convenience init(_ url: String) {
        self.init(tabContent: .url(url.url!, source: .link), favicon: nil, title: nil, interactionData: Data(), index: .unpinned(0))
    }
}

private extension RecentlyClosedWindow {
    convenience init(_ tabs: [RecentlyClosedTab]) {
        self.init(tabs: tabs, droppingPoint: nil, contentSize: nil)
    }
}

final class WindowControllersManagerMock: WindowControllersManagerProtocol {

    var stateChanged: AnyPublisher<Void, Never> = Empty().eraseToAnyPublisher()

    var mainWindowControllers: [DuckDuckGo_Privacy_Browser.MainWindowController] = []

    var pinnedTabsManagerProvider: PinnedTabsManagerProviding = PinnedTabsManagerProvidingMock()

    var didRegisterWindowController = PassthroughSubject<(MainWindowController), Never>()
    var didUnregisterWindowController = PassthroughSubject<(MainWindowController), Never>()

    func register(_ windowController: MainWindowController) {}
    func unregister(_ windowController: MainWindowController) {}

    var customAllTabCollectionViewModels: [TabCollectionViewModel]?
    var allTabCollectionViewModels: [TabCollectionViewModel] {
        if let customAllTabCollectionViewModels {
            return customAllTabCollectionViewModels
        } else {
            // The default implementation
            return mainWindowControllers.map {
                $0.mainViewController.tabCollectionViewModel
            }
        }
    }

    var lastKeyMainWindowController: MainWindowController?

    struct ShowArgs: Equatable {
        let url: URL?, source: Tab.TabContent.URLSource, newTab: Bool, selected: Bool?
    }
    var showCalled: ShowArgs?
    func show(url: URL?, tabId: String?, source: Tab.TabContent.URLSource, newTab: Bool, selected: Bool?) {
        showCalled = .init(url: url, source: source, newTab: newTab, selected: selected)
    }
    var showBookmarksTabCalled = false
    func showBookmarksTab() {
        showBookmarksTabCalled = true
    }

    struct OpenNewWindowArgs: Equatable {
        var contents: [TabContent]?
        var burnerMode: BurnerMode = .regular, droppingPoint: NSPoint?, contentSize: NSSize?, showWindow: Bool = true, popUp: Bool = false, lazyLoadTabs: Bool = false, isMiniaturized: Bool = false, isMaximized: Bool = false, isFullscreen: Bool = false
    }
    var openNewWindowCalled: OpenNewWindowArgs?
    @discardableResult
    func openNewWindow(with tabCollectionViewModel: DuckDuckGo_Privacy_Browser.TabCollectionViewModel?, burnerMode: DuckDuckGo_Privacy_Browser.BurnerMode, droppingPoint: NSPoint?, contentSize: NSSize?, showWindow: Bool, popUp: Bool, lazyLoadTabs: Bool, isMiniaturized: Bool, isMaximized: Bool, isFullscreen: Bool) -> DuckDuckGo_Privacy_Browser.MainWindow? {
        openNewWindowCalled = .init(contents: tabCollectionViewModel?.tabs.map(\.content), burnerMode: burnerMode, droppingPoint: droppingPoint, contentSize: contentSize, showWindow: showWindow, popUp: popUp, lazyLoadTabs: lazyLoadTabs, isMiniaturized: isMiniaturized, isMaximized: isMaximized, isFullscreen: isFullscreen)
        return nil
    }

    func open(_ url: URL, source: DuckDuckGo_Privacy_Browser.Tab.TabContent.URLSource, target window: NSWindow?, event: NSEvent?) {
        openCalls.append(.init(url, source, window, event))
    }
    func showTab(with content: DuckDuckGo_Privacy_Browser.Tab.TabContent) {
        showTabCalls.append(content)
    }

    func openAIChat(_ url: URL, with linkOpenBehavior: LinkOpenBehavior) {}
    func openAIChat(_ url: URL, with linkOpenBehavior: LinkOpenBehavior, hasPrompt: Bool) {}

    var showTabCalls: [Tab.TabContent] = []

    struct Open: Equatable {
        let url: URL
        let source: Tab.TabContent.URLSource
        let target: NSWindow?
        let event: NSEvent?

        init(_ url: URL, _ source: Tab.TabContent.URLSource, _ target: NSWindow? = nil, _ event: NSEvent? = nil) {
            self.url = url
            self.source = source
            self.target = target
            self.event = event
        }

        static func == (lhs: Open, rhs: Open) -> Bool {
            return lhs.url == rhs.url && lhs.source == rhs.source && lhs.target === rhs.target && lhs.event === rhs.event
        }
    }
    var openCalls: [Open] = []
}
