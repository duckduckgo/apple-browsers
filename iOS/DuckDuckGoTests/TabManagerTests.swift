//
//  TabManagerTests.swift
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

import BrowserServicesKit
import Persistence
import BrowserServicesKitTestsUtils
import Combine
import ConcurrencyExtensions
import Core
import PersistenceTestingUtils
import SubscriptionTestingUtilities
import XCTest
@testable import DuckDuckGo

@MainActor
final class TabManagerTests: XCTestCase {

    override func tearDown() {
        UserDefaults.app.removeObject(forKey: FireModeCapability.isFireModeEnabledKey)
        UserDefaults.app.removeObject(forKey: UserDefaultsWrapper<Bool>.Key.faviconTabsCacheNeedsCleanup.rawValue)
        super.tearDown()
    }

    func testWhenClosingOnlyOpenTabThenASingleEmptyTabIsAdded() async throws {

        let tabsModel = TabsModel(desktop: false)
        XCTAssertEqual(1, tabsModel.count)

        let originalTab = try XCTUnwrap(tabsModel.get(tabAt: 0))
        XCTAssertTrue(originalTab === tabsModel.get(tabAt: 0))

        let manager = try makeManager(tabsModel)
        manager.remove(tab: originalTab)

        XCTAssertEqual(1, tabsModel.count)
        XCTAssertFalse(originalTab === tabsModel.get(tabAt: 0))
    }

    func testWhenTabOpenedFromOtherTabThenRemovingTabSetsIndexToPreviousTab() async throws {
        let tabsModel = TabsModel(desktop: false)
        let exampleTab = Tab(link: Link(title: "example", url: URL(string: "https://example.com")!))
        tabsModel.insert(tab: exampleTab, placement: .atEnd, selectNewTab: true)
        tabsModel.insert(tab: Tab(), placement: .atEnd, selectNewTab: true)
        XCTAssertEqual(3, tabsModel.count)

        tabsModel.select(tab: exampleTab)

        let manager = try makeManager(tabsModel)

        // We expect the new tab to be the index after whatever was current (ie zero)
        XCTAssertEqual(1, tabsModel.currentIndex)
        XCTAssertEqual("https://example.com", tabsModel.tabs[1].link?.url.absoluteString)

        XCTAssertEqual(3, tabsModel.count)

        manager.remove(tab: exampleTab)
        // We expect the new current index to be the previous index
        XCTAssertEqual(0, tabsModel.currentIndex)
    }

    func testWhenAppBecomesActiveAndExcessPreviewsThenCleanUpHappens() async throws {
        let mock = MockTabPreviewsSource(totalStoredPreviews: 5)
        let tabsModel = TabsModel(desktop: false)
        let fireModel = TabsModel(desktop: false, mode: .fire)
        tabsModel.insert(tab: Tab(), placement: .atEnd, selectNewTab: false)
        fireModel.insert(tab: Tab(fireTab: true), placement: .atEnd, selectNewTab: false)
        let manager = try makeManager(tabsModel, fireModel: fireModel, previewsSource: mock)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        try await Task.sleep(interval: 0.5)
        XCTAssertEqual(1, mock.removePreviewsWithIdNotInCalls.count)

        // This is just to keep a reference to the manager to supress the unused warning and keep it from being deinit
        manager.removeAll()
    }

    // MARK: - Tab History Cleanup Tests
    
    func testWhenTabRemoved_ThenTabHistoryIsCleared() async throws {
        let tabsModel = TabsModel(desktop: false)
        let tabToRemove = Tab(link: Link(title: "example", url: URL(string: "https://example.com")!))
        tabsModel.insert(tab: tabToRemove, placement: .atEnd, selectNewTab: true)
        let tabID = tabToRemove.uid
        
        let mockHistoryManager = MockHistoryManager()
        mockHistoryManager.removeTabHistoryExpectation = expectation(description: "removeTabHistory called")
        let manager = try makeManager(tabsModel, historyManager: mockHistoryManager)
        
        manager.remove(tab: tabToRemove)
        
        await fulfillment(of: [mockHistoryManager.removeTabHistoryExpectation!], timeout: 5.0)
        
        XCTAssertEqual(mockHistoryManager.removeTabHistoryCalls.count, 1)
        XCTAssertEqual(mockHistoryManager.removeTabHistoryCalls.first, [tabID])
    }
    
