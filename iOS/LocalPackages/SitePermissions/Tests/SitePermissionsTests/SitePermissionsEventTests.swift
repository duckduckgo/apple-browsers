//
//  SitePermissionsEventTests.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
@testable import SitePermissions

final class SitePermissionsEventTests: XCTestCase {

    func testWhenPermissionSetsAreSupportedThenTheyProduceExpectedTokens() {
        let cases: [(Set<SitePermissionType>, SitePermissionsEvent.PermissionType, String)] = [
            ([.camera], .camera, "camera"),
            ([.microphone], .microphone, "microphone"),
            ([.camera, .microphone], .cameraAndMicrophone, "camera_and_microphone"),
            ([.location], .geolocation, "geolocation")
        ]

        for (permissionTypes, expectedType, expectedToken) in cases {
            let type = SitePermissionsEvent.PermissionType(permissionTypes)

            XCTAssertEqual(type, expectedType)
            XCTAssertEqual(type?.rawValue, expectedToken)
        }
    }

    func testWhenPermissionSetCannotBeRepresentedByOnePixelTokenThenConstructionFails() {
        let unsupportedPermissionSets: [Set<SitePermissionType>] = [
            [],
            [.camera, .location],
            [.microphone, .location],
            [.camera, .microphone, .location]
        ]

        for permissionTypes in unsupportedPermissionSets {
            XCTAssertNil(SitePermissionsEvent.PermissionType(permissionTypes))
        }
    }

    func testSystemPromptResultTypeCanOnlyUseIndividualPermissionTokens() {
        XCTAssertEqual(SitePermissionType.allCases.map(\.rawValue), ["camera", "microphone", "geolocation"])

        let events = SitePermissionType.allCases.map {
            SitePermissionsEvent.permissionSystemPromptResult(type: $0, result: .granted)
        }

        XCTAssertEqual(events, [
            .permissionSystemPromptResult(type: .camera, result: .granted),
            .permissionSystemPromptResult(type: .microphone, result: .granted),
            .permissionSystemPromptResult(type: .location, result: .granted)
        ])
    }

    func testActionTokensMatchPixelDefinitionSuffixes() {
        XCTAssertEqual(SitePermissionsEvent.DialogSelection.allowOnce.rawValue, "allow_once")
        XCTAssertEqual(SitePermissionsEvent.DialogSelection.allowAlways.rawValue, "allow_always")
        XCTAssertEqual(SitePermissionsEvent.DialogSelection.never.rawValue, "never")
        XCTAssertEqual(SitePermissionsEvent.SystemPromptResult.granted.rawValue, "granted")
        XCTAssertEqual(SitePermissionsEvent.SystemPromptResult.denied.rawValue, "denied")
        XCTAssertEqual(SitePermissionsEvent.ReminderDialogAction.shown.rawValue, "shown")
        XCTAssertEqual(SitePermissionsEvent.ReminderDialogAction.settings.rawValue, "settings")
        XCTAssertEqual(SitePermissionsEvent.ReminderDialogAction.cancel.rawValue, "cancel")
        XCTAssertEqual(SitePermissionsEvent.VoiceSearchPermissionPromptAction.shown.rawValue, "shown")
        XCTAssertEqual(SitePermissionsEvent.VoiceSearchPermissionPromptAction.settings.rawValue, "settings")
        XCTAssertEqual(SitePermissionsEvent.VoiceSearchPermissionPromptAction.hide.rawValue, "hide")
        XCTAssertEqual(SitePermissionsEvent.VoiceSearchPermissionPromptAction.cancel.rawValue, "cancel")
    }
}
