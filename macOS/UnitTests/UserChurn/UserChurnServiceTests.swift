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

@_spi(Testing) import Persistence
@_spi(Testing) import PixelKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class UserChurnServiceTests: XCTestCase {

    private var sut: UserChurnService!
    private var mockDefaultBrowserProvider: MockDefaultBrowserProvider!
    private var mockKeyValueStore: MockThrowingKeyValueStore!
    private var mockPixelFiring: PixelKitMock!
    private var mockBundleIdentifiers: [URL: String]!

    override func setUp() {
        super.setUp()

        mockDefaultBrowserProvider = MockDefaultBrowserProvider()
        mockKeyValueStore = MockThrowingKeyValueStore()
        mockPixelFiring = PixelKitMock()
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
        XCTAssertTrue(mockPixelFiring.actualFireCalls.isEmpty, "No pixel should be fired when DuckDuckGo is still the default")
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
        XCTAssertTrue(mockPixelFiring.actualFireCalls.isEmpty, "No pixel should be fired when DuckDuckGo becomes the default")
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
        XCTAssertEqual(mockPixelFiring.actualFireCalls.count, 1, "Pixel should be fired when user changes default away from DuckDuckGo")
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.pixel.name, "m_mac_unset-as-default")
    }

    func testWhenDuckDuckGoIsNotDefaultAndWasDefault_ThenPixelContainsCorrectNewDefault() throws {
        // Given
        setDefaultBrowserAsNonDuckDuckGo(path: "/Applications/Safari.app", bundleId: "com.apple.Safari")
        try mockKeyValueStore.set(true, forKey: "user-churn.was-default-browser")

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.pixel.parameters?["newDefault"], "Safari")
    }

    func testWhenDuckDuckGoIsNotDefaultAndWasDefault_ThenPixelContainsAtb() throws {
        // Given
        setDefaultBrowserAsNonDuckDuckGo(path: "/Applications/Safari.app", bundleId: "com.apple.Safari")
        try mockKeyValueStore.set(true, forKey: "user-churn.was-default-browser")

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.pixel.parameters?["atb"], "v123-4")
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
        XCTAssertTrue(mockPixelFiring.actualFireCalls.isEmpty, "No pixel should be fired when DuckDuckGo was never the default")
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
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.pixel.parameters?["newDefault"], "Chrome")
    }

    func testWhenNewDefaultIsFirefox_ThenPixelContainsFirefoxParameter() throws {
        // Given
        setDefaultBrowserAsNonDuckDuckGo(path: "/Applications/Firefox.app", bundleId: "org.mozilla.firefox")
        try mockKeyValueStore.set(true, forKey: "user-churn.was-default-browser")

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.pixel.parameters?["newDefault"], "Firefox")
    }

    func testWhenNewDefaultIsBrave_ThenPixelContainsBraveParameter() throws {
        // Given
        setDefaultBrowserAsNonDuckDuckGo(path: "/Applications/Brave Browser.app", bundleId: "com.brave.Browser")
        try mockKeyValueStore.set(true, forKey: "user-churn.was-default-browser")

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.pixel.parameters?["newDefault"], "Brave")
    }

    func testWhenNewDefaultIsUnknown_ThenPixelContainsOtherParameter() throws {
        // Given
        setDefaultBrowserAsNonDuckDuckGo(path: "/Applications/SomeOtherBrowser.app", bundleId: "com.example.browser")
        try mockKeyValueStore.set(true, forKey: "user-churn.was-default-browser")

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.pixel.parameters?["newDefault"], "Other")
    }

    func testWhenNewDefaultURLIsNil_ThenPixelContainsOtherParameter() throws {
        // Given
        mockDefaultBrowserProvider.defaultBrowserURL = nil
        try mockKeyValueStore.set(true, forKey: "user-churn.was-default-browser")

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.pixel.parameters?["newDefault"], "Other")
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
        XCTAssertTrue(mockPixelFiring.actualFireCalls.isEmpty)
    }

    func testWhenNoStoredStateAndDuckDuckGoIsNotDefault_ThenStateInitializedToFalseAndNoPixelFired() throws {
        // Given
        setDefaultBrowserAsNonDuckDuckGo(path: "/Applications/Safari.app", bundleId: "com.apple.Safari")
        // No stored state

        // When
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(try mockKeyValueStore.object(forKey: "user-churn.was-default-browser") as? Bool, false, "State should be initialized to false")
        XCTAssertTrue(mockPixelFiring.actualFireCalls.isEmpty, "No pixel should be fired when state is being initialized")
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
        XCTAssertEqual(mockPixelFiring.actualFireCalls.count, 1, "Churn pixel should be fired")
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.pixel.name, "m_mac_unset-as-default")
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
        XCTAssertTrue(mockPixelFiring.actualFireCalls.isEmpty, "No pixel should be fired when switching between DuckDuckGo builds")
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
        XCTAssertTrue(mockPixelFiring.actualFireCalls.isEmpty, "No pixel should be fired when switching between DuckDuckGo builds")
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
        XCTAssertTrue(mockPixelFiring.actualFireCalls.isEmpty, "No pixel should be fired when switching between DuckDuckGo builds")
    }

    func testWhenUserSwitchesFromAppStoreToSafari_ThenPixelFired() throws {
        // Given - App starts with DuckDuckGo App Store as default
        setDefaultBrowserAsDuckDuckGo(bundleId: "com.duckduckgo.mobile.ios")
        sut.checkForDefaultBrowserChange()  // Initialize state

        // When - User switches to Safari
        setDefaultBrowserAsNonDuckDuckGo(path: "/Applications/Safari.app", bundleId: "com.apple.Safari")
        sut.checkForDefaultBrowserChange()

        // Then
        XCTAssertEqual(mockPixelFiring.actualFireCalls.count, 1, "Churn pixel should be fired when switching away from DuckDuckGo")
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
        XCTAssertEqual(mockPixelFiring.actualFireCalls.count, 1, "Pixel should be fired when new default has no bundle ID")
    }

    // MARK: - Tests: Churned-from-default flag

    private let wasDefaultKey = "user-churn.was-default-browser"
    private let churnedKey = "user-churn.churned-from-default"

    private var unsetPixelCalls: [ExpectedFireCall] {
        mockPixelFiring.actualFireCalls.filter { $0.pixel.name == "m_mac_unset-as-default" }
    }

    func testWhenCheckDetectsChurn_ThenChurnedFlagIsSet() throws {
        setDefaultBrowserAsNonDuckDuckGo(path: "/Applications/Safari.app", bundleId: "com.apple.Safari")
        try mockKeyValueStore.set(true, forKey: wasDefaultKey)

        sut.checkForDefaultBrowserChange()

        XCTAssertTrue(sut.hasChurnedFromDefault)
        XCTAssertEqual(try mockKeyValueStore.object(forKey: churnedKey) as? Bool, true)
        XCTAssertEqual(unsetPixelCalls.count, 1)
    }

    func testWhenCheckSeesDuckDuckGoDefault_ThenChurnedFlagIsCleared() throws {
        setDefaultBrowserAsDuckDuckGo()
        try mockKeyValueStore.set(false, forKey: wasDefaultKey)
        try mockKeyValueStore.set(true, forKey: churnedKey)

        sut.checkForDefaultBrowserChange()

        XCTAssertFalse(sut.hasChurnedFromDefault)
        XCTAssertEqual(try mockKeyValueStore.object(forKey: churnedKey) as? Bool, false)
    }

    func testWhenNotDefaultAndWasNotDefault_ThenChurnedFlagStaysTrue() throws {
        setDefaultBrowserAsNonDuckDuckGo(path: "/Applications/Safari.app", bundleId: "com.apple.Safari")
        try mockKeyValueStore.set(false, forKey: wasDefaultKey)
        try mockKeyValueStore.set(true, forKey: churnedKey)

        sut.checkForDefaultBrowserChange()

        XCTAssertTrue(sut.hasChurnedFromDefault)
        XCTAssertTrue(mockPixelFiring.actualFireCalls.isEmpty)
    }

    func testWhenFirstRun_ThenChurnedFlagIsNotSet() {
        setDefaultBrowserAsNonDuckDuckGo(path: "/Applications/Safari.app", bundleId: "com.apple.Safari")

        sut.checkForDefaultBrowserChange()

        XCTAssertFalse(sut.hasChurnedFromDefault)
        XCTAssertTrue(mockPixelFiring.actualFireCalls.isEmpty)
    }

    func testWhenChecksRunConcurrently_ThenOnePixelFires() throws {
        setDefaultBrowserAsNonDuckDuckGo(path: "/Applications/Safari.app", bundleId: "com.apple.Safari")
        try mockKeyValueStore.set(true, forKey: wasDefaultKey)

        DispatchQueue.concurrentPerform(iterations: 50) { _ in
            sut.checkForDefaultBrowserChange()
        }

        XCTAssertEqual(unsetPixelCalls.count, 1)
    }

    func testWhenDuckDuckGoIsDefaultAndChurned_ThenChurnedFlagIsClearedAndWasDefaultNotRewritten() throws {
        let store = RecordingKeyValueStore()
        let service = makeService(store: store)
        setDefaultBrowserAsDuckDuckGo()
        try store.set(true, forKey: wasDefaultKey)
        try store.set(true, forKey: churnedKey)
        store.writtenKeys = []

        service.checkForDefaultBrowserChange()

        XCTAssertFalse(service.hasChurnedFromDefault)
        XCTAssertEqual(store.writtenKeys, [churnedKey])
        XCTAssertEqual(try store.object(forKey: wasDefaultKey) as? Bool, true)
    }

    func testWhenReadFails_ThenReadFailedPixelFires() {
        let store = RecordingKeyValueStore()
        store.failingGetKeys = [wasDefaultKey]
        let service = makeService(store: store)
        setDefaultBrowserAsNonDuckDuckGo(path: "/Applications/Safari.app", bundleId: "com.apple.Safari")

        service.checkForDefaultBrowserChange()

        assertSingleFailurePixel(named: "user-churn_was-default-browser_read-failed_macos")
    }

    func testWhenWriteFails_ThenWriteFailedPixelFires() throws {
        let store = RecordingKeyValueStore()
        let service = makeService(store: store)
        setDefaultBrowserAsNonDuckDuckGo(path: "/Applications/Safari.app", bundleId: "com.apple.Safari")
        try store.set(true, forKey: wasDefaultKey)
        store.failingSetKeys = [churnedKey]

        service.checkForDefaultBrowserChange()

        assertSingleFailurePixel(named: "user-churn_churned-from-default_write-failed_macos")
    }

    private func assertSingleFailurePixel(named name: String, file: StaticString = #filePath, line: UInt = #line) {
        let calls = mockPixelFiring.actualFireCalls.filter { $0.pixel.name == name }
        XCTAssertEqual(calls.count, 1, file: file, line: line)
        XCTAssertEqual(calls.first?.pixel.namePrefix, PixelKitNamePrefix.none, file: file, line: line)
        XCTAssertNotNil(calls.first?.pixel.error, file: file, line: line)
        XCTAssertEqual(calls.first?.frequency, .dailyAndCount, file: file, line: line)
    }

    private func makeService(store: ThrowingKeyValueStoring) -> UserChurnService {
        UserChurnService(
            defaultBrowserProvider: mockDefaultBrowserProvider,
            keyValueStore: store,
            pixelFiring: mockPixelFiring,
            atbProvider: { "v123-4" },
            bundleIdentifierProvider: { [weak self] url in
                self?.mockBundleIdentifiers[url]
            }
        )
    }
}

private final class RecordingKeyValueStore: ThrowingKeyValueStoring {
    private let store = MockThrowingKeyValueStore()
    var failingGetKeys: Set<String> = []
    var failingSetKeys: Set<String> = []
    var writtenKeys: [String] = []

    func object(forKey defaultName: String) throws -> Any? {
        if failingGetKeys.contains(defaultName) { throw MockThrowingKeyValueStore.MockError.getError }
        return try store.object(forKey: defaultName)
    }

    func set(_ value: Any?, forKey defaultName: String) throws {
        if failingSetKeys.contains(defaultName) { throw MockThrowingKeyValueStore.MockError.setError }
        try store.set(value, forKey: defaultName)
        writtenKeys.append(defaultName)
    }

    func removeObject(forKey defaultName: String) throws {
        try store.removeObject(forKey: defaultName)
    }
}
