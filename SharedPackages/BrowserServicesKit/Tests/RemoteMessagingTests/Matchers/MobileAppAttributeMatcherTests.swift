//
//  MobileAppAttributeMatcherTests.swift
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

import BrowserServicesKitTestsUtils
import Common
import Foundation
import RemoteMessagingTestsUtils
import XCTest
@testable import RemoteMessaging

class MobileAppAttributeMatcherTests: XCTestCase {

    private func makeMatcher(canUpgradeOS: Bool) -> MobileAppAttributeMatcher {
        let mockStatisticsStore = MockStatisticsStore()
        mockStatisticsStore.atb = "v105-2"

        let manager = MockVariantManager(isSupportedReturns: true, currentVariant: MockVariant(name: "zo", weight: 44, isIncluded: { return true }, features: [.dummy]))
        return MobileAppAttributeMatcher(
            bundleId: AppVersion.shared.identifier,
            appVersion: "3.2.1",
            isInternalUser: true,
            statisticsStore: mockStatisticsStore,
            variantManager: manager,
            canUpgradeOS: canUpgradeOS
        )
    }

    // MARK: - OSUpgradeCapability (canUpgradeOS)

    func testWhenCanUpgradeOSMatchesThenReturnMatch() throws {
        let matcher = makeMatcher(canUpgradeOS: true)
        XCTAssertEqual(matcher.evaluate(matchingAttribute: OSUpgradeCapabilityMatchingAttribute(value: true, fallback: nil)),
                       .match)
    }

    func testWhenCanUpgradeOSDoesNotMatchThenReturnFail() throws {
        let matcher = makeMatcher(canUpgradeOS: true)
        XCTAssertEqual(matcher.evaluate(matchingAttribute: OSUpgradeCapabilityMatchingAttribute(value: false, fallback: nil)),
                       .fail)
    }

    func testWhenCannotUpgradeOSAndAttributeIsFalseThenReturnMatch() throws {
        let matcher = makeMatcher(canUpgradeOS: false)
        XCTAssertEqual(matcher.evaluate(matchingAttribute: OSUpgradeCapabilityMatchingAttribute(value: false, fallback: nil)),
                       .match)
        XCTAssertEqual(matcher.evaluate(matchingAttribute: OSUpgradeCapabilityMatchingAttribute(value: true, fallback: nil)),
                       .fail)
    }

    func testWhenCanUpgradeOSIsNotSpecifiedThenDefaultsToCapable() throws {
        let matcher = MobileAppAttributeMatcher(statisticsStore: MockStatisticsStore(), variantManager: MockVariantManager())
        XCTAssertEqual(matcher.evaluate(matchingAttribute: OSUpgradeCapabilityMatchingAttribute(value: true, fallback: nil)),
                       .match)
    }

    // MARK: - Common attributes

    func testWhenCommonAttributeIsEvaluatedThenDelegatesToCommonMatcher() throws {
        let matcher = makeMatcher(canUpgradeOS: false)
        XCTAssertEqual(matcher.evaluate(matchingAttribute: AtbMatchingAttribute(value: "v105-2", fallback: nil)),
                       .match)
        XCTAssertEqual(matcher.evaluate(matchingAttribute: IsInternalUserMatchingAttribute(value: false, fallback: nil)),
                       .fail)
    }
}
