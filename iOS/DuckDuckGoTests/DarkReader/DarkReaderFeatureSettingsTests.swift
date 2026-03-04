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

import XCTest
@testable import DuckDuckGo
import BrowserServicesKit
import Persistence
import PersistenceTestingUtils
import Combine

class DarkReaderFeatureSettingsTests: XCTestCase {

    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockStore: MockKeyValueStore!
    private var mockPrivacyConfigManager: MockPrivacyConfigurationManager!
    private var mockAppSettings: AppSettingsMock!
    private var sut: AppDarkReaderFeatureSettings!

    override func setUp() {
        super.setUp()
        mockFeatureFlagger = MockFeatureFlagger()
        mockStore = MockKeyValueStore()
        mockPrivacyConfigManager = MockPrivacyConfigurationManager()
        mockAppSettings = AppSettingsMock()
    }

    override func tearDown() {
        mockFeatureFlagger = nil
        mockStore = nil
        mockPrivacyConfigManager = nil
        mockAppSettings = nil
        sut = nil
        super.tearDown()
    }

    private func makeSUT() -> AppDarkReaderFeatureSettings {
        AppDarkReaderFeatureSettings(
            featureFlagger: mockFeatureFlagger,
            privacyConfigurationManager: mockPrivacyConfigManager,
            appSettings: mockAppSettings,
            storage: mockStore.keyedStoring()
        )
    }

    // MARK: - isFeatureEnabled

    @available(iOS 18.4, *)
    func testIsFeatureEnabled_WhenFlagIsOn_ReturnsTrue() {
        mockFeatureFlagger.enabledFeatureFlags = [.forceDarkModeOnWebsites, .webExtensions]
        sut = makeSUT()

        XCTAssertTrue(sut.isFeatureEnabled)
    }

    func testIsFeatureEnabled_WhenFlagIsOff_ReturnsFalse() {
        mockFeatureFlagger.enabledFeatureFlags = []
        sut = makeSUT()

        XCTAssertFalse(sut.isFeatureEnabled)
    }

    @available(iOS 18.4, *)
    func testIsFeatureEnabled_WhenFlagIsOnButThemeIsLight_ReturnsFalse() {
        mockFeatureFlagger.enabledFeatureFlags = [.forceDarkModeOnWebsites, .webExtensions]
        mockAppSettings.currentThemeStyle = .light
        sut = makeSUT()

        XCTAssertFalse(sut.isFeatureEnabled)
    }

    @available(iOS 18.4, *)
    func testIsForceDarkModeEnabled_WhenThemeIsLight_ReturnsFalse() {
        mockFeatureFlagger.enabledFeatureFlags = [.forceDarkModeOnWebsites, .webExtensions]
        mockAppSettings.currentThemeStyle = .light
        sut = makeSUT()
        sut.setForceDarkModeEnabled(true)

        XCTAssertFalse(sut.isForceDarkModeEnabled)
    }

    // MARK: - themeDidChange

    @available(iOS 18.4, *)
    func testThemeDidChange_EmitsOnForceDarkModeChangedPublisher() {
        mockFeatureFlagger.enabledFeatureFlags = [.forceDarkModeOnWebsites, .webExtensions]
        sut = makeSUT()
        sut.setForceDarkModeEnabled(true)

        var receivedValues: [Bool] = []
        let cancellable = sut.forceDarkModeChangedPublisher
            .sink { receivedValues.append($0) }

        mockAppSettings.currentThemeStyle = .light
        sut.themeDidChange()

        mockAppSettings.currentThemeStyle = .dark
        sut.themeDidChange()

        XCTAssertEqual(receivedValues, [false, true])
        cancellable.cancel()
    }

    // MARK: - isForceDarkModeEnabled

    func testIsForceDarkModeEnabled_WhenFlagOffAndStoredTrue_ReturnsFalse() {
        mockFeatureFlagger.enabledFeatureFlags = []
        sut = makeSUT()
        sut.setForceDarkModeEnabled(true)

        XCTAssertFalse(sut.isForceDarkModeEnabled)
    }

