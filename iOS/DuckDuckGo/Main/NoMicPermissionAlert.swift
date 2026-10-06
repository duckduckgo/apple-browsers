//
//  NoMicPermissionAlert.swift
//  DuckDuckGo
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import AVFoundation
import Foundation
import SitePermissions
import SwiftUI
import UIKit

@MainActor
struct NoMicPermissionAlert {

    static func build(isRedesigned: Bool,
                      onAction: @escaping (PermissionReminderDialogAction) -> Void) -> UIViewController {
        isRedesigned ? buildReminder(onAction: onAction) : buildAlert()
    }
    
    static func buildAlert() -> UIAlertController {
        let alertController = UIAlertController(title: UserText.noVoicePermissionAlertTitle,
                                                message: UserText.noVoicePermissionAlertMessage,
                                                preferredStyle: .alert)

        let openSettingsButton = UIAlertAction(title: UserText.noVoicePermissionActionSettings, style: .default) { _ in
            let url = URL(string: UIApplication.openSettingsURLString)!
            UIApplication.shared.open(url)
        }
        let cancelAction = UIAlertAction(title: UserText.actionCancel, style: .cancel, handler: nil)

        alertController.addAction(openSettingsButton)
        alertController.addAction(cancelAction)
        return alertController
    }

    static func buildVoiceChatReminderIfNeeded(isSitePermissionsEnabled: Bool,
                                               microphoneAuthorization: AVAuthorizationStatus,
                                               onAction: @escaping (PermissionReminderDialogAction) -> Void) -> UIViewController? {
        guard isSitePermissionsEnabled,
              microphoneAuthorization == .denied || microphoneAuthorization == .restricted else { return nil }
        return buildReminder(viewModel: .voiceChat, onAction: onAction)
    }

    static func buildReminder(viewModel: PermissionReminderDialogViewModel = .voiceSearch,
                              onAction: @escaping (PermissionReminderDialogAction) -> Void) -> UIViewController {
        let reminder = PermissionReminderDialogView(viewModel: viewModel, onAction: onAction)
        let hostingController = UIHostingController(rootView: reminder)
        hostingController.modalPresentationStyle = .overFullScreen
        hostingController.modalTransitionStyle = .crossDissolve
        hostingController.view.backgroundColor = .clear
        hostingController.view.accessibilityViewIsModal = true
        return hostingController
    }
}

@MainActor
struct VoiceSearchPermissionPromptActionHandler {

    typealias DismissHandler = (_ completion: (() -> Void)?) -> Void

    private let eventHandler: (SitePermissionsEvent) -> Void
    private let disableVoiceSearch: () -> Void
    private let dismiss: DismissHandler
    private let openSystemSettings: () -> Void

    init(eventHandler: @escaping (SitePermissionsEvent) -> Void,
         disableVoiceSearch: @escaping () -> Void,
         dismiss: @escaping DismissHandler,
         openSystemSettings: @escaping () -> Void) {
        self.eventHandler = eventHandler
        self.disableVoiceSearch = disableVoiceSearch
        self.dismiss = dismiss
        self.openSystemSettings = openSystemSettings
    }

    func didShow() {
        eventHandler(.voiceSearchPermissionPrompt(action: .shown))
    }

    func handle(_ action: PermissionReminderDialogAction) {
        switch action {
        case .changePermissions:
            eventHandler(.voiceSearchPermissionPrompt(action: .settings))
            eventHandler(.permissionSystemSettingsOpened(type: .microphone))
            dismiss(openSystemSettings)
        case .hideVoiceSearch:
            eventHandler(.voiceSearchPermissionPrompt(action: .hide))
            disableVoiceSearch()
            dismiss(nil)
        case .cancel:
            eventHandler(.voiceSearchPermissionPrompt(action: .cancel))
            dismiss(nil)
        }
    }
}
