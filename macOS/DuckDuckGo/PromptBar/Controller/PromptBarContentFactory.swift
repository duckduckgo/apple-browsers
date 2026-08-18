//
//  PromptBarContentFactory.swift
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

/// Assembles the Prompt Bar's content from the shared Duck.ai prompt stack. The address-bar
/// equivalent lives in `MainViewController.init`.
@MainActor
enum PromptBarContentFactory {

    static func makeContent(promptSubmitter: PromptBarPromptSubmitting,
                            themeManager: ThemeManaging,
                            aiChatTabOpener: AIChatTabOpening,
                            duckAiNativeStorageHandler: DuckAiNativeStorageHandling?,
                            preferences: AIChatPreferencesPersisting) -> PromptBarOmnibarContentViewController {
        let draftStore = EphemeralPromptDraftStore()

        let omnibarController = AIChatOmnibarController(
            aiChatTabOpener: aiChatTabOpener,
            surface: .promptBar,
            draftSource: StaticPromptDraftSource(store: draftStore),
            // No browser window behind the bar, so nothing scopes page context or voice reuse.
            origin: nil,
            pixelHandler: PromptBarPixelHandler(),
            suggestionsReader: nil,
            preferences: preferences
        )

        let containerViewController = AIChatOmnibarContainerViewController(
            themeManager: themeManager,
            omnibarController: omnibarController,
            duckAiNativeStorageHandler: duckAiNativeStorageHandler,
            // No window to inherit burner mode from.
            burnerMode: .regular
        )
        let textViewController = AIChatOmnibarTextContainerViewController(
            omnibarController: omnibarController,
            themeManager: themeManager,
            isBurner: false
        )

        return PromptBarOmnibarContentViewController(
            omnibarController: omnibarController,
            containerViewController: containerViewController,
            textViewController: textViewController,
            draftStore: draftStore,
            promptSubmitter: promptSubmitter,
            themeManager: themeManager
        )
    }
}
