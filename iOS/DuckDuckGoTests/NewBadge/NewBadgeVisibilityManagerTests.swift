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

    func testShouldShowBadgeWhenElapsedDaysIsSix() throws {
        let store = MockThrowingKeyValueStore()
        let firstImpressionDate = Date(timeIntervalSince1970: 1_000_000)
        try store.set(firstImpressionDate, forKey: NewBadgeFeature.personalInformationRemoval.firstImpressionDateStorageKey)

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
        try store.set(firstImpressionDate, forKey: NewBadgeFeature.personalInformationRemoval.firstImpressionDateStorageKey)

        let manager = NewBadgeVisibilityManager(
            keyValueStore: store,
            configProvider: MockNewBadgeConfigProvider(),
            currentAppVersionProvider: { "7.100.0" },
            currentDateProvider: { firstImpressionDate.addingTimeInterval(7 * 24 * 60 * 60) }
        )

        XCTAssertFalse(manager.shouldShowBadge(for: .personalInformationRemoval))
    }

    func testShouldNotShowBadgeWhenDisplayDurationIsZero() {
        let manager = NewBadgeVisibilityManager(
            keyValueStore: MockThrowingKeyValueStore(),
            configProvider: MockNewBadgeConfigProvider(displayDurationDays: 0),
            currentAppVersionProvider: { "7.100.0" }
        )

        XCTAssertFalse(manager.shouldShowBadge(for: .personalInformationRemoval))
    }

    func testShouldPersistFirstImpressionDateOnlyOnce() throws {
        let store = MockThrowingKeyValueStore()
        var now = Date(timeIntervalSince1970: 1_000_000)
        let key = NewBadgeFeature.personalInformationRemoval.firstImpressionDateStorageKey

        let manager = NewBadgeVisibilityManager(
            keyValueStore: store,
            configProvider: MockNewBadgeConfigProvider(),
            currentAppVersionProvider: { "7.100.0" },
            currentDateProvider: { now }
        )

        XCTAssertTrue(manager.shouldShowBadge(for: .personalInformationRemoval))
        let firstStoredDate = try XCTUnwrap(try store.object(forKey: key) as? Date)

        now = now.addingTimeInterval(24 * 60 * 60)
        XCTAssertTrue(manager.shouldShowBadge(for: .personalInformationRemoval))
        let secondStoredDate = try XCTUnwrap(try store.object(forKey: key) as? Date)

        XCTAssertEqual(firstStoredDate, secondStoredDate)
    }
}

final class DefaultNewBadgeConfigProviderTests: XCTestCase {

    func testReleaseWindowComparison() {
        let provider = makeProvider(minSupportedVersion: "7.100.0")

        XCTAssertTrue(provider.isWithinReleaseWindow(for: .personalInformationRemoval, currentAppVersion: "7.100.0"))
        XCTAssertTrue(provider.isWithinReleaseWindow(for: .personalInformationRemoval, currentAppVersion: "7.100.2"))
        XCTAssertTrue(provider.isWithinReleaseWindow(for: .personalInformationRemoval, currentAppVersion: "7.102.9"))
        XCTAssertFalse(provider.isWithinReleaseWindow(for: .personalInformationRemoval, currentAppVersion: "7.103.0"))
    }

    private func makeProvider(minSupportedVersion: String) -> DefaultNewBadgeConfigProvider {
        let privacyConfigurationManager = PrivacyConfigTestsUtils.MockPrivacyConfigurationManager()
        privacyConfigurationManager.currentConfigString = """
        {
            "features": {
                "dbp": {
                    "state": "enabled",
                    "features": {
                        "settingsNewBadge": {
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
    let minSupportedVersion: String
    let isWithinReleaseWindowResult: Bool
    let maxMinorReleaseOffsetValue: Int
    let displayDurationDaysValue: Int

    init(isFeatureEnabled: Bool = true,
         minSupportedVersion: String = "7.100.0",
         isWithinReleaseWindowResult: Bool = true,
         maxMinorReleaseOffset: Int = 3,
         displayDurationDays: Int = 7) {
        self.isFeatureEnabled = isFeatureEnabled
        self.minSupportedVersion = minSupportedVersion
        self.isWithinReleaseWindowResult = isWithinReleaseWindowResult
        self.maxMinorReleaseOffsetValue = maxMinorReleaseOffset
        self.displayDurationDaysValue = displayDurationDays
    }

    func isFeatureOn(_ feature: NewBadgeFeature) -> Bool {
        isFeatureEnabled
    }

    func minSupportedVersion(for feature: NewBadgeFeature) -> String? {
        minSupportedVersion
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
