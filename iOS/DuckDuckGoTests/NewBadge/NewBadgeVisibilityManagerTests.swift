//
//  NewBadgeVisibilityManagerTests.swift
//  DuckDuckGoTests
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
@testable import DuckDuckGo
import PrivacyConfigTestsUtils
import PersistenceTestingUtils

final class NewBadgeVisibilityManagerTests: XCTestCase {

    private static let firstImpressionDateStorageKey = NewBadgeFeature.personalInformationRemoval.firstImpressionDateStorageKey

    func testShouldNotShowBadgeWhenOutsideReleaseWindow() {
        let manager = NewBadgeVisibilityManager(
            keyValueStore: MockThrowingKeyValueStore(),
            configProvider: MockNewBadgeConfigProvider(isWithinReleaseWindowResult: false),
            currentAppVersionProvider: { "7.100.0" }
        )

        XCTAssertFalse(manager.shouldShowBadge(for: .personalInformationRemoval))
    }

    func testShouldNotShowBadgeWhenFeatureIsDisabled() {
        let manager = NewBadgeVisibilityManager(
            keyValueStore: MockThrowingKeyValueStore(),
            configProvider: MockNewBadgeConfigProvider(isFeatureEnabled: false),
            currentAppVersionProvider: { "7.100.0" }
        )

        XCTAssertFalse(manager.shouldShowBadge(for: .personalInformationRemoval))
    }

    func testShouldShowBadgeWhenFirstImpressionDateIsNil() throws {
        let store = MockThrowingKeyValueStore()
        let manager = NewBadgeVisibilityManager(
            keyValueStore: store,
            configProvider: MockNewBadgeConfigProvider(),
            currentAppVersionProvider: { "7.100.0" }
        )

        XCTAssertTrue(manager.shouldShowBadge(for: .personalInformationRemoval))
        XCTAssertNil(try store.object(forKey: Self.firstImpressionDateStorageKey) as? Date)
    }

    func testShouldShowBadgeWhenElapsedDaysIsSix() throws {
        let store = MockThrowingKeyValueStore()
        let firstImpressionDate = Date(timeIntervalSince1970: 1_000_000)
        try store.set(firstImpressionDate, forKey: Self.firstImpressionDateStorageKey)

        let manager = NewBadgeVisibilityManager(
            keyValueStore: store,
            configProvider: MockNewBadgeConfigProvider(),
            currentAppVersionProvider: { "7.100.0" },
            currentDateProvider: { firstImpressionDate.addingTimeInterval(6 * 24 * 60 * 60) }
        )

        XCTAssertTrue(manager.shouldShowBadge(for: .personalInformationRemoval))
    }

    func testShouldNotShowBadgeWhenElapsedDaysIsSeven() throws {
        let store = MockThrowingKeyValueStore()
        let firstImpressionDate = Date(timeIntervalSince1970: 1_000_000)
        try store.set(firstImpressionDate, forKey: Self.firstImpressionDateStorageKey)

        let manager = NewBadgeVisibilityManager(
            keyValueStore: store,
            configProvider: MockNewBadgeConfigProvider(),
            currentAppVersionProvider: { "7.100.0" },
            currentDateProvider: { firstImpressionDate.addingTimeInterval(7 * 24 * 60 * 60) }
        )

        XCTAssertFalse(manager.shouldShowBadge(for: .personalInformationRemoval))
    }

    func testStoreFirstImpressionDateIfNeededDoesNotStoreWhenOutsideReleaseWindow() throws {
        let store = MockThrowingKeyValueStore()
        let manager = NewBadgeVisibilityManager(
            keyValueStore: store,
            configProvider: MockNewBadgeConfigProvider(isWithinReleaseWindowResult: false),
            currentAppVersionProvider: { "7.100.0" }
        )

        manager.storeFirstImpressionDateIfNeeded(for: .personalInformationRemoval)

        XCTAssertNil(try store.object(forKey: Self.firstImpressionDateStorageKey) as? Date)
    }

    func testStoreFirstImpressionDateIfNeededStoresWhenEligibleAndDateIsNil() throws {
        let store = MockThrowingKeyValueStore()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let manager = NewBadgeVisibilityManager(
            keyValueStore: store,
            configProvider: MockNewBadgeConfigProvider(),
            currentAppVersionProvider: { "7.100.0" },
            currentDateProvider: { now }
        )

        manager.storeFirstImpressionDateIfNeeded(for: .personalInformationRemoval)

        XCTAssertEqual(try store.object(forKey: Self.firstImpressionDateStorageKey) as? Date, now)
    }

