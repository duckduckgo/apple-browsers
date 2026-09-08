//
//  SitePermissionDialogViewModelTests.swift
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

final class SitePermissionDialogViewModelTests: XCTestCase {

    func testCameraPromptUsesCameraCopyAndThreeEqualActionsInOrder() throws {
        let viewModel = try XCTUnwrap(SitePermissionDialogViewModel(prompt: prompt(for: [.camera])))

        XCTAssertEqual(viewModel.title, "“example.com” website wants to access your camera")
        XCTAssertNil(viewModel.body)
        XCTAssertEqual(viewModel.icon, .camera)
        XCTAssertEqual(viewModel.actions.map(\.action), [.allowOnce, .allowWhileUsingSite, .neverAllow])
        XCTAssertEqual(viewModel.actions.map(\.title), ["Allow Once", "Allow While Using Site", "Never Allow"])
    }

    func testMicrophonePromptUsesMicrophoneCopy() throws {
        let viewModel = try XCTUnwrap(SitePermissionDialogViewModel(prompt: prompt(for: [.microphone])))

        XCTAssertEqual(viewModel.title, "“example.com” website wants to access your microphone")
        XCTAssertNil(viewModel.body)
        XCTAssertEqual(viewModel.icon, .microphone)
    }

    func testCombinedPromptNamesBothPermissionsWithoutAnIcon() throws {
        let viewModel = try XCTUnwrap(SitePermissionDialogViewModel(prompt: prompt(for: [.camera, .microphone])))

        XCTAssertEqual(viewModel.title, "“example.com” website wants to access your camera and microphone")
        XCTAssertNil(viewModel.body)
        XCTAssertNil(viewModel.icon)
        XCTAssertEqual(viewModel.actions.map(\.action), [.allowOnce, .allowWhileUsingSite, .neverAllow])
    }

    func testUnsupportedPromptVariantsAreRejected() {
        XCTAssertNil(SitePermissionDialogViewModel(prompt: prompt(for: [])))
        XCTAssertNil(SitePermissionDialogViewModel(prompt: prompt(for: [.location])))
    }

    func testWhenDialogActionsAreSelectedThenDecisionsAndPixelSelectionsMatch() {
        let actions: [SitePermissionDialogAction] = [.allowOnce, .allowWhileUsingSite, .neverAllow]

        XCTAssertEqual(actions.map(\.promptDecision), [.allowOnce, .allowWhileUsingSite, .neverAllow])
        XCTAssertEqual(actions.map(\.pixelDialogSelection), [.allowOnce, .allowAlways, .never])
    }

    private func prompt(for permissionTypes: Set<SitePermissionType>) -> SitePermissionPrompt {
        SitePermissionPrompt(site: SitePermissionKey(committedURL: URL(string: "https://example.com")!)!,
                             permissionTypes: permissionTypes)
    }
}
