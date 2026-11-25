//
//  AIChatLinkContextAttacher.swift
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
import AppKit
import Foundation
import PixelKit

@MainActor
protocol AIChatLinkContextAttaching {
    func askAboutLink(_ url: URL, linkType: AIChatLinkAskAboutPageType)
}

@MainActor
final class AIChatLinkContextAttacher: AIChatLinkContextAttaching {

    private let aiChatMenuConfig: AIChatMenuVisibilityConfigurable
    private let aiChatCoordinator: AIChatCoordinating
    private let pixelFiring: PixelFiring?
    private let currentPageContextProvider: () -> PageContextProtocol?
    private let aiChatConversationSourceHandler: AIChatConversationSourceHandler

    init(
        aiChatMenuConfig: AIChatMenuVisibilityConfigurable,
        aiChatCoordinator: AIChatCoordinating,
        pixelFiring: PixelFiring?,
        currentPageContextProvider: @escaping () -> PageContextProtocol?,
        aiChatConversationSourceHandler: AIChatConversationSourceHandler = Application.appDelegate.aiChatConversationSourceHandler
    ) {
        self.aiChatMenuConfig = aiChatMenuConfig
        self.aiChatCoordinator = aiChatCoordinator
        self.pixelFiring = pixelFiring
        self.currentPageContextProvider = currentPageContextProvider
        self.aiChatConversationSourceHandler = aiChatConversationSourceHandler
    }

    func askAboutLink(_ url: URL, linkType: AIChatLinkAskAboutPageType) {
        pixelFiring?.fire(AIChatPixel.aiChatLinkAskAboutPage(linkType: linkType), frequency: .dailyAndCount)
        guard let pageContext = currentPageContextProvider() else { return }

        if !aiChatCoordinator.isChatPresentedForCurrentTab() {
            pixelFiring?.fire(
                AIChatPixel.aiChatSidebarOpened(
                    source: .askAboutLink,
                    shouldAutomaticallySendPageContext: aiChatMenuConfig.shouldAutomaticallySendPageContextTelemetryValue,
                    minutesSinceSidebarHidden: aiChatCoordinator.sidebarHiddenAtForCurrentTab()?.minutesSinceNow()
                ),
                frequency: .dailyAndStandard
            )
            aiChatConversationSourceHandler.setData(.askAboutPage)
        }

        // Take the slot before the sidebar opens, so it doesn't attach the tab's own page meanwhile.
        _ = pageContext.attachLinkedPage(url)
        aiChatCoordinator.revealChat()
    }
}
