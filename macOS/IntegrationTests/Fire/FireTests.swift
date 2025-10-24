//
//  FireTests.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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
import Foundation
import History
import os.log
import XCTest

@testable import DuckDuckGo_Privacy_Browser

@available(macOS 12.0, *)
final class FireTests: XCTestCase {

    var pinnedTabsManagerProvider: PinnedTabsManagerProvidingMock!
    var schemeHandler: TestSchemeHandler!
    var cancellables = Set<AnyCancellable>()
    static let testHtml = "<html><head><title>Title 1</title></head><body>test</body></html>"

    override func setUp() {
        schemeHandler = TestSchemeHandler { _ in
            return .ok(.html(Self.testHtml))
        }
        pinnedTabsManagerProvider = PinnedTabsManagerProvidingMock()
    }

    @MainActor
    override func tearDown() {
        schemeHandler = nil
        pinnedTabsManagerProvider = nil
        autoreleasepool {
            WindowsManager.closeWindows()
            for controller in Application.appDelegate.windowControllersManager.mainWindowControllers {
                Application.appDelegate.windowControllersManager.unregister(controller)
            }
            cancellables = []
        }
    }

    // MARK: - Tests

    @MainActor
    func testWhenBurnAll_WithExistingWindow_ThenWindowStaysOpenAndTabsAreCleared() {
        // When burning "Everything", keep window open and just close tabs + open a new tab
        let manager = WebCacheManagerMock()
        let historyCoordinator = HistoryCoordinatingMock()
        let permissionManager = PermissionManagerMock()
        let faviconManager = FaviconManagerMock()
        let visualizeFire = MockVisualizeFireAnimationDecider()
        visualizeFire.shouldShowFireAnimation = true

        let fire = Fire(cacheManager: manager,
                        historyCoordinating: historyCoordinator,
                        permissionManager: permissionManager,
                        windowControllersManager: Application.appDelegate.windowControllersManager,
                        faviconManagement: faviconManager,
                        tld: Application.appDelegate.tld,
                        visualizeFireAnimationDecider: visualizeFire,
                        isAppActiveProvider: { true })  // App is active - should manage windows

        let tabCollectionViewModel = TabCollectionViewModel.makeTabCollectionViewModel(with: pinnedTabsManagerProvider)
        var window: NSWindow! = WindowsManager.openNewWindow(with: tabCollectionViewModel, lazyLoadTabs: true)
        Logger.tests.info("\(self.name) opened \(window.windowController ??? "<nil>")")
        defer {
            window.close()
            window = nil
        }
        let windowCountBeforeBurning = Application.appDelegate.windowControllersManager.mainWindowControllers.count
        let windowControllersBeforeBurning = Set(Application.appDelegate.windowControllersManager.mainWindowControllers.map { ObjectIdentifier($0) })

        XCTAssertEqual(tabCollectionViewModel.tabCollection.tabs.count, 3)
        XCTAssertEqual(tabCollectionViewModel.tabCollection.tabs.first?.content, .newtab)
        XCTAssertGreaterThan(windowCountBeforeBurning, 0, "Should have at least one window before burning")

        let burningExpectation = expectation(description: "Burning")

        fire.burnAll {
            burningExpectation.fulfill()
        }

        wait(for: [burningExpectation], timeout: 5)

        // Verify: All old tabs cleared and a new tab was added to keep window open
        XCTAssertEqual(tabCollectionViewModel.tabCollection.tabs.count, 1,
                       "A new tab should be added to keep the window open (original 3 tabs cleared)")
        XCTAssertEqual(tabCollectionViewModel.tabCollection.tabs.first?.content, .newtab,
                       "New tab should be a newtab")

        // Verify: Window is still open (not closed and reopened)
        let windowCountAfterBurning = Application.appDelegate.windowControllersManager.mainWindowControllers.count
        XCTAssertEqual(windowCountAfterBurning, windowCountBeforeBurning,
                       "Window count should remain the same - window should not be closed and reopened")

        // Verify: The same window controller instances are still present
        let windowControllersAfterBurning = Set(Application.appDelegate.windowControllersManager.mainWindowControllers.map { ObjectIdentifier($0) })
        XCTAssertEqual(windowControllersBeforeBurning, windowControllersAfterBurning,
                      "Original window controllers should still be registered (not closed and reopened)")
    }

