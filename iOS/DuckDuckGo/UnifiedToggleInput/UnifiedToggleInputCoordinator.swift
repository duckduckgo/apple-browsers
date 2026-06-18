//
//  UnifiedToggleInputCoordinator.swift
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
import BrowserServicesKit
import Combine
import Core
import DDGSync
import os.log
import Subscription
import UIKit
import UniformTypeIdentifiers

// MARK: - State Types

enum InputTextState {
    case empty
    case prefilledSelected
    case userTyped
}

enum UnifiedToggleInputDisplayState: Equatable {
    case hidden
    case aiTab(AITabState)
    case omnibar(OmnibarState)

    enum AITabState: Equatable {
        case collapsed
        case expanded
    }

    enum OmnibarState: Equatable {
        case active
        case inactive
    }
}

enum UnifiedToggleInputIntent: Equatable {
    case showCollapsed(from: UnifiedToggleInputDisplayState)
    case showExpanded(from: UnifiedToggleInputDisplayState)
    case showOmnibarEditing(expandedHeight: CGFloat, pendingExpandedHeight: CGFloat? = nil)
    case showOmnibarInactive
    case showOmnibarActive
    case hideOmnibarEditing(animated: Bool)
    case hide
}

/// First-class wrapper around "should this UI mutation animate, or snap?" Both branches
/// take a closure of work to run — the wrapper handles the animation-context plumbing
/// (`UIView.animate` vs `UIView.performWithoutAnimation`) so call sites stay flat.
enum UTIAnimationStyle {
    case snap
    case animated(duration: TimeInterval, options: UIView.AnimationOptions, layoutTarget: UIView)

    func perform(_ body: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
        switch self {
        case .snap:
            UIView.performWithoutAnimation(body)
            completion?(true)
        case let .animated(duration, options, layoutTarget):
            UIView.animate(withDuration: duration, delay: 0, options: options, animations: {
                body()
                layoutTarget.layoutIfNeeded()
            }, completion: completion)
        }
    }

    /// Duration of this style — `0` for snap, the configured duration for animated. Useful
    /// for matching parallel animations (e.g. `adjustUI(withKeyboardFrame:in:)`) to the same
    /// timing.
    var duration: TimeInterval {
        switch self {
        case .snap: return 0
        case let .animated(duration, _, _): return duration
        }
    }
}

extension UnifiedToggleInputIntent {
    enum AnimationConstants {
        /// In-place pose morph on Duck.ai (collapsed ↔ expanded card).
        static let aiTabPoseMorphDuration: TimeInterval = 0.35
    }

    /// Animation style derived from the intent's transition. The (from, to) pair is the only
    /// signal needed — adding new transitions means adding new cases in the matrix below, not
    /// scattering `if/else` across handlers.
    func animationStyle(layoutTarget: UIView) -> UTIAnimationStyle {
        switch self {
        case let .showCollapsed(from):
            return Self.transitionStyle(from: from, to: .aiTab(.collapsed), layoutTarget: layoutTarget)
        case let .showExpanded(from):
            return Self.transitionStyle(from: from, to: .aiTab(.expanded), layoutTarget: layoutTarget)
        case .hide, .showOmnibarEditing, .showOmnibarInactive, .showOmnibarActive, .hideOmnibarEditing:
            // `.hide` is always a snap (no animatable transition pair); the omnibar intents
            // own bespoke animation flows and pick their own style.
            return .snap
        }
    }

    private static func transitionStyle(from: UnifiedToggleInputDisplayState,
                                        to: UnifiedToggleInputDisplayState,
                                        layoutTarget: UIView) -> UTIAnimationStyle {
        switch (from, to) {
        case (.aiTab(.expanded), .aiTab(.collapsed)),
             (.aiTab(.collapsed), .aiTab(.expanded)):
            return .animated(duration: AnimationConstants.aiTabPoseMorphDuration,
                             options: .curveEaseInOut,
                             layoutTarget: layoutTarget)
        default:
            // Fresh entry into a state from a different layout (tab swipe, app launch,
            // omnibar dismiss, hide). The outer constraint changes shouldn't be animated;
            // the destination should just BE there.
            return .snap
        }
    }
}

enum ExternalSubmissionType {
    case query
    case prompt
}

enum SubscriptionFlowSource {
    case modelPicker
    case reasoningPicker
}

enum UpsellFlowType: String {
    case purchase
    case upgrade
}

private struct PromptSubmissionConfiguration {
    let modelId: String?
    let reasoningEffort: AIChatReasoningEffort?
}

// MARK: - Subscription State

struct SubscriptionState {
    let userTier: AIChatUserTier
    let hasActiveSubscription: Bool

    static let free = SubscriptionState(userTier: .free, hasActiveSubscription: false)
}

// MARK: - Coordinator

@MainActor
final class UnifiedToggleInputCoordinator: NSObject, AIChatInputBoxHandling {

    private enum Constants {
        static let topOmnibarKeyboardPresentationTimeout: TimeInterval = 0.35
        static let subscriptionFeaturePage = "duckai"
    }

    private var attachmentPolicy: UTIAttachmentPolicy {
        UTIAttachmentPolicy(
            attachmentLimits: modelStore.attachmentLimits,
            attachmentUsage: attachmentUsage,
            pendingAttachments: viewController.currentAttachments,
            model: modelStore.selectedModel
        )
    }

    // MARK: - AIChatInputBoxHandling

    let didPressFireButton = PassthroughSubject<Void, Never>()
    let didPressNewChatButton = PassthroughSubject<Void, Never>()
    let didSubmitPrompt = PassthroughSubject<String, Never>()
    let didSubmitQuery = PassthroughSubject<String, Never>()
    let didPressStopGeneratingButton = PassthroughSubject<Void, Never>()
    let didPressCustomizeResponsesButton = PassthroughSubject<Void, Never>()

    var aiChatStatusPublisher: Published<AIChatStatusValue>.Publisher { $aiChatStatus }
    var aiChatInputBoxVisibilityPublisher: Published<AIChatInputBoxVisibility>.Publisher { $aiChatInputBoxVisibility }
    var isVoiceSessionActivePublisher: Published<Bool>.Publisher { $isVoiceSessionActive }
    var attachmentUsagePublisher: Published<AIChatAttachmentUsage?>.Publisher { $attachmentUsage }
    var persistedReasoningEffort: AIChatReasoningEffort? {
        guard let selectedModel else { return nil }
        guard persistedReasoningMode != nil || selectedModel.supportsReasoningPicker else { return nil }

        return selectedModel.resolvedReasoningEffort(from: persistedReasoningMode)
    }
    private var promptSubmissionModelId: String? {
        hasSubmittedPrompt ? nil : persistedModelId
    }
    private var promptSubmissionConfiguration: PromptSubmissionConfiguration {
        PromptSubmissionConfiguration(
            modelId: promptSubmissionModelId,
            reasoningEffort: persistedReasoningEffort
        )
    }
    var voicePromptSubmissionConfiguration: (modelId: String?, reasoningEffort: AIChatReasoningEffort?) {
        (promptSubmissionModelId, nil)
    }

    @Published var aiChatStatus: AIChatStatusValue = .unknown
    @Published var aiChatInputBoxVisibility: AIChatInputBoxVisibility = .unknown {
        didSet {
            guard oldValue != aiChatInputBoxVisibility else { return }
            persistDraftToStore()
        }
    }
    @Published var isVoiceSessionActive: Bool = false {
        didSet {
            guard oldValue != isVoiceSessionActive else { return }
            persistDraftToStore()
        }
    }
    @Published var attachmentUsage: AIChatAttachmentUsage?

    var isSubmitBlockedByRecoveryCard: Bool = false {
        didSet {
            guard oldValue != isSubmitBlockedByRecoveryCard else { return }
            viewController.isSubmitBlockedByRecoveryCard = isSubmitBlockedByRecoveryCard
        }
    }

    // MARK: - Properties

    private(set) var viewController: UnifiedToggleInputViewController
    private(set) var contentViewController: UnifiedInputContentContainerViewController
    private(set) var floatingReturnKeyViewController: UnifiedToggleInputFloatingReturnKeyViewController
    weak var delegate: UnifiedToggleInputDelegate?

    private(set) var host: UnifiedToggleInputHost
    private(set) var isToggleEnabled: Bool
    /// Snapshot of `UnifiedToggleInputFeatureProviding.isToggleHiddenOnDuckAITab` at init.
    private let hidesToggleOnDuckAITab: Bool
    private(set) var isOnboardingLocked: Bool = false
    private(set) var displayState: UnifiedToggleInputDisplayState = .hidden
    private(set) var textState: InputTextState = .empty
    private(set) var inputMode: TextEntryMode = .aiChat
    private let stateStore: UnifiedInputStateStoring
    private let switchBarSubmissionMetrics: SwitchBarSubmissionMetricsProviding
    private let aiChatSettings: AIChatSettingsProvider
    private let sessionStateMetrics: SessionStateMetricsProviding
    private static var hasUsedSearchInSession = false
    private static var hasUsedAIChatInSession = false
    private var backgroundObserver: NSObjectProtocol?
    private(set) var currentTabUID: TabUID?
    private var lastActivatedTabUID: TabUID?
    private var isApplyingState = false
    /// True while a dismiss-time visible-text clear is in flight. The deferred
    /// `clearText()` is a UI cleanup, not a user intent to delete their typed text;
    /// per-tab persistence must keep the draft so re-activating the same tab restores it.
    private var isPerformingDismissCleanup = false
    private(set) var committedInputMode: TextEntryMode = .search
    private(set) var cardPosition: UnifiedToggleInputCardPosition = .bottom
    private(set) var isInputVisibleForKeyboard: Bool = true
    private var isAwaitingTopOmnibarKeyboardPresentation = false
    private var topOmnibarKeyboardPresentationFallback: DispatchWorkItem?
    private var invalidAttachmentRecoveryTasks: [UUID: Task<Void, Never>] = [:]
    private var isContentOverlaySuppressed = false
    private var pendingGatedModelId: String?
    private var pendingGatedReasoningSelection: (modelId: String, mode: AIChatReasoningMode)?
    /// Forces the model chip visible mid-chat for the FE's `showModelPicker` flow; cleared on prompt
    /// submit or session reset.
    private var isModelPickerForcedVisible: Bool = false {
        didSet {
            guard oldValue != isModelPickerForcedVisible else { return }
            guard !isClearingModelPickerPinWithoutPersist else { return }
            persistDraftToStore()
        }
    }
    /// Scoped guard for `hide()`: clear the live pin without writing `false` to `TabInputState`
    /// (the per-tab pin must survive so `activateForTab` can restore the recovery chip).
    private var isClearingModelPickerPinWithoutPersist = false

    private(set) var currentText: String = ""
    var hasActiveChat: Bool { boundUserScript != nil }
    var switchBarHandler: SwitchBarHandling { viewController.handler }
    var onAnimatedDismissToOmnibar: ((_ completion: (() -> Void)?) -> Void)?

    var isOmnibarSession: Bool {
        if case .omnibar = displayState { return true }
        return false
    }

    var isAITabState: Bool {
        if case .aiTab = displayState { return true }
        return false
    }

    var isAITabExpanded: Bool {
        displayState == .aiTab(.expanded)
    }

    /// True when the current display state corresponds to the expanded card layout.
    /// Synchronous (driven by `displayState`) so it's safe to read before the deferred
    /// `applyCardLayout` runs from the intent handler.
    var isInputPaneExpanded: Bool {
        switch displayState {
        case .aiTab(.expanded), .omnibar(.active): return true
        default: return false
        }
    }

    var isInputEditing: Bool {
        isOmnibarSession || isAITabExpanded
    }

    var isActive: Bool {
        displayState != .hidden
    }

    private var isOmnibarNewAIChatPrompt: Bool {
        isOmnibarSession && inputMode == .aiChat && !hasSubmittedPrompt
    }

    private var usesFloatingReturnKey: Bool {
        displayState == .omnibar(.active) && isInputVisibleForKeyboard && isOmnibarNewAIChatPrompt
    }

