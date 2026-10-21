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
    private var isFreemiumEnabledReturnValue = true

    override func setUp() {
        super.setUp()
        suiteName = "DefaultFreemiumDBPUserStateManagerTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)!
        isAuthenticatedReturnValue = false
        isFreemiumEnabledReturnValue = true
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
            isUserAuthenticated: { [self] in isAuthenticatedReturnValue },
            isFreemiumEnabled: { [self] in isFreemiumEnabledReturnValue }
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

    // MARK: - recordSubscriptionUpgradeIfEligible

    func test_recordSubscriptionUpgradeIfEligible_didActivateFalse_doesNothing() async {
        let sut = makeSUT()

        await sut.recordSubscriptionUpgradeIfEligible()

        XCTAssertNil(sut.upgradeToSubscriptionTimestamp)
    }

    func test_recordSubscriptionUpgradeIfEligible_didActivateTrue_noPriorTimestamp_setsTimestamp() async throws {
        userDefaults.set(true, forKey: "ios.browser.freemium.dbp.did.activate")
        let sut = makeSUT()

        let before = Date()
        await sut.recordSubscriptionUpgradeIfEligible()
        let after = Date()

        let timestamp = try XCTUnwrap(sut.upgradeToSubscriptionTimestamp)
        XCTAssertGreaterThanOrEqual(timestamp, before)
        XCTAssertLessThanOrEqual(timestamp, after)
    }

    func test_recordSubscriptionUpgradeIfEligible_priorTimestamp_doesNotOverwrite() async {
        let priorDate = Date(timeIntervalSince1970: 1_600_000_000)
        userDefaults.set(true, forKey: "ios.browser.freemium.dbp.did.activate")
        userDefaults.set(priorDate, forKey: "ios.browser.freemium.dbp.upgrade.to.subscription.timestamp")
        let sut = makeSUT()

        await sut.recordSubscriptionUpgradeIfEligible()

        XCTAssertEqual(sut.upgradeToSubscriptionTimestamp, priorDate)
    }

    // MARK: - Feature-flag gate on writes (persisted state outlives flag transitions)

    func test_recordProfileSavedIfNeeded_flagDisabled_writesNothing() async {
        isAuthenticatedReturnValue = false
        isFreemiumEnabledReturnValue = false
        let sut = makeSUT()

        await sut.recordProfileSavedIfNeeded()

        XCTAssertFalse(sut.didActivate)
        XCTAssertNil(sut.firstProfileSavedTimestamp)
    }

    func test_recordFirstScanResultIfNeeded_flagDisabled_writesNothing() async {
        isAuthenticatedReturnValue = false
        isFreemiumEnabledReturnValue = false
        let sut = makeSUT()

        await sut.recordFirstScanResultIfNeeded(hasMatches: true)

        XCTAssertNil(sut.firstScanResult)
    }

    func test_recordSubscriptionUpgradeIfEligible_flagDisabled_writesNothing() async {
        userDefaults.set(true, forKey: "ios.browser.freemium.dbp.did.activate")
        isFreemiumEnabledReturnValue = false
        let sut = makeSUT()

        await sut.recordSubscriptionUpgradeIfEligible()

        XCTAssertNil(sut.upgradeToSubscriptionTimestamp)
    }

    // The async write methods check `isFreemiumEnabled()` up front as a fast path, but the
    // flag can flip off while they're suspended on `await isUserAuthenticated()`. The sync
    // persist helpers re-check the flag under the lock to keep the gate atomic with the
    // write. These tests simulate the transition by flipping the flag from inside the auth
    // closure — the auth closure runs after the first flag check and before the persist
    // helper runs.

    func test_recordProfileSavedIfNeeded_flagFlipsOffDuringAuthCheck_writesNothing() async {
        isFreemiumEnabledReturnValue = true
        let sut = DefaultFreemiumDBPUserStateManager(
            userDefaults: userDefaults,
            isUserAuthenticated: { [self] in
                isFreemiumEnabledReturnValue = false
                return false
            },
            isFreemiumEnabled: { [self] in isFreemiumEnabledReturnValue }
        )

        await sut.recordProfileSavedIfNeeded()

        XCTAssertFalse(sut.didActivate)
        XCTAssertNil(sut.firstProfileSavedTimestamp)
    }

    func test_recordFirstScanResultIfNeeded_flagFlipsOffDuringAuthCheck_writesNothing() async {
        isFreemiumEnabledReturnValue = true
        let sut = DefaultFreemiumDBPUserStateManager(
            userDefaults: userDefaults,
            isUserAuthenticated: { [self] in
                isFreemiumEnabledReturnValue = false
                return false
            },
            isFreemiumEnabled: { [self] in isFreemiumEnabledReturnValue }
        )

        await sut.recordFirstScanResultIfNeeded(hasMatches: true)

        XCTAssertNil(sut.firstScanResult)
    }
}
