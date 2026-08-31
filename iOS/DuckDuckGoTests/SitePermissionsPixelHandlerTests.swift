//
//  SitePermissionsPixelHandlerTests.swift
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

@_spi(Testing) import PixelKit
import SitePermissions
import SwiftUI
import UIKit
import XCTest

@testable import DuckDuckGo

final class SitePermissionsPixelHandlerTests: XCTestCase {

    @MainActor
    func testVoiceSearchPermissionPromptUsesUnchangedLegacyAlertWhenRedesignIsDisabled() throws {
        let viewController = NoMicPermissionAlert.build(isRedesigned: false) { _ in
            XCTFail("The legacy alert must not use redesigned actions")
        }
        let alertController = try XCTUnwrap(viewController as? UIAlertController)

        XCTAssertEqual(alertController.title, UserText.noVoicePermissionAlertTitle)
        XCTAssertEqual(alertController.message, UserText.noVoicePermissionAlertMessage)
        XCTAssertEqual(alertController.preferredStyle, .alert)
        XCTAssertEqual(alertController.actions.map(\.title), [UserText.noVoicePermissionActionSettings, UserText.actionCancel])
        XCTAssertEqual(alertController.actions.map(\.style), [.default, .cancel])
    }

    @MainActor
    func testVoiceSearchPermissionPromptUsesRedesignedReminderWhenEnabled() {
        let viewController = NoMicPermissionAlert.build(isRedesigned: true) { _ in }

        XCTAssertTrue(viewController is UIHostingController<PermissionReminderDialogView>)
        XCTAssertEqual(viewController.modalPresentationStyle, .overFullScreen)
        XCTAssertEqual(viewController.modalTransitionStyle, .crossDissolve)
        XCTAssertTrue(viewController.view.accessibilityViewIsModal)
    }

    @MainActor
    func testVoiceSearchPermissionPromptShownEmitsShownEvent() {
        let eventRecorder = EventRecorder()
        let handler = makeVoiceSearchActionHandler(eventRecorder: eventRecorder)

        handler.didShow()

        XCTAssertEqual(eventRecorder.events, [.voiceSearchPermissionPrompt(action: .shown)])
    }

    @MainActor
    func testVoiceSearchPermissionPromptSettingsEmitsEventsAndOpensSettingsAfterDismissal() {
        let eventRecorder = EventRecorder()
        var actions = [String]()
        let handler = makeVoiceSearchActionHandler(eventRecorder: eventRecorder,
                                                   onDismiss: { completion in
                                                       actions.append("dismiss")
                                                       completion?()
                                                   },
                                                   onOpenSystemSettings: { actions.append("openSettings") })

        handler.handle(.changePermissions)

        XCTAssertEqual(eventRecorder.events, [
            .voiceSearchPermissionPrompt(action: .settings),
            .permissionSystemSettingsOpened(type: .microphone)
        ])
        XCTAssertEqual(actions, ["dismiss", "openSettings"])
    }

    @MainActor
    func testVoiceSearchPermissionPromptHideEmitsEventDisablesVoiceSearchAndDismisses() {
        let eventRecorder = EventRecorder()
        var actions = [String]()
        let handler = makeVoiceSearchActionHandler(eventRecorder: eventRecorder,
                                                   onDisableVoiceSearch: { actions.append("disableVoiceSearch") },
                                                   onDismiss: { _ in actions.append("dismiss") })

        handler.handle(.hideVoiceSearch)

        XCTAssertEqual(eventRecorder.events, [.voiceSearchPermissionPrompt(action: .hide)])
        XCTAssertEqual(actions, ["disableVoiceSearch", "dismiss"])
    }

    @MainActor
    func testVoiceSearchPermissionPromptCancelEmitsEventAndDismisses() {
        let eventRecorder = EventRecorder()
        var didDismiss = false
        let handler = makeVoiceSearchActionHandler(eventRecorder: eventRecorder,
                                                   onDismiss: { _ in didDismiss = true })

        handler.handle(.cancel)

        XCTAssertEqual(eventRecorder.events, [.voiceSearchPermissionPrompt(action: .cancel)])
        XCTAssertTrue(didDismiss)
    }

