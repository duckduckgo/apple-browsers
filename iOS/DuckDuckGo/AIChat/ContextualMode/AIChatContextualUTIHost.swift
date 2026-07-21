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

/// Owns a `UnifiedToggleInputCoordinator` configured for the contextual chat surface.
@MainActor
final class AIChatContextualUTIHost: UnifiedToggleInputDelegate {

    private let coordinator: UnifiedToggleInputCoordinator
    let chipViewModel: UnifiedToggleInputPageContextChipViewModel
    private let hasActiveChat: () -> Bool
    private weak var contextualChatViewController: AIChatContextualWebViewController?
    private weak var currentUserScript: AIChatUserScript?
    private weak var pendingUserScriptToBind: AIChatUserScript?
    private var isBoundToUserScript = false
    private var hasDeliveredFirstPrompt = false
    private let startsPreSubmit: Bool
    private var cancellables = Set<AnyCancellable>()
    private let duckAIWideEventInstrumentation: DuckAIWideEventInstrumentation
    private let duckAIWideEventFlowScope = DuckAIWideEventFlowScope.contextual(UUID())

    var onAttachRequested: (() -> Void)?
    var onRemoveRequested: (() -> Void)?
    var onPromptSubmitted: (() -> Void)?
    /// Fires on every prompt delivery so the session state can mark context delivered and re-render the chip.
    var onPromptDelivered: (() -> Void)?
    var onAIVoiceChatRequested: (() -> Void)?

    var attachedContextURL: URL? {
        chipViewModel.attachedContext.flatMap { URL(string: $0.contextData.url) }
    }

    init(
        originatingURLPublisher: AnyPublisher<URL?, Never>,
        initialAttachedContext: AIChatPageContext?,
        initialAttachmentDeliveryState: PageContextAttachmentDeliveryState = .delivered,
        hasActiveChat: @escaping () -> Bool,
        isAutoAttachEnabled: @escaping () -> Bool,
        isCurrentPageAttachable: @escaping () -> Bool = { true },
        isFireTab: Bool,
        lastUsedModelProvider: DuckAiLastUsedModelProviding? = nil,
        voiceShortcutFeature: DuckAIVoiceShortcutFeatureProviding = DuckAIVoiceShortcutFeature(),
        startsPreSubmit: Bool = false
    ) {
        self.hasActiveChat = hasActiveChat
        self.startsPreSubmit = startsPreSubmit
        self.hasDeliveredFirstPrompt = !startsPreSubmit
        let wideEventInstrumentation = DefaultDuckAIWideEventInstrumentation(
            wideEvent: AppDependencyProvider.shared.wideEvent
        )
        self.duckAIWideEventInstrumentation = wideEventInstrumentation
        self.coordinator = UnifiedToggleInputCoordinator(
            host: .contextualChat,
            isToggleEnabled: false,
            isFireTab: isFireTab,
            lastUsedModelProvider: lastUsedModelProvider,
            duckAIWideEventInstrumentation: wideEventInstrumentation,
            duckAIWideEventFlowScope: duckAIWideEventFlowScope,
            contextualStartsPreSubmit: startsPreSubmit
        )
        self.chipViewModel = UnifiedToggleInputPageContextChipViewModel(
            originatingURLPublisher: originatingURLPublisher,
            initialAttachedContext: initialAttachedContext,
            initialAttachmentDeliveryState: initialAttachmentDeliveryState,
            isAutoAttachEnabled: isAutoAttachEnabled
        )
        coordinator.delegate = self
        coordinator.updateAIVoiceChatAvailability(voiceShortcutFeature.isAvailable)
        coordinator.onPageContextAttachRequested = { [weak chipViewModel] in
            chipViewModel?.tapToAttach()
        }
        coordinator.isPageContextAttachable = isCurrentPageAttachable
        coordinator.hasPendingPageContextProvider = { [weak chipViewModel] in
            chipViewModel?.pendingAttachedContextData != nil
        }
        coordinator.updateImageButtonVisibility()
        coordinator.viewController.bindPageContextChip(to: chipViewModel)
        chipViewModel.onAttachActionRequested = { [weak self] in
            self?.onAttachRequested?()
        }
        chipViewModel.onRemoveActionRequested = { [weak self] in
            self?.onRemoveRequested?()
        }

        Logger.contextualUTI.debug("UTIHost init — carryOver=\(initialAttachedContext != nil, privacy: .public) auto=\(isAutoAttachEnabled(), privacy: .public)")

        coordinator.intentPublisher
            .sink { [weak self] _ in
                self?.applyCurrentRenderState()
            }
            .store(in: &cancellables)
    }

