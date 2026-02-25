//
//  DarkReaderFeatureSettingsTests.swift
//  DuckDuckGo
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

import Combine
import XCTest
@testable import DuckDuckGo
import BrowserServicesKit
import Persistence
import PersistenceTestingUtils

class DarkReaderFeatureSettingsTests: XCTestCase {

    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockStore: MockKeyValueStore!
    private var mockPrivacyConfigManager: MockPrivacyConfigurationManager!
    private var sut: AppDarkReaderFeatureSettings!

    override func setUp() {
        super.setUp()
        mockFeatureFlagger = MockFeatureFlagger()
        mockStore = MockKeyValueStore()
        mockPrivacyConfigManager = MockPrivacyConfigurationManager()
    }

    override func tearDown() {
        mockFeatureFlagger = nil
        mockStore = nil
        mockPrivacyConfigManager = nil
        sut = nil
        super.tearDown()
    }

    private func makeSUT() -> AppDarkReaderFeatureSettings {
        AppDarkReaderFeatureSettings(
            featureFlagger: mockFeatureFlagger,
            privacyConfigurationManager: mockPrivacyConfigManager,
            storage: mockStore.keyedStoring()
        )
    }

    // MARK: - isFeatureEnabled

    func testIsFeatureEnabled_WhenFlagIsOn_ReturnsTrue() {
        mockFeatureFlagger.enabledFeatureFlags = [.forceDarkModeOnWebsites]
        sut = makeSUT()

        XCTAssertTrue(sut.isFeatureEnabled)
    }

    func testIsFeatureEnabled_WhenFlagIsOff_ReturnsFalse() {
        mockFeatureFlagger.enabledFeatureFlags = []
        sut = makeSUT()

        XCTAssertFalse(sut.isFeatureEnabled)
    }

    // MARK: - isForceDarkModeEnabled

    func testIsForceDarkModeEnabled_WhenFlagOffAndStoredTrue_ReturnsFalse() {
        mockFeatureFlagger.enabledFeatureFlags = []
        sut = makeSUT()
        sut.setForceDarkModeEnabled(true)

        XCTAssertFalse(sut.isForceDarkModeEnabled)
    }

    func testIsForceDarkModeEnabled_WhenFlagOnAndStoredFalse_ReturnsFalse() {
        mockFeatureFlagger.enabledFeatureFlags = [.forceDarkModeOnWebsites]
        sut = makeSUT()
        sut.setForceDarkModeEnabled(false)

        XCTAssertFalse(sut.isForceDarkModeEnabled)
    }

    func testIsForceDarkModeEnabled_WhenFlagOnAndStoredTrue_ReturnsTrue() {
        mockFeatureFlagger.enabledFeatureFlags = [.forceDarkModeOnWebsites]
        sut = makeSUT()
        sut.setForceDarkModeEnabled(true)

        XCTAssertTrue(sut.isForceDarkModeEnabled)
    }

    func testIsForceDarkModeEnabled_WhenFlagOnAndNothingStored_ReturnsFalse() {
        mockFeatureFlagger.enabledFeatureFlags = [.forceDarkModeOnWebsites]
        sut = makeSUT()

        XCTAssertFalse(sut.isForceDarkModeEnabled)
    }

    // MARK: - setForceDarkModeEnabled

    func testSetForceDarkModeEnabled_PersistsValue() {
        sut = makeSUT()

        sut.setForceDarkModeEnabled(true)
        XCTAssertTrue(mockStore.object(forKey: DarkReaderStorageKeys.forceDarkModeOnWebsitesEnabled.rawValue) as? Bool ?? false)

        sut.setForceDarkModeEnabled(false)
        XCTAssertFalse(mockStore.object(forKey: DarkReaderStorageKeys.forceDarkModeOnWebsitesEnabled.rawValue) as? Bool ?? true)
    }

    // MARK: - forceDarkModeChangedPublisher

    func testForceDarkModeChangedPublisher_EmitsValueOnChange() {
        sut = makeSUT()
        var receivedValues: [Bool] = []
        let cancellable = sut.forceDarkModeChangedPublisher
            .sink { receivedValues.append($0) }

        sut.setForceDarkModeEnabled(true)
        sut.setForceDarkModeEnabled(false)
        sut.setForceDarkModeEnabled(true)

        XCTAssertEqual(receivedValues, [true, false, true])
        cancellable.cancel()
    }

    // MARK: - excludedDomains

    func testExcludedDomains_ReturnsExceptionsListFromPrivacyConfig() {
        let mockConfig = mockPrivacyConfigManager.privacyConfig as! MockPrivacyConfiguration
        mockConfig.exceptionsList = { feature in
            if feature == .forceDarkModeOnWebsites {
                return ["example.com", "test.org"]
            }
            return []
        }
        sut = makeSUT()

        XCTAssertEqual(sut.excludedDomains, ["example.com", "test.org"])
    }

    func testExcludedDomains_WhenNoExceptions_ReturnsEmptyArray() {
        sut = makeSUT()

        XCTAssertEqual(sut.excludedDomains, [])
    }
}