    private var cancellables = Set<AnyCancellable>()
    private weak var boundUserScript: AIChatUserScript?
    private var boundUserScriptIdentifier: ObjectIdentifier?
    private let lastUsedModelProvider: DuckAiLastUsedModelProviding?
    private let lastUsedReasoningModeProvider: DuckAiLastUsedReasoningModeProviding?
    private let lastUsedModelCache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 64
        return cache
    }()
    private var chatUpdatesCancellable: AnyCancellable?
    private let toolsController = UTIToolsController()
    private let toolsMenuFactory = UTIToolsMenuFactory()
    private let modelMenuFactory = UnifiedToggleInputModelMenuFactory()
    private let attachmentPresenter = UnifiedToggleInputAttachmentPresenter()

    private let intentSubject = PassthroughSubject<UnifiedToggleInputIntent, Never>()
    var intentPublisher: AnyPublisher<UnifiedToggleInputIntent, Never> {
        intentSubject.eraseToAnyPublisher()
    }

    private let textChangeSubject = PassthroughSubject<String, Never>()
    var textChangePublisher: AnyPublisher<String, Never> {
        textChangeSubject.eraseToAnyPublisher()
    }

    private let modeChangeSubject = PassthroughSubject<TextEntryMode, Never>()
    var modeChangePublisher: AnyPublisher<TextEntryMode, Never> {
        modeChangeSubject.eraseToAnyPublisher()
    }

    private let attachmentsChangeSubject = PassthroughSubject<Void, Never>()
    var attachmentsChangePublisher: AnyPublisher<Void, Never> {
        attachmentsChangeSubject.eraseToAnyPublisher()
    }

    private let duckAIWideEventInstrumentation: DuckAIWideEventInstrumentation?
    private let duckAIWideEventFlowScope: DuckAIWideEventFlowScope?

    // MARK: - Initialization

    init(
        host: UnifiedToggleInputHost,
        isToggleEnabled: Bool,
        isFireTab: Bool = false,
        hidesToggleOnDuckAITab: Bool = false,
        duckAiNativeStorageHandler: DuckAiNativeStorageHandling? = nil,
        duckAiNativeStoragePixelFiring: DuckAiNativeStoragePixelFiring = DuckAiNativeStoragePixelAdapter(),
        lastUsedModelProvider: DuckAiLastUsedModelProviding? = nil,
        lastUsedReasoningModeProvider: DuckAiLastUsedReasoningModeProviding? = nil,
        modelsService: AIChatModelsProviding = AIChatModelsService(),
        preferences: AIChatPreferencesPersisting = AIChatPreferencesPersistor(),
        subscriptionManager: any SubscriptionManager = AppDependencyProvider.shared.subscriptionManager,
        toggleModeStorage: ToggleModeStoring = ToggleModeStorage(),
        stateStore: UnifiedInputStateStoring? = nil,
        syncService: DDGSyncing? = nil,
        switchBarSubmissionMetrics: SwitchBarSubmissionMetricsProviding = SwitchBarSubmissionMetrics(),
        aiChatSettings: AIChatSettingsProvider = AIChatSettings(),
        aiChatSyncCleaner: AIChatSyncCleaning? = nil,
        sessionStateMetrics: SessionStateMetricsProviding = SessionStateMetrics(storage: UserDefaults.standard),
        duckAIWideEventInstrumentation: DuckAIWideEventInstrumentation? = nil,
        duckAIWideEventFlowScope: DuckAIWideEventFlowScope? = nil
    ) {
        self.host = host
        self.isToggleEnabled = isToggleEnabled
        self.hidesToggleOnDuckAITab = hidesToggleOnDuckAITab
        self.switchBarSubmissionMetrics = switchBarSubmissionMetrics
        self.aiChatSettings = aiChatSettings
        self.sessionStateMetrics = sessionStateMetrics
        self.stateStore = stateStore ?? UnifiedInputStateStore(
            preferences: preferences,
            toggleModeStorage: toggleModeStorage
        )
        self.modelStore = UTIModelStore(
            modelsService: modelsService,
            preferences: preferences,
            subscriptionManager: subscriptionManager
        )
        self.lastUsedModelProvider = lastUsedModelProvider
            ?? duckAiNativeStorageHandler.map { DuckAiLastUsedModelProvider(storage: $0, pixelFiring: duckAiNativeStoragePixelFiring) }
        self.lastUsedReasoningModeProvider = lastUsedReasoningModeProvider
            ?? duckAiNativeStorageHandler.map { DuckAiLastUsedReasoningModeProvider(storage: $0, pixelFiring: duckAiNativeStoragePixelFiring) }
        self.duckAIWideEventInstrumentation = duckAIWideEventInstrumentation
        self.duckAIWideEventFlowScope = duckAIWideEventFlowScope
        viewController = UnifiedToggleInputViewController(isToggleEnabled: isToggleEnabled, isFireTab: isFireTab)
        contentViewController = UnifiedInputContentContainerViewController(
            switchBarHandler: viewController.handler,
            duckAiNativeStorageHandler: duckAiNativeStorageHandler,
            syncService: syncService,
            aiChatSyncCleaner: aiChatSyncCleaner
        )
        floatingReturnKeyViewController = UnifiedToggleInputFloatingReturnKeyViewController()
        super.init()
        viewController.delegate = self
        attachmentPresenter.onExpandIfNeeded = { [weak self] in
            self?.expandIfOnAITab()
        }
        attachmentPresenter.onImagePicked = { [weak self] image, fileName in
            self?.addImageAttachment(image: image, fileName: fileName)
        }
        attachmentPresenter.onFilePicked = { [weak self] attachment, metadata in
            self?.addFileAttachment(attachment, sourceURL: metadata.url)
        }
        attachmentPresenter.onFileValidationFailed = { [weak self] message, metadata in
            guard let self else { return }
            let reason: UTIAttachmentPolicy.FileValidationFailureReason
            if let metadataError = self.attachmentPolicy
                .fileMetadataValidationError(mimeType: metadata.mimeType, fileSizeBytes: metadata.fileSizeBytes) {
                reason = metadataError.reason
            } else if message == UserText.aiChatAttachmentFileUnreadable {
                reason = .unreadable
            } else {
                reason = .other
            }
            DailyPixel.fireDailyAndCount(
                pixel: .unifiedToggleInputFileValidationFailed,
                withAdditionalParameters: ["reason": reason.rawValue]
            )
            self.addInvalidFileAttachment(metadata: metadata, validationMessage: message)
        }
        attachmentPresenter.fileMetadataValidationMessage = { [weak self] metadata in
            self?.attachmentPolicy.fileMetadataValidationError(mimeType: metadata.mimeType, fileSizeBytes: metadata.fileSizeBytes)?.message
        }
        modelStore.onModelsUpdated = { [weak self] in
            self?.handleModelsUpdated()
        }
        subscribeToGeneratingState()
        subscribeToStopGeneratingTap()
        subscribeToCustomizeResponsesTap()
        subscribeToVoiceSearchTap()
        subscribeToAIVoiceChatTap()
        subscribeToClearButtonTap()
        subscribeToAttachmentUsageChanges()
        subscribeToSubscriptionChanges()
        subscribeToDuckAIWideEventSignals()
        viewController.isToolsButtonHidden = true

        if let cachedLabel = modelStore.displayShortName {
            viewController.modelName = cachedLabel
        }

        // Contextual chat boots in expanded form; no collapsed/inactive states are reachable.
        // The chat is already post-submit by the time the contextual UTI installs, so
        // `hasSubmittedPrompt` should reflect that — drives follow-up placeholder + model chip hide.
        if host == .contextualChat {
            displayState = .aiTab(.expanded)
            hasSubmittedPrompt = true
            syncHasSubmittedPromptToHandler()
            updateModelChipVisibility()
        }

        if host == .omnibar {
            backgroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.sessionStateMetrics.finalizeSession()
                    Self.resetSessionFlags()
                }
            }
        }
    }

    deinit {
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
    }

    // MARK: - Tab Binding

    func bindToTab(_ userScript: AIChatUserScript, hasExistingChat: Bool = false) {
        let newIdentifier = ObjectIdentifier(userScript)
        if boundUserScriptIdentifier == newIdentifier {
            boundUserScript = userScript
            userScript.inputBoxHandler = self
            syncChipVisibility(hasExistingChat: hasExistingChat)
            return
        }
        let hadPreviousScript = boundUserScriptIdentifier != nil
        boundUserScript?.inputBoxHandler = nil
        boundUserScript = userScript
        boundUserScriptIdentifier = newIdentifier
        userScript.inputBoxHandler = self
        if hadPreviousScript {
            resetSessionState()
        }
        syncChipVisibility(hasExistingChat: hasExistingChat)
    }

    func unbind() {
        boundUserScript?.inputBoxHandler = nil
        boundUserScript = nil
        boundUserScriptIdentifier = nil
        resetSessionState()
    }

    /// Subscribes to bridge-side chat-update events so the UTI's model/tools reflect any
    /// model change the FE makes on the active chat (e.g. user picks a different model
    /// mid-conversation). Replaces any previous subscription.
    func observeChatUpdates(_ publisher: AnyPublisher<String, Never>) {
        chatUpdatesCancellable = publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] updatedChatID in
                guard let self else { return }
                guard let activeChatID = self.boundUserScript?.webView?.url?.duckAIChatID,
                      activeChatID == updatedChatID else {
                    return
                }
                // Storage changed for this chat; drop the cached model so the next read reflects it.
                self.lastUsedModelCache[activeChatID] = nil
                self.restoreLastUsedModel(forChatID: activeChatID)
                self.restoreLastUsedReasoningMode(forChatID: activeChatID)
            }
    }

    /// Reads the last-used model from native storage for `chatID` and applies it to the
    /// model store so the toolbar (model chip + tools) reflects the model the chat last
    /// used. No-op when the provider is unavailable or the chat has no recorded model.
    /// Safe to call before models have loaded — `handleModelsUpdated()` will reconcile.
    func restoreLastUsedModel(forChatID chatID: String) {
        guard let lastUsedModelProvider else {
            Logger.unifiedInputState.debug("restoreLastUsedModel [\(chatID, privacy: .public)]: no provider configured")
            return
        }
        let modelID: String?
        if let cached = lastUsedModelCache[chatID] {
            modelID = cached
        } else {
            modelID = lastUsedModelProvider.lastUsedModel(forChatId: chatID)
            if let modelID {
                lastUsedModelCache[chatID] = modelID
            }
        }
        guard let modelID else {
            Logger.unifiedInputState.debug("restoreLastUsedModel [\(chatID, privacy: .public)]: no last-used model recorded")
            return
        }
        if modelStore.currentModelId == modelID {
            Logger.unifiedInputState.debug("restoreLastUsedModel [\(chatID, privacy: .public)]: model '\(modelID, privacy: .public)' already current, skipping")
            return
        }
        Logger.unifiedInputState.debug("restoreLastUsedModel [\(chatID, privacy: .public)]: loaded model '\(modelID, privacy: .public)'")
        modelStore.updateSelectedModel(modelID, isNewChatContext: false)
        handleModelsUpdated()
    }

    /// Reads the persisted `reasoningMode` for `chatID` from the chat payload in native
    /// storage and applies it to the live reasoning picker. Mirrors `restoreLastUsedModel`.
    /// Contract:
    /// - Missing field → no-op (older chats keep current picker state).
    /// - Unknown value → no-op (same as missing).
    /// - Known value → live preferences updated + reasoning picker refreshed.
    func restoreLastUsedReasoningMode(forChatID chatID: String) {
        guard let lastUsedReasoningModeProvider else {
            Logger.unifiedInputState.debug("restoreLastUsedReasoningMode [\(chatID, privacy: .public)]: no provider configured")
            return
        }
        guard let rawValue = lastUsedReasoningModeProvider.reasoningMode(forChatId: chatID) else {
            Logger.unifiedInputState.debug("restoreLastUsedReasoningMode [\(chatID, privacy: .public)]: no reasoningMode in payload")
            return
        }
        guard let mode = AIChatReasoningMode(rawValue: rawValue) else {
            Logger.unifiedInputState.debug("restoreLastUsedReasoningMode [\(chatID, privacy: .public)]: unknown value '\(rawValue, privacy: .public)'")
            return
        }
        Logger.unifiedInputState.debug("restoreLastUsedReasoningMode [\(chatID, privacy: .public)]: applying '\(rawValue, privacy: .public)'")
        modelStore.applyChatPersistedReasoningMode(mode)
        updateReasoningPicker()
    }

    // MARK: - Per-Tab State

    func activateForTab(_ uid: TabUID) {
        let previous = currentTabUID
        if previous == uid {
            Logger.unifiedInputState.debug("activateForTab [\(uid)]: already active, skipping re-apply")
            return
        }
        if let previous {
            let snapshot = snapshotCurrentState()
            Logger.unifiedInputState.debug("activateForTab [\(uid)]: flushing previous tab [\(previous)] — \(snapshot.summary)")
            stateStore.update(snapshot, for: previous)
            duckAIWideEventInstrumentation?.tabSwitchedAwayDuringGeneration(tabID: previous)
        } else {
            Logger.unifiedInputState.debug("activateForTab [\(uid)]: first activation, no flush")
        }
        currentTabUID = uid
        lastActivatedTabUID = uid
        applyState(stateStore.state(for: uid))
    }

    func applyState(_ state: TabInputState) {
        isApplyingState = true
        defer {
            isApplyingState = false
            updateFloatingReturnKeyState()
        }
        Logger.unifiedInputState.debug("applyState for tab [\(self.currentTabUID ?? "nil")]: \(state.summary)")

        aiChatInputBoxVisibility = state.aiChatInputBoxVisibility
        isVoiceSessionActive = state.isVoiceSessionActive
        isModelPickerForcedVisible = state.isModelPickerForcedVisible
        setText(state.text)
        syncInputModeFromExternalSource(state.toggleMode)

        cancelInvalidAttachmentRecoveryTasks()
        viewController.removeAllAttachments()
        for attachment in state.attachments {
            viewController.addAttachment(attachment)
        }
        syncAttachmentValidationErrorForCurrentMode()

        // Always sync the live model store from per-tab state — including nil values —
        // so the previous tab's selections don't leak through preferences. With the
        // `if let` shape we used to skip the write when state was nil, the live
        // preferences kept the previous tab's reasoning/model and the next snapshot
        // wrote that leaked value back into this tab's stored state.
        modelStore.applyPersistedSelection(
            modelID: state.selectedModelID,
            reasoningMode: state.selectedReasoningMode
        )
        handleModelsUpdated()
        updateReasoningPicker()

        if let tool = state.selectedTool {
            toolsController.select(tool, for: modelStore)
        } else {
            toolsController.clearSelection()
        }
        refreshToolsPresentation()
    }

    func snapshotCurrentState() -> TabInputState {
        TabInputState(
            text: currentText,
            toggleMode: inputMode,
            attachments: viewController.currentAttachments,
            selectedModelID: modelStore.persistedModelId,
            selectedReasoningMode: modelStore.selectedReasoningMode,
            selectedTool: toolsController.selectedTool,
            aiChatInputBoxVisibility: aiChatInputBoxVisibility,
            isVoiceSessionActive: isVoiceSessionActive,
            isModelPickerForcedVisible: isModelPickerForcedVisible
        )
    }

    /// Persists per-tab-only state — text and attachments. These are drafts the user
    /// is actively building; they belong to the tab, not to the global last-used
    /// defaults, and must not write through to global preferences.
    private func persistDraftToStore() {
        guard !isApplyingState, !isPerformingDismissCleanup, let uid = currentTabUID else { return }
        stateStore.update(snapshotCurrentState(), for: uid)
    }

    /// `hide()` clears the live pin without updating `TabInputState`, so submit after `hide()`
    /// (`currentTabUID` nil) must patch the stored pin directly for `lastActivatedTabUID`.
    private func persistModelPickerPinClearedAfterHideIfNeeded() {
        guard currentTabUID == nil, let uid = lastActivatedTabUID else { return }
        var state = stateStore.state(for: uid)
        guard state.isModelPickerForcedVisible else { return }
        state.isModelPickerForcedVisible = false
        stateStore.update(state, for: uid)
    }

    /// Persists a user-deliberate choice — toggle mode, model, reasoning, tool. These
    /// update the global last-used defaults and write through to the canonical global
    /// preference homes so other components (e.g. NTP omnibar) observe the change.
    private func recordUserChoiceToStore() {
        guard !isApplyingState, !isPerformingDismissCleanup, let uid = currentTabUID else { return }
        stateStore.recordUserChoice(snapshotCurrentState(), for: uid, isNewChatContext: isNewChatContext)
    }

    private var isNewChatContext: Bool {
        !hasSubmittedPrompt
    }

    private func clearStoreEntryAfterSubmission() {
        currentText = ""
        textState = .empty
        guard let uid = currentTabUID else { return }
        var cleared = snapshotCurrentState()
        cleared.text = ""
        cleared.attachments = []
        cleared.selectedTool = nil
        stateStore.recordUserChoice(cleared, for: uid, isNewChatContext: false)
        Logger.unifiedInputState.debug("submission cleared store text + attachments + tool for tab [\(uid)]")
    }

    private var isNewChatPending = false

    // MARK: - AI Tab State

    func showCollapsed() {
        // Contextual chat has no AI tab collapsed mode; the host always renders expanded.
        if host == .contextualChat { return }
        cancelTopOmnibarKeyboardPresentationFallback()
        isAwaitingTopOmnibarKeyboardPresentation = false
        let previousDisplayState = displayState
        displayState = .aiTab(.collapsed)
        setInitialInputMode(.aiChat)
        isInputVisibleForKeyboard = true

        // Pose deferred to the intent handler so the morph animates in sync with the keyboard.
        applyToolbarPresentation()
        viewController.deactivateInput()
        intentSubject.send(.showCollapsed(from: previousDisplayState))
    }

    func showExpanded(prefilledText: String? = nil, inputMode: TextEntryMode = .aiChat) {
        guard !isOnboardingLocked else { return }
        cancelTopOmnibarKeyboardPresentationFallback()
        isAwaitingTopOmnibarKeyboardPresentation = false
        let previousDisplayState = displayState
        displayState = .aiTab(.expanded)
        // Pixels fire only on a real transition into expanded — header re-entries (Plus → New Chat) call this too but don't actually show either UI.
        if host == .omnibar, previousDisplayState != .aiTab(.expanded) {
            DailyPixel.fireDailyAndCount(pixel: .aiChatInternalSwitchBarDisplayed)
            DailyPixel.fireDailyAndCount(pixel: .aiChatExperimentalOmnibarShown)
        }
        setInitialInputMode(inputMode)
        isInputVisibleForKeyboard = true
        viewController.handler.resetInteractionState()

        // Pose deferred to the intent handler so the morph animates in sync with the keyboard.
        applyToolbarPresentation()
        fetchModels()

        if let prefilledText, !prefilledText.isEmpty {
            setText(prefilledText)
            textState = .prefilledSelected
        }
        updateFloatingReturnKeyState()

        intentSubject.send(.showExpanded(from: previousDisplayState))
        DispatchQueue.main.async { [weak self] in
            guard let self, case .aiTab(.expanded) = self.displayState else { return }
            guard !self.isOnboardingLocked else { return }
            self.viewController.activateInput()
            if !self.viewController.isInputFirstResponder {
                DispatchQueue.main.async { [weak self] in
                    guard let self, case .aiTab(.expanded) = self.displayState else { return }
                    guard !self.isOnboardingLocked else { return }
                    self.viewController.activateInput()
                }
            }
            if self.textState == .prefilledSelected {
                self.viewController.selectAllText()
            }
        }
    }

    func hide() {
        cancelTopOmnibarKeyboardPresentationFallback()
        isAwaitingTopOmnibarKeyboardPresentation = false
        displayState = .hidden
        isClearingModelPickerPinWithoutPersist = true
        isModelPickerForcedVisible = false
        isClearingModelPickerPinWithoutPersist = false
        isSubmitBlockedByRecoveryCard = false
        syncInputBehaviorToHandler()
        isInputVisibleForKeyboard = true
        // The live state is no longer authoritative for the previous tab; clearing
        // currentTabUID prevents the next activateForTab from snapshotting the
        // (now tool-cleared) live state back over the previous tab's stored entry.
        // Fire the wide-event cancellation here too — `activateForTab` skips it once
        // currentTabUID is nil, so Duck.ai → non-AI transitions would otherwise orphan.
        if let previousTabUID = currentTabUID {
            duckAIWideEventInstrumentation?.tabSwitchedAwayDuringGeneration(tabID: previousTabUID)
        }
        currentTabUID = nil
        resetToolsSelection()
        clearAttachments()
        setText("")
        updateFloatingReturnKeyState()

        let renderState = computeRenderState()
        viewController.apply(renderState.viewConfig, animated: false)
        applyToolbarPresentation()
        viewController.deactivateInput()
        intentSubject.send(.hide)
    }

    // MARK: - Omnibar State

    func activateFromOmnibar(prefilledText: String? = nil, inputMode: TextEntryMode = .search, cardPosition: UnifiedToggleInputCardPosition = .top) {
        cancelTopOmnibarKeyboardPresentationFallback()
        isAwaitingTopOmnibarKeyboardPresentation = cardPosition == .top
        displayState = .omnibar(.active)
        if host == .omnibar {
            DailyPixel.fireDailyAndCount(pixel: .aiChatInternalSwitchBarDisplayed)
            DailyPixel.fireDailyAndCount(pixel: .aiChatExperimentalOmnibarShown)
        }
        // Omnibar without a toggle UI locks to .search; inlined to avoid an ordering coupling with `effectiveInputMode`.
        setInitialInputMode(isToggleEnabled ? inputMode : .search)
        self.cardPosition = cardPosition
        viewController.handler.hidesVoiceButton = false
        isInputVisibleForKeyboard = true
        hasSubmittedPrompt = false
        viewController.handler.resetInteractionState()
        resetToolsSelection()
        updateModelChipVisibility()
        syncHasSubmittedPromptToHandler()

        viewController.applyCardLayout(.collapsed, animated: false)
        let renderState = computeRenderState()
        viewController.apply(renderState.viewConfig, animated: false)
        applyToolbarPresentation()
        fetchModels()

        let shouldSelectAllText: Bool
        if let text = prefilledText, !text.isEmpty {
            setText(text)
            textState = .prefilledSelected
            shouldSelectAllText = true
        } else {
            shouldSelectAllText = false
        }
        updateFloatingReturnKeyState()

        let expandedHeight = editingHeight()

        // Pre-stage to the start pose so the intent handler animates from initial to final height.
        viewController.prepareForOmnibarEditingShow()
        let initialHeight = editingHeight()
        intentSubject.send(.showOmnibarEditing(expandedHeight: initialHeight, pendingExpandedHeight: expandedHeight))

        if cardPosition == .top {
            scheduleTopOmnibarKeyboardPresentationFallback()
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, case .omnibar(.active) = displayState else { return }
            viewController.activateInput()
            if shouldSelectAllText {
                DispatchQueue.main.async { [weak self] in
                    guard let self, case .omnibar(.active) = displayState else { return }
                    viewController.selectAllText()
                }
            }
        }
    }

    func deactivateToOmnibar(resetView: Bool = true, animateDismiss: Bool = true) {
        guard isOmnibarSession else { return }
        inputMode = committedInputMode
        cancelTopOmnibarKeyboardPresentationFallback()
        isAwaitingTopOmnibarKeyboardPresentation = false
        displayState = .hidden
        cardPosition = .bottom
        isInputVisibleForKeyboard = true
        syncInputBehaviorToHandler()
        // Text clear is deferred to dismiss completion — avoids placeholder flash mid-collapse.
        resetToolsSelection()
        clearAttachments()
        updateFloatingReturnKeyState()

        if resetView {
            let renderState = computeRenderState()
            viewController.apply(renderState.viewConfig, animated: false)
            applyToolbarPresentation()
            viewController.deactivateInput()
        } else {
            applyToolbarPresentation()
            viewController.deactivateInput()
        }
        intentSubject.send(.hideOmnibarEditing(animated: animateDismiss))
    }

    func updateToggleEnabled(_ enabled: Bool) {
        guard enabled != isToggleEnabled else { return }
        isToggleEnabled = enabled
        // Pass `showsToolbar` derived from the coordinator's render-state rule rather than
        // letting the view re-derive it locally — the view doesn't know `isAITabState`, and
        // recomputing from `inputMode == .aiChat && enabled` alone would strip the AI toolbar
        // on a Duck.ai tab when the user disables the toggle.
        viewController.updateToggleEnabled(enabled, showsToolbar: computeRenderState().cardLayout.showsToolbar)
        let effective = effectiveInputMode(for: inputMode)
        let inputModeChanged = effective != inputMode
        if inputModeChanged {
            inputMode = effective
            syncInputBehaviorToHandler()
        }
        // Apply outside the inputMode gate so visibility-only flips (kill switch on Duck.ai tabs) still propagate to the view.
        viewController.apply(computeRenderState().viewConfig, animated: false)
        if inputModeChanged {
            refreshToolsPresentation()
            modeChangeSubject.send(effective)
            syncAttachmentValidationErrorForCurrentMode()
        }
        updateFloatingReturnKeyState()
    }

    /// Without a visible toggle the user can't switch mode — omnibar locks to `.search`, AI tabs to `.aiChat`.
    /// Keyed on `isToggleVisible` so the clamp fires when the kill switch hides the toggle, not just when the setting is off.
    private func effectiveInputMode(for requestedMode: TextEntryMode) -> TextEntryMode {
        guard !isToggleVisible else { return requestedMode }
        if isOmnibarSession { return .search }
        if isAITabState { return .aiChat }
        return requestedMode
    }

    func editingHeight() -> CGFloat {
        let screenWidth = viewController.view.window?.bounds.width ?? viewController.view.bounds.width
        let height = viewController.view.systemLayoutSizeFitting(
            CGSize(width: screenWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        return height
    }

    // MARK: - Text Management

    func setText(_ text: String) {
        currentText = text
        textState = text.isEmpty ? .empty : .userTyped
        viewController.text = text
        persistDraftToStore()
        updateFloatingReturnKeyState()
    }

    // MARK: - Input Management

    func updateInputMode(_ mode: TextEntryMode, animated: Bool) {
        let effectiveMode = effectiveInputMode(for: mode)
        let didModeChange = inputMode != effectiveMode
        let needsViewSync = viewController.inputMode != effectiveMode
        guard didModeChange || needsViewSync else { return }

        let isDismissingOmnibarNewPromptToolbar = isOmnibarNewAIChatPrompt && effectiveMode == .search
        if isDismissingOmnibarNewPromptToolbar {
            viewController.prepareToolbarSubmitStyleForDismissal()
        }

        if didModeChange && host == .omnibar {
            fireModeSwitchedPixel(to: effectiveMode)
        }

        inputMode = effectiveMode
        syncInputBehaviorToHandler()
        updateFloatingReturnKeyState()

        // Wraps toolbar-height update + content-swap broadcast in one CATransaction so they animate
        // together; otherwise the content snaps while the toolbar is still growing.
        let applyModeChange = { [self] in
            if needsViewSync {
                viewController.setInputMode(effectiveMode, animated: animated)
            }
            if didModeChange {
                modeChangeSubject.send(effectiveMode)
            }
        }

        if animated {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
                applyModeChange()
            }
        } else {
            applyModeChange()
        }

        applyToolbarPresentation()
        if didModeChange {
            syncAttachmentValidationErrorForCurrentMode()
            recordUserChoiceToStore()
        }
    }

    func updateAIVoiceChatAvailability(_ enabled: Bool) {
        viewController.handler.isAIVoiceChatEnabled = enabled
        updateToolbarAIVoiceChat()
    }

    func syncInputModeFromExternalSource(_ mode: TextEntryMode) {
        let effectiveMode = effectiveInputMode(for: mode)
        let didModeChange = inputMode != effectiveMode
        let needsViewSync = viewController.inputMode != effectiveMode
        guard didModeChange || needsViewSync else { return }

        inputMode = effectiveMode
        syncInputBehaviorToHandler()
        updateFloatingReturnKeyState()
        if needsViewSync {
            viewController.setInputMode(effectiveMode, animated: false)
        }
        if didModeChange {
            modeChangeSubject.send(effectiveMode)
            refreshToolsPresentation()
        }
        updateToolbarAIVoiceChat()
    }

    func updateOmnibarInputVisibility(_ isInputVisible: Bool) {
        guard isInputVisibleForKeyboard != isInputVisible else { return }
        isInputVisibleForKeyboard = isInputVisible
        syncInputBehaviorToHandler()
        updateFloatingReturnKeyState()
        let isAITabSearch = displayState == .aiTab(.expanded) && inputMode == .search

        switch (displayState, isInputVisible) {
        case (.omnibar(.active), false) where isAwaitingTopOmnibarKeyboardPresentation:
            return
        case (.omnibar(.active), false) where viewController.isInputFirstResponder:
            // A hardware keyboard is connected (or the keyboard frame went off-screen)
            // while the user is still actively editing. Treat the input as in-use and
            // skip the dismissal — otherwise the bar collapses on every keystroke.
            cancelTopOmnibarKeyboardPresentationFallback()
        case (.omnibar(.active), false):
            cancelTopOmnibarKeyboardPresentationFallback()
            transitionOmnibarToInactive()
        case (.omnibar(.inactive), true):
            cancelTopOmnibarKeyboardPresentationFallback()
            isAwaitingTopOmnibarKeyboardPresentation = false
            displayState = .omnibar(.active)
            syncInputBehaviorToHandler()
            updateFloatingReturnKeyState()
            let renderState = computeRenderState()
            viewController.apply(renderState.viewConfig, animated: false)
            intentSubject.send(.showOmnibarActive)
        case (.omnibar(.active), true):
            cancelTopOmnibarKeyboardPresentationFallback()
            isAwaitingTopOmnibarKeyboardPresentation = false
        case (.aiTab(.expanded), _) where isAITabSearch:
            let renderState = computeRenderState()
            viewController.apply(renderState.viewConfig, animated: false)
        default:
            break
        }
    }

    func activateInput() {
        guard !isOnboardingLocked else { return }
        viewController.activateInput()
    }

    /// The collapsed AI-tab fire button. Exposed for `ViewHighlighter` targeting during onboarding.
    var aiTabFireButton: UIButton { viewController.aiTabFireButton }

    /// Locks or unlocks the input bar during the Duck.ai onboarding experiment path.
    /// When locked the text field cannot be activated and the collapsed bar ignores taps.
    func setOnboardingControlsLocked(_ locked: Bool) {
        isOnboardingLocked = locked
        viewController.setOnboardingDimmed(locked)
    }

    func dismissOmnibarKeyboard() {
        switch displayState {
        case .omnibar(.active), .aiTab(.expanded):
            viewController.deactivateInput()
        default:
            return
        }
    }

    func setEscapeHatch(_ model: EscapeHatchModel) {
        contentViewController.setEscapeHatch(model)
    }

    func clearEscapeHatch() {
        contentViewController.setEscapeHatch(nil)
    }

    func updateVoiceSearchAvailability(_ enabled: Bool) {
        viewController.isVoiceSearchAvailable = enabled
    }

    func updateAIChatShortcutAvailability(_ available: Bool) {
        viewController.handler.isAIChatShortcutAvailable = available
    }

    func updateIsFireTab(_ isFireTab: Bool) {
        guard viewController.handler.isFireTab != isFireTab else { return }
        viewController.handler.isFireTab = isFireTab
        viewController.refreshFireMode(fireMode: isFireTab)
        contentViewController.refreshFireMode(fireMode: isFireTab)
    }

    private func cancelTopOmnibarKeyboardPresentationFallback() {
        topOmnibarKeyboardPresentationFallback?.cancel()
        topOmnibarKeyboardPresentationFallback = nil
    }

    private func scheduleTopOmnibarKeyboardPresentationFallback() {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  case .omnibar(.active) = self.displayState,
                  self.cardPosition == .top,
                  self.isAwaitingTopOmnibarKeyboardPresentation else {
                return
            }

            self.topOmnibarKeyboardPresentationFallback = nil
            if !self.isInputVisibleForKeyboard, !self.viewController.isInputFirstResponder {
                self.transitionOmnibarToInactive()
            } else {
                self.isAwaitingTopOmnibarKeyboardPresentation = false
            }
        }

        topOmnibarKeyboardPresentationFallback = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.topOmnibarKeyboardPresentationTimeout, execute: workItem)
    }

    private func transitionOmnibarToInactive() {
        isAwaitingTopOmnibarKeyboardPresentation = false
        displayState = .omnibar(.inactive)
        let renderState = computeRenderState()
        // Animated so a concurrent mode change doesn't get snapped to final layout non-animatedly.
        viewController.apply(renderState.viewConfig, animated: true)
        intentSubject.send(.showOmnibarInactive)
    }

    func clearText() {
        // Dismiss-time clear: scrub the visible input but keep the per-tab draft.
        // - Bypass setText() so coordinator.currentText (the source of truth for the
        //   flush snapshot) isn't reset to "".
        // - textState reflects what's visible, so reset it to .empty.
        // - The handler's text publisher still emits "" downstream (because the
        //   text view's text changes); the gate in unifiedToggleInputVC(_:didChangeText:)
        //   covers the queued sink that fires next runloop tick.
        isPerformingDismissCleanup = true
        textState = .empty
        viewController.text = ""
        DispatchQueue.main.async { [weak self] in
            self?.isPerformingDismissCleanup = false
        }
    }

    func stopGeneratingButtonTapped() {
        viewController.handler.stopGeneratingButtonTapped()
    }

    // MARK: - External Submissions

    var hasBoundUserScript: Bool {
        boundUserScript != nil
    }

    func submitVoicePrompt(_ text: String) {
        guard let userScript = boundUserScript else { return }
        let configuration = voicePromptSubmissionConfiguration
        recordDuckAISubmissionStarted(
            modelId: configuration.modelId,
            reasoningEffort: configuration.reasoningEffort,
            inputMode: .voice,
            frontendDeliveryPath: .userScript,
            hasPageContext: userScript.attachedPageContextProvider?() != nil,
            toolsSelected: false,
            attachmentsSelected: false
        )
        markActiveChatPromptSubmitted()
        resetToolsSelection()
        clearStoreEntryAfterSubmission()
        showCollapsed()
        let didSendBridgeMessage = userScript.canDispatchBridgeMessages
        userScript.submitPrompt(text, images: nil, modelId: configuration.modelId, reasoningEffort: configuration.reasoningEffort)
        recordDuckAIPromptDelivered(wasQueued: false, didSendBridgeMessage: didSendBridgeMessage)
    }

    func prepareExternalPromptSubmission() -> (modelId: String?, reasoningEffort: AIChatReasoningEffort?) {
        let configuration = promptSubmissionConfiguration
        markActiveChatPromptSubmitted()
        return (configuration.modelId, configuration.reasoningEffort)
    }

    func handleExternalSubmission(_ type: ExternalSubmissionType) {
        commitCurrentToggleState()
        // External submissions (suggestion taps, voice, intent dispatch) bypass
        // unifiedToggleInputVC(_:didSubmitText:mode:), so the per-tab store entry
        // would otherwise retain the just-submitted text and be restored on the
        // next activation of the same tab. Mirror the internal-submit cleanup.
        clearStoreEntryAfterSubmission()
        switch displayState {
        case .omnibar:
            deactivateToOmnibar()
        case .aiTab:
            switch type {
            case .query: hide()
            case .prompt:
                resetToolsSelection()
                clearAttachments()
                showCollapsed()
            }
        case .hidden:
            break
        }
    }

    // MARK: - Toggle State Persistence

    private func setInitialInputMode(_ mode: TextEntryMode) {
        inputMode = mode
        committedInputMode = mode
        syncInputBehaviorToHandler()
    }

    private func commitCurrentToggleState() {
        committedInputMode = inputMode
        stateStore.commitToggleMode(inputMode)
        delegate?.unifiedToggleInputDidCommitMode(inputMode)
    }

    // MARK: - Content & Layout

    func pushContentInsets() {
        // Use the deterministic target height (same source adjustUI uses for the navbar
        // constraint) while editing, so the content inset animates in lockstep with the
        // input instead of chasing transient frame values mid-animation.
        let utiHeight = isInputEditing ? editingHeight() : viewController.view.frame.height
        if cardPosition == .top {
            contentViewController.setContentInset(top: utiHeight, bottom: 0)
        } else {
            contentViewController.setContentInset(top: 0, bottom: utiHeight)
        }
    }

    func syncContentInputMode(_ mode: TextEntryMode, animated: Bool = true) {
        contentViewController.setInputMode(mode, animated: animated)
    }

    func setContentOverlaySuppressed(_ suppressed: Bool) {
        isContentOverlaySuppressed = suppressed
    }

    // MARK: - Render State

    func computeRenderState() -> UTIRenderState {
        let isExpanded: Bool
        let isInputVisible: Bool
        let isContentVisible: Bool
        let inactiveAppearance: Bool

        switch displayState {
        case .hidden:
            isExpanded = false
            isInputVisible = false
            isContentVisible = false
            inactiveAppearance = false

        case .aiTab(.collapsed):
            isExpanded = false
            isInputVisible = true
            isContentVisible = false
            inactiveAppearance = false

        case .aiTab(.expanded):
            isExpanded = true
            isInputVisible = true
            let isAIChatOnAITab = isAITabState && inputMode == .aiChat
            let isSearchOnAITab = isAITabState && inputMode == .search
            // Toggling to Search on a chat tab without visible text is a mode switch — keep the
            // chat web view; `textState` (not `currentText`) excludes preserved drafts from
            // dismiss-cleanup.
            let isSearchOnAITabWithoutText = isSearchOnAITab && textState == .empty
            isContentVisible = !(isAIChatOnAITab || isSearchOnAITabWithoutText)
            let isSearchKeyboardHidden = isSearchOnAITab && !isInputVisibleForKeyboard
            inactiveAppearance = isSearchKeyboardHidden

        case .omnibar(.active):
            isExpanded = true
            isInputVisible = true
            isContentVisible = true
            inactiveAppearance = false

        case .omnibar(.inactive):
            isExpanded = true
            isInputVisible = true
            isContentVisible = true
            inactiveAppearance = (cardPosition == .bottom)
        }

        let floatingReturnKeyState = makeFloatingReturnKeyState()
        let canShowFloatingReturnKey = floatingReturnKeyState.canInsertReturn
        let shouldSuppressContentOverlay = isOmnibarSession && isContentOverlaySuppressed && textState != .userTyped
        let effectiveContentVisible = isContentVisible && !shouldSuppressContentOverlay

        return UTIRenderState(
            isInputVisible: isInputVisible,
            isContentVisible: effectiveContentVisible,
            cardLayout: cardLayout(forIsExpanded: isExpanded),
            cardPosition: cardPosition,
            usesOmnibarMargins: cardPosition == .top && isOmnibarSession,
            inactiveAppearance: inactiveAppearance,
            isFloatingReturnKeyVisible: canShowFloatingReturnKey,
            contentInputMode: inputMode,
            inputMode: inputMode,
            isAITab: isAITabState
        )
    }

    /// Whether the toggle row appears in the UTI and the swipe-between-modes gesture is active.
    /// Combines user setting + Duck.ai-tab hide flag; the kill-switch term drops out on non-AI tabs.
    var isToggleVisible: Bool {
        isToggleEnabled && !(hidesToggleOnDuckAITab && isAITabState)
    }

    /// Decides which card components are visible right now, based on host + display state +
    /// toggle setting + input mode. Centralised here so the view layer just renders.
    private func cardLayout(forIsExpanded isExpanded: Bool) -> UnifiedToggleInputCardLayout {
        guard isExpanded else {
            return isAITabState ? .flanked : .collapsed
        }
        switch host {
        case .contextualChat:
            return .expanded(showsToggle: false, showsToolbar: true)
        case .omnibar:
            // Keep the AI-chat toolbar on Duck.ai tabs even when the toggle is hidden,
            // so the user retains the model selector / attachments / send affordances.
            let showsToolbar = inputMode == .aiChat && (isToggleEnabled || isAITabState)
            return .expanded(showsToggle: isToggleVisible, showsToolbar: showsToolbar)
        }
    }

    // MARK: - Models

    let modelStore: UTIModelStore
    private(set) var hasSubmittedPrompt = false

    var models: [AIChatModel] { modelStore.models }
    var subscriptionState: SubscriptionState { modelStore.subscriptionState }
    var persistedModelId: String? { modelStore.persistedModelId }
    var currentModelId: String? { modelStore.currentModelId }
    var persistedReasoningMode: AIChatReasoningMode? { modelStore.selectedReasoningMode }
    var selectedModel: AIChatModel? { modelStore.selectedModel }
    var selectedModelSupportsImageUpload: Bool { modelStore.selectedModelSupportsImageUpload }
    var selectedModelSupportsFileUpload: Bool { modelStore.selectedModelSupportsFileUpload }
    var selectedModelSupportedFileTypes: [String] { modelStore.selectedModelSupportedFileTypes }
    var selectedTool: AIChatRAGTool? { toolsController.selectedTool }

    func fetchModels() {
        modelStore.fetchModels()
    }

    func refreshModelsAfterSubscriptionChange() {
        fetchModels()
    }

    func startNewChat() {
        isNewChatPending = true
        hasSubmittedPrompt = false
        isModelPickerForcedVisible = false
        isSubmitBlockedByRecoveryCard = false
        resetToolsSelection()
        updateModelChipVisibility()
        syncHasSubmittedPromptToHandler()
        clearAttachments()
        setText("")
        attachmentUsage = nil
        aiChatInputBoxVisibility = .visible
        isVoiceSessionActive = false
    }

    func updateSelectedModel(_ modelId: String) {
        modelStore.updateSelectedModel(modelId, isNewChatContext: isNewChatContext)
        handleModelsUpdated()
        recordUserChoiceToStore()
    }

    /// Tells the FE to switch the active chat's model via the `submitChangeModelAction` bridge push.
    /// No-op for a new chat that hasn't submitted yet — there the model rides in the first
    /// `submitAIChatNativePrompt`.
    private func notifyFrontendOfActiveChatModelChange(_ modelId: String) {
        guard hasSubmittedPrompt, let userScript = boundUserScript else {
            return
        }
        userScript.submitChangeModel(modelId)
        guard isModelPickerForcedVisible, userScript.canDispatchBridgeMessages else {
            return
        }
        UnifiedToggleInputCoordinatorPixelHelper.fireSubmitChangeModelPixel(modelId: modelId)
    }

    /// Surfaces the native model picker on the **active** chat in response to the FE's
    /// `showModelPicker` (e.g. the recovery card's "Switch Model" CTA). Expands the input and
    /// reveals the model chip **without starting a new chat** — the chat stays `hasSubmittedPrompt`,
    /// so a subsequent supported-model selection still emits `submitChangeModelAction`.
    func presentModelPickerForActiveChat() {
        isModelPickerForcedVisible = true
        showExpanded(inputMode: .aiChat)
        if isSubmitBlockedByRecoveryCard,
           let supportedModel = modelStore.selectedModel,
           supportedModel.entityHasAccess {
            isSubmitBlockedByRecoveryCard = false
            notifyFrontendOfActiveChatModelChange(supportedModel.id)
        }
        // Defer to the next runloop so the toolbar (and the now-revealed chip) is laid out after the
        // expand animation before we ask the button to open its menu.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            UnifiedToggleInputCoordinatorPixelHelper.fireShowModelPickerPixel()
            self.viewController.presentModelPickerMenu()
        }
    }

    func handleModelSelection(_ modelId: String) {
        guard let model = modelStore.models.first(where: { $0.id == modelId }) else {
            return
        }

        if model.entityHasAccess {
            let isNewSelection = modelId != modelStore.persistedModelId
            pendingGatedModelId = nil
            // Supported model picked in the native picker — the recovery card's reason to block
            // submit is gone, so drop the block (no-op when it wasn't set).
            isSubmitBlockedByRecoveryCard = false
            updateSelectedModel(modelId)
            if isNewSelection {
                Pixel.fire(pixel: .unifiedToggleInputModelSelected, withAdditionalParameters: ["model_id": modelId])
            }
            notifyFrontendOfActiveChatModelChange(modelId)
        } else {
            if routeGatedModelSelection(model) {
                pendingGatedModelId = modelId
            }
            refreshModelPickerMenuAfterRejectedSelection()
        }
    }

    @discardableResult
    private func routeGatedModelSelection(_ model: AIChatModel) -> Bool {
        guard let requiredPublicTier = model.lowestPublicAccessTier else {
            Logger.unifiedInputState.debug("Gated model has no public access tier: \(model.id, privacy: .public)")
            return false
        }

        let userTier = subscriptionState.userTier

        if userTier == .free, requiredPublicTier == .plus || requiredPublicTier == .pro {
            UnifiedToggleInputCoordinatorPixelHelper.fireSubscriptionUpsellTriggeredPixel(
                source: .modelPicker,
                currentTier: userTier,
                requiredTier: requiredPublicTier,
                flowType: .purchase
            )
            presentPurchaseFlow(source: .modelPicker)
            return true
        }

        if userTier == .plus, requiredPublicTier == .pro {
            UnifiedToggleInputCoordinatorPixelHelper.fireSubscriptionUpsellTriggeredPixel(
                source: .modelPicker,
                currentTier: userTier,
                requiredTier: requiredPublicTier,
                flowType: .upgrade
            )
            presentUpgradeFlow(source: .modelPicker)
            return true
        }

        Logger.unifiedInputState.debug("No native subscription flow for gated model")
        return false
    }

    private func presentPurchaseFlow(source: SubscriptionFlowSource) {
        NotificationCenter.default.post(
            name: .settingsDeepLinkNotification,
            object: SettingsViewModel.SettingsDeepLinkSection.subscriptionFlow(
                redirectURLComponents: makeSubscriptionRedirectURLComponents(source: source)
            )
        )
    }

    private func presentUpgradeFlow(source: SubscriptionFlowSource) {
        NotificationCenter.default.post(
            name: .settingsDeepLinkNotification,
            object: SettingsViewModel.SettingsDeepLinkSection.subscriptionPlanChangeFlow(
                redirectURLComponents: makeSubscriptionRedirectURLComponents(source: source)
            )
        )
    }

    private func makeSubscriptionRedirectURLComponents(source: SubscriptionFlowSource) -> URLComponents {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "featurePage", value: Constants.subscriptionFeaturePage),
            URLQueryItem(name: AttributionParameter.origin, value: subscriptionOrigin(for: source).rawValue)
        ]
        return components
    }

    private func subscriptionOrigin(for source: SubscriptionFlowSource) -> SubscriptionFunnelOrigin {
        switch (isAITabState, source) {
        case (true, .modelPicker):
            return .duckAIModelPicker
        case (true, .reasoningPicker):
            return .duckAIReasoningPicker
        case (false, .modelPicker):
            return .addressBarModelPicker
        case (false, .reasoningPicker):
            return .addressBarReasoningPicker
        }
    }

    private func refreshModelPickerMenuAfterRejectedSelection() {
        DispatchQueue.main.async { [weak self] in
            self?.updateModelChipLabel()
        }
    }

    private func refreshReasoningPickerMenuAfterRejectedSelection() {
        DispatchQueue.main.async { [weak self] in
            self?.updateReasoningPicker()
        }
    }

    @discardableResult
    private func applyPendingGatedModelSelectionIfPossible() -> Bool {
        guard let modelId = pendingGatedModelId,
              modelStore.models.first(where: { $0.id == modelId })?.entityHasAccess == true else {
            return false
        }

        let isNewSelection = modelId != modelStore.persistedModelId
        pendingGatedModelId = nil
        // Mirror the direct-selection path: the gated model in the recovery-card
        // is now accessible (post-purchase), so drop the recovery-card submit block.
        isSubmitBlockedByRecoveryCard = false
        updateSelectedModel(modelId)
        if isNewSelection {
            Pixel.fire(pixel: .unifiedToggleInputModelSelected, withAdditionalParameters: ["model_id": modelId])
        }
        notifyFrontendOfActiveChatModelChange(modelId)
        return true
    }

    private func applyPendingGatedReasoningSelectionIfPossible() {
        guard let pendingSelection = pendingGatedReasoningSelection else { return }
        guard let selectedModel, selectedModel.id == pendingSelection.modelId else {
            pendingGatedReasoningSelection = nil
            return
        }

        if let requiredPublicTier = requiredPublicTier(for: pendingSelection.mode, model: selectedModel),
           !canSelectReasoningModeRequiringTier(requiredPublicTier) {
            return
        }

        pendingGatedReasoningSelection = nil
        updateSelectedReasoningMode(pendingSelection.mode)
        fireReasoningEffortSelectedPixel(mode: pendingSelection.mode)
    }

    func updateSelectedReasoningMode(_ mode: AIChatReasoningMode) {
        modelStore.updateSelectedReasoningMode(mode)
        updateReasoningPicker()
        recordUserChoiceToStore()
    }

    func handleReasoningModeSelection(_ mode: AIChatReasoningMode) {
        guard let selectedModel else { return }
        guard let requiredPublicTier = requiredPublicTier(for: mode, model: selectedModel) else {
            pendingGatedReasoningSelection = nil
            updateSelectedReasoningMode(mode)
            fireReasoningEffortSelectedPixel(mode: mode)
            return
        }

        if canSelectReasoningModeRequiringTier(requiredPublicTier) {
            pendingGatedReasoningSelection = nil
            updateSelectedReasoningMode(mode)
            fireReasoningEffortSelectedPixel(mode: mode)
        } else {
            if routeGatedReasoningModeSelection(requiredPublicTier: requiredPublicTier) {
                pendingGatedReasoningSelection = (selectedModel.id, mode)
            }
            refreshReasoningPickerMenuAfterRejectedSelection()
        }
    }

    private func fireReasoningEffortSelectedPixel(mode: AIChatReasoningMode) {
        Pixel.fire(pixel: .unifiedToggleInputReasoningEffortSelected, withAdditionalParameters: ["effort_level": mode.rawValue])
    }
    
    private func requiredPublicTier(for mode: AIChatReasoningMode, model: AIChatModel) -> AIChatModelPublicAccessTier? {
        guard !model.accessibleReasoningModes.contains(mode) else { return nil }
        guard let effort = model.reasoningEffort(for: mode) else { return nil }
        return model.lowestPublicAccessTier(for: effort)
    }

    private func canSelectReasoningModeRequiringTier(_ requiredTier: AIChatModelPublicAccessTier) -> Bool {
        switch requiredTier {
        case .free:
            return true
        case .plus:
            return subscriptionState.userTier != .free
        case .pro:
            return subscriptionState.userTier == .pro || subscriptionState.userTier == .internal
        }
    }

    @discardableResult
    private func routeGatedReasoningModeSelection(requiredPublicTier: AIChatModelPublicAccessTier) -> Bool {
        let userTier = subscriptionState.userTier

        if userTier == .free, requiredPublicTier == .plus || requiredPublicTier == .pro {
            UnifiedToggleInputCoordinatorPixelHelper.fireSubscriptionUpsellTriggeredPixel(
                source: .reasoningPicker,
                currentTier: userTier,
                requiredTier: requiredPublicTier,
                flowType: .purchase
            )
            presentPurchaseFlow(source: .reasoningPicker)
            return true
        }

        if userTier == .plus, requiredPublicTier == .pro {
            UnifiedToggleInputCoordinatorPixelHelper.fireSubscriptionUpsellTriggeredPixel(
                source: .reasoningPicker,
                currentTier: userTier,
                requiredTier: requiredPublicTier,
                flowType: .upgrade
            )
            presentUpgradeFlow(source: .reasoningPicker)
            return true
        }

        Logger.unifiedInputState.debug("No native subscription flow for gated reasoning mode")
        return false
    }

    func selectTool(_ tool: AIChatRAGTool) {
        toolsController.select(tool, for: modelStore)
        refreshToolsPresentation()
        recordUserChoiceToStore()
    }

    func clearSelectedTool() {
        resetToolsSelection()
        recordUserChoiceToStore()
    }

    private func updateModelChipLabel() {
        let selectedId = modelStore.persistedModelId
        let shortName = modelMenuFactory.selectedShortName(models: modelStore.models, selectedId: selectedId)
        if let shortName {
            viewController.modelName = shortName
        }
        viewController.modelPickerMenu = modelStore.models.isEmpty ? nil : modelMenuFactory.makeMenu(
            models: modelStore.models,
            selectedId: selectedId,
            plusSectionTitle: UserText.aiChatPlusModelsSectionHeader,
            proSectionTitle: UserText.aiChatProModelsSectionHeader
        ) { [weak self] modelId in
            self?.handleModelSelection(modelId)
        }
    }

    private func buildReasoningPickerMenu() -> UIMenu? {
        guard let selectedModel, selectedModel.supportsReasoningPicker else { return nil }

        let selectedMode = resolvedSelectedReasoningMode
        let actions = selectedModel.availableReasoningModes.map { mode in
            UIAction(
                title: mode.unifiedToggleInputTitle,
                subtitle: mode.unifiedToggleInputSubtitle,
                image: mode.unifiedToggleInputMenuImage,
                state: mode == selectedMode ? .on : .off
            ) { [weak self] _ in
                self?.handleReasoningModeSelection(mode)
            }
        }

        return UIMenu(options: .singleSelection, children: actions)
    }

    private func updateReasoningPicker() {
        if toolsController.selectedTool == .imageGeneration {
            // Reasoning effort doesn't apply to image generation; hide the picker without touching the persisted
            // mode so the previous selection returns when the user deselects the image-gen tool.
            viewController.isReasoningButtonHidden = true
            viewController.reasoningPickerMenu = nil
            return
        }
        let selectedMode = resolvedSelectedReasoningMode
        let shouldHide = !(selectedModel?.supportsReasoningPicker ?? false)
        viewController.selectedReasoningMode = selectedMode
        viewController.isReasoningButtonHidden = shouldHide
        viewController.reasoningPickerMenu = shouldHide ? nil : buildReasoningPickerMenu()
    }

    // MARK: - Attachments

    var remainingImagesInConversation: Int {
        attachmentPolicy.remainingImagesInConversation
    }

    var remainingImagesForPicker: Int {
        attachmentPolicy.remainingImagesForPicker
    }

    var isConversationImageLimitReached: Bool {
        attachmentPolicy.isConversationImageLimitReached
    }

    /// Optional override for the view controller used to present pickers (camera/photo library).
    /// Hosts that embed the UTI inside another presented stack (e.g. the contextual chat half-sheet)
    /// must set this so the picker presents from the correct level.
    weak var attachmentPresentingViewController: UIViewController?

    var allowedFileUTTypes: [UTType] {
        selectedModelSupportedFileTypes.compactMap(Self.contentType(for:))
    }

    func addImageAttachment(image: UIImage, fileName: String) {
        guard attachmentPolicy.canAttachImages else { return }
        let attachment = UnifiedToggleInputAttachment.image(AIChatImageAttachment(image: image, fileName: fileName))
        viewController.addAttachment(attachment)
        persistDraftToStore()
        clearAttachmentValidationErrorIfPossible()
        updateAttachButtonPresentation()
    }

    func addFileAttachment(_ fileAttachment: AIChatFileAttachment, sourceURL: URL? = nil) {
        if let validationError = attachmentPolicy.fileValidationError(for: fileAttachment) {
            DailyPixel.fireDailyAndCount(
                pixel: .unifiedToggleInputFileValidationFailed,
                withAdditionalParameters: ["reason": validationError.reason.rawValue]
            )
            viewController.addAttachment(.invalidFile(
                UnifiedToggleInputInvalidFileAttachment(
                    id: fileAttachment.id,
                    fileName: fileAttachment.fileName,
                    mimeType: fileAttachment.mimeType,
                    fileSizeBytes: fileAttachment.fileSizeBytes,
                    validationMessage: validationError.message,
                    sourceURL: sourceURL
                )
            ))
            presentAttachmentValidationError(validationError.message)
            persistDraftToStore()
            updateAttachButtonPresentation()
            return
        }

        DailyPixel.fireDailyAndCount(pixel: .unifiedToggleInputFileAttached)
        viewController.addAttachment(.file(fileAttachment))
        persistDraftToStore()
        clearAttachmentValidationErrorIfPossible()
        updateAttachButtonPresentation()
    }

    func removeAttachment(id: UUID) {
        invalidAttachmentRecoveryTasks[id]?.cancel()
        invalidAttachmentRecoveryTasks[id] = nil
        viewController.removeAttachment(id: id)
        persistDraftToStore()
        syncAttachmentValidationErrorForCurrentMode()
        updateAttachButtonPresentation()
    }

    func clearAttachments() {
        guard !viewController.currentAttachments.isEmpty else {
            viewController.clearAttachmentValidationError()
            updateAttachButtonPresentation()
            return
        }
        cancelInvalidAttachmentRecoveryTasks()
        viewController.removeAllAttachments()
        viewController.clearAttachmentValidationError()
        persistDraftToStore()
        updateAttachButtonPresentation()
    }

    func updateImageButtonVisibility() {
        updateAttachButtonVisibility()
    }

    func updateAttachButtonVisibility() {
        updateAttachButtonPresentation()
    }

    // MARK: - Session Management

    @MainActor
    private static func resetSessionFlags() {
        hasUsedSearchInSession = false
        hasUsedAIChatInSession = false
    }

}

