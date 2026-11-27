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
import Common
import PixelKit
import WebKit

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

    /// The source of the translate action
    let source: AIChatSelectionActionSource
}

extension AIChatTextTranslationRequest {

    /// Builds a request for `text` selected in `webView`, reading the site's eTLD and the selection's language.
    @MainActor
    static func make(text: String, in webView: WKWebView?, tld: TLD, source: AIChatSelectionActionSource) async -> AIChatTextTranslationRequest {
        let websiteTLD: String? = {
            guard let sourceTLD = tld.eTLD(forStringURL: webView?.url?.absoluteString ?? "") else { return nil }
            return "." + sourceTLD
        }()

        let sourceLanguage: String? = await webView?.currentSelectionLanguage

        return AIChatTextTranslationRequest(text: text,
                                            websiteURL: webView?.url,
                                            websiteTitle: webView?.title,
                                            websiteTLD: websiteTLD,
                                            sourceLanguage: sourceLanguage,
                                            source: source)
    }
}

/// This protocol describes APIs for translation in AI Chat.
@MainActor
protocol AIChatTranslating {

    /// Handle text translation.
    func translate(_ request: AIChatTextTranslationRequest)

    /// Translate and summarize the current page into the user's language.
    func translateCurrentPage() async
}

final class AIChatTranslator: AIChatTranslating {

    private let aiChatMenuConfig: AIChatMenuVisibilityConfigurable
    private let aiChatCoordinator: AIChatCoordinating
    private let aiChatTabOpener: AIChatTabOpening
    private let pixelFiring: PixelFiring?
    private let currentPageContextProvider: () -> PageContextProtocol?
    private let currentTabProvider: @MainActor () -> Tab?
    private let pageContentExtractor: @MainActor (Tab) async -> AIChatPageContextData?
    private let aiChatConversationSourceHandler: AIChatConversationSourceHandler

    init(
        aiChatMenuConfig: AIChatMenuVisibilityConfigurable,
        aiChatCoordinator: AIChatCoordinating,
        aiChatTabOpener: AIChatTabOpening,
        pixelFiring: PixelFiring?,
        currentPageContextProvider: @escaping () -> PageContextProtocol?,
        currentTabProvider: @escaping @MainActor () -> Tab?,
        pageContentExtractor: @escaping @MainActor (Tab) async -> AIChatPageContextData?,
        aiChatConversationSourceHandler: AIChatConversationSourceHandler = Application.appDelegate.aiChatConversationSourceHandler
    ) {
        self.aiChatMenuConfig = aiChatMenuConfig
        self.aiChatCoordinator = aiChatCoordinator
        self.aiChatTabOpener = aiChatTabOpener
        self.pixelFiring = pixelFiring
        self.currentPageContextProvider = currentPageContextProvider
        self.currentTabProvider = currentTabProvider
        self.pageContentExtractor = pageContentExtractor
        self.aiChatConversationSourceHandler = aiChatConversationSourceHandler
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
        pixelFiring?.fire(AIChatPixel.aiChatTranslateText(source: .init(request.source)), frequency: .dailyAndStandard)
        revealTranslation(prompt)
    }

    /// Opens Duck.ai for the current tab with the page attached and auto-submits a request to
    /// translate and summarize it into the user's language.
    @MainActor
    func translateCurrentPage() async {
        guard aiChatMenuConfig.shouldDisplayTranslationMenuItem,
              let tab = currentTabProvider(),
              currentPageContextProvider()?.isCurrentPageAttachable == true else {
            return
        }
        let url = tab.url
        // Reading the page is async: drop it if the user moved to another tab or page meanwhile,
        // since the prompt goes to whichever tab is current.
        guard let page = await pageContentExtractor(tab), page.hasAttachedPage,
              currentTabProvider() === tab, tab.url == url else {
            return
        }

        let prompt = AIChatNativePrompt.queryPrompt(Self.pageTranslationQuery(targetLanguage: targetTranslationLanguage()),
                                                    autoSubmit: true,
                                                    pageContext: .single(page))
        pixelFiring?.fire(AIChatPixel.aiChatTranslateText(source: .translateOffer), frequency: .dailyAndStandard)
        revealTranslation(prompt)
    }

    /// Sent to the model rather than shown in the UI, so it stays in English.
    static func pageTranslationQuery(targetLanguage: String) -> String {
        let languageName = Locale(identifier: "en").localizedString(forIdentifier: targetLanguage) ?? targetLanguage
        return "Translate this page into \(languageName) and summarize it."
    }

    @MainActor
    private func revealTranslation(_ prompt: AIChatNativePrompt) {
        if !aiChatCoordinator.isChatPresentedForCurrentTab() {
            pixelFiring?.fire(
                AIChatPixel.aiChatSidebarOpened(
                    source: .translation,
                    shouldAutomaticallySendPageContext: aiChatMenuConfig.shouldAutomaticallySendPageContextTelemetryValue,
                    minutesSinceSidebarHidden: aiChatCoordinator.sidebarHiddenAtForCurrentTab()?.minutesSinceNow()
                ),
                frequency: .dailyAndStandard
            )
            aiChatConversationSourceHandler.setData(.contextualTranslate)
        }
        // The prompt carries its own context (selection or page), so the input must not also auto-attach the page.
        currentPageContextProvider()?.suppressAutoPageContextForSelectionAction()
        aiChatCoordinator.revealChat(for: prompt)
    }

    /// Return target translation language as BCP 47 code
    private func targetTranslationLanguage() -> String {
        appPreferredLanguage() ?? systemLanguage()
    }

    private let appPreferredLanguage = { Locale.preferredLanguages.first }
    private let systemLanguage = { Locale.current.identifier.replacingOccurrences(of: "_", with: "-") }
}
