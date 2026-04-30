//
//  NewAddressBarPickerViewModel.swift
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

import Combine
import AIChat
import Core

final class NewAddressBarPickerViewModel: ObservableObject {
    @Published var isDuckAISelected: Bool

    private let aiChatSettings: AIChatSettingsProvider
    private let dailyPixelFiring: DailyPixelFiring.Type
    private let onDismiss: () -> Void

    init(
        aiChatSettings: AIChatSettingsProvider,
        dailyPixelFiring: DailyPixelFiring.Type = DailyPixel.self,
        onDismiss: @escaping () -> Void
    ) {
        self.aiChatSettings = aiChatSettings
        self.dailyPixelFiring = dailyPixelFiring
        self.onDismiss = onDismiss
        self.isDuckAISelected = true
    }

    func confirm() {
        aiChatSettings.enableAIChatSearchInputUserSettings(enable: isDuckAISelected)
        fireConfirmPixel()
        onDismiss()
    }
}

private extension NewAddressBarPickerViewModel {

    func fireConfirmPixel() {
        let selectionValue = isDuckAISelected ? "search_and_ai" : "search_only"
        dailyPixelFiring.fireDailyAndCount(
            .aiChatNewAddressBarPickerConfirmed,
            error: nil,
            withAdditionalParameters: [PixelParameters.selection: selectionValue]
        )
    }
}