// MARK: - Tools Menu Selection

extension UnifiedToggleInputCoordinator {
    
    func handleToolsMenuSelection(_ identifier: UTIToolsMenu.Item.Identifier) {
        if case .customizeResponses = identifier {
            UnifiedToggleInputCoordinatorPixelHelper.fireCustomizeResponsesSelectedPixel()
            viewController.handler.customizeResponsesButtonTapped()
            return
        }

        let previousTool = toolsController.selectedTool
        switch identifier {
        case .webSearch:
            toolsController.toggleSelection(for: .webSearch, modelStore: modelStore)
        case .imageGeneration:
            toolsController.toggleSelection(for: .imageGeneration, modelStore: modelStore)
        case .customizeResponses:
            return
        }
        let currentTool = toolsController.selectedTool
        fireToolToggleTransitionPixel(previous: previousTool, current: currentTool)
        refreshToolsPresentation()
        recordUserChoiceToStore()
    }

    private func fireToolToggleTransitionPixel(previous: AIChatRAGTool?, current: AIChatRAGTool?) {
        guard previous != current else { return }
        if let previous, current == nil || current != previous {
            UnifiedToggleInputCoordinatorPixelHelper.fireToolDeselectedPixel(for: previous)
        }
        if let current {
            UnifiedToggleInputCoordinatorPixelHelper.fireToolSelectedPixel(for: current)
        }
    }
}

