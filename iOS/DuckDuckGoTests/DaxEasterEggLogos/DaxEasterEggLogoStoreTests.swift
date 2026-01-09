//
//  DaxEasterEggLogoStoreTests.swift
//  DuckDuckGo
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
@testable import DuckDuckGo
@testable import Core

final class DaxEasterEggLogoStoreTests: XCTestCase {

    private let testSuiteName = "test.dax.easter.egg.logo.store"
    private var store: DaxEasterEggLogoStore!
    private var originalUserDefaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        originalUserDefaults = UserDefaults.app
        let testDefaults = UserDefaults(suiteName: testSuiteName)!
        testDefaults.removePersistentDomain(forName: testSuiteName)
        UserDefaults.app = testDefaults
        store = DaxEasterEggLogoStore()
    }

    override func tearDownWithError() throws {
        store.clearLogo()
        UserDefaults.app = originalUserDefaults
        UserDefaults.standard.removePersistentDomain(forName: testSuiteName)
        store = nil
        try super.tearDownWithError()
    }

    func testInitialState_hasNoLogo() {
        // Then
        XCTAssertNil(store.logoURL)
        XCTAssertFalse(store.hasLogo)
    }

    func testSetLogo_storesURL() {
        // When
        store.setLogo(url: "https://duckduckgo.com/assets/logo.png")

        // Then
        XCTAssertEqual(store.logoURL, "https://duckduckgo.com/assets/logo.png")
        XCTAssertTrue(store.hasLogo)
    }

    func testSetLogo_overwritesPreviousLogo() {
        // Given
        store.setLogo(url: "https://duckduckgo.com/logo1.png")

        // When
        store.setLogo(url: "https://duckduckgo.com/logo2.png")

        // Then
        XCTAssertEqual(store.logoURL, "https://duckduckgo.com/logo2.png")
    }

    func testClearLogo_removesURL() {
        // Given
        store.setLogo(url: "https://duckduckgo.com/logo.png")

        // When
        store.clearLogo()

        // Then
        XCTAssertNil(store.logoURL)
        XCTAssertFalse(store.hasLogo)
    }

    func testClearLogo_whenNoLogo_doesNotCrash() {
        // When/Then
        store.clearLogo()
        XCTAssertFalse(store.hasLogo)
    }

    func testLogo_persistsAcrossInstances() {
        // Given
        store.setLogo(url: "https://duckduckgo.com/logo.png")

        // When
        let newStore = DaxEasterEggLogoStore()

        // Then
        XCTAssertEqual(newStore.logoURL, "https://duckduckgo.com/logo.png")
        XCTAssertTrue(newStore.hasLogo)
    }

    func testSetLogo_postsNotification() {
        // Given
        let expectation = expectation(forNotification: .logoDidChangeNotification, object: nil)

        // When
        store.setLogo(url: "https://duckduckgo.com/logo.png")

        // Then
        wait(for: [expectation], timeout: 1.0)
    }

    func testClearLogo_postsNotification() {
        // Given
        store.setLogo(url: "https://duckduckgo.com/logo.png")
        let expectation = expectation(forNotification: .logoDidChangeNotification, object: nil)

        // When
        store.clearLogo()

        // Then
        wait(for: [expectation], timeout: 1.0)
    }
}
