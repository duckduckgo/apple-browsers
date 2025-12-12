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
import XCTest

@testable import DuckDuckGo_Privacy_Browser

/// Tests for PermissionCenterViewModel filtering behavior.
final class PermissionCenterViewModelTests: XCTestCase {

    var mockPermissionManager: PermissionManagerMock!
    var mockSystemPermissionManager: MockSystemPermissionManager!
    var mockFeatureFlagger: MockFeatureFlagger!

    override func setUp() {
        super.setUp()
        mockPermissionManager = PermissionManagerMock()
        mockSystemPermissionManager = MockSystemPermissionManager()
        mockFeatureFlagger = MockFeatureFlagger()
    }

    override func tearDown() {
        mockPermissionManager = nil
        mockSystemPermissionManager = nil
        mockFeatureFlagger = nil
        super.tearDown()
    }

    /// Tests that notification permissions appear in the permission items list.
    func testNotificationPermissionsAppearInUI() {
        // Create permissions including notification
        var usedPermissions = Permissions()
        usedPermissions[.camera] = .active(query: nil)
        usedPermissions[.notification] = .active(query: nil)
        usedPermissions[.microphone] = .active(query: nil)

        let viewModel = PermissionCenterViewModel(
            domain: "example.com",
            usedPermissions: usedPermissions,
            permissionManager: mockPermissionManager,
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
        usedPermissions[.camera] = .active(query: nil)
        usedPermissions[.notification] = .active(query: nil)
        usedPermissions[.geolocation] = .active(query: nil)

        let viewModel = PermissionCenterViewModel(
            domain: "example.com",
            usedPermissions: usedPermissions,
            permissionManager: mockPermissionManager,
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
}

// MARK: - Mock System Permission Manager

final class MockSystemPermissionManager: SystemPermissionManagerProtocol {

    var authorizationStateToReturn: SystemPermissionAuthorizationState = .authorized

    func authorizationState(for permissionType: PermissionType) async -> SystemPermissionAuthorizationState {
        return authorizationStateToReturn
    }

    func isAuthorizationRequired(for permissionType: PermissionType) async -> Bool {
        return false
    }

    func requestAuthorization(for permissionType: PermissionType, completion: @escaping (SystemPermissionAuthorizationState) -> Void) -> AnyCancellable? {
        completion(authorizationStateToReturn)
        return nil
    }
}