    @MainActor
    func testWhenBurnAll_WithNoExistingWindows_ThenNewWindowIsOpened() async {
        // When no windows exist, should still open a new window (preserve existing behavior)
        let manager = WebCacheManagerMock()
        let historyCoordinator = HistoryCoordinatingMock()
        let permissionManager = PermissionManagerMock()
        let faviconManager = FaviconManagerMock()

        let fire = Fire(cacheManager: manager,
                        historyCoordinating: historyCoordinator,
                        permissionManager: permissionManager,
                        windowControllersManager: Application.appDelegate.windowControllersManager,
                        faviconManagement: faviconManager,
                        pinnedTabsManagerProvider: pinnedTabsManagerProvider,
                        tld: Application.appDelegate.tld,
                        isAppActiveProvider: { true })  // App is active - should open new window

        // Ensure no windows exist
        XCTAssertEqual(Application.appDelegate.windowControllersManager.mainWindowControllers.count, 0,
                       "Should start with no windows")

        let burningExpectation = expectation(description: "Burning")

        fire.burnAll {
            burningExpectation.fulfill()
        }

        await fulfillment(of: [burningExpectation], timeout: 5)

        // Wait a bit for async window opening
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Verify: A new window was opened
        XCTAssertEqual(Application.appDelegate.windowControllersManager.mainWindowControllers.count, 1,
                       "A new window should be opened when no windows existed before burning")
    }

    @MainActor
    func testWhenBurnAll_WithAppInactive_ThenNoWindowIsOpened() async {
        // When app is inactive, should NOT open a new window even if none exist
        let manager = WebCacheManagerMock()
        let historyCoordinator = HistoryCoordinatingMock()
        let permissionManager = PermissionManagerMock()
        let faviconManager = FaviconManagerMock()

        let fire = Fire(cacheManager: manager,
                        historyCoordinating: historyCoordinator,
                        permissionManager: permissionManager,
                        windowControllersManager: Application.appDelegate.windowControllersManager,
                        faviconManagement: faviconManager,
                        pinnedTabsManagerProvider: pinnedTabsManagerProvider,
                        tld: Application.appDelegate.tld,
                        isAppActiveProvider: { false })  // App is INACTIVE - should NOT open window

        // Ensure no windows exist
        XCTAssertEqual(Application.appDelegate.windowControllersManager.mainWindowControllers.count, 0,
                       "Should start with no windows")

        let burningExpectation = expectation(description: "Burning")

        fire.burnAll {
            // Verify: NO window was opened (app is inactive)
            XCTAssertEqual(Application.appDelegate.windowControllersManager.mainWindowControllers.count, 0,
                           "No window should be opened when app is inactive")
            burningExpectation.fulfill()
        }

        await fulfillment(of: [burningExpectation], timeout: 5)
    }

    @MainActor
    func testWhenBurnAll_ThenPinnedTabsArePersisted() async {

        let manager = WebCacheManagerMock()
        let historyCoordinator = HistoryCoordinatingMock()
        let permissionManager = PermissionManagerMock()
        let faviconManager = FaviconManagerMock()

        let pinnedTabs: [Tab] = [
            .init(content: .url("https://duck.com/".url!, source: .link), webViewConfiguration: schemeHandler.webViewConfiguration()),
            .init(content: .url("https://spreadprivacy.com/".url!, source: .link), webViewConfiguration: schemeHandler.webViewConfiguration()),
            .init(content: .url("https://wikipedia.org/".url!, source: .link), webViewConfiguration: schemeHandler.webViewConfiguration())
        ]
        pinnedTabsManagerProvider.newPinnedTabsManager = PinnedTabsManager(tabCollection: .init(tabs: pinnedTabs))

        let fire = Fire(cacheManager: manager,
                        historyCoordinating: historyCoordinator,
                        permissionManager: permissionManager,
                        windowControllersManager: Application.appDelegate.windowControllersManager,
                        faviconManagement: faviconManager,
                        pinnedTabsManagerProvider: pinnedTabsManagerProvider,
                        tld: Application.appDelegate.tld)
        let tabCollectionViewModel = TabCollectionViewModel.makeTabCollectionViewModel(with: pinnedTabsManagerProvider)
        var window: NSWindow! = WindowsManager.openNewWindow(with: tabCollectionViewModel, lazyLoadTabs: true)
        Logger.tests.info("\(self.name) opened \(window.windowController ??? "<nil>")")
        defer {
            window.close()
            window = nil
        }

        let burningExpectation = expectation(description: "Burning")
        fire.burnAll {
            burningExpectation.fulfill()
        }

        await fulfillment(of: [burningExpectation], timeout: 5)

        // Verify: No new tab is inserted because pinned tabs exist (window stays open with pinned tabs only)
        XCTAssertEqual(tabCollectionViewModel.tabCollection.tabs.count, 0, "No new regular tab should be inserted when pinned tabs exist")
        XCTAssertEqual(pinnedTabsManagerProvider.newPinnedTabsManager.tabCollection.tabs.map(\.content.userEditableUrl), pinnedTabs.map(\.content.userEditableUrl), "Pinned tabs should be preserved")
    }