    func testStoreFirstImpressionDateIfNeededDoesNotOverwriteExistingDate() throws {
        let store = MockThrowingKeyValueStore()
        let existingDate = Date(timeIntervalSince1970: 1_000_000)
        try store.set(existingDate, forKey: Self.firstImpressionDateStorageKey)
        var now = existingDate
        let manager = NewBadgeVisibilityManager(
            keyValueStore: store,
            configProvider: MockNewBadgeConfigProvider(),
            currentAppVersionProvider: { "7.100.0" },
            currentDateProvider: { now }
        )

        manager.storeFirstImpressionDateIfNeeded(for: .personalInformationRemoval)
        now = now.addingTimeInterval(24 * 60 * 60)
        manager.storeFirstImpressionDateIfNeeded(for: .personalInformationRemoval)

        XCTAssertEqual(try store.object(forKey: Self.firstImpressionDateStorageKey) as? Date, existingDate)
    }
}

final class DefaultNewBadgeConfigProviderTests: XCTestCase {

    func testReleaseWindowComparison() {
        let provider = makeProvider(minSupportedVersion: "7.100.0")

        XCTAssertFalse(provider.isWithinReleaseWindow(for: .personalInformationRemoval, currentAppVersion: "7.99.0"))
        XCTAssertTrue(provider.isWithinReleaseWindow(for: .personalInformationRemoval, currentAppVersion: "7.100.0"))
        XCTAssertTrue(provider.isWithinReleaseWindow(for: .personalInformationRemoval, currentAppVersion: "7.100.2"))
        XCTAssertTrue(provider.isWithinReleaseWindow(for: .personalInformationRemoval, currentAppVersion: "7.102.9"))
        XCTAssertFalse(provider.isWithinReleaseWindow(for: .personalInformationRemoval, currentAppVersion: "7.103.0"))
    }

    func testMinSupportedVersionIsReadFromPrivacyConfig() {
        let appVersion = "7.100.0"
        let providerMin100 = makeProvider(minSupportedVersion: "7.100.0")
        let providerMin101 = makeProvider(minSupportedVersion: "7.101.0")

        XCTAssertTrue(providerMin100.isWithinReleaseWindow(for: .personalInformationRemoval, currentAppVersion: appVersion))
        XCTAssertFalse(providerMin101.isWithinReleaseWindow(for: .personalInformationRemoval, currentAppVersion: appVersion))
    }

    private func makeProvider(minSupportedVersion: String) -> DefaultNewBadgeConfigProvider {
        let privacyConfigurationManager = PrivacyConfigTestsUtils.MockPrivacyConfigurationManager()
        privacyConfigurationManager.currentConfigString = """
        {
            "features": {
                "dbp": {
                    "state": "enabled",
                    "features": {
                        "goToMarket": {
                            "state": "enabled",
                            "minSupportedVersion": "\(minSupportedVersion)"
                        }
                    }
                }
            },
            "unprotectedTemporary": []
        }
        """

        return DefaultNewBadgeConfigProvider(
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.personalInformationRemoval]),
            privacyConfigurationManager: privacyConfigurationManager
        )
    }
}

private struct MockNewBadgeConfigProvider: NewBadgeConfigProviding {

    let isFeatureEnabled: Bool
    let isWithinReleaseWindowResult: Bool
    let maxMinorReleaseOffsetValue: Int
    let displayDurationDaysValue: Int

    init(isFeatureEnabled: Bool = true,
         isWithinReleaseWindowResult: Bool = true,
         maxMinorReleaseOffset: Int = 3,
         displayDurationDays: Int = 7) {
        self.isFeatureEnabled = isFeatureEnabled
        self.isWithinReleaseWindowResult = isWithinReleaseWindowResult
        self.maxMinorReleaseOffsetValue = maxMinorReleaseOffset
        self.displayDurationDaysValue = displayDurationDays
    }

    func isFeatureOn(_ feature: NewBadgeFeature) -> Bool {
        isFeatureEnabled
    }

    func isWithinReleaseWindow(for feature: NewBadgeFeature, currentAppVersion: String) -> Bool {
        isWithinReleaseWindowResult
    }

    func maxMinorReleaseOffset(for feature: NewBadgeFeature) -> Int {
        maxMinorReleaseOffsetValue
    }

    func displayDurationDays(for feature: NewBadgeFeature) -> Int {
        displayDurationDaysValue
    }
}