    func testEventsMapToExactPixelNames() throws {
        let cases: [(SitePermissionsEvent, String)] = [
            (.permissionDialogImpression(type: .camera), "permission_dialog_impression_camera"),
            (.permissionDialogImpression(type: .cameraAndMicrophone), "permission_dialog_impression_camera_and_microphone"),
            (.permissionDialogClick(type: .microphone, selection: .allowOnce), "permission_dialog_click_microphone_allow_once"),
            (.permissionDialogClick(type: .cameraAndMicrophone, selection: .allowAlways), "permission_dialog_click_camera_and_microphone_allow_always"),
            (.permissionDialogClick(type: .geolocation, selection: .never), "permission_dialog_click_geolocation_never"),
            (.permissionSystemPromptResult(type: .camera, result: .granted), "permission_system_prompt_result_camera_granted"),
            (.permissionSystemPromptResult(type: .microphone, result: .denied), "permission_system_prompt_result_microphone_denied"),
            (.permissionSystemPromptResult(type: .location, result: .granted), "permission_system_prompt_result_geolocation_granted"),
            (.permissionReminderDialog(type: .cameraAndMicrophone, action: .shown), "permission_reminder_dialog_camera_and_microphone_shown"),
            (.permissionReminderDialog(type: .geolocation, action: .settings), "permission_reminder_dialog_geolocation_settings"),
            (.permissionReminderDialog(type: .camera, action: .cancel), "permission_reminder_dialog_camera_cancel"),
            (.permissionSystemSettingsOpened(type: .cameraAndMicrophone), "permission_system_settings_opened_camera_and_microphone"),
            (.voiceSearchPermissionPrompt(action: .shown), "voice_search_permission_prompt_shown"),
            (.voiceSearchPermissionPrompt(action: .settings), "voice_search_permission_prompt_settings"),
            (.voiceSearchPermissionPrompt(action: .hide), "voice_search_permission_prompt_hide"),
            (.voiceSearchPermissionPrompt(action: .cancel), "voice_search_permission_prompt_cancel")
        ]

        for (event, expectedName) in cases {
            let fireCall = try fire(event)

            XCTAssertEqual(fireCall.pixel.name, expectedName)
        }
    }

    func testMappedPixelUsesStandardFrequencyAndWirePolicies() throws {
        let fireCall = try fire(.permissionDialogImpression(type: .cameraAndMicrophone))

        XCTAssertEqual(fireCall.frequency, .standard)
        XCTAssertEqual(fireCall.pixel.namePrefix, .none)
        XCTAssertEqual(fireCall.pixel.platformSuffixPolicy, .standard)
        XCTAssertNil(fireCall.pixel.parameters)
        XCTAssertNil(fireCall.pixel.standardParameters)
        XCTAssertNil(fireCall.additionalParameters)
        XCTAssertTrue(fireCall.includeAppVersionParameter)
    }

    private func fire(_ event: SitePermissionsEvent,
                      file: StaticString = #file,
                      line: UInt = #line) throws -> ExpectedFireCall {
        let pixelFiring = PixelKitMock()
        let handler = SitePermissionsPixelHandler(pixelFiring: pixelFiring)

        handler.fire(event)

        XCTAssertEqual(pixelFiring.actualFireCalls.count, 1, file: file, line: line)
        return try XCTUnwrap(pixelFiring.actualFireCalls.first, file: file, line: line)
    }

    @MainActor
    private func makeVoiceSearchActionHandler(eventRecorder: EventRecorder,
                                              onDisableVoiceSearch: @escaping () -> Void = {},
                                              onDismiss: @escaping VoiceSearchPermissionPromptActionHandler.DismissHandler = { _ in },
                                              onOpenSystemSettings: @escaping () -> Void = {}) -> VoiceSearchPermissionPromptActionHandler {
        VoiceSearchPermissionPromptActionHandler(
            eventHandler: { eventRecorder.events.append($0) },
            disableVoiceSearch: onDisableVoiceSearch,
            dismiss: onDismiss,
            openSystemSettings: onOpenSystemSettings)
    }
}

private final class EventRecorder {
    var events = [SitePermissionsEvent]()
}