    func testWhenAllTabsRemoved_ThenTabHistoryIsCleared() async throws {
        let tabsModel = TabsModel(desktop: false)
        let initialTab = try XCTUnwrap(tabsModel.tabs.first)
        let tab1 = Tab(link: Link(title: "example1", url: URL(string: "https://example1.com")!))
        tabsModel.insert(tab: tab1, placement: .atEnd, selectNewTab: true)
        let tabIDs = [initialTab.uid, tab1.uid]
        
        let mockHistoryManager = MockHistoryManager()
        mockHistoryManager.removeTabHistoryExpectation = expectation(description: "removeTabHistory called")
        let manager = try makeManager(tabsModel, historyManager: mockHistoryManager)
        
        manager.removeAll()
        
        await fulfillment(of: [mockHistoryManager.removeTabHistoryExpectation!], timeout: 5.0)
        
        XCTAssertEqual(mockHistoryManager.removeTabHistoryCalls.count, 1)
        XCTAssertEqual(Set(mockHistoryManager.removeTabHistoryCalls.first ?? []), Set(tabIDs))
    }

    func testWhenTabRemoved_ThenTabsFaviconCacheMarkedForCleanup() throws {
        let tabsModel = TabsModel(desktop: false)
        let tabToRemove = Tab(link: Link(title: "example", url: URL(string: "https://example.com")!))
        tabsModel.insert(tab: tabToRemove, placement: .atEnd, selectNewTab: true)

        let manager = try makeManager(tabsModel)

        manager.tabsCacheNeedsCleanup = false

        manager.remove(tab: tabToRemove)

        XCTAssertTrue(manager.tabsCacheNeedsCleanup,
                      "Removing a tab should flag the tabs favicon cache for cleanup so orphaned favicons are swept on next launch")
    }

    func testWhenViewModelRequested_ThenReturnsViewModelForTab() throws {
        let tabsModel = TabsModel(desktop: false)
        let tab = try XCTUnwrap(tabsModel.get(tabAt: 0))
        
        let mockHistoryManager = MockHistoryManager()
        let manager = try makeManager(tabsModel, historyManager: mockHistoryManager)
        
        let viewModel = manager.viewModel(for: tab)
        
        XCTAssertEqual(viewModel.tab.uid, tab.uid)
    }

    func testWhenFireModeResolvedAtLaunchThenMidSessionFlagChangeDoesNotAffectBrowsingMode() throws {
        let tabsModel = TabsModel(desktop: false)
        let flagger = MockFeatureFlagger()
        flagger.enabledFeatureFlags = [.fireMode]
        let manager = try makeManager(tabsModel, featureFlagger: flagger)

        manager.setBrowsingMode(.fire, source: .tabSelection)
        XCTAssertEqual(manager.currentBrowsingMode, .fire)

        // Simulate the feature flag source changing mid-session;
        // the resolved value in UserDefaults should remain unchanged.
        flagger.enabledFeatureFlags = []

        XCTAssertEqual(manager.currentBrowsingMode, .fire,
                       "Browsing mode should remain .fire because the capability was resolved at launch")
    }

    // MARK: - Fire Mode Zero Tabs

    func testWhenFireModeRemoveAllThenTabsIsEmpty() throws {
        let fireModel = TabsModel(tabs: [
            Tab(link: Link(title: "url1", url: URL(string: "https://url1.com")!), fireTab: true),
            Tab(link: Link(title: "url2", url: URL(string: "https://url2.com")!), fireTab: true)
        ], desktop: false, mode: .fire)
        let normalModel = TabsModel(desktop: false)
        let flagger = MockFeatureFlagger()
        flagger.enabledFeatureFlags = [.fireMode]
        let manager = try makeManager(normalModel, fireModel: fireModel, featureFlagger: flagger)
        manager.setBrowsingMode(.fire, source: .tabSelection)

        XCTAssertEqual(manager.currentTabsModel.count, 2)

        manager.removeAll()

        XCTAssertEqual(manager.currentTabsModel.count, 0)
        XCTAssertNil(manager.currentTabsModel.currentTab)
    }

    func testWhenFireModeCurrentWithCreateIfNeededFalseAndNoTabsThenReturnsNil() throws {
        let fireModel = TabsModel(desktop: false, mode: .fire)
        let normalModel = TabsModel(desktop: false)
        let flagger = MockFeatureFlagger()
        flagger.enabledFeatureFlags = [.fireMode]
        let manager = try makeManager(normalModel, fireModel: fireModel, featureFlagger: flagger)
        manager.setBrowsingMode(.fire, source: .tabSelection)

        XCTAssertEqual(manager.currentTabsModel.count, 0)
        XCTAssertNil(manager.current(createIfNeeded: false))
    }

