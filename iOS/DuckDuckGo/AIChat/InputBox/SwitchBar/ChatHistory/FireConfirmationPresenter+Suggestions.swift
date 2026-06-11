//
//  FireConfirmationPresenter+Suggestions.swift
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

import AIChat
import Core
import UIKit

extension FireConfirmationPresenter {

    @MainActor
    static func presentFireConfirmation(suggestion: AIChatSuggestion, presenter: UIViewController, source: UIView, onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void) {
        let fireContext: ScopedFireConfirmationViewModel.FireContext = .custom(
            title: UserText.removeRecentChatConfirmationTitle,
            subtitle: String(format: UserText.removeRecentChatConfirmationMessage, suggestion.title),
            action: UserText.removeRecentChatConfirmationButton
        )

        let confirmationPresenter = FireConfirmationPresenter()
        confirmationPresenter.presentFireConfirmation(
            on: presenter,
            attachPopoverTo: source,
            tabViewModel: nil,
            pixelSource: .chatSuggestions,
            fireContext: fireContext,
            browsingMode: .normal,
            onConfirm: { _ in
                onConfirm()
            },
            onCancel: {
                onCancel()
            }
        )
    }
}
