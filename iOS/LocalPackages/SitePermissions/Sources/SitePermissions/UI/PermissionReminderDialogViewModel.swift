//
//  PermissionReminderDialogViewModel.swift
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

import Foundation

public enum PermissionReminderDialogAction: Hashable, Sendable {
    case changePermissions
    case hideVoiceSearch
    case cancel
}

public struct PermissionReminderDialogViewModel: Equatable, Sendable {

    public struct ActionItem: Equatable, Identifiable, Sendable {
        public enum Style: Equatable, Sendable {
            case primary
            case secondary
        }

        public let action: PermissionReminderDialogAction
        public let title: String
        public let style: Style
        public var id: PermissionReminderDialogAction { action }

        fileprivate init(action: PermissionReminderDialogAction, title: String, style: Style) {
            self.action = action
            self.title = title
            self.style = style
        }
    }

    public let title: String
    public let body: String
    public let actions: [ActionItem]

    public init?(sitePermissionTypes: Set<SitePermissionType>) {
        switch sitePermissionTypes {
        case [.camera]:
            title = UserText.PermissionRecovery.cameraTitle
            body = UserText.PermissionRecovery.cameraBody
        case [.microphone]:
            title = UserText.PermissionRecovery.microphoneTitle
            body = UserText.PermissionRecovery.microphoneBody
        case [.location]:
            title = UserText.PermissionRecovery.locationTitle
            body = UserText.PermissionRecovery.locationBody
        case [.camera, .microphone]:
            title = UserText.PermissionRecovery.cameraAndMicrophoneTitle
            body = UserText.PermissionRecovery.cameraAndMicrophoneBody
        default:
            return nil
        }

        actions = Self.settingsActions
    }

    public static var voiceSearch: PermissionReminderDialogViewModel {
        PermissionReminderDialogViewModel(
            title: UserText.VoiceSearchPermissionRecovery.title,
            body: UserText.VoiceSearchPermissionRecovery.body,
            actions: [
                ActionItem(action: .changePermissions,
                           title: UserText.PermissionRecovery.changePermissions,
                           style: .primary),
                ActionItem(action: .hideVoiceSearch,
                           title: UserText.VoiceSearchPermissionRecovery.hideVoiceSearch,
                           style: .secondary),
                ActionItem(action: .cancel,
                           title: UserText.PermissionRecovery.cancel,
                           style: .secondary)
            ]
        )
    }

    public static var voiceChat: PermissionReminderDialogViewModel {
        PermissionReminderDialogViewModel(
            title: UserText.PermissionRecovery.microphoneTitle,
            body: UserText.VoiceChatPermissionRecovery.body,
            actions: settingsActions
        )
    }

    private static let settingsActions = [
        ActionItem(action: .changePermissions,
                   title: UserText.PermissionRecovery.changePermissions,
                   style: .primary),
        ActionItem(action: .cancel,
                   title: UserText.PermissionRecovery.cancel,
                   style: .secondary)
    ]

    public static func sitePermissionToastMessage(for permissionTypes: Set<SitePermissionType>) -> String? {
        switch permissionTypes {
        case [.camera]:
            return UserText.PermissionRecovery.cameraToast
        case [.microphone]:
            return UserText.PermissionRecovery.microphoneToast
        case [.location]:
            return UserText.PermissionRecovery.locationToast
        case [.camera, .microphone]:
            return UserText.PermissionRecovery.cameraAndMicrophoneToast
        default:
            return nil
        }
    }

    private init(title: String, body: String, actions: [ActionItem]) {
        self.title = title
        self.body = body
        self.actions = actions
    }

}
