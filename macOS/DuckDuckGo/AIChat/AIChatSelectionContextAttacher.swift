//
//  AIChatSelectionContextAttacher.swift
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
import Foundation
import PixelKit

/// Handles the "Attach to Duck.ai" context-menu action: attaches the user's text selection as the
/// AI Chat sidebar's page context (instead of the full page) and reveals the sidebar.
///
/// Mirrors `AIChatSummarizer`/`AIChatTranslator`: it owns gating + telemetry, then delegates the
/// actual attachment to the current content tab's `PageContextTabExtension` (the single authority
/// that drives the sidebar's page-context chip) before revealing the sidebar.
@MainActor
protocol AIChatSelectionContextAttaching {

    /// Attaches `text` selected on the page at `url`/`title` as the sidebar's page context.
    func attach(text: String, url: URL?, title: String?)
}

@MainActor
final class AIChatSelectionContextAttacher: AIChatSelectionContextAttaching {

    private let aiChatMenuConfig: AIChatMenuVisibilityConfigurable
    private let aiChatCoordinator: AIChatCoordinating
    private let pixelFiring: PixelFiring?
    private let currentPageContextProvider: () -> PageContextProtocol?

    init(
        aiChatMenuConfig: AIChatMenuVisibilityConfigurable,
        aiChatCoordinator: AIChatCoordinating,
        pixelFiring: PixelFiring?,
        currentPageContextProvider: @escaping () -> PageContextProtocol?
    ) {
        self.aiChatMenuConfig = aiChatMenuConfig
        self.aiChatCoordinator = aiChatCoordinator
        self.pixelFiring = pixelFiring
        self.currentPageContextProvider = currentPageContextProvider
    }

    func attach(text: String, url: URL?, title: String?) {
        guard aiChatMenuConfig.shouldDisplaySelectionContextMenuItem else {
            return
        }

        pixelFiring?.fire(AIChatPixel.aiChatAttachSelection, frequency: .dailyAndStandard)

        if !aiChatCoordinator.isChatPresentedForCurrentTab() {
            pixelFiring?.fire(
                AIChatPixel.aiChatSidebarOpened(
                    source: .attachSelection,
                    shouldAutomaticallySendPageContext: aiChatMenuConfig.shouldAutomaticallySendPageContextTelemetryValue,
                    minutesSinceSidebarHidden: aiChatCoordinator.sidebarHiddenAtForCurrentTab()?.minutesSinceNow()
                ),
                frequency: .dailyAndStandard
            )
        }

        // Set the override before revealing so the sidebar's session-creation path delivers the
        // selection (not the auto-collected full page) as the active context.
        currentPageContextProvider()?.attachSelectionContext(text: text, url: url, title: title)
        aiChatCoordinator.revealChat()
    }
}
