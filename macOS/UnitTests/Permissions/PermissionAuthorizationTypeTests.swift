//
//  PermissionAuthorizationTypeTests.swift
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
@testable import DuckDuckGo_Privacy_Browser

final class PermissionAuthorizationTypeTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitFromSingleCameraPermission() {
        let type = PermissionAuthorizationType(from: [.camera])
        XCTAssertEqual(type, .camera)
    }

    func testInitFromSingleMicrophonePermission() {
        let type = PermissionAuthorizationType(from: [.microphone])
        XCTAssertEqual(type, .microphone)
    }

    func testInitFromSingleGeolocationPermission() {
        let type = PermissionAuthorizationType(from: [.geolocation])
        XCTAssertEqual(type, .geolocation)
    }

    func testInitFromSinglePopupsPermission() {
        let type = PermissionAuthorizationType(from: [.popups])
        XCTAssertEqual(type, .popups)
    }

    func testInitFromSingleExternalSchemePermission() {
        let type = PermissionAuthorizationType(from: [.externalScheme(scheme: "zoom")])
        XCTAssertEqual(type, .externalScheme(scheme: "zoom"))
    }

    func testInitFromCameraAndMicrophonePermissions() {
        let type = PermissionAuthorizationType(from: [.camera, .microphone])
        XCTAssertEqual(type, .cameraAndMicrophone)
    }

    func testInitFromMicrophoneAndCameraPermissions_OrderIndependent() {
        let type = PermissionAuthorizationType(from: [.microphone, .camera])
        XCTAssertEqual(type, .cameraAndMicrophone)
    }

    // MARK: - requiresSystemPermission Tests

    func testRequiresSystemPermission_Geolocation_ReturnsTrue() {
        XCTAssertTrue(PermissionAuthorizationType.geolocation.requiresSystemPermission)
    }

    func testRequiresSystemPermission_Camera_ReturnsFalse() {
        XCTAssertFalse(PermissionAuthorizationType.camera.requiresSystemPermission)
    }

    func testRequiresSystemPermission_Microphone_ReturnsFalse() {
        XCTAssertFalse(PermissionAuthorizationType.microphone.requiresSystemPermission)
    }

    func testRequiresSystemPermission_CameraAndMicrophone_ReturnsFalse() {
        XCTAssertFalse(PermissionAuthorizationType.cameraAndMicrophone.requiresSystemPermission)
    }

    func testRequiresSystemPermission_Popups_ReturnsFalse() {
        XCTAssertFalse(PermissionAuthorizationType.popups.requiresSystemPermission)
    }

    func testRequiresSystemPermission_ExternalScheme_ReturnsFalse() {
        XCTAssertFalse(PermissionAuthorizationType.externalScheme(scheme: "zoom").requiresSystemPermission)
    }

    // MARK: - usesPermanentDecisions Tests

    func testUsesPermanentDecisions_AllCases_ReturnTrue() {
        XCTAssertTrue(PermissionAuthorizationType.camera.usesPermanentDecisions)
        XCTAssertTrue(PermissionAuthorizationType.microphone.usesPermanentDecisions)
        XCTAssertTrue(PermissionAuthorizationType.cameraAndMicrophone.usesPermanentDecisions)
        XCTAssertTrue(PermissionAuthorizationType.geolocation.usesPermanentDecisions)
        XCTAssertTrue(PermissionAuthorizationType.popups.usesPermanentDecisions)
        XCTAssertTrue(PermissionAuthorizationType.externalScheme(scheme: "zoom").usesPermanentDecisions)
    }

    // MARK: - asPermissionType Tests

    func testAsPermissionType_Camera() {
        XCTAssertEqual(PermissionAuthorizationType.camera.asPermissionType, .camera)
    }

    func testAsPermissionType_Microphone() {
        XCTAssertEqual(PermissionAuthorizationType.microphone.asPermissionType, .microphone)
    }

    func testAsPermissionType_CameraAndMicrophone_ReturnsCamera() {
        // cameraAndMicrophone maps to .camera for system permission checks
        XCTAssertEqual(PermissionAuthorizationType.cameraAndMicrophone.asPermissionType, .camera)
    }

    func testAsPermissionType_Geolocation() {
        XCTAssertEqual(PermissionAuthorizationType.geolocation.asPermissionType, .geolocation)
    }

    func testAsPermissionType_Popups() {
        XCTAssertEqual(PermissionAuthorizationType.popups.asPermissionType, .popups)
    }

    func testAsPermissionType_ExternalScheme() {
        XCTAssertEqual(PermissionAuthorizationType.externalScheme(scheme: "zoom").asPermissionType, .externalScheme(scheme: "zoom"))
    }

    // MARK: - localizedDescription Tests

    func testLocalizedDescription_Camera() {
        XCTAssertEqual(PermissionAuthorizationType.camera.localizedDescription, UserText.permissionCamera)
    }

    func testLocalizedDescription_Microphone() {
        XCTAssertEqual(PermissionAuthorizationType.microphone.localizedDescription, UserText.permissionMicrophone)
    }

    func testLocalizedDescription_CameraAndMicrophone() {
        XCTAssertEqual(PermissionAuthorizationType.cameraAndMicrophone.localizedDescription, UserText.permissionCameraAndMicrophone)
    }

    func testLocalizedDescription_Geolocation() {
        XCTAssertEqual(PermissionAuthorizationType.geolocation.localizedDescription, UserText.permissionGeolocation)
    }

    func testLocalizedDescription_Popups() {
        XCTAssertEqual(PermissionAuthorizationType.popups.localizedDescription, UserText.permissionPopups)
    }

    // MARK: - systemSettingsURL Tests

    func testSystemSettingsURL_Geolocation_ReturnsValidURL() {
        let url = PermissionAuthorizationType.geolocation.systemSettingsURL
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.absoluteString, "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
    }

    func testSystemSettingsURL_NonGeolocation_ReturnsNil() {
        XCTAssertNil(PermissionAuthorizationType.camera.systemSettingsURL)
        XCTAssertNil(PermissionAuthorizationType.microphone.systemSettingsURL)
        XCTAssertNil(PermissionAuthorizationType.cameraAndMicrophone.systemSettingsURL)
        XCTAssertNil(PermissionAuthorizationType.popups.systemSettingsURL)
        XCTAssertNil(PermissionAuthorizationType.externalScheme(scheme: "zoom").systemSettingsURL)
    }

    // MARK: - Two-Step UI String Tests

    func testSystemPermissionEnableText_Geolocation() {
        XCTAssertEqual(PermissionAuthorizationType.geolocation.systemPermissionEnableText, UserText.permissionSystemLocationEnable)
    }

    func testSystemPermissionEnableText_NonGeolocation_ReturnsEmpty() {
        XCTAssertEqual(PermissionAuthorizationType.camera.systemPermissionEnableText, "")
        XCTAssertEqual(PermissionAuthorizationType.microphone.systemPermissionEnableText, "")
        XCTAssertEqual(PermissionAuthorizationType.cameraAndMicrophone.systemPermissionEnableText, "")
        XCTAssertEqual(PermissionAuthorizationType.popups.systemPermissionEnableText, "")
        XCTAssertEqual(PermissionAuthorizationType.externalScheme(scheme: "zoom").systemPermissionEnableText, "")
    }

    func testSystemPermissionWaitingText_Geolocation() {
        XCTAssertEqual(PermissionAuthorizationType.geolocation.systemPermissionWaitingText, UserText.permissionSystemLocationWaiting)
    }

    func testSystemPermissionEnabledText_Geolocation() {
        XCTAssertEqual(PermissionAuthorizationType.geolocation.systemPermissionEnabledText, UserText.permissionSystemLocationEnabled)
    }

    func testSystemPermissionDisabledText_Geolocation() {
        XCTAssertEqual(PermissionAuthorizationType.geolocation.systemPermissionDisabledText, UserText.permissionSystemLocationDisabled)
    }

    func testSystemSettingsLinkText_Geolocation() {
        XCTAssertEqual(PermissionAuthorizationType.geolocation.systemSettingsLinkText, UserText.permissionSystemSettingsLocation)
    }
}

// MARK: - Equatable Conformance for Tests

extension PermissionAuthorizationType: Equatable {
    public static func == (lhs: PermissionAuthorizationType, rhs: PermissionAuthorizationType) -> Bool {
        switch (lhs, rhs) {
        case (.camera, .camera),
             (.microphone, .microphone),
             (.cameraAndMicrophone, .cameraAndMicrophone),
             (.geolocation, .geolocation),
             (.popups, .popups):
            return true
        case (.externalScheme(let lhsScheme), .externalScheme(let rhsScheme)):
            return lhsScheme == rhsScheme
        default:
            return false
        }
    }
}
