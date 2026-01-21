//
//  AIChatContextualSheetViewModel.swift
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

import AIChat
import Combine
import DesignResourcesKitIcons
import UIKit

/// ViewModel for the contextual AI chat sheet, managing state and business logic.
final class AIChatContextualSheetViewModel {

    // MARK: - Published State

    /// Whether the expand button should be enabled
    @Published private(set) var isExpandEnabled: Bool = true

    /// Whether the new chat button should be visible
    @Published private(set) var isNewChatButtonVisible: Bool = false

    // MARK: - Properties

    private let settings: AIChatSettingsProvider

    /// Single source of truth for page context
    let pageContextStore: AIChatPageContextStoring

    /// Tracks whether the user has submitted at least one prompt
    private(set) var hasSubmittedPrompt = false

    /// The URL containing chat ID for session restoration when expanding to full mode
    private(set) var contextualChatURL: URL?

    // MARK: - Initialization

    init(settings: AIChatSettingsProvider,
         pageContextStore: AIChatPageContextStoring,
         hasExistingChat: Bool = false) {
        self.settings = settings
        self.pageContextStore = pageContextStore
        if hasExistingChat {
            hasSubmittedPrompt = true
            isNewChatButtonVisible = true
        }
        updateExpandButtonState()
    }

    // MARK: - Public Methods

    /// Returns the URL to use when expanding to full mode.
    /// Uses the contextual chat URL if available (preserves active chat session),
    /// otherwise falls back to the base AI chat URL.
    func expandURL() -> URL {
        contextualChatURL ?? settings.aiChatURL
    }

    /// Creates the attach actions for the contextual input view
    func createAttachActions(onAttachPage: @escaping () -> Void) -> [AIChatAttachAction] {
        let attachPageAction = AIChatAttachAction(
            title: UserText.aiChatAttachPageContent,
            icon: DesignResourcesKitIcons.DesignSystemImages.Glyphs.Size16.summary,
            handler: onAttachPage
        )
        return [attachPageAction]
    }

    /// Creates and configures a context chip view with the current page context
    func createContextChipView(onRemove: @escaping () -> Void) -> AIChatContextChipView? {
        guard let context = pageContextStore.latestContext else { return nil }

        let chipView = AIChatContextChipView()
        chipView.configure(title: context.title, favicon: pageContextStore.latestFavicon)
        chipView.subtitle = UserText.aiChatContextChipSubtitle
        chipView.onRemove = onRemove
        return chipView
    }

    /// Whether automatic context attachment is enabled
    var isAutomaticContextAttachmentEnabled: Bool {
        settings.isAutomaticContextAttachmentEnabled
    }

    /// Whether the contextual onboarding has been seen
    var hasSeenContextualOnboarding: Bool {
        settings.hasSeenContextualOnboarding
    }

    /// Marks the contextual onboarding as seen
    func markContextualOnboardingSeen() {
        settings.markContextualOnboardingSeen()
    }

    /// Called when a prompt is submitted
    func didSubmitPrompt() {
        hasSubmittedPrompt = true
        isNewChatButtonVisible = true
        updateExpandButtonState()
    }

    /// Called when the contextual chat URL changes
    func didUpdateContextualChatURL(_ url: URL?) {
        contextualChatURL = url
        updateExpandButtonState()
    }

    /// Called when the user explicitly starts a new chat
    func didStartNewChat() {
        hasSubmittedPrompt = false
        contextualChatURL = nil
        isNewChatButtonVisible = false
        updateExpandButtonState()
    }

    /// Sets the initial contextual chat URL (e.g., from an existing web view controller)
    func setInitialContextualChatURL(_ url: URL?) {
        contextualChatURL = url
        updateExpandButtonState()
    }

    /// Clears the page context (called when user removes the context chip)
    func clearPageContext() {
        pageContextStore.clear()
    }

    // MARK: - Private Methods

    private func updateExpandButtonState() {
        isExpandEnabled = !hasSubmittedPrompt || contextualChatURL != nil
    }
}