// MARK: - UnifiedToggleInputViewControllerDelegate

extension UnifiedToggleInputCoordinator: UnifiedToggleInputViewControllerDelegate {

    func unifiedToggleInputVCDidTapWhileCollapsed(_ vc: UnifiedToggleInputViewController) {
        guard !isOnboardingLocked else { return }
        if host == .omnibar {
            delegate?.unifiedToggleInputDidTapToActivate()
        }
        showExpanded(inputMode: inputMode)
    }

    func unifiedToggleInputVCDidRequestSubmitCurrentInput(_ vc: UnifiedToggleInputViewController) {
        submitCurrentInputFromCoordinator()
    }

    func unifiedToggleInputVCDidTapReturnKey(_ vc: UnifiedToggleInputViewController) {
        insertNewlineFromFloatingReturnKey()
    }

    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didSubmitText text: String, mode: TextEntryMode) {
        commitCurrentToggleState()

        switch mode {
        case .search:
            if !URL.isValidAddressBarURLInput(text) {
                switchBarSubmissionMetrics.process(text, for: .search)
            }
            processSessionActivity(mode: .search)
            clearStoreEntryAfterSubmission()
            if case .aiTab = displayState {
                hide()
            } else if isOmnibarSession {
                deactivateToOmnibar()
            }
            delegate?.unifiedToggleInputDidSubmitQuery(text)
            didSubmitQuery.send(text)
        case .aiChat:
            let userScript = boundUserScript
            let tools = toolsController.selectedToolsForSubmission()

            if let validationMessage = attachmentSubmissionValidationMessage(for: text, mode: mode) {
                presentAttachmentValidationError(validationMessage)
                return
            }

            switchBarSubmissionMetrics.process(text, for: .aiChat)
            processSessionActivity(mode: .aiChat)
            UnifiedToggleInputCoordinatorPixelHelper.fireUnifiedPromptSubmittedPixel(
                text: text,
                selectedTool: toolsController.selectedTool,
                attachments: viewController.currentAttachments,
                reasoningMode: reasoningModeForSubmitPixel,
                modelId: modelStore.persistedModelId
            )
            UnifiedToggleInputCoordinatorPixelHelper.fireToolSubmittedPixelIfNeeded(
                selectedTool: toolsController.selectedTool,
                attachments: viewController.currentAttachments
            )

            let configuration = promptSubmissionConfiguration
            recordDuckAISubmissionStarted(
                modelId: configuration.modelId,
                reasoningEffort: configuration.reasoningEffort,
                inputMode: .keyboard,
                frontendDeliveryPath: userScript != nil ? .userScript : .urlAutoSubmit,
                hasPageContext: userScript?.attachedPageContextProvider?() != nil,
                toolsSelected: !(tools?.isEmpty ?? true),
                attachmentsSelected: !viewController.currentAttachments.isEmpty
            )

            let images = selectedModelSupportsImageUpload
                ? UnifiedToggleInputImageEncoder.encode(viewController.currentAttachments)
                : nil
            let files = selectedModelSupportsFileUpload
                ? UnifiedToggleInputFileEncoder.encode(viewController.currentAttachments)
                : nil

            resetToolsSelection()
            clearStoreEntryAfterSubmission()
            clearAttachments()
            if isOmnibarNewAIChatPrompt {
                viewController.prepareToolbarSubmitStyleForDismissal()
            }
            markActiveChatPromptSubmitted()
            if isOmnibarSession {
                deactivateToOmnibar()
            } else {
                // showCollapsed has no dismiss hook; clear synchronously.
                setText("")
                showCollapsed()
            }
            if let userScript {
                let didSendBridgeMessage = userScript.canDispatchBridgeMessages
                userScript.submitPrompt(text, images: images, files: files, modelId: configuration.modelId, tools: tools, reasoningEffort: configuration.reasoningEffort)
                recordDuckAIPromptDelivered(wasQueued: false, didSendBridgeMessage: didSendBridgeMessage)
            } else {
                delegate?.unifiedToggleInputDidSubmitPrompt(text, modelId: configuration.modelId, tools: tools, reasoningEffort: configuration.reasoningEffort, images: images, files: files)
            }
        }
    }

    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didChangeText text: String) {
        if isPerformingDismissCleanup { return }
        currentText = text
        textState = text.isEmpty ? .empty : .userTyped
        persistDraftToStore()
        clearAttachmentValidationErrorIfPossible()
        updateFloatingReturnKeyState()
        textChangeSubject.send(text)
    }

    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didChangeMode mode: TextEntryMode) {
        updateInputMode(mode, animated: true)
    }

    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, isDraggingToggle isDragging: Bool) {
        // While the toggle pill is in flight, suppress the content swipe-between-modes gesture so the
        // two animations can't run concurrently and glitch each other. On release, restore swipe to
        // whatever toggle visibility dictates (the single source of truth for the gesture).
        contentViewController.isSwipeEnabled = isDragging ? false : isToggleVisible
    }

    func unifiedToggleInputVCDidClearSelectedTool(_ vc: UnifiedToggleInputViewController) {
        let previousTool = toolsController.selectedTool
        clearSelectedTool()
        if let previousTool {
            UnifiedToggleInputCoordinatorPixelHelper.fireToolDeselectedPixel(for: previousTool)
        }
    }

    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didRemoveAttachment id: UUID, attachment: UnifiedToggleInputAttachment, isUserInitiated: Bool) {
        removeAttachment(id: id)
        if isUserInitiated {
            UnifiedToggleInputCoordinatorPixelHelper.fireAttachmentRemovedPixel(for: attachment)
        }
    }

    func unifiedToggleInputVCDidChangeAttachments(_ vc: UnifiedToggleInputViewController) {
        attachmentsChangeSubject.send()
        updateImageButtonEnabledState()
        updateFloatingReturnKeyState()
    }

    func unifiedToggleInputVCDidChangeHeight(_ vc: UnifiedToggleInputViewController) {
        delegate?.unifiedToggleInputDidChangeHeight()
    }

    func unifiedToggleInputVCDidTapInlineDismiss(_ vc: UnifiedToggleInputViewController) {
        if host == .omnibar {
            Pixel.fire(pixel: .aiChatExperimentalOmnibarBackButtonPressed, withAdditionalParameters: ["mode": inputMode.rawValue])
        }
        // Visual-only snap to the omnibar destination; then route through the shared dismiss handler.
        vc.applyDismissSnapshot(delegate?.unifiedToggleInputDismissSnapshot() ?? .empty)
        contentViewController.onDismissRequested?()
    }

    func unifiedToggleInputVCDidTapAIChatShortcut(_ vc: UnifiedToggleInputViewController) {
        let prefilledText = viewController.handler.currentText
        // Outside omnibar editing the chip can't dismiss-to-omnibar; preserve the original
        // straight-to-chat behavior to avoid wrong-destination collapses.
        guard isOmnibarSession else {
            delegate?.unifiedToggleInputDidRequestAIChat(prefilledText: prefilledText)
            return
        }
        // Defer the chat request to the dismiss completion — its side-effects (omniBar.endEditing,
        // sheet present, tab refresh) clobber the in-flight UTI mid-collapse otherwise.
        vc.applyDismissSnapshot(delegate?.unifiedToggleInputDismissSnapshot() ?? .empty)
        onAnimatedDismissToOmnibar?({ [weak self] in
            self?.delegate?.unifiedToggleInputDidRequestAIChat(prefilledText: prefilledText)
        })
    }

    func unifiedToggleInputVCDidTapFire(_ vc: UnifiedToggleInputViewController) {
        delegate?.unifiedToggleInputDidRequestFire()
    }

    func unifiedToggleInputVCDidTapAppMenu(_ vc: UnifiedToggleInputViewController) {
        guard !isOnboardingLocked else { return }
        delegate?.unifiedToggleInputDidRequestAppMenu()
    }
}

