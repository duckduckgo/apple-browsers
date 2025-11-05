//
//  PromptCooldownMigratorTests.swift
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
import PersistenceTestingUtils
@testable import DuckDuckGo

@Suite("Modal Prompt Coordination - Prompt Cooldown Migrator")
struct PromptCooldownMigratorTests {
    let keyValueStore: MockKeyValueFileStore
    let sut: PromptCooldownMigrator

    init() throws {
        keyValueStore = try MockKeyValueFileStore()
        sut = PromptCooldownMigrator(keyValueStore: keyValueStore)
    }

    // MARK: - Migration Success Tests

    @Test("Check Migration Runs When Data Exists")
    func whenOldDataExistsThenMigrationRuns() throws {
        // GIVEN
        // Set old Default Browser timestamp
        let oldTimestamp: TimeInterval = 1761177600 // Thursday, 23 October 2025 12:00:00 AM (GMT)
        try keyValueStore.set(oldTimestamp, forKey: PromptCooldownMigrator.MigrationKey.defaultBrowserLastModalShownDate)
        // Verify no global cooldown exists yet
        let cooldownBeforeMigration = try keyValueStore.object(forKey: PromptCooldownMigrator.MigrationKey.globalCooldownTimestamp) as? TimeInterval
        #expect(cooldownBeforeMigration == nil)

        // WHEN
        let result = sut.migrateIfNeeded()

        // THEN
        #expect(result)
        let cooldownAfterMigration = try keyValueStore.object(forKey: PromptCooldownMigrator.MigrationKey.globalCooldownTimestamp) as? TimeInterval
        #expect(cooldownAfterMigration == oldTimestamp)
    }

    @Test("Check Migration Deletes Old Value After Migration")
    func whenMigrationRunsThenDeletesOldValue() throws {
        // GIVEN
        let oldTimestamp: TimeInterval = 1761177600 // Thursday, 23 October 2025 12:00:00 AM (GMT)
        try keyValueStore.set(oldTimestamp, forKey: PromptCooldownMigrator.MigrationKey.defaultBrowserLastModalShownDate)

        // WHEN
        let result = sut.migrateIfNeeded()

        // THEN
        #expect(result)
        let oldValue = try keyValueStore.object(forKey: PromptCooldownMigrator.MigrationKey.defaultBrowserLastModalShownDate) as? TimeInterval
        #expect(oldValue == nil)
    }

    @Test("Check Migration Skips When Old Value Does Not Exist")
    func whenOldValueDoesNotExistThenSkipsMigration() throws {
        // GIVEN
        let oldValue = try keyValueStore.object(forKey: PromptCooldownMigrator.MigrationKey.defaultBrowserLastModalShownDate) as? TimeInterval
        #expect(oldValue == nil)

        // WHEN
        let result = sut.migrateIfNeeded()

        // THEN
        #expect(!result)
        let globalTimestamp = try keyValueStore.object(forKey: PromptCooldownMigrator.MigrationKey.globalCooldownTimestamp) as? TimeInterval
        #expect(globalTimestamp == nil) // No migration occurred
    }

    // MARK: - Edge Cases

    @Test("Check Migration Uses Most Recent Timestamp When Both Timestamps Exist")
    func whenBothTimestampsExistThenUsesMostRecent() throws {
        // GIVEN
        let oldTimestamp: TimeInterval = 1761177600 // Thursday, 23 October 2025 12:00:00 AM (GMT)
        let newTimestamp: TimeInterval = 1761436800 // Thursday, 26 October 2025 12:00:00 AM (GMT)

        // Set old Default Browser timestamp (older)
        try keyValueStore.set(oldTimestamp, forKey: PromptCooldownMigrator.MigrationKey.defaultBrowserLastModalShownDate)

        // Set global cooldown timestamp (newer) - shouldn't normally happen. Defensive code.
        try keyValueStore.set(newTimestamp, forKey: PromptCooldownMigrator.MigrationKey.globalCooldownTimestamp)

        // WHEN
        let result = sut.migrateIfNeeded()

        // THEN
        #expect(result)
        let globalCooldown = try keyValueStore.object(forKey: PromptCooldownMigrator.MigrationKey.globalCooldownTimestamp) as? TimeInterval
        #expect(globalCooldown == newTimestamp) // Should keep the newer timestamp
    }

    @Test("Check Migration Uses Old Value When It Is More Recent")
    func whenOldTimestampIsMoreRecentThenUsesIt() throws {
        // GIVEN
        let oldTimestamp: TimeInterval = 1761177600 // Thursday, 23 October 2025 12:00:00 AM (GMT)
        let newTimestamp: TimeInterval = 1761436800 // Thursday, 26 October 2025 12:00:00 AM (GMT)

        // Set old Default Browser timestamp (newer)
        try keyValueStore.set(newTimestamp, forKey: PromptCooldownMigrator.MigrationKey.defaultBrowserLastModalShownDate)

        // Set global cooldown timestamp (newer) - shouldn't normally happen. Defensive code.
        try keyValueStore.set(oldTimestamp, forKey: PromptCooldownMigrator.MigrationKey.globalCooldownTimestamp)

        // WHEN
        let result = sut.migrateIfNeeded()

        // THEN
        #expect(result)
        let globalCooldown = try keyValueStore.object(forKey: PromptCooldownMigrator.MigrationKey.globalCooldownTimestamp) as? TimeInterval
        #expect(globalCooldown == newTimestamp) // Should use the newer timestamp from old storage
    }


    @Test("Check Running Migration Multiple Times Is Safe")
    func whenMigrationRunMultipleTimesThenIsSafe() throws {
        // GIVEN
        let timestamp: TimeInterval = 1761177600 // Thursday, 23 October 2025 12:00:00 AM (GMT)
        try keyValueStore.set(timestamp, forKey: PromptCooldownMigrator.MigrationKey.defaultBrowserLastModalShownDate)

        // WHEN - Run migration 3 times
        let result1 = sut.migrateIfNeeded()
        let result2 = sut.migrateIfNeeded()
        let result3 = sut.migrateIfNeeded()

        // THEN
        #expect(result1 == true)  // First run performs migration
        #expect(result2 == false) // Second run skips
        #expect(result3 == false) // Third run skips

        let defaultBrowserShownDate = try keyValueStore.object(forKey: PromptCooldownMigrator.MigrationKey.defaultBrowserLastModalShownDate) as? TimeInterval
        let globalCooldown = try keyValueStore.object(forKey: PromptCooldownMigrator.MigrationKey.globalCooldownTimestamp) as? TimeInterval
        #expect(defaultBrowserShownDate == nil)
        #expect(globalCooldown == timestamp) // Timestamp unchanged after multiple runs
    }

    @Test(
        "Check Migration Works With Different Timestamp Values",
        arguments: [
            0.0,                    // Unix epoch
            1000000.0,              // Jan 1970
            1750739150.0,           // June 2025
            Date().timeIntervalSince1970  // Current time
        ]
    )
    func whenMigratingDifferentTimestampsThenAllSucceed(timestamp: TimeInterval) throws {
        // GIVEN
        try keyValueStore.set(timestamp, forKey: PromptCooldownMigrator.MigrationKey.defaultBrowserLastModalShownDate)

        // WHEN
        let result = sut.migrateIfNeeded()

        // THEN
        #expect(result == true)
        let globalCooldown = try keyValueStore.object(forKey: PromptCooldownMigrator.MigrationKey.globalCooldownTimestamp) as? TimeInterval
        #expect(globalCooldown == timestamp)
    }
}
