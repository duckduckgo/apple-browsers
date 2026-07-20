//
//  AIChatContextualChatSessionState.swift
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
import BrowserServicesKit
import Combine
import Common
import Core
import Foundation
import os.log
import PrivacyConfig
import UIKit

// MARK: - State Enums

/// Manages the lifecycle state of the frontend chat
enum FrontendChatState: CustomStringConvertible {
    case noChat
    case chatWithoutInitialContext
    case chatWithInitialContext
    case restoredChat

    var description: String {
        switch self {
        case .noChat: return "noChat"
        case .chatWithoutInitialContext: return "chatWithoutInitialContext"
        case .chatWithInitialContext: return "chatWithInitialContext"
        case .restoredChat: return "restoredChat"
        }
    }
}

/// Manages the current state of the context chip
enum ChipState: CustomStringConvertible, Equatable {
    case placeholder
    case attached(AIChatPageContext)

    var description: String {
        switch self {
        case .placeholder: return "placeholder"
        case .attached: return "attached"
        }
    }
}

enum SuggestionsLoadState: Equatable {
    case loading
    case loaded
}

struct SheetViewState {
    let content: ContentMode
    let isExpandButtonEnabled: Bool
    let shouldShowNewChatButton: Bool
    let chipState: ChipState
    let quickActions: [AIChatContextualQuickAction]
    let suggestions: [ContextualSuggestedPrompt]
    let suggestionsLoadState: SuggestionsLoadState

    enum ContentMode {
        case nativeInput
        case webView(restoreURL: URL?)
    }
}

enum SheetEffect {
    case submitPrompt(prompt: String, context: AIChatPageContextData?)
    case reloadWebView
    case deliverPageContext(AIChatPageContextData?, targets: PageContextDeliveryTargets)
    case clearPrompt
}

struct PageContextDeliveryTargets: OptionSet {
    let rawValue: Int

    static let utiChip = PageContextDeliveryTargets(rawValue: 1 << 0)
    static let frontendBridge = PageContextDeliveryTargets(rawValue: 1 << 1)
    static let utiAttachAffordance = PageContextDeliveryTargets(rawValue: 1 << 2)
}

// MARK: - Session State

/// Single source of truth for all contextual chat session state.
@MainActor
final class AIChatContextualChatSessionState {

    // MARK: - Dependencies

    private let aiChatSettings: AIChatSettingsProvider
    private let pixelHandler: AIChatContextualModePixelFiring
    private let featureFlagger: FeatureFlagger
    private let suggestedPromptsProvider: ContextualSuggestedPromptsProviding

    /// When false, page-context quick actions are suppressed. Fail-open (always attachable) by default.
    private let isCurrentPageAttachable: () -> Bool

    // MARK: - Core State (private(set) - mutations happen via methods)

    private(set) var frontendState: FrontendChatState = .noChat
    private(set) var chipState: ChipState = .placeholder
    private(set) var contextualChatURL: URL?
    private(set) var latestContext: AIChatPageContext?

    /// URL included in the last submitted prompt with no navigation since; used to spot a stale auto-attach echo.
    private var deliveredContextURLWithNoNavigationSince: URL?

    @Published private(set) var viewState = SheetViewState(
        content: .nativeInput,
        isExpandButtonEnabled: true,
        shouldShowNewChatButton: false,
        chipState: .placeholder,
        quickActions: [.summarize],
        suggestions: [],
        suggestionsLoadState: .loaded
    )

    let effects = PassthroughSubject<SheetEffect, Never>()

    /// Tracks whether the user explicitly downgraded from attached to placeholder
    private(set) var userDowngradedToPlaceholder = false
    private var wasAutoAttachEnabled: Bool
    private var isUnifiedToggleInputActive = false

    // MARK: - Internal Flags

    /// Flag to track a manual attach flow in progress
    private var isManualAttachInProgress = false
    private var isManualAttachFromFrontend = false

    /// Flag to prevent duplicate navigation processing
    private var isProcessingNavigation = false

    private var pendingSignalsOnlyCollection = false

    private(set) var suggestionsLoadState: SuggestionsLoadState = .loaded
    private(set) var suggestions: [ContextualSuggestedPrompt] = []
    private var suggestionsResolveTask: Task<Void, Never>?
    private var suggestionsTimeoutTask: Task<Void, Never>?

    // MARK: - Initialization

