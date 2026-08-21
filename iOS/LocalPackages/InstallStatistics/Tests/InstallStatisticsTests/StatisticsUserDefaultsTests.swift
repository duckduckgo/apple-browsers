//
//  StatisticsUserDefaultsTests.swift
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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
@testable import InstallStatistics

final class StatisticsUserDefaultsTests: XCTestCase {

    private enum Constants {
        static let suiteName = "StatisticsUserDefaultsTestSuite"
        static let otherSuiteName = "StatisticsUserDefaultsOtherTestSuite"
        static let installDateKey = "com.duckduckgo.statistics.installdate.key"
        static let atbKey = "com.duckduckgo.statistics.atb.key"
        static let searchRetentionAtbKey = "com.duckduckgo.statistics.retentionatb.key"
        static let appRetentionAtbKey = "com.duckduckgo.statistics.appretentionatb.key"
        static let duckAIRetentionAtbKey = "com.duckduckgo.statistics.duckairetentionatb.key"
        static let variantKey = "com.duckduckgo.statistics.variant.key"
        static let installDate = Date(timeIntervalSince1970: 1_700_000_000)
        static let atb = "v123-4"
        static let searchRetentionAtb = "v120-1"
        static let appRetentionAtb = "v121-2"
        static let duckAIRetentionAtb = "v122-3"
        static let variant = "ru"
    }

