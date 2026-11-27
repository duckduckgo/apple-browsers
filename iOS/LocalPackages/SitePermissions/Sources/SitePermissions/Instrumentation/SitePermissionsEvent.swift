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

import Foundation

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
        case dismissed
    }

    /// Why a dialog the user saw went away without an answer.
    public enum DialogCloseReason: String, Equatable, Sendable {
        /// The main frame navigated to the URL it was already showing.
        case navigationReload = "navigation_reload"
        case navigationSameSite = "navigation_same_site"
        case navigationCrossSite = "navigation_cross_site"
        case processTerminated = "process_terminated"
        /// The tab was closed or unloaded from memory.
        case tabClosed = "tab_closed"
        case dataCleared = "data_cleared"
        /// The request was cancelled or replaced, for example after a permission change in another tab.
        case cancelled
    }

    /// How long a dialog was visible before it went away, in coarse buckets.
    public enum DialogVisibleDuration: String, Equatable, Sendable {
        case lessThanOneSecond = "lt_1s"
        case oneToFiveSeconds = "1_5s"
        case fiveToThirtySeconds = "5_30s"
        case moreThanThirtySeconds = "gt_30s"

        public init(seconds: TimeInterval) {
            switch seconds {
            case ..<1: self = .lessThanOneSecond
            case ..<5: self = .oneToFiveSeconds
            case ..<30: self = .fiveToThirtySeconds
            default: self = .moreThanThirtySeconds
            }
        }
    }

    public enum DialogFrame: String, Equatable, Sendable {
        case main
        case iframe
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
    case permissionDialogClosedWithoutChoice(type: PermissionType,
                                             reason: DialogCloseReason,
                                             visibleFor: DialogVisibleDuration,
                                             frame: DialogFrame)
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
