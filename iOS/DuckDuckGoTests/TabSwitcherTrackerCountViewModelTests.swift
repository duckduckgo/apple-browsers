//
//  TabSwitcherTrackerCountViewModelTests.swift
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

import XCTest
@testable import DuckDuckGo
@testable import Core

@MainActor
final class TabSwitcherTrackerCountViewModelTests: XCTestCase {

    final class MockPrivacyStats: PrivacyStatsProviding {
        var total: Int64 = 0
        var recordCalls: [String] = []
        var clearCallCount = 0
        var handleAppTerminationCallCount = 0
        var fetchDelayNanoseconds: UInt64?
        var fetchCallCount = 0

        func recordBlockedTracker(_ name: String) async { recordCalls.append(name) }
        func fetchPrivacyStatsTotalCount() async -> Int64 {
            fetchCallCount += 1
            if let delay = fetchDelayNanoseconds {
                try? await Task.sleep(nanoseconds: delay)
            }
            return total
        }
        func clearPrivacyStats() async { clearCallCount += 1 }
        func handleAppTermination() async { handleAppTerminationCallCount += 1 }
    }

    final class MockTabSwitcherSettings: TabSwitcherSettings {
        var isGridViewEnabled: Bool = true
        var hasSeenNewLayout: Bool = false
        var showTrackerCountInTabSwitcher: Bool = true
        var lastTrackerCountInTabSwitcher: Int64?
    }

