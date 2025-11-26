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

    override func setUp() {
        super.setUp()

        mockDefaultBrowserProvider = MockDefaultBrowserProvider()
        mockKeyValueStore = MockThrowingKeyValueStore()
        mockPixelFiring = MockPixelFiring()

        sut = UserChurnService(
            defaultBrowserProvider: mockDefaultBrowserProvider,
            keyValueStore: mockKeyValueStore,
            pixelFiring: mockPixelFiring,
            atbProvider: { "v123-4" }
        )
    }

    override func tearDown() {
        sut = nil
        mockDefaultBrowserProvider = nil
        mockKeyValueStore = nil
        mockPixelFiring = nil
        super.tearDown()
    }

    // MARK: - Tests: DuckDuckGo is currently the default browser

    func testWhenDuckDuckGoIsDefaultAndWasDefault_ThenNoPixelFired() throws {
        // Given
        mockDefaultBrowserProvider.isDefault = true
        try mockKeyValueStore.set(true, forKey: "user-churn.was-default-browser")

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertTrue(mockPixelFiring.firedPixels.isEmpty, "No pixel should be fired when DuckDuckGo is still the default")
    }

    func testWhenDuckDuckGoIsDefaultAndWasDefault_ThenStoredStateNotUpdated() throws {
        // Given
        mockDefaultBrowserProvider.isDefault = true
        try mockKeyValueStore.set(true, forKey: "user-churn.was-default-browser")

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(try mockKeyValueStore.object(forKey: "user-churn.was-default-browser") as? Bool, true)
    }

    func testWhenDuckDuckGoIsDefaultAndWasNotDefault_ThenNoPixelFired() throws {
        // Given
        mockDefaultBrowserProvider.isDefault = true
        try mockKeyValueStore.set(false, forKey: "user-churn.was-default-browser")

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertTrue(mockPixelFiring.firedPixels.isEmpty, "No pixel should be fired when DuckDuckGo becomes the default")
    }

    func testWhenDuckDuckGoIsDefaultAndWasNotDefault_ThenStoredStateUpdatedToTrue() throws {
        // Given
        mockDefaultBrowserProvider.isDefault = true
        try mockKeyValueStore.set(false, forKey: "user-churn.was-default-browser")

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(try mockKeyValueStore.object(forKey: "user-churn.was-default-browser") as? Bool, true)
    }

    // MARK: - Tests: DuckDuckGo is not the default browser

    func testWhenDuckDuckGoIsNotDefaultAndWasDefault_ThenPixelFired() throws {
        // Given
        mockDefaultBrowserProvider.isDefault = false
        mockDefaultBrowserProvider.defaultBrowserURL = URL(fileURLWithPath: "/Applications/Safari.app")
        try mockKeyValueStore.set(true, forKey: "user-churn.was-default-browser")

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(mockPixelFiring.firedPixels.count, 1, "Pixel should be fired when user changes default away from DuckDuckGo")
        XCTAssertEqual(mockPixelFiring.firedPixels.first?.event.name, "m_mac_unset-as-default")
    }

    func testWhenDuckDuckGoIsNotDefaultAndWasDefault_ThenPixelContainsCorrectNewDefault() throws {
        // Given
        mockDefaultBrowserProvider.isDefault = false
        mockDefaultBrowserProvider.defaultBrowserURL = URL(fileURLWithPath: "/Applications/Safari.app")
        try mockKeyValueStore.set(true, forKey: "user-churn.was-default-browser")

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(mockPixelFiring.firedPixels.first?.event.parameters?["newDefault"], "Safari")
    }

    func testWhenDuckDuckGoIsNotDefaultAndWasDefault_ThenPixelContainsAtb() throws {
        // Given
        mockDefaultBrowserProvider.isDefault = false
        mockDefaultBrowserProvider.defaultBrowserURL = URL(fileURLWithPath: "/Applications/Safari.app")
        try mockKeyValueStore.set(true, forKey: "user-churn.was-default-browser")

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(mockPixelFiring.firedPixels.first?.event.parameters?["atb"], "v123-4")
    }

    func testWhenDuckDuckGoIsNotDefaultAndWasDefault_ThenStoredStateUpdatedToFalse() throws {
        // Given
        mockDefaultBrowserProvider.isDefault = false
        mockDefaultBrowserProvider.defaultBrowserURL = URL(fileURLWithPath: "/Applications/Safari.app")
        try mockKeyValueStore.set(true, forKey: "user-churn.was-default-browser")

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(try mockKeyValueStore.object(forKey: "user-churn.was-default-browser") as? Bool, false)
    }

    func testWhenDuckDuckGoIsNotDefaultAndWasNotDefault_ThenNoPixelFired() throws {
        // Given
        mockDefaultBrowserProvider.isDefault = false
        try mockKeyValueStore.set(false, forKey: "user-churn.was-default-browser")

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertTrue(mockPixelFiring.firedPixels.isEmpty, "No pixel should be fired when DuckDuckGo was never the default")
    }

    func testWhenDuckDuckGoIsNotDefaultAndWasNotDefault_ThenStoredStateNotUpdated() throws {
        // Given
        mockDefaultBrowserProvider.isDefault = false
        try mockKeyValueStore.set(false, forKey: "user-churn.was-default-browser")

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(try mockKeyValueStore.object(forKey: "user-churn.was-default-browser") as? Bool, false)
    }

    // MARK: - Tests: Browser detection

    func testWhenNewDefaultIsChrome_ThenPixelContainsChromeParameter() throws {
        // Given
        mockDefaultBrowserProvider.isDefault = false
        mockDefaultBrowserProvider.defaultBrowserURL = URL(fileURLWithPath: "/Applications/Google Chrome.app")
        try mockKeyValueStore.set(true, forKey: "user-churn.was-default-browser")

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(mockPixelFiring.firedPixels.first?.event.parameters?["newDefault"], "Chrome")
    }

    func testWhenNewDefaultIsFirefox_ThenPixelContainsFirefoxParameter() throws {
        // Given
        mockDefaultBrowserProvider.isDefault = false
        mockDefaultBrowserProvider.defaultBrowserURL = URL(fileURLWithPath: "/Applications/Firefox.app")
        try mockKeyValueStore.set(true, forKey: "user-churn.was-default-browser")

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(mockPixelFiring.firedPixels.first?.event.parameters?["newDefault"], "Firefox")
    }

    func testWhenNewDefaultIsBrave_ThenPixelContainsBraveParameter() throws {
        // Given
        mockDefaultBrowserProvider.isDefault = false
        mockDefaultBrowserProvider.defaultBrowserURL = URL(fileURLWithPath: "/Applications/Brave Browser.app")
        try mockKeyValueStore.set(true, forKey: "user-churn.was-default-browser")

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(mockPixelFiring.firedPixels.first?.event.parameters?["newDefault"], "Brave")
    }

    func testWhenNewDefaultIsUnknown_ThenPixelContainsOtherParameter() throws {
        // Given
        mockDefaultBrowserProvider.isDefault = false
        mockDefaultBrowserProvider.defaultBrowserURL = URL(fileURLWithPath: "/Applications/SomeOtherBrowser.app")
        try mockKeyValueStore.set(true, forKey: "user-churn.was-default-browser")

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(mockPixelFiring.firedPixels.first?.event.parameters?["newDefault"], "Other")
    }

    func testWhenNewDefaultURLIsNil_ThenPixelContainsOtherParameter() throws {
        // Given
        mockDefaultBrowserProvider.isDefault = false
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
        mockDefaultBrowserProvider.isDefault = true
        // No stored state

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(try mockKeyValueStore.object(forKey: "user-churn.was-default-browser") as? Bool, true, "State should be initialized to true")
        XCTAssertTrue(mockPixelFiring.firedPixels.isEmpty)
    }

    func testWhenNoStoredStateAndDuckDuckGoIsNotDefault_ThenStateInitializedToFalseAndNoPixelFired() throws {
        // Given
        mockDefaultBrowserProvider.isDefault = false
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
        mockDefaultBrowserProvider.isDefault = true
        sut.checkForDefaultBrowserChange()  // First call initializes state

        // When - User changes default browser away from DuckDuckGo
        mockDefaultBrowserProvider.isDefault = false
        mockDefaultBrowserProvider.defaultBrowserURL = URL(fileURLWithPath: "/Applications/Safari.app")
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(mockPixelFiring.firedPixels.count, 1, "Churn pixel should be fired")
        XCTAssertEqual(mockPixelFiring.firedPixels.first?.event.name, "m_mac_unset-as-default")
    }
}