    init(aiChatSettings: AIChatSettingsProvider,
         pixelHandler: AIChatContextualModePixelFiring,
         featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         suggestedPromptsProvider: ContextualSuggestedPromptsProviding = DefaultContextualSuggestedPromptsProvider(),
         isCurrentPageAttachable: @escaping () -> Bool = { true }) {
        self.aiChatSettings = aiChatSettings
        self.pixelHandler = pixelHandler
        self.featureFlagger = featureFlagger
        self.suggestedPromptsProvider = suggestedPromptsProvider
        self.isCurrentPageAttachable = isCurrentPageAttachable
        self.wasAutoAttachEnabled = aiChatSettings.isAutomaticContextAttachmentEnabled
        rebuildViewState()
    }

    // MARK: - Derived Properties (computed, no storage)

    /// Whether there's an active chat session (frontend is loaded)
    var hasActiveChat: Bool {
        frontendState != .noChat
    }

    /// Whether the new chat button should be visible
    var isNewChatButtonVisible: Bool {
        hasActiveChat
    }

    /// Whether the expand button should be enabled
    var isExpandEnabled: Bool {
        frontendState == .noChat || contextualChatURL != nil
    }

    /// Whether showing native input (no active chat)
    var isShowingNativeInput: Bool {
        frontendState == .noChat
    }

    /// Whether context is available for display
    var hasContext: Bool {
        latestContext != nil
    }

    /// User-attached context (nil if opted out / never attached). Unlike `latestContext`,
    /// this respects X-tap downgrades — `latestContext` keeps the last collected payload regardless.
    var intendedAttachedContext: AIChatPageContext? {
        if case .attached(let context) = chipState { return context }
        return nil
    }

    /// Whether automatic context collection is enabled
    var shouldAutoCollectContext: Bool {
        aiChatSettings.isAutomaticContextAttachmentEnabled
    }

    var supportsMultipleContexts: Bool {
        featureFlagger.isFeatureOn(.multiplePageContexts)
    }

    var showsSuggestionsStartSurface: Bool {
        featureFlagger.isFeatureOn(.contextualSuggestedPrompts)
    }

    private var hasUserOptedOutOfContext: Bool {
        userDowngradedToPlaceholder
    }

    // MARK: - Frontend Chat State Transitions

    /// Call when user submits a prompt from native input
    func handlePromptSubmission(_ prompt: String, url: URL? = nil) {
        guard frontendState != .restoredChat else {
            Logger.aiChat.debug("[SessionState] Chat start request ignored - preserving .restoredChat state")
            return
        }

        let contextData: AIChatPageContextData?
        switch chipState {
        case .attached(let context):
            contextData = context.contextData
            frontendState = .chatWithInitialContext
            deliveredContextURLWithNoNavigationSince = URL(string: context.contextData.url)
            pixelHandler.firePromptSubmittedWithContext()
            Logger.aiChat.debug("[SessionState] Chat started WITH initial context (chip was attached)")
        case .placeholder:
            contextData = nil
            frontendState = .chatWithoutInitialContext
            pixelHandler.firePromptSubmittedWithoutContext()
            Logger.aiChat.debug("[SessionState] Chat started WITHOUT initial context (chip was placeholder)")
        }

        if let url = url {
            contextualChatURL = url
        }

        rebuildViewState()
        emit(.submitPrompt(prompt: prompt, context: contextData))
    }

    /// Call when the first prompt is submitted through contextual UTI. The UTI coordinator
    /// delivers the prompt, so this only performs the contextual session transition and pixels.
    func beginChatForUTISubmission() {
        guard frontendState != .restoredChat else {
            Logger.aiChat.debug("[SessionState] UTI chat start request ignored - preserving .restoredChat state")
            return
        }

        switch chipState {
        case .attached(let context):
            frontendState = .chatWithInitialContext
            deliveredContextURLWithNoNavigationSince = URL(string: context.contextData.url)
            pixelHandler.firePromptSubmittedWithContext()
            Logger.aiChat.debug("[SessionState] UTI chat started WITH initial context")
        case .placeholder:
            frontendState = .chatWithoutInitialContext
            pixelHandler.firePromptSubmittedWithoutContext()
            Logger.aiChat.debug("[SessionState] UTI chat started WITHOUT initial context")
        }

        rebuildViewState()
    }

