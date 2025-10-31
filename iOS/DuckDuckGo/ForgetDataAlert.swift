//
//  ForgetDataAlert.swift
//  DuckDuckGo
//
//  Copyright © 2019 DuckDuckGo. All rights reserved.
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

import UIKit
import SwiftUI
import Core

class ForgetDataAlert {
    
    static func buildAlert(cancelHandler: (() -> Void)? = nil, forgetTabsAndDataHandler: @escaping () -> Void) -> UIAlertController {
        
        let alert = UIAlertController(title: additionalDescription, message: nil, preferredStyle: .actionSheet)

        let title = forgetAllActionTitle()
        let forgetTabsAndDataAction = UIAlertAction(title: title, style: .destructive) { _ in
            forgetTabsAndDataHandler()
        }

        forgetTabsAndDataAction.accessibilityIdentifier = confirmAccessibilityIdentifier

        let cancelAction = UIAlertAction(title: UserText.actionCancel, style: .cancel) { _ in
            cancelHandler?()
        }

        cancelAction.accessibilityIdentifier = cancelAccessibilityIdentifier

        alert.addAction(forgetTabsAndDataAction)
        alert.addAction(cancelAction)

        return alert
    }

    private static var additionalDescription: String? {
        ongoingDownloadsInProgress() ? UserText.fireButtonInterruptingDownloadsAlertDescription : nil
    }

    private static var confirmAccessibilityIdentifier: String {
        "alert.forget-data.confirm"
    }

    private static var cancelAccessibilityIdentifier: String {
        "alert.forget-data.cancel"
    }
    
    static private func forgetAllActionTitle() -> String {
        let appSettings = AppDependencyProvider.shared.appSettings
        let shouldIncludeAIChat = appSettings.autoClearAIChatHistory
        
        return shouldIncludeAIChat ? UserText.actionForgetAllWithAIChat : UserText.actionForgetAll
    }

    static private func ongoingDownloadsInProgress() -> Bool {
        let allDownloads = AppDependencyProvider.shared.downloadManager.downloadList
        let ongoingDownloads = allDownloads.filter { $0.isRunning && !$0.temporary }
        return !ongoingDownloads.isEmpty
    }

    fileprivate struct ConfirmationModifier: ViewModifier {
        @Binding var isPresented: Bool

        let onConfirm: () -> Void
        let onCancel: (() -> Void)?

        func body(content: Content) -> some View {
            let additionalDescription = ForgetDataAlert.additionalDescription
            let titleVisibility = additionalDescription == nil ? Visibility.hidden : .visible
            content
                .confirmationDialog(
                    ForgetDataAlert.additionalDescription ?? "",
                    isPresented: $isPresented,
                    titleVisibility: titleVisibility
                ) {
                    Button(forgetAllActionTitle(), role: .destructive) {
                        onConfirm()
                    }
                    .accessibilityIdentifier(ForgetDataAlert.confirmAccessibilityIdentifier)

                    Button(UserText.actionCancel, role: .cancel) {
                        onCancel?()
                    }
                    .accessibilityIdentifier(ForgetDataAlert.cancelAccessibilityIdentifier)
                }
        }
    }
}

extension View {
    func forgetDataConfirmationDialog(
        isPresented: Binding<Bool>,
        onConfirm: @escaping () -> Void,
        onCancel: (() -> Void)? = nil
    ) -> some View {
        modifier(ForgetDataAlert.ConfirmationModifier(isPresented: isPresented,
                                                      onConfirm: onConfirm,
                                                      onCancel: onCancel))
    }
}
