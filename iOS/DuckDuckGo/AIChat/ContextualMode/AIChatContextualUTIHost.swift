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
    /// Live phase source handed to the coordinator (weak there) so the model chip survives a rebind.
    private let hostAdapter: ContextualChatHostAdapter
    private weak var contextualChatViewController: AIChatContextualWebViewController?
    private var pendingChipAttachCancellable: AnyCancellable?
    private var suppressExternalContextUntilNextAttach = false
    private var isBoundToUserScript = false
    /// True for the immediate-UTI fresh-chat host: the coordinator stays unbound until the first
    /// submit so that prompt takes the unbound → web-VC-queue path (a bound first submit would skip
    /// the frontend-state flip → invisible chat). Restored/legacy hosts bind immediately.
    private let startsPreSubmit: Bool
    /// Set once the first UTI prompt is delivered; gates rapid re-submit and flips a deferred bind to immediate.
    private var hasDeliveredFirstPrompt = false
    /// User script stashed at `bindToUserScript` while pre-submit; bound after the first submit.
    private weak var pendingUserScriptToBind: AIChatUserScript?
    /// The web view's user script, remembered across binds so a New-Chat reset can re-arm the
    /// deferred bind against the same (still-alive) script without waiting for a fresh install.
    private weak var lastKnownUserScript: AIChatUserScript?
    /// Flips the session into an active chat (native→web swap + expand) on the first UTI submit and
    /// returns the page context frozen at flip time. Wired by the sheet coordinator, which owns session state.
    var onFirstPromptSubmitted: (() -> AIChatPageContextData?)?
    /// Fired when the queued first prompt can no longer be delivered (page load failed) so the sheet
    /// can recover to a clean pre-submit state for retry. Wired by the sheet coordinator.
    var onFirstPromptFailed: (() -> Void)?
    private var cancellables = Set<AnyCancellable>()
    private let duckAIWideEventInstrumentation: DuckAIWideEventInstrumentation
    private let duckAIWideEventFlowScope = DuckAIWideEventFlowScope.contextual(UUID())

    init(
        originatingURLPublisher: AnyPublisher<URL?, Never>,
        didFinishURLPublisher: AnyPublisher<URL?, Never>,
        initialAttachedContext: AIChatPageContext?,
        initialAttachmentDeliveryState: PageContextAttachmentDeliveryState = .delivered,
        hasActiveChat: @escaping () -> Bool,
        isAutoAttachEnabled: @escaping () -> Bool,
        pageContextHandler: AIChatPageContextHandling,
        isFireTab: Bool,
        contextualStartsPreSubmit: Bool = false,
        lastUsedModelProvider: DuckAiLastUsedModelProviding? = nil
    ) {
        self.pageContextHandler = pageContextHandler
        self.isAutoAttachEnabled = isAutoAttachEnabled
        self.hasActiveChat = hasActiveChat
        self.startsPreSubmit = contextualStartsPreSubmit
        self.hostAdapter = ContextualChatHostAdapter(hasActiveChat: hasActiveChat)
        let wideEventInstrumentation = DefaultDuckAIWideEventInstrumentation(
            wideEvent: AppDependencyProvider.shared.wideEvent
        )
        self.duckAIWideEventInstrumentation = wideEventInstrumentation
        self.coordinator = UnifiedToggleInputCoordinator(
            host: .contextualChat,
            isToggleEnabled: false,
            isFireTab: isFireTab,
            contextualStartsPreSubmit: contextualStartsPreSubmit,
            lastUsedModelProvider: lastUsedModelProvider,
            duckAIWideEventInstrumentation: wideEventInstrumentation,
            duckAIWideEventFlowScope: duckAIWideEventFlowScope
        )
        // Immediate pre-submit: a carried-over attachment hasn't been delivered yet (it rides the
        // first prompt), so seed the chip as pending → visible, matching the legacy native chip.
        let seedDeliveryState: PageContextAttachmentDeliveryState =
            (contextualStartsPreSubmit && initialAttachedContext != nil) ? .pendingSubmit : initialAttachmentDeliveryState
        self.chipViewModel = UnifiedToggleInputPageContextChipViewModel(
            originatingURLPublisher: originatingURLPublisher,
            initialAttachedContext: initialAttachedContext,
            initialAttachmentDeliveryState: seedDeliveryState,
            isAutoAttachEnabled: isAutoAttachEnabled
        )
        coordinator.viewController.bindPageContextChip(to: chipViewModel)
        coordinator.hostAdapter = hostAdapter
        chipViewModel.onAttachActionRequested = { [weak self] url in
            self?.handleChipAttachRequest(originatingURL: url)
        }
        chipViewModel.onRemoveActionRequested = { [weak self] in
            self?.handleChipRemoveRequest()
        }

        Logger.contextualUTI.debug("UTIHost init — carryOver=\(initialAttachedContext != nil, privacy: .public) auto=\(isAutoAttachEnabled(), privacy: .public)")

        coordinator.intentPublisher
            .sink { [weak self] _ in
                self?.applyCurrentRenderState()
            }
            .store(in: &cancellables)

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
                Logger.contextualUTI.debug("UTIHost didFinish (post-replay) → \(url?.shortDescription ?? "nil", privacy: .private)")
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
                Logger.contextualUTI.info("Auto-attach on page load — triggering for \(url.shortDescription, privacy: .private)")
                self.handleChipAttachRequest(originatingURL: url)
            }
            .store(in: &cancellables)

        // The host receives the first (unbound) UTI submit through the coordinator delegate; once
        // bound, subsequent prompts go direct. Legacy/restored hosts bind immediately, so the
        // delegate submit path never fires for them.
        coordinator.delegate = self
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
        lastKnownUserScript = userScript
        // Wire the page-context provider + submission callback right away — safe pre-submit, and
        // subsequent (bound) prompts pull their context from the provider.
        userScript.attachedPageContextProvider = { [weak self] in
            self?.chipViewModel.pendingAttachedContextData
        }
        userScript.onPromptSubmitted = { [weak self] in
            self?.chipViewModel.markPromptSubmitted()
        }

        // Immediate-UTI fresh chat: defer the coordinator bind until the first submit so that first
        // prompt takes the unbound → web-VC-queue path (a bound first submit would skip the
        // frontend-state flip → invisible chat). Legacy/restored hosts bind immediately.
        guard startsPreSubmit, !hasDeliveredFirstPrompt else {
            commitBind(to: userScript)
            return
        }
        Logger.contextualUTI.info("Deferring coordinator bind until first submit (pre-submit immediate UTI)")
        pendingUserScriptToBind = userScript
    }

    private func commitBind(to userScript: AIChatUserScript) {
        Logger.contextualUTI.info("Binding coordinator to AIChatUserScript")
        isBoundToUserScript = true
        let chatID = userScript.webView?.url?.duckAIChatID
        coordinator.bindToTab(userScript, hasExistingChat: hasActiveChat() || chatID != nil)
        if let chatID {
            coordinator.restoreLastUsedModel(forChatID: chatID)
        }
    }

    /// Binds the user script stashed during the pre-submit window (called right after the first submit).
    /// No-op if the web view hasn't installed its user script yet — a later `bindToUserScript` will
    /// bind immediately because `hasDeliveredFirstPrompt` is now set.
    private func commitDeferredBindIfNeeded() {
        guard let userScript = pendingUserScriptToBind else { return }
        pendingUserScriptToBind = nil
        commitBind(to: userScript)
    }

    /// Returns the persistent host to a clean pre-submit state for a new chat (New-Chat / session
    /// timeout), reusing the same sheet + web view. Unbinds the coordinator so the next first prompt
    /// takes the unbound → flip path (a bound first submit would skip the frontend-state flip and the
    /// chat would never become visible), re-arms the deferred bind against the still-alive user
    /// script, resets the chip, and restores the expanded pre-submit bar (keyboard down).
    func prepareForNewChat() {
        coordinator.unbind()
        isBoundToUserScript = false
        hasDeliveredFirstPrompt = false
        pendingUserScriptToBind = lastKnownUserScript
        chipViewModel.clearAttached()
        coordinator.showExpanded(activatesInput: false)
        Logger.contextualUTI.info("Host reset for new chat — unbound, re-armed deferred bind")
    }

    /// Called when the web view fails to load while a first prompt is queued for delivery. The web
    /// VC queue is the sole first-prompt buffer, so a failed load would strand it — recover to a
    /// clean pre-submit state (via the sheet) so the user can retry.
    func firstPromptDeliveryFailed() {
        Logger.contextualUTI.error("First prompt delivery failed (page load) — recovering to pre-submit")
        onFirstPromptFailed?()
    }

    func observeChatUpdates(_ publisher: AnyPublisher<String, Never>) {
        coordinator.observeChatUpdates(publisher)
    }

    func markPromptSubmitted() {
        chipViewModel.markPromptSubmitted()
    }

    private var externalContextDeliveryState: PageContextAttachmentDeliveryState {
        // Immediate pre-submit: context collected on sheet open (via the external publisher) rides
        // the first prompt, so show the chip as pending — parity with the legacy native chip and the
        // manual-attach / post-nav paths, which are already pending. Without this, the sheet-open
        // auto-attach would arrive `.delivered` and the chip would be silently hidden pre-submit.
        if startsPreSubmit && !hasDeliveredFirstPrompt {
            return .pendingSubmit
        }
        // These states can differ during preload/restore: the user script may be bound before
        // `sessionState` records an active chat, while restored chats may be active before bind.
        return isBoundToUserScript || hasActiveChat() ? .pendingSubmit : .delivered
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
            applyCurrentRenderState()
            contextualChatViewController.view.layoutIfNeeded()
        }
        Logger.contextualUTI.info("Installed at bottom of contextual chat")
    }

    /// Immediate-UTI path: mounts the persistent UTI at the sheet level so it outlives the
    /// presubmission→postsubmission content swap. Returns the UTI view so the sheet can anchor its
    /// content above it. Mounted expanded but keyboard-down (parity); the chat web view is set later
    /// via `setContextualChatViewController`, and binding is deferred until the first submit.
    @discardableResult
    func mountAtSheetLevel(in sheetViewController: UIViewController) -> UIView {
        coordinator.attachmentPresentingViewController = sheetViewController
        UIView.performWithoutAnimation {
            sheetViewController.addChild(coordinator.viewController)
            sheetViewController.view.addSubview(coordinator.viewController.view)
            coordinator.viewController.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                coordinator.viewController.view.leadingAnchor.constraint(equalTo: sheetViewController.view.leadingAnchor),
                coordinator.viewController.view.trailingAnchor.constraint(equalTo: sheetViewController.view.trailingAnchor),
                coordinator.viewController.view.bottomAnchor.constraint(equalTo: sheetViewController.view.keyboardLayoutGuide.topAnchor),
            ])
            coordinator.viewController.didMove(toParent: sheetViewController)
            coordinator.showExpanded(activatesInput: false)
            applyCurrentRenderState()
            sheetViewController.view.layoutIfNeeded()
        }
        Logger.contextualUTI.info("Mounted UTI at sheet level (immediate-UTI)")
        return coordinator.viewController.view
    }

    /// Sets the chat web view the host pushes page context into / binds to, without mounting the UTI
    /// inside it (sheet-level mount path).
    func setContextualChatViewController(_ webViewController: AIChatContextualWebViewController) {
        self.contextualChatViewController = webViewController
    }

    private func applyCurrentRenderState() {
        coordinator.viewController.apply(coordinator.computeRenderState().viewConfig, animated: false)
        contextualChatViewController?.view.layoutIfNeeded()
    }
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

