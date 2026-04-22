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

import Combine
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

    // MARK: - selectedModelIdPublisher

    func testSelectedModelIdPublisher_emitsOnEveryDistinctWrite() {
        var received: [String?] = []
        let cancellable = persistor.selectedModelIdPublisher.sink { received.append($0) }

        persistor.selectedModelId = "gpt-4o-mini"
        persistor.selectedModelId = "claude-sonnet-4-5"
        persistor.selectedModelId = nil

        cancellable.cancel()
        XCTAssertEqual(received, ["gpt-4o-mini", "claude-sonnet-4-5", nil])
    }

    func testSelectedModelIdPublisher_dedupsIdenticalWrites() {
        var received: [String?] = []
        let cancellable = persistor.selectedModelIdPublisher.sink { received.append($0) }

        persistor.selectedModelId = "gpt-4o-mini"
        persistor.selectedModelId = "gpt-4o-mini"   // no-op, publisher must not emit
        persistor.selectedModelId = "claude-sonnet-4-5"

        cancellable.cancel()
        XCTAssertEqual(received, ["gpt-4o-mini", "claude-sonnet-4-5"])
    }

    func testSelectedModelIdPublisher_isInstanceScoped() {
        // Two persistors on the same store: a write on one MUST NOT emit on the other's publisher.
        // (Callers that want cross-component propagation share a single persistor instance.)
        let otherPersistor = AIChatPreferencesPersistor(keyValueStore: userDefaults)
        var received: [String?] = []
        let cancellable = otherPersistor.selectedModelIdPublisher.sink { received.append($0) }

        persistor.selectedModelId = "gpt-4o-mini"

        cancellable.cancel()
        XCTAssertEqual(received, [])
    }
}
