//
//  SparkleUpdaterAvailabilityCheckerTests.swift
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

#if SPARKLE

import XCTest
import Sparkle
@testable import DuckDuckGo_Privacy_Browser

final class SparkleUpdaterAvailabilityCheckerTests: XCTestCase {

    private var mockUpdater: MockSPUUpdater!
    private var checker: SparkleUpdaterAvailabilityChecker!

    override func setUp() {
        super.setUp()
        autoreleasepool {
            mockUpdater = MockSPUUpdater()
            checker = SparkleUpdaterAvailabilityChecker(updater: mockUpdater)
        }
    }

    override func tearDown() {
        checker = nil
        mockUpdater = nil
        super.tearDown()
    }

    // MARK: - Protocol Conformance Tests

    func testConformsToUpdaterAvailabilityChecking() {
        XCTAssertTrue(checker is UpdaterAvailabilityChecking)
    }

    // MARK: - Updater Availability Tests

    func testCanCheckForUpdates_WithUpdaterAvailable_ReturnsUpdaterValue() {
        // Given
        mockUpdater.mockCanCheckForUpdates = true

        // When
        let result = checker.canCheckForUpdates

        // Then
        XCTAssertTrue(result)
    }

    func testCanCheckForUpdates_WithUpdaterUnavailable_ReturnsUpdaterValue() {
        // Given
        mockUpdater.mockCanCheckForUpdates = false

        // When
        let result = checker.canCheckForUpdates

        // Then
        XCTAssertFalse(result)
    }

    func testCanCheckForUpdates_WithNilUpdater_ReturnsTrue() {
        // Given
        checker = SparkleUpdaterAvailabilityChecker(updater: nil)

        // When
        let result = checker.canCheckForUpdates

        // Then
        XCTAssertTrue(result)
    }

    func testCanCheckForUpdates_WithDefaultInitializer_ReturnsTrue() {
        // Given
        checker = SparkleUpdaterAvailabilityChecker()

        // When
        let result = checker.canCheckForUpdates

        // Then
        XCTAssertTrue(result) // Since updater is nil by default
    }

    // MARK: - State Change Tests

    func testCanCheckForUpdates_ReflectsUpdaterStateChanges() {
        // Given
        mockUpdater.mockCanCheckForUpdates = true
        XCTAssertTrue(checker.canCheckForUpdates)

        // When
        mockUpdater.mockCanCheckForUpdates = false

        // Then
        XCTAssertFalse(checker.canCheckForUpdates)
    }
}

#endif
