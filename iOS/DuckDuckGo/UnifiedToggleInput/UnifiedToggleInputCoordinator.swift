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
import Combine
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
    @Published var attachmentUsage: AIChatAttachmentUsage?

    // MARK: - Properties

    private(set) var viewController: UnifiedToggleInputViewController
    private(set) var contentViewController: UnifiedInputContentContainerViewController
    private(set) var floatingSubmitViewController: UnifiedToggleInputFloatingSubmitViewController
    weak var delegate: UnifiedToggleInputDelegate?

    private(set) var host: UnifiedToggleInputHost
    private(set) var isToggleEnabled: Bool
    private(set) var displayState: UnifiedToggleInputDisplayState = .hidden
    private(set) var textState: InputTextState = .empty
    private(set) var inputMode: TextEntryMode = .aiChat
    private let toggleModeStorage: ToggleModeStoring
    private let stateStore: UnifiedInputStateStoring
    private(set) var currentTabUID: TabUID?
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

    private(set) var currentText: String = ""
    var hasActiveChat: Bool { boundUserScript != nil }
    var switchBarHandler: SwitchBarHandling { viewController.handler }
    var onAnimatedDismissToOmnibar: (() -> Void)?

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

    var shouldCollapseOnKeyboardDismiss: Bool {
        displayState == .aiTab(.expanded) && inputMode == .aiChat
    }

    private var cancellables = Set<AnyCancellable>()
    private weak var boundUserScript: AIChatUserScript?
    private var boundUserScriptIdentifier: ObjectIdentifier?
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

    private let floatingSubmitStateSubject = CurrentValueSubject<UnifiedToggleInputFloatingSubmitState, Never>(.empty)
    var floatingSubmitStatePublisher: AnyPublisher<UnifiedToggleInputFloatingSubmitState, Never> {
        floatingSubmitStateSubject.eraseToAnyPublisher()
    }

    private let modeChangeSubject = PassthroughSubject<TextEntryMode, Never>()
    var modeChangePublisher: AnyPublisher<TextEntryMode, Never> {
        modeChangeSubject.eraseToAnyPublisher()
    }

    private let attachmentsChangeSubject = PassthroughSubject<Void, Never>()
    var attachmentsChangePublisher: AnyPublisher<Void, Never> {
        attachmentsChangeSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    init(
        host: UnifiedToggleInputHost,
        isToggleEnabled: Bool,
        isFireTab: Bool = false,
        duckAiNativeStorageHandler: DuckAiNativeStorageHandling? = nil,
        modelsService: AIChatModelsProviding = AIChatModelsService(),
        preferences: AIChatPreferencesPersisting = AIChatPreferencesPersistor(),
        subscriptionManager: any SubscriptionManager = AppDependencyProvider.shared.subscriptionManager,
        toggleModeStorage: ToggleModeStoring = ToggleModeStorage(),
        stateStore: UnifiedInputStateStoring? = nil
    ) {
        self.host = host
        self.isToggleEnabled = isToggleEnabled
        self.toggleModeStorage = toggleModeStorage
        self.stateStore = stateStore ?? UnifiedInputStateStore(
            preferences: preferences,
            toggleModeStorage: toggleModeStorage
        )
        self.modelStore = UTIModelStore(
            modelsService: modelsService,
            preferences: preferences,
            subscriptionManager: subscriptionManager
        )
        viewController = UnifiedToggleInputViewController(isToggleEnabled: isToggleEnabled, isFireTab: isFireTab)
        contentViewController = UnifiedInputContentContainerViewController(
            switchBarHandler: viewController.handler,
            duckAiNativeStorageHandler: duckAiNativeStorageHandler
        )
        floatingSubmitViewController = UnifiedToggleInputFloatingSubmitViewController()
        floatingSubmitViewController.refreshFireMode(fireMode: isFireTab)
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
            self?.addInvalidFileAttachment(metadata: metadata, validationMessage: message)
        }
        attachmentPresenter.fileMetadataValidationMessage = { [weak self] metadata in
            self?.attachmentPolicy.fileMetadataValidationMessage(mimeType: metadata.mimeType, fileSizeBytes: metadata.fileSizeBytes)
        }
        modelStore.onModelsUpdated = { [weak self] in
            self?.handleModelsUpdated()
        }
        subscribeToGeneratingState()
        subscribeToStopGeneratingTap()
        subscribeToCustomizeResponsesTap()
        subscribeToVoiceSearchTap()
        subscribeToAIVoiceChatTap()
        subscribeToAttachmentUsageChanges()
        viewController.isToolsButtonHidden = true

        if let cachedLabel = modelStore.preferences.selectedModelShortName {
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
        } else {
            Logger.unifiedInputState.debug("activateForTab [\(uid)]: first activation, no flush")
        }
        currentTabUID = uid
        applyState(stateStore.state(for: uid))
    }

    func applyState(_ state: TabInputState) {
        isApplyingState = true
        defer {
            isApplyingState = false
            updateFloatingSubmitState()
        }
        Logger.unifiedInputState.debug("applyState for tab [\(self.currentTabUID ?? "nil")]: \(state.summary)")

        aiChatInputBoxVisibility = state.aiChatInputBoxVisibility
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
            aiChatInputBoxVisibility: aiChatInputBoxVisibility
        )
    }

    /// Persists per-tab-only state — text and attachments. These are drafts the user
    /// is actively building; they belong to the tab, not to the global last-used
    /// defaults, and must not write through to global preferences.
    private func persistDraftToStore() {
        guard !isApplyingState, !isPerformingDismissCleanup, let uid = currentTabUID else { return }
        stateStore.update(snapshotCurrentState(), for: uid)
    }

    /// Persists a user-deliberate choice — toggle mode, model, reasoning, tool. These
    /// update the global last-used defaults and write through to the canonical global
    /// preference homes so other components (e.g. NTP omnibar) observe the change.
    private func recordUserChoiceToStore() {
        guard !isApplyingState, !isPerformingDismissCleanup, let uid = currentTabUID else { return }
        stateStore.recordUserChoice(snapshotCurrentState(), for: uid)
    }

    private func clearStoreEntryAfterSubmission() {
        currentText = ""
        textState = .empty
        guard let uid = currentTabUID else { return }
        var cleared = snapshotCurrentState()
        cleared.text = ""
        cleared.attachments = []
        cleared.selectedTool = nil
        stateStore.recordUserChoice(cleared, for: uid)
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
        cancelTopOmnibarKeyboardPresentationFallback()
        isAwaitingTopOmnibarKeyboardPresentation = false
        let previousDisplayState = displayState
        displayState = .aiTab(.expanded)
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
        updateFloatingSubmitState()

        intentSubject.send(.showExpanded(from: previousDisplayState))
        DispatchQueue.main.async { [weak self] in
            guard let self, case .aiTab(.expanded) = self.displayState else { return }
            self.viewController.activateInput()
            if !self.viewController.isInputFirstResponder {
                DispatchQueue.main.async { [weak self] in
                    guard let self, case .aiTab(.expanded) = self.displayState else { return }
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
        isInputVisibleForKeyboard = true
        // The live state is no longer authoritative for the previous tab; clearing
        // currentTabUID prevents the next activateForTab from snapshotting the
        // (now tool-cleared) live state back over the previous tab's stored entry.
        currentTabUID = nil
        resetToolsSelection()
        clearAttachments()
        setText("")
        updateFloatingSubmitState()

        let renderState = computeRenderState()
        viewController.apply(renderState.viewConfig, animated: false)
        applyToolbarPresentation()
        viewController.deactivateInput()
        intentSubject.send(.hide)
    }

    // MARK: - Omnibar State

    func activateFromOmnibar(prefilledText: String? = nil, inputMode: TextEntryMode = .search, cardPosition: UnifiedToggleInputCardPosition = .top) {
        let effectiveInputMode = isToggleEnabled ? inputMode : .search
        cancelTopOmnibarKeyboardPresentationFallback()
        isAwaitingTopOmnibarKeyboardPresentation = cardPosition == .top
        displayState = .omnibar(.active)
        setInitialInputMode(effectiveInputMode)
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
        updateFloatingSubmitState()

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
        // Text clear is deferred to dismiss completion — avoids placeholder flash mid-collapse.
        resetToolsSelection()
        clearAttachments()
        updateFloatingSubmitState()

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
        if !enabled, isOmnibarSession {
            inputMode = .search
            viewController.apply(computeRenderState().viewConfig, animated: false)
            refreshToolsPresentation()
            modeChangeSubject.send(.search)
            syncAttachmentValidationErrorForCurrentMode()
            updateFloatingSubmitState()
        }
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
        updateFloatingSubmitState()
    }

    // MARK: - Input Management

    func updateInputMode(_ mode: TextEntryMode, animated: Bool) {
        let effectiveMode: TextEntryMode = (!isToggleEnabled && isOmnibarSession) ? .search : mode
        let didModeChange = inputMode != effectiveMode
        let needsViewSync = viewController.inputMode != effectiveMode
        guard didModeChange || needsViewSync else { return }

        inputMode = effectiveMode

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
        updateFloatingSubmitState()
    }

    func updateAIVoiceChatAvailability(_ enabled: Bool) {
        viewController.handler.isAIVoiceChatEnabled = enabled
        floatingSubmitViewController.isAIVoiceChatEnabled = enabled
        updateToolbarAIVoiceChat()
    }

    func syncInputModeFromExternalSource(_ mode: TextEntryMode) {
        let effectiveMode: TextEntryMode = (!isToggleEnabled && isOmnibarSession) ? .search : mode
        let didModeChange = inputMode != effectiveMode
        let needsViewSync = viewController.inputMode != effectiveMode
        guard didModeChange || needsViewSync else { return }

        inputMode = effectiveMode
        if needsViewSync {
            viewController.setInputMode(effectiveMode, animated: false)
        }
        if didModeChange {
            modeChangeSubject.send(effectiveMode)
            refreshToolsPresentation()
        }
        updateToolbarAIVoiceChat()
        updateFloatingSubmitState()
    }

    func updateOmnibarInputVisibility(_ isInputVisible: Bool) {
        guard isInputVisibleForKeyboard != isInputVisible else { return }
        isInputVisibleForKeyboard = isInputVisible
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
        viewController.activateInput()
    }

    func dismissOmnibarKeyboard() {
        switch displayState {
        case .omnibar(.active), .aiTab(.expanded):
            viewController.deactivateInput()
        default:
            return
        }
    }

    func setEscapeHatch(_ model: EscapeHatchModel,
                        openTabCount: Int,
                        onTapped: @escaping () -> Void,
                        onTabSwitcherTapped: @escaping () -> Void) {
        contentViewController.setEscapeHatch(
            model,
            openTabCount: openTabCount,
            onTapped: onTapped,
            onTabSwitcherTapped: onTabSwitcherTapped
        )
    }

    func clearEscapeHatch() {
        contentViewController.setEscapeHatch(nil, openTabCount: 0, onTapped: nil, onTabSwitcherTapped: nil)
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
        floatingSubmitViewController.refreshFireMode(fireMode: isFireTab)
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
        hasSubmittedPrompt = true
        updateModelChipVisibility()
        syncHasSubmittedPromptToHandler()
        resetToolsSelection()
        clearStoreEntryAfterSubmission()
        showCollapsed()
        userScript.submitPrompt(text, images: nil, modelId: configuration.modelId, reasoningEffort: configuration.reasoningEffort)
    }

    func prepareExternalPromptSubmission() -> (modelId: String?, reasoningEffort: AIChatReasoningEffort?) {
        let configuration = promptSubmissionConfiguration
        hasSubmittedPrompt = true
        updateModelChipVisibility()
        syncHasSubmittedPromptToHandler()
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
    }

    private func commitCurrentToggleState() {
        committedInputMode = inputMode
        toggleModeStorage.save(inputMode)
        delegate?.unifiedToggleInputDidCommitMode(inputMode)
    }

    // MARK: - Content & Layout

    func pushContentInsets() {
        let utiHeight = viewController.view.frame.height
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
            // Toggling to search on a chat tab without text is a *mode switch*; keep the chat
            // web view visible. Suggestions take over once the user starts typing.
            let isSearchOnAITabWithoutText = isSearchOnAITab && currentText.isEmpty
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

        let isFloatingSubmitVisible = displayState == .omnibar(.active)
            && cardPosition == .top
            && inputMode == .aiChat
        let shouldSuppressContentOverlay = isOmnibarSession && isContentOverlaySuppressed && textState != .userTyped
        let effectiveContentVisible = isContentVisible && !shouldSuppressContentOverlay

        return UTIRenderState(
            isInputVisible: isInputVisible,
            isContentVisible: effectiveContentVisible,
            cardLayout: cardLayout(forIsExpanded: isExpanded),
            cardPosition: cardPosition,
            usesOmnibarMargins: cardPosition == .top && isOmnibarSession,
            isToolbarSubmitHidden: cardPosition == .top && isOmnibarSession,
            inactiveAppearance: inactiveAppearance,
            isFloatingSubmitVisible: isFloatingSubmitVisible,
            isToggleEnabled: isToggleEnabled,
            contentInputMode: inputMode,
            inputMode: inputMode
        )
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
            let showsToggle = isToggleEnabled
            // Keep the AI-chat toolbar on Duck.ai tabs even when the toggle is user-disabled,
            // so the user retains the model selector / attachments / send affordances.
            let showsToolbar = inputMode == .aiChat && (isToggleEnabled || isAITabState)
            return .expanded(showsToggle: showsToggle, showsToolbar: showsToolbar)
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

    func startNewChat() {
        isNewChatPending = true
        hasSubmittedPrompt = false
        resetToolsSelection()
        updateModelChipVisibility()
        syncHasSubmittedPromptToHandler()
        clearAttachments()
        setText("")
        attachmentUsage = nil
        aiChatInputBoxVisibility = .visible
    }

    func updateSelectedModel(_ modelId: String) {
        modelStore.updateSelectedModel(modelId)
        handleModelsUpdated()
        recordUserChoiceToStore()
    }

    func updateSelectedReasoningMode(_ mode: AIChatReasoningMode) {
        modelStore.updateSelectedReasoningMode(mode)
        updateReasoningPicker()
        recordUserChoiceToStore()
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
            modelStore.cacheSelectedModelShortName(shortName)
        }
        viewController.modelPickerMenu = modelStore.models.isEmpty ? nil : modelMenuFactory.makeMenu(
            models: modelStore.models,
            selectedId: selectedId,
            hasActiveSubscription: modelStore.subscriptionState.hasActiveSubscription,
            advancedSectionTitle: modelStore.subscriptionState.hasActiveSubscription
                ? UserText.aiChatAdvancedModelsSectionHeader
                : UserText.aiChatAdvancedModelsMenuTitle,
            basicSectionTitle: UserText.aiChatBasicModelsSectionHeader
        ) { [weak self] modelId in
            self?.updateSelectedModel(modelId)
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
                self?.updateSelectedReasoningMode(mode)
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
        if let validationMessage = attachmentPolicy.fileValidationMessage(for: fileAttachment) {
            viewController.addAttachment(.invalidFile(
                UnifiedToggleInputInvalidFileAttachment(
                    id: fileAttachment.id,
                    fileName: fileAttachment.fileName,
                    mimeType: fileAttachment.mimeType,
                    fileSizeBytes: fileAttachment.fileSizeBytes,
                    validationMessage: validationMessage,
                    sourceURL: sourceURL
                )
            ))
            presentAttachmentValidationError(validationMessage)
            persistDraftToStore()
            updateAttachButtonPresentation()
            return
        }

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

}

// MARK: - Tools Menu Selection

extension UnifiedToggleInputCoordinator {
    
    func handleToolsMenuSelection(_ identifier: UTIToolsMenu.Item.Identifier) {
        switch identifier {
        case .webSearch:
            toolsController.toggleSelection(for: .webSearch, modelStore: modelStore)
        case .imageGeneration:
            toolsController.toggleSelection(for: .imageGeneration, modelStore: modelStore)
        }
        refreshToolsPresentation()
        recordUserChoiceToStore()
    }
}

// MARK: - UnifiedToggleInputViewControllerDelegate

extension UnifiedToggleInputCoordinator: UnifiedToggleInputViewControllerDelegate {

    func unifiedToggleInputVCDidTapWhileCollapsed(_ vc: UnifiedToggleInputViewController) {
        showExpanded(inputMode: inputMode)
    }

    func unifiedToggleInputVCDidRequestSubmitCurrentInput(_ vc: UnifiedToggleInputViewController) {
        submitCurrentInputFromCoordinator()
    }

    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didSubmitText text: String, mode: TextEntryMode) {
        commitCurrentToggleState()

        switch mode {
        case .search:
            clearStoreEntryAfterSubmission()
            if case .aiTab = displayState {
                hide()
            } else if isOmnibarSession {
                deactivateToOmnibar()
            }
            delegate?.unifiedToggleInputDidSubmitQuery(text)
            didSubmitQuery.send(text)
        case .aiChat:
            if let validationMessage = attachmentSubmissionValidationMessage(for: text, mode: mode) {
                presentAttachmentValidationError(validationMessage)
                return
            }

            let tools = toolsController.selectedToolsForSubmission()
            let images = selectedModelSupportsImageUpload
                ? UnifiedToggleInputImageEncoder.encode(viewController.currentAttachments)
                : nil
            let files = selectedModelSupportsFileUpload
                ? UnifiedToggleInputFileEncoder.encode(viewController.currentAttachments)
                : nil
            let configuration = promptSubmissionConfiguration

            resetToolsSelection()
            clearStoreEntryAfterSubmission()
            clearAttachments()
            hasSubmittedPrompt = true
            updateModelChipVisibility()
            syncHasSubmittedPromptToHandler()
            if isOmnibarSession {
                deactivateToOmnibar()
            } else {
                // showCollapsed has no dismiss hook; clear synchronously.
                setText("")
                showCollapsed()
            }
            if let userScript = boundUserScript {
                userScript.submitPrompt(text, images: images, files: files, modelId: configuration.modelId, tools: tools, reasoningEffort: configuration.reasoningEffort)
            } else {
                delegate?.unifiedToggleInputDidSubmitPrompt(text, modelId: configuration.modelId, tools: tools, reasoningEffort: configuration.reasoningEffort, images: images, files: files)
            }
        }
    }

    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didChangeText text: String) {
        if isPerformingDismissCleanup { return }
        currentText = text
        textState = text.isEmpty ? .empty : .userTyped
        textChangeSubject.send(text)
        persistDraftToStore()
        clearAttachmentValidationErrorIfPossible()
        updateFloatingSubmitState()
    }

    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didChangeMode mode: TextEntryMode) {
        updateInputMode(mode, animated: true)
    }

    func unifiedToggleInputVCDidTapSearchGoTo(_ vc: UnifiedToggleInputViewController) {
        showExpanded(inputMode: .search)
    }

    func unifiedToggleInputVCDidClearSelectedTool(_ vc: UnifiedToggleInputViewController) {
        clearSelectedTool()
    }

    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didRemoveAttachment id: UUID) {
        removeAttachment(id: id)
    }

    func unifiedToggleInputVCDidChangeAttachments(_ vc: UnifiedToggleInputViewController) {
        attachmentsChangeSubject.send()
        updateImageButtonEnabledState()
        updateFloatingSubmitState()
    }

    func unifiedToggleInputVCDidChangeHeight(_ vc: UnifiedToggleInputViewController) {
        delegate?.unifiedToggleInputDidChangeHeight()
    }

    func unifiedToggleInputVCDidTapInlineDismiss(_ vc: UnifiedToggleInputViewController) {
        // The inline X dismisses the same way the floating X does — forward to the
        // content container's shared handler so both controls route through one path.
        contentViewController.onDismissRequested?()
    }

    func unifiedToggleInputVCDidTapAIChatShortcut(_ vc: UnifiedToggleInputViewController) {
        delegate?.unifiedToggleInputDidRequestAIChat(prefilledText: viewController.handler.currentText)
    }

    func unifiedToggleInputVCDidTapFire(_ vc: UnifiedToggleInputViewController) {
        delegate?.unifiedToggleInputDidRequestFire()
    }

    func unifiedToggleInputVCDidTapVoice(_ vc: UnifiedToggleInputViewController) {
        delegate?.unifiedToggleInputDidRequestDuckAIVoiceMode()
    }
}

