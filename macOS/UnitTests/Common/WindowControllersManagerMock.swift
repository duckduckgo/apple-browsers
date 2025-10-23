//
//  WindowControllersManagerMock.swift
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

import Combine
import AIChat
@testable import DuckDuckGo_Privacy_Browser

typealias MockWindowControllerManager = WindowControllersManagerMock
final class WindowControllersManagerMock: WindowControllersManagerProtocol, AIChatTabManaging {
    var stateChanged: AnyPublisher<Void, Never> = Empty().eraseToAnyPublisher()
    var tabsChanged: AnyPublisher<Void, Never> = Empty().eraseToAnyPublisher()

    var mainWindowControllers: [DuckDuckGo_Privacy_Browser.MainWindowController] = []

    var pinnedTabsManagerProvider: PinnedTabsManagerProviding

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
    var selectedWindowIndex: Int
    var selectedTab: Tab? {
        allTabCollectionViewModels[selectedWindowIndex].selectedTab
    }

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

    struct OpenWindowCall: Equatable {
        let contents: [TabContent]?
        let burnerMode: BurnerMode
        let droppingPoint: NSPoint?
        let contentSize: NSSize?
        let showWindow: Bool
        let popUp: Bool
        let lazyLoadTabs: Bool
        let isMiniaturized: Bool
        let isMaximized: Bool
        let isFullscreen: Bool
    }
    var openWindowCalls: [OpenWindowCall] = []
    var onOpenNewWindow: ((OpenWindowCall) -> Void)?
    @discardableResult
    func openNewWindow(with tabCollectionViewModel: DuckDuckGo_Privacy_Browser.TabCollectionViewModel?, burnerMode: DuckDuckGo_Privacy_Browser.BurnerMode, droppingPoint: NSPoint?, contentSize: NSSize?, showWindow: Bool, popUp: Bool, lazyLoadTabs: Bool, isMiniaturized: Bool, isMaximized: Bool, isFullscreen: Bool) -> NSWindow? {
        let call = OpenWindowCall(
            contents: tabCollectionViewModel?.tabs.map(\.content),
            burnerMode: burnerMode,
            droppingPoint: droppingPoint,
            contentSize: contentSize,
            showWindow: showWindow,
            popUp: popUp,
            lazyLoadTabs: lazyLoadTabs,
            isMiniaturized: isMiniaturized,
            isMaximized: isMaximized,
            isFullscreen: isFullscreen
        )
        openWindowCalls.append(call)
        onOpenNewWindow?(call)
        return nil
    }

    func open(_ url: URL, source: DuckDuckGo_Privacy_Browser.Tab.TabContent.URLSource, target window: NSWindow?, event: NSEvent?) {
        openCalls.append(.init(url, source, window, event))
    }
    func showTab(with content: DuckDuckGo_Privacy_Browser.Tab.TabContent) {
        showTabCalls.append(content)
    }

    func openTab(_ tab: DuckDuckGo_Privacy_Browser.Tab, afterParentTab parentTab: DuckDuckGo_Privacy_Browser.Tab, selected: Bool) {
        openTabCalls.append(OpenTabCall(tab: tab, parentTab: parentTab, selected: selected))
    }

    // MARK: - AIChatTabManaging

    struct OpenAIChatCall: Equatable {
        let url: URL
        let behavior: LinkOpenBehavior
        let hasPrompt: Bool
    }
    var openAIChatCalls: [OpenAIChatCall] = []

    @MainActor
    func openAIChat(_ url: URL, with behavior: LinkOpenBehavior, hasPrompt: Bool) {
        openAIChatCalls.append(OpenAIChatCall(url: url, behavior: behavior, hasPrompt: hasPrompt))
    }

    struct InsertAIChatTabCall: Equatable {
        let url: URL
        let payload: AIChatPayload?
        let restorationData: AIChatRestorationData?

        static func == (lhs: InsertAIChatTabCall, rhs: InsertAIChatTabCall) -> Bool {
            return lhs.url == rhs.url &&
            (lhs.payload as? NSDictionary) == (rhs.payload as? NSDictionary) &&
            lhs.restorationData?.id == rhs.restorationData?.id
        }
    }
    var insertAIChatTabCalls: [InsertAIChatTabCall] = []

    @MainActor
    func insertAIChatTab(with url: URL, payload: AIChatPayload) {
        insertAIChatTabCalls.append(InsertAIChatTabCall(url: url, payload: payload, restorationData: nil))
    }

    @MainActor
    func insertAIChatTab(with url: URL, restorationData: AIChatRestorationData) {
        insertAIChatTabCalls.append(InsertAIChatTabCall(url: url, payload: nil, restorationData: restorationData))
    }

    var showTabCalls: [Tab.TabContent] = []
    struct OpenTabCall: Equatable {
        let tab: Tab
        let parentTab: Tab
        let selected: Bool
    }
    var openTabCalls: [OpenTabCall] = []

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

    init(pinnedTabsManagerProvider: PinnedTabsManagerProviding = PinnedTabsManagerProvidingMock(), tabCollectionViewModels: [TabCollectionViewModel]? = nil, selectedWindow: Int = 0) {
        self.pinnedTabsManagerProvider = pinnedTabsManagerProvider
        self.customAllTabCollectionViewModels = tabCollectionViewModels
        self.selectedWindowIndex = selectedWindow
    }

}