    /// Call when starting a new chat (resetting frontend)
    func resetToNoChat() {
        frontendState = .noChat
        chipState = .placeholder
        contextualChatURL = nil
        deliveredContextURLWithNoNavigationSince = nil
        userDowngradedToPlaceholder = false
        isManualAttachInProgress = false
        isManualAttachFromFrontend = false
        isProcessingNavigation = false
        pendingSignalsOnlyCollection = false
        suggestionsResolveTask?.cancel()
        suggestionsTimeoutTask?.cancel()
        suggestions = []
        suggestionsLoadState = .loaded
        pixelHandler.endManualAttach()
        rebuildViewState()
        emit(.clearPrompt)
        Logger.aiChat.debug("[SessionState] Reset to no chat")
    }

    /// Updates the contextual chat URL (for persistence/expansion)
    func updateContextualChatURL(_ url: URL?) {
        contextualChatURL = url
        rebuildViewState()

        if let url {
            Logger.aiChat.debug("[SessionState] Updated contextual chat URL: \(url.shortDescription)")
        } else {
            Logger.aiChat.debug("[SessionState] Cleared contextual chat URL")
        }
    }

    func restoreChat(with url: URL) {
        contextualChatURL = url
        frontendState = .restoredChat
        rebuildViewState()
        Logger.aiChat.debug("[SessionState] Restored chat URL: \(url.shortDescription)")
    }

    // MARK: - Chip State Transitions

    /// Handles chip removal by user (X button tap)
    func handleChipRemoval() -> Bool {
        guard case .attached = chipState else { return false }

        downgradeToPlaceholder()
        return true
    }

    /// Downgrades an attached chip to placeholder state.
    func downgradeToPlaceholder() {
        guard case .attached(let context) = chipState else { return }
        chipState = .placeholder
        userDowngradedToPlaceholder = true
        pixelHandler.firePageContextRemovedNative()
        rebuildViewState()
        pushDetachedContextToSuggestionsSurfaceIfNeeded(context)
        emitDeliveryIfNeeded(nil)
        Logger.aiChat.debug("[SessionState] Chip downgraded to placeholder via coordinator")
    }

    // MARK: - Context Management

    /// Begin a manual attach operation (user tapped "Attach Page")
    func beginManualAttach(fromFrontend: Bool = false) {
        Logger.aiChat.debug("[SessionState] Manual attach requested (frontend: \(fromFrontend))")
        pixelHandler.beginManualAttach()
        isManualAttachInProgress = true
        isManualAttachFromFrontend = fromFrontend
    }

    /// Notify that page navigation occurred
    func notifyPageChanged(pageURL: URL? = nil) {
        Logger.aiChat.debug("[SessionState] Page navigation detected")
        isProcessingNavigation = true
        // A real navigation means any subsequent context update is fresh, even if it later
        // resolves to a URL that was already submitted (e.g. the user navigated away and back).
        deliveredContextURLWithNoNavigationSince = nil
        if shouldAutoCollectContext, userDowngradedToPlaceholder {
            userDowngradedToPlaceholder = false
            Logger.aiChat.debug("[SessionState] Page navigation cleared temporary context removal")
        }
    }

    /// Re-evaluate the sheet view state (e.g. "Ask about page" quick action) for the current page's
    /// attachability. Driven by the URL-change signal so it stays in sync on back/forward navigation.
    func refreshForCurrentPage() {
        rebuildViewState()
    }

    func updateUnifiedToggleInputActive(_ isActive: Bool, isImmediateContextual _: Bool = false) {
        isUnifiedToggleInputActive = isActive
        rebuildViewState()
    }

    func shouldTriggerAutoCollect(for pageURL: URL? = nil) -> Bool {
        guard shouldAutoCollectContext else { return false }
        guard !hasUserOptedOutOfContext else { return false }
        guard let pageURL else { return true }
        guard let attachedContext = intendedAttachedContext,
              URL(string: attachedContext.contextData.url) == pageURL else {
            return true
        }
        return false
    }

    /// Sends a null context as a navigation signal.
    /// Used when auto-collect is OFF but multiple contexts are supported,
    /// so the FE can show the "Add page content" button for the new page.
    func notifyFrontendOfMultiContextNavigation() {
        guard supportsMultipleContexts else { return }

        var targets: PageContextDeliveryTargets = []
        if shouldDeliverToFrontendBridge(nil) {
            targets.insert(.frontendBridge)
        }
        if shouldShowUTIAttachAffordanceForMultiContextNavigation() {
            targets.insert(.utiAttachAffordance)
        }

        guard !targets.isEmpty else { return }
        emit(.deliverPageContext(nil, targets: targets))
        Logger.aiChat.debug("[SessionState] Sent null context navigation signal")
    }