extension UnifiedToggleInputCoordinator {

    func submitCurrentInputFromFloatingSubmit() {
        submitCurrentInputFromCoordinator()
    }

}

private extension UnifiedToggleInputCoordinator {

    func submitCurrentInputFromCoordinator() {
        let state = makeFloatingSubmitState()
        guard state.canSubmit else {
            if state.hasInvalidAttachment {
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
        updateFloatingSubmitState()
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
        attachmentPolicy.fileMetadataValidationMessage(
            mimeType: attachment.mimeType,
            fileSizeBytes: attachment.fileSizeBytes > 0 ? attachment.fileSizeBytes : nil
        )
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

    func makeFloatingSubmitState() -> UnifiedToggleInputFloatingSubmitState {
        UnifiedToggleInputFloatingSubmitState(
            text: currentText,
            mode: inputMode,
            attachments: viewController.currentAttachments)
    }

    func updateFloatingSubmitState() {
        floatingSubmitStateSubject.send(makeFloatingSubmitState())
    }

    // MARK: Session State

    func syncChipVisibility(hasExistingChat: Bool) {
        if isNewChatPending && hasExistingChat {
            return
        }
        isNewChatPending = false
        let shouldHide = hasExistingChat || hasSubmittedPrompt
        guard hasSubmittedPrompt != shouldHide else { return }
        hasSubmittedPrompt = shouldHide
        updateModelChipVisibility()
        syncHasSubmittedPromptToHandler()
    }

    func updateModelChipVisibility() {
        // Contextual chat picks the model upstream (in the half-sheet); the model chip is permanently hidden here.
        // Image generation has no model picker either — when active, the chip is hidden until the tool is deselected.
        let isImageGenActive = toolsController.selectedTool == .imageGeneration
        viewController.isModelChipHidden = host == .contextualChat || hasSubmittedPrompt || isImageGenActive
        updateReasoningPicker()
    }

    func syncHasSubmittedPromptToHandler() {
        switchBarHandler.hasSubmittedPrompt = hasSubmittedPrompt
    }

    func resetSessionState() {
        isNewChatPending = false
        aiChatStatus = .unknown
        attachmentUsage = nil
        hasSubmittedPrompt = false
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

    // MARK: Subscriptions

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
                self.resetToolsSelection()
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
                self?.delegate?.unifiedToggleInputDidRequestAIVoiceChat()
            }
            .store(in: &cancellables)
    }
}
