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
import Combine
import UIKit

// MARK: - Contextual AI Chat

extension TabViewController {

    /// Presents the contextual AI chat sheet over the current tab.
    /// Re-presents an active chat if one exists for this tab.
    ///
    /// - Parameter presentingViewController: The view controller to present the sheet from.
    func presentContextualAIChatSheet(from presentingViewController: UIViewController) {
        Task { @MainActor in
            var pageContext: AIChatPageContextData?

            let isFirstDisplay = aiChatContextualSheetCoordinator.sheetViewController == nil
            if isFirstDisplay && aiChatContextualSheetCoordinator.aiChatSettings.isAutomaticContextAttachmentEnabled {
                pageContext = await collectPageContext()
            }

            aiChatContextualSheetCoordinator.presentSheet(
                from: presentingViewController,
                pageContext: pageContext
            )
        }
    }

    /// Collects page context from the current tab via JS userscript
    func collectPageContext() async -> AIChatPageContextData? {
        guard let script = pageContextUserScript else { return nil }

        script.webView = webView

        return await withCheckedContinuation { continuation in
            var cancellable: AnyCancellable?
            var didResume = false

            cancellable = script.collectionResultPublisher
                .first()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] pageContext in
                    guard !didResume else { return }
                    didResume = true
                    cancellable?.cancel()
                    let enriched = self?.enrichWithFavicon(pageContext)
                    continuation.resume(returning: enriched)
                }

            script.collect()

            DispatchQueue.main.asyncAfter(deadline: .now() + Constants.pageContextCollectionTimeout) {
                guard !didResume else { return }
                didResume = true
                cancellable?.cancel()
                continuation.resume(returning: nil)
            }
        }
    }

    /// Reloads the contextual AI chat web view if one exists.
    func reloadContextualAIChatIfNeeded() {
        aiChatContextualSheetCoordinator.reloadIfNeeded()
    }
}

// MARK: - Private Methods

private extension TabViewController {

    enum Constants {
        static let pageContextCollectionTimeout: TimeInterval = 2
    }

    var pageContextUserScript: PageContextUserScript? {
        userScripts?.pageContextUserScript
    }

    func enrichWithFavicon(_ context: AIChatPageContextData?) -> AIChatPageContextData? {
        guard let context = context,
              let url = URL(string: context.url) else {
            return context
        }

        guard let faviconBase64 = getFaviconBase64(for: url) else {
            return context
        }

        let favicon = AIChatPageContextData.PageContextFavicon(href: faviconBase64, rel: "icon")
        return AIChatPageContextData(
            title: context.title,
            favicon: [favicon],
            url: context.url,
            content: context.content,
            truncated: context.truncated,
            fullContentLength: context.fullContentLength
        )
    }

    func getFaviconBase64(for url: URL) -> String? {
        guard let domain = url.host else { return nil }
        let faviconResult = FaviconsHelper.loadFaviconSync(forDomain: domain, usingCache: .tabs, useFakeFavicon: false)
        guard let favicon = faviconResult.image, !faviconResult.isFake else { return nil }
        return makeBase64EncodedFavicon(from: favicon)
    }

    func makeBase64EncodedFavicon(from image: UIImage) -> String? {
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

    func aiChatContextualSheetCoordinatorDidRequestOpenSettings(_ coordinator: AIChatContextualSheetCoordinator) {
        delegate?.tabDidRequestSettingsToAIChat(self)
    }

    func aiChatContextualSheetCoordinatorDidRequestOpenSyncSettings(_ coordinator: AIChatContextualSheetCoordinator) {
        delegate?.tabDidRequestSettingsToSync(self)
    }

    func aiChatContextualSheetCoordinatorDidRequestAttachPage(_ coordinator: AIChatContextualSheetCoordinator) {
        Task { @MainActor in
            guard let context = await collectPageContext() else { return }
            aiChatContextualSheetCoordinator.updatePageContext(context)
        }
    }
}
