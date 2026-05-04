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
    private let hasActiveChat: () -> Bool
    private weak var contextualChatViewController: AIChatContextualWebViewController?
    private var pendingChipAttachCancellable: AnyCancellable?
    private var suppressExternalContextUntilNextAttach = false
    private var isBoundToUserScript = false
    private var cancellables = Set<AnyCancellable>()

    init(
        originatingURLPublisher: AnyPublisher<URL?, Never>,
        didFinishURLPublisher: AnyPublisher<URL?, Never>,
        initialAttachedContext: AIChatPageContext?,
        initialAttachmentDeliveryState: PageContextAttachmentDeliveryState = .delivered,
        hasActiveChat: @escaping () -> Bool,
        isAutoAttachEnabled: @escaping () -> Bool,
        pageContextHandler: AIChatPageContextHandling,
        isFireTab: Bool
    ) {
        self.pageContextHandler = pageContextHandler
        self.isAutoAttachEnabled = isAutoAttachEnabled
        self.hasActiveChat = hasActiveChat
        self.coordinator = UnifiedToggleInputCoordinator(
            host: .contextualChat,
            isToggleEnabled: false,
            isFireTab: isFireTab
        )
        self.chipViewModel = UnifiedToggleInputPageContextChipViewModel(
            originatingURLPublisher: originatingURLPublisher,
            initialAttachedContext: initialAttachedContext,
            initialAttachmentDeliveryState: initialAttachmentDeliveryState,
            isAutoAttachEnabled: isAutoAttachEnabled
        )
        coordinator.viewController.bindPageContextChip(to: chipViewModel)
        chipViewModel.onAttachActionRequested = { [weak self] url in
            self?.handleChipAttachRequest(originatingURL: url)
        }
        chipViewModel.onRemoveActionRequested = { [weak self] in
            self?.handleChipRemoveRequest()
        }

        Logger.contextualUTI.debug("UTIHost init — carryOver=\(initialAttachedContext != nil, privacy: .public) auto=\(isAutoAttachEnabled(), privacy: .public)")

        // Out-of-band context (BEFORECHAT manual attach, FE-driven flows) reaches the chip
        // here; pick a delivery state from session timing — pre-chat = silent, active-chat =
        // pending. `dropFirst` skips the cold-start replay. We step aside while a UTI-driven
        // attach is in flight; that path has its own one-shot subscriber in `handleChipAttachRequest`.
        pageContextHandler.contextPublisher
            .dropFirst()
            .sink { [weak self] context in
                guard let self else { return }
                guard self.pendingChipAttachCancellable == nil else { return }
                guard context == nil || !self.suppressExternalContextUntilNextAttach else { return }
                guard context != self.chipViewModel.attachedContext else { return }
                Logger.contextualUTI.debug("UTIHost contextPublisher emission → \(context != nil ? "context" : "nil", privacy: .public) — syncing chip")
                if let context {
                    self.chipViewModel.setAttached(context, deliveryState: self.externalContextDeliveryState)
                } else {
                    self.chipViewModel.clearAttached()
                }
            }
            .store(in: &cancellables)

        // didFinish (not didCommit) so the new DOM is ready when JS reads it. `dropFirst`
        // skips the synchronous replay of the URL the half-sheet was opened on — the
        // half-sheet is the user's attach/skip decision point. Only subsequent in-chat
        // navigations should trigger auto-attach.
        didFinishURLPublisher
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] url in
                guard let self else { return }
                Logger.contextualUTI.debug("UTIHost didFinish (post-replay) → \(url?.absoluteString ?? "nil", privacy: .private)")
                guard let url else { return }
                guard self.isAutoAttachEnabled() else {
                    Logger.contextualUTI.debug("UTIHost didFinish skip — auto disabled")
                    return
                }
                if let attached = self.chipViewModel.attachedContext,
                   URL(string: attached.contextData.url) == url {
                    Logger.contextualUTI.debug("UTIHost didFinish skip — already attached to same URL")
                    return
                }
                Logger.contextualUTI.info("Auto-attach on page load — triggering for \(url.absoluteString, privacy: .private)")
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
        suppressExternalContextUntilNextAttach = false
        pendingChipAttachCancellable = pageContextHandler.contextPublisher
            .dropFirst()
            .prefix(1)
            .sink { [weak self] context in
                guard let self else { return }
                self.pendingChipAttachCancellable = nil
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
        // Cancel any in-flight collection so a late-arriving result doesn't overwrite the clear.
        pendingChipAttachCancellable = nil
        suppressExternalContextUntilNextAttach = true
        // Use `clear()` rather than `clearAttachedContext()` here because CHAT detach must also
        // cancel the handler's active JS subscription; otherwise a late collection can still
        // flow through the coordinator and re-push stale context to the frontend.
        pageContextHandler.clear()
        contextualChatViewController?.pushPageContext(nil)
        chipViewModel.clearAttached()
    }

    /// Routes UTI-submitted prompts through the contextual chat's JS message channel (same as the FE).
    /// Also wires the user script's page-context provider so every prompt payload carries whatever
    /// the chip says is currently attached — no duplicate state, single source of truth.
    func bindToUserScript(_ userScript: AIChatUserScript) {
        Logger.contextualUTI.info("Binding coordinator to AIChatUserScript")
        isBoundToUserScript = true
        coordinator.bindToTab(userScript)
        userScript.attachedPageContextProvider = { [weak self] in
            self?.chipViewModel.attachedContext?.contextData
        }
        userScript.onPromptSubmitted = { [weak self] in
            self?.chipViewModel.markPromptSubmitted()
        }
    }

    func markPromptSubmitted() {
        chipViewModel.markPromptSubmitted()
    }

    private var externalContextDeliveryState: PageContextAttachmentDeliveryState {
        // These states can differ during preload/restore: the user script may be bound before
        // `sessionState` records an active chat, while restored chats may be active before bind.
        isBoundToUserScript || hasActiveChat() ? .pendingSubmit : .delivered
    }

    func install(in contextualChatViewController: AIChatContextualWebViewController) {
        self.contextualChatViewController = contextualChatViewController
        coordinator.attachmentPresentingViewController = contextualChatViewController
        // Install + lay out without animation. Otherwise the half-sheet's slide-up animation
        // captures the UTI's first layout pass and interpolates from a zero-frame at (0,0),
        // making the bar fly in from the top-left.
        UIView.performWithoutAnimation {
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
            contextualChatViewController.view.layoutIfNeeded()
        }
        Logger.contextualUTI.info("Installed at bottom of contextual chat")
    }
}
