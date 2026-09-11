//
//  PermissionTypeTests.swift
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
@testable import DuckDuckGo_Privacy_Browser

final class PermissionTypeTests: XCTestCase {
    func testWhenNativeVoiceFlowIsEnabledThenDuckAiMicrophoneIsNotEditable() {
        XCTAssertFalse(PermissionType.microphone.isUserEditable(forDomain: "duck.ai", nativeVoiceFlowEnabled: true))
    }

    func testWhenNativeVoiceFlowIsDisabledThenDuckAiMicrophoneIsEditable() {
        XCTAssertTrue(PermissionType.microphone.isUserEditable(forDomain: "duck.ai", nativeVoiceFlowEnabled: false))
    }

    func testWhenDomainIsNotDuckAiThenMicrophoneIsEditableRegardlessOfNativeVoiceFlow() {
        for nativeVoiceFlowEnabled in [true, false] {
            XCTAssertTrue(PermissionType.microphone.isUserEditable(forDomain: "example.com", nativeVoiceFlowEnabled: nativeVoiceFlowEnabled))
        }
    }

    func testWhenPermissionIsNotMicrophoneThenItIsEditableOnDuckAiRegardlessOfNativeVoiceFlow() {
        let permissionTypes: [PermissionType] = [.camera, .geolocation, .popups, .notification, .externalScheme(scheme: "mailto"), .autoplayPolicy]

        for nativeVoiceFlowEnabled in [true, false] {
            for permissionType in permissionTypes {
                XCTAssertTrue(permissionType.isUserEditable(forDomain: "duck.ai", nativeVoiceFlowEnabled: nativeVoiceFlowEnabled),
                              "Expected \(permissionType) to be editable with native voice flow enabled: \(nativeVoiceFlowEnabled)")
            }
        }
    }
}
