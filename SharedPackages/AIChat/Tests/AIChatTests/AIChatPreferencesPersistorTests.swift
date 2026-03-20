//
//  AIChatPreferencesPersistorTests.swift
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
import AIChat

final class AIChatPreferencesPersistorTests: XCTestCase {

    private var userDefaults: UserDefaults!
    private var persistor: AIChatPreferencesPersistor!

    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: "AIChatPreferencesPersistorTests.\(UUID().uuidString)")!
        persistor = AIChatPreferencesPersistor(keyValueStore: userDefaults)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: userDefaults.volatileDomainNames.first ?? "")
        userDefaults = nil
        persistor = nil
        super.tearDown()
    }

    // MARK: - Selected Model ID

    func testWhenNoModelSelected_ThenSelectedModelIdIsNil() {
        XCTAssertNil(persistor.selectedModelId)
    }

    func testWhenModelIdIsSet_ThenItCanBeReadBack() {
        // Given & When
        persistor.selectedModelId = "gpt-4o-mini"

        // Then
        XCTAssertEqual(persistor.selectedModelId, "gpt-4o-mini")
    }

    func testWhenModelIdIsOverwritten_ThenNewValueIsReturned() {
        // Given
        persistor.selectedModelId = "gpt-4o-mini"

        // When
        persistor.selectedModelId = "claude-sonnet-4-5"

        // Then
        XCTAssertEqual(persistor.selectedModelId, "claude-sonnet-4-5")
    }

    func testWhenModelIdIsCleared_ThenItReturnsNil() {
        // Given
        persistor.selectedModelId = "gpt-4o-mini"

        // When
        persistor.selectedModelId = nil

        // Then
        XCTAssertNil(persistor.selectedModelId)
    }

    func testWhenModelIdIsPersisted_ThenItSurvivesNewPersistorInstance() {
        // Given
        persistor.selectedModelId = "gpt-4o-mini"

        // When — create new persistor backed by the same store
        let secondPersistor = AIChatPreferencesPersistor(keyValueStore: userDefaults)

        // Then
        XCTAssertEqual(secondPersistor.selectedModelId, "gpt-4o-mini")
    }
}
