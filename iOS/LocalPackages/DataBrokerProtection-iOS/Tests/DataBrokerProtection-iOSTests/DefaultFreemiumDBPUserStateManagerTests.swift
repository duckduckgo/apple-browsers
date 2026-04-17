//
//  DefaultFreemiumDBPUserStateManagerTests.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
}