    /// Re-evaluates the attach button/menu for the current page (e.g. page-context attachability after navigation).
    func refreshPageContextAttachability() {
        coordinator.updateImageButtonVisibility()
    }

    func setAttachedContext(_ context: AIChatPageContext, deliveryState: PageContextAttachmentDeliveryState = .pendingSubmit) {
        chipViewModel.setAttached(context, deliveryState: deliveryState)
    }

    func clearAttachedContext() {
        chipViewModel.clearAttached()
    }

    func showAttachAffordance() {
        chipViewModel.showAttachAffordance()
    }

    /// Routes UTI-submitted prompts through the contextual chat's JS message channel (same as the FE).
    /// Also wires the user script's page-context provider so every prompt payload carries whatever
    /// the chip says is currently attached — no duplicate state, single source of truth.
    func bindToUserScript(_ userScript: AIChatUserScript) {
        Logger.contextualUTI.info("Binding coordinator to AIChatUserScript")
        currentUserScript = userScript
        userScript.attachedPageContextProvider = { [weak self] in
            self?.chipViewModel.pendingAttachedContextData
        }
        userScript.onPromptSubmitted = { [weak self] in
            self?.handlePromptSubmittedFromUserScript()
        }

        if startsPreSubmit, !hasDeliveredFirstPrompt {
            pendingUserScriptToBind = userScript
            return
        }

        bindCoordinator(to: userScript)
    }

    func observeChatUpdates(_ publisher: AnyPublisher<String, Never>) {
        coordinator.observeChatUpdates(publisher)
    }

    /// Called when a prompt carrying page context is delivered; routes to the session state via `onPromptDelivered`.
    func notifyPromptDelivered() {
        onPromptDelivered?()
    }

    func setContextualChatViewController(_ contextualChatViewController: AIChatContextualWebViewController) {
        self.contextualChatViewController = contextualChatViewController
    }

