//
//  DefaultFreemiumDBPUserStateManagerTests.swift
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

import XCTest
@testable import DataBrokerProtection_iOS

final class DefaultFreemiumDBPUserStateManagerTests: XCTestCase {

    private var userDefaults: UserDefaults!
    private var suiteName: String!
    private var isAuthenticatedReturnValue = false

    override func setUp() {
        super.setUp()
        suiteName = "DefaultFreemiumDBPUserStateManagerTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)!
        isAuthenticatedReturnValue = false
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeSUT() -> DefaultFreemiumDBPUserStateManager {
        DefaultFreemiumDBPUserStateManager(
            userDefaults: userDefaults,
            isUserAuthenticated: { [self] in isAuthenticatedReturnValue }
        )
    }

    // MARK: - Getter defaults

    func test_getters_returnDefaults_whenNoKeysSet() {
        let sut = makeSUT()
        XCTAssertFalse(sut.didActivate)
        XCTAssertNil(sut.firstProfileSavedTimestamp)
        XCTAssertNil(sut.firstScanResult)
        XCTAssertNil(sut.upgradeToSubscriptionTimestamp)
    }

    // MARK: - didActivate

    func test_didActivate_returnsPersistedValue() {
        userDefaults.set(true, forKey: "ios.browser.freemium.dbp.did.activate")
        let sut = makeSUT()
        XCTAssertTrue(sut.didActivate)
    }

    // MARK: - firstProfileSavedTimestamp

    func test_firstProfileSavedTimestamp_returnsPersistedValue() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        userDefaults.set(date, forKey: "ios.browser.freemium.dbp.first.profile.saved.timestamp")
        let sut = makeSUT()
        XCTAssertEqual(sut.firstProfileSavedTimestamp, date)
    }

    // MARK: - firstScanResult

    func test_firstScanResult_returnsMatchesFound_whenRawStringMatches() {
        userDefaults.set("matchesFound", forKey: "ios.browser.freemium.dbp.first.scan.result")
        let sut = makeSUT()
        XCTAssertEqual(sut.firstScanResult, .matchesFound)
    }

    func test_firstScanResult_returnsNoMatches_whenRawStringMatches() {
        userDefaults.set("noMatches", forKey: "ios.browser.freemium.dbp.first.scan.result")
        let sut = makeSUT()
        XCTAssertEqual(sut.firstScanResult, .noMatches)
    }

    func test_firstScanResult_returnsNil_whenRawStringInvalid() {
        userDefaults.set("garbage", forKey: "ios.browser.freemium.dbp.first.scan.result")
        let sut = makeSUT()
        XCTAssertNil(sut.firstScanResult)
    }

    // MARK: - upgradeToSubscriptionTimestamp

