//
//  PermissionReminderDialogViewModelTests.swift
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

final class PermissionReminderDialogViewModelTests: XCTestCase {

    func testCameraSiteReminderUsesCameraCopyAndPrimarySettingsAction() throws {
        let viewModel = try XCTUnwrap(PermissionReminderDialogViewModel(sitePermissionTypes: [.camera]))

        XCTAssertEqual(viewModel.title, "DuckDuckGo needs to access your camera")
        XCTAssertEqual(viewModel.body, "Camera permissions are needed if you want to use camera features on this site.")
        XCTAssertEqual(viewModel.actions.map(\.action), [.changePermissions, .cancel])
        XCTAssertEqual(viewModel.actions.map(\.style), [.primary, .secondary])
    }

    func testMicrophoneSiteReminderUsesMicrophoneCopy() throws {
        let viewModel = try XCTUnwrap(PermissionReminderDialogViewModel(sitePermissionTypes: [.microphone]))

        XCTAssertEqual(viewModel.title, "DuckDuckGo needs to access your microphone")
        XCTAssertEqual(viewModel.body, "Microphone permissions are needed if you want to use microphone features on this site.")
    }

    func testCombinedSiteReminderUsesSingleCombinedSurface() throws {
        let viewModel = try XCTUnwrap(PermissionReminderDialogViewModel(sitePermissionTypes: [.camera, .microphone]))

        XCTAssertEqual(viewModel.title, "DuckDuckGo needs to access your camera and microphone")
        XCTAssertEqual(viewModel.body, "Camera and microphone permissions are needed if you want to use related features on this site.")
        XCTAssertEqual(viewModel.actions.map(\.action), [.changePermissions, .cancel])
    }

    func testLocationSiteReminderUsesLocationCopy() throws {
        let viewModel = try XCTUnwrap(PermissionReminderDialogViewModel(sitePermissionTypes: [.location]))

        XCTAssertEqual(viewModel.title, "DuckDuckGo needs to access your location")
        XCTAssertEqual(viewModel.body, "Location permissions are needed if you want to use location features on this site.")
        XCTAssertEqual(viewModel.actions.map(\.action), [.changePermissions, .cancel])
        XCTAssertEqual(viewModel.actions.map(\.style), [.secondary, .secondary])
    }

    func testVoiceSearchReminderUsesPrimarySettingsActionAndHideAction() {
        let viewModel = PermissionReminderDialogViewModel.voiceSearch

        XCTAssertEqual(viewModel.title, "DuckDuckGo needs to access your microphone")
        XCTAssertEqual(viewModel.body, "Microphone permissions are needed if you want to use our Private Voice Search.")
        XCTAssertEqual(viewModel.actions.map(\.action), [.changePermissions, .hideVoiceSearch, .cancel])
        XCTAssertEqual(viewModel.actions.map(\.style), [.primary, .secondary, .secondary])
    }

    func testVoiceChatReminderUsesDuckAICopyWithoutHideVoiceSearch() {
        let viewModel = PermissionReminderDialogViewModel.voiceChat

        XCTAssertEqual(viewModel.title, "DuckDuckGo needs to access your microphone")
        XCTAssertEqual(viewModel.body, "Microphone permissions are needed if you want to use Voice Chat in Duck.ai.")
        XCTAssertEqual(viewModel.actions.map(\.action), [.changePermissions, .cancel])
        XCTAssertEqual(viewModel.actions.map(\.style), [.primary, .secondary])
    }

    func testSitePermissionToastCopyCoversSingleAndCombinedFreshDenials() {
        XCTAssertEqual(PermissionReminderDialogViewModel.sitePermissionToastMessage(for: [.camera]),
                       "DuckDuckGo couldn’t give camera access to this site")
        XCTAssertEqual(PermissionReminderDialogViewModel.sitePermissionToastMessage(for: [.microphone]),
                       "DuckDuckGo couldn’t give microphone access to this site")
        XCTAssertEqual(PermissionReminderDialogViewModel.sitePermissionToastMessage(for: [.location]),
                       "DuckDuckGo couldn’t share location with this site")
        XCTAssertEqual(PermissionReminderDialogViewModel.sitePermissionToastMessage(for: [.camera, .microphone]),
                       "DuckDuckGo couldn’t give camera and microphone access to this site")
    }

    func testUnsupportedSitePermissionVariantsAreRejected() {
        XCTAssertNil(PermissionReminderDialogViewModel(sitePermissionTypes: []))
        XCTAssertNil(PermissionReminderDialogViewModel(sitePermissionTypes: [.camera, .location]))
        XCTAssertNil(PermissionReminderDialogViewModel.sitePermissionToastMessage(for: []))
    }

}