    func testRefreshHiddenWhenSettingDisabled() async {
        let settings = MockTabSwitcherSettings()
        settings.showTrackerCountInTabSwitcher = false
        let stats = MockPrivacyStats()
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.tabSwitcherTrackerCount])
        let viewModel = TabSwitcherTrackerCountViewModel(settings: settings, privacyStats: stats, featureFlagger: featureFlagger, initialState: .hidden)

        await viewModel.refreshAsync()

        XCTAssertFalse(viewModel.state.isVisible)
    }

    func testRefreshHiddenWhenFeatureFlagDisabled() async {
        let settings = MockTabSwitcherSettings()
        settings.showTrackerCountInTabSwitcher = true
        let stats = MockPrivacyStats()
        stats.total = 5
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [])
        let viewModel = TabSwitcherTrackerCountViewModel(settings: settings, privacyStats: stats, featureFlagger: featureFlagger, initialState: .hidden)

        await viewModel.refreshAsync()

        XCTAssertFalse(viewModel.state.isVisible)
    }

    func testRefreshHiddenWhenZeroCount() async {
        let settings = MockTabSwitcherSettings()
        let stats = MockPrivacyStats()
        stats.total = 0
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.tabSwitcherTrackerCount])
        let viewModel = TabSwitcherTrackerCountViewModel(settings: settings, privacyStats: stats, featureFlagger: featureFlagger, initialState: .hidden)

        await viewModel.refreshAsync()

        XCTAssertFalse(viewModel.state.isVisible)
    }

    func testRefreshShowsWhenCountPositive() async {
        let settings = MockTabSwitcherSettings()
        let stats = MockPrivacyStats()
        stats.total = 5
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.tabSwitcherTrackerCount])
        let viewModel = TabSwitcherTrackerCountViewModel(settings: settings, privacyStats: stats, featureFlagger: featureFlagger, initialState: .hidden)

        await viewModel.refreshAsync()

        XCTAssertTrue(viewModel.state.isVisible)
        XCTAssertTrue(viewModel.state.title.contains("5"))
    }

    func testHideTurnsOffSetting() {
        let settings = MockTabSwitcherSettings()
        settings.showTrackerCountInTabSwitcher = true
        let stats = MockPrivacyStats()
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.tabSwitcherTrackerCount])
        let viewModel = TabSwitcherTrackerCountViewModel(settings: settings, privacyStats: stats, featureFlagger: featureFlagger, initialState: .hidden)

        viewModel.hide()

        XCTAssertFalse(settings.showTrackerCountInTabSwitcher)
        XCTAssertFalse(viewModel.state.isVisible)
    }

    func testRefreshCancelsPreviousRefresh() async {
        let settings = MockTabSwitcherSettings()
        let stats = MockPrivacyStats()
        stats.total = 100
        stats.fetchDelayNanoseconds = 100_000_000 // 100ms
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.tabSwitcherTrackerCount])
        let viewModel = TabSwitcherTrackerCountViewModel(settings: settings, privacyStats: stats, featureFlagger: featureFlagger, initialState: .hidden)

        // Start first refresh (will be slow due to delay)
        viewModel.refresh()

        // Immediately start second refresh which should cancel the first
        stats.total = 200
        let state = await viewModel.refreshAsync()

        // The final state should reflect the second refresh's value (200)
        XCTAssertTrue(state.isVisible)
        XCTAssertTrue(state.title.contains("200"))
        // Both fetches should have been initiated
        XCTAssertEqual(stats.fetchCallCount, 2)
    }

    func testHideWhileRefreshInProgress() async {
        let settings = MockTabSwitcherSettings()
        let stats = MockPrivacyStats()
        stats.total = 50
        stats.fetchDelayNanoseconds = 100_000_000 // 100ms
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.tabSwitcherTrackerCount])
        let viewModel = TabSwitcherTrackerCountViewModel(settings: settings, privacyStats: stats, featureFlagger: featureFlagger, initialState: .hidden)

        // Start refresh (will be slow due to delay)
        viewModel.refresh()

        // Immediately hide, which should cancel the refresh task
        viewModel.hide()

        // Wait for any pending work to complete
        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms

        // State should remain hidden (hide should have cancelled the refresh)
        XCTAssertFalse(viewModel.state.isVisible)
        XCTAssertFalse(settings.showTrackerCountInTabSwitcher)
    }

    func testHideCancelsRefreshAsync() async {
        let settings = MockTabSwitcherSettings()
        let stats = MockPrivacyStats()
        stats.total = 50
        stats.fetchDelayNanoseconds = 100_000_000 // 100ms
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.tabSwitcherTrackerCount])
        let viewModel = TabSwitcherTrackerCountViewModel(settings: settings, privacyStats: stats, featureFlagger: featureFlagger, initialState: .hidden)

        // Start refreshAsync in a separate task (will be slow due to delay)
        let refreshTask = Task {
            await viewModel.refreshAsync()
        }

        // Give the task a moment to start and begin fetching
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        // Hide should cancel the in-progress refreshAsync task
        viewModel.hide()

        // Wait for the refresh task to complete (it should be cancelled)
        _ = await refreshTask.value

        // Wait a bit more to ensure no delayed state updates occur
        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms

        // State should remain hidden because hide() cancelled the refreshAsync task
        XCTAssertFalse(viewModel.state.isVisible)
        XCTAssertFalse(settings.showTrackerCountInTabSwitcher)
    }

    // MARK: - calculateInitialState tests

    func testCalculateInitialStateReturnsHiddenWhenFeatureDisabled() async {
        let settings = MockTabSwitcherSettings()
        settings.showTrackerCountInTabSwitcher = true
        let stats = MockPrivacyStats()
        stats.total = 100
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [])

        let state = await TabSwitcherTrackerCountViewModel.calculateInitialState(
            featureFlagger: featureFlagger,
            settings: settings,
            privacyStats: stats
        )

        XCTAssertFalse(state.isVisible)
    }

    func testCalculateInitialStateReturnsHiddenWhenSettingDisabled() async {
        let settings = MockTabSwitcherSettings()
        settings.showTrackerCountInTabSwitcher = false
        let stats = MockPrivacyStats()
        stats.total = 100
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.tabSwitcherTrackerCount])

        let state = await TabSwitcherTrackerCountViewModel.calculateInitialState(
            featureFlagger: featureFlagger,
            settings: settings,
            privacyStats: stats
        )

        XCTAssertFalse(state.isVisible)
    }

    func testCalculateInitialStateReturnsHiddenWhenCountIsZero() async {
        let settings = MockTabSwitcherSettings()
        settings.showTrackerCountInTabSwitcher = true
        let stats = MockPrivacyStats()
        stats.total = 0
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.tabSwitcherTrackerCount])

        let state = await TabSwitcherTrackerCountViewModel.calculateInitialState(
            featureFlagger: featureFlagger,
            settings: settings,
            privacyStats: stats
        )

        XCTAssertFalse(state.isVisible)
    }

    func testCalculateInitialStateReturnsVisibleWithCorrectCount() async {
        let settings = MockTabSwitcherSettings()
        settings.showTrackerCountInTabSwitcher = true
        let stats = MockPrivacyStats()
        stats.total = 42
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.tabSwitcherTrackerCount])

        let state = await TabSwitcherTrackerCountViewModel.calculateInitialState(
            featureFlagger: featureFlagger,
            settings: settings,
            privacyStats: stats
        )

        XCTAssertTrue(state.isVisible)
        XCTAssertTrue(state.title.contains("42"))
        XCTAssertFalse(state.subtitle.isEmpty)
    }

    func testInitialStateIsUsedByViewModel() async {
        let settings = MockTabSwitcherSettings()
        let stats = MockPrivacyStats()
        stats.total = 100
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.tabSwitcherTrackerCount])

        let initialState = TabSwitcherTrackerCountViewModel.State(
            isVisible: true,
            title: "Initial Title",
            subtitle: "Initial Subtitle"
        )

        let viewModel = TabSwitcherTrackerCountViewModel(
            settings: settings,
            privacyStats: stats,
            featureFlagger: featureFlagger,
            initialState: initialState
        )

        // Verify the initial state is used
        XCTAssertTrue(viewModel.state.isVisible)
        XCTAssertEqual(viewModel.state.title, "Initial Title")
        XCTAssertEqual(viewModel.state.subtitle, "Initial Subtitle")
    }
}
