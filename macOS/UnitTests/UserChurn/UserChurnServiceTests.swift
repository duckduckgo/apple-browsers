//
//  UserChurnServiceTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import PixelKit
import PersistenceTestingUtils
@testable import DuckDuckGo_Privacy_Browser

final class MockPixelFiring: PixelFiring {
    var firedPixels: [(event: PixelKitEvent, frequency: PixelKit.Frequency)] = []

    func fire(_ event: PixelKitEvent) {
        fire(event, frequency: .standard)
    }

    func fire(_ event: PixelKitEvent, frequency: PixelKit.Frequency) {
        firedPixels.append((event: event, frequency: frequency))
    }
}

final class UserChurnServiceTests: XCTestCase {

    private var sut: UserChurnService!
    private var mockDefaultBrowserProvider: MockDefaultBrowserProvider!
    private var mockKeyValueStore: MockThrowingKeyValueStore!
    private var mockPixelFiring: MockPixelFiring!
    private var mockBundleIdentifiers: [URL: String]!

    override func setUp() {
        super.setUp()

        mockDefaultBrowserProvider = MockDefaultBrowserProvider()
        mockKeyValueStore = MockThrowingKeyValueStore()
        mockPixelFiring = MockPixelFiring()
        mockBundleIdentifiers = [:]

        sut = UserChurnService(
            defaultBrowserProvider: mockDefaultBrowserProvider,
            keyValueStore: mockKeyValueStore,
            pixelFiring: mockPixelFiring,
            atbProvider: { "v123-4" },
            bundleIdentifierProvider: { [weak self] url in
                self?.mockBundleIdentifiers[url]
            }
        )
    }

