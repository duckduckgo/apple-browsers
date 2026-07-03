//
//  SystemDisabledPermissionInfoView.swift
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

import AppKit
import DesignResourcesKit
import PixelKit
import SwiftUI

/// Informational view shown when permission is blocked because system permission is disabled.
/// Matches the layout of `systemDisabledPermissionView` in `PermissionAuthorizationSwiftUIView`.
struct SystemDisabledPermissionInfoView: View {
    let domain: String
    let permissionType: PermissionType
    /// Selects the duck.ai mic-prompt copy (voice chat vs dictation). Only consulted for the
    /// `.microphone` + duck.ai branch; defaults to voice chat for all other callers.
    var micPromptSource: DuckAiMicPermissionSource = .voiceChat

    private var promptText: String {
        switch permissionType {
        case .notification:
            return String(format: UserText.notificationPermissionAuthorizationFormat, domain)
        case .geolocation:
            return String(format: UserText.locationPermissionAuthorizationFormat, domain)
        case .microphone:
            // On duck.ai the only mic uses are voice chat and dictation, so phrase the prompt
            // around the triggering flow rather than the generic "website would like to…" form.
            if domain == URL.duckAi.host {
                switch micPromptSource {
                case .voiceChat:
                    return UserText.duckAiVoiceChatMicrophonePrompt
                case .dictation:
                    return UserText.duckAiDictationMicrophonePrompt
                }
            }
            return String(format: UserText.microphonePermissionAuthorizationFormat, domain)
        default:
            return ""
        }
    }

    private var warningText: String {
        switch permissionType {
        case .notification:
            return UserText.permissionPopoverSystemNotificationDisabledStandalone
        case .geolocation:
            return UserText.permissionSystemLocationDisabled
        case .microphone:
            return UserText.permissionSystemMicrophoneDisabled
        default:
            return ""
        }
    }

    private var settingsLinkText: String {
        switch permissionType {
        case .notification:
            return UserText.permissionCenterSystemSettingsNotifications
        case .geolocation:
            return UserText.permissionSystemSettingsLocation
        case .microphone:
            return UserText.permissionSystemSettingsMicrophone
        default:
            return ""
        }
    }

    private var systemSettingsURL: URL? {
        switch permissionType {
        case .notification:
            return URL(string: "x-apple.systempreferences:com.apple.preference.notifications")
        case .geolocation:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        default:
            return nil
        }
    }

    /// Separator between warning text and link text
    private var linkSeparator: String {
        switch permissionType {
        case .notification:
            return "\n"
        case .geolocation, .microphone:
            return ""  // Strings already have a trailing space
        default:
            return " "
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            // Prompt text
            Text(promptText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // Warning + link
            warningWithLink
                .lineSpacing(6)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .cursor(.pointingHand)
                .onTapGesture {
                    openSystemSettings()
                }
        }
        .padding(16)
        .frame(width: 360)
        .background(Color(designSystemColor: .surfaceSecondary))
    }

    private var warningWithLink: some View {
        Text(warningText)
            .font(.system(size: 12))
            .foregroundColor(Color(designSystemColor: .textSecondary))
        + Text(linkSeparator)
        + Text(settingsLinkText)
            .font(.system(size: 12))
            .foregroundColor(Color(designSystemColor: .textLink))
    }

    private func openSystemSettings() {
        guard let url = systemSettingsURL else { return }
        PixelKit.fire(PermissionPixel.systemPreferencesOpened(permissionType: permissionType))
        NSWorkspace.shared.open(url)
    }
}
