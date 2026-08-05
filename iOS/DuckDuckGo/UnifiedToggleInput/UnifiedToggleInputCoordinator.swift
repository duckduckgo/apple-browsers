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
        modelStore.submissionReasoningEffort
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
    private let stateMachine: UTIStateMachine
    var displayState: UnifiedToggleInputDisplayState {
        get { stateMachine.displayState }
        set { stateMachine.transition(to: newValue) }
    }
    var textState: InputTextState { textModel.textState }
    private var omnibarPrefilledText: String? {
        get { textModel.omnibarPrefilledText }
        set { textModel.omnibarPrefilledText = newValue }
    }
    private(set) var inputMode: TextEntryMode = .aiChat
    private let stateStore: UnifiedInputStateStoring
    private let switchBarSubmissionMetrics: SwitchBarSubmissionMetricsProviding
    private let aiChatSettings: AIChatSettingsProvider
    private let sessionMonitor: UTISessionMonitor
    private(set) var currentTabUID: TabUID?
    private var lastActivatedTabUID: TabUID?
    private var isApplyingState = false
    private var isPerformingDismissCleanup: Bool { textModel.isPerformingDismissCleanup }
    private(set) var committedInputMode: TextEntryMode = .search
    private(set) var cardPosition: UnifiedToggleInputCardPosition = .bottom
    private(set) var isInputVisibleForKeyboard: Bool = true
    /// Window-space X of the resting omnibar placeholder text, captured at focus time (before the
    /// bottom floating omnibar is detached from the toolbar). Reused on dismiss to slide the UTI
    /// text back onto the omnibar's text leading edge — the omnibar can't be measured live then.
    var cachedOmnibarPlaceholderWindowX: CGFloat?
    private var keyboardMonitor: UTIKeyboardMonitor!
    private var pixelReporter: UTIPixelReporter!
    private var wideEventReporter: UTIWideEventReporter!
    private var modelSelector: UTIModelSelector!
    private var attachmentController: UTIAttachmentController!
    private var isContentOverlaySuppressed = false
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

    private var textModel: UTITextModel!
    var currentText: String { textModel.currentText }
    var hasActiveChat: Bool { boundUserScript != nil }
    var switchBarHandler: SwitchBarHandling { viewController.handler }
    var onAnimatedDismissToOmnibar: ((_ completion: (() -> Void)?) -> Void)?

    var isOmnibarSession: Bool { stateMachine.isOmnibarSession }
    var isAITabState: Bool { stateMachine.isAITabState }
    var isAITabExpanded: Bool { stateMachine.isAITabExpanded }
    var isAITabCollapsed: Bool { stateMachine.isAITabCollapsed }
    var isContextualChatState: Bool { stateMachine.isContextualChatState }
    var isOmnibarEditing: Bool { stateMachine.isOmnibarEditing }
    var omnibarState: UnifiedToggleInputDisplayState.OmnibarState? { stateMachine.omnibarState }
    var isSearchOnAITab: Bool { stateMachine.isSearchOnAITab(inputMode: inputMode) }
    var isDuckAISurfaceForAttribution: Bool { stateMachine.isDuckAISurfaceForAttribution }
    var pixelSurface: UnifiedToggleInputPixelSurface { stateMachine.pixelSurface }
    var isInputPaneExpanded: Bool { stateMachine.isInputPaneExpanded }
    var isInputEditing: Bool { stateMachine.isInputEditing }
    var isActive: Bool { stateMachine.isActive }

    private var isOmnibarNewAIChatPrompt: Bool {
        isOmnibarSession && inputMode == .aiChat && !hasSubmittedPrompt
    }

    private var submitsAIChatPromptOnKeyboardReturn: Bool {
        isOmnibarNewAIChatPrompt || isContextualChatState
    }

    private var usesReturnKeySubmitButtonStyle: Bool {
        isOmnibarNewAIChatPrompt
    }

    private var usesFloatingReturnKey: Bool {
        isOmnibarEditing && isInputVisibleForKeyboard && isOmnibarNewAIChatPrompt
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

    private let intentSubject = PassthroughSubject<UnifiedToggleInputIntent, Never>()
    var intentPublisher: AnyPublisher<UnifiedToggleInputIntent, Never> {
        intentSubject.eraseToAnyPublisher()
    }

    var textChangePublisher: AnyPublisher<String, Never> { textModel.textChangePublisher }

    private let modeChangeSubject = PassthroughSubject<TextEntryMode, Never>()
    var modeChangePublisher: AnyPublisher<TextEntryMode, Never> {
        modeChangeSubject.eraseToAnyPublisher()
    }

    private let attachmentsChangeSubject = PassthroughSubject<Void, Never>()
    var attachmentsChangePublisher: AnyPublisher<Void, Never> {
        attachmentsChangeSubject.eraseToAnyPublisher()
    }

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
        modelsService: AIChatModelsProviding? = nil,
        preferences: AIChatPreferencesPersisting = AIChatPreferencesPersistor(),
        subscriptionManager: any SubscriptionManager = AppDependencyProvider.shared.subscriptionManager,
        toggleModeStorage: ToggleModeStoring = ToggleModeStorage(),
        stateStore: UnifiedInputStateStoring? = nil,
        syncService: DDGSyncing? = nil,
        switchBarSubmissionMetrics: SwitchBarSubmissionMetricsProviding = SwitchBarSubmissionMetrics(),
        aiChatSettings: AIChatSettingsProvider = AIChatSettings(),
        aiChatSyncCleaner: AIChatSyncCleaning? = nil,
        recentModalPromptStatusProvider: RecentModalPromptStatusProviding? = nil,
        sessionStateMetrics: SessionStateMetricsProviding = SessionStateMetrics(storage: UserDefaults.standard),
        duckAIWideEventInstrumentation: DuckAIWideEventInstrumentation? = nil,
        duckAIWideEventFlowScope: DuckAIWideEventFlowScope? = nil,
        pixelFiring: UTIPixelFiring = .live,
        contextualStartsPreSubmit: Bool = false,
        attachmentPasteEnabled: Bool = false
    ) {
        self.host = host
        self.isToggleEnabled = isToggleEnabled
        self.hidesToggleOnDuckAITab = hidesToggleOnDuckAITab
        self.switchBarSubmissionMetrics = switchBarSubmissionMetrics
        self.aiChatSettings = aiChatSettings
        self.sessionMonitor = UTISessionMonitor(
            isEnabled: host == .omnibar,
            metrics: sessionStateMetrics,
            fireBothModesPixel: { pixelFiring.fireDailyAndCount(.aiChatExperimentalOmnibarSessionBothModes) }
        )
        self.stateMachine = UTIStateMachine(host: host, hidesToggleOnDuckAITab: hidesToggleOnDuckAITab)
        self.stateStore = stateStore ?? UnifiedInputStateStore(
            preferences: preferences,
            toggleModeStorage: toggleModeStorage
        )
        self.modelStore = UTIModelStore(
            modelsService: modelsService ?? AIChatModelsService(
                baseURL: aiChatModelsBaseURL(forChatURL: aiChatSettings.aiChatURL)
            ),
            preferences: preferences,
            subscriptionManager: subscriptionManager
        )
        self.lastUsedModelProvider = lastUsedModelProvider
            ?? duckAiNativeStorageHandler.map { DuckAiLastUsedModelProvider(storage: $0, pixelFiring: duckAiNativeStoragePixelFiring) }
        self.lastUsedReasoningModeProvider = lastUsedReasoningModeProvider
            ?? duckAiNativeStorageHandler.map { DuckAiLastUsedReasoningModeProvider(storage: $0, pixelFiring: duckAiNativeStoragePixelFiring) }
        self.duckAIWideEventFlowScope = duckAIWideEventFlowScope
        viewController = UnifiedToggleInputViewController(isToggleEnabled: isToggleEnabled, isFireTab: isFireTab)
        contentViewController = UnifiedInputContentContainerViewController(
            switchBarHandler: viewController.handler,
            duckAiNativeStorageHandler: duckAiNativeStorageHandler,
            syncService: syncService,
            aiChatSyncCleaner: aiChatSyncCleaner,
            recentModalPromptStatusProvider: recentModalPromptStatusProvider
        )
        floatingReturnKeyViewController = UnifiedToggleInputFloatingReturnKeyViewController()
        super.init()
        viewController.delegate = self
        textModel = UTITextModel(sideEffects: .init(
            applyTextToView: { [weak self] in self?.viewController.text = $0 },
            persistDraft: { [weak self] in self?.persistDraftToStore() },
            updateFloatingReturnKey: { [weak self] in self?.updateFloatingReturnKeyState() },
            clearAttachmentValidationErrorIfPossible: { [weak self] in self?.attachmentController.clearValidationErrorIfPossible() }
        ))
        keyboardMonitor = UTIKeyboardMonitor(environment: .init(
            isOmnibarActiveTopCard: { [weak self] in
                guard let self else { return false }
                if case .omnibar(.active) = self.displayState, self.cardPosition == .top { return true }
                return false
            },
            isInputVisibleForKeyboard: { [weak self] in self?.isInputVisibleForKeyboard ?? false },
            isInputFirstResponder: { [weak self] in self?.viewController.isInputFirstResponder ?? false }
        ))
        keyboardMonitor.onTimeoutRequiresInactive = { [weak self] in self?.transitionOmnibarToInactive() }
        pixelReporter = UTIPixelReporter(firing: pixelFiring, context: { [weak self] in
            guard let self else { return nil }
            return UTIPixelContext(
                surface: self.pixelSurface,
                isDuckAISurfaceForAttribution: self.isDuckAISurfaceForAttribution,
                inputMode: self.inputMode
            )
        })
        wideEventReporter = UTIWideEventReporter(
            instrumentation: duckAIWideEventInstrumentation,
            flowScope: { [weak self] in self?.currentDuckAIWideEventFlowScope },
            submissionInputs: { [weak self] in
                guard let self else { return nil }
                return UTIWideEventSubmissionInputs(
                    modelId: self.persistedModelId,
                    userTier: self.subscriptionState.userTier,
                    persistedReasoningEffort: self.persistedReasoningEffort,
                    fireMode: self.viewController.handler.isFireTab,
                    hasSubmittedPrompt: self.hasSubmittedPrompt,
                    entryPoint: self.duckAIEntryPoint
                )
            }
        )
        modelSelector = UTIModelSelector(
            modelStore: modelStore,
            toolsController: toolsController,
            pixelReporter: pixelReporter,
            view: .init(
                setModelName: { [weak self] in self?.viewController.modelName = $0 },
                setModelPickerMenu: { [weak self] in self?.viewController.modelPickerMenu = $0 },
                setModelChipHidden: { [weak self] in self?.viewController.isModelChipHidden = $0 },
                setSelectedReasoningMode: { [weak self] in self?.viewController.selectedReasoningMode = $0 },
                setReasoningButtonHidden: { [weak self] in self?.viewController.isReasoningButtonHidden = $0 },
                setReasoningPickerMenu: { [weak self] in self?.viewController.reasoningPickerMenu = $0 }
            ),
            environment: .init(
                isDuckAISurfaceForAttribution: { [weak self] in self?.isDuckAISurfaceForAttribution ?? false },
                hasSubmittedPrompt: { [weak self] in self?.hasSubmittedPrompt ?? false },
                host: { [weak self] in self?.host },
                isModelPickerForcedVisible: { [weak self] in self?.isModelPickerForcedVisible ?? false }
            ),
            callbacks: .init(
                onModelsUpdated: { [weak self] in self?.handleModelsUpdated() },
                onUserChoiceRecorded: { [weak self] in self?.recordUserChoiceToStore() },
                clearSubmitRecoveryBlock: { [weak self] in self?.isSubmitBlockedByRecoveryCard = false },
                onModelApplied: { [weak self] in self?.notifyFrontendOfActiveChatModelChange($0) }
            )
        )
        attachmentController = UTIAttachmentController(
            pixelReporter: pixelReporter,
            view: .init(
                currentAttachments: { [weak self] in self?.viewController.currentAttachments ?? [] },
                isGenerating: { [weak self] in self?.viewController.isGenerating ?? false },
                addAttachment: { [weak self] in self?.viewController.addAttachment($0) },
                removeAttachment: { [weak self] in self?.viewController.removeAttachment(id: $0) },
                removeAllAttachments: { [weak self] in self?.viewController.removeAllAttachments() },
                replaceAttachment: { [weak self] id, attachment in self?.viewController.replaceAttachment(id: id, with: attachment) },
                showValidationError: { [weak self] in self?.viewController.showAttachmentValidationError($0) },
                clearValidationError: { [weak self] in self?.viewController.clearAttachmentValidationError() },
                setImageButtonHidden: { [weak self] in self?.viewController.isImageButtonHidden = $0 },
                setImageButtonEnabled: { [weak self] in self?.viewController.isImageButtonEnabled = $0 },
                setAttachmentMenu: { [weak self] in self?.viewController.attachmentMenu = $0 }
            ),
            environment: .init(
                policy: { [weak self] in
                    self?.attachmentPolicy ?? UTIAttachmentPolicy(attachmentLimits: nil, attachmentUsage: nil, pendingAttachments: [], model: nil)
                },
                inputMode: { [weak self] in self?.inputMode ?? .aiChat },
                pixelSurface: { [weak self] in self?.pixelSurface ?? .addressBar },
                isContextualChatState: { [weak self] in self?.isContextualChatState ?? false },
                supportsImageUpload: { [weak self] in self?.selectedModelSupportsImageUpload ?? false },
                supportedFileTypes: { [weak self] in self?.selectedModelSupportedFileTypes ?? [] },
                hasSelectedModel: { [weak self] in self?.selectedModel != nil },
                attachmentLimits: { [weak self] in self?.modelStore.attachmentLimits },
                currentTabUID: { [weak self] in self?.currentTabUID },
                isPageContextAttachable: { [weak self] in self?.isPageContextAttachable?() },
                pageContextAttachHandler: { [weak self] in self?.onPageContextAttachRequested },
                presenterViewController: { [weak self] in self?.attachmentPresenterViewController }
            ),
            callbacks: .init(
                onDraftChanged: { [weak self] in self?.persistDraftToStore() },
                onExpandIfNeeded: { [weak self] in self?.expandIfOnExpandedInputHost() },
                updateFloatingReturnKey: { [weak self] in self?.updateFloatingReturnKeyState() }
            )
        )
        viewController.attachmentPasteHandler = attachmentPasteEnabled ? attachmentController.pasteHandler : nil
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
        wideEventReporter.subscribe(
            aiChatStatus: $aiChatStatus.eraseToAnyPublisher(),
            stopGeneratingTapped: viewController.handler.stopGeneratingButtonTappedPublisher
        )
        viewController.isToolsButtonHidden = true

        if let cachedLabel = modelStore.displayShortName {
            viewController.modelName = cachedLabel
        }

        // Contextual chat boots in expanded form; no collapsed/inactive states are reachable.
        // The chat is already post-submit by the time the contextual UTI installs, so
        // `hasSubmittedPrompt` should reflect that — drives follow-up placeholder + model chip hide.
        if host == .contextualChat {
            displayState = .contextualChat
            hasSubmittedPrompt = !contextualStartsPreSubmit
            syncHasSubmittedPromptToHandler()
            modelSelector.updateModelChipVisibility()
        }

        sessionMonitor.startObservingBackground()
    }

    // MARK: - Tab Binding

    func bindToTab(_ userScript: AIChatUserScript, hasExistingChat: Bool = false) {
        let newIdentifier = ObjectIdentifier(userScript)
        if boundUserScriptIdentifier == newIdentifier {
            boundUserScript = userScript
            userScript.inputBoxHandler = self
            syncChipVisibility(hasExistingChat: hasExistingChat)
            refreshToolsPresentation()
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
        refreshToolsPresentation()
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
        modelSelector.updateReasoningPicker()
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
            wideEventReporter.recordTabSwitchedAwayDuringGeneration(tabID: previous)
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

        attachmentController.replaceAllAttachments(with: state.attachments)

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
        modelSelector.updateReasoningPicker()

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
        textModel.resetToEmpty()
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
        keyboardMonitor.disarm()
        let previousDisplayState = displayState
        displayState = .aiTab(.collapsed)
        setInitialInputMode(.aiChat)
        isInputVisibleForKeyboard = true

        // Pose deferred to the intent handler so the morph animates in sync with the keyboard.
        applyToolbarPresentation()
        viewController.deactivateInput()
        intentSubject.send(.showCollapsed(from: previousDisplayState))
    }

    func showExpanded(prefilledText: String? = nil, inputMode: TextEntryMode = .aiChat, activatesInput: Bool = true) {
        guard !isOnboardingLocked else { return }
        keyboardMonitor.disarm()
        let previousDisplayState = displayState
        displayState = host == .contextualChat ? .contextualChat : .aiTab(.expanded)
        // Pixels fire only on a real transition into expanded — header re-entries (Plus → New Chat) call this too but don't actually show either UI.
        if host == .omnibar, previousDisplayState != .aiTab(.expanded) {
            pixelReporter.reportOmnibarInputSurfaceShown()
        }
        setInitialInputMode(inputMode)
        isInputVisibleForKeyboard = true
        viewController.handler.resetInteractionState()

        // Pose deferred to the intent handler so the morph animates in sync with the keyboard.
        applyToolbarPresentation()
        fetchModels()

        if let prefilledText, !prefilledText.isEmpty {
            textModel.setText(prefilledText)
            textModel.markPrefilledSelected()
        }
        updateFloatingReturnKeyState()

        intentSubject.send(.showExpanded(from: previousDisplayState))
        guard activatesInput else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isInputPaneExpanded else { return }
            guard !self.isOnboardingLocked else { return }
            self.viewController.activateInput()
            if !self.viewController.isInputFirstResponder {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isInputPaneExpanded else { return }
                    guard !self.isOnboardingLocked else { return }
                    self.viewController.activateInput()
                }
            }
            if self.textState == .prefilledSelected {
                self.viewController.selectAllText()
            }
        }
    }

    func submitProgrammatic(text: String) {
        unifiedToggleInputVC(viewController, didSubmitText: text, mode: .aiChat)
    }

    func hide() {
        keyboardMonitor.disarm()
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
            wideEventReporter.recordTabSwitchedAwayDuringGeneration(tabID: previousTabUID)
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

    func activateFromOmnibar(prefilledText: String? = nil, shouldSelectAllText: Bool = true, inputMode: TextEntryMode = .search, cardPosition: UnifiedToggleInputCardPosition = .top) {
        keyboardMonitor.arm(awaiting: cardPosition == .top)
        displayState = .omnibar(.active)
        if host == .omnibar {
            pixelReporter.reportOmnibarInputSurfaceShown()
        }
        // Omnibar without a toggle UI locks to .search; inlined to avoid an ordering coupling with `effectiveInputMode`.
        setInitialInputMode(isToggleEnabled ? inputMode : .search)
        self.cardPosition = cardPosition
        viewController.handler.hidesVoiceButton = false
        isInputVisibleForKeyboard = true
        hasSubmittedPrompt = false
        viewController.handler.resetInteractionState()
        resetToolsSelection()
        modelSelector.updateModelChipVisibility()
        syncHasSubmittedPromptToHandler()

        viewController.applyCardLayout(.collapsed, animated: false)
        let renderState = computeRenderState()

        // Set text before apply so clearDismissSnapshot sees the correct handler state when
        // it fires inside applyCardLayout — otherwise textRightInset starts at the no-button value.
        let selectsAllText: Bool
        if let text = prefilledText, !text.isEmpty {
            textModel.setText(text)
            textModel.markPrefilledSelected()
            omnibarPrefilledText = text
            selectsAllText = shouldSelectAllText
        } else {
            omnibarPrefilledText = nil
            selectsAllText = false
        }
        updateFloatingReturnKeyState()

        viewController.apply(renderState.viewConfig, animated: false)
        applyToolbarPresentation()
        fetchModels()

        let expandedHeight = editingHeight()

        // Pre-stage to the start pose so the intent handler animates from initial to final height.
        viewController.prepareForOmnibarEditingShow()
        let initialHeight = editingHeight()
        intentSubject.send(.showOmnibarEditing(expandedHeight: initialHeight, pendingExpandedHeight: expandedHeight))

        if cardPosition == .top {
            keyboardMonitor.scheduleFallback()
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, isOmnibarEditing else { return }
            viewController.activateInput()
            guard omnibarPrefilledText != nil else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, isOmnibarEditing else { return }
                if selectsAllText {
                    viewController.selectAllText()
                } else {
                    viewController.moveCaretToStart()
                }
            }
        }
    }

    func deactivateToOmnibar(resetView: Bool = true, animateDismiss: Bool = true) {
        guard isOmnibarSession else { return }
        inputMode = committedInputMode
        keyboardMonitor.disarm()
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
            attachmentController.syncValidationErrorForCurrentMode()
        }
        updateFloatingReturnKeyState()
    }

    /// Without a visible toggle the user can't switch mode — omnibar locks to `.search`, AI tabs to `.aiChat`.
    /// Keyed on `isToggleVisible` so the clamp fires when the kill switch hides the toggle, not just when the setting is off.
    private func effectiveInputMode(for requestedMode: TextEntryMode) -> TextEntryMode {
        guard !isToggleVisible else { return requestedMode }
        if isOmnibarSession { return .search }
        if isContextualChatState { return .aiChat }
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
        textModel.setText(text)
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
            pixelReporter.reportModeSwitched(to: effectiveMode, currentText: currentText, defaultOmnibarMode: aiChatSettings.defaultOmnibarMode)
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
                // Push the new mode's content inset here (target height) so the suggestions content and
                // the logo move in the same pass as the bar — not reactively after the height callback.
                if didModeChange { self.pushContentInsets() }
            }
        } else {
            applyModeChange()
            if didModeChange { pushContentInsets() }
        }

        applyToolbarPresentation()
        if didModeChange {
            attachmentController.syncValidationErrorForCurrentMode()
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
        let isAITabSearch = isSearchOnAITab

        switch (displayState, isInputVisible) {
        case (.omnibar(.active), false) where keyboardMonitor.isAwaitingPresentation:
            return
        case (.omnibar(.active), false) where viewController.isInputFirstResponder:
            // A hardware keyboard is connected (or the keyboard frame went off-screen)
            // while the user is still actively editing. Treat the input as in-use and
            // skip the dismissal — otherwise the bar collapses on every keystroke.
            keyboardMonitor.cancelFallback()
        case (.omnibar(.active), false):
            keyboardMonitor.cancelFallback()
            transitionOmnibarToInactive()
        case (.omnibar(.inactive), true):
            keyboardMonitor.disarm()
            displayState = .omnibar(.active)
            syncInputBehaviorToHandler()
            updateFloatingReturnKeyState()
            let renderState = computeRenderState()
            viewController.apply(renderState.viewConfig, animated: false)
            intentSubject.send(.showOmnibarActive)
        case (.omnibar(.active), true):
            keyboardMonitor.disarm()
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

    /// Locks or unlocks the input bar during the Duck.ai fire onboarding path.
    /// When locked the text field cannot be activated and the collapsed bar ignores taps.
    func setOnboardingControlsLocked(_ locked: Bool) {
        isOnboardingLocked = locked
        viewController.setOnboardingDimmed(locked)
    }

    func dismissOmnibarKeyboard() {
        guard isInputPaneExpanded else { return }
        viewController.deactivateInput()
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

    private func transitionOmnibarToInactive() {
        keyboardMonitor.clearAwaiting()
        displayState = .omnibar(.inactive)
        let renderState = computeRenderState()
        // Animated so a concurrent mode change doesn't get snapped to final layout non-animatedly.
        viewController.apply(renderState.viewConfig, animated: true)
        intentSubject.send(.showOmnibarInactive)
    }

    func clearText() {
        textModel.clearForDismiss()
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
        case .contextualChat:
            resetToolsSelection()
            clearAttachments()
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
        stateMachine.computeRenderState(
            inputMode: inputMode,
            textState: textModel.textState,
            cardPosition: cardPosition,
            isInputVisibleForKeyboard: isInputVisibleForKeyboard,
            isContentOverlaySuppressed: isContentOverlaySuppressed,
            isToggleEnabled: isToggleEnabled,
            floatingReturnKeyState: makeFloatingReturnKeyState()
        )
    }

    /// Whether the toggle row appears in the UTI and the swipe-between-modes gesture is active.
    /// Combines user setting + Duck.ai-tab hide flag; the kill-switch term drops out on non-AI tabs.
    var isToggleVisible: Bool { stateMachine.isToggleVisible(isToggleEnabled: isToggleEnabled) }

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
        attachmentController.resetPasteConversation()
        isNewChatPending = true
        hasSubmittedPrompt = false
        isModelPickerForcedVisible = false
        isSubmitBlockedByRecoveryCard = false
        resetToolsSelection()
        modelSelector.updateModelChipVisibility()
        syncHasSubmittedPromptToHandler()
        clearAttachments()
        setText("")
        attachmentUsage = nil
        aiChatInputBoxVisibility = .visible
        isVoiceSessionActive = false
    }

    /// Surfaces a rejection in the input's validation banner for something the input refused that
    /// isn't an attachment — currently the text-selection cap.
    func presentRejectionBanner(_ message: String) {
        attachmentController.presentRejectionBanner(message)
    }

    func updateSelectedModel(_ modelId: String) {
        modelSelector.updateSelectedModel(modelId)
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
        pixelReporter.reportSubmitChangeModel(modelId: modelId)
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
            self.pixelReporter.reportShowModelPicker()
            if self.viewController.presentModelPickerMenu() {
                self.fireModelPickerShown()
            }
        }
    }

    func handleModelSelection(_ modelId: String) {
        modelSelector.handleModelSelection(modelId)
    }

    func updateSelectedReasoningMode(_ mode: AIChatReasoningMode) {
        modelSelector.updateSelectedReasoningMode(mode)
    }

    func handleReasoningModeSelection(_ mode: AIChatReasoningMode) {
        modelSelector.handleReasoningModeSelection(mode)
    }

    private func fireModelPickerShown() {
        pixelReporter.reportModelPickerShown()
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
    var onPageContextAttachRequested: (() -> Void)?
    /// Whether the current page can be attached. When false, the "Ask about page" menu action is disabled. Host-injected; nil ⇒ attachable.
    var isPageContextAttachable: (() -> Bool)?
    /// Reports whether page context is attached but not yet submitted, for the voice-tap pixel. Host-injected; nil off the contextual sheet.
    var hasPendingPageContextProvider: (() -> Bool)?

    func addImageAttachment(image: UIImage, fileName: String) {
        attachmentController.addImageAttachment(image: image, fileName: fileName)
    }

    func addFileAttachment(_ fileAttachment: AIChatFileAttachment, sourceURL: URL? = nil, source: String = "file_picker") {
        attachmentController.addFileAttachment(fileAttachment, sourceURL: sourceURL, source: source)
    }

    func removeAttachment(id: UUID) {
        attachmentController.removeAttachment(id: id)
    }

    func clearAttachments() {
        attachmentController.clearAttachments()
    }

    func presentPasteError(_ message: String) {
        attachmentController.presentPasteError(message)
    }

    func updateImageButtonVisibility() {
        attachmentController.updateAttachButtonPresentation()
    }

}

// MARK: - Tools Menu Selection

extension UnifiedToggleInputCoordinator {
    
    func handleToolsMenuSelection(_ identifier: UTIToolsMenu.Item.Identifier) {
        if case .customizeResponses = identifier {
            pixelReporter.reportCustomizeResponsesSelected()
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
            pixelReporter.reportToolDeselected(previous)
        }
        if let current {
            pixelReporter.reportToolSelected(current)
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
            sessionMonitor.recordActivity(mode: .search)
            clearStoreEntryAfterSubmission()
            if isAITabState {
                hide()
            } else if isContextualChatState {
                hide()
            } else if isOmnibarSession {
                deactivateToOmnibar()
            }
            delegate?.unifiedToggleInputDidSubmitQuery(text)
            didSubmitQuery.send(text)
        case .aiChat:
            let userScript = boundUserScript
            let tools = toolsController.selectedToolsForSubmission()

            if let validationMessage = attachmentController.submissionValidationMessage(for: text, mode: mode) {
                attachmentController.presentValidationError(validationMessage)
                return
            }

            switchBarSubmissionMetrics.process(text, for: .aiChat)
            sessionMonitor.recordActivity(mode: .aiChat)
            pixelReporter.reportPromptSubmitted(
                hasText: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                selectedTool: toolsController.selectedTool,
                attachments: viewController.currentAttachments,
                reasoningMode: reasoningModeForSubmitPixel,
                modelId: modelStore.persistedModelId
            )
            pixelReporter.reportToolSubmittedIfNeeded(
                selectedTool: toolsController.selectedTool,
                attachments: viewController.currentAttachments
            )

            let configuration = promptSubmissionConfiguration
            recordDuckAISubmissionStarted(
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
            if isContextualChatState, userScript == nil {
                markActiveChatPromptSubmitted()
                delegate?.unifiedToggleInputDidSubmitPrompt(
                    text,
                    modelId: configuration.modelId,
                    tools: tools,
                    reasoningEffort: configuration.reasoningEffort,
                    images: images,
                    files: files
                )
                recordDuckAIPromptDelivered(wasQueued: false, didSendBridgeMessage: nil)
                clearAttachments()
                setText("")
                dismissOmnibarKeyboard()
                return
            }

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
                if isContextualChatState {
                    dismissOmnibarKeyboard()
                }
            }
            if let userScript {
                let didSendBridgeMessage = userScript.canDispatchBridgeMessages
                userScript.submitPrompt(text, images: images, files: files, modelId: configuration.modelId, tools: tools, reasoningEffort: configuration.reasoningEffort)
                recordDuckAIPromptDelivered(wasQueued: false, didSendBridgeMessage: didSendBridgeMessage)
            } else {
                delegate?.unifiedToggleInputDidSubmitPrompt(text, modelId: configuration.modelId, tools: tools, reasoningEffort: configuration.reasoningEffort, images: images, files: files)
                recordDuckAIPromptDelivered(wasQueued: false, didSendBridgeMessage: nil)
            }
        }
    }

    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didChangeText text: String) {
        textModel.handleUserTextChange(text)
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

    func unifiedToggleInputVCDidShowModelPicker(_ vc: UnifiedToggleInputViewController) {
        fireModelPickerShown()
    }

    func unifiedToggleInputVCDidShowReasoningPicker(_ vc: UnifiedToggleInputViewController) {
        pixelReporter.reportReasoningPickerShown()
    }

    func unifiedToggleInputVCDidClearSelectedTool(_ vc: UnifiedToggleInputViewController) {
        let previousTool = toolsController.selectedTool
        clearSelectedTool()
        if let previousTool {
            pixelReporter.reportToolDeselected(previousTool)
        }
    }

    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didRemoveAttachment id: UUID, attachment: UnifiedToggleInputAttachment, isUserInitiated: Bool) {
        removeAttachment(id: id)
        if isUserInitiated {
            pixelReporter.reportAttachmentRemoved(attachment)
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
            pixelReporter.reportBackButtonPressed()
        }
        // Visual-only snap to the omnibar destination; then route through the shared dismiss handler.
        vc.applyDismissSnapshot(delegate?.unifiedToggleInputDismissSnapshot() ?? .empty)
        contentViewController.onDismissRequested?()
    }

    func unifiedToggleInputVCDidTapAIChatShortcut(_ vc: UnifiedToggleInputViewController) {
        // Non-omnibar chip can't dismiss-to-omnibar; hand off current text to avoid wrong-destination collapses.
        guard isOmnibarSession else {
            delegate?.unifiedToggleInputDidRequestAIChat(prefilledText: currentText)
            return
        }
        // Untouched prefill (== omnibarPrefilledText) opens Duck.ai with no prompt; typed/edited text is the prompt.
        let isUnmodifiedPrefill = omnibarPrefilledText.map { !$0.isEmpty && currentText == $0 } ?? false
        let prefilledText = isUnmodifiedPrefill ? "" : currentText
        // Defer to the dismiss completion — its side-effects clobber the in-flight UTI mid-collapse otherwise.
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
        pixelReporter.reportFloatingReturnPressed()
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
                attachmentController.syncValidationErrorForCurrentMode()
            }
            return
        }

        if let validationMessage = attachmentController.submissionValidationMessage(for: currentText, mode: inputMode) {
            attachmentController.presentValidationError(validationMessage)
            return
        }

        if currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, inputMode == .aiChat {
            viewController.handler.submitAIChatAttachmentOnlyPrompt()
        } else {
            viewController.handler.submitText(currentText)
        }
    }

    // MARK: Attachments

    func expandIfOnExpandedInputHost() {
        if isAITabState {
            showExpanded()
        } else if isContextualChatState {
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
        modelSelector.updateModelChipVisibility()
        syncHasSubmittedPromptToHandler()
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
        modelSelector.updateModelChipVisibility()
        refreshToolsPresentation()
        syncHasSubmittedPromptToHandler()
        if wasInRecoveryPickerSession {
            pixelReporter.reportSubmitChangeModelPromptSent()
        }
    }

    func syncInputBehaviorToHandler() {
        viewController.handler.submitsAIChatOnKeyboardReturn = submitsAIChatPromptOnKeyboardReturn
        viewController.handler.usesReturnKeySubmitButtonStyle = usesReturnKeySubmitButtonStyle
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
        modelSelector.updateModelChipVisibility()
        syncHasSubmittedPromptToHandler()
    }

    // MARK: Toolbar

    func updateToolbarAIVoiceChat() {
        viewController.isToolbarAIVoiceChatActive = viewController.handler.isAIVoiceChatEnabled && inputMode == .aiChat
    }

    func applyToolbarPresentation() {
        refreshToolsPresentation()
        modelSelector.updateReasoningPicker()
        updateToolbarAIVoiceChat()
    }

    // MARK: Tools

    func handleModelsUpdated() {
        toolsController.clearSelectionIfUnsupported(for: modelStore)
        attachmentController.removeUnsupportedAttachmentsForSelectedModel()
        modelSelector.updateModelChipLabel()
        modelSelector.updateReasoningPicker()
        if modelSelector.applyPendingGatedModelSelectionIfPossible() {
            return
        }
        modelSelector.applyPendingGatedReasoningSelectionIfPossible()
        updateImageButtonVisibility()
        refreshToolsPresentation()
    }

    func refreshToolsPresentation() {
        let presentation = toolsController.presentation(
            isActive: isActive,
            modelStore: modelStore,
            canShowCustomizeResponses: canShowCustomizeResponsesMenuItem
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
        modelSelector.updateModelChipVisibility()
        // Reflect the image-generation tool in the input placeholder ("Create images privately").
        viewController.handler.isImageGenerationSelected = toolsController.selectedTool == .imageGeneration
        viewController.refreshPlaceholderForCurrentMode()
    }

    func resetToolsSelection() {
        toolsController.clearSelection()
        refreshToolsPresentation()
    }

    var canShowCustomizeResponsesMenuItem: Bool {
        switch displayState {
        case .aiTab:
            return true
        case .contextualChat:
            return hasSubmittedPrompt && boundUserScript?.canDispatchBridgeMessages == true
        case .hidden, .omnibar:
            return false
        }
    }

    func updateImageButtonEnabledState() {
        attachmentController.updateAttachButtonPresentation()
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
        return modelSelector.resolvedSelectedReasoningMode
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
                guard let self else { return }
                self.pixelReporter.reportStopGenerationTapped()
                self.didPressStopGeneratingButton.send()
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
                if self.isContextualChatState {
                    self.viewController.deactivateInput()
                }
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
                let hasPendingPageContext = self.hasPendingPageContextProvider?() ?? false
                self.pixelReporter.reportVoiceTapped(hasPendingPageContext: hasPendingPageContext)
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
    func recordDuckAISubmissionStarted(reasoningEffort: AIChatReasoningEffort?,
                                       inputMode: DuckAIPromptWideEventData.InputMode,
                                       frontendDeliveryPath: DuckAIPromptWideEventData.FrontendDeliveryPath,
                                       hasPageContext: Bool,
                                       toolsSelected: Bool,
                                       attachmentsSelected: Bool) {
        wideEventReporter.recordSubmissionStarted(
            reasoningEffort: reasoningEffort,
            inputMode: inputMode,
            frontendDeliveryPath: frontendDeliveryPath,
            hasPageContext: hasPageContext,
            toolsSelected: toolsSelected,
            attachmentsSelected: attachmentsSelected
        )
    }

    func recordDuckAIPromptDelivered(wasQueued: Bool?, didSendBridgeMessage: Bool?) {
        wideEventReporter.recordPromptDelivered(wasQueued: wasQueued, didSendBridgeMessage: didSendBridgeMessage)
    }

    func recordDuckAIPromptInterpretedAsURL() {
        wideEventReporter.recordPromptInterpretedAsURL()
    }

    /// Called by the contextual sheet's native-input path, which submits its initial prompt
    /// outside the UTI (no `userScript` bound yet).
    func recordExternalPromptSubmitted(entryPoint: DuckAIPromptWideEventData.EntryPoint,
                                       inputMode: DuckAIPromptWideEventData.InputMode,
                                       isFirstPrompt: Bool,
                                       hasPageContext: Bool) {
        wideEventReporter.recordExternalPromptSubmitted(
            entryPoint: entryPoint,
            inputMode: inputMode,
            isFirstPrompt: isFirstPrompt,
            hasPageContext: hasPageContext
        )
    }
}

/// Derives the AI Chat models API base (scheme + host) from the resolved chat URL, so `/models` is fetched
/// from the same origin the chat loads from — production `duck.ai`, or a debug/dev host when the chat URL is
/// overridden via Debug → "Set Custom AI Chat URL". Falls back to `AIChatModelsService.defaultBaseURL` if the
/// chat URL lacks a host.
func aiChatModelsBaseURL(forChatURL chatURL: URL) -> URL {
    guard let scheme = chatURL.scheme, let host = chatURL.host else { return AIChatModelsService.defaultBaseURL }
    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    components.port = chatURL.port
    return components.url ?? AIChatModelsService.defaultBaseURL
}
