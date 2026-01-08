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
#if APPSTORE
import Combine
import NetworkingTestingUtils
import PrivacyConfig
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class AppStoreUpdateControllerTests: XCTestCase {

    private var controller: AppStoreUpdateController!
    private var cancellables: Set<AnyCancellable>!
    private var mockAppStoreOpener: MockAppStoreOpener!

    override func setUp() {
        super.setUp()
        autoreleasepool {
            // Use mocked dependencies to prevent actual App Store from opening
            mockAppStoreOpener = MockAppStoreOpener()
            controller = AppStoreUpdateController(appStoreOpener: mockAppStoreOpener)
            cancellables = Set<AnyCancellable>()
        }
    }

    override func tearDown() {
        cancellables?.removeAll()
        controller = nil
        mockAppStoreOpener = nil
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
        controller.checkForUpdateSkippingRollout()

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

    // MARK: - Feature Flag Tests

    func testCheckForUpdate_FeatureFlagOff_GoesDirectlyToAppStore() {
        autoreleasepool {
            // Given
            let mockFeatureFlagger = MockFeatureFlagger()
            let mockAppStoreOpener = MockAppStoreOpener()
            // Feature flag is OFF by default

            let controller = AppStoreUpdateController(
                featureFlagger: mockFeatureFlagger,
                appStoreOpener: mockAppStoreOpener
            )

            // When
            controller.checkForUpdateSkippingRollout()

            // Then - Should go directly to App Store
            XCTAssertTrue(mockAppStoreOpener.openAppStoreCalled, "Should open App Store when feature flag is off")
            XCTAssertEqual(mockAppStoreOpener.openAppStoreCallCount, 1)
        }
    }

    func testCheckForUpdate_FeatureFlagOn_PerformsCloudCheck() {
        autoreleasepool {
            // Given
            let mockFeatureFlagger = MockFeatureFlagger()
            let mockAppStoreOpener = MockAppStoreOpener()
            mockFeatureFlagger.enabledFeatureFlags = [.appStoreUpdateFlow]

            let controller = AppStoreUpdateController(
                featureFlagger: mockFeatureFlagger,
                appStoreOpener: mockAppStoreOpener
            )

            // When
            controller.checkForUpdateSkippingRollout()

            // Then - Should attempt cloud check, NOT open App Store directly
            XCTAssertFalse(mockAppStoreOpener.openAppStoreCalled, "Should not open App Store when feature flag is on")
            XCTAssertEqual(mockAppStoreOpener.openAppStoreCallCount, 0)
        }
    }

    func testCheckForUpdateAutomatically_FeatureFlagOff_DoesNothing() {
        autoreleasepool {
            // Given
            let mockFeatureFlagger = MockFeatureFlagger()
            let mockAppStoreOpener = MockAppStoreOpener()
            // Feature flag is OFF by default

            let controller = AppStoreUpdateController(
                featureFlagger: mockFeatureFlagger,
                appStoreOpener: mockAppStoreOpener
            )

            // When
            controller.checkForUpdateAutomatically()

            // Then - Should do nothing (no cloud check, no crash, no App Store opening)
            XCTAssertFalse(mockAppStoreOpener.openAppStoreCalled, "Should not open App Store on automatic check when feature flag is off")
        }
    }

    func testCheckForUpdateAutomatically_FeatureFlagOn_PerformsCheck() {
        autoreleasepool {
            // Given
            let mockFeatureFlagger = MockFeatureFlagger()
            let mockAppStoreOpener = MockAppStoreOpener()
            mockFeatureFlagger.enabledFeatureFlags = [.appStoreUpdateFlow]

            let controller = AppStoreUpdateController(
                featureFlagger: mockFeatureFlagger,
                appStoreOpener: mockAppStoreOpener
            )

            // When
            controller.checkForUpdateAutomatically()

            // Then - Should attempt automatic check without opening App Store
            XCTAssertFalse(mockAppStoreOpener.openAppStoreCalled, "Should not open App Store on automatic check")
        }
    }

    func testInitialization_FeatureFlagOff_SkipsSetup() {
        autoreleasepool {
            // Given
            let mockFeatureFlagger = MockFeatureFlagger()
            let mockAppStoreOpener = MockAppStoreOpener()
            // Feature flag is OFF by default

            // When
            let controller = AppStoreUpdateController(
                featureFlagger: mockFeatureFlagger,
                appStoreOpener: mockAppStoreOpener
            )

            // Then - Should initialize without setting up automatic checks
            XCTAssertNotNil(controller)
            XCTAssertFalse(controller.hasPendingUpdate)
            XCTAssertFalse(controller.needsNotificationDot)
        }
    }

    func testInitialization_FeatureFlagOn_PerformsSetup() {
        autoreleasepool {
            // Given
            let mockFeatureFlagger = MockFeatureFlagger()
            let mockAppStoreOpener = MockAppStoreOpener()
            mockFeatureFlagger.enabledFeatureFlags = [.appStoreUpdateFlow]

            // When
            let controller = AppStoreUpdateController(
                featureFlagger: mockFeatureFlagger,
                appStoreOpener: mockAppStoreOpener
            )

            // Then - Should initialize and set up automatic checks
            XCTAssertNotNil(controller)
            XCTAssertFalse(controller.hasPendingUpdate) // Initial state
            XCTAssertFalse(controller.needsNotificationDot) // Initial state
        }
    }

    // MARK: - App Store Opening Tests

    func testRunUpdate_AlwaysOpensAppStore() {
        autoreleasepool {
            // Given
            let mockAppStoreOpener = MockAppStoreOpener()
            let controller = AppStoreUpdateController(appStoreOpener: mockAppStoreOpener)

            // When
            controller.runUpdate()

            // Then - Should always open App Store regardless of feature flag
            XCTAssertTrue(mockAppStoreOpener.openAppStoreCalled, "runUpdate should always open App Store")
            XCTAssertEqual(mockAppStoreOpener.openAppStoreCallCount, 1)
        }
    }

    func testRunUpdate_AlwaysOpensAppStore_EvenWithFeatureFlagOn() {
        autoreleasepool {
            // Given
            let mockFeatureFlagger = MockFeatureFlagger()
            mockFeatureFlagger.enabledFeatureFlags = [.appStoreUpdateFlow]
            let mockAppStoreOpener = MockAppStoreOpener()

            let controller = AppStoreUpdateController(
                featureFlagger: mockFeatureFlagger,
                appStoreOpener: mockAppStoreOpener
            )

            // When
            controller.runUpdate()

            // Then - Should open App Store even when feature flag is on
            XCTAssertTrue(mockAppStoreOpener.openAppStoreCalled, "runUpdate should always open App Store")
            XCTAssertEqual(mockAppStoreOpener.openAppStoreCallCount, 1)
        }
    }

    func testOpenUpdatesPage_OpensAppStore() {
        autoreleasepool {
            // Given
            let mockAppStoreOpener = MockAppStoreOpener()
            let controller = AppStoreUpdateController(appStoreOpener: mockAppStoreOpener)

            // When
            controller.openUpdatesPage()

            // Then - Should open App Store
            XCTAssertTrue(mockAppStoreOpener.openAppStoreCalled, "openUpdatesPage should open App Store")
            XCTAssertEqual(mockAppStoreOpener.openAppStoreCallCount, 1)
        }
    }

    func testOpenUpdatesPage_CanBeCalledMultipleTimes() {
        autoreleasepool {
            // Given
            let mockAppStoreOpener = MockAppStoreOpener()
            let controller = AppStoreUpdateController(appStoreOpener: mockAppStoreOpener)

            // When
            controller.openUpdatesPage()
            controller.openUpdatesPage()
            controller.openUpdatesPage()

            // Then - Should track multiple calls
            XCTAssertTrue(mockAppStoreOpener.openAppStoreCalled)
            XCTAssertEqual(mockAppStoreOpener.openAppStoreCallCount, 3)
        }
    }

    // MARK: - Debug Settings Tests

    func testIsUpdateAvailable_WithForceUpdateDebugSetting_InternalUser_ReturnsTrue() {
        autoreleasepool {
            // Given
            let debugSettings = UpdatesDebugSettings()
            let mockInternalUserDecider = MockInternalUserDecider(isInternalUser: true)
            let mockAppStoreOpener = MockAppStoreOpener()

            let controller = AppStoreUpdateController(
                internalUserDecider: mockInternalUserDecider,
                appStoreOpener: mockAppStoreOpener
            )

            // When - enabling force update debug setting
            debugSettings.forceUpdateAvailable = true

            // Then - should always return true regardless of versions for internal users
            let expectation = XCTestExpectation(description: "Update available check")

            Task {
                let result = await controller.isUpdateAvailable(
                    currentVersion: "2.0.0",
                    currentBuild: "999",
                    remoteVersion: "1.0.0",
                    remoteBuild: "1"
                )

                XCTAssertTrue(result, "Should return true when force update is enabled for internal users")
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 1.0)

            // Cleanup
            debugSettings.reset()
        }
    }

    func testIsUpdateAvailable_WithForceUpdateDebugSetting_ExternalUser_ReturnsNormalLogic() {
        autoreleasepool {
            // Given
            let debugSettings = UpdatesDebugSettings()
            let mockInternalUserDecider = MockInternalUserDecider(isInternalUser: false) // External user
            let mockAppStoreOpener = MockAppStoreOpener()

            let controller = AppStoreUpdateController(
                internalUserDecider: mockInternalUserDecider,
                appStoreOpener: mockAppStoreOpener
            )

            // When - enabling force update debug setting (but user is external)
            debugSettings.forceUpdateAvailable = true

            // Then - should follow normal logic since user is not internal
            let expectation = XCTestExpectation(description: "Update available check")

            Task {
                let result = await controller.isUpdateAvailable(
                    currentVersion: "2.0.0",
                    currentBuild: "999",
                    remoteVersion: "1.0.0",
                    remoteBuild: "1"
                )

                XCTAssertFalse(result, "Should return false (normal logic) when force update is enabled but user is not internal")
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 1.0)

            // Cleanup
            debugSettings.reset()
        }
    }

    func testIsUpdateAvailable_WithoutForceUpdateDebugSetting_ReturnsNormalLogic() {
        autoreleasepool {
            // Given
            let debugSettings = UpdatesDebugSettings()
            let mockInternalUserDecider = MockInternalUserDecider(isInternalUser: true) // Even internal users follow normal logic when debug is off
            let mockAppStoreOpener = MockAppStoreOpener()

            debugSettings.forceUpdateAvailable = false // Ensure it's off

            let controller = AppStoreUpdateController(
                internalUserDecider: mockInternalUserDecider,
                appStoreOpener: mockAppStoreOpener
            )

            // When & Then - should follow normal version comparison logic
            let expectation = XCTestExpectation(description: "Normal update check")

            Task {
                let result = await controller.isUpdateAvailable(
                    currentVersion: "2.0.0",
                    currentBuild: "999",
                    remoteVersion: "1.0.0",
                    remoteBuild: "1"
                )

                XCTAssertFalse(result, "Should return false when current version is newer, even for internal users when debug is off")
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 1.0)
        }
    }
}

// MARK: - Mock Objects

class MockAppStoreOpener: AppStoreOpener {
    private(set) var openAppStoreCalled = false
    private(set) var openAppStoreCallCount = 0

    func openAppStore() {
        openAppStoreCalled = true
        openAppStoreCallCount += 1
    }

    func reset() {
        openAppStoreCalled = false
        openAppStoreCallCount = 0
    }
}

#endif