    func installInWebView(_ contextualChatViewController: AIChatContextualWebViewController) {
        setContextualChatViewController(contextualChatViewController)
        coordinator.attachmentPresentingViewController = contextualChatViewController

        let viewController = coordinator.viewController
        guard viewController.parent !== contextualChatViewController else {
            return
        }

        UIView.performWithoutAnimation {
            contextualChatViewController.addChild(viewController)
            contextualChatViewController.view.addSubview(viewController.view)
            viewController.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                viewController.view.leadingAnchor.constraint(equalTo: contextualChatViewController.view.leadingAnchor),
                viewController.view.trailingAnchor.constraint(equalTo: contextualChatViewController.view.trailingAnchor),
                viewController.view.bottomAnchor.constraint(equalTo: contextualChatViewController.view.keyboardLayoutGuide.topAnchor),
            ])
            contextualChatViewController.anchorWebViewBottom(to: viewController.view.topAnchor)
            viewController.didMove(toParent: contextualChatViewController)
            coordinator.showExpanded()
            applyCurrentRenderState()
            contextualChatViewController.view.layoutIfNeeded()
        }
        Logger.contextualUTI.info("Installed at bottom of contextual web chat")
    }

    func mountAtSheetLevel(in sheetViewController: UIViewController) -> UIView {
        coordinator.attachmentPresentingViewController = sheetViewController

        let viewController = coordinator.viewController
        guard viewController.parent !== sheetViewController else {
            return viewController.view
        }

        // Install + lay out without animation. Otherwise the half-sheet's slide-up animation
        // captures the UTI's first layout pass and interpolates from a zero-frame at (0,0),
        // making the bar fly in from the top-left.
        UIView.performWithoutAnimation {
            sheetViewController.addChild(viewController)
            sheetViewController.view.addSubview(viewController.view)
            viewController.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                viewController.view.leadingAnchor.constraint(equalTo: sheetViewController.view.leadingAnchor),
                viewController.view.trailingAnchor.constraint(equalTo: sheetViewController.view.trailingAnchor),
                viewController.view.bottomAnchor.constraint(equalTo: sheetViewController.view.keyboardLayoutGuide.topAnchor),
            ])
            viewController.didMove(toParent: sheetViewController)
            coordinator.showExpanded(activatesInput: false)
            applyCurrentRenderState()
            sheetViewController.view.layoutIfNeeded()
        }
        Logger.contextualUTI.info("Mounted at bottom of contextual sheet")
        return viewController.view
    }

    func activateInput() {
        coordinator.showExpanded()
    }

    func deactivateInput() {
        coordinator.viewController.deactivateInput()
    }

    /// Preselects a model on the bound coordinator (e.g. the onboarding-chosen model), so the first submitted
    /// prompt — and every subsequent live-pushed one — carries it.
    func preselectModel(_ modelId: String) {
        coordinator.updateSelectedModel(modelId)
    }

    func submitQuickActionPrompt(_ prompt: String) {
        coordinator.submitProgrammatic(text: prompt)
    }

    func prepareForNewChat() {
        hasDeliveredFirstPrompt = !startsPreSubmit
        clearAttachedContext()
        if startsPreSubmit, let currentUserScript {
            coordinator.unbind()
            isBoundToUserScript = false
            pendingUserScriptToBind = currentUserScript
        }
        coordinator.startNewChat()
        coordinator.showExpanded(activatesInput: false)
        applyCurrentRenderState()
    }

    private func applyCurrentRenderState() {
        coordinator.viewController.apply(coordinator.computeRenderState().viewConfig, animated: false)
        contextualChatViewController?.view.layoutIfNeeded()
    }

    private func bindCoordinator(to userScript: AIChatUserScript) {
        isBoundToUserScript = true
        let chatID = userScript.webView?.url?.duckAIChatID
        coordinator.bindToTab(userScript, hasExistingChat: hasActiveChat() || chatID != nil)
        if let chatID {
            coordinator.restoreLastUsedModel(forChatID: chatID)
        }
    }

    private func commitDeferredBindIfNeeded() {
        guard !isBoundToUserScript, let pendingUserScriptToBind else { return }
        self.pendingUserScriptToBind = nil
        bindCoordinator(to: pendingUserScriptToBind)
    }

    private func handlePromptSubmittedFromUserScript() {
        if !hasDeliveredFirstPrompt {
            hasDeliveredFirstPrompt = true
            onPromptSubmitted?()
            commitDeferredBindIfNeeded()
        }
        onPromptDelivered?()
    }

    func unifiedToggleInputDidSubmitPrompt(_ prompt: String,
                                           modelId: String?,
                                           tools: [AIChatRAGTool]?,
                                           reasoningEffort: AIChatReasoningEffort?,
                                           images: [AIChatNativePrompt.NativePromptImage]?,
                                           files: [AIChatNativePrompt.NativePromptFile]?) {
        guard !hasDeliveredFirstPrompt else { return }
        hasDeliveredFirstPrompt = true
        onPromptSubmitted?()
        contextualChatViewController?.submitPrompt(prompt,
                                                   images: images,
                                                   files: files,
                                                   modelId: modelId,
                                                   tools: tools,
                                                   pageContext: chipViewModel.pendingAttachedContextData,
                                                   reasoningEffort: reasoningEffort)
        commitDeferredBindIfNeeded()
        onPromptDelivered?()
    }

    func unifiedToggleInputDidSubmitQuery(_ query: String) {}
    func unifiedToggleInputDidRequestVoiceSearch() {}
    func unifiedToggleInputDidRequestAIVoiceChat() {
        onAIVoiceChatRequested?()
    }
    func unifiedToggleInputDidRequestAIChat(prefilledText: String) {}
    func unifiedToggleInputDidChangeHeight() {}
    func unifiedToggleInputDidCommitMode(_ mode: TextEntryMode) {}
    func unifiedToggleInputDidRequestFire() {}
    func unifiedToggleInputDidRequestAppMenu() {}
}

// MARK: - Duck.ai Wide Event

extension AIChatContextualUTIHost {

    func sheetDismissed() {
        duckAIWideEventInstrumentation.sheetDismissedDuringGeneration(scope: duckAIWideEventFlowScope)
    }

    func promptDeliveryUpdated(wasQueued: Bool?, didSendBridgeMessage: Bool?) {
        duckAIWideEventInstrumentation.promptDeliveryUpdated(scope: duckAIWideEventFlowScope, wasQueued: wasQueued, didSendBridgeMessage: didSendBridgeMessage)
    }

    func frontendSubmissionAcknowledged() {
        duckAIWideEventInstrumentation.frontendSubmissionAcknowledged(scope: duckAIWideEventFlowScope)
    }

    func pageLoadFailed(error: Error) {
        duckAIWideEventInstrumentation.pageLoadFailed(scope: duckAIWideEventFlowScope, error: error)
    }

    /// Called when the contextual sheet's native input submits the initial prompt of a chat,
    /// which bypasses the UTI. Routes the wide-event start through the shared UTI coordinator
    /// so the in-flight flow receives the JS status updates that follow.
    func initialNativePromptSubmitted(hasPageContext: Bool) {
        coordinator.recordExternalPromptSubmitted(
            entryPoint: .contextualChat,
            inputMode: .keyboard,
            isFirstPrompt: true,
            hasPageContext: hasPageContext
        )
    }
}