    func testWhenFireModeRemoveOnlyTabThenTabsIsEmpty() throws {
        let tab = Tab(link: Link(title: "url1", url: URL(string: "https://url1.com")!), fireTab: true)
        let fireModel = TabsModel(tabs: [tab], desktop: false, mode: .fire)
        let normalModel = TabsModel(desktop: false)
        let flagger = MockFeatureFlagger()
        flagger.enabledFeatureFlags = [.fireMode]
        let manager = try makeManager(normalModel, fireModel: fireModel, featureFlagger: flagger)
        manager.setBrowsingMode(.fire, source: .tabSelection)

        XCTAssertEqual(manager.currentTabsModel.count, 1)

        manager.remove(tab: tab)

        XCTAssertEqual(manager.currentTabsModel.count, 0)
        XCTAssertNil(manager.currentTabsModel.currentTab)
    }

    func testWhenFireModeReplaceOnlyTabThenNewTabIsInserted() throws {
        let oldTab = Tab(link: Link(title: "old", url: URL(string: "https://old.com")!), fireTab: true)
        let fireModel = TabsModel(tabs: [oldTab], desktop: false, mode: .fire)
        let normalModel = TabsModel(desktop: false)
        let flagger = MockFeatureFlagger()
        flagger.enabledFeatureFlags = [.fireMode]
        let manager = try makeManager(normalModel, fireModel: fireModel, featureFlagger: flagger)
        manager.setBrowsingMode(.fire, source: .tabSelection)

        let newTab = Tab(fireTab: true)
        manager.replace(tab: oldTab, withNewTab: newTab)

        XCTAssertEqual(manager.currentTabsModel.count, 1)
        XCTAssertTrue(manager.currentTabsModel.tabs[0] === newTab)
    }

    func testWhenRemovingFireTabWhileCurrentModeIsNormalThenFireTabIsRemovedFromFireModel() throws {
        // Guards the escape-hatch burn-immediate crash: `remove(tab:)` must target
        // the tab's own `tab.mode` model, not `currentTabsModel`, or
        // `TabsModel.validateTabMode` asserts when burning a fire tab from normal mode.
        let fireTab = Tab(link: Link(title: "fire-target", url: URL(string: "https://fire-target.com")!), fireTab: true)
        let normalTab = Tab(link: Link(title: "normal-current", url: URL(string: "https://normal-current.com")!))
        let fireModel = TabsModel(tabs: [fireTab], desktop: false, mode: .fire)
        let normalModel = TabsModel(tabs: [normalTab], desktop: false)
        let flagger = MockFeatureFlagger()
        flagger.enabledFeatureFlags = [.fireMode]
        let manager = try makeManager(normalModel, fireModel: fireModel, featureFlagger: flagger)
        manager.setBrowsingMode(.normal, source: .tabSelection)

        XCTAssertEqual(manager.tabsModel(for: .fire).count, 1)
        XCTAssertEqual(manager.tabsModel(for: .normal).count, 1)
        XCTAssertEqual(manager.currentBrowsingMode, .normal)

        manager.remove(tab: fireTab)

        XCTAssertEqual(manager.tabsModel(for: .fire).count, 0, "Fire tab should be removed from the fire model")
        XCTAssertEqual(manager.tabsModel(for: .normal).count, 1, "Normal model should be untouched")
        XCTAssertTrue(manager.tabsModel(for: .normal).tabs.first === normalTab, "Normal model should still contain the original tab instance")
    }

    // MARK: - removeAll(browsingMode:) Isolation

    func testWhenRemoveAllWithFireMode() throws {
        let normalTab = Tab(link: Link(title: "normal", url: URL(string: "https://normal.com")!))
        let fireTab = Tab(link: Link(title: "fire", url: URL(string: "https://fire.com")!), fireTab: true)
        let normalModel = TabsModel(tabs: [normalTab], desktop: false)
        let fireModel = TabsModel(tabs: [fireTab], desktop: false, mode: .fire)
        let mockPreviews = MockTabPreviewsSource()

        let manager = try makeManager(normalModel, fireModel: fireModel, previewsSource: mockPreviews)

        manager.removeAll(browsingMode: .fire)

        // Previews preserved
        XCTAssertEqual(mockPreviews.removePreviewsWithIdNotInCalls.count, 1)
        let preservedIDs = mockPreviews.removePreviewsWithIdNotInCalls.first
        XCTAssertEqual(preservedIDs, Set([normalTab.uid]))
        
        // Normal tabs untouched
        XCTAssertEqual(fireModel.count, 0)
        XCTAssertEqual(normalModel.count, 1)
        XCTAssertEqual(normalModel.tabs.first?.link?.url.absoluteString, "https://normal.com")
    }