    func testIsForceDarkModeEnabled_WhenFlagOnAndStoredFalse_ReturnsFalse() {
        mockFeatureFlagger.enabledFeatureFlags = [.forceDarkModeOnWebsites, .webExtensions]
        sut = makeSUT()
        sut.setForceDarkModeEnabled(false)

        XCTAssertFalse(sut.isForceDarkModeEnabled)
    }

    func testIsForceDarkModeEnabled_WhenFlagOnAndStoredTrue_ReturnsTrue() {
        mockFeatureFlagger.enabledFeatureFlags = [.forceDarkModeOnWebsites, .webExtensions]
        sut = makeSUT()
        sut.setForceDarkModeEnabled(true)

        XCTAssertTrue(sut.isForceDarkModeEnabled)
    }

    func testIsForceDarkModeEnabled_WhenFlagOnAndNothingStored_ReturnsFalse() {
        mockFeatureFlagger.enabledFeatureFlags = [.forceDarkModeOnWebsites, .webExtensions]
        sut = makeSUT()

        XCTAssertFalse(sut.isForceDarkModeEnabled)
    }

    // MARK: - setForceDarkModeEnabled

    func testSetForceDarkModeEnabled_WhenFeatureDisabled_DoesNotPersistValue() {
        mockFeatureFlagger.enabledFeatureFlags = []
        sut = makeSUT()

        sut.setForceDarkModeEnabled(true)
        XCTAssertNil(mockStore.object(forKey: DarkReaderStorageKeys.forceDarkModeOnWebsitesEnabled.rawValue))
    }

    @available(iOS 18.4, *)
    func testSetForceDarkModeEnabled_PersistsValue() {
        mockFeatureFlagger.enabledFeatureFlags = [.forceDarkModeOnWebsites, .webExtensions]
        sut = makeSUT()

        sut.setForceDarkModeEnabled(true)
        XCTAssertTrue(mockStore.object(forKey: DarkReaderStorageKeys.forceDarkModeOnWebsitesEnabled.rawValue) as? Bool ?? false)

        sut.setForceDarkModeEnabled(false)
        XCTAssertFalse(mockStore.object(forKey: DarkReaderStorageKeys.forceDarkModeOnWebsitesEnabled.rawValue) as? Bool ?? true)
    }

    // MARK: - forceDarkModeChangedPublisher

    @available(iOS 18.4, *)
    func testForceDarkModeChangedPublisher_EmitsValueOnChange() {
        mockFeatureFlagger.enabledFeatureFlags = [.forceDarkModeOnWebsites, .webExtensions]
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

    func testForceDarkModeChangedPublisher_WhenFeatureDisabled_DoesNotEmit() {
        mockFeatureFlagger.enabledFeatureFlags = []
        sut = makeSUT()
        var receivedValues: [Bool] = []
        let cancellable = sut.forceDarkModeChangedPublisher
            .sink { receivedValues.append($0) }

        sut.setForceDarkModeEnabled(true)

        XCTAssertTrue(receivedValues.isEmpty)
        cancellable.cancel()
    }

    // MARK: - excludedDomains

    // MARK: - excludedDomainsChangedPublisher

    func testExcludedDomainsChangedPublisher_EmitsWhenPrivacyConfigChanges() {
        sut = makeSUT()
        var receivedCount = 0
        let cancellable = sut.excludedDomainsChangedPublisher
            .sink { receivedCount += 1 }

        mockPrivacyConfigManager.updatesSubject.send()
        mockPrivacyConfigManager.updatesSubject.send()

        XCTAssertEqual(receivedCount, 2)
        cancellable.cancel()
    }

    // MARK: - excludedDomains

    func testExcludedDomains_ReturnsExceptionsListFromPrivacyConfig() throws {
        let mockConfig = try XCTUnwrap(mockPrivacyConfigManager.privacyConfig as? MockPrivacyConfiguration)
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
