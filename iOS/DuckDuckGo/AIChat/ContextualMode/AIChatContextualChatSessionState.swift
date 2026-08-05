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
import FeatureFlags_iOS

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
    /// Analytics-only metadata for the resolved suggestions; meaningful when `suggestionsLoadState == .loaded`.
    let suggestionsAreSmart: Bool
    let suggestionsPageType: SuggestionsPageType

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

    /// Images and files currently in the input. Lives in `UTIAttachmentController`, which the session
    /// state has no view of, so it is supplied from outside — and defaults to zero, which is correct for
    /// the basic native input (no attachment affordance) and for tests.
    ///
    /// Settable rather than an init parameter because the unified-input host that answers it is created
    /// after this object.
    var inputAttachmentCount: () -> Int = { 0 }

    // MARK: - Core State (private(set) - mutations happen via methods)

    private(set) var frontendState: FrontendChatState = .noChat
    private(set) var chipState: ChipState = .placeholder
    private(set) var contextualChatURL: URL?
    private(set) var latestContext: AIChatPageContext?

    /// Text selections attached from the page's selection menu, in attach order. Independent of
    /// `latestContext`: page context is *trimmed*, so a selection is not guaranteed to be inside it
    /// and replacing one with the other would lose content the user explicitly chose.
    private(set) var attachedSelections: [AIChatSelectionContextData] = []

    /// Title of the page the most recent selection came from. Distinct from
    /// `AIChatSelectionContextData.title`, which is the generic payload title ("Text selection").
    private(set) var attachedSelectionPageTitle: String?

    /// URL included in the last submitted prompt with no navigation since; used to spot a stale auto-attach echo.
    private var deliveredContextURLWithNoNavigationSince: URL?

    /// Which prompt-submitted pixel is owed once a conditional delivery is confirmed. See
    /// `beginChatForUTISubmission(deferringSubmissionPixel:)`.
    private enum DeferredSubmissionPixel {
        case withContext
        case withoutContext
    }
    private var deferredSubmissionPixel: DeferredSubmissionPixel?

    @Published private(set) var viewState = SheetViewState(
        content: .nativeInput,
        isExpandButtonEnabled: true,
        shouldShowNewChatButton: false,
        chipState: .placeholder,
        quickActions: [.summarize],
        suggestions: [],
        suggestionsLoadState: .loaded,
        suggestionsAreSmart: false,
        suggestionsPageType: .none
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
    private var suggestionsAreSmart = false
    private var suggestionsPageType: SuggestionsPageType = .none
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

    /// A pinned context remains tied to its original page while auto-attach is disabled, so page
    /// suggestions must remain tied to that same context until the chip is removed.
    var shouldSuspendSuggestionsRefresh: Bool {
        !shouldAutoCollectContext && intendedAttachedContext != nil
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

        firePromptSubmittedWithSelectionsIfNeeded()
        rebuildViewState()
        emit(.submitPrompt(prompt: prompt, context: contextData))
    }

    /// Call when the first prompt is submitted through contextual UTI. The UTI coordinator
    /// delivers the prompt, so this only performs the contextual session transition and pixels.
    ///
    /// - Parameter deferringSubmissionPixel: pass `true` when delivery is still conditional at this
    ///   point, so the prompt-submitted pixel is withheld until `confirmDeferredSubmissionPixel()`.
    ///   The transition itself still happens immediately — the user should see the chat surface right
    ///   away — but reporting a submission that may never leave the device would be a false positive.
    func beginChatForUTISubmission(deferringSubmissionPixel: Bool = false) {
        guard frontendState != .restoredChat else {
            Logger.aiChat.debug("[SessionState] UTI chat start request ignored - preserving .restoredChat state")
            return
        }

        switch chipState {
        case .attached(let context):
            frontendState = .chatWithInitialContext
            deliveredContextURLWithNoNavigationSince = URL(string: context.contextData.url)
            firePromptSubmittedPixel(.withContext, deferred: deferringSubmissionPixel)
            Logger.aiChat.debug("[SessionState] UTI chat started WITH initial context")
        case .placeholder:
            frontendState = .chatWithoutInitialContext
            firePromptSubmittedPixel(.withoutContext, deferred: deferringSubmissionPixel)
            Logger.aiChat.debug("[SessionState] UTI chat started WITHOUT initial context")
        }

        // Not deferred with the context pixels: a selection-tool submission attaches nothing, so when
        // this is deferred there are no selections riding along to report anyway.
        firePromptSubmittedWithSelectionsIfNeeded()
        rebuildViewState()
    }

    /// Reports how many text selections a submitted prompt carried.
    ///
    /// Called from the submission paths rather than from consumption, because consumption runs while the
    /// payload is being built and is skipped entirely when the prompt carries no selections. Must run
    /// before anything clears the list.
    private func firePromptSubmittedWithSelectionsIfNeeded() {
        guard !attachedSelections.isEmpty else { return }
        pixelHandler.firePromptSubmittedWithSelections(count: attachedSelections.count)
    }

    /// Fires a submission pixel withheld by `beginChatForUTISubmission(deferringSubmissionPixel: true)`,
    /// now that the prompt has actually reached the frontend.
    func confirmDeferredSubmissionPixel() {
        guard let deferred = deferredSubmissionPixel else { return }
        deferredSubmissionPixel = nil
        switch deferred {
        case .withContext: pixelHandler.firePromptSubmittedWithContext()
        case .withoutContext: pixelHandler.firePromptSubmittedWithoutContext()
        }
    }

    /// Drops a withheld submission pixel because the prompt never got delivered.
    func discardDeferredSubmissionPixel() {
        deferredSubmissionPixel = nil
    }

    private func firePromptSubmittedPixel(_ pixel: DeferredSubmissionPixel, deferred: Bool) {
        guard deferred else {
            switch pixel {
            case .withContext: pixelHandler.firePromptSubmittedWithContext()
            case .withoutContext: pixelHandler.firePromptSubmittedWithoutContext()
            }
            return
        }
        deferredSubmissionPixel = pixel
    }

    func attachContextFromSuggestionTap(_ context: AIChatPageContext) {
        chipState = .attached(context)
        userDowngradedToPlaceholder = false
        emitDeliveryIfNeeded(context.contextData)
        rebuildViewState()
    }

    // MARK: - Attached Text Selections

    /// Records text the user selected on the page, so it can be shown as a chip and later inlined
    /// into the prompt.
    ///
    /// Capped at `AIChatSelectionContextBuilder.maxAttachedSelections`; a further selection is
    /// refused rather than displacing an existing one, so nothing the user already collected
    /// disappears without them asking. Returns whether it was attached, so the caller can tell the
    /// user why nothing appeared instead of failing silently.
    @discardableResult
    func attachSelection(_ selection: AIChatSelectionContextData, pageTitle: String?) -> Bool {
        guard attachedSelections.count < AIChatSelectionContextBuilder.maxAttachedSelections else {
            return false
        }
        attachedSelections.append(selection)
        attachedSelectionPageTitle = pageTitle
        resolveSuggestionsForScopeChange()
        rebuildViewState()
        return true
    }

    /// Removes one attached selection (its chip's remove button). Page context and the other
    /// selections are untouched — each chip is independent.
    func removeAttachedSelection(id: String) {
        guard attachedSelections.contains(where: { $0.id == id }) else { return }
        attachedSelections.removeAll { $0.id == id }
        if attachedSelections.isEmpty {
            attachedSelectionPageTitle = nil
        }
        resolveSuggestionsForScopeChange()
        rebuildViewState()
    }

    /// Clears the selections a prompt has taken ownership of, matching macOS's
    /// `clearSelectionContexts()` on submit.
    ///
    /// Separate from `clearAttachedSelections()` because this runs while a payload is being built:
    /// re-rendering there would fight the submit transition, so the caller refreshes the chips.
    func consumeAttachedSelections() {
        guard !attachedSelections.isEmpty else { return }
        attachedSelections = []
        attachedSelectionPageTitle = nil
    }

    /// Drops the attached selections and re-renders. For callers acting outside a submit.
    func clearAttachedSelections() {
        guard !attachedSelections.isEmpty else { return }
        attachedSelections = []
        attachedSelectionPageTitle = nil
        rebuildViewState()
    }

    /// Call when starting a new chat (resetting frontend)
    ///
    /// `preservingSelections` keeps the collected selections, for the inactivity timer: expiring an
    /// idle chat must not destroy text the user gathered across several pages while reading, which is
    /// the whole point of gathering it before asking. New Chat and the fire button are explicit
    /// start-overs, so they clear — hence the default.
    func resetToNoChat(preservingSelections: Bool = false) {
        if !preservingSelections {
            attachedSelections = []
            attachedSelectionPageTitle = nil
        }
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
        suggestionsAreSmart = false
        suggestionsPageType = .none
        suggestionsLoadState = .loaded
        pixelHandler.endManualAttach()
        rebuildViewState()
        emit(.clearPrompt)
        Logger.aiChat.debug("[SessionState] Reset to no chat (selections preserved: \(preservingSelections, privacy: .public))")
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
    /// Re-resolves the suggestions because their scope changed: a selection was attached or removed, and
    /// the page-scoped and selection-scoped sets are different catalog entries. Without this the row
    /// keeps whichever set was resolved last, so an attached selection would still be offered
    /// "Summarize this page".
    private func resolveSuggestionsForScopeChange() {
        guard frontendState == .noChat, showsSuggestionsStartSurface, !hasActiveChat else { return }
        suggestionsResolveTask?.cancel()
        suggestionsLoadState = .loading
        resolveSuggestionsIfLoading(from: latestContext)
    }

    /// Re-renders after something outside this object changed the attachment count — an image added to
    /// or removed from the input — since that decides whether suggestions are offered.
    func refreshForAttachmentChange() {
        rebuildViewState()
    }

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

        let context = context.flatMap { $0.contextData.content.isEmpty ? nil : $0 }

        guard let context = context else {
            guard shouldProcessNilContextUpdate else {
                Logger.aiChat.debug("[SessionState] Ignoring nil context update without active collection")
                return
            }
            Logger.aiChat.debug("[SessionState] Context collection returned nil/empty - clearing context and downgrading to placeholder")
            latestContext = nil
            chipState = .placeholder
            // Clear the persistent UTI host chip
            emit(.deliverPageContext(nil, targets: .utiChip))
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

    /// How many attachments the prompt currently carries: the page-context chip, each text selection,
    /// and each image or file in the input.
    ///
    /// Auto-attached page context counts the same as manually attached — the user sees one chip either
    /// way, and distinguishing them would mean recording provenance that nothing tracks today.
    private var attachmentCount: Int {
        let pageContextCount = if case .attached = chipState { 1 } else { 0 }
        return pageContextCount + attachedSelections.count + inputAttachmentCount()
    }

    /// Suggestions are offered only while exactly one thing is attached, or nothing is.
    ///
    /// Beyond that the user has assembled something specific, and a one-line suggestion can no longer
    /// say which part of it it acts on — the same reasoning that already hides suggestions when several
    /// tabs are attached, generalised to attachments of any kind. So a selection plus an image, or page
    /// context plus an image, offers nothing.
    ///
    /// Consequence worth knowing: with auto-attach on, a selection makes two attachments, so selection
    /// suggestions never appear for those users. Whether to skip auto-attach when a selection is
    /// attached is an open product question.
    private var shouldHideSuggestions: Bool {
        attachmentCount > 1
    }

    private func resolveQuickActions() -> [AIChatContextualQuickAction] {
        // Deliberately NOT suppressed while a selection is attached, unlike the suggestions.
        // "Ask about page" is the only route to attaching page context, so hiding it would make a
        // selection and page context mutually exclusive — contradicting the decision that the two
        // coexist, and macOS's TS3 ruling that attaching page content to an ongoing chat must keep
        // working.
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
            guard self.suggestionsLoadState == .loading,
                  self.featureFlagger.isFeatureOn(.contextualSuggestedPrompts),
                  !self.hasActiveChat else { return }
            self.pixelHandler.fireSuggestionsContextCollectionTimedOut()
            self.resolveSuggestionsIfLoading(from: nil)
        }
    }

    func resolveSuggestionsIfLoading(from context: AIChatPageContext?) {
        guard suggestionsLoadState == .loading,
              featureFlagger.isFeatureOn(.contextualSuggestedPrompts),
              !hasActiveChat else { return }

        suggestionsTimeoutTask?.cancel()

        // A selection is attached, so offer the selection-scoped pair instead of page-derived ones.
        // `pageTypeSignals` still travels: translate's `differentLanguage` condition compares the source
        // page's language against the UI language, and a selection's source is that page.
        let input = ResolvePageSuggestionsInput(
            pageTypeSignals: context?.contextData.pageTypeSignals,
            url: context?.contextData.url,
            uiLocale: Locale.current.identifier,
            scope: attachedSelections.isEmpty ? .page : .selection
        )

        suggestionsResolveTask?.cancel()
        suggestionsResolveTask = Task { [weak self] in
            guard let resolved = await self?.suggestedPromptsProvider.resolveSuggestions(input) else { return }
            // A prompt submission may start a chat while the resolve is in flight; submission
            // methods don't cancel this task, so drop late results to keep chat view state intact.
            guard let self, !Task.isCancelled, !self.hasActiveChat else { return }
            self.suggestions = resolved.suggestions
            self.suggestionsAreSmart = resolved.isSmart
            self.suggestionsPageType = resolved.pageType
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

        let quickActions = resolveQuickActions()
        viewState = SheetViewState(
            content: content,
            isExpandButtonEnabled: frontendState == .noChat || contextualChatURL != nil,
            shouldShowNewChatButton: frontendState != .noChat,
            chipState: chipState,
            quickActions: quickActions,
            suggestions: shouldHideSuggestions ? [] : visibleSuggestions(reserving: quickActions.count),
            suggestionsLoadState: suggestionsLoadState,
            suggestionsAreSmart: suggestionsAreSmart,
            suggestionsPageType: suggestionsPageType
        )
    }

    func visibleSuggestions(reserving slots: Int) -> [ContextualSuggestedPrompt] {
        let cap = max(0, suggestedPromptsProvider.maxSuggestedPrompts - slots)
        guard suggestions.count > cap else { return suggestions }

        let prioritySuggestionIDs = suggestedPromptsProvider.prioritySuggestionIDs
        let prioritySuggestions = suggestions.filter { prioritySuggestionIDs.contains($0.id) }
        let regularSuggestions = suggestions.filter { !prioritySuggestionIDs.contains($0.id) }
        let priorityCount = min(prioritySuggestions.count, cap)

        return Array(regularSuggestions.prefix(cap - priorityCount)) + Array(prioritySuggestions.prefix(priorityCount))
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