    func testWhenRemoveAllWithNilPreserveNothing() throws {
        let normalTab = Tab(link: Link(title: "normal", url: URL(string: "https://normal.com")!))
        let fireTab = Tab(link: Link(title: "fire", url: URL(string: "https://fire.com")!), fireTab: true)
        let normalModel = TabsModel(tabs: [normalTab], desktop: false)
        let fireModel = TabsModel(tabs: [fireTab], desktop: false, mode: .fire)
        let mockPreviews = MockTabPreviewsSource()

        let manager = try makeManager(normalModel, fireModel: fireModel, previewsSource: mockPreviews)

        manager.removeAll(browsingMode: nil)

        // Previews removed
        XCTAssertEqual(mockPreviews.removePreviewsWithIdNotInCalls.count, 1)
        let preservedIDs = mockPreviews.removePreviewsWithIdNotInCalls.first
        XCTAssertTrue(preservedIDs?.isEmpty ?? false)
        
        // All tabs removed
        XCTAssertEqual(fireModel.count, 0)
        XCTAssertEqual(normalModel.count, 1)
        XCTAssertNil(normalModel.tabs.first?.link?.url.absoluteString)
    }

    // MARK: - Save debouncing

    func testSave_coalescesBurst_writesOnce() throws {
        let countingStore = CountingThrowingKeyValueStore()
        let tabsModel = TabsModel(desktop: false)
        tabsModel.insert(tab: Tab(link: Link(title: "a", url: URL(string: "https://a.com")!)),
                         placement: .atEnd, selectNewTab: false)
        let flagger = MockFeatureFlagger()
        flagger.enabledFeatureFlags = [.tabsSaveOptimization]
        let manager = try makeManager(tabsModel, featureFlagger: flagger, normalStore: countingStore)

        for _ in 0..<10 {
            manager.save()
        }

        // Wait for the debounce window (300 ms) + persist queue.
        let debounceWindow = expectation(description: "debounce settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { debounceWindow.fulfill() }
        wait(for: [debounceWindow], timeout: 2.0)

        XCTAssertEqual(countingStore.setCount, 1, "10 rapid save() calls should coalesce into 1 disk write")
    }

    func testSave_firesWithinMaxWaitUnderSustainedActivity() throws {
        let countingStore = CountingThrowingKeyValueStore()
        let tabsModel = TabsModel(desktop: false)
        tabsModel.insert(tab: Tab(link: Link(title: "a", url: URL(string: "https://a.com")!)),
                         placement: .atEnd, selectNewTab: false)
        let flagger = MockFeatureFlagger()
        flagger.enabledFeatureFlags = [.tabsSaveOptimization]
        let manager = try makeManager(tabsModel, featureFlagger: flagger, normalStore: countingStore)

        // Drive save() faster than the debounce window for ~1.5 s.
        let start = Date()
        let firingDone = expectation(description: "sustained activity loop")
        func keepCalling() {
            manager.save()
            if Date().timeIntervalSince(start) < 1.5 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: keepCalling)
            } else {
                firingDone.fulfill()
            }
        }
        keepCalling()
        wait(for: [firingDone], timeout: 3.0)

        // Allow the persist queue to drain.
        let drain = expectation(description: "queue drain")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { drain.fulfill() }
        wait(for: [drain], timeout: 2.0)

