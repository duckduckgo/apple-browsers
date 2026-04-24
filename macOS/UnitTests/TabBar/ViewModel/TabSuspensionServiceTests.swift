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

import PersistenceTestingUtils
import PixelKit
import PrivacyConfig
import PrivacyConfigTestsUtils
import XCTest

@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class TabSuspensionServiceTests: XCTestCase {

    private var featureFlagger: MockFeatureFlagger!
    private var windowControllersManager: WindowControllersManagerMock!
    private var now: Date!
    private var tabExtensionsBuilder: TestTabExtensionsBuilder!
    private var notificationCenter: NotificationCenter!
    private var mockPixelFiring: MockSuspensionPixelFiring!

    private var sut: TabSuspensionService!

    override func setUp() {
        super.setUp()
        featureFlagger = MockFeatureFlagger()
        now = Date()
        tabExtensionsBuilder = TestTabExtensionsBuilder(load: [TabSuspensionExtension.self])
        notificationCenter = NotificationCenter()
        mockPixelFiring = MockSuspensionPixelFiring()
    }

    override func tearDown() {
        sut = nil
        featureFlagger = nil
        windowControllersManager = nil
        now = nil
        tabExtensionsBuilder = nil
        notificationCenter = nil
        mockPixelFiring = nil
        super.tearDown()
    }

    private func makeSUT(
        tabCollectionViewModels: [TabCollectionViewModel],
        privacyConfigurationManager: PrivacyConfigurationManaging = MockPrivacyConfigurationManager(),
        memoryProvider: @escaping (pid_t) -> UInt64? = { _ in nil }
    ) -> TabSuspensionService {
        windowControllersManager = WindowControllersManagerMock(tabCollectionViewModels: tabCollectionViewModels)
        return TabSuspensionService(
            windowControllersManager: windowControllersManager,
            featureFlagger: featureFlagger,
            privacyConfigurationManager: privacyConfigurationManager,
            pixelFiring: mockPixelFiring,
            keyValueStore: InMemoryKeyValueStore(),
            memoryProvider: memoryProvider,
            notificationCenter: notificationCenter,
            dateProvider: { [unowned self] in self.now }
        )
    }

    private func makeTabCollectionViewModel(tabs: [AnyTab], selectionIndex: TabIndex = .unpinned(0)) -> TabCollectionViewModel {
        let tabCollection = TabCollection(tabs: tabs)
        return TabCollectionViewModel(tabCollection: tabCollection, selectionIndex: selectionIndex, pinnedTabsManagerProvider: PinnedTabsManagerProvidingMock())
    }

    private func postMemoryPressure() {
        notificationCenter.post(name: .memoryPressureCritical, object: nil)
    }

    // MARK: - Feature Flag

    func testWhenFeatureFlagDisabled_ThenMemoryPressureDoesNotSuspendTabs() {
        featureFlagger.enabledFeatureFlags = []
        let tab = Tab(content: .url(.duckDuckGo, credential: nil, source: .link), extensionsBuilder: tabExtensionsBuilder, featureFlagger: featureFlagger, lastSelectedAt: now.addingTimeInterval(-20 * 60))
        let vm = makeTabCollectionViewModel(tabs: [.loaded(tab)])
        sut = makeSUT(tabCollectionViewModels: [vm])

        // Select tab 0 so suspendTab would skip it, then add another tab and select it
        // Actually we need 2 tabs so the first one isn't selected
        let selectedTab = Tab(content: .newtab)
        vm.append(tab: selectedTab)
        vm.select(at: .unpinned(1))

        postMemoryPressure()

        XCTAssertEqual(vm.tabs.map(\.isSuspended), [false, false])
    }

    func testWhenFeatureFlagEnabled_ThenMemoryPressureSuspendsTabs() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        let tab = Tab(content: .url(.duckDuckGo, credential: nil, source: .link), extensionsBuilder: tabExtensionsBuilder, featureFlagger: featureFlagger)
        let selectedTab = Tab(content: .newtab, extensionsBuilder: tabExtensionsBuilder, featureFlagger: featureFlagger, lastSelectedAt: now)
        let vm = makeTabCollectionViewModel(tabs: [.loaded(tab), .loaded(selectedTab)], selectionIndex: .unpinned(1))
        sut = makeSUT(tabCollectionViewModels: [vm])
        tab.lastSelectedAt = now.addingTimeInterval(-20 * 60)

        postMemoryPressure()

        XCTAssertEqual(vm.tabs.map(\.isSuspended), [true, false])
    }

    // MARK: - Inactive Interval

    func testWhenTabRecentlySelected_ThenItIsNotSuspended() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        // Tab selected 5 minutes ago (less than 10 min threshold)
        let tab = Tab(content: .url(.duckDuckGo, credential: nil, source: .link), extensionsBuilder: tabExtensionsBuilder, featureFlagger: featureFlagger, lastSelectedAt: now.addingTimeInterval(-5 * 60))
        let selectedTab = Tab(content: .newtab, extensionsBuilder: tabExtensionsBuilder, featureFlagger: featureFlagger, lastSelectedAt: now)
        let vm = makeTabCollectionViewModel(tabs: [.loaded(tab), .loaded(selectedTab)], selectionIndex: .unpinned(1))
        sut = makeSUT(tabCollectionViewModels: [vm])

        postMemoryPressure()

        XCTAssertEqual(vm.tabs.map(\.isSuspended), [false, false])
    }

    func testWhenTabHasNoLastSelectedAt_ThenItIsSuspended() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        let tab = Tab(content: .url(.duckDuckGo, credential: nil, source: .link), extensionsBuilder: tabExtensionsBuilder, featureFlagger: featureFlagger)
        let selectedTab = Tab(content: .newtab, extensionsBuilder: tabExtensionsBuilder, featureFlagger: featureFlagger)
        let vm = makeTabCollectionViewModel(tabs: [.loaded(tab), .loaded(selectedTab)], selectionIndex: .unpinned(1))
        sut = makeSUT(tabCollectionViewModels: [vm])
        tab.lastSelectedAt = nil

        postMemoryPressure()

        // Tabs with no lastSelectedAt were never selected — they should be suspended
        XCTAssertEqual(vm.tabs.map(\.isSuspended), [true, false])
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

        XCTAssertEqual(vm.tabs.map(\.isSuspended), [false, false])
    }

    // MARK: - Already Suspended

    func testWhenTabAlreadySuspended_ThenItIsSkipped() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        let tab = UnloadedTab(content: .url(.duckDuckGo, credential: nil, source: .link), lastSelectedAt: now.addingTimeInterval(-20 * 60), isSuspended: true)
        let selectedTab = Tab(content: .newtab, extensionsBuilder: tabExtensionsBuilder, featureFlagger: featureFlagger, lastSelectedAt: now)
        let vm = makeTabCollectionViewModel(tabs: [.unloaded(tab), .loaded(selectedTab)], selectionIndex: .unpinned(1))
        sut = makeSUT(tabCollectionViewModels: [vm])

        postMemoryPressure()

        // Tab should remain suspended (not double-suspended)
        XCTAssertEqual(vm.tabs.map(\.isSuspended), [true, false])
    }

    // MARK: - Date Provider

    func testDateProviderIsUsedForCutoffCalculation() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        // Tab selected 15 minutes ago
        let tabSelectedAt = now.addingTimeInterval(-15 * 60)
        let tab = Tab(content: .url(.duckDuckGo, credential: nil, source: .link), extensionsBuilder: tabExtensionsBuilder, featureFlagger: featureFlagger, lastSelectedAt: tabSelectedAt)
        let selectedTab = Tab(content: .newtab, extensionsBuilder: tabExtensionsBuilder, featureFlagger: featureFlagger, lastSelectedAt: now)
        let vm = makeTabCollectionViewModel(tabs: [.loaded(tab), .loaded(selectedTab)], selectionIndex: .unpinned(1))
        sut = makeSUT(tabCollectionViewModels: [vm])

        // Move time back so the tab appears recently selected relative to "now"
        now = tabSelectedAt.addingTimeInterval(5 * 60)

        postMemoryPressure()

        // With the shifted date, the tab was selected only 5 minutes ago relative to "now" — should not be suspended
        XCTAssertEqual(vm.tabs.map(\.isSuspended), [false, false])
    }

    // MARK: - Pixel Firing

    func testWhenTabsSuspended_ThenPixelIsFiredWithCorrectParameters() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        let tab = Tab(content: .url(.duckDuckGo, credential: nil, source: .link), extensionsBuilder: tabExtensionsBuilder, featureFlagger: featureFlagger)
        let selectedTab = Tab(content: .newtab, extensionsBuilder: tabExtensionsBuilder, featureFlagger: featureFlagger, lastSelectedAt: now)
        let vm = makeTabCollectionViewModel(tabs: [.loaded(tab), .loaded(selectedTab)], selectionIndex: .unpinned(1))
        sut = makeSUT(tabCollectionViewModels: [vm])
        tab.lastSelectedAt = now.addingTimeInterval(-20 * 60)

        postMemoryPressure()

        XCTAssertEqual(mockPixelFiring.fireCalls.count, 1)
        let call = mockPixelFiring.fireCalls.first
        XCTAssertEqual(call?.pixel.name, "m_mac_tab_suspension")
        XCTAssertEqual(call?.pixel.parameters?["trigger"], "critical_memory_pressure")
        XCTAssertEqual(call?.pixel.parameters?["tabs_suspended"], "1")
        // Test tabs have no active web process, so memoryProvider is never consulted
        // and reclaimed bytes stay at 0.
        XCTAssertEqual(call?.pixel.parameters?["memory_reclaimed_mb"], "0")
    }

    func testWhenNoTabsSuspended_ThenPixelIsFiredWithZeroCounts() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        // Tab selected 5 minutes ago — won't be suspended
        let tab = Tab(content: .url(.duckDuckGo, credential: nil, source: .link), extensionsBuilder: tabExtensionsBuilder, featureFlagger: featureFlagger, lastSelectedAt: now.addingTimeInterval(-5 * 60))
        let selectedTab = Tab(content: .newtab, extensionsBuilder: tabExtensionsBuilder, featureFlagger: featureFlagger, lastSelectedAt: now)
        let vm = makeTabCollectionViewModel(tabs: [.loaded(tab), .loaded(selectedTab)], selectionIndex: .unpinned(1))
        sut = makeSUT(tabCollectionViewModels: [vm])

        postMemoryPressure()

        XCTAssertEqual(mockPixelFiring.fireCalls.count, 1)
        let call = mockPixelFiring.fireCalls.first
        XCTAssertEqual(call?.pixel.name, "m_mac_tab_suspension")
        XCTAssertEqual(call?.pixel.parameters?["trigger"], "critical_memory_pressure")
        XCTAssertEqual(call?.pixel.parameters?["tabs_suspended"], "0")
        XCTAssertEqual(call?.pixel.parameters?["memory_reclaimed_mb"], "0")
        XCTAssertEqual(call?.frequency, .dailyAndCount)
    }

    func testWhenFeatureFlagDisabled_ThenPixelIsNotFired() {
        featureFlagger.enabledFeatureFlags = []
        let tab = Tab(content: .url(.duckDuckGo, credential: nil, source: .link), extensionsBuilder: tabExtensionsBuilder, featureFlagger: featureFlagger, lastSelectedAt: now.addingTimeInterval(-20 * 60))
        let selectedTab = Tab(content: .newtab, extensionsBuilder: tabExtensionsBuilder, featureFlagger: featureFlagger, lastSelectedAt: now)
        let vm = makeTabCollectionViewModel(tabs: [.loaded(tab), .loaded(selectedTab)], selectionIndex: .unpinned(1))
        sut = makeSUT(tabCollectionViewModels: [vm])

        postMemoryPressure()

        XCTAssertTrue(mockPixelFiring.fireCalls.isEmpty)
    }

    // MARK: - View Model Swap on Suspension

    func testWhenTabIsSuspended_ThenViewModelChangesToUnloadedTabViewModel() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        let tab = Tab(content: .url(.duckDuckGo, credential: nil, source: .link), extensionsBuilder: tabExtensionsBuilder, featureFlagger: featureFlagger)
        let selectedTab = Tab(content: .newtab, extensionsBuilder: tabExtensionsBuilder, featureFlagger: featureFlagger, lastSelectedAt: now)
        let vm = makeTabCollectionViewModel(tabs: [.loaded(tab), .loaded(selectedTab)], selectionIndex: .unpinned(1))
        sut = makeSUT(tabCollectionViewModels: [vm])
        tab.lastSelectedAt = now.addingTimeInterval(-20 * 60)

        // Before suspension, view model should be TabViewModel
        XCTAssertTrue(vm.tabBarViewModel(at: .unpinned(0)) is TabViewModel)

        postMemoryPressure()

        // After suspension, view model should be UnloadedTabViewModel
        XCTAssertTrue(vm.tabBarViewModel(at: .unpinned(0)) is UnloadedTabViewModel)
    }

    // MARK: - Suspend + Materialize Roundtrip

    func testWhenSuspendedTabIsSelected_ThenItIsMaterializedAndViewModelIsRestored() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        let tab = Tab(content: .url(.duckDuckGo, credential: nil, source: .link), extensionsBuilder: tabExtensionsBuilder, featureFlagger: featureFlagger)
        let selectedTab = Tab(content: .newtab, extensionsBuilder: tabExtensionsBuilder, featureFlagger: featureFlagger, lastSelectedAt: now)
        let vm = makeTabCollectionViewModel(tabs: [.loaded(tab), .loaded(selectedTab)], selectionIndex: .unpinned(1))
        sut = makeSUT(tabCollectionViewModels: [vm])
        tab.lastSelectedAt = now.addingTimeInterval(-20 * 60)

        // Suspend the tab
        postMemoryPressure()
        XCTAssertEqual(vm.tabs.map(\.isSuspended), [true, false])
        XCTAssertTrue(vm.tabBarViewModel(at: .unpinned(0)) is UnloadedTabViewModel)

        // Select the suspended tab to materialize it
        let materializedTab = vm.selectTab(at: .unpinned(0))

        XCTAssertNotNil(materializedTab)
        XCTAssertEqual(vm.tabs.map(\.isSuspended), [false, false])
        XCTAssertTrue(vm.tabBarViewModel(at: .unpinned(0)) is TabViewModel)

        // Content should be preserved through the roundtrip
        XCTAssertEqual(materializedTab?.content, .url(.duckDuckGo, credential: nil, source: .pendingStateRestoration))
    }

    func testWhenSuspendedTabIsSelected_ThenUUIDIsPreserved() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        let tab = Tab(content: .url(.duckDuckGo, credential: nil, source: .link), extensionsBuilder: tabExtensionsBuilder, featureFlagger: featureFlagger)
        let originalUUID = tab.uuid
        let selectedTab = Tab(content: .newtab, extensionsBuilder: tabExtensionsBuilder, featureFlagger: featureFlagger, lastSelectedAt: now)
        let vm = makeTabCollectionViewModel(tabs: [.loaded(tab), .loaded(selectedTab)], selectionIndex: .unpinned(1))
        sut = makeSUT(tabCollectionViewModels: [vm])
        tab.lastSelectedAt = now.addingTimeInterval(-20 * 60)

        postMemoryPressure()

        // UUID should be preserved in the unloaded tab
        XCTAssertEqual(vm.tabs[0].uuid, originalUUID)

        // Materialize by selecting
        let materializedTab = vm.selectTab(at: .unpinned(0))

        // UUID should still be preserved after materialization
        XCTAssertEqual(materializedTab?.uuid, originalUUID)
    }

    // MARK: - makeSuspendedTab Snapshot Preservation

    func testWhenTabIsSuspended_ThenShouldClearSnapshotOnDeinitIsSetToFalse() {
        featureFlagger.enabledFeatureFlags = [.tabSuspension]
        let extensionsBuilder = TestTabExtensionsBuilder(load: [TabSuspensionExtension.self, TabSnapshotExtension.self])
        let tab = Tab(content: .url(.duckDuckGo, credential: nil, source: .link), extensionsBuilder: extensionsBuilder, featureFlagger: featureFlagger)
        let selectedTab = Tab(content: .newtab, extensionsBuilder: self.tabExtensionsBuilder, featureFlagger: featureFlagger, lastSelectedAt: now)
        let vm = makeTabCollectionViewModel(tabs: [.loaded(tab), .loaded(selectedTab)], selectionIndex: .unpinned(1))
        tab.lastSelectedAt = now.addingTimeInterval(-20 * 60)

        // Before suspension, shouldClearSnapshotOnDeinit defaults to true
        XCTAssertEqual(tab.tabSnapshots?.shouldClearSnapshotOnDeinit, true)

        _ = vm.suspendTab(at: .unpinned(0))

        // After suspension, the original tab's snapshot extension should be told not to clear
        XCTAssertEqual(tab.tabSnapshots?.shouldClearSnapshotOnDeinit, false)
    }

}

private final class MockSuspensionPixelFiring: PixelFiring {
    struct FireCall {
        let pixel: PixelKitEvent
        let frequency: PixelKit.Frequency
    }

    var fireCalls = [FireCall]()

    func fire(_ event: PixelKitEvent) {
        fire(event, frequency: .standard)
    }

    func fire(_ event: PixelKitEvent, frequency: PixelKit.Frequency) {
        fire(event, frequency: frequency, includeAppVersionParameter: true, withAdditionalParameters: nil, withNamePrefix: nil, onComplete: { _, _ in })
    }

    func fire(_ event: PixelKitEvent, frequency: PixelKit.Frequency, includeAppVersionParameter: Bool, withAdditionalParameters: [String: String]?, withNamePrefix: String?, onComplete: @escaping PixelKit.CompletionBlock) {
        fireCalls.append(FireCall(pixel: event, frequency: frequency))
        onComplete(true, nil)
    }
}