    @MainActor
    func testWhenBurnAll_ThenAllWebsiteDataAreRemoved() async {
        let manager = WebCacheManagerMock()
        let historyCoordinator = HistoryCoordinatingMock()
        let zoomLevelsCoordinator = MockSavedZoomCoordinator()
        let permissionManager = PermissionManagerMock()
        let faviconManager = FaviconManagerMock()
        let recentlyClosedCoordinator = RecentlyClosedCoordinatorMock()
        let visitedLinkStore = WKVisitedLinkStoreMock()

        let fire = Fire(cacheManager: manager,
                        historyCoordinating: historyCoordinator,
                        permissionManager: permissionManager,
                        savedZoomLevelsCoordinating: zoomLevelsCoordinator,
                        windowControllersManager: Application.appDelegate.windowControllersManager,
                        faviconManagement: faviconManager,
                        recentlyClosedCoordinator: recentlyClosedCoordinator,
                        pinnedTabsManagerProvider: pinnedTabsManagerProvider,
                        tld: Application.appDelegate.tld,
                        getVisitedLinkStore: { WKVisitedLinkStoreWrapper(visitedLinkStore: visitedLinkStore) })
        let tabCollectionViewModel = TabCollectionViewModel.makeTabCollectionViewModel(with: pinnedTabsManagerProvider)
        var window: NSWindow! = WindowsManager.openNewWindow(with: tabCollectionViewModel, lazyLoadTabs: true)
        Logger.tests.info("\(self.name) opened \(window.windowController ??? "<nil>")")
        defer {
            window.close()
            window = nil
        }

        let finishedBurningExpectation = expectation(description: "Finished burning")
        fire.burnAll {
            finishedBurningExpectation.fulfill()
        }

        await fulfillment(of: [finishedBurningExpectation], timeout: 5)
        XCTAssert(manager.clearCalled)
        XCTAssert(historyCoordinator.burnAllCalled)
        XCTAssert(permissionManager.burnPermissionsCalled)
        XCTAssert(recentlyClosedCoordinator.burnCacheCalled)
        XCTAssert(zoomLevelsCoordinator.burnAllZoomLevelsCalled)
        XCTAssertTrue(visitedLinkStore.removeAllCalled)
    }

    @MainActor
    func testWhenBurnAllThenBurningFlagToggles() async {
        let manager = WebCacheManagerMock()
        let historyCoordinator = HistoryCoordinatingMock()
        let permissionManager = PermissionManagerMock()
        let faviconManager = FaviconManagerMock()

        let fire = Fire(cacheManager: manager,
                        historyCoordinating: historyCoordinator,
                        permissionManager: permissionManager,
                        faviconManagement: faviconManager,
                        pinnedTabsManagerProvider: pinnedTabsManagerProvider,
                        tld: Application.appDelegate.tld)

        _ = TabCollectionViewModel.makeTabCollectionViewModel(with: pinnedTabsManagerProvider)

        let isBurningExpectation = expectation(description: "Burning")
        let finishedBurningExpectation = expectation(description: "Finished burning")

        fire.$burningData.dropFirst().sink { burningData in
            if burningData != nil {
                isBurningExpectation.fulfill()
            } else {
                finishedBurningExpectation.fulfill()
            }
        } .store(in: &cancellables)

        fire.burnAll(completion: {})

        await fulfillment(of: [isBurningExpectation, finishedBurningExpectation], timeout: 5)
    }