    /// Clear the navigation processing flag (called when collection can't start)
    func clearProcessingNavigationFlag() {
        isProcessingNavigation = false
        Logger.aiChat.debug("[SessionState] Cleared processing navigation flag")
    }

    /// Refresh cached auto-attach setting and clear user downgrade if toggled on.
    func refreshAutoAttachSetting() {
        let isEnabled = shouldAutoCollectContext
        if isEnabled && !wasAutoAttachEnabled {
            userDowngradedToPlaceholder = false
            Logger.aiChat.debug("[SessionState] Auto-attach enabled - cleared user downgrade")
        }
        wasAutoAttachEnabled = isEnabled
    }

    func markPendingSignalsOnlyCollection() {
        pendingSignalsOnlyCollection = true
        beginLoadingSuggestions()
    }

    func beginLoadingSuggestions() {
        guard featureFlagger.isFeatureOn(.contextualSuggestedPrompts), !hasActiveChat else { return }
        suggestionsResolveTask?.cancel()
        suggestions = []
        suggestionsLoadState = .loading
        rebuildViewState()
        startSuggestionsTimeout()
    }

    /// Updates the latest page context and determines attach behavior based on internal state.
    func updateContext(_ context: AIChatPageContext?) {
        resolveSuggestionsIfLoading(from: context)

        if pendingSignalsOnlyCollection {
            pendingSignalsOnlyCollection = false
            isProcessingNavigation = false
            if let context {
                let payload = signalsOnlyPayload(from: context.contextData)
                emit(.deliverPageContext(payload, targets: .frontendBridge))
            }
            return
        }

        guard let context = context else {
            guard shouldProcessNilContextUpdate else {
                Logger.aiChat.debug("[SessionState] Ignoring nil context update without active collection")
                return
            }
            Logger.aiChat.debug("[SessionState] Context collection returned nil - clearing context and downgrading to placeholder")
            latestContext = nil
            chipState = .placeholder
            cleanupFlags()
            rebuildViewState()
            return
        }

        latestContext = context
        Logger.aiChat.debug("[SessionState] Context updated: \(context.title)")

        if isManualAttachInProgress {
            handleManualAttach(context)
        } else if shouldAutoCollectContext {
            handleAutoAttach(context)
        } else {
            Logger.aiChat.debug("[SessionState] Context updated without chip change (auto-attach OFF)")
        }

        if isProcessingNavigation {
            pixelHandler.firePageContextUpdatedOnNavigation(url: context.contextData.url)
            isProcessingNavigation = false
        }

        rebuildViewState()
    }

    /// Cancels an in-progress manual attach operation.
    func cancelManualAttach() {
        guard isManualAttachInProgress else { return }
        isManualAttachInProgress = false
        isManualAttachFromFrontend = false
        pixelHandler.endManualAttach()
        Logger.aiChat.debug("[SessionState] Manual attach cancelled")
    }

    /// Ends in-flight attach work when a sheet session ends.
    func handleSheetDismissed() {
        if isManualAttachInProgress {
            isManualAttachInProgress = false
            isManualAttachFromFrontend = false
            pixelHandler.endManualAttach()
        }

        rebuildViewState()
    }

    /// Clears manual context when reopening on a different page.
    /// Auto-attach-off manual context remains sticky while the sheet is open, including across
    /// navigation and same-page reopen, but it should not leak into another page's sheet session.
    func clearManualContextIfStale(for currentPageURL: URL?) -> Bool {
        guard !shouldAutoCollectContext,
              case .attached(let context) = chipState,
              let currentPageURL,
              let attachedURL = URL(string: context.contextData.url),
              !attachedURL.equals(currentPageURL, by: .sameDocument) else {
            return false
        }

        chipState = .placeholder
        latestContext = nil
        userDowngradedToPlaceholder = false
        rebuildViewState()
        Logger.aiChat.debug("[SessionState] Cleared stale manual context on sheet present")
        return true
    }

    /// Requests a WebView reload. ViewController should observe `effects`.
    func requestWebViewReload() {
        emit(.reloadWebView)
    }