    private var testee: StatisticsUserDefaults!
    private var userDefaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        removePersistentDomains()
        userDefaults = try XCTUnwrap(UserDefaults(suiteName: Constants.suiteName))
        testee = StatisticsUserDefaults(groupName: Constants.suiteName)
    }

    override func tearDownWithError() throws {
        testee = nil
        userDefaults = nil
        removePersistentDomains()
        try super.tearDownWithError()
    }

    func testWhenStoreIsEmptyThenReturnsEmptyState() {
        XCTAssertNil(testee.installDate)
        XCTAssertNil(testee.atb)
        XCTAssertNil(testee.searchRetentionAtb)
        XCTAssertNil(testee.appRetentionAtb)
        XCTAssertNil(testee.duckAIRetentionAtb)
        XCTAssertNil(testee.variant)
        XCTAssertFalse(testee.hasInstallStatistics)
    }

    func testWhenValuesAreWrittenThenLegacyKeysContainExpectedRepresentations() {
        testee.installDate = Constants.installDate
        testee.atb = Constants.atb
        testee.searchRetentionAtb = Constants.searchRetentionAtb
        testee.appRetentionAtb = Constants.appRetentionAtb
        testee.duckAIRetentionAtb = Constants.duckAIRetentionAtb
        testee.variant = Constants.variant

        XCTAssertEqual(userDefaults.double(forKey: Constants.installDateKey), Constants.installDate.timeIntervalSince1970)
        XCTAssertEqual(userDefaults.string(forKey: Constants.atbKey), Constants.atb)
        XCTAssertEqual(userDefaults.string(forKey: Constants.searchRetentionAtbKey), Constants.searchRetentionAtb)
        XCTAssertEqual(userDefaults.string(forKey: Constants.appRetentionAtbKey), Constants.appRetentionAtb)
        XCTAssertEqual(userDefaults.string(forKey: Constants.duckAIRetentionAtbKey), Constants.duckAIRetentionAtb)
        XCTAssertEqual(userDefaults.string(forKey: Constants.variantKey), Constants.variant)
    }

    func testWhenLegacyKeysContainValuesThenPropertiesReturnThem() {
        userDefaults.set(Constants.installDate.timeIntervalSince1970, forKey: Constants.installDateKey)
        userDefaults.set(Constants.atb, forKey: Constants.atbKey)
        userDefaults.set(Constants.searchRetentionAtb, forKey: Constants.searchRetentionAtbKey)
        userDefaults.set(Constants.appRetentionAtb, forKey: Constants.appRetentionAtbKey)
        userDefaults.set(Constants.duckAIRetentionAtb, forKey: Constants.duckAIRetentionAtbKey)
        userDefaults.set(Constants.variant, forKey: Constants.variantKey)

        XCTAssertEqual(testee.installDate, Constants.installDate)
        XCTAssertEqual(testee.atb, Constants.atb)
        XCTAssertEqual(testee.searchRetentionAtb, Constants.searchRetentionAtb)
        XCTAssertEqual(testee.appRetentionAtb, Constants.appRetentionAtb)
        XCTAssertEqual(testee.duckAIRetentionAtb, Constants.duckAIRetentionAtb)
        XCTAssertEqual(testee.variant, Constants.variant)
        XCTAssertTrue(testee.hasInstallStatistics)
    }

    func testWhenInstallDateIsZeroOrNegativeThenReturnsNil() {
        userDefaults.set(0, forKey: Constants.installDateKey)
        XCTAssertNil(testee.installDate)

        userDefaults.set(-1, forKey: Constants.installDateKey)
        XCTAssertNil(testee.installDate)
    }

    func testWhenValuesAreSetToNilThenLegacyKeysAreRemoved() {
        testee.installDate = Constants.installDate
        testee.atb = Constants.atb
        testee.searchRetentionAtb = Constants.searchRetentionAtb
        testee.appRetentionAtb = Constants.appRetentionAtb
        testee.duckAIRetentionAtb = Constants.duckAIRetentionAtb
        testee.variant = Constants.variant

        testee.installDate = nil
        testee.atb = nil
        testee.searchRetentionAtb = nil
        testee.appRetentionAtb = nil
        testee.duckAIRetentionAtb = nil
        testee.variant = nil

        XCTAssertNil(userDefaults.object(forKey: Constants.installDateKey))
        XCTAssertNil(userDefaults.object(forKey: Constants.atbKey))
        XCTAssertNil(userDefaults.object(forKey: Constants.searchRetentionAtbKey))
        XCTAssertNil(userDefaults.object(forKey: Constants.appRetentionAtbKey))
        XCTAssertNil(userDefaults.object(forKey: Constants.duckAIRetentionAtbKey))
        XCTAssertNil(userDefaults.object(forKey: Constants.variantKey))
        XCTAssertFalse(testee.hasInstallStatistics)
    }

    func testWhenRetentionValuesAreMissingThenAtbIsReturned() {
        testee.atb = Constants.atb

        XCTAssertEqual(testee.searchRetentionAtb, Constants.atb)
        XCTAssertEqual(testee.appRetentionAtb, Constants.atb)
    }

    func testWhenRetentionValuesExistThenTheyOverrideAtb() {
        testee.atb = Constants.atb
        testee.searchRetentionAtb = Constants.searchRetentionAtb
        testee.appRetentionAtb = Constants.appRetentionAtb

        XCTAssertEqual(testee.searchRetentionAtb, Constants.searchRetentionAtb)
        XCTAssertEqual(testee.appRetentionAtb, Constants.appRetentionAtb)
    }

    func testWhenDuckAIRetentionValueIsMissingThenDoesNotFallBackToAtb() {
        testee.atb = Constants.atb

        XCTAssertNil(testee.duckAIRetentionAtb)
    }

    func testWhenCreatingAnotherStoreForSameSuiteThenValuesPersist() {
        testee.atb = Constants.atb
        testee.variant = Constants.variant

        let otherStore = StatisticsUserDefaults(groupName: Constants.suiteName)

        XCTAssertEqual(otherStore.atb, Constants.atb)
        XCTAssertEqual(otherStore.variant, Constants.variant)
    }

    func testWhenCreatingStoreForDifferentSuiteThenValuesAreIsolated() {
        testee.atb = Constants.atb

        let otherStore = StatisticsUserDefaults(groupName: Constants.otherSuiteName)

        XCTAssertNil(otherStore.atb)
    }

    func testWhenAtbIsMissingThenAtbWithVariantReturnsNil() {
        testee.variant = Constants.variant

        XCTAssertNil(testee.atbWithVariant)
    }

    func testWhenVariantIsMissingThenAtbWithVariantReturnsAtb() {
        testee.atb = Constants.atb

        XCTAssertEqual(testee.atbWithVariant, Constants.atb)
    }

    func testWhenAtbAndVariantExistThenAtbWithVariantReturnsCombinedValue() {
        testee.atb = Constants.atb
        testee.variant = Constants.variant

        XCTAssertEqual(testee.atbWithVariant, Constants.atb + Constants.variant)
    }

    private func removePersistentDomains() {
        UserDefaults.standard.removePersistentDomain(forName: Constants.suiteName)
        UserDefaults.standard.removePersistentDomain(forName: Constants.otherSuiteName)
    }
}