    func test_upgradeToSubscriptionTimestamp_returnsPersistedValue() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        userDefaults.set(date, forKey: "ios.browser.freemium.dbp.upgrade.to.subscription.timestamp")
        let sut = makeSUT()
        XCTAssertEqual(sut.upgradeToSubscriptionTimestamp, date)
    }

    // MARK: - resetAllState

    func test_resetAllState_clearsEveryKey() {
        userDefaults.set(true, forKey: "ios.browser.freemium.dbp.did.activate")
        userDefaults.set(Date(), forKey: "ios.browser.freemium.dbp.first.profile.saved.timestamp")
        userDefaults.set("matchesFound", forKey: "ios.browser.freemium.dbp.first.scan.result")
        userDefaults.set(Date(), forKey: "ios.browser.freemium.dbp.upgrade.to.subscription.timestamp")

        let sut = makeSUT()
        sut.resetAllState()

        XCTAssertFalse(sut.didActivate)
        XCTAssertNil(sut.firstProfileSavedTimestamp)
        XCTAssertNil(sut.firstScanResult)
        XCTAssertNil(sut.upgradeToSubscriptionTimestamp)
    }

    // MARK: - recordProfileSavedIfNeeded

    func test_recordProfileSavedIfNeeded_unauthenticated_setsDidActivateAndTimestamp() async throws {
        isAuthenticatedReturnValue = false
        let sut = makeSUT()

        let before = Date()
        await sut.recordProfileSavedIfNeeded()
        let after = Date()

        XCTAssertTrue(sut.didActivate)
        let timestamp = try XCTUnwrap(sut.firstProfileSavedTimestamp)
        XCTAssertGreaterThanOrEqual(timestamp, before)
        XCTAssertLessThanOrEqual(timestamp, after)
    }

    func test_recordProfileSavedIfNeeded_authenticated_writesNothing() async {
        isAuthenticatedReturnValue = true
        let sut = makeSUT()

        await sut.recordProfileSavedIfNeeded()

        XCTAssertFalse(sut.didActivate)
        XCTAssertNil(sut.firstProfileSavedTimestamp)
    }

    func test_recordProfileSavedIfNeeded_secondCall_doesNotOverwriteTimestamp() async {
        isAuthenticatedReturnValue = false
        let sut = makeSUT()

        await sut.recordProfileSavedIfNeeded()
        let firstTimestamp = sut.firstProfileSavedTimestamp

        try? await Task.sleep(nanoseconds: 10_000_000)
        await sut.recordProfileSavedIfNeeded()

        XCTAssertTrue(sut.didActivate)
        XCTAssertEqual(sut.firstProfileSavedTimestamp, firstTimestamp)
    }

    // MARK: - recordFirstScanResultIfNeeded

    func test_recordFirstScanResultIfNeeded_unauthenticated_hasMatchesTrue_setsMatchesFound() async {
        isAuthenticatedReturnValue = false
        let sut = makeSUT()

        await sut.recordFirstScanResultIfNeeded(hasMatches: true)

        XCTAssertEqual(sut.firstScanResult, .matchesFound)
    }

    func test_recordFirstScanResultIfNeeded_unauthenticated_hasMatchesFalse_setsNoMatches() async {
        isAuthenticatedReturnValue = false
        let sut = makeSUT()

        await sut.recordFirstScanResultIfNeeded(hasMatches: false)

        XCTAssertEqual(sut.firstScanResult, .noMatches)
    }

    func test_recordFirstScanResultIfNeeded_authenticated_writesNothing() async {
        isAuthenticatedReturnValue = true
        let sut = makeSUT()

        await sut.recordFirstScanResultIfNeeded(hasMatches: true)

        XCTAssertNil(sut.firstScanResult)
    }

    func test_recordFirstScanResultIfNeeded_priorNoMatches_withMatchesTrue_staysNoMatches() async {
        isAuthenticatedReturnValue = false
        let sut = makeSUT()

        await sut.recordFirstScanResultIfNeeded(hasMatches: false)
        await sut.recordFirstScanResultIfNeeded(hasMatches: true)

        XCTAssertEqual(sut.firstScanResult, .noMatches)
    }

    func test_recordFirstScanResultIfNeeded_priorMatchesFound_withMatchesFalse_staysMatchesFound() async {
        isAuthenticatedReturnValue = false
        let sut = makeSUT()

        await sut.recordFirstScanResultIfNeeded(hasMatches: true)
        await sut.recordFirstScanResultIfNeeded(hasMatches: false)

        XCTAssertEqual(sut.firstScanResult, .matchesFound)
    }

    func test_recordFirstScanResultIfNeeded_concurrentCalls_produceDeterministicSingleWrite() async {
        isAuthenticatedReturnValue = false
        let sut = makeSUT()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                let hasMatches = i % 2 == 0
                group.addTask {
                    await sut.recordFirstScanResultIfNeeded(hasMatches: hasMatches)
                }
            }
        }

        XCTAssertNotNil(sut.firstScanResult)
        XCTAssertTrue(sut.firstScanResult == .matchesFound || sut.firstScanResult == .noMatches)
    }

    // MARK: - recordSubscriptionUpgradeIfNeeded

    func test_recordSubscriptionUpgradeIfNeeded_didActivateFalse_doesNothing() async {
        let sut = makeSUT()

        await sut.recordSubscriptionUpgradeIfNeeded()

        XCTAssertNil(sut.upgradeToSubscriptionTimestamp)
    }

    func test_recordSubscriptionUpgradeIfNeeded_didActivateTrue_noPriorTimestamp_setsTimestamp() async throws {
        userDefaults.set(true, forKey: "ios.browser.freemium.dbp.did.activate")
        let sut = makeSUT()

        let before = Date()
        await sut.recordSubscriptionUpgradeIfNeeded()
        let after = Date()

        let timestamp = try XCTUnwrap(sut.upgradeToSubscriptionTimestamp)
        XCTAssertGreaterThanOrEqual(timestamp, before)
        XCTAssertLessThanOrEqual(timestamp, after)
    }

    func test_recordSubscriptionUpgradeIfNeeded_priorTimestamp_doesNotOverwrite() async {
        let priorDate = Date(timeIntervalSince1970: 1_600_000_000)
        userDefaults.set(true, forKey: "ios.browser.freemium.dbp.did.activate")
        userDefaults.set(priorDate, forKey: "ios.browser.freemium.dbp.upgrade.to.subscription.timestamp")
        let sut = makeSUT()

        await sut.recordSubscriptionUpgradeIfNeeded()

        XCTAssertEqual(sut.upgradeToSubscriptionTimestamp, priorDate)
    }
}