    func shouldDeliverToUTIChip(_ context: AIChatPageContextData?) -> Bool {
        guard isUnifiedToggleInputActive else { return false }
        guard context != nil || hasActiveChat || userDowngradedToPlaceholder else { return false }
        return true
    }

    /// `.delivered` when `context` is a stale echo of the already-submitted page (chip stays hidden); else `.pendingSubmit`.
    func utiChipDeliveryState(forDelivering context: AIChatPageContextData) -> PageContextAttachmentDeliveryState {
        isStaleEchoOfDeliveredContext(context) ? .delivered : .pendingSubmit
    }

    /// Marks the attached context delivered on submit so it stops riding later prompts and the chip hides.
    func markUTIContextDelivered() {
        guard case .attached(let context) = chipState else { return }
        deliveredContextURLWithNoNavigationSince = URL(string: context.contextData.url)
        emitDeliveryIfNeeded(context.contextData)
    }

    func shouldDeliverToFrontendBridge(_ context: AIChatPageContextData?) -> Bool {
        if isUnifiedToggleInputActive, context != nil {
            Logger.aiChat.debug("[SessionState] shouldDeliverToFrontendBridge=false (non-nil context delivered to UTI)")
            return false
        }

        let shouldDeliver: Bool
        switch frontendState {
        case .chatWithoutInitialContext, .restoredChat:
            shouldDeliver = true
        case .chatWithInitialContext:
            shouldDeliver = supportsMultipleContexts
        case .noChat:
            shouldDeliver = false
        }
        Logger.aiChat.debug("[SessionState] shouldDeliverToFrontendBridge=\(shouldDeliver) (frontendState=\(self.frontendState), multipleContexts=\(self.supportsMultipleContexts), uti=\(self.isUnifiedToggleInputActive))")
        return shouldDeliver
    }

    func shouldShowUTIAttachAffordanceForMultiContextNavigation() -> Bool {
        isUnifiedToggleInputActive && hasActiveChat && !shouldAutoCollectContext
    }

}

// MARK: - Private

private extension AIChatContextualChatSessionState {

    func handleManualAttach(_ context: AIChatPageContext) {
        if isShowingNativeInput || isUnifiedToggleInputActive {
            chipState = .attached(context)
            userDowngradedToPlaceholder = false
            // A manual attach is always fresh: clear the delivered marker so it is not read as a stale echo.
            deliveredContextURLWithNoNavigationSince = nil
            Logger.aiChat.debug("[SessionState] Manually attached context")
        }

        emitDeliveryIfNeeded(context.contextData)

        if isManualAttachFromFrontend {
            pixelHandler.firePageContextManuallyAttachedFrontend()
        } else {
            pixelHandler.firePageContextManuallyAttachedNative()
        }

        isManualAttachInProgress = false
        isManualAttachFromFrontend = false
        pixelHandler.endManualAttach()
    }

    func handleAutoAttach(_ context: AIChatPageContext) {
        var didUpdateAttachment = false

        if isShowingNativeInput || isUnifiedToggleInputActive {
            switch chipState {
            case .placeholder:
                if shouldAllowAutomaticUpgrade() {
                    chipState = .attached(context)
                    userDowngradedToPlaceholder = false
                    didUpdateAttachment = true
                    Logger.aiChat.debug("[SessionState] Auto-attached context (setting ON)")
                    pixelHandler.firePageContextAutoAttached()
                }

            case .attached:
                if isStaleEchoOfDeliveredContext(context.contextData) {
                    Logger.aiChat.debug("[SessionState] Ignoring stale auto-attach echo for already-delivered context")
                } else {
                    chipState = .attached(context)
                    didUpdateAttachment = true
                    Logger.aiChat.debug("[SessionState] Updated attached context (setting ON)")
                }
            }
        } else {
            Logger.aiChat.debug("[SessionState] Context updated on navigation (WebView active, chip not updated)")
        }

        if didUpdateAttachment || shouldDeliverToFrontendBridge(context.contextData) {
            emitDeliveryIfNeeded(context.contextData)
        }
    }

    /// Whether `context` is a passive same-page re-collection already submitted with no navigation since.
    func isStaleEchoOfDeliveredContext(_ context: AIChatPageContextData) -> Bool {
        guard let deliveredContextURLWithNoNavigationSince,
              let contextURL = URL(string: context.url) else { return false }
        return contextURL.equals(deliveredContextURLWithNoNavigationSince, by: .sameDocument)
    }

