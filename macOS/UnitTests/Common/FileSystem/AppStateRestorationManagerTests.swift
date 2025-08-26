//
//  AppStateRestorationManagerTests.swift
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
import Combine
import PersistenceTestingUtils
@testable import DuckDuckGo_Privacy_Browser

final class AppStateRestorationManagerTests: XCTestCase {

    private var mockKeyValueStore: MockKeyValueFileStore!
    private var appStateManager: AppStateRestorationManager!
    private let terminationFlagKey = "appDidTerminateAsExpected"

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        let mockFileStore = FileStoreMock()
        let mockService = StatePersistenceService(fileStore: FileStoreMock(), fileName: "test_persistent_state")
        let appearancePreferences = AppearancePreferences(persistor: MockAppearancePreferencesPersistor(), privacyConfigurationManager: MockPrivacyConfigurationManager(), featureFlagger: MockFeatureFlagger())
        let mockStartupPreferences = StartupPreferences(appearancePreferences: appearancePreferences)
        mockKeyValueStore = try MockKeyValueFileStore()

        appStateManager = AppStateRestorationManager(
            fileStore: mockFileStore,
            service: mockService,
            startupPreferences: mockStartupPreferences,
            keyValueStore: mockKeyValueStore
        )
    }

    override func tearDown() {
        appStateManager = nil
        mockKeyValueStore = nil
        super.tearDown()
    }

    @MainActor
    func testAppDidFinishLaunching_WhenAppTerminatedAsExpected_SetsExpectedValueForTerminationFlag() throws {
        try mockKeyValueStore.set(true, forKey: terminationFlagKey)

        appStateManager.applicationDidFinishLaunching()

        XCTAssertEqual(try mockKeyValueStore.object(forKey: terminationFlagKey) as? Bool, false)
    }

    @MainActor
    func testAppDidFinishLaunching_WhenAppDidNotTerminateAsExpected_SetsExpectedValueForTerminationFlag() throws {
        try mockKeyValueStore.set(false, forKey: terminationFlagKey)

        appStateManager.applicationDidFinishLaunching()

        XCTAssertEqual(try mockKeyValueStore.object(forKey: terminationFlagKey) as? Bool, false)
    }

    @MainActor
    func testAppDidFinishLaunching_WhenKeyValueStoreIsEmpty_SetsExpectedValueForTerminationFlag() throws {
        try mockKeyValueStore.removeObject(forKey: terminationFlagKey)

        appStateManager.applicationDidFinishLaunching()

        XCTAssertEqual(try mockKeyValueStore.object(forKey: terminationFlagKey) as? Bool, false)
    }

    @MainActor
    func testAppWillTerminate_SetsTerminationFlagToTrue() throws {
        try mockKeyValueStore.set(false, forKey: terminationFlagKey)

        appStateManager.applicationWillTerminate()

        XCTAssertEqual(try mockKeyValueStore.object(forKey: terminationFlagKey) as? Bool, true)
    }

    // MARK: - Error Handling Tests

    @MainActor
    func testKeyValueStoreReadError_DefaultsToTrue() throws {
        // Given: Key value store throws an error on read
        mockKeyValueStore.throwOnRead = MockError.error

        // When: App finishes launching (which reads the flag)
        // Then: No crash occurs
        XCTAssertNoThrow {
            self.appStateManager.applicationDidFinishLaunching()
        }
    }

    @MainActor
    func testKeyValueStoreWriteError_DoesNotCrash() throws {
        // Given: Key value store throws an error on write
        mockKeyValueStore.throwOnSet = MockError.error

        // When: App will terminate (which writes the flag)
        // Then: No crash occurs
        XCTAssertNoThrow {
            self.appStateManager.applicationWillTerminate()
        }
    }
}

// MARK: - Mock Helpers

private enum MockError: Error {
    case error
}
