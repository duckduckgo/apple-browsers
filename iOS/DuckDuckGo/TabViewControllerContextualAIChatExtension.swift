//
//  TabViewControllerContextualAIChatExtension.swift
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
import Core
import UIKit

// MARK: - Contextual AI Chat

extension TabViewController {

    /// Presents the contextual AI chat sheet over the current tab.
    /// Re-presents an active chat if one exists for this tab, or restores from persisted URL after app restart.
    ///
    /// - Parameter presentingViewController: The view controller to present the sheet from.
    func presentContextualAIChatSheet(from presentingViewController: UIViewController) {
        Task { @MainActor in
            await aiChatContextualSheetCoordinator.presentSheet(
                from: presentingViewController,
                restoreURL: restoreURLForContextualSheet()
            )
        }
    }

    func presentContextualFloatingInput(from presentingViewController: UIViewController) {
        Task { @MainActor in
            await aiChatContextualSheetCoordinator.presentFloatingInput(from: presentingViewController)
        }
    }

    /// Presents the contextual surface with `text` attached as its own context. Nothing is submitted — the selection
    /// is there for the user to ask about, so the page is not auto-attached on top of it.
    @MainActor
    func presentContextualAIChat(withSelectedText text: String,
                                 from presentingViewController: UIViewController) async {
        let url = webView.url
        await aiChatContextualSheetCoordinator.handleSelectionAction(
            .ask,
            selection: AIChatPageTextSelection(
                text: text,
                url: url,
                faviconBase64: url.flatMap { getFaviconBase64(for: $0) }
            ),
            restoreURL: restoreURLForContextualSheet(),
            from: presentingViewController
        )
    }

    /// A conversation this tab can return to: either still live in the coordinator, or persisted by an
    /// earlier launch and waiting to be restored.
    var hasContextualChatToReopen: Bool {
        aiChatContextualSheetCoordinator.sessionState.hasActiveChat || tabModel.contextualChatURL != nil
    }

    /// The persisted chat to restore, for both the plain and the selection-carrying entry points —
    /// attaching a selection must not cost the user the conversation they already had.
    private func restoreURLForContextualSheet() -> URL? {
        guard !aiChatContextualSheetCoordinator.hasActiveSheet,
              let urlString = tabModel.contextualChatURL else { return nil }
        return URL(string: urlString)
    }

    /// Reloads the contextual AI chat web view if one exists.
    func reloadContextualAIChatIfNeeded() {
        aiChatContextualSheetCoordinator.reloadIfNeeded()
    }
}

// MARK: - Favicon Helpers

extension TabViewController {

    func getFaviconBase64(for url: URL) -> String? {
        guard let domain = url.host else { return nil }
        let faviconResult = FaviconsHelper.loadFaviconSync(forDomain: domain, usingCache: .tabs, useFakeFavicon: false)
        guard let favicon = faviconResult.image, !faviconResult.isFake else { return nil }
        return makeBase64EncodedFavicon(from: favicon)
    }

    private func makeBase64EncodedFavicon(from image: UIImage) -> String? {
        guard let pngData = image.pngData() else { return nil }
        return "data:image/png;base64,\(pngData.base64EncodedString())"
    }
}

// MARK: - AIChatContextualSheetCoordinatorDelegate

extension TabViewController: AIChatContextualSheetCoordinatorDelegate {

    func aiChatContextualSheetCoordinator(_ coordinator: AIChatContextualSheetCoordinator, didRequestToLoad url: URL) {
        delegate?.tab(self, didRequestNewTabForUrl: url, openedByPage: false, inheritingAttribution: nil)
    }

    func aiChatContextualSheetCoordinator(_ coordinator: AIChatContextualSheetCoordinator, didRequestExpandWithURL url: URL) {
        delegate?.tab(self, didRequestNewTabForUrl: url, openedByPage: false, inheritingAttribution: nil)
    }

    func aiChatContextualSheetCoordinatorDidRequestViewAllChats(_ coordinator: AIChatContextualSheetCoordinator) {
        delegate?.tabDidRequestAIChatHistory(tab: self, source: .contextualChat)
    }

    func aiChatContextualSheetCoordinatorDidRequestOpenSettings(_ coordinator: AIChatContextualSheetCoordinator) {
        delegate?.tabDidRequestSettingsToAIChat(self)
    }

    func aiChatContextualSheetCoordinatorDidRequestOpenSyncSettings(_ coordinator: AIChatContextualSheetCoordinator) {
        delegate?.tabDidRequestSettingsToSync(self)
    }

    func aiChatContextualSheetCoordinator(_ coordinator: AIChatContextualSheetCoordinator, didUpdateContextualChatURL url: URL?) {
        tabModel.contextualChatURL = url?.absoluteString
        delegate?.tabLoadingStateDidChange(tab: self)
    }

    func aiChatContextualSheetCoordinator(_ coordinator: AIChatContextualSheetCoordinator, didRequestOpenDownloadWithFileName fileName: String) {
        delegate?.tabDidRequestDownloads(tab: self)
    }

    func aiChatContextualSheetCoordinator(_ coordinator: AIChatContextualSheetCoordinator, didRequestDeleteChatWithID chatID: String) {
        delegate?.tabDidRequestDeleteContextualChat(tab: self, chatID: chatID)
    }

    func aiChatContextualSheetCoordinatorDidRequestNewVoiceChat(_ coordinator: AIChatContextualSheetCoordinator) {
        delegate?.tabDidRequestNewVoiceChat(self)
    }
}