    @MainActor
    func testWhenBurnAllIsCalledThenLastSessionStateIsCleared() {
        let fileName = "testStateFileForBurningAllData"
        let fileStore = preparePersistedState(withFileName: fileName)
        let service = StatePersistenceService(fileStore: fileStore, fileName: fileName)
        let appStateRestorationManager = AppStateRestorationManager(fileStore: fileStore,
                                                                    service: service,
                                                                    startupPreferences: NSApp.delegateTyped.startupPreferences,
                                                                    keyValueStore: NSApp.delegateTyped.keyValueStore,
                                                                    sessionRestorePromptCoordinator: NSApp.delegateTyped.sessionRestorePromptCoordinator,
                                                                    pixelFiring: nil)
        appStateRestorationManager.applicationDidFinishLaunching()

        let fire = Fire(historyCoordinating: HistoryCoordinatingMock(),
                        stateRestorationManager: appStateRestorationManager,
                        pinnedTabsManagerProvider: pinnedTabsManagerProvider,
                        tld: Application.appDelegate.tld)

        XCTAssertTrue(appStateRestorationManager.canRestoreLastSessionState)
        fire.burnAll()
        XCTAssertFalse(appStateRestorationManager.canRestoreLastSessionState)
    }

    @MainActor
    func testWhenBurnDomainsIsCalledThenLastSessionStateIsCleared() {
        let fileName = "testStateFileForBurningAllData"
        let fileStore = preparePersistedState(withFileName: fileName)
        let service = StatePersistenceService(fileStore: fileStore, fileName: fileName)
        let appStateRestorationManager = AppStateRestorationManager(fileStore: fileStore,
                                                                    service: service,
                                                                    startupPreferences: NSApp.delegateTyped.startupPreferences,
                                                                    keyValueStore: NSApp.delegateTyped.keyValueStore,
                                                                    sessionRestorePromptCoordinator: NSApp.delegateTyped.sessionRestorePromptCoordinator,
                                                                    pixelFiring: nil)
        appStateRestorationManager.applicationDidFinishLaunching()

        let fire = Fire(historyCoordinating: HistoryCoordinatingMock(),
                        stateRestorationManager: appStateRestorationManager,
                        pinnedTabsManagerProvider: pinnedTabsManagerProvider,
                        tld: Application.appDelegate.tld)

        XCTAssertTrue(appStateRestorationManager.canRestoreLastSessionState)
        fire.burnEntity(.none(selectedDomains: Set()))
        XCTAssertFalse(appStateRestorationManager.canRestoreLastSessionState)
    }

    @MainActor
    func testWhenBurnDomainsIsCalledThenSelectedDomainsZoomLevelsAreBurned() {
        let domainsToBurn: Set<String> = ["test.com", "provola.co.uk"]
        let zoomLevelsCoordinator = MockSavedZoomCoordinator()
        let fire = Fire(savedZoomLevelsCoordinating: zoomLevelsCoordinator,
                        pinnedTabsManagerProvider: pinnedTabsManagerProvider,
                        tld: Application.appDelegate.tld)

        let finishedBurningExpectation = expectation(description: "Finished burning")
        fire.burnEntity(.none(selectedDomains: domainsToBurn)) {
            finishedBurningExpectation.fulfill()
        }

        waitForExpectations(timeout: 5)
        XCTAssertTrue(zoomLevelsCoordinator.burnZoomLevelsOfDomainsCalled)
        XCTAssertEqual(zoomLevelsCoordinator.domainsBurned, domainsToBurn)
    }

    @MainActor
    func testWhenBurnVisitIsCalledForTodayThenAllExistingTabsAreCleared() async {
        let manager = WebCacheManagerMock()
        let historyCoordinator = HistoryCoordinatingMock()
        let permissionManager = PermissionManagerMock()
        let faviconManager = FaviconManagerMock()
        let recentlyClosedCoordinator = RecentlyClosedCoordinatorMock()
        let visitedLinkStore = WKVisitedLinkStoreMock()

        let fire = Fire(cacheManager: manager,
                        historyCoordinating: historyCoordinator,
                        permissionManager: permissionManager,
                        windowControllersManager: Application.appDelegate.windowControllersManager,
                        faviconManagement: faviconManager,
                        recentlyClosedCoordinator: recentlyClosedCoordinator,
                        pinnedTabsManagerProvider: pinnedTabsManagerProvider,
                        tld: Application.appDelegate.tld,
                        getVisitedLinkStore: { WKVisitedLinkStoreWrapper(visitedLinkStore: visitedLinkStore) })
        let tabCollectionViewModel = TabCollectionViewModel.makeTabCollectionViewModel(with: pinnedTabsManagerProvider)
        var window: NSWindow! = WindowsManager.openNewWindow(with: tabCollectionViewModel, lazyLoadTabs: true)
        Logger.tests.info("\(self.name) opened \(window.windowController ??? "<nil>")")
        defer {
            window.close()
            window = nil
        }
        XCTAssertNotEqual(tabCollectionViewModel.allTabsCount, 0)

        let finishedBurningExpectation = expectation(description: "Finished burning")
        fire.burnVisits([],
                        except: Application.appDelegate.fireproofDomains,
                        isToday: true,
                        closeWindows: true,
                        clearSiteData: true,
                        clearChatHistory: false,
                        completion: {
            finishedBurningExpectation.fulfill()
        })

        await fulfillment(of: [finishedBurningExpectation], timeout: 5)
        // Verify: New empty tab is present to keep window open (original tabs were cleared)
        XCTAssertEqual(tabCollectionViewModel.allTabsCount, 1, "A new tab should be inserted to keep window open")
        XCTAssert(manager.clearCalled)
        XCTAssert(historyCoordinator.burnVisitsCalled)
        XCTAssertFalse(historyCoordinator.burnAllCalled)
        XCTAssert(permissionManager.burnPermissionsOfDomainsCalled)
        XCTAssertFalse(permissionManager.burnPermissionsCalled)
        XCTAssert(recentlyClosedCoordinator.burnCacheCalled)
        XCTAssertFalse(visitedLinkStore.removeAllCalled)
    }