        XCTAssertGreaterThanOrEqual(countingStore.setCount, 1,
                                    "max-wait should force at least one write within ~1 s of sustained saves")
    }

    func testFlushPendingSave_writesImmediately() throws {
        let countingStore = CountingThrowingKeyValueStore()
        let tabsModel = TabsModel(desktop: false)
        tabsModel.insert(tab: Tab(link: Link(title: "a", url: URL(string: "https://a.com")!)),
                         placement: .atEnd, selectNewTab: false)
        let flagger = MockFeatureFlagger()
        flagger.enabledFeatureFlags = [.tabsSaveOptimization]
        let manager = try makeManager(tabsModel, featureFlagger: flagger, normalStore: countingStore)

        manager.save()
        // No wait. flushPendingSave should drain synchronously.
        _ = manager.flushPendingSave()

        XCTAssertGreaterThanOrEqual(countingStore.setCount, 1,
                                    "flushPendingSave should write synchronously without waiting for debounce")
    }

    func makeManager(_ model: TabsModel,
                     fireModel: TabsModel? = nil,
                     previewsSource: TabPreviewsSource = MockTabPreviewsSource(),
                     historyManager: MockHistoryManager = MockHistoryManager(),
                     featureFlagger: MockFeatureFlagger = MockFeatureFlagger(),
                     launchSourceManager: LaunchSourceManaging = MockLaunchSourceManager(),
                     normalStore: ThrowingKeyValueStoring? = nil) throws -> TabManager {
        FireModeCapability.resolve(using: featureFlagger)
        let normalStore = try normalStore ?? MockKeyValueFileStore(throwOnInit: nil)
        let tabsPersistence = TabsModelPersistence(normalStore: normalStore,
                                                   fireStore: MockKeyValueFileStore(),
                                                   legacyStore: MockKeyValueStore())
        let fireModel = fireModel ?? TabsModel(tabs: [], desktop: false, mode: .fire)
        let modelProvider = TabsModelProvider(normalTabsModel: model, fireModeTabsModel: fireModel, persistence: tabsPersistence)
        return TabManager(tabsModelProvider: modelProvider,
                          previewsSource: previewsSource,
                          interactionStateSource: TabInteractionStateDiskSource(),
                          privacyConfigurationManager: MockPrivacyConfigurationManager(),
                          bookmarksDatabase: MockBookmarksDatabase.make(prepareFolderStructure: false),
                          historyManager: historyManager,
                          syncService: MockDDGSyncing(),
                          userScriptsDependencies: DefaultScriptSourceProvider.Dependencies.makeMock(),
                          contentBlockingAssetsPublisher: PassthroughSubject<ContentBlockingUpdating.NewContent, Never>().eraseToAnyPublisher(),
                          subscriptionDataReporter: MockSubscriptionDataReporter(),
                          contextualOnboardingPresenter: ContextualOnboardingPresenterMock(),
                          contextualOnboardingLogic: ContextualOnboardingLogicMock(),
                          onboardingPixelReporter: OnboardingPixelReporterMock(),
                          featureFlagger: featureFlagger,
                          contentScopeExperimentManager: MockContentScopeExperimentManager(),
                          appSettings: AppSettingsMock(),
                          textZoomCoordinatorProvider: MockTextZoomCoordinatorProvider(),
                          autoconsentManagementProvider: MockAutoconsentManagementProvider(),
                          websiteDataManager: MockWebsiteDataManager(),
                          fireproofing: MockFireproofing(),
                          favicons: Favicons(),
                          maliciousSiteProtectionManager: MockMaliciousSiteProtectionManager(),
                          maliciousSiteProtectionPreferencesManager: MockMaliciousSiteProtectionPreferencesManager(),
                          featureDiscovery: MockFeatureDiscovery(),
                          keyValueStore: MockKeyValueFileStore(),
                          daxDialogsManager: MockDaxDialogsManager(),
                          aiChatSettings: MockAIChatSettingsProvider(),
                          productSurfaceTelemetry: MockProductSurfaceTelemetry(),
                          privacyStats: MockPrivacyStats(),
                          voiceSearchHelper: MockVoiceSearchHelper(),
                          launchSourceManager: launchSourceManager,
                          darkReaderFeatureSettings: MockDarkReaderFeatureSettings(),
                          adBlockingAvailability: StubAdBlockingAvailability())
    }

}

/// Counts `set` calls so tests can assert how many disk writes actually landed.
private final class CountingThrowingKeyValueStore: ThrowingKeyValueStoring, @unchecked Sendable {
    private(set) var setCount = 0
    private(set) var storedValue: Any?
    private let lock = NSLock()

    func object(forKey defaultName: String) throws -> Any? {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func set(_ value: Any?, forKey defaultName: String) throws {
        lock.lock()
        setCount += 1
        storedValue = value
        lock.unlock()
    }

    func removeObject(forKey defaultName: String) throws {
        lock.lock()
        storedValue = nil
        lock.unlock()
    }
}
