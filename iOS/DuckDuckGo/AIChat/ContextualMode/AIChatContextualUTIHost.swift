//
//  AIChatContextualUTIHost.swift
//  DuckDuckGo
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
import Combine
import UIKit
import os.log

/// Owns a `UnifiedToggleInputCoordinator` configured for the contextual chat surface and
/// embeds its view controller as a child of `AIChatContextualWebViewController`.
@MainActor
final class AIChatContextualUTIHost {

    private let coordinator: UnifiedToggleInputCoordinator
    private let pageContextHandler: AIChatPageContextHandling
    let chipViewModel: UnifiedToggleInputPageContextChipViewModel
    private let isAutoAttachEnabled: () -> Bool
    private weak var contextualChatViewController: AIChatContextualWebViewController?
    private var pendingChipAttachCancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()

    init(
        originatingURLPublisher: AnyPublisher<URL?, Never>,
        initialAttachedContext: AIChatPageContext?,
        isAutoAttachEnabled: @escaping () -> Bool,
        pageContextHandler: AIChatPageContextHandling,
        isFireTab: Bool
    ) {
        self.pageContextHandler = pageContextHandler
        self.isAutoAttachEnabled = isAutoAttachEnabled
        self.coordinator = UnifiedToggleInputCoordinator(
            host: .contextualChat,
            isToggleEnabled: false,
            isFireTab: isFireTab
        )
        self.chipViewModel = UnifiedToggleInputPageContextChipViewModel(
            originatingURLPublisher: originatingURLPublisher,
            initialAttachedContext: initialAttachedContext,
            isAutoAttachEnabled: isAutoAttachEnabled
        )
        coordinator.viewController.bindPageContextChip(to: chipViewModel)
        chipViewModel.onAttachActionRequested = { [weak self] url in
            self?.handleChipAttachRequest(originatingURL: url)
        }
        chipViewModel.onRemoveActionRequested = { [weak self] in
            self?.handleChipRemoveRequest()
        }

        originatingURLPublisher
            .removeDuplicates()
            .dropFirst()  // initial value already accounted for via initialAttachedContext
            .sink { [weak self] url in
                guard let self, let url, self.isAutoAttachEnabled() else { return }
                Logger.contextualUTI.info("Auto-attach on tab navigation — triggering for \(url.absoluteString, privacy: .private)")
                self.handleChipAttachRequest(originatingURL: url)
            }
            .store(in: &cancellables)
    }

    private func handleChipAttachRequest(originatingURL: URL) {
        Logger.contextualUTI.info("Chip onAttach — triggering context collection")
        guard pageContextHandler.triggerContextCollection() else {
            Logger.contextualUTI.error("triggerContextCollection returned false")
            return
        }
        pendingChipAttachCancellable = pageContextHandler.contextPublisher
            .dropFirst()
            .prefix(1)
            .sink { [weak self] context in
                guard let self else { return }
                guard let context else {
                    Logger.contextualUTI.error("Collection completed with nil context")
                    return
                }
                Logger.contextualUTI.info("Pushing collected context to contextual chat for FE delivery")
                self.contextualChatViewController?.pushPageContext(context.contextData)
                self.chipViewModel.setAttached(context)
            }
    }

    private func handleChipRemoveRequest() {
        Logger.contextualUTI.info("Chip onRemove — clearing attached context")
        pageContextHandler.clearAttachedContext()
        contextualChatViewController?.pushPageContext(nil)
        chipViewModel.setAttached(nil)
    }

    /// Routes UTI-submitted prompts through the contextual chat's JS message channel (same as the FE).
    func bindToUserScript(_ userScript: AIChatUserScript) {
        Logger.contextualUTI.info("Binding coordinator to AIChatUserScript")
        coordinator.bindToTab(userScript)
    }

    func install(in contextualChatViewController: AIChatContextualWebViewController) {
        self.contextualChatViewController = contextualChatViewController
        coordinator.attachmentPresentingViewController = contextualChatViewController
        contextualChatViewController.addChild(coordinator.viewController)
        contextualChatViewController.view.addSubview(coordinator.viewController.view)
        coordinator.viewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            coordinator.viewController.view.leadingAnchor.constraint(equalTo: contextualChatViewController.view.leadingAnchor),
            coordinator.viewController.view.trailingAnchor.constraint(equalTo: contextualChatViewController.view.trailingAnchor),
            coordinator.viewController.view.bottomAnchor.constraint(equalTo: contextualChatViewController.view.keyboardLayoutGuide.topAnchor),
        ])
        contextualChatViewController.anchorWebViewBottom(to: coordinator.viewController.view.topAnchor)
        coordinator.viewController.didMove(toParent: contextualChatViewController)
        coordinator.showExpanded()
        Logger.contextualUTI.info("Installed at bottom of contextual chat")
    }
}
