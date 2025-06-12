//
//  NewTabPageProtectionsReportClientTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import PrivacyStats
import PersistenceTestingUtils
import TrackerRadarKit
import XCTest
@testable import NewTabPage

final class NewTabPageProtectionsReportClientTests: XCTestCase {
    private var client: NewTabPageProtectionsReportClient!
    private var model: NewTabPageProtectionsReportModel!

    private var privacyStats: CapturingPrivacyStats!
    private var settingsPersistor: MockNewTabPageProtectionsReportSettingsPersistor!
    private var trackerDataProvider: MockPrivacyStatsTrackerDataProvider!

    private var userScript: NewTabPageUserScript!
    private var messageHelper: MessageHelper<NewTabPageProtectionsReportClient.MessageName>!

    override func setUp() async throws {
        try await super.setUp()

        privacyStats = CapturingPrivacyStats()
        settingsPersistor = MockNewTabPageProtectionsReportSettingsPersistor()

        model = NewTabPageProtectionsReportModel(privacyStats: privacyStats, settingsPersistor: settingsPersistor)
        client = NewTabPageProtectionsReportClient(model: model)

        userScript = NewTabPageUserScript()
        messageHelper = .init(userScript: userScript)
        client.registerMessageHandlers(for: userScript)
    }

    // MARK: - getConfig

    func testWhenProtectionsReportIsExpandedThenGetConfigReturnsExpandedState() async throws {
        model.isViewExpanded = true
        let config: NewTabPageDataModel.ProtectionsConfig = try await messageHelper.handleMessage(named: .getConfig)
        XCTAssertEqual(config.expansion, .expanded)
    }

    func testWhenProtectionsReportIsCollapsedThenGetConfigReturnsCollapsedState() async throws {
        model.isViewExpanded = false
        let config: NewTabPageDataModel.ProtectionsConfig = try await messageHelper.handleMessage(named: .getConfig)
        XCTAssertEqual(config.expansion, .collapsed)
    }

    func testWhenProtectionsReportShowsPrivacyStatsThenGetConfigReturnsPrivacyStatsAsFeed() async throws {
        model.activeFeed = .privacyStats
        let config: NewTabPageDataModel.ProtectionsConfig = try await messageHelper.handleMessage(named: .getConfig)
        XCTAssertEqual(config.feed, .privacyStats)
    }

    func testWhenProtectionsReportShowsRecentActivityThenGetConfigReturnsRecentActivityAsFeed() async throws {
        model.activeFeed = .activity
        let config: NewTabPageDataModel.ProtectionsConfig = try await messageHelper.handleMessage(named: .getConfig)
        XCTAssertEqual(config.feed, .activity)
    }

    // MARK: - setConfig

    func testWhenSetConfigContainsExpandedStateThenModelSettingIsSetToExpanded() async throws {
        model.isViewExpanded = false
        let config = NewTabPageDataModel.ProtectionsConfig(expansion: .expanded, feed: .privacyStats)
        try await messageHelper.handleMessageExpectingNilResponse(named: .setConfig, parameters: config)
        XCTAssertEqual(model.isViewExpanded, true)
    }

    func testWhenSetConfigContainsCollapsedStateThenModelSettingIsSetToCollapsed() async throws {
        model.isViewExpanded = true
        let config = NewTabPageDataModel.ProtectionsConfig(expansion: .collapsed, feed: .privacyStats)
        try await messageHelper.handleMessageExpectingNilResponse(named: .setConfig, parameters: config)
        XCTAssertEqual(model.isViewExpanded, false)
    }

    func testWhenSetConfigContainsPrivacyStatsFeedThenModelSettingIsSetToPrivacyStats() async throws {
        model.activeFeed = .activity
        let config = NewTabPageDataModel.ProtectionsConfig(expansion: .expanded, feed: .privacyStats)
        try await messageHelper.handleMessageExpectingNilResponse(named: .setConfig, parameters: config)
        XCTAssertEqual(model.activeFeed, .privacyStats)
    }

    func testWhenSetConfigContainsRecentActivityFeedThenModelSettingIsSetToPrivacyStats() async throws {
        model.activeFeed = .privacyStats
        let config = NewTabPageDataModel.ProtectionsConfig(expansion: .expanded, feed: .activity)
        try await messageHelper.handleMessageExpectingNilResponse(named: .setConfig, parameters: config)
        XCTAssertEqual(model.activeFeed, .activity)
    }

    // MARK: - getData

    func testThatGetDataReturnsTotalCountFromPrivacyStats() async throws {
        privacyStats.privacyStatsTotalCount = 1500100900
        let data: NewTabPageDataModel.ProtectionsData = try await messageHelper.handleMessage(named: .getData)
        XCTAssertEqual(data.totalCount, privacyStats.privacyStatsTotalCount)
    }
}
