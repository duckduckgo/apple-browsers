//
//  RecentChatDeletionAlert.swift
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

class RecentChatDeletionAlert {

    @MainActor
    static func show(for suggestion: AIChatSuggestion, presenter: UIViewController, confirmed: @escaping () -> Void) {
        let alert = UIAlertController(title: UserText.removeRecentChatConfirmationTitle,
                                      message: String(format: UserText.removeRecentChatConfirmationMessage, suggestion.title),
                                      preferredStyle: .alert)
        alert.addAction(title: UserText.actionCancel, style: .cancel) {
            // TODO: Wire Pixel
        }
        alert.addAction(title: UserText.removeRecentChatConfirmationButton, style: .destructive) {
            // TODO: Wire Pixel
            confirmed()
        }

        presenter.present(alert, animated: true)
    }
}
