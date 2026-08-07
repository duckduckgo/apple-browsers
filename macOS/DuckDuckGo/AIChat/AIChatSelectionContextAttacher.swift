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

/// Handles the "Attach to Duck.ai" context-menu action: appends the user's text selection to the
/// Duck.ai sidebar's selection-context list (independent of the single page-context slot) and
/// reveals the sidebar.
///
/// Mirrors `AIChatSummarizer`/`AIChatTranslator`: it owns gating + telemetry and builds the item,
/// then hands it to the current content tab's `PageContextTabExtension`, which buffers/forwards it
/// to the sidebar. The duck.ai web app owns the resulting list of selections.
@MainActor
protocol AIChatSelectionContextAttaching {

    /// Appends `text` selected on the page at `url` to the Duck.ai selection list and reveals the sidebar.
    func attach(text: String, url: URL?)
}

@MainActor
final class AIChatSelectionContextAttacher: AIChatSelectionContextAttaching {

    private enum Constants {
        /// Matches `maxContentLength` default in content-scope-scripts (page-context.js).
        static let maxSelectionContextLength = 9500
    }

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

    func attach(text: String, url: URL?) {
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

        let truncated = text.count > Constants.maxSelectionContextLength
        let content = truncated ? String(text.prefix(Constants.maxSelectionContextLength)) : text
        // Count words on the full selection (not the truncated `content`) so the FE shows the real size.
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        let selection = AIChatSelectionContextData(
            id: UUID().uuidString,
            title: UserText.aiChatTextSelection,
            url: url?.absoluteString ?? "",
            content: content,
            truncated: truncated,
            fullContentLength: text.count,
            wordCount: wordCount
        )

        // Append the selection, then reveal the sidebar; the tab extension flushes it once the chat VC is up.
        currentPageContextProvider()?.appendSelectionContext(selection)
        aiChatCoordinator.revealChat()
    }
}
