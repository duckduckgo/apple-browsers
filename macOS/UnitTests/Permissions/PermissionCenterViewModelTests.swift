//
//  PermissionCenterViewModelTests.swift
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

import Combine
import FeatureFlags
import PrivacyConfig
import XCTest

@testable import DuckDuckGo_Privacy_Browser

/// Tests for PermissionCenterViewModel filtering behavior.
final class PermissionCenterViewModelTests: XCTestCase {

    var mockPermissionManager: PermissionManagerMock!
    var mockSystemPermissionManager: MockSystemPermissionManager!
    var mockFeatureFlagger: MockFeatureFlagger!
    var autoplayPreferences: AutoplayPreferences!

    override func setUp() {
        super.setUp()
        mockPermissionManager = PermissionManagerMock()
        mockSystemPermissionManager = MockSystemPermissionManager()
        mockFeatureFlagger = MockFeatureFlagger()
        autoplayPreferences = AutoplayPreferences()
    }

    override func tearDown() {
        mockPermissionManager = nil
        mockSystemPermissionManager = nil
        mockFeatureFlagger = nil
        autoplayPreferences = nil
        super.tearDown()
    }

    /// Tests that notification permissions appear in the permission items list.
    func testNotificationPermissionsAppearInUI() {
        // Create permissions including notification
        var usedPermissions = Permissions()
        usedPermissions[.camera] = .active
        usedPermissions[.notification] = .active
        usedPermissions[.microphone] = .active

        let viewModel = PermissionCenterViewModel(
            domain: "example.com",
            usedPermissions: usedPermissions,
            permissionManager: mockPermissionManager,
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            removePermission: { _ in },
            dismissPopover: { },
            systemPermissionManager: mockSystemPermissionManager
        )

        // Verify notification is in the items
        let permissionTypes = viewModel.permissionItems.map { $0.permissionType }
        XCTAssertTrue(permissionTypes.contains(.notification), "Notification should appear in UI")
        XCTAssertTrue(permissionTypes.contains(.camera), "Camera should be present")
        XCTAssertTrue(permissionTypes.contains(.microphone), "Microphone should be present")
    }

    /// Tests that notification permissions work alongside other permissions.
    func testNotificationPermissionsWorkAlongsideOtherPermissions() {
        var usedPermissions = Permissions()
        usedPermissions[.camera] = .active
        usedPermissions[.notification] = .active
        usedPermissions[.geolocation] = .active

        let viewModel = PermissionCenterViewModel(
            domain: "example.com",
            usedPermissions: usedPermissions,
            permissionManager: mockPermissionManager,
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            removePermission: { _ in },
            dismissPopover: { },
            systemPermissionManager: mockSystemPermissionManager
        )

        XCTAssertEqual(viewModel.permissionItems.count, 3, "Should show all three permissions")
        let types = viewModel.permissionItems.map { $0.permissionType }
        XCTAssertTrue(types.contains(.notification))
        XCTAssertTrue(types.contains(.camera))
        XCTAssertTrue(types.contains(.geolocation))
    }

    // MARK: - requestSystemPermission Tests

    /// Verifies requestSystemPermission calls the system permission manager with correct permission type.
    func testWhenRequestSystemPermissionCalledThenSystemManagerRequestsAuthorization() {
        var usedPermissions = Permissions()
        usedPermissions[.notification] = .active

        let viewModel = PermissionCenterViewModel(
            domain: "example.com",
            usedPermissions: usedPermissions,
            permissionManager: mockPermissionManager,
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            removePermission: { _ in },
            dismissPopover: { },
            systemPermissionManager: mockSystemPermissionManager
        )

        viewModel.requestSystemPermission(for: .notification)

        XCTAssertTrue(mockSystemPermissionManager.requestAuthorizationCalled)
        XCTAssertEqual(mockSystemPermissionManager.lastRequestedPermissionType, .notification)
    }

    /// Verifies permission item's systemAuthorizationState updates after authorization request completes.
    func testWhenSystemPermissionGrantedThenPermissionItemStateUpdates() async throws {
        mockSystemPermissionManager.authorizationStateToReturn = .notDetermined

        var usedPermissions = Permissions()
        usedPermissions[.notification] = .active

        let viewModel = PermissionCenterViewModel(
            domain: "example.com",
            usedPermissions: usedPermissions,
            permissionManager: mockPermissionManager,
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            removePermission: { _ in },
            dismissPopover: { },
            systemPermissionManager: mockSystemPermissionManager
        )

        // Change the state that will be returned after request
        mockSystemPermissionManager.authorizationStateToReturn = .authorized

        viewModel.requestSystemPermission(for: .notification)

        // Wait for async state update
        try await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)