    @MainActor
    func testWhenBurnVisitIsCalledForOtherDayThenExistingTabsRemainOpen() async {
        let manager = WebCacheManagerMock()
        let historyCoordinator = HistoryCoordinatingMock()
        let permissionManager = PermissionManagerMock()
        let faviconManager = FaviconManagerMock()
        let recentlyClosedCoordinator = RecentlyClosedCoordinatorMock()
        let visitedLinkStore = WKVisitedLinkStoreMock()

        let fire = Fire(cacheManager: manager,
                        historyCoordinating: historyCoordinator,
                        permissionManager: permissionManager,
                        windowControllersManager: Application.appDelegate.windowControllersManager,
                        faviconManagement: faviconManager,
                        recentlyClosedCoordinator: recentlyClosedCoordinator,
                        pinnedTabsManagerProvider: pinnedTabsManagerProvider,
                        tld: Application.appDelegate.tld,
                        getVisitedLinkStore: { WKVisitedLinkStoreWrapper(visitedLinkStore: visitedLinkStore) })
        let tabCollectionViewModel = TabCollectionViewModel.makeTabCollectionViewModel(with: pinnedTabsManagerProvider)
        var window: NSWindow! = WindowsManager.openNewWindow(with: tabCollectionViewModel, lazyLoadTabs: true)
        Logger.tests.info("\(self.name) opened \(window.windowController ??? "<nil>")")
        defer {
            window.close()
            window = nil
        }
        XCTAssertNotEqual(tabCollectionViewModel.allTabsCount, 0)
        let numberOfTabs = tabCollectionViewModel.allTabsCount

        let finishedBurningExpectation = expectation(description: "Finished burning")
        let historyEntries = [
            HistoryEntry(identifier: UUID(), url: .duckDuckGo, failedToLoad: false, numberOfTotalVisits: 1, lastVisit: Date(), visits: [], numberOfTrackersBlocked: 0, blockedTrackingEntities: [], trackersFound: false),
            HistoryEntry(identifier: UUID(), url: .duckDuckGoEmail, failedToLoad: false, numberOfTotalVisits: 1, lastVisit: Date(), visits: [], numberOfTrackersBlocked: 0, blockedTrackingEntities: [], trackersFound: false),
        ]
        fire.burnVisits([
            Visit(date: Date(), identifier: nil, historyEntry: historyEntries[0]),
            Visit(date: Date(), identifier: nil, historyEntry: historyEntries[1]),
        ],
                        except: Application.appDelegate.fireproofDomains,
                        isToday: false,
                        closeWindows: false,
                        clearSiteData: true,
                        clearChatHistory: false,
                        completion: {
            finishedBurningExpectation.fulfill()
        })

        await fulfillment(of: [finishedBurningExpectation], timeout: 5)
        XCTAssertEqual(tabCollectionViewModel.allTabsCount, numberOfTabs)
        XCTAssert(manager.clearCalled)
        XCTAssert(historyCoordinator.burnVisitsCalled)
        XCTAssertFalse(historyCoordinator.burnAllCalled)
        XCTAssert(permissionManager.burnPermissionsOfDomainsCalled)
        XCTAssertFalse(permissionManager.burnPermissionsCalled)
        XCTAssert(recentlyClosedCoordinator.burnCacheCalled)
        XCTAssertFalse(visitedLinkStore.removeAllCalled)
        XCTAssertEqual(visitedLinkStore.removeVisitedLinkCalledWithURLs, [.duckDuckGo, .duckDuckGoEmail])
    }