// MARK: - UnifiedToggleInputDelegate

extension AIChatContextualUTIHost: UnifiedToggleInputDelegate {

    /// The first (unbound) UTI prompt lands here; subsequent prompts go direct via the bound user
    /// script. Flips the session into an active chat, freezes the attached page context, delivers
    /// the rich payload into the web view's readiness queue, then binds so later prompts skip this.
    func unifiedToggleInputDidSubmitPrompt(_ prompt: String,
                                           modelId: String?,
                                           tools: [AIChatRAGTool]?,
                                           reasoningEffort: AIChatReasoningEffort?,
                                           images: [AIChatNativePrompt.NativePromptImage]?,
                                           files: [AIChatNativePrompt.NativePromptFile]?) {
        // Gate a rapid re-submit during the loading/bind window — the web view queue holds one
        // prompt, so a second would overwrite the first. Once bound, prompts skip this path entirely.
        guard !hasDeliveredFirstPrompt else {
            Logger.contextualUTI.info("Ignoring UTI re-submit before first prompt delivered")
            return
        }
        hasDeliveredFirstPrompt = true

        // Flip session state (native→web swap + expand) and freeze the page context attached at
        // flip time — the chip can change during the async swap.
        let frozenContext = onFirstPromptSubmitted?() ?? nil
        Logger.contextualUTI.info("Delivering first UTI prompt — hasContext=\(frozenContext != nil, privacy: .public) model=\(modelId ?? "nil", privacy: .public)")

        contextualChatViewController?.submitPrompt(
            prompt,
            images: images,
            files: files,
            modelId: modelId,
            tools: tools,
            reasoningEffort: reasoningEffort,
            pageContext: frozenContext
        )

        commitDeferredBindIfNeeded()
    }

