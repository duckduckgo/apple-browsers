//
//  SitePermissionsEvent.swift
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

public enum SitePermissionsEvent: Equatable, Sendable {

    public enum PermissionType: String, Equatable, Sendable {
        case camera
        case microphone
        case cameraAndMicrophone = "camera_and_microphone"
        case geolocation

        public init?(_ permissionTypes: Set<SitePermissionType>) {
            switch permissionTypes {
            case [.camera]:
                self = .camera
            case [.microphone]:
                self = .microphone
            case [.camera, .microphone]:
                self = .cameraAndMicrophone
            case [.location]:
                self = .geolocation
            default:
                return nil
            }
        }
    }

    public enum DialogSelection: String, Equatable, Sendable {
        case allowOnce = "allow_once"
        case allowAlways = "allow_always"
        case never
    }

    public enum SystemPromptResult: String, Equatable, Sendable {
        case granted
        case denied
    }

    public enum ReminderDialogAction: String, Equatable, Sendable {
        case shown
        case settings
        case cancel
    }

    public enum VoiceSearchPermissionPromptAction: String, Equatable, Sendable {
        case shown
        case settings
        case hide
        case cancel
    }

    case permissionDialogImpression(type: PermissionType)
    case permissionDialogClick(type: PermissionType, selection: DialogSelection)
    case permissionSystemPromptResult(type: SitePermissionType, result: SystemPromptResult)
    case permissionReminderDialog(type: PermissionType, action: ReminderDialogAction)
    case permissionSystemSettingsOpened(type: PermissionType)
    case voiceSearchPermissionPrompt(action: VoiceSearchPermissionPromptAction)
    case permissionCenterOpened
    case permissionCenterChanged(type: SitePermissionType, from: SitePermissionDecision, to: SitePermissionDecision)
    case permissionCenterDismissedDirty
    case permissionRemoveSite
    case permissionRemoveAll
    case permissionRemoveUndo
    case settingsSitePermissionsOpen
    case settingsSitePermissionsGlobalChanged(type: SitePermissionType, to: GlobalSitePermissionDecision)
}
