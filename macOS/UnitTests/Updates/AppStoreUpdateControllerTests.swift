//
//  AppStoreUpdateControllerTests.swift
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
import NetworkingTestingUtils
@testable import DuckDuckGo_Privacy_Browser

final class AppStoreUpdateControllerTests: XCTestCase {

    private var controller: AppStoreUpdateController!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        autoreleasepool {
            // Use the default dependencies for simpler testing
            controller = AppStoreUpdateController()
            cancellables = Set<AnyCancellable>()
        }
    }

    override func tearDown() {
        cancellables?.removeAll()
        controller = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitialization_SetsCorrectDefaults() {
        XCTAssertNil(controller.latestUpdate)
        XCTAssertFalse(controller.hasPendingUpdate)
        XCTAssertFalse(controller.needsNotificationDot)
        XCTAssertFalse(controller.areAutomaticUpdatesEnabled) // App Store cannot enable automatic updates
        // UpdateProgress default value varies, so we just check it's not nil
        XCTAssertNotNil(controller.updateProgress)
    }

    // MARK: - Version Comparison Tests

    func testCompareSemanticVersions_EqualVersions() {
        // Given/When
        let result = controller.compareSemanticVersions("1.0.0", "1.0.0")

        // Then
        XCTAssertEqual(result, .orderedSame)
    }

    func testCompareSemanticVersions_FirstVersionOlder() {
        // Given/When
        let result = controller.compareSemanticVersions("1.0.0", "1.1.0")

        // Then
        XCTAssertEqual(result, .orderedAscending)
    }

    func testCompareSemanticVersions_FirstVersionNewer() {
        // Given/When
        let result = controller.compareSemanticVersions("1.1.0", "1.0.0")

        // Then
        XCTAssertEqual(result, .orderedDescending)
    }

    func testCompareSemanticVersions_DifferentComponentCounts() {
        // Test version with fewer components is treated as having zeros
        XCTAssertEqual(controller.compareSemanticVersions("1.0", "1.0.0"), .orderedSame)
        XCTAssertEqual(controller.compareSemanticVersions("1.0", "1.0.1"), .orderedAscending)
        XCTAssertEqual(controller.compareSemanticVersions("1.0.1", "1.0"), .orderedDescending)
    }

    func testCompareSemanticVersions_ComplexVersions() {
        XCTAssertEqual(controller.compareSemanticVersions("1.2.3", "1.2.4"), .orderedAscending)
        XCTAssertEqual(controller.compareSemanticVersions("1.2.3", "1.3.0"), .orderedAscending)
        XCTAssertEqual(controller.compareSemanticVersions("2.0.0", "1.9.9"), .orderedDescending)
    }

    // MARK: - Update Detection Tests

    func testIsUpdateAvailable_NoCurrentVersion() async {
        // Given - When current version is nil, should always return true
        let result = await controller.isUpdateAvailable(
            currentVersion: nil,
            currentBuild: "100",
            remoteVersion: "1.0.1",
            remoteBuild: "101"
        )

        // Then
        XCTAssertTrue(result)
    }

    func testIsUpdateAvailable_NewerVersionAvailable() async {
        // Given
        let result = await controller.isUpdateAvailable(
            currentVersion: "1.0.0",
            currentBuild: "100",
            remoteVersion: "1.0.1",
            remoteBuild: "101"
        )

        // Then
        XCTAssertTrue(result)
    }

    func testIsUpdateAvailable_SameVersionNewerBuild() async {
        // Given
        let result = await controller.isUpdateAvailable(
            currentVersion: "1.0.0",
            currentBuild: "100",
            remoteVersion: "1.0.0",
            remoteBuild: "101"
        )

        // Then
        XCTAssertTrue(result)
    }

    func testIsUpdateAvailable_SameVersionSameBuild() async {
        // Given
        let result = await controller.isUpdateAvailable(
            currentVersion: "1.0.0",
            currentBuild: "100",
            remoteVersion: "1.0.0",
            remoteBuild: "100"
        )

        // Then
        XCTAssertFalse(result)
    }

    func testIsUpdateAvailable_CurrentVersionNewer() async {
        // Given
        let result = await controller.isUpdateAvailable(
            currentVersion: "1.1.0",
            currentBuild: "110",
            remoteVersion: "1.0.0",
            remoteBuild: "100"
        )

        // Then
        XCTAssertFalse(result)
    }

    func testIsUpdateAvailable_SameVersionCurrentBuildNewer() async {
        // Given
        let result = await controller.isUpdateAvailable(
            currentVersion: "1.0.0",
            currentBuild: "110",
            remoteVersion: "1.0.0",
            remoteBuild: "100"
        )

        // Then
        XCTAssertFalse(result)
    }

    func testIsUpdateAvailable_SameVersionNoBuildNumbers() async {
        // Given
        let result = await controller.isUpdateAvailable(
            currentVersion: "1.0.0",
            currentBuild: nil,
            remoteVersion: "1.0.0",
            remoteBuild: "100"
        )

        // Then
        XCTAssertFalse(result)
    }

    // MARK: - Basic Update Check Tests

    func testCheckForUpdate_DoesNotCrash() {
        // When
        controller.checkForUpdate()

        // Then - Just verify the method doesn't crash
        XCTAssertNotNil(controller)
    }

    func testCheckForUpdateAutomatically_DoesNotCrash() {
        // When
        controller.checkForUpdateAutomatically()

        // Then - Just verify the method doesn't crash
        XCTAssertNotNil(controller)
    }

    // MARK: - State Management Tests

    func testHasPendingUpdatePublisher_InitialValue() {
        let expectation = expectation(description: "hasPendingUpdate should emit initial value")

        controller.hasPendingUpdatePublisher
            .sink { value in
                XCTAssertFalse(value) // Initial value should be false
                expectation.fulfill()
            }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)
    }

    func testNotificationDotPublisher_InitialValue() {
        let expectation = expectation(description: "needsNotificationDot should emit initial value")

        controller.notificationDotPublisher
            .sink { value in
                XCTAssertFalse(value) // Initial value should be false
                expectation.fulfill()
            }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)
    }
}
