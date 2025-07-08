//
//  AIChatSummarizer.swift
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

import AIChat
import BrowserServicesKit
import Foundation
import PixelKit

/// This struct represents an object that's consumed by `AIChatSummarizing` protocol and used to perform text summarization.
struct AIChatTextSummarizationRequest: Equatable {
    /// The text to be summarized
    let text: String

    /// The URL of the website where the summarized text was selected
    let websiteURL: URL?

    /// The title of the website where the summarized text was selected
    let websiteTitle: String?

    /// The source of the summarize action
    let source: Source

    enum Source: String {
        case contextMenu = "context-menu", keyboardShortcut = "keyboard-shortcut"
    }
}

/// This protocol describes APIs for summarization in AI Chat.
@MainActor
protocol AIChatSummarizing {

    /// Handle text summarization.
    func summarize(_ request: AIChatTextSummarizationRequest)
}

final class AIChatSummarizer: AIChatSummarizing {

    private let aiChatMenuConfig: AIChatMenuVisibilityConfigurable
    private let aiChatSidebarPresenter: AIChatSidebarPresenting
    private let aiChatTabOpener: AIChatTabOpening
    private let featureFlagger: FeatureFlagger
    private let pixelFiring: PixelFiring?

    init(
        aiChatMenuConfig: AIChatMenuVisibilityConfigurable = AIChatMenuConfiguration(),
        aiChatSidebarPresenter: AIChatSidebarPresenting,
        aiChatTabOpener: AIChatTabOpening,
        featureFlagger: FeatureFlagger,
        pixelFiring: PixelFiring?
    ) {
        self.aiChatMenuConfig = aiChatMenuConfig
        self.aiChatSidebarPresenter = aiChatSidebarPresenter
        self.aiChatTabOpener = aiChatTabOpener
        self.featureFlagger = featureFlagger
        self.pixelFiring = pixelFiring
    }

    /// This function performs text summarization for the provided `request`.
    ///
    /// Depending on AI Chat sidebar feature availability and on the sidebar settings,
    /// summarization will happen either in a tab sidebar or in a new tab.
    @MainActor
    func summarize(_ request: AIChatTextSummarizationRequest) {
        guard featureFlagger.isFeatureOn(.aiChatTextSummarization) else {
            return
        }

        let promptText = """
            You are an expert summarizer AI. Your purpose is to read the provided text and generate a concise, accurate, and easy-to-understand summary. Summarize the following text in a neutral, encyclopedic tone. The summary should be a single paragraph and should not exceed 50 words. Use the same language as the original text.
            <text>
            \(request.text)
            </text>
            """

        let prompt = AIChatNativePrompt.queryPrompt(promptText, autoSubmit: true)
        pixelFiring?.fire(AIChatPixel.aiChatSummarizeText(source: request.source), frequency: .dailyAndStandard)

        if featureFlagger.isFeatureOn(.aiChatSidebar) && aiChatMenuConfig.openAIChatInSidebar {
            aiChatSidebarPresenter.presentSidebar(for: prompt)
        } else {
            AIChatPromptHandler.shared.setData(prompt)
            aiChatTabOpener.openAIChatTab(nil, with: .newTab(selected: true))
        }
    }
}
