//
//  NewAddressBarPickerModalPromptProvider.swift
//  DuckDuckGo
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

import UIKit
import AIChat

// Adapter between NewAddressBarPickerPrompt and PromptCoordination system
final class NewAddressBarPickerModalPromptProvider: ModalPromptProvider {
    private let validator: NewAddressBarPickerDisplayValidating
    private let store: NewAddressBarPickerStorageWriting
    private let aiChatSettings: AIChatSettingsProvider
    private let isIPad: Bool

    init(
        validator: NewAddressBarPickerDisplayValidating,
        store: NewAddressBarPickerStorage,
        aiChatSettings: AIChatSettingsProvider,
        isIPad: Bool
    ) {
        self.validator = validator
        self.store = store
        self.aiChatSettings = aiChatSettings
        self.isIPad = isIPad
    }

    func provideModalPrompt() -> ModalPromptConfiguration? {
        guard validator.shouldDisplayNewAddressBarPicker() else {
            Logger.modalPrompt.info("[Modal Prompt Coordination] - Address Bar Picker Does Not Need To Be Displayed.")
            return nil
        }

        let pickerViewController = NewAddressBarPickerViewController(aiChatSettings: aiChatSettings)

        // Configure presentation properties on the view controller
        if #available(iOS 26.0, *), isIPad {
            pickerViewController.modalPresentationStyle = .formSheet
        } else {
            pickerViewController.modalPresentationStyle = .pageSheet
        }
        pickerViewController.modalTransitionStyle = .coverVertical
        pickerViewController.isModalInPresentation = true

        return ModalPromptConfiguration(
            viewController: pickerViewController,
            animated: true
        )
    }
    
    func didPresentModal() {
        Logger.modalPrompt.info("[Modal Prompt Coordination] - New Address Bar Picker Did Present Prompt")
        store.markAsShown()
    }
    
}
