//
//  NewTabPageProtectionsReportModelTests.swift
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

final class NewTabPageProtectionsReportModelTests: XCTestCase {
    private var model: NewTabPageProtectionsReportModel!
    private var privacyStats: CapturingPrivacyStats!
    private var settingsPersistor: MockNewTabPageProtectionsReportSettingsPersistor!

    override func setUp() async throws {
        try await super.setUp()

        privacyStats = CapturingPrivacyStats()
        settingsPersistor = MockNewTabPageProtectionsReportSettingsPersistor()
        model = NewTabPageProtectionsReportModel(privacyStats: privacyStats,
                                                 settingsPersistor: settingsPersistor,
                                                 burnAnimationSettingChanges: Just(true).eraseToAnyPublisher(),
                                                 showBurnAnimation: true)
    }

    // MARK: - Initialization Tests

    func testWhenInitializedThenDefaultValuesAreSet() {
        XCTAssertTrue(model.isViewExpanded)
        XCTAssertEqual(model.activeFeed, .privacyStats)
        XCTAssertEqual(model.visibleFeed, .privacyStats)
    }

    func testWhenInitializedWithCustomSettingsThenValuesAreSetFromSettings() {
        settingsPersistor.isViewExpanded = false
        settingsPersistor.activeFeed = .activity

        model = NewTabPageProtectionsReportModel(privacyStats: privacyStats,
                                                 settingsPersistor: settingsPersistor,
                                                 burnAnimationSettingChanges: Just(true).eraseToAnyPublisher(),
                                                 showBurnAnimation: true)

        XCTAssertFalse(model.isViewExpanded)
        XCTAssertEqual(model.activeFeed, .activity)
        XCTAssertNil(model.visibleFeed)
    }

    // MARK: - View Expansion Tests

    func testWhenViewIsExpandedThenVisibleFeedMatchesActiveFeed() {
        model.isViewExpanded = true
        model.activeFeed = .privacyStats
        XCTAssertEqual(model.visibleFeed, .privacyStats)

        model.activeFeed = .activity
        XCTAssertEqual(model.visibleFeed, .activity)
    }

    func testWhenViewIsCollapsedThenVisibleFeedIsNil() {
        model.isViewExpanded = false
        XCTAssertNil(model.visibleFeed)

        model.activeFeed = .activity
        XCTAssertNil(model.visibleFeed)
    }

    // MARK: - Settings Persistence Tests

    func testWhenViewExpansionChangesThenSettingsArePersisted() {
        model.isViewExpanded = false
        XCTAssertFalse(settingsPersistor.isViewExpanded)

        model.isViewExpanded = true
        XCTAssertTrue(settingsPersistor.isViewExpanded)
    }

    func testWhenActiveFeedChangesThenSettingsArePersisted() {
        model.activeFeed = .activity
        XCTAssertEqual(settingsPersistor.activeFeed, .activity)

        model.activeFeed = .privacyStats
        XCTAssertEqual(settingsPersistor.activeFeed, .privacyStats)
    }

    // MARK: - Privacy Stats Tests

    func testWhenPrivacyStatsUpdateThenStatsUpdatePublisherEmits() async {
        let expectation = expectation(description: "Stats update publisher should emit")
        expectation.expectedFulfillmentCount = 1

        let cancellable =  model.statsUpdatePublisher.sink { _ in expectation.fulfill() }

        privacyStats.statsUpdateSubject.send()

        await fulfillment(of: [expectation], timeout: 1.0)
        cancellable.cancel()
    }

    func testCalculateTotalCountReturnsValueFromPrivacyStats() async {
        privacyStats.privacyStatsTotalCount = 12345
        let totalCount = await model.calculateTotalCount()
        XCTAssertEqual(totalCount, 12345)
    }

    // MARK: - Visibility Provider Tests

    func testWhenPrivacyStatsFeedIsActiveThenIsPrivacyStatsVisibleReturnsTrue() {
        model.isViewExpanded = true
        model.activeFeed = .privacyStats
        XCTAssertTrue(model.isPrivacyStatsVisible)
    }

    func testWhenActivityFeedIsActiveThenIsPrivacyStatsVisibleReturnsFalse() {
        model.isViewExpanded = true
        model.activeFeed = .activity
        XCTAssertFalse(model.isPrivacyStatsVisible)
    }

    func testWhenViewIsCollapsedThenIsPrivacyStatsVisibleReturnsFalse() {
        model.isViewExpanded = false
        model.activeFeed = .privacyStats
        XCTAssertFalse(model.isPrivacyStatsVisible)
    }

    func testWhenActivityFeedIsActiveThenIsRecentActivityVisibleReturnsTrue() {
        model.isViewExpanded = true
        model.activeFeed = .activity
        XCTAssertTrue(model.isRecentActivityVisible)
    }

    func testWhenPrivacyStatsFeedIsActiveThenIsRecentActivityVisibleReturnsFalse() {
        model.isViewExpanded = true
        model.activeFeed = .privacyStats
        XCTAssertFalse(model.isRecentActivityVisible)
    }

