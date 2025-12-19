//
//  TabSwitcherTrackerCountViewModelTests.swift
//  DuckDuckGoTests
//
//  Created to validate TabSwitcherTrackerCountViewModel behaviour.
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

        func recordBlockedTracker(_ name: String) async { recordCalls.append(name) }
        func fetchPrivacyStatsTotalCount() async -> Int64 { total }
        func clearPrivacyStats() async { clearCallCount += 1 }
        func handleAppTermination() async { handleAppTerminationCallCount += 1 }
    }

    final class MockTabSwitcherSettings: TabSwitcherSettings {
        var isGridViewEnabled: Bool = true
        var hasSeenNewLayout: Bool = false
        var showTrackerCountInTabSwitcher: Bool = true
    }

    func testRefreshHiddenWhenSettingDisabled() async {
        let settings = MockTabSwitcherSettings()
        settings.showTrackerCountInTabSwitcher = false
        let stats = MockPrivacyStats()
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.tabSwitcherTrackerCount])
        let viewModel = TabSwitcherTrackerCountViewModel(settings: settings, privacyStats: stats, featureFlagger: featureFlagger)

        await viewModel.refreshAsync()

        XCTAssertFalse(viewModel.state.isVisible)
    }

    func testRefreshHiddenWhenFeatureFlagDisabled() async {
        let settings = MockTabSwitcherSettings()
        settings.showTrackerCountInTabSwitcher = true
        let stats = MockPrivacyStats()
        stats.total = 5
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [])
        let viewModel = TabSwitcherTrackerCountViewModel(settings: settings, privacyStats: stats, featureFlagger: featureFlagger)

        await viewModel.refreshAsync()

        XCTAssertFalse(viewModel.state.isVisible)
    }

    func testRefreshHiddenWhenZeroCount() async {
        let settings = MockTabSwitcherSettings()
        let stats = MockPrivacyStats()
        stats.total = 0
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.tabSwitcherTrackerCount])
        let viewModel = TabSwitcherTrackerCountViewModel(settings: settings, privacyStats: stats, featureFlagger: featureFlagger)

        await viewModel.refreshAsync()

        XCTAssertFalse(viewModel.state.isVisible)
    }

    func testRefreshShowsWhenCountPositive() async {
        let settings = MockTabSwitcherSettings()
        let stats = MockPrivacyStats()
        stats.total = 5
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.tabSwitcherTrackerCount])
        let viewModel = TabSwitcherTrackerCountViewModel(settings: settings, privacyStats: stats, featureFlagger: featureFlagger)

        await viewModel.refreshAsync()

        XCTAssertTrue(viewModel.state.isVisible)
        XCTAssertTrue(viewModel.state.title.contains("5"))
    }

    func testHideTurnsOffSetting() {
        let settings = MockTabSwitcherSettings()
        settings.showTrackerCountInTabSwitcher = true
        let stats = MockPrivacyStats()
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.tabSwitcherTrackerCount])
        let viewModel = TabSwitcherTrackerCountViewModel(settings: settings, privacyStats: stats, featureFlagger: featureFlagger)

        viewModel.hide()

        XCTAssertFalse(settings.showTrackerCountInTabSwitcher)
        XCTAssertFalse(viewModel.state.isVisible)
    }
}