        // Find the notification item and verify its system state was updated
        let notificationItem = viewModel.permissionItems.first { $0.permissionType == .notification }
        XCTAssertEqual(notificationItem?.systemAuthorizationState, .authorized)
    }
    // MARK: - Autoplay Row Visibility Tests

    func testWhenDisplayAutoplayPolicyIsEnabledThenAutoplayRowAppearsInPermissionItems() {
        let viewModel = PermissionCenterViewModel(
            domain: "example.com",
            usedPermissions: Permissions(),
            permissionManager: mockPermissionManager,
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            removePermission: { _ in },
            dismissPopover: { },
            displaysAutoplayPolicy: true,
            systemPermissionManager: mockSystemPermissionManager
        )

        let types = viewModel.permissionItems.map { $0.permissionType }
        XCTAssertTrue(types.contains(.autoplayPolicy), "Autoplay row should appear when feature flag is on")
    }

    func testWhenDisplaysAutoplayPolicyIsDisabledThenAutoplayRowDoesNotAppear() {
        let viewModel = PermissionCenterViewModel(
            domain: "example.com",
            usedPermissions: Permissions(),
            permissionManager: mockPermissionManager,
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            removePermission: { _ in },
            dismissPopover: { },
            displaysAutoplayPolicy: false,
            systemPermissionManager: mockSystemPermissionManager
        )

        let types = viewModel.permissionItems.map { $0.permissionType }
        XCTAssertFalse(types.contains(.autoplayPolicy), "Autoplay row should not appear when feature flag is off")
    }

    // MARK: - currentAutoplayDecision Tests

    func testWhenNoOverrideAndGlobalBlockAudioThenCurrentDecisionIsAudioMuted() {
        let persistor = AutoplayPreferencesPersistorMock(autoplayBlockingModeRawValue: AutoplayBlockingMode.blockAudio.rawValue)
        let autoplayPreferences = AutoplayPreferences(persistor: persistor)

        let viewModel = PermissionCenterViewModel(
            domain: "example.com",
            usedPermissions: Permissions(),
            permissionManager: mockPermissionManager,
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            removePermission: { _ in },
            dismissPopover: { },
            systemPermissionManager: mockSystemPermissionManager
        )

        XCTAssertEqual(viewModel.currentAutoplayDecision(), .audioMuted)
    }

    func testWhenNoOverrideThenCurrentDecisionMatchesGlobalPreference() {
        let cases: [(AutoplayBlockingMode, AutoplayDecision)] = [
            (.blockAudio, .audioMuted),
            (.allowAll, .allowAll),
            (.blockAll, .blockAll),
        ]

        for (blockingMode, expectedDecision) in cases {
            let persistor = AutoplayPreferencesPersistorMock(autoplayBlockingModeRawValue: blockingMode.rawValue)
            let autoplayPreferences = AutoplayPreferences(persistor: persistor)

            let viewModel = PermissionCenterViewModel(
                domain: "example.com",
                usedPermissions: Permissions(),
                permissionManager: mockPermissionManager,
                autoplayPreferences: autoplayPreferences,
                featureFlagger: mockFeatureFlagger,
                removePermission: { _ in },
                dismissPopover: { },
                systemPermissionManager: mockSystemPermissionManager
            )

            XCTAssertEqual(viewModel.currentAutoplayDecision(), expectedDecision, "Global \(blockingMode) should map to \(expectedDecision)")
        }
    }

    func testWhenAutoplayAllowPersistedThenCurrentDecisionIsAllowAll() {
        mockPermissionManager.setPermission(.allow, forDomain: "example.com", permissionType: .autoplayPolicy)

        let viewModel = PermissionCenterViewModel(
            domain: "example.com",
            usedPermissions: Permissions(),
            permissionManager: mockPermissionManager,
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            removePermission: { _ in },
            dismissPopover: { },
            systemPermissionManager: mockSystemPermissionManager
        )

        XCTAssertEqual(viewModel.currentAutoplayDecision(), .allowAll)
    }

    func testWhenAutoplayDenyPersistedThenCurrentDecisionIsBlockAll() {
        mockPermissionManager.setPermission(.deny, forDomain: "example.com", permissionType: .autoplayPolicy)

        let viewModel = PermissionCenterViewModel(
            domain: "example.com",
            usedPermissions: Permissions(),
            permissionManager: mockPermissionManager,
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            removePermission: { _ in },
            dismissPopover: { },
            systemPermissionManager: mockSystemPermissionManager
        )

        XCTAssertEqual(viewModel.currentAutoplayDecision(), .blockAll)
    }

    func testWhenAutoplayAskPersistedThenCurrentDecisionIsAudioMuted() {
        mockPermissionManager.setPermission(.ask, forDomain: "example.com", permissionType: .autoplayPolicy)

        let viewModel = PermissionCenterViewModel(
            domain: "example.com",
            usedPermissions: Permissions(),
            permissionManager: mockPermissionManager,
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            removePermission: { _ in },
            dismissPopover: { },
            systemPermissionManager: mockSystemPermissionManager
        )

        XCTAssertEqual(viewModel.currentAutoplayDecision(), .audioMuted)
    }

    // MARK: - setAutoplayDecision Tests

    func testWhenSetAutoplayDecisionThenCorrectPermissionIsStored() {
        let cases: [(AutoplayDecision, PersistedPermissionDecision)] = [
            (.allowAll, .allow),
            (.audioMuted, .ask),
            (.blockAll, .deny),
        ]

        for (decision, expectedPermission) in cases {
            mockPermissionManager = PermissionManagerMock()

            let viewModel = PermissionCenterViewModel(
                domain: "example.com",
                usedPermissions: Permissions(),
                permissionManager: mockPermissionManager,
                autoplayPreferences: autoplayPreferences,
                featureFlagger: mockFeatureFlagger,
                removePermission: { _ in },
                dismissPopover: { },
                systemPermissionManager: mockSystemPermissionManager
            )

            viewModel.setAutoplayDecision(decision)

            XCTAssertEqual(mockPermissionManager.permission(forDomain: "example.com", permissionType: .autoplayPolicy), expectedPermission, "Setting \(decision) should store \(expectedPermission)")
        }
    }

    func testWhenSetAutoplayDecisionWithSameValueAlreadyPersistedThenNoOp() {
        mockPermissionManager.setPermission(.deny, forDomain: "example.com", permissionType: .autoplayPolicy)
        mockPermissionManager.setPermissionCalls.removeAll()

        let viewModel = PermissionCenterViewModel(
            domain: "example.com",
            usedPermissions: Permissions(),
            permissionManager: mockPermissionManager,
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            removePermission: { _ in },
            dismissPopover: { },
            systemPermissionManager: mockSystemPermissionManager
        )

        viewModel.setAutoplayDecision(.blockAll)

        XCTAssertTrue(mockPermissionManager.setPermissionCalls.isEmpty, "Should not re-persist when value and persisted state are unchanged")
        XCTAssertFalse(viewModel.showReloadBanner, "Reload banner should not show when nothing changed")
    }

    func testWhenSetAutoplayDecisionWithSameValueButNotPersistedThenPersists() {
        // mockPermissionManager has no persisted autoplay permission.
        // Its default return from permission(forDomain:permissionType:) is .ask,
        // which matches .audioMuted's permissionDecision.
        let viewModel = PermissionCenterViewModel(
            domain: "example.com",
            usedPermissions: Permissions(),
            permissionManager: mockPermissionManager,
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            removePermission: { _ in },
            dismissPopover: { },
            systemPermissionManager: mockSystemPermissionManager
        )

        viewModel.setAutoplayDecision(.audioMuted)

        XCTAssertEqual(mockPermissionManager.permission(forDomain: "example.com", permissionType: .autoplayPolicy), .ask,
                       "Should persist the decision even when it matches the default value")
        XCTAssertTrue(viewModel.showReloadBanner, "Reload banner should show for a newly persisted override")
    }

    func testWhenSetAutoplayDecisionThenReloadBannerIsShown() {
        let viewModel = PermissionCenterViewModel(
            domain: "example.com",
            usedPermissions: Permissions(),
            permissionManager: mockPermissionManager,
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            removePermission: { _ in },
            dismissPopover: { },
            systemPermissionManager: mockSystemPermissionManager
        )

        viewModel.setAutoplayDecision(.blockAll)

        XCTAssertTrue(viewModel.showReloadBanner, "Reload banner should be shown after changing autoplay decision")
    }
}

// MARK: - Mock System Permission Manager

final class MockSystemPermissionManager: SystemPermissionManagerProtocol {

    var authorizationStateToReturn: SystemPermissionAuthorizationState = .authorized
    private(set) var requestAuthorizationCalled = false
    private(set) var lastRequestedPermissionType: PermissionType?

    func authorizationState(for permissionType: PermissionType) async -> SystemPermissionAuthorizationState {
        return authorizationStateToReturn
    }

    func cachedAuthorizationState(for permissionType: PermissionType) -> SystemPermissionAuthorizationState {
        return authorizationStateToReturn
    }

    func isAuthorizationRequired(for permissionType: PermissionType) -> Bool {
        return false
    }

    func requestAuthorization(for permissionType: PermissionType, completion: @escaping (SystemPermissionAuthorizationState) -> Void) -> AnyCancellable? {
        requestAuthorizationCalled = true
        lastRequestedPermissionType = permissionType
        completion(authorizationStateToReturn)
        return nil
    }
}