    func testWhenViewIsCollapsedThenIsRecentActivityVisibleReturnsFalse() {
        model.isViewExpanded = false
        model.activeFeed = .activity
        XCTAssertFalse(model.isRecentActivityVisible)
    }

    // MARK: - Burn Animation Tests

    func testWhenInitializedWithShowBurnAnimationTrueThenShouldShowBurnAnimationIsTrue() {
        XCTAssertTrue(model.shouldShowBurnAnimation)
    }

    func testWhenInitializedWithShowBurnAnimationFalseThenShouldShowBurnAnimationIsFalse() {
        model = NewTabPageProtectionsReportModel(privacyStats: privacyStats,
                                                 settingsPersistor: settingsPersistor,
                                                 burnAnimationSettingChanges: Just(false).eraseToAnyPublisher(),
                                                 showBurnAnimation: false)
        XCTAssertFalse(model.shouldShowBurnAnimation)
    }

    @MainActor
    func testWhenBurnAnimationSettingChangesToTrueThenShouldShowBurnAnimationIsTrue() async throws {
        let burnAnimationSubject = PassthroughSubject<Bool, Never>()
        model = NewTabPageProtectionsReportModel(
            privacyStats: privacyStats,
            settingsPersistor: settingsPersistor,
            burnAnimationSettingChanges: burnAnimationSubject.eraseToAnyPublisher(),
            showBurnAnimation: false
        )

        try makeShouldShowBurnAnimationStream()
        burnAnimationSubject.send(true)
        let shouldShowBurnAnimation = try await getShouldShowBurnAnimationValue()
        XCTAssertTrue(shouldShowBurnAnimation)
    }

    @MainActor
    func testWhenBurnAnimationSettingChangesToFalseThenShouldShowBurnAnimationIsFalse() async throws {
        let burnAnimationSubject = PassthroughSubject<Bool, Never>()
        model = NewTabPageProtectionsReportModel(privacyStats: privacyStats,
                                                 settingsPersistor: settingsPersistor,
                                                 burnAnimationSettingChanges: burnAnimationSubject.eraseToAnyPublisher(),
                                                 showBurnAnimation: true)

        XCTAssertTrue(model.shouldShowBurnAnimation)

        try makeShouldShowBurnAnimationStream()
        burnAnimationSubject.send(false)
        let shouldShowBurnAnimation = try await getShouldShowBurnAnimationValue()
        XCTAssertFalse(shouldShowBurnAnimation)
    }

    @MainActor
    func testWhenBurnAnimationSettingChangesMultipleTimesThenShouldShowBurnAnimationFollowsChanges() async throws {
        let burnAnimationSubject = PassthroughSubject<Bool, Never>()
        model = NewTabPageProtectionsReportModel(privacyStats: privacyStats,
                                                 settingsPersistor: settingsPersistor,
                                                 burnAnimationSettingChanges: burnAnimationSubject.eraseToAnyPublisher(),
                                                 showBurnAnimation: true)

        try makeShouldShowBurnAnimationStream()

        burnAnimationSubject.send(false)
        burnAnimationSubject.send(true)
        burnAnimationSubject.send(false)

        let shouldShowBurnAnimationValues = try await getShouldShowBurnAnimationValues(3)
        XCTAssertEqual(shouldShowBurnAnimationValues, [false, true, false])
        XCTAssertFalse(model.shouldShowBurnAnimation)
    }

    // MARK: - Helpers

    @MainActor
    private var shouldShowBurnAnimationStream: AsyncStream<Bool>!
    private struct ShouldShowBurnAnimationNotReceivedError: Error {}

    /// Creates AsyncStream that emits updates to `model.shouldShowBurnAnimation`.
    @MainActor
    private func makeShouldShowBurnAnimationStream() throws {
        shouldShowBurnAnimationStream = AsyncStream { continuation in
            let cancellable = model.$shouldShowBurnAnimation.dropFirst()
                .sink { value in
                    continuation.yield(value)
                }

            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }

    /// Awaits first event emitted by the shouldShowBurnAnimation AsyncStream.
    @MainActor
    private func getShouldShowBurnAnimationValue() async throws -> Bool {
        let values = try await getShouldShowBurnAnimationValues(1)
        guard let value = values.first else {
            throw ShouldShowBurnAnimationNotReceivedError()
        }
        return value
    }

    /// Awaits first `count` events emitted by the shouldShowBurnAnimation AsyncStream.
    @MainActor
    private func getShouldShowBurnAnimationValues(_ count: Int) async throws -> [Bool] {
        var iterator = shouldShowBurnAnimationStream.makeAsyncIterator()
        var values: [Bool] = []

        for _ in 0..<count {
            guard let value = await iterator.next() else {
                throw ShouldShowBurnAnimationNotReceivedError()
            }
            values.append(value)
        }

        return values
    }
}