    func cleanupFlags() {
        Logger.aiChat.debug("[SessionState] Context update - nil result")

        if isManualAttachInProgress {
            isManualAttachInProgress = false
            pixelHandler.endManualAttach()
        }
        if isProcessingNavigation {
            isProcessingNavigation = false
        }
    }

    func shouldAllowAutomaticUpgrade() -> Bool {
        return !userDowngradedToPlaceholder
    }

    func pushDetachedContextToSuggestionsSurfaceIfNeeded(_ context: AIChatPageContext) {
        guard frontendState == .noChat, showsSuggestionsStartSurface else { return }
        let payload = signalsOnlyPayload(from: context.contextData)
        emit(.deliverPageContext(nil, targets: .frontendBridge))
        emit(.deliverPageContext(payload, targets: .frontendBridge))
    }

    /// Strips page content, keeping metadata + page-type signals so the FE renders page-tailored suggestions without attaching content.
    func signalsOnlyPayload(from context: AIChatPageContextData) -> AIChatPageContextData {
        AIChatPageContextData(
            title: context.title,
            favicon: [],
            url: context.url,
            content: "",
            truncated: false,
            fullContentLength: 0,
            attachable: true,
            pageTypeSignals: context.pageTypeSignals,
            attached: false
        )
    }

    var shouldProcessNilContextUpdate: Bool {
        shouldAutoCollectContext || isManualAttachInProgress || isProcessingNavigation
    }

    private func resolveQuickActions() -> [AIChatContextualQuickAction] {
        // No "Ask about page" for pages that can't be attached — it would no-op on tap.
        guard isCurrentPageAttachable() else { return [] }
        if featureFlagger.isFeatureOn(.contextualSuggestedPrompts) {
            switch chipState {
            case .placeholder: return [.askAboutPage]
            case .attached: return []
            }
        }
        switch chipState {
        case .placeholder: return [.askAboutPage]
        case .attached: return [.summarizePage]
        }
    }

    func startSuggestionsTimeout() {
        suggestionsTimeoutTask?.cancel()
        let timeout = AIChatContextualSheetCoordinator.contextualContextCollectionTimeout
        suggestionsTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.resolveSuggestionsIfLoading(from: nil)
        }
    }

    func resolveSuggestionsIfLoading(from context: AIChatPageContext?) {
        guard suggestionsLoadState == .loading,
              featureFlagger.isFeatureOn(.contextualSuggestedPrompts),
              !hasActiveChat else { return }

        suggestionsTimeoutTask?.cancel()

        let input = ResolvePageSuggestionsInput(
            pageTypeSignals: context?.contextData.pageTypeSignals,
            url: context?.contextData.url,
            uiLocale: Locale.current.identifier
        )

        suggestionsResolveTask?.cancel()
        suggestionsResolveTask = Task { [weak self] in
            guard let resolved = await self?.suggestedPromptsProvider.resolveSuggestions(input) else { return }
            guard let self, !Task.isCancelled else { return }
            self.suggestions = resolved
            self.suggestionsLoadState = .loaded
            self.rebuildViewState()
        }
    }

    func rebuildViewState() {
        let content: SheetViewState.ContentMode
        switch frontendState {
        case .noChat:
            content = .nativeInput
        case .chatWithInitialContext, .chatWithoutInitialContext, .restoredChat:
            content = .webView(restoreURL: contextualChatURL)
        }

        viewState = SheetViewState(
            content: content,
            isExpandButtonEnabled: frontendState == .noChat || contextualChatURL != nil,
            shouldShowNewChatButton: frontendState != .noChat,
            chipState: chipState,
            quickActions: resolveQuickActions(),
            suggestions: suggestions,
            suggestionsLoadState: suggestionsLoadState
        )
    }

    func emit(_ effect: SheetEffect) {
        effects.send(effect)
    }

    func emitDeliveryIfNeeded(_ context: AIChatPageContextData?) {
        var targets: PageContextDeliveryTargets = []
        if shouldDeliverToUTIChip(context) {
            targets.insert(.utiChip)
        }
        if shouldDeliverToFrontendBridge(context) {
            targets.insert(.frontendBridge)
        }
        guard !targets.isEmpty else { return }
        emit(.deliverPageContext(context, targets: targets))
    }
}
