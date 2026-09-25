//
//  NewPermissionAuthorizationViewState.swift
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

struct NewPermissionAuthorizationViewState: Equatable {
    var title = ""
    var learnMore: LearnMore?
    var closeButtonAccessibilityIdentifier = "NewPermissionAuthorizationSwiftUIView.closeButton"
    var decisionButtons: [DecisionButton] = [
        DecisionButton(
            action: .allowThisVisit,
            title: UserText.websitePermissionsPromptAllowThisVisit,
            accessibilityIdentifier: "NewPermissionAuthorizationSwiftUIView.allowThisVisitButton"
        ),
        DecisionButton(
            action: .alwaysAllow,
            title: UserText.permissionCenterAlwaysAllow,
            accessibilityIdentifier: "NewPermissionAuthorizationSwiftUIView.alwaysAllowButton"
        ),
        DecisionButton(
            action: .neverAllow,
            title: UserText.permissionCenterNeverAllow,
            accessibilityIdentifier: "NewPermissionAuthorizationSwiftUIView.neverAllowButton"
        ),
    ]
}

extension NewPermissionAuthorizationViewState {
    struct LearnMore: Equatable {
        let title: String
        let url: URL
    }

    struct DecisionButton: Identifiable, Equatable {
        let action: NewPermissionAuthorizationViewModel.Action
        let title: String
        let accessibilityIdentifier: String

        var id: String { accessibilityIdentifier }
    }
}
