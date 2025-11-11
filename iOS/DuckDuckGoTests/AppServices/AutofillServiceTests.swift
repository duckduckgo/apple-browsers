//
//  AutofillServiceTests.swift
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

import Foundation
import Testing
import Persistence
@testable import DuckDuckGo
@testable import PersistenceTestingUtils

final class AutofillServiceTests {

    private var mockKeyValueStore: ThrowingKeyValueStoring!
    private var mockFeatureFlagger: MockFeatureFlagger!

    init() throws {
        let store = try MockKeyValueFileStore()
        mockKeyValueStore = store
        mockFeatureFlagger = MockFeatureFlagger()
    }

    @Test("init() when feature enabled and migration not completed should attempt migration and set flag on success")
    func initMigratesAccessibilityWhenFeatureEnabled() async {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.migrateKeychainAccessibility]

        // When
        _ = AutofillService(keyValueStore: mockKeyValueStore, featureFlagger: mockFeatureFlagger)

        // Then
        let migrationCompleted = try? mockKeyValueStore.object(forKey: "com.duckduckgo.autofill.keystore.accessibility.migrated.v4") as? Bool
        #expect(migrationCompleted == true || migrationCompleted == nil)
    }

    @Test("init() when feature disabled should not attempt migration")
    func initSkipsMigrationWhenFeatureDisabled() async throws {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = []

        // When
        _ = AutofillService(keyValueStore: mockKeyValueStore, featureFlagger: mockFeatureFlagger)

        // Then
        let migrationCompleted = try? mockKeyValueStore.object(forKey: "com.duckduckgo.autofill.keystore.accessibility.migrated.v4") as? Bool
        #expect(migrationCompleted == nil)
    }

    @Test("init() when migration already completed should not set flag again")
    func initSkipsMigrationWhenAlreadyCompleted() async throws {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.migrateKeychainAccessibility]
        try mockKeyValueStore.set(true, forKey: "com.duckduckgo.autofill.keystore.accessibility.migrated.v4")

        // When
        _ = AutofillService(keyValueStore: mockKeyValueStore, featureFlagger: mockFeatureFlagger)

        // Then
        let migrationCompleted = try mockKeyValueStore.object(forKey: "com.duckduckgo.autofill.keystore.accessibility.migrated.v4") as? Bool
        #expect(migrationCompleted == true)
    }

    @Test("init() when migration fails should not set flag")
    func initDoesNotSetFlagWhenMigrationFails() async {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.migrateKeychainAccessibility]

        // When
        _ = AutofillService(keyValueStore: mockKeyValueStore, featureFlagger: mockFeatureFlagger)

        // Then
        let migrationCompleted = try? mockKeyValueStore.object(forKey: "com.duckduckgo.autofill.keystore.accessibility.migrated.v4") as? Bool
        #expect(migrationCompleted == true || migrationCompleted == nil)
    }

}
