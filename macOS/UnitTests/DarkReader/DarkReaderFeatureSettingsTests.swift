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
import PixelKit
import PixelKitTestingUtilities
import PrivacyConfig
import PrivacyConfigTestsUtils
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class DarkReaderFeatureSettingsTests: XCTestCase {

    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockStore: MockThrowingKeyValueStore!
    private var mockPrivacyConfigManager: MockPrivacyConfigurationManager!
    private var mockThemeProvider: MockDarkReaderCurrentThemeProvider!
    private var sut: AppDarkReaderFeatureSettings!

    override func setUp() {
        super.setUp()
        mockFeatureFlagger = MockFeatureFlagger()
        mockStore = MockThrowingKeyValueStore()
        mockPrivacyConfigManager = MockPrivacyConfigurationManager()
        mockThemeProvider = MockDarkReaderCurrentThemeProvider()
    }

    override func tearDown() {
        mockFeatureFlagger = nil
        mockStore = nil
        mockPrivacyConfigManager = nil
        mockThemeProvider = nil
        sut = nil
        super.tearDown()
    }

    private func makeSUT(currentThemeProvider: DarkReaderCurrentThemeProviding? = nil, pixelFiring: PixelFiring? = nil) -> AppDarkReaderFeatureSettings {
        AppDarkReaderFeatureSettings(
            featureFlagger: mockFeatureFlagger,
            privacyConfigurationManager: mockPrivacyConfigManager,
            storage: mockStore.throwingKeyedStoring(),
            currentThemeProvider: currentThemeProvider ?? mockThemeProvider,
            pixelFiring: pixelFiring
        )
    }

    // MARK: - isFeatureEnabled

    @available(macOS 15.4, *)
    func testIsFeatureEnabled_WhenBothFlagsAreOnAndDarkTheme_ReturnsTrue() {
        mockFeatureFlagger.enabledFeatureFlags = [.forceDarkModeOnWebsites, .webExtensions]
        mockThemeProvider.isLightTheme = false
        sut = makeSUT()

        XCTAssertTrue(sut.isFeatureEnabled)
    }

    @available(macOS 15.4, *)
    func testIsFeatureEnabled_WhenBothFlagsAreOnAndLightTheme_ReturnsFalse() {
        mockFeatureFlagger.enabledFeatureFlags = [.forceDarkModeOnWebsites, .webExtensions]
        mockThemeProvider.isLightTheme = true
        sut = makeSUT()

        XCTAssertFalse(sut.isFeatureEnabled)
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

    func testIsForceDarkModeEnabled_WhenFlagOffAndStoredTrue_ReturnsFalse() throws {
        mockFeatureFlagger.enabledFeatureFlags = []
        try mockStore.set(true, forKey: UserDefaultsKeys.forceDarkModeOnWebsites.rawValue)
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

    func testSetForceDarkModeEnabled_WhenFeatureDisabled_DoesNotPersistValue() throws {
        mockFeatureFlagger.enabledFeatureFlags = []
        sut = makeSUT()

        sut.setForceDarkModeEnabled(true)
        XCTAssertNil(try mockStore.object(forKey: UserDefaultsKeys.forceDarkModeOnWebsites.rawValue))
    }

    @available(macOS 15.4, *)
    func testSetForceDarkModeEnabled_PersistsValue() throws {
        mockFeatureFlagger.enabledFeatureFlags = [.forceDarkModeOnWebsites, .webExtensions]
        sut = makeSUT()

        sut.setForceDarkModeEnabled(true)
        XCTAssertTrue(try mockStore.object(forKey: UserDefaultsKeys.forceDarkModeOnWebsites.rawValue) as? Bool ?? false)

        sut.setForceDarkModeEnabled(false)
        XCTAssertFalse(try mockStore.object(forKey: UserDefaultsKeys.forceDarkModeOnWebsites.rawValue) as? Bool ?? true)
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

    // MARK: - Pixel Firing

    @available(macOS 15.4, *)
    func testSetForceDarkModeEnabled_WhenEnabling_FiresDarkReaderEnabledPixel() {
        let pixelMock = PixelKitMock(expecting: [
            ExpectedFireCall(pixel: WebExtensionPixel.darkReaderEnabled, frequency: .dailyAndCount)
        ])
        mockFeatureFlagger.enabledFeatureFlags = [.forceDarkModeOnWebsites, .webExtensions]
        sut = makeSUT(pixelFiring: pixelMock)

        sut.setForceDarkModeEnabled(true)

        pixelMock.verifyExpectations(file: #file, line: #line)
    }

    @available(macOS 15.4, *)
    func testSetForceDarkModeEnabled_WhenDisabling_FiresDarkReaderDisabledPixel() {
        let pixelMock = PixelKitMock(expecting: [
            ExpectedFireCall(pixel: WebExtensionPixel.darkReaderEnabled, frequency: .dailyAndCount),
            ExpectedFireCall(pixel: WebExtensionPixel.darkReaderDisabled, frequency: .dailyAndCount)
        ])
        mockFeatureFlagger.enabledFeatureFlags = [.forceDarkModeOnWebsites, .webExtensions]
        sut = makeSUT(pixelFiring: pixelMock)

        sut.setForceDarkModeEnabled(true)
        sut.setForceDarkModeEnabled(false)

        pixelMock.verifyExpectations(file: #file, line: #line)
    }

    func testSetForceDarkModeEnabled_WhenFeatureDisabled_DoesNotFirePixel() {
        let pixelMock = PixelKitMock(expecting: [])
        mockFeatureFlagger.enabledFeatureFlags = []
        sut = makeSUT(pixelFiring: pixelMock)

        sut.setForceDarkModeEnabled(true)

        pixelMock.verifyExpectations(file: #file, line: #line)
    }

    @available(macOS 15.4, *)
    func testSetForceDarkModeEnabled_WhenSettingSameValue_DoesNotFirePixel() {
        let pixelMock = PixelKitMock(expecting: [
            ExpectedFireCall(pixel: WebExtensionPixel.darkReaderEnabled, frequency: .dailyAndCount)
        ])
        mockFeatureFlagger.enabledFeatureFlags = [.forceDarkModeOnWebsites, .webExtensions]
        sut = makeSUT(pixelFiring: pixelMock)

        sut.setForceDarkModeEnabled(true)
        sut.setForceDarkModeEnabled(true)

        pixelMock.verifyExpectations(file: #file, line: #line)
    }
}

final class MockDarkReaderCurrentThemeProvider: DarkReaderCurrentThemeProviding {
    var isLightTheme: Bool = false
}