extension UnifiedToggleInputCoordinator {

    func insertNewlineFromFloatingReturnKey() {
        Pixel.fire(pixel: .aiChatExperimentalOmnibarFloatingReturnPressed)
        viewController.insertNewlineAtCursor()
    }

}

private extension UnifiedToggleInputCoordinator {

    func submitCurrentInputFromCoordinator() {
        let hasText = !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasValidAttachment = inputMode == .aiChat && viewController.currentAttachments.contains { !$0.isInvalid }
        let hasInvalidAttachment = inputMode == .aiChat && viewController.currentAttachments.contains(where: \.isInvalid)

        guard !hasInvalidAttachment && (hasText || hasValidAttachment) else {
            if hasInvalidAttachment {
                syncAttachmentValidationErrorForCurrentMode()
            }
            return
        }

        if let validationMessage = attachmentSubmissionValidationMessage(for: currentText, mode: inputMode) {
            presentAttachmentValidationError(validationMessage)
            return
        }

        if currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, inputMode == .aiChat {
            viewController.handler.submitAIChatAttachmentOnlyPrompt()
        } else {
            viewController.handler.submitText(currentText)
        }
    }

    // MARK: Attachments

    var canPresentFilePicker: Bool {
        attachmentPolicy.canAttachFiles && !allowedFileUTTypes.isEmpty
    }

