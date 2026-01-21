//
//  UpdatesDebugSettingsTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
@testable import DuckDuckGo_Privacy_Browser
import Common
import Persistence
import PersistenceTestingUtils

final class UpdatesDebugSettingsTests: XCTestCase {

    var mockKeyValueStore: MockKeyValueStore!
    var persistor: UpdatesDebugSettingsUserDefaultsPersistor!
    var debugSettings: UpdatesDebugSettings!

    override func setUp() {
        super.setUp()
        mockKeyValueStore = MockKeyValueStore()
        persistor = UpdatesDebugSettingsUserDefaultsPersistor(keyValueStore: mockKeyValueStore)
        debugSettings = UpdatesDebugSettings(persistor: persistor)
    }

    override func tearDown() {
        debugSettings.reset() // Clean up after tests
        debugSettings = nil
        persistor = nil
        mockKeyValueStore = nil
        super.tearDown()
    }

    func testDefaultValue() {
        // Given - fresh debug settings
        let settings = UpdatesDebugSettings(persistor: persistor)

        // Then - should be in default state
        XCTAssertFalse(settings.forceUpdateAvailable)
    }

    func testForceUpdateAvailable() {
        // Given - default state
        XCTAssertFalse(debugSettings.forceUpdateAvailable)

        // When - enabling force update
        debugSettings.forceUpdateAvailable = true

        // Then - should be enabled
        XCTAssertTrue(debugSettings.forceUpdateAvailable)

        // When - disabling force update
        debugSettings.forceUpdateAvailable = false

        // Then - should be disabled
        XCTAssertFalse(debugSettings.forceUpdateAvailable)
    }

    func testReset() {
        // Given - settings with force update enabled
        debugSettings.forceUpdateAvailable = true

        // Verify it's set
        XCTAssertTrue(debugSettings.forceUpdateAvailable)

        // When - resetting
        debugSettings.reset()

        // Then - should be back to default
        XCTAssertFalse(debugSettings.forceUpdateAvailable)
    }

    func testPersistence() {
        // Given - settings with force update enabled
        debugSettings.forceUpdateAvailable = true

        // When - creating new instance (simulates app restart)
        let newSettings = UpdatesDebugSettings(persistor: persistor)

        // Then - value should persist
        XCTAssertTrue(newSettings.forceUpdateAvailable)

        // Cleanup
        newSettings.reset()
    }
}
