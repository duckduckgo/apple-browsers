//
//  SitePermissionDialogViewModel.swift
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

public enum SitePermissionDialogAction: Hashable, Sendable {
    case allowOnce
    case allowWhileUsingSite
    case neverAllow

    public var promptDecision: SitePermissionPromptDecision {
        switch self {
        case .allowOnce:
            return .allowOnce
        case .allowWhileUsingSite:
            return .allowWhileUsingSite
        case .neverAllow:
            return .neverAllow
        }
    }

    public var pixelDialogSelection: SitePermissionsEvent.DialogSelection {
        switch self {
        case .allowOnce:
            return .allowOnce
        case .allowWhileUsingSite:
            return .allowAlways
        case .neverAllow:
            return .never
        }
    }
}

public struct SitePermissionDialogViewModel: Equatable, Sendable {

    public struct ActionItem: Equatable, Identifiable, Sendable {
        public let action: SitePermissionDialogAction
        public let title: String
        public var id: SitePermissionDialogAction { action }

        fileprivate init(action: SitePermissionDialogAction, title: String) {
            self.action = action
            self.title = title
        }
    }

    enum Icon: Equatable, Sendable {
        case camera
        case microphone
        case location
        case duckDuckGo
    }

    public var title: String { title(domain: domain) }
    public let body: String?
    public let actions: [ActionItem]

    let domain: String
    let permissionTypes: Set<SitePermissionType>
    let icon: Icon?
    let isDuckDuckGoSERP: Bool

    public init?(prompt: SitePermissionPrompt, isDuckDuckGoSERP: Bool = false) {
        domain = prompt.site.host
        permissionTypes = prompt.permissionTypes
        self.isDuckDuckGoSERP = isDuckDuckGoSERP && prompt.permissionTypes == [.location]
        switch prompt.permissionTypes {
        case [.camera]:
            icon = .camera
        case [.microphone]:
            icon = .microphone
        case [.camera, .microphone]:
            icon = nil
        case [.location]:
            icon = self.isDuckDuckGoSERP ? .duckDuckGo : .location
        default:
            return nil
        }

        body = self.isDuckDuckGoSERP ? UserText.PermissionDialog.duckDuckGoSERPLocationBody : nil
        actions = [
            ActionItem(action: .allowOnce, title: UserText.PermissionDialog.allowOnce),
            ActionItem(action: .allowWhileUsingSite, title: UserText.PermissionDialog.allowWhileUsingSite),
            ActionItem(action: .neverAllow, title: UserText.PermissionDialog.neverAllow)
        ]
    }

    func title(domain: String) -> String {
        switch permissionTypes {
        case [.camera]:
            return UserText.PermissionDialog.cameraTitle(domain: domain)
        case [.microphone]:
            return UserText.PermissionDialog.microphoneTitle(domain: domain)
        case [.camera, .microphone]:
            return UserText.PermissionDialog.cameraAndMicrophoneTitle(domain: domain)
        case [.location] where isDuckDuckGoSERP:
            return UserText.PermissionDialog.duckDuckGoSERPLocationTitle
        case [.location]:
            return UserText.PermissionDialog.locationTitle(domain: domain)
        default:
            assertionFailure("Unsupported permission dialog variant")
            return ""
        }
    }

}