    func expandIfOnAITab() {
        if case .aiTab = displayState {
            showExpanded()
        }
    }

    var attachmentPresenterViewController: UIViewController? {
        if let attachmentPresentingViewController {
            return attachmentPresentingViewController
        }
        guard let scene = viewController.view.window?.windowScene else { return nil }
        return scene.keyWindow?.rootViewController
    }

    static func contentType(for mimeType: String) -> UTType? {
        UTType(mimeType: mimeType)
    }

    func addInvalidFileAttachment(
        metadata: UnifiedToggleInputAttachmentPresenter.FileMetadata,
        validationMessage: String
    ) {
        viewController.addAttachment(.invalidFile(
            UnifiedToggleInputInvalidFileAttachment(
                fileName: metadata.fileName,
                mimeType: metadata.mimeType,
                fileSizeBytes: metadata.fileSizeBytes ?? 0,
                validationMessage: validationMessage,
                sourceURL: metadata.url
            )
        ))
        persistDraftToStore()
        updateAttachButtonPresentation()
        presentAttachmentValidationError(validationMessage)
    }

    func revalidateInvalidAttachmentsForSelectedModel() {
        var didChange = false

        for attachment in viewController.currentAttachments {
            guard case .invalidFile(let invalidAttachment) = attachment else { continue }
            didChange = revalidateInvalidAttachment(invalidAttachment) || didChange
        }

        guard didChange else { return }
        finishAttachmentRevalidation()
    }

