//
//  AIChatTranslator.swift
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

import Foundation

import AIChat
import BrowserServicesKit
import PixelKit

/// This struct represents an object that's consumed by `AIChatTranslating` protocol and used to perform text translation.
struct AIChatTextTranslationRequest: Equatable {
    /// The text to be translated
    let text: String

    /// The URL of the website where the text for translation was selected
    let websiteURL: URL?

    /// The title of the website where the text for translation was selected
    let websiteTitle: String?

    /// The eTLD of the website's URL where the text for translation was selected
    let websiteTLD: String?

    /// Source language of the selected text based on element or document `lang` attribute
    let sourceLanguage: String?
}

/// This protocol describes APIs for translation in AI Chat.
@MainActor
protocol AIChatTranslating {

    /// Handle text translation.
    func translate(_ request: AIChatTextTranslationRequest)
}

final class AIChatTranslator: AIChatTranslating {

    private let aiChatMenuConfig: AIChatMenuVisibilityConfigurable
    private let aiChatSidebarPresenter: AIChatSidebarPresenting
    private let aiChatTabOpener: AIChatTabOpening
    private let pixelFiring: PixelFiring?

    init(
        aiChatMenuConfig: AIChatMenuVisibilityConfigurable,
        aiChatSidebarPresenter: AIChatSidebarPresenting,
        aiChatTabOpener: AIChatTabOpening,
        pixelFiring: PixelFiring?
    ) {
        self.aiChatMenuConfig = aiChatMenuConfig
        self.aiChatSidebarPresenter = aiChatSidebarPresenter
        self.aiChatTabOpener = aiChatTabOpener
        self.pixelFiring = pixelFiring
    }

    /// This function performs text translation for the provided `request`.
    ///
    /// Depending on AI Chat sidebar feature availability and on the sidebar settings,
    /// translation will happen either in a tab sidebar or in a new tab.
    @MainActor
    func translate(_ request: AIChatTextTranslationRequest) {
        guard aiChatMenuConfig.shouldDisplayTranslationMenuItem else {
            return
        }

        let prompt = AIChatNativePrompt.translationPrompt(request.text,
                                                          url: request.websiteURL,
                                                          title: request.websiteTitle,
                                                          sourceTLD: request.websiteTLD,
                                                          sourceLanguage: request.sourceLanguage,
                                                          targetLanguage: targetTranslationLanguage())
        pixelFiring?.fire(AIChatPixel.aiChatTranslateText, frequency: .dailyAndStandard)

        if aiChatMenuConfig.shouldOpenAIChatInSidebar {
            if !aiChatSidebarPresenter.isSidebarOpenForCurrentTab() {
                pixelFiring?.fire(AIChatPixel.aiChatSidebarOpened(source: .translation), frequency: .dailyAndStandard)
            }
            aiChatSidebarPresenter.presentSidebar(for: prompt)
        } else {
            AIChatPromptHandler.shared.setData(prompt)
            aiChatTabOpener.openAIChatTab(nil, with: .newTab(selected: true))
        }
    }

    /// Return target translation language as BCP 47 code
    private func targetTranslationLanguage() -> String {
        appPreferredLanguage() ?? systemLanguage()
    }

    private let appPreferredLanguage = { Locale.preferredLanguages.first }
    private let systemLanguage = { Locale.current.identifier.replacingOccurrences(of: "_", with: "-") }
}
