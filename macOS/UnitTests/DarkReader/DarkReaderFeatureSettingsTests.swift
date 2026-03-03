//
//  DarkReaderFeatureSettingsTests.swift
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
import PersistenceTestingUtils
import PrivacyConfig
import PrivacyConfigTestsUtils
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class DarkReaderFeatureSettingsTests: XCTestCase {

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

    @available(macOS 15.4, *)
    func testIsFeatureEnabled_WhenBothFlagsAreOn_ReturnsTrue() {
        mockFeatureFlagger.enabledFeatureFlags = [.forceDarkModeOnWebsites, .webExtensions]
        sut = makeSUT()

        XCTAssertTrue(sut.isFeatureEnabled)
    }

    func testIsFeatureEnabled_WhenFlagsAreOff_ReturnsFalse() {
        mockFeatureFlagger.enabledFeatureFlags = []
        sut = makeSUT()

        XCTAssertFalse(sut.isFeatureEnabled)
    }

    func testIsFeatureEnabled_WhenOnlyForceDarkModeFlagIsOn_ReturnsFalse() {
        mockFeatureFlagger.enabledFeatureFlags = [.forceDarkModeOnWebsites]
        sut = makeSUT()

        XCTAssertFalse(sut.isFeatureEnabled)
    }

    func testIsFeatureEnabled_WhenOnlyWebExtensionsFlagIsOn_ReturnsFalse() {
        mockFeatureFlagger.enabledFeatureFlags = [.webExtensions]
        sut = makeSUT()

        XCTAssertFalse(sut.isFeatureEnabled)
    }

    // MARK: - isForceDarkModeEnabled

    func testIsForceDarkModeEnabled_WhenFlagOffAndStoredTrue_ReturnsFalse() {
        mockFeatureFlagger.enabledFeatureFlags = []
        mockStore.set(true, forKey: UserDefaultsKeys.forceDarkModeOnWebsitesEnabled.rawValue)
        sut = makeSUT()

        XCTAssertFalse(sut.isForceDarkModeEnabled)
    }

    @available(macOS 15.4, *)
    func testIsForceDarkModeEnabled_WhenFlagOnAndStoredFalse_ReturnsFalse() {
        mockFeatureFlagger.enabledFeatureFlags = [.forceDarkModeOnWebsites, .webExtensions]
        sut = makeSUT()
        sut.setForceDarkModeEnabled(false)

        XCTAssertFalse(sut.isForceDarkModeEnabled)
    }

    @available(macOS 15.4, *)
    func testIsForceDarkModeEnabled_WhenFlagOnAndStoredTrue_ReturnsTrue() {
        mockFeatureFlagger.enabledFeatureFlags = [.forceDarkModeOnWebsites, .webExtensions]
        sut = makeSUT()
        sut.setForceDarkModeEnabled(true)

        XCTAssertTrue(sut.isForceDarkModeEnabled)
    }

    @available(macOS 15.4, *)
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
        XCTAssertNil(mockStore.object(forKey: UserDefaultsKeys.forceDarkModeOnWebsitesEnabled.rawValue))
    }

    @available(macOS 15.4, *)
    func testSetForceDarkModeEnabled_PersistsValue() {
        mockFeatureFlagger.enabledFeatureFlags = [.forceDarkModeOnWebsites, .webExtensions]
        sut = makeSUT()

        sut.setForceDarkModeEnabled(true)
        XCTAssertTrue(mockStore.object(forKey: UserDefaultsKeys.forceDarkModeOnWebsitesEnabled.rawValue) as? Bool ?? false)

        sut.setForceDarkModeEnabled(false)
        XCTAssertFalse(mockStore.object(forKey: UserDefaultsKeys.forceDarkModeOnWebsitesEnabled.rawValue) as? Bool ?? true)
    }

    @available(macOS 15.4, *)
    func testSetForceDarkModeEnabled_WhenSettingSameValue_DoesNotEmit() {
        mockFeatureFlagger.enabledFeatureFlags = [.forceDarkModeOnWebsites, .webExtensions]
        sut = makeSUT()
        sut.setForceDarkModeEnabled(true)

        var receivedValues: [Bool] = []
        let cancellable = sut.forceDarkModeChangedPublisher
            .sink { receivedValues.append($0) }

        sut.setForceDarkModeEnabled(true)

        XCTAssertTrue(receivedValues.isEmpty)
        cancellable.cancel()
    }

    // MARK: - forceDarkModeChangedPublisher

    @available(macOS 15.4, *)
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

    // MARK: - themeDidChange

    @available(macOS 15.4, *)
    func testThemeDidChange_EmitsCurrentStateOnPublisher() {
        mockFeatureFlagger.enabledFeatureFlags = [.forceDarkModeOnWebsites, .webExtensions]
        sut = makeSUT()
        sut.setForceDarkModeEnabled(true)

        var receivedValues: [Bool] = []
        let cancellable = sut.forceDarkModeChangedPublisher
            .sink { receivedValues.append($0) }

        sut.themeDidChange()

        XCTAssertEqual(receivedValues, [true])
        cancellable.cancel()
    }

    func testThemeDidChange_WhenFeatureDisabled_EmitsFalse() {
        mockFeatureFlagger.enabledFeatureFlags = []
        sut = makeSUT()

        var receivedValues: [Bool] = []
        let cancellable = sut.forceDarkModeChangedPublisher
            .sink { receivedValues.append($0) }

        sut.themeDidChange()

        XCTAssertEqual(receivedValues, [false])
        cancellable.cancel()
    }

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

    func testExcludedDomains_WhenNoExceptions_ReturnsEmptyArray() {
        sut = makeSUT()

        XCTAssertEqual(sut.excludedDomains, [])
    }
}