    func unifiedToggleInputDidChangeHeight() {
        // The sheet-level mount is bottom-anchored to the keyboard guide and the content above
        // re-anchors to the UTI's top, so height changes are resolved by constraints — no explicit
        // container-height recompute (that's an omnibar concern). Kept a no-op to leave the legacy
        // embedded host byte-for-byte unchanged.
    }

    // Remaining actions are omnibar-only surfaces; the contextual sheet never presents them.
    func unifiedToggleInputDidSubmitQuery(_ query: String) {}
    func unifiedToggleInputDidRequestVoiceSearch() {}
    func unifiedToggleInputDidRequestAIVoiceChat() {}
    func unifiedToggleInputDidRequestAIChat(prefilledText: String) {}
    func unifiedToggleInputDidCommitMode(_ mode: TextEntryMode) {}
    func unifiedToggleInputDidRequestFire() {}
    func unifiedToggleInputDidRequestAppMenu() {}
}

/// Live view of the contextual chat's submission phase for the coordinator's model-chip logic.
/// Reads `hasActiveChat` on each access so it reflects the current phase even after a user-script
/// rebind (which resets `hasSubmittedPrompt` but not the chat's active state).
private final class ContextualChatHostAdapter: UnifiedToggleInputHostAdapter {
    private let hasActiveChat: () -> Bool

    init(hasActiveChat: @escaping () -> Bool) {
        self.hasActiveChat = hasActiveChat
    }

    var isPreSubmitPhase: Bool { !hasActiveChat() }
}
