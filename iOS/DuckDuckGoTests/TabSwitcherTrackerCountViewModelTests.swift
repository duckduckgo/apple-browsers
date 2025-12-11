//
//  TabSwitcherTrackerCountViewModelTests.swift
//  DuckDuckGoTests
//
//  Created to validate TabSwitcherTrackerCountViewModel behaviour.
//

import XCTest
@testable import DuckDuckGo

@MainActor
final class TabSwitcherTrackerCountViewModelTests: XCTestCase {

    final class MockPrivacyStats: PrivacyStatsProviding {
        var total: Int64 = 0
        var recordCalls: [String] = []
        var clearCallCount = 0

        func recordBlockedTracker(_ name: String) async { recordCalls.append(name) }
        func fetchPrivacyStatsTotalCount() async -> Int64 { total }
        func clearPrivacyStats() async { clearCallCount += 1 }
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
        let viewModel = TabSwitcherTrackerCountViewModel(settings: settings, privacyStats: stats)

        viewModel.refresh()
        await Task.yield()

        XCTAssertFalse(viewModel.state.isVisible)
    }

    func testRefreshHiddenWhenZeroCount() async {
        let settings = MockTabSwitcherSettings()
        let stats = MockPrivacyStats()
        stats.total = 0
        let viewModel = TabSwitcherTrackerCountViewModel(settings: settings, privacyStats: stats)

        viewModel.refresh()
        await Task.yield()

        XCTAssertFalse(viewModel.state.isVisible)
    }

    func testRefreshShowsWhenCountPositive() async {
        let settings = MockTabSwitcherSettings()
        let stats = MockPrivacyStats()
        stats.total = 5
        let viewModel = TabSwitcherTrackerCountViewModel(settings: settings, privacyStats: stats)

        viewModel.refresh()
        await Task.yield()

        XCTAssertTrue(viewModel.state.isVisible)
        XCTAssertTrue(viewModel.state.title.contains("5"))
    }

    func testHideTurnsOffSetting() {
        let settings = MockTabSwitcherSettings()
        settings.showTrackerCountInTabSwitcher = true
        let stats = MockPrivacyStats()
        let viewModel = TabSwitcherTrackerCountViewModel(settings: settings, privacyStats: stats)

        viewModel.hide()

        XCTAssertFalse(settings.showTrackerCountInTabSwitcher)
        XCTAssertFalse(viewModel.state.isVisible)
    }
}
