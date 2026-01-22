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
    private var autoconsentStats: CapturingAutoconsentStats!
    private var settingsPersistor: MockNewTabPageProtectionsReportSettingsPersistor!
    private var trackerDataProvider: MockPrivacyStatsTrackerDataProvider!

    private var userScript: NewTabPageUserScript!
    private var messageHelper: MessageHelper<NewTabPageProtectionsReportClient.MessageName>!

    override func setUp() {
        super.setUp()

        privacyStats = CapturingPrivacyStats()
        autoconsentStats = CapturingAutoconsentStats()
        settingsPersistor = MockNewTabPageProtectionsReportSettingsPersistor()

        model = NewTabPageProtectionsReportModel(privacyStats: privacyStats,
                                                 autoconsentStats: autoconsentStats,
                                                 settingsPersistor: settingsPersistor,
                                                 burnAnimationSettingChanges: Just(true).eraseToAnyPublisher(),
                                                 showBurnAnimation: true,
                                                 isAutoconsentEnabled: { true })
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

    func testWhenModelShowBurnAnimationIsTrueThenGetConfigReturnsShowBurnAnimationTrue() async throws {
        model.shouldShowBurnAnimation = true
        let config: NewTabPageDataModel.ProtectionsConfig = try await messageHelper.handleMessage(named: .getConfig)
        XCTAssertTrue(config.showBurnAnimation)
    }

    func testWhenModelShouldShowProtectionsReportNewLabelIsTrueThenGetConfigReturnsShowProtectionsReportNewLabelTrue() async throws {
        settingsPersistor.widgetNewLabelFirstShownDate = Date()

        model = NewTabPageProtectionsReportModel(
            privacyStats: privacyStats,
            autoconsentStats: autoconsentStats,
            settingsPersistor: settingsPersistor,
            burnAnimationSettingChanges: Just(true).eraseToAnyPublisher(),
            showBurnAnimation: true,
            isAutoconsentEnabled: { true }
        )
        client = NewTabPageProtectionsReportClient(model: model)
        client.registerMessageHandlers(for: userScript)

        let config: NewTabPageDataModel.ProtectionsConfig = try await messageHelper.handleMessage(named: .getConfig)
        XCTAssertTrue(config.showProtectionsReportNewLabel)
    }

    func testWhenModelShouldShowProtectionsReportNewLabelIsFalseThenGetConfigReturnsShowProtectionsReportNewLabelFalse() async throws {
        let eightDaysAgo = Date().addingTimeInterval(-8 * 24 * 60 * 60)
        settingsPersistor.widgetNewLabelFirstShownDate = eightDaysAgo

        model = NewTabPageProtectionsReportModel(
            privacyStats: privacyStats,
            autoconsentStats: autoconsentStats,
            settingsPersistor: settingsPersistor,
            burnAnimationSettingChanges: Just(true).eraseToAnyPublisher(),
            showBurnAnimation: true,
            isAutoconsentEnabled: { true }
        )
        client = NewTabPageProtectionsReportClient(model: model)
        client.registerMessageHandlers(for: userScript)

        let config: NewTabPageDataModel.ProtectionsConfig = try await messageHelper.handleMessage(named: .getConfig)
        XCTAssertFalse(config.showProtectionsReportNewLabel)
    }

    // MARK: - setConfig

    func testWhenSetConfigContainsExpandedStateThenModelSettingIsSetToExpanded() async throws {
        model.isViewExpanded = false
        let config = NewTabPageDataModel.ProtectionsConfig(expansion: .expanded, feed: .privacyStats, showBurnAnimation: false, showProtectionsReportNewLabel: false)
        try await messageHelper.handleMessageExpectingNilResponse(named: .setConfig, parameters: config)
        XCTAssertEqual(model.isViewExpanded, true)
    }

    func testWhenSetConfigContainsCollapsedStateThenModelSettingIsSetToCollapsed() async throws {
        model.isViewExpanded = true
        let config = NewTabPageDataModel.ProtectionsConfig(expansion: .collapsed, feed: .privacyStats, showBurnAnimation: false, showProtectionsReportNewLabel: false)
        try await messageHelper.handleMessageExpectingNilResponse(named: .setConfig, parameters: config)
        XCTAssertEqual(model.isViewExpanded, false)
    }

    func testWhenSetConfigContainsPrivacyStatsFeedThenModelSettingIsSetToPrivacyStats() async throws {
        model.activeFeed = .activity
        let config = NewTabPageDataModel.ProtectionsConfig(expansion: .expanded, feed: .privacyStats, showBurnAnimation: false, showProtectionsReportNewLabel: false)
        try await messageHelper.handleMessageExpectingNilResponse(named: .setConfig, parameters: config)
        XCTAssertEqual(model.activeFeed, .privacyStats)
    }

    func testWhenSetConfigContainsRecentActivityFeedThenModelSettingIsSetToPrivacyStats() async throws {
        model.activeFeed = .privacyStats
        let config = NewTabPageDataModel.ProtectionsConfig(expansion: .expanded, feed: .activity, showBurnAnimation: false, showProtectionsReportNewLabel: false)
        try await messageHelper.handleMessageExpectingNilResponse(named: .setConfig, parameters: config)
        XCTAssertEqual(model.activeFeed, .activity)
    }

    func testWhenSetConfigContainsShowBurnAnimationFalseThenModelShowBurnAnimationIsNotAffected() async throws {
        model.shouldShowBurnAnimation = true
        let config = NewTabPageDataModel.ProtectionsConfig(expansion: .expanded, feed: .privacyStats, showBurnAnimation: false, showProtectionsReportNewLabel: false)
        try await messageHelper.handleMessageExpectingNilResponse(named: .setConfig, parameters: config)
        XCTAssertTrue(model.shouldShowBurnAnimation) // Should remain unchanged
    }

    // MARK: - getData

    func testThatGetDataReturnsTotalCountFromPrivacyStats() async throws {
        privacyStats.privacyStatsTotalCount = 1500100900
        let data: NewTabPageDataModel.ProtectionsData = try await messageHelper.handleMessage(named: .getData)
        XCTAssertEqual(data.totalCount, privacyStats.privacyStatsTotalCount)
    }

    // MARK: - isAutoconsentEnabled Tests

    func testWhenAutoconsentEnabledIsTrueThenGetDataIncludesTotalCookiePopUpsBlocked() async throws {
        // Setup: Configure autoconsent stats and enable autoconsent
        autoconsentStats.isEnabledValue = true
        autoconsentStats.totalCookiePopUpsBlocked = 42
        privacyStats.privacyStatsTotalCount = 1000

        // Recreate model with isAutoconsentEnabled returning true
        model = NewTabPageProtectionsReportModel(
            privacyStats: privacyStats,
            autoconsentStats: autoconsentStats,
            settingsPersistor: settingsPersistor,
            burnAnimationSettingChanges: Just(true).eraseToAnyPublisher(),
            showBurnAnimation: true,
            isAutoconsentEnabled: { true }
        )
        client = NewTabPageProtectionsReportClient(model: model)
        client.registerMessageHandlers(for: userScript)

        // Act
        let data: NewTabPageDataModel.ProtectionsData = try await messageHelper.handleMessage(named: .getData)

        // Assert
        XCTAssertEqual(data.totalCount, 1000)
        XCTAssertEqual(data.totalCookiePopUpsBlocked, 42)
    }

    func testWhenAutoconsentEnabledIsFalseThenGetDataExcludesTotalCookiePopUpsBlocked() async throws {
        // Setup: Configure autoconsent stats but disable autoconsent
        autoconsentStats.isEnabledValue = true
        autoconsentStats.totalCookiePopUpsBlocked = 42
        privacyStats.privacyStatsTotalCount = 1000

        // Recreate model with isAutoconsentEnabled returning false
        model = NewTabPageProtectionsReportModel(
            privacyStats: privacyStats,
            autoconsentStats: autoconsentStats,
            settingsPersistor: settingsPersistor,
            burnAnimationSettingChanges: Just(true).eraseToAnyPublisher(),
            showBurnAnimation: true,
            isAutoconsentEnabled: { false }
        )
        client = NewTabPageProtectionsReportClient(model: model)
        client.registerMessageHandlers(for: userScript)

        // Act
        let data: NewTabPageDataModel.ProtectionsData = try await messageHelper.handleMessage(named: .getData)

        // Assert
        XCTAssertEqual(data.totalCount, 1000)
        XCTAssertNil(data.totalCookiePopUpsBlocked, "totalCookiePopUpsBlocked should be nil when isAutoconsentEnabled is false")
    }

    func testWhenAutoconsentStatsIsDisabledThenGetDataReturnsLegacyFormat() async throws {
        // Setup: Disable autoconsent stats entirely
        autoconsentStats.isEnabledValue = false
        privacyStats.privacyStatsTotalCount = 1000

        // Act
        let data: NewTabPageDataModel.ProtectionsDataLegacy = try await messageHelper.handleMessage(named: .getData)

        // Assert
        XCTAssertEqual(data.totalCount, 1000)
        // ProtectionsDataLegacy doesn't have totalCookiePopUpsBlocked field at all
    }

    func testWhenAutoconsentEnabledIsTrueButStatsAreZeroThenGetDataIncludesZeroValue() async throws {
        // Setup: Enable autoconsent but with zero stats
        autoconsentStats.isEnabledValue = true
        autoconsentStats.totalCookiePopUpsBlocked = 0
        privacyStats.privacyStatsTotalCount = 500

        // Recreate model with isAutoconsentEnabled returning true
        model = NewTabPageProtectionsReportModel(
            privacyStats: privacyStats,
            autoconsentStats: autoconsentStats,
            settingsPersistor: settingsPersistor,
            burnAnimationSettingChanges: Just(true).eraseToAnyPublisher(),
            showBurnAnimation: true,
            isAutoconsentEnabled: { true }
        )
        client = NewTabPageProtectionsReportClient(model: model)
        client.registerMessageHandlers(for: userScript)

        // Act
        let data: NewTabPageDataModel.ProtectionsData = try await messageHelper.handleMessage(named: .getData)

        // Assert
        XCTAssertEqual(data.totalCount, 500)
        XCTAssertEqual(data.totalCookiePopUpsBlocked, 0, "Should include totalCookiePopUpsBlocked even when zero")
    }
}
