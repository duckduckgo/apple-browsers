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
    private var mockStatisticsStore: MockStatisticsStore!
    private var mockKeyValueStore: MockThrowingKeyValueStore!
    private var mockPixelFiring: MockPixelFiring!

    override func setUp() {
        super.setUp()

        mockDefaultBrowserProvider = MockDefaultBrowserProvider()
        mockStatisticsStore = MockStatisticsStore()
        mockKeyValueStore = MockThrowingKeyValueStore()
        mockPixelFiring = MockPixelFiring()

        sut = UserChurnService(
            defaultBrowserProvider: mockDefaultBrowserProvider,
            statisticsStore: mockStatisticsStore,
            keyValueStore: mockKeyValueStore,
            pixelFiring: mockPixelFiring
        )
    }

    override func tearDown() {
        sut = nil
        mockDefaultBrowserProvider = nil
        mockStatisticsStore = nil
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
        mockStatisticsStore.atb = "v123-4"

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
        mockStatisticsStore.atb = "v123-4"

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

    // MARK: - Tests: ATB handling

    func testWhenAtbIsNil_ThenPixelDoesNotContainAtb() throws {
        // Given
        mockDefaultBrowserProvider.isDefault = false
        mockDefaultBrowserProvider.defaultBrowserURL = URL(fileURLWithPath: "/Applications/Safari.app")
        try mockKeyValueStore.set(true, forKey: "user-churn.was-default-browser")
        mockStatisticsStore.atb = nil

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertNil(mockPixelFiring.firedPixels.first?.event.parameters?["atb"])
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

    // MARK: - Tests: First run (no stored state)

    func testWhenNoStoredStateAndDuckDuckGoIsDefault_ThenStoredStateSetToTrue() throws {
        // Given
        mockDefaultBrowserProvider.isDefault = true
        // No stored state

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(try mockKeyValueStore.object(forKey: "user-churn.was-default-browser") as? Bool, true)
        XCTAssertTrue(mockPixelFiring.firedPixels.isEmpty)
    }

    func testWhenNoStoredStateAndDuckDuckGoIsNotDefault_ThenNoPixelFired() {
        // Given
        mockDefaultBrowserProvider.isDefault = false
        // No stored state (defaults to false)

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertTrue(mockPixelFiring.firedPixels.isEmpty, "No pixel should be fired on first run when DuckDuckGo is not default")
    }
}