    @discardableResult
    func revalidateInvalidAttachment(_ attachment: UnifiedToggleInputInvalidFileAttachment) -> Bool {
        if let validationMessage = metadataValidationMessage(for: attachment) {
            invalidAttachmentRecoveryTasks[attachment.id]?.cancel()
            invalidAttachmentRecoveryTasks[attachment.id] = nil
            return replaceInvalidAttachment(attachment, validationMessage: validationMessage)
        }

        guard attachment.sourceURL != nil else {
            return false
        }

        recoverInvalidAttachmentFromSourceURL(attachment)
        return false
    }

    func recoverInvalidAttachmentFromSourceURL(_ attachment: UnifiedToggleInputInvalidFileAttachment) {
        guard invalidAttachmentRecoveryTasks[attachment.id] == nil,
              let metadata = fileMetadata(for: attachment) else { return }

        let attachmentID = attachment.id
        invalidAttachmentRecoveryTasks[attachmentID] = Task.detached(priority: .userInitiated) { [weak self] in
            let fileAttachment = UnifiedToggleInputAttachmentPresenter.recoverFileAttachment(from: metadata, id: attachmentID)
            guard !Task.isCancelled else { return }
            await self?.completeInvalidAttachmentRecovery(id: attachmentID, fileAttachment: fileAttachment)
        }
    }

    func completeInvalidAttachmentRecovery(id: UUID, fileAttachment: AIChatFileAttachment?) {
        invalidAttachmentRecoveryTasks[id] = nil
        guard let attachment = viewController.currentAttachments.first(where: { $0.id == id }),
              case .invalidFile(let invalidAttachment) = attachment else { return }

        let didChange: Bool
        if let validationMessage = metadataValidationMessage(for: invalidAttachment) {
            didChange = replaceInvalidAttachment(invalidAttachment, validationMessage: validationMessage)
        } else if let fileAttachment {
            didChange = applyRecoveredFileAttachment(fileAttachment, for: invalidAttachment)
        } else {
            didChange = replaceInvalidAttachment(invalidAttachment, validationMessage: UserText.aiChatAttachmentFileUnreadable)
        }

        guard didChange else { return }
        finishAttachmentRevalidation()
    }

    @discardableResult
    func applyRecoveredFileAttachment(
        _ fileAttachment: AIChatFileAttachment,
        for attachment: UnifiedToggleInputInvalidFileAttachment
    ) -> Bool {
        if let validationMessage = attachmentPolicy.fileValidationMessage(for: fileAttachment) {
            return replaceInvalidAttachment(attachment, validationMessage: validationMessage)
        }

        viewController.replaceAttachment(id: attachment.id, with: .file(fileAttachment))
        return true
    }

    @discardableResult
    func replaceInvalidAttachment(
        _ attachment: UnifiedToggleInputInvalidFileAttachment,
        validationMessage: String
    ) -> Bool {
        guard validationMessage != attachment.validationMessage else { return false }
        viewController.replaceAttachment(
            id: attachment.id,
            with: invalidFileAttachment(from: attachment, validationMessage: validationMessage)
        )
        return true
    }

    func finishAttachmentRevalidation() {
        persistDraftToStore()
        updateAttachButtonPresentation()
        updateFloatingReturnKeyState()
        syncAttachmentValidationErrorForCurrentMode()
    }

    func invalidFileAttachment(
        from attachment: UnifiedToggleInputInvalidFileAttachment,
        validationMessage: String
    ) -> UnifiedToggleInputAttachment {
        .invalidFile(
            UnifiedToggleInputInvalidFileAttachment(
                id: attachment.id,
                fileName: attachment.fileName,
                mimeType: attachment.mimeType,
                fileSizeBytes: attachment.fileSizeBytes,
                validationMessage: validationMessage,
                sourceURL: attachment.sourceURL
            )
        )
    }

    func metadataValidationMessage(for attachment: UnifiedToggleInputInvalidFileAttachment) -> String? {
        attachmentPolicy.fileMetadataValidationError(
            mimeType: attachment.mimeType,
            fileSizeBytes: attachment.fileSizeBytes > 0 ? attachment.fileSizeBytes : nil
        )?.message
    }

    func fileMetadata(for attachment: UnifiedToggleInputInvalidFileAttachment) -> UnifiedToggleInputAttachmentPresenter.FileMetadata? {
        guard let sourceURL = attachment.sourceURL else { return nil }
        return UnifiedToggleInputAttachmentPresenter.FileMetadata(
            fileName: attachment.fileName,
            mimeType: attachment.mimeType,
            fileSizeBytes: attachment.fileSizeBytes > 0 ? attachment.fileSizeBytes : nil,
            url: sourceURL
        )
    }

    func cancelInvalidAttachmentRecoveryTasks() {
        invalidAttachmentRecoveryTasks.values.forEach { $0.cancel() }
        invalidAttachmentRecoveryTasks.removeAll()
    }

    func removeUnsupportedAttachmentsForSelectedModel() {
        guard selectedModel != nil else { return }
        let unsupportedAttachments = viewController.currentAttachments.filter { attachment in
            attachmentPolicy.isAttachmentSupported(attachment) == false
        }
        unsupportedAttachments.forEach { attachment in
            invalidAttachmentRecoveryTasks[attachment.id]?.cancel()
            invalidAttachmentRecoveryTasks[attachment.id] = nil
            viewController.removeAttachment(id: attachment.id)
        }
        revalidateInvalidAttachmentsForSelectedModel()
        syncAttachmentValidationErrorForCurrentMode()
    }

    func makeAttachmentMenu() -> UIMenu? {
        attachmentPresenter.makeAttachmentMenu(
            presenterProvider: { [weak self] in
                self?.attachmentPresenterViewController
            },
            photoSelectionLimit: attachmentPolicy.canAttachImages ? remainingImagesForPicker : 0,
            canAttachFile: canPresentFilePicker,
            allowedFileTypes: allowedFileUTTypes
        )
    }

    func updateAttachButtonPresentation() {
        let supportsAttachments = selectedModelSupportsImageUpload || !allowedFileUTTypes.isEmpty
        let canAttachMore = (attachmentPolicy.canAttachImages || canPresentFilePicker) && !viewController.isGenerating
        viewController.isImageButtonHidden = !supportsAttachments
        viewController.isImageButtonEnabled = canAttachMore
        viewController.attachmentMenu = supportsAttachments && canAttachMore ? makeAttachmentMenu() : nil
    }

    func presentAttachmentValidationError(_ message: String) {
        viewController.showAttachmentValidationError(message)
    }

    func attachmentSubmissionValidationMessage(for text: String, mode: TextEntryMode) -> String? {
        guard mode == .aiChat else { return nil }

        if let validationMessage = attachmentPolicy.imageSubmissionValidationMessage() {
            return validationMessage
        }

        if let validationMessage = attachmentPolicy.fileSubmissionValidationMessage() {
            return validationMessage
        }

        return attachmentPolicy.promptValidationMessage(for: text)
    }

    func syncAttachmentValidationError() {
        if let validationMessage = viewController.currentAttachments.compactMap(\.validationMessage).first {
            viewController.showAttachmentValidationError(validationMessage)
        } else {
            viewController.clearAttachmentValidationError()
        }
    }

    func syncAttachmentValidationErrorForCurrentMode() {
        guard inputMode == .aiChat else {
            viewController.clearAttachmentValidationError()
            return
        }

        syncAttachmentValidationError()
    }

    func clearAttachmentValidationErrorIfPossible() {
        guard viewController.currentAttachments.contains(where: \.isInvalid) == false else { return }
        viewController.clearAttachmentValidationError()
    }

    func makeFloatingReturnKeyState() -> UnifiedToggleInputFloatingReturnKeyState {
        UnifiedToggleInputFloatingReturnKeyState(
            text: currentText,
            mode: inputMode,
            usesFloatingReturnKey: usesFloatingReturnKey)
    }

    func updateFloatingReturnKeyState() {
        floatingReturnKeyViewController.updateState(makeFloatingReturnKeyState())
    }

    // MARK: Session State

    func syncChipVisibility(hasExistingChat: Bool) {
        if isNewChatPending && hasExistingChat {
            return
        }
        isNewChatPending = false
        // Upgrade only — the chat URL gets its chatID after the page loads, so downgrading
        // here would clobber a just-submitted prompt. Explicit resets cover the rest.
        guard hasExistingChat, !hasSubmittedPrompt else { return }
        hasSubmittedPrompt = true
        updateModelChipVisibility()
        syncHasSubmittedPromptToHandler()
    }