    override func tearDown() {
        sut = nil
        mockDefaultBrowserProvider = nil
        mockKeyValueStore = nil
        mockPixelFiring = nil
        mockBundleIdentifiers = nil
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func setDefaultBrowserAsDuckDuckGo(bundleId: String = "com.duckduckgo.macos.browser") {
        let url = URL(fileURLWithPath: "/Applications/DuckDuckGo.app")
        mockDefaultBrowserProvider.defaultBrowserURL = url
        mockBundleIdentifiers[url] = bundleId
    }

    private func setDefaultBrowserAsNonDuckDuckGo(path: String, bundleId: String) {
        let url = URL(fileURLWithPath: path)
        mockDefaultBrowserProvider.defaultBrowserURL = url
        mockBundleIdentifiers[url] = bundleId
    }

    // MARK: - Tests: DuckDuckGo is currently the default browser

    func testWhenDuckDuckGoIsDefaultAndWasDefault_ThenNoPixelFired() throws {
        // Given
        setDefaultBrowserAsDuckDuckGo()
        try mockKeyValueStore.set(true, forKey: "user-churn.was-default-browser")

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertTrue(mockPixelFiring.firedPixels.isEmpty, "No pixel should be fired when DuckDuckGo is still the default")
    }

    func testWhenDuckDuckGoIsDefaultAndWasDefault_ThenStoredStateNotUpdated() throws {
        // Given
        setDefaultBrowserAsDuckDuckGo()
        try mockKeyValueStore.set(true, forKey: "user-churn.was-default-browser")

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(try mockKeyValueStore.object(forKey: "user-churn.was-default-browser") as? Bool, true)
    }

    func testWhenDuckDuckGoIsDefaultAndWasNotDefault_ThenNoPixelFired() throws {
        // Given
        setDefaultBrowserAsDuckDuckGo()
        try mockKeyValueStore.set(false, forKey: "user-churn.was-default-browser")

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertTrue(mockPixelFiring.firedPixels.isEmpty, "No pixel should be fired when DuckDuckGo becomes the default")
    }

    func testWhenDuckDuckGoIsDefaultAndWasNotDefault_ThenStoredStateUpdatedToTrue() throws {
        // Given
        setDefaultBrowserAsDuckDuckGo()
        try mockKeyValueStore.set(false, forKey: "user-churn.was-default-browser")

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(try mockKeyValueStore.object(forKey: "user-churn.was-default-browser") as? Bool, true)
    }

    // MARK: - Tests: DuckDuckGo is not the default browser

    func testWhenDuckDuckGoIsNotDefaultAndWasDefault_ThenPixelFired() throws {
        // Given
        setDefaultBrowserAsNonDuckDuckGo(path: "/Applications/Safari.app", bundleId: "com.apple.Safari")
        try mockKeyValueStore.set(true, forKey: "user-churn.was-default-browser")

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(mockPixelFiring.firedPixels.count, 1, "Pixel should be fired when user changes default away from DuckDuckGo")
        XCTAssertEqual(mockPixelFiring.firedPixels.first?.event.name, "m_mac_unset-as-default")
    }

    func testWhenDuckDuckGoIsNotDefaultAndWasDefault_ThenPixelContainsCorrectNewDefault() throws {
        // Given
        setDefaultBrowserAsNonDuckDuckGo(path: "/Applications/Safari.app", bundleId: "com.apple.Safari")
        try mockKeyValueStore.set(true, forKey: "user-churn.was-default-browser")

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(mockPixelFiring.firedPixels.first?.event.parameters?["newDefault"], "Safari")
    }

    func testWhenDuckDuckGoIsNotDefaultAndWasDefault_ThenPixelContainsAtb() throws {
        // Given
        setDefaultBrowserAsNonDuckDuckGo(path: "/Applications/Safari.app", bundleId: "com.apple.Safari")
        try mockKeyValueStore.set(true, forKey: "user-churn.was-default-browser")

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(mockPixelFiring.firedPixels.first?.event.parameters?["atb"], "v123-4")
    }

    func testWhenDuckDuckGoIsNotDefaultAndWasDefault_ThenStoredStateUpdatedToFalse() throws {
        // Given
        setDefaultBrowserAsNonDuckDuckGo(path: "/Applications/Safari.app", bundleId: "com.apple.Safari")
        try mockKeyValueStore.set(true, forKey: "user-churn.was-default-browser")

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(try mockKeyValueStore.object(forKey: "user-churn.was-default-browser") as? Bool, false)
    }

    func testWhenDuckDuckGoIsNotDefaultAndWasNotDefault_ThenNoPixelFired() throws {
        // Given
        setDefaultBrowserAsNonDuckDuckGo(path: "/Applications/Safari.app", bundleId: "com.apple.Safari")
        try mockKeyValueStore.set(false, forKey: "user-churn.was-default-browser")

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertTrue(mockPixelFiring.firedPixels.isEmpty, "No pixel should be fired when DuckDuckGo was never the default")
    }

    func testWhenDuckDuckGoIsNotDefaultAndWasNotDefault_ThenStoredStateNotUpdated() throws {
        // Given
        setDefaultBrowserAsNonDuckDuckGo(path: "/Applications/Safari.app", bundleId: "com.apple.Safari")
        try mockKeyValueStore.set(false, forKey: "user-churn.was-default-browser")

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(try mockKeyValueStore.object(forKey: "user-churn.was-default-browser") as? Bool, false)
    }

    // MARK: - Tests: Browser detection

    func testWhenNewDefaultIsChrome_ThenPixelContainsChromeParameter() throws {
        // Given
        setDefaultBrowserAsNonDuckDuckGo(path: "/Applications/Google Chrome.app", bundleId: "com.google.Chrome")
        try mockKeyValueStore.set(true, forKey: "user-churn.was-default-browser")

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(mockPixelFiring.firedPixels.first?.event.parameters?["newDefault"], "Chrome")
    }

    func testWhenNewDefaultIsFirefox_ThenPixelContainsFirefoxParameter() throws {
        // Given
        setDefaultBrowserAsNonDuckDuckGo(path: "/Applications/Firefox.app", bundleId: "org.mozilla.firefox")
        try mockKeyValueStore.set(true, forKey: "user-churn.was-default-browser")

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(mockPixelFiring.firedPixels.first?.event.parameters?["newDefault"], "Firefox")
    }

    func testWhenNewDefaultIsBrave_ThenPixelContainsBraveParameter() throws {
        // Given
        setDefaultBrowserAsNonDuckDuckGo(path: "/Applications/Brave Browser.app", bundleId: "com.brave.Browser")
        try mockKeyValueStore.set(true, forKey: "user-churn.was-default-browser")

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(mockPixelFiring.firedPixels.first?.event.parameters?["newDefault"], "Brave")
    }

    func testWhenNewDefaultIsUnknown_ThenPixelContainsOtherParameter() throws {
        // Given
        setDefaultBrowserAsNonDuckDuckGo(path: "/Applications/SomeOtherBrowser.app", bundleId: "com.example.browser")
        try mockKeyValueStore.set(true, forKey: "user-churn.was-default-browser")

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(mockPixelFiring.firedPixels.first?.event.parameters?["newDefault"], "Other")
    }

    func testWhenNewDefaultURLIsNil_ThenPixelContainsOtherParameter() throws {
        // Given
        mockDefaultBrowserProvider.defaultBrowserURL = nil
        try mockKeyValueStore.set(true, forKey: "user-churn.was-default-browser")

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(mockPixelFiring.firedPixels.first?.event.parameters?["newDefault"], "Other")
    }

    // MARK: - Tests: checkForDefaultBrowserChange with no stored state

    func testWhenNoStoredStateAndDuckDuckGoIsDefault_ThenStateInitializedToTrue() throws {
        // Given
        setDefaultBrowserAsDuckDuckGo()
        // No stored state

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(try mockKeyValueStore.object(forKey: "user-churn.was-default-browser") as? Bool, true, "State should be initialized to true")
        XCTAssertTrue(mockPixelFiring.firedPixels.isEmpty)
    }

    func testWhenNoStoredStateAndDuckDuckGoIsNotDefault_ThenStateInitializedToFalseAndNoPixelFired() throws {
        // Given
        setDefaultBrowserAsNonDuckDuckGo(path: "/Applications/Safari.app", bundleId: "com.apple.Safari")
        // No stored state

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(try mockKeyValueStore.object(forKey: "user-churn.was-default-browser") as? Bool, false, "State should be initialized to false")
        XCTAssertTrue(mockPixelFiring.firedPixels.isEmpty, "No pixel should be fired when state is being initialized")
    }

    // MARK: - Tests: Full churn detection flow

    func testWhenAppLaunchesThenUserChangesDefaultBrowser_ThenChurnDetectedCorrectly() throws {
        // Given - App starts with DuckDuckGo as default
        setDefaultBrowserAsDuckDuckGo()
        sut.checkForDefaultBrowserChange()  // First call initializes state

        // When - User changes default browser away from DuckDuckGo
        setDefaultBrowserAsNonDuckDuckGo(path: "/Applications/Safari.app", bundleId: "com.apple.Safari")
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(mockPixelFiring.firedPixels.count, 1, "Churn pixel should be fired")
        XCTAssertEqual(mockPixelFiring.firedPixels.first?.event.name, "m_mac_unset-as-default")
    }

    // MARK: - Tests: Switching between DuckDuckGo builds

    func testWhenUserSwitchesFromDMGToAppStore_ThenNoPixelFired() throws {
        // Given - App starts with DuckDuckGo DMG as default
        setDefaultBrowserAsDuckDuckGo(bundleId: "com.duckduckgo.macos.browser")
        sut.checkForDefaultBrowserChange()  // Initialize state

        // When - User switches to App Store version
        let appStoreURL = URL(fileURLWithPath: "/Applications/DuckDuckGo.app")
        mockDefaultBrowserProvider.defaultBrowserURL = appStoreURL
        mockBundleIdentifiers[appStoreURL] = "com.duckduckgo.mobile.ios"
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertTrue(mockPixelFiring.firedPixels.isEmpty, "No pixel should be fired when switching between DuckDuckGo builds")
        XCTAssertEqual(try mockKeyValueStore.object(forKey: "user-churn.was-default-browser") as? Bool, true, "State should remain true")
    }

    func testWhenUserSwitchesFromReleaseToDebug_ThenNoPixelFired() throws {
        // Given - App starts with DuckDuckGo release as default
        setDefaultBrowserAsDuckDuckGo(bundleId: "com.duckduckgo.macos.browser")
        sut.checkForDefaultBrowserChange()  // Initialize state

        // When - User switches to debug build
        let debugURL = URL(fileURLWithPath: "/Applications/DuckDuckGo Debug.app")
        mockDefaultBrowserProvider.defaultBrowserURL = debugURL
        mockBundleIdentifiers[debugURL] = "com.duckduckgo.macos.browser.debug"
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertTrue(mockPixelFiring.firedPixels.isEmpty, "No pixel should be fired when switching between DuckDuckGo builds")
    }

    func testWhenUserSwitchesFromReleaseToAlpha_ThenNoPixelFired() throws {
        // Given - App starts with DuckDuckGo release as default
        setDefaultBrowserAsDuckDuckGo(bundleId: "com.duckduckgo.macos.browser")
        sut.checkForDefaultBrowserChange()  // Initialize state

        // When - User switches to alpha build
        let alphaURL = URL(fileURLWithPath: "/Applications/DuckDuckGo Alpha.app")
        mockDefaultBrowserProvider.defaultBrowserURL = alphaURL
        mockBundleIdentifiers[alphaURL] = "com.duckduckgo.macos.browser.alpha"
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertTrue(mockPixelFiring.firedPixels.isEmpty, "No pixel should be fired when switching between DuckDuckGo builds")
    }

    func testWhenUserSwitchesFromAppStoreToSafari_ThenPixelFired() throws {
        // Given - App starts with DuckDuckGo App Store as default
        setDefaultBrowserAsDuckDuckGo(bundleId: "com.duckduckgo.mobile.ios")
        sut.checkForDefaultBrowserChange()  // Initialize state

        // When - User switches to Safari
        setDefaultBrowserAsNonDuckDuckGo(path: "/Applications/Safari.app", bundleId: "com.apple.Safari")
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(mockPixelFiring.firedPixels.count, 1, "Churn pixel should be fired when switching away from DuckDuckGo")
    }

    func testWhenDefaultBrowserURLHasNoBundleIdentifier_ThenTreatedAsNonDuckDuckGo() throws {
        // Given - DuckDuckGo was previously the default
        try mockKeyValueStore.set(true, forKey: "user-churn.was-default-browser")

        // When - Default browser URL has no bundle identifier (unknown app)
        let unknownURL = URL(fileURLWithPath: "/Applications/Unknown.app")
        mockDefaultBrowserProvider.defaultBrowserURL = unknownURL
        // mockBundleIdentifiers does not contain this URL, so bundleIdentifierProvider returns nil
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(mockPixelFiring.firedPixels.count, 1, "Pixel should be fired when new default has no bundle ID")
    }
}
