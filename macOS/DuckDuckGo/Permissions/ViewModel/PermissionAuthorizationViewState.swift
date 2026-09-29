//
//  PermissionAuthorizationViewState.swift
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

struct PermissionAuthorizationViewState: Equatable {
    var title = ""
    var learnMore: LearnMore?
    /// Shown instead of the decision buttons after an allow choice, while macOS hasn't granted its own permission.
    var systemPermissionStep: SystemPermissionStep?
    var closeButtonAccessibilityIdentifier = "PermissionAuthorizationView.closeButton"
    var decisionButtons: [DecisionButton] = [
        DecisionButton(
            action: .allowThisVisit,
            title: UserText.websitePermissionsPromptAllowThisVisit,
            accessibilityIdentifier: "PermissionAuthorizationView.allowThisVisitButton"
        ),
        DecisionButton(
            action: .alwaysAllow,
            title: UserText.permissionCenterAlwaysAllow,
            accessibilityIdentifier: "PermissionAuthorizationView.alwaysAllowButton"
        ),
        DecisionButton(
            action: .neverAllow,
            title: UserText.permissionCenterNeverAllow,
            accessibilityIdentifier: "PermissionAuthorizationView.neverAllowButton"
        ),
    ]
}

extension PermissionAuthorizationViewState {
    struct LearnMore: Equatable {
        let title: String
        let url: URL
    }

    struct DecisionButton: Identifiable, Equatable {
        let action: PermissionAuthorizationViewModel.Action
        let title: String
        let accessibilityIdentifier: String

        var id: String { accessibilityIdentifier }
    }

    struct SystemPermissionStep: Equatable {
        enum Phase: Equatable {
            /// macOS hasn't asked yet: the button shows the macOS prompt.
            case request
            /// The macOS prompt is open: the button is disabled.
            case waiting
            /// macOS denied, the prompt timed out, or the permission is off system-wide: the button opens System Settings.
            case openSettings
        }

        let phase: Phase
        let message: String
        let buttonTitle: String
        let buttonAccessibilityIdentifier = "PermissionAuthorizationView.systemPermissionButton"

        /// `nil` while waiting, which disables the button.
        var buttonAction: PermissionAuthorizationViewModel.Action? {
            switch phase {
            case .request:
                return .requestSystemPermission
            case .waiting:
                return nil
            case .openSettings:
                return .openSystemSettings
            }
        }
    }
}