    func updateModelChipVisibility() {
        // Contextual chat picks the model upstream (in the half-sheet); the model chip is permanently hidden here.
        // Image generation has no model picker either — when active, the chip is hidden until the tool is deselected.
        let isImageGenActive = toolsController.selectedTool == .imageGeneration
        // `isModelPickerForcedVisible` only relaxes the `hasSubmittedPrompt` hide reason — contextual
        // chat and image generation stay hidden regardless.
        let shouldHideModelChip = host == .contextualChat || isImageGenActive || (hasSubmittedPrompt && !isModelPickerForcedVisible)
        viewController.isModelChipHidden = shouldHideModelChip
        updateReasoningPicker()
    }

    func syncHasSubmittedPromptToHandler() {
        syncInputBehaviorToHandler()
        switchBarHandler.hasSubmittedPrompt = hasSubmittedPrompt
        // Beat the view's async sink so the flanked UTI's first frame uses the new placeholder.
        viewController.refreshPlaceholderForCurrentMode()
        updateFloatingReturnKeyState()
    }

    private func markActiveChatPromptSubmitted() {
        let wasInRecoveryPickerSession = isModelPickerForcedVisible
        hasSubmittedPrompt = true
        isModelPickerForcedVisible = false
        persistModelPickerPinClearedAfterHideIfNeeded()
        updateModelChipVisibility()
        syncHasSubmittedPromptToHandler()
        if wasInRecoveryPickerSession {
            UnifiedToggleInputCoordinatorPixelHelper.fireSubmitChangeModelPromptSentPixel()
        }
    }

    func syncInputBehaviorToHandler() {
        viewController.handler.submitsAIChatOnKeyboardReturn = isOmnibarNewAIChatPrompt
    }

    func resetSessionState() {
        isNewChatPending = false
        aiChatStatus = .unknown
        attachmentUsage = nil
        hasSubmittedPrompt = false
        // Do not clear the model-picker pin here. It is stored per tab in TabInputState and
        // restored by applyState during activateForTab. bindToTab calls resetSessionState
        // immediately after that restore when switching Duck.ai tabs, so resetting the pin
        // here would undo the value we just loaded for the incoming tab.
        isSubmitBlockedByRecoveryCard = false
        updateModelChipVisibility()
        syncHasSubmittedPromptToHandler()
    }

    // MARK: Toolbar

    func updateToolbarAIVoiceChat() {
        viewController.isToolbarAIVoiceChatActive = viewController.handler.isAIVoiceChatEnabled && inputMode == .aiChat
    }

    func applyToolbarPresentation() {
        refreshToolsPresentation()
        updateReasoningPicker()
        updateToolbarAIVoiceChat()
    }

    // MARK: Tools

    func handleModelsUpdated() {
        toolsController.clearSelectionIfUnsupported(for: modelStore)
        removeUnsupportedAttachmentsForSelectedModel()
        updateModelChipLabel()
        updateReasoningPicker()
        if applyPendingGatedModelSelectionIfPossible() {
            return
        }
        applyPendingGatedReasoningSelectionIfPossible()
        updateImageButtonVisibility()
        refreshToolsPresentation()
    }

    func refreshToolsPresentation() {
        let presentation = toolsController.presentation(
            displayState: displayState,
            modelStore: modelStore
        )
        let toolsMenu = presentation.toolsMenu.map { [weak self] menu in
            self?.toolsMenuFactory.makeMenu(menu) { identifier in
                self?.handleToolsMenuSelection(identifier)
            }
        } ?? nil
        viewController.applyToolsPresentation(
            isToolsButtonHidden: presentation.isToolsButtonHidden,
            selectedTool: presentation.selectedTool,
            toolsMenu: toolsMenu
        )
        // Tool selection toggles the model-chip + reasoning-picker visibility. Route through the
        // canonical updaters so we don't clobber the other signals (`hasSubmittedPrompt`, `host`).
        updateModelChipVisibility()
    }

    func resetToolsSelection() {
        toolsController.clearSelection()
        refreshToolsPresentation()
    }

    func updateImageButtonEnabledState() {
        updateAttachButtonPresentation()
    }

    var resolvedSelectedReasoningMode: AIChatReasoningMode? {
        selectedModel?.resolvedReasoningMode(from: persistedReasoningMode)
    }

    /// Reasoning mode to report in submit-time pixels.
    /// Returns `nil` ( "none") whenever the reasoning picker is hidden in the UI:
    /// selected tool hides it, or the model doesn't support a reasoning picker.
    var reasoningModeForSubmitPixel: AIChatReasoningMode? {
        if let tool = toolsController.selectedTool,
           let identifier = UTIToolsMenu.Item.Identifier(tool: tool),
           identifier.hidesReasoningPicker {
            return nil
        }
        guard selectedModel?.supportsReasoningPicker == true else { return nil }
        return resolvedSelectedReasoningMode
    }

    // MARK: - Subscriptions

    func subscribeToGeneratingState() {
        $aiChatStatus
            .map { status in
                status == .loading || status == .streaming || status == .startStreamNewPrompt
            }
            .removeDuplicates()
            .sink { [weak self] isGenerating in
                guard let self else { return }
                self.viewController.isGenerating = isGenerating
                self.updateImageButtonEnabledState()
            }
            .store(in: &cancellables)
    }

    func subscribeToStopGeneratingTap() {
        viewController.handler.stopGeneratingButtonTappedPublisher
            .sink { [weak self] in
                Pixel.fire(pixel: .unifiedToggleInputStopGenerationTapped)
                self?.didPressStopGeneratingButton.send()
            }
            .store(in: &cancellables)
    }

    func subscribeToAttachmentUsageChanges() {
        $attachmentUsage
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.updateImageButtonVisibility()
            }
            .store(in: &cancellables)
    }

    func subscribeToCustomizeResponsesTap() {
        viewController.handler.customizeResponsesButtonTappedPublisher
            .sink { [weak self] in
                guard let self else { return }
                self.didPressCustomizeResponsesButton.send()
                self.showCollapsed()
            }
            .store(in: &cancellables)
    }

    func subscribeToVoiceSearchTap() {
        viewController.handler.microphoneButtonTappedPublisher
            .sink { [weak self] in
                guard let self else { return }
                let isCollapsedAIVoiceChatButton = viewController.handler.isAIVoiceChatEnabled
                    && viewController.inputMode == .aiChat
                    && !isInputPaneExpanded
                if isCollapsedAIVoiceChatButton {
                    delegate?.unifiedToggleInputDidRequestAIVoiceChat()
                } else {
                    guard viewController.handler.isVoiceSearchEnabled else { return }
                    delegate?.unifiedToggleInputDidRequestVoiceSearch()
                }
            }
            .store(in: &cancellables)
    }

    func subscribeToAIVoiceChatTap() {
        viewController.handler.aiVoiceChatButtonTappedPublisher
            .sink { [weak self] in
                guard let self else { return }
                let source = self.isAITabState ? "duck_ai" : "ntp"
                DailyPixel.fireDailyAndCount(
                    pixel: .unifiedToggleInputVoiceTapped,
                    withAdditionalParameters: ["source": source]
                )
                self.delegate?.unifiedToggleInputDidRequestAIVoiceChat()
            }
            .store(in: &cancellables)
    }

    func subscribeToClearButtonTap() {
        viewController.handler.clearButtonTappedPublisher
            .sink { [weak self] in
                guard let self, host == .omnibar else { return }
                delegate?.unifiedToggleInputDidTapClearText()
            }
            .store(in: &cancellables)
    }

    func subscribeToSubscriptionChanges() {
        NotificationCenter.default.publisher(for: .subscriptionDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshModelsAfterSubscriptionChange()
            }
            .store(in: &cancellables)
    }

    // MARK: - Pixels

    private func processSessionActivity(mode: TextEntryMode) {
        guard host == .omnibar else { return }

        let previouslyUsedBothModes = Self.hasUsedSearchInSession && Self.hasUsedAIChatInSession

        switch mode {
        case .search:
            Self.hasUsedSearchInSession = true
            sessionStateMetrics.incrementActivity(.searchSubmitted)
        case .aiChat:
            Self.hasUsedAIChatInSession = true
            sessionStateMetrics.incrementActivity(.promptSubmitted)
        }

        let nowUsesBothModes = Self.hasUsedSearchInSession && Self.hasUsedAIChatInSession
        if nowUsesBothModes && !previouslyUsedBothModes {
            DailyPixel.fireDailyAndCount(pixel: .aiChatExperimentalOmnibarSessionBothModes)
        }
    }

    private func fireModeSwitchedPixel(to mode: TextEntryMode) {
        let direction = mode == .search ? "to_search" : "to_duckai"
        let hadText = !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let parameters = [
            "direction": direction,
            "had_text": String(hadText),
            "default_position": aiChatSettings.defaultOmnibarMode.rawValue
        ]
        Pixel.fire(pixel: .aiChatExperimentalOmnibarModeSwitched, withAdditionalParameters: parameters)
    }
}

private extension NSCache where KeyType == NSString, ObjectType == NSString {
    subscript(key: String) -> String? {
        get { object(forKey: key as NSString) as String? }
        set {
            if let newValue {
                setObject(newValue as NSString, forKey: key as NSString)
            } else {
                removeObject(forKey: key as NSString)
            }
        }
    }
}

// MARK: - Duck.ai Wide Event

extension UnifiedToggleInputCoordinator {

    private var currentDuckAIWideEventFlowScope: DuckAIWideEventFlowScope? {
        switch host {
        case .contextualChat:
            return duckAIWideEventFlowScope
        case .omnibar:
            return (currentTabUID ?? lastActivatedTabUID).map(DuckAIWideEventFlowScope.tab)
        }
    }

    private var duckAIEntryPoint: DuckAIPromptWideEventData.EntryPoint {
        switch host {
        case .contextualChat: return .contextualChat
        case .omnibar: return isOmnibarSession ? .omnibar : .aiTab
        }
    }

    /// Records a submission for the user's primary input path (voice or keyboard) - opens the
    /// wide-event flow with the snapshot of state at submit time.
    func recordDuckAISubmissionStarted(modelId: String?,
                                       reasoningEffort: AIChatReasoningEffort?,
                                       inputMode: DuckAIPromptWideEventData.InputMode,
                                       frontendDeliveryPath: DuckAIPromptWideEventData.FrontendDeliveryPath,
                                       hasPageContext: Bool,
                                       toolsSelected: Bool,
                                       attachmentsSelected: Bool) {
        guard let scope = currentDuckAIWideEventFlowScope else { return }
        duckAIWideEventInstrumentation?.submissionStarted(
            scope: scope,
            modelId: modelId,
            userTier: subscriptionState.userTier,
            reasoningEffort: reasoningEffort,
            entryPoint: duckAIEntryPoint,
            inputMode: inputMode,
            fireMode: viewController.handler.isFireTab,
            isFirstPrompt: !hasSubmittedPrompt,
            frontendDeliveryPath: frontendDeliveryPath,
            hasPageContext: hasPageContext,
            toolsSelected: toolsSelected,
            attachmentsSelected: attachmentsSelected
        )
    }

    func recordDuckAIPromptDelivered(wasQueued: Bool?, didSendBridgeMessage: Bool?) {
        guard let scope = currentDuckAIWideEventFlowScope else { return }
        duckAIWideEventInstrumentation?.promptDeliveryUpdated(scope: scope, wasQueued: wasQueued, didSendBridgeMessage: didSendBridgeMessage)
    }

    /// Called by the contextual sheet's native-input path, which submits its initial prompt
    /// outside the UTI (no `userScript` bound yet). Opens the flow so the JS status updates
    /// that follow have a flow to attach to.
    func recordExternalPromptSubmitted(entryPoint: DuckAIPromptWideEventData.EntryPoint,
                                       inputMode: DuckAIPromptWideEventData.InputMode,
                                       isFirstPrompt: Bool,
                                       hasPageContext: Bool) {
        guard let scope = currentDuckAIWideEventFlowScope else { return }
        duckAIWideEventInstrumentation?.submissionStarted(
            scope: scope,
            modelId: persistedModelId,
            userTier: subscriptionState.userTier,
            reasoningEffort: persistedReasoningEffort,
            entryPoint: entryPoint,
            inputMode: inputMode,
            fireMode: viewController.handler.isFireTab,
            isFirstPrompt: isFirstPrompt,
            frontendDeliveryPath: entryPoint == .contextualChat ? .contextualNativeInput : .urlAutoSubmit,
            hasPageContext: hasPageContext,
            toolsSelected: false,
            attachmentsSelected: false
        )
    }

    func subscribeToDuckAIWideEventSignals() {
        $aiChatStatus
            .removeDuplicates()
            .sink { [weak self] status in
                guard let self, let scope = self.currentDuckAIWideEventFlowScope else { return }
                self.duckAIWideEventInstrumentation?.chatStatusChanged(status, scope: scope)
            }
            .store(in: &cancellables)

        viewController.handler.stopGeneratingButtonTappedPublisher
            .sink { [weak self] in
                guard let self, let scope = self.currentDuckAIWideEventFlowScope else { return }
                self.duckAIWideEventInstrumentation?.stopGeneratingTapped(scope: scope)
            }
            .store(in: &cancellables)
    }
}
