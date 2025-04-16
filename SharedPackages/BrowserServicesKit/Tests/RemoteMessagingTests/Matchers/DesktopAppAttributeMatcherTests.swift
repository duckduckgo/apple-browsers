//
//  DesktopAppAttributeMatcherTests.swift
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

import BrowserServicesKitTestsUtils
import Common
import Foundation
import RemoteMessagingTestsUtils
import XCTest
@testable import RemoteMessaging

class DesktopAppAttributeMatcherTests: XCTestCase {

    private var matcher: DesktopAppAttributeMatcher!

    override func setUpWithError() throws {
        try super.setUpWithError()

        let mockStatisticsStore = MockStatisticsStore()
        mockStatisticsStore.atb = "v105-2"
        mockStatisticsStore.appRetentionAtb = "v105-44"
        mockStatisticsStore.searchRetentionAtb = "v105-88"

        let manager = MockVariantManager(isSupportedReturns: true, currentVariant: MockVariant(name: "zo", weight: 44, isIncluded: { return true }, features: [.dummy]))
        matcher = DesktopAppAttributeMatcher(statisticsStore: mockStatisticsStore, variantManager: manager, isInstalledMacAppStore: false)
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()

        matcher = nil
    }

    // MARK: - InstalledMacAppStore

    func testWhenInstalledMacAppStoreMatchesThenReturnMatch() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: IsInstalledMacAppStoreMatchingAttribute(value: false, fallback: nil)),
                       .match)
    }

    func testWhenWidgetAddedDoesNotMatchThenReturnFail() throws {
        XCTAssertEqual(matcher.evaluate(matchingAttribute: IsInstalledMacAppStoreMatchingAttribute(value: true, fallback: nil)),
                       .fail)
    }
}
