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
    /// URL of the context last confirmed delivered in a prompt — an auto-update for this same URL must not reopen the chip.
    private var lastDeliveredContextURL: URL?
    private var isBoundToUserScript = false
    /// Immediate-UTI fresh chat: keep the coordinator unbound until first submit so that prompt takes the unbound path.
    private let startsPreSubmit: Bool
    /// Set once the first UTI prompt is delivered; gates rapid re-submit and flips a deferred bind to immediate.
    private var hasDeliveredFirstPrompt = false
    /// User script stashed at `bindToUserScript` while pre-submit; bound after the first submit.
    private weak var pendingUserScriptToBind: AIChatUserScript?
    /// The web view's user script, remembered across binds so a New-Chat reset can re-arm the deferred bind.
    private weak var lastKnownUserScript: AIChatUserScript?
    /// Flip-only (native→web swap + expand); the host freezes the chip context itself, so this returns nothing.
    var onFirstPromptSubmitted: (() -> Void)?
    /// Fired whenever the chip's effective attachment changes, so `sessionState` can recompute its view state.
    var onAttachedContextChanged: (() -> Void)?
    /// Recover to a clean pre-submit sheet when the queued first prompt can't be delivered (page load failed).
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
        // Immediate pre-submit: a carried-over attachment rides the first prompt, so seed it pending → visible.
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

        // Page context is attached via the "Ask About Page" attach-menu item.
        coordinator.canAttachPageContext = { [weak self] in
            self?.chipViewModel.canAttachPageContext ?? false
        }
        coordinator.onAttachPageContextRequested = { [weak self] in
            self?.chipViewModel.tapToAttach()
        }
        chipViewModel.$canAttachPageContext
            .removeDuplicates()
            .sink { [weak self] _ in self?.coordinator.refreshAttachmentMenu() }
            .store(in: &cancellables)

        // Lets `sessionState` recompute its view state whenever the chip's effective attachment changes.
        chipViewModel.$state
            .dropFirst()
            .sink { [weak self] _ in self?.onAttachedContextChanged?() }
            .store(in: &cancellables)

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
                    // The same page continuing to load/settle after its context was already delivered must not reopen the chip — only a genuine navigation (handled by the didFinish listener below) should.
                    let alreadyDeliveredThisPage = URL(string: context.contextData.url) != nil && URL(string: context.contextData.url) == self.lastDeliveredContextURL
                    self.chipViewModel.setAttached(context, deliveryState: alreadyDeliveredThisPage ? .delivered : self.externalContextDeliveryState)
                } else {
                    self.chipViewModel.clearAttached()
                }
            }
            .store(in: &cancellables)

        // `didFinish` (not `didCommit`) so the new page's DOM is ready when JS reads it — collecting at didCommit reads the outgoing page (off-by-one). `dropFirst` skips the sheet-open replay (the half-sheet is the attach/skip decision point); only subsequent navigations re-collect.
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
                // The user explicitly removed context this chat — respect that across navigation (don't silently re-attach); cleared by an explicit re-attach or a new chat.
                guard !self.suppressExternalContextUntilNextAttach else {
                    Logger.contextualUTI.debug("UTIHost didFinish skip — user removed context; not re-attaching on nav")
                    return
                }
                if let attached = self.chipViewModel.attachedContext,
                   URL(string: attached.contextData.url) == url {
                    Logger.contextualUTI.debug("UTIHost didFinish skip — already attached to same URL")
                    return
                }
                Logger.contextualUTI.info("Auto-attach on navigation — triggering for \(url.shortDescription, privacy: .private)")
                self.handleChipAttachRequest(originatingURL: url)
            }
            .store(in: &cancellables)

        // The host receives the first (unbound) UTI submit through the coordinator delegate; bound prompts go direct.
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
        // Wire the provider + submission callback right away — safe pre-submit; bound prompts read context from it.
        userScript.attachedPageContextProvider = { [weak self] in
            self?.chipViewModel.pendingAttachedContextData
        }
        userScript.onPromptSubmitted = { [weak self] in
            self?.recordDeliveryAndMarkSubmitted()
        }

        // Immediate-UTI fresh chat: defer the bind until first submit so that prompt takes the unbound path.
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

    /// Binds the user script stashed during the pre-submit window, called right after the first submit.
    private func commitDeferredBindIfNeeded() {
        guard let userScript = pendingUserScriptToBind else { return }
        pendingUserScriptToBind = nil
        commitBind(to: userScript)
    }

    /// Resets the reused host to a clean pre-submit state for a new chat: unbind, re-arm the deferred bind, reset chip, re-expand.
    func prepareForNewChat() {
        coordinator.unbind()
        isBoundToUserScript = false
        hasDeliveredFirstPrompt = false
        pendingUserScriptToBind = lastKnownUserScript
        // A new chat is a fresh start — clear any post-remove suppression from the prior chat so the new chat's auto-attach isn't silently dropped.
        suppressExternalContextUntilNextAttach = false
        lastDeliveredContextURL = nil
        chipViewModel.clearAttached()
        coordinator.showExpanded(activatesInput: false)
        Logger.contextualUTI.info("Host reset for new chat — unbound, re-armed deferred bind")
    }

    /// Web view failed to load while a first prompt was queued (the sole buffer) — recover to pre-submit for retry.
    func firstPromptDeliveryFailed() {
        Logger.contextualUTI.error("First prompt delivery failed (page load) — recovering to pre-submit")
        onFirstPromptFailed?()
    }

    func observeChatUpdates(_ publisher: AnyPublisher<String, Never>) {
        coordinator.observeChatUpdates(publisher)
    }

    /// Raises the keyboard / focuses the sheet-mounted UTI (mounted keyboard-down); used when a quick action attaches context and should hand off to typing.
    func activateInput() {
        coordinator.activateInput()
    }

    /// Clears the post-remove context suppression so a fresh externally-triggered attach reaches the chip. The sheet's "Ask about page" quick action collects via the page-context handler (not the chip's own attach path, which clears this itself), so without this the out-of-band listener would drop the re-collected context and the chip would never reappear.
    func clearExternalContextSuppression() {
        suppressExternalContextUntilNextAttach = false
    }

    func markPromptSubmitted() {
        recordDeliveryAndMarkSubmitted()
    }

    /// Records which page's context was just delivered, then marks the chip's attachment delivered.
    private func recordDeliveryAndMarkSubmitted() {
        lastDeliveredContextURL = chipViewModel.attachedContext.flatMap { URL(string: $0.contextData.url) }
        chipViewModel.markPromptSubmitted()
    }

    /// Routes a quick-action prompt through the same submit funnel as a typed UTI prompt, so it can't strand the coordinator unbound.
    func submitQuickActionPrompt(_ prompt: String) {
        coordinator.submitProgrammatic(text: prompt)
    }

    private var externalContextDeliveryState: PageContextAttachmentDeliveryState {
        // Immediate pre-submit: sheet-open context rides the first prompt, so show it pending (parity with manual/post-nav), not silently delivered.
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

    /// Immediate-UTI: mounts the persistent UTI at sheet level (expanded, keyboard-down) so it outlives the content swap; returns its view to anchor content above.
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

    /// Sets the chat web view the host pushes context into / binds to, without mounting the UTI inside it.
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

    /// The first (unbound) UTI prompt: flip the session, freeze the chip context, deliver the rich payload to the web-VC queue, then bind.
    func unifiedToggleInputDidSubmitPrompt(_ prompt: String,
                                           modelId: String?,
                                           tools: [AIChatRAGTool]?,
                                           reasoningEffort: AIChatReasoningEffort?,
                                           images: [AIChatNativePrompt.NativePromptImage]?,
                                           files: [AIChatNativePrompt.NativePromptFile]?) {
        // Gate a rapid re-submit during the loading/bind window — the web-VC queue holds only one prompt.
        guard !hasDeliveredFirstPrompt else {
            Logger.contextualUTI.info("Ignoring UTI re-submit before first prompt delivered")
            return
        }
        hasDeliveredFirstPrompt = true

        // Freeze the context from the chip (authoritative — matches the chip + bound prompts), before delivery marks it delivered.
        let frozenContext = chipViewModel.pendingAttachedContextData
        // Flip session state (native→web swap + expand).
        onFirstPromptSubmitted?()
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
        // No-op: the sheet-level mount is constraint-driven, so height changes need no explicit recompute (an omnibar concern).
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

/// Live submission-phase view for the coordinator's model-chip logic; reads `hasActiveChat` each access so it survives a rebind.
private final class ContextualChatHostAdapter: UnifiedToggleInputHostAdapter {
    private let hasActiveChat: () -> Bool

    init(hasActiveChat: @escaping () -> Bool) {
        self.hasActiveChat = hasActiveChat
    }

    var isPreSubmitPhase: Bool { !hasActiveChat() }
}
