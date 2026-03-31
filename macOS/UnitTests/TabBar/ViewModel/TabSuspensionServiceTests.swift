//
//  TabSuspensionServiceTests.swift
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

import PrivacyConfig
import XCTest

@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class TabSuspensionServiceTests: XCTestCase {

    private var featureFlagger: MockFeatureFlagger!
    private var windowControllersManager: WindowControllersManagerMock!
    private var now: Date!
    private var tabExtensionsBuilder: TestTabExtensionsBuilder!
    private var notificationCenter: NotificationCenter!

    private var sut: TabSuspensionService!

    override func setUp() {
        super.setUp()
        featureFlagger = MockFeatureFlagger()
        now = Date()
        tabExtensionsBuilder = TestTabExtensionsBuilder(load: [TabSuspensionExtension.self])
        notificationCenter = NotificationCenter()
    }

    override func tearDown() {
        sut = nil
        featureFlagger = nil
        windowControllersManager = nil
        now = nil
        tabExtensionsBuilder = nil
        notificationCenter = nil
        super.tearDown()
    }

    private func makeSUT(tabCollectionViewModels: [TabCollectionViewModel]) -> TabSuspensionService {
        windowControllersManager = WindowControllersManagerMock(tabCollectionViewModels: tabCollectionViewModels)
        return TabSuspensionService(
            windowControllersManager: windowControllersManager,
            featureFlagger: featureFlagger,
            notificationCenter: notificationCenter,
            dateProvider: { [unowned self] in self.now }
        )
    }

    private func makeTabCollectionViewModel(tabs: [Tab]) -> TabCollectionViewModel {
        let tabCollection = TabCollection(tabs: tabs)
        return TabCollectionViewModel(tabCollection: tabCollection, pinnedTabsManagerProvider: PinnedTabsManagerProvidingMock())
    }

    private func postMemoryPressure() {
        notificationCenter.post(name: .memoryPressureCritical, object: nil)
    }

    // MARK: - Feature Flag

    func testWhenFeatureFlagDisabled_ThenMemoryPressureDoesNotSuspendTabs() {
        featureFlagger.enabledFeatureFlags = []
        let tab = Tab(content: .url(.duckDuckGo, credential: nil, source: .link), extensionsBuilder: tabExtensionsBuilder, featureFlagger: featureFlagger, lastSelectedAt: now.addingTimeInterval(-20 * 60))
        let vm = makeTabCollectionViewModel(tabs: [tab])
        sut = makeSUT(tabCollectionViewModels: [vm])

        // Select tab 0 so suspendTab would skip it, then add another tab and select it
        // Actually we need 2 tabs so the first one isn't selected
        let selectedTab = Tab(content: .newtab)
        vm.append(tab: selectedTab)
        vm.select(at: .unpinned(1))

        postMemoryPressure()

        XCTAssertFalse(tab.isSuspended)
    }

    func testWhenFeatureFlagEnabled_ThenMemoryPressureSuspendsTabs() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        let tab = Tab(content: .url(.duckDuckGo, credential: nil, source: .link), extensionsBuilder: tabExtensionsBuilder, featureFlagger: featureFlagger)
        let selectedTab = Tab(content: .newtab, extensionsBuilder: tabExtensionsBuilder, featureFlagger: featureFlagger, lastSelectedAt: now)
        let vm = makeTabCollectionViewModel(tabs: [tab, selectedTab])
        sut = makeSUT(tabCollectionViewModels: [vm])
        vm.select(at: .unpinned(1))
        tab.lastSelectedAt = now.addingTimeInterval(-20 * 60)

        postMemoryPressure()

        XCTAssert(vm.tabs.first?.isSuspended == true)
    }

    // MARK: - Inactive Interval

    func testWhenTabRecentlySelected_ThenItIsNotSuspended() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        // Tab selected 5 minutes ago (less than 10 min threshold)
        let tab = Tab(content: .url(.duckDuckGo, credential: nil, source: .link), extensionsBuilder: tabExtensionsBuilder, featureFlagger: featureFlagger, lastSelectedAt: now.addingTimeInterval(-5 * 60))
        let selectedTab = Tab(content: .newtab, extensionsBuilder: tabExtensionsBuilder, featureFlagger: featureFlagger, lastSelectedAt: now)
        let vm = makeTabCollectionViewModel(tabs: [tab, selectedTab])
        sut = makeSUT(tabCollectionViewModels: [vm])
        vm.select(at: .unpinned(1))

        postMemoryPressure()

        XCTAssertFalse(tab.isSuspended)
    }

    func testWhenTabHasNoLastSelectedAt_ThenItIsSuspended() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        let tab = Tab(content: .url(.duckDuckGo, credential: nil, source: .link), extensionsBuilder: tabExtensionsBuilder, featureFlagger: featureFlagger)
        let selectedTab = Tab(content: .newtab, extensionsBuilder: tabExtensionsBuilder, featureFlagger: featureFlagger)
        let vm = makeTabCollectionViewModel(tabs: [tab, selectedTab])
        sut = makeSUT(tabCollectionViewModels: [vm])
        vm.select(at: .unpinned(1))
        tab.lastSelectedAt = nil

        postMemoryPressure()

        // Tabs with no lastSelectedAt were never selected — they should be suspended
        XCTAssert(vm.tabs.first?.isSuspended == true)
    }

    // MARK: - Burner Tabs

    func testWhenViewModelIsBurner_ThenTabsAreNotSuspended() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        let burnerMode = BurnerMode(isBurner: true)
        let tab = Tab(content: .url(.duckDuckGo, credential: nil, source: .link), extensionsBuilder: tabExtensionsBuilder, featureFlagger: featureFlagger, burnerMode: burnerMode, lastSelectedAt: now.addingTimeInterval(-20 * 60))
        let selectedTab = Tab(content: .newtab, extensionsBuilder: tabExtensionsBuilder, featureFlagger: featureFlagger, burnerMode: burnerMode, lastSelectedAt: now)
        let tabCollection = TabCollection(tabs: [tab, selectedTab])
        let vm = TabCollectionViewModel(tabCollection: tabCollection, pinnedTabsManagerProvider: PinnedTabsManagerProvidingMock(), burnerMode: burnerMode)
        sut = makeSUT(tabCollectionViewModels: [vm])
        vm.select(at: .unpinned(1))

        postMemoryPressure()

        XCTAssertFalse(tab.isSuspended)
    }

    // MARK: - Already Suspended

    func testWhenTabAlreadySuspended_ThenItIsSkipped() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        let tab = Tab(content: .url(.duckDuckGo, credential: nil, source: .link), extensionsBuilder: tabExtensionsBuilder, featureFlagger: featureFlagger, isSuspended: true, lastSelectedAt: now.addingTimeInterval(-20 * 60))
        let selectedTab = Tab(content: .newtab, extensionsBuilder: tabExtensionsBuilder, featureFlagger: featureFlagger, lastSelectedAt: now)
        let vm = makeTabCollectionViewModel(tabs: [tab, selectedTab])
        sut = makeSUT(tabCollectionViewModels: [vm])
        vm.select(at: .unpinned(1))

        postMemoryPressure()

        // Tab should remain suspended (not double-suspended)
        XCTAssertTrue(tab.isSuspended)
    }

    // MARK: - Date Provider

    func testDateProviderIsUsedForCutoffCalculation() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        // Tab selected 15 minutes ago
        let tabSelectedAt = now.addingTimeInterval(-15 * 60)
        let tab = Tab(content: .url(.duckDuckGo, credential: nil, source: .link), extensionsBuilder: tabExtensionsBuilder, featureFlagger: featureFlagger, lastSelectedAt: tabSelectedAt)
        let selectedTab = Tab(content: .newtab, extensionsBuilder: tabExtensionsBuilder, featureFlagger: featureFlagger, lastSelectedAt: now)
        let vm = makeTabCollectionViewModel(tabs: [tab, selectedTab])
        sut = makeSUT(tabCollectionViewModels: [vm])
        vm.select(at: .unpinned(1))

        // Move time back so the tab appears recently selected relative to "now"
        now = tabSelectedAt.addingTimeInterval(5 * 60)

        postMemoryPressure()

        // With the shifted date, the tab was selected only 5 minutes ago relative to "now" — should not be suspended
        XCTAssertFalse(tab.isSuspended)
    }
}