    @MainActor
    func testWhenBurnAllIsCalled_ChatHistoryIsCleared() async {
        let chatHistoryCleaner = MockAIChatHistoryCleaner()
        let fire = Fire(pinnedTabsManagerProvider: pinnedTabsManagerProvider,
                        tld: Application.appDelegate.tld,
                        aIChatHistoryCleaner: chatHistoryCleaner)

        let burningExpectation = expectation(description: "Burning")

        fire.burnAll {
            XCTAssertTrue(chatHistoryCleaner.didCleanAIChatHistory)
            burningExpectation.fulfill()
        }

        await fulfillment(of: [burningExpectation], timeout: 5)
    }

    @MainActor
    func testWhenBurnVisitsIsCalled_IncludingChatHistory_ChatHistoryIsCleared() async {
        let chatHistoryCleaner = MockAIChatHistoryCleaner()
        let fire = Fire(pinnedTabsManagerProvider: pinnedTabsManagerProvider,
                        tld: Application.appDelegate.tld,
                        aIChatHistoryCleaner: chatHistoryCleaner)

        let burningExpectation = expectation(description: "Burning")

        fire.burnVisits([],
                        except: Application.appDelegate.fireproofDomains,
                        isToday: false,
                        closeWindows: false,
                        clearSiteData: true,
                        clearChatHistory: true,
        ) {
            XCTAssertTrue(chatHistoryCleaner.didCleanAIChatHistory)
            burningExpectation.fulfill()
        }

        await fulfillment(of: [burningExpectation], timeout: 5)
    }

    @MainActor
    func testWhenBurnVisitsIsCalled_NotIncludingChatHistory_ChatHistoryIsNotCleared() async {
        let chatHistoryCleaner = MockAIChatHistoryCleaner()
        let fire = Fire(pinnedTabsManagerProvider: pinnedTabsManagerProvider,
                        tld: Application.appDelegate.tld,
                        aIChatHistoryCleaner: chatHistoryCleaner)

        let burningExpectation = expectation(description: "Burning")

        fire.burnVisits([],
                        except: Application.appDelegate.fireproofDomains,
                        isToday: false,
                        closeWindows: true,
                        clearSiteData: true,
                        clearChatHistory: false,
        ) {
            XCTAssertFalse(chatHistoryCleaner.didCleanAIChatHistory)
            burningExpectation.fulfill()
        }

        await fulfillment(of: [burningExpectation], timeout: 5)
    }

    @MainActor
    func preparePersistedState(withFileName fileName: String) -> FileStore {
        let fileStore = FileStoreMock()
        let state = SavedStateMock()
        state.val1 = "String"
        state.val2 = 0x8badf00d

        let serviceToPersistStateFile = StatePersistenceService(fileStore: fileStore, fileName: fileName)
        serviceToPersistStateFile.persistState(using: state.encode(with:), sync: true)

        return fileStore
    }

}

fileprivate extension TabCollectionViewModel {

    @MainActor
    static func makeTabCollectionViewModel(with pinnedTabsManagerProvider: PinnedTabsManagerProviding) -> TabCollectionViewModel {

        let tabCollectionViewModel = TabCollectionViewModel(tabCollection: .init(), pinnedTabsManagerProvider: pinnedTabsManagerProvider)
        tabCollectionViewModel.append(tab: Tab(content: .none))
        tabCollectionViewModel.append(tab: Tab(content: .none))
        return tabCollectionViewModel
    }

}

class MockSavedZoomCoordinator: SavedZoomLevelsCoordinating {
    var burnAllZoomLevelsCalled = false
    var burnZoomLevelsOfDomainsCalled = false
    var domainsBurned: Set<String> = []

    func burnZoomLevels(except fireproofDomains: DuckDuckGo_Privacy_Browser.FireproofDomains) {
        burnAllZoomLevelsCalled = true
    }

    func burnZoomLevel(of baseDomains: Set<String>) {
        burnZoomLevelsOfDomainsCalled = true
        domainsBurned = baseDomains
    }
}

private class WKVisitedLinkStoreMock: NSObject {

    private(set) var removeAllCalled = false
    @objc func removeAll() {
        removeAllCalled = true
    }

    private(set) var removeVisitedLinkCalledWithURLs = Set<URL>()
    @objc(removeVisitedLinkWithURL:)
    func removeVisitedLink(with url: URL) {
        removeVisitedLinkCalledWithURLs.insert(url)
    }

}
