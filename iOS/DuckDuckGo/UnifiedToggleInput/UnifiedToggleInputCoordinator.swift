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
import Subscription
import UIKit

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
    case showCollapsed
    case showExpanded
    case showOmnibarEditing(expandedHeight: CGFloat, pendingExpandedHeight: CGFloat? = nil)
    case showOmnibarInactive
    case showOmnibarActive
    case hideOmnibarEditing(animated: Bool)
    case hide
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
            attachmentUsage: attachmentUsage,
            pendingAttachmentCount: viewController.currentAttachments.count
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
    @Published var aiChatInputBoxVisibility: AIChatInputBoxVisibility = .unknown
    @Published var attachmentUsage: AIChatAttachmentUsage?

    // MARK: - Properties

    private(set) var viewController: UnifiedToggleInputViewController
    private(set) var contentViewController: UnifiedInputContentContainerViewController
    private(set) var floatingSubmitViewController: UnifiedToggleInputFloatingSubmitViewController
    weak var delegate: UnifiedToggleInputDelegate?

    private(set) var isToggleEnabled: Bool
    private(set) var displayState: UnifiedToggleInputDisplayState = .hidden
    private(set) var textState: InputTextState = .empty
    private(set) var inputMode: TextEntryMode = .aiChat
    private let toggleModeStorage: ToggleModeStoring
    private(set) var committedInputMode: TextEntryMode = .search
    private(set) var cardPosition: UnifiedToggleInputCardPosition = .bottom
    private(set) var isInputVisibleForKeyboard: Bool = true
    private var isAwaitingTopOmnibarKeyboardPresentation = false
    private var topOmnibarKeyboardPresentationFallback: DispatchWorkItem?

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
        isToggleEnabled: Bool,
        isFireTab: Bool = false,
        duckAiNativeStorageHandler: DuckAiNativeStorageHandling? = nil,
        modelsService: AIChatModelsProviding = AIChatModelsService(),
        preferences: AIChatPreferencesPersisting = AIChatPreferencesPersistor(),
        subscriptionManager: any SubscriptionManager = AppDependencyProvider.shared.subscriptionManager,
        toggleModeStorage: ToggleModeStoring = ToggleModeStorage()
    ) {
        self.isToggleEnabled = isToggleEnabled
        self.toggleModeStorage = toggleModeStorage
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
        modelStore.onModelsUpdated = { [weak self] in
            self?.handleModelsUpdated()
        }
        subscribeToGeneratingState()
        subscribeToStopGeneratingTap()
        subscribeToCustomizeResponsesTap()
        subscribeToVoiceSearchTap()
        subscribeToAttachmentUsageChanges()
        viewController.isToolsButtonHidden = true

        if let cachedLabel = modelStore.preferences.selectedModelShortName {
            viewController.modelName = cachedLabel
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

    private var isNewChatPending = false

    // MARK: - AI Tab State

    func showCollapsed() {
        cancelTopOmnibarKeyboardPresentationFallback()
        isAwaitingTopOmnibarKeyboardPresentation = false
        displayState = .aiTab(.collapsed)
        setInitialInputMode(.aiChat)
        isInputVisibleForKeyboard = true

        let renderState = computeRenderState()

        viewController.apply(renderState.viewConfig, animated: false)
        applyToolbarPresentation()
        viewController.deactivateInput()
        intentSubject.send(.showCollapsed)
    }

    func showExpanded(prefilledText: String? = nil, inputMode: TextEntryMode = .aiChat) {
        cancelTopOmnibarKeyboardPresentationFallback()
        isAwaitingTopOmnibarKeyboardPresentation = false
        displayState = .aiTab(.expanded)
        setInitialInputMode(inputMode)
        isInputVisibleForKeyboard = true

        let renderState = computeRenderState()

        viewController.apply(renderState.viewConfig, animated: false)
        applyToolbarPresentation()
        fetchModels()

        if let prefilledText, !prefilledText.isEmpty {
            setText(prefilledText)
            textState = .prefilledSelected
        }

        intentSubject.send(.showExpanded)
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
        resetToolsSelection()

        let renderState = computeRenderState()
        viewController.apply(renderState.viewConfig, animated: false)
        applyToolbarPresentation()
        viewController.deactivateInput()
        contentViewController.setDismissButtonVisible(renderState.isFloatingDismissVisible)
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
        updateToolbarAIVoiceChat()
        isInputVisibleForKeyboard = true
        hasSubmittedPrompt = false
        resetToolsSelection()
        updateModelChipVisibility()
        syncHasSubmittedPromptToHandler()

        viewController.setExpanded(false, animated: false)
        let renderState = computeRenderState()
        viewController.apply(renderState.viewConfig, animated: false)
        applyToolbarPresentation()
        fetchModels()

        if let text = prefilledText, !text.isEmpty {
            setText(text)
            textState = .prefilledSelected
        }

        contentViewController.setDismissButtonVisible(renderState.isFloatingDismissVisible)
        let expandedHeight = editingHeight()

        if cardPosition == .top && isToggleEnabled {
            viewController.setExpanded(false, animated: false)
            viewController.setExpandedWithToggleHidden(true)
            let toggleHiddenHeight = editingHeight()
            intentSubject.send(.showOmnibarEditing(expandedHeight: toggleHiddenHeight, pendingExpandedHeight: expandedHeight))
        } else if cardPosition == .top {
            viewController.setExpanded(false, animated: false)
            viewController.setExpandedWithToggleHidden(true)
            let omnibarMatchingHeight = editingHeight()
            intentSubject.send(.showOmnibarEditing(expandedHeight: omnibarMatchingHeight))
        } else {
            intentSubject.send(.showOmnibarEditing(expandedHeight: expandedHeight))
        }

        if cardPosition == .top {
            scheduleTopOmnibarKeyboardPresentationFallback()
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, case .omnibar(.active) = displayState else { return }
            viewController.activateInput()
            if textState == .prefilledSelected {
                viewController.selectAllText()
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

        if resetView {
            let renderState = computeRenderState()
            viewController.apply(renderState.viewConfig, animated: false)
            applyToolbarPresentation()
            viewController.deactivateInput()
            contentViewController.setDismissButtonVisible(renderState.isFloatingDismissVisible)
        } else {
            applyToolbarPresentation()
            viewController.deactivateInput()
            let renderState = computeRenderState()
            contentViewController.setDismissButtonVisible(renderState.isFloatingDismissVisible)
        }
        intentSubject.send(.hideOmnibarEditing(animated: animateDismiss))
    }

    func updateToggleEnabled(_ enabled: Bool) {
        guard enabled != isToggleEnabled else { return }
        isToggleEnabled = enabled
        viewController.updateToggleEnabled(enabled)
        if !enabled, isOmnibarSession {
            inputMode = .search
            viewController.apply(computeRenderState().viewConfig, animated: false)
            refreshToolsPresentation()
            modeChangeSubject.send(.search)
        }
    }

    func animateOmnibarExpansion(additionalAnimations: (() -> Void)? = nil) {
        viewController.animateToggleReveal(additionalAnimations: additionalAnimations)
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
    }

    // MARK: - Input Management

    func updateInputMode(_ mode: TextEntryMode, animated: Bool) {
        let effectiveMode: TextEntryMode = (!isToggleEnabled && isOmnibarSession) ? .search : mode
        let didModeChange = inputMode != effectiveMode
        let needsViewSync = viewController.inputMode != effectiveMode
        guard didModeChange || needsViewSync else { return }

        inputMode = effectiveMode
        if needsViewSync {
            viewController.setInputMode(effectiveMode, animated: animated)
        }
        if didModeChange {
            modeChangeSubject.send(effectiveMode)
        }
        updateToolbarAIVoiceChat()
        refreshToolsPresentation()
        if didModeChange, effectiveMode == .search {
            clearAttachments()
        }
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
    }

    func updateOmnibarInputVisibility(_ isInputVisible: Bool) {
        guard isInputVisibleForKeyboard != isInputVisible else { return }
        isInputVisibleForKeyboard = isInputVisible
        let isAITabSearch = displayState == .aiTab(.expanded) && inputMode == .search

        switch (displayState, isInputVisible) {
        case (.omnibar(.active), false) where isAwaitingTopOmnibarKeyboardPresentation:
            return
        case (.omnibar(.active), false):
            cancelTopOmnibarKeyboardPresentationFallback()
            transitionOmnibarToInactive()
        case (.omnibar(.inactive), true):
            cancelTopOmnibarKeyboardPresentationFallback()
            isAwaitingTopOmnibarKeyboardPresentation = false
            displayState = .omnibar(.active)
            let renderState = computeRenderState()
            viewController.apply(renderState.viewConfig, animated: false)
            contentViewController.setDismissButtonVisible(renderState.isFloatingDismissVisible)
            intentSubject.send(.showOmnibarActive)
        case (.omnibar(.active), true):
            cancelTopOmnibarKeyboardPresentationFallback()
            isAwaitingTopOmnibarKeyboardPresentation = false
        case (.aiTab(.expanded), _) where isAITabSearch:
            let renderState = computeRenderState()
            viewController.apply(renderState.viewConfig, animated: false)
            contentViewController.setDismissButtonVisible(renderState.isFloatingDismissVisible)
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

    func setEscapeHatch(_ model: EscapeHatchModel?, onTapped: (() -> Void)?) {
        contentViewController.setEscapeHatch(model, onTapped: onTapped)
    }

    func updateVoiceSearchAvailability(_ enabled: Bool) {
        viewController.isVoiceSearchAvailable = enabled
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
        contentViewController.setDismissButtonVisible(renderState.isFloatingDismissVisible)
        intentSubject.send(.showOmnibarInactive)
    }

    func clearText() {
        setText("")
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
        switch displayState {
        case .omnibar:
            deactivateToOmnibar()
        case .aiTab:
            switch type {
            case .query: hide()
            case .prompt:
                resetToolsSelection()
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

    func applyDismissButtonVisibility() {
        let renderState = computeRenderState()
        contentViewController.setDismissButtonVisible(renderState.isFloatingDismissVisible)
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
            isContentVisible = !isAIChatOnAITab
            let isSearchOnAITab = isAITabState && inputMode == .search
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

        return UTIRenderState(
            isInputVisible: isInputVisible,
            isContentVisible: isContentVisible,
            isExpanded: isExpanded,
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
    }

    func updateSelectedModel(_ modelId: String) {
        modelStore.updateSelectedModel(modelId)
        handleModelsUpdated()
    }

    func updateSelectedReasoningMode(_ mode: AIChatReasoningMode) {
        modelStore.updateSelectedReasoningMode(mode)
        updateReasoningPicker()
    }

    func selectTool(_ tool: AIChatRAGTool) {
        toolsController.select(tool, for: modelStore)
        refreshToolsPresentation()
    }

    func clearSelectedTool() {
        resetToolsSelection()
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
            isBottomAnchored: viewController.cardPosition == .bottom,
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

    func presentAttachmentOptions() {
        let remaining = remainingImagesForPicker
        guard remaining > 0 else { return }
        guard let scene = viewController.view.window?.windowScene,
              let root = scene.keyWindow?.rootViewController else { return }
        attachmentPresenter.presentAttachmentOptions(
            from: viewController.attachButtonView,
            presenter: root,
            remaining: remaining
        )
    }

    private func expandIfOnAITab() {
        if case .aiTab = displayState {
            showExpanded()
        }
    }

    func addImageAttachment(image: UIImage, fileName: String) {
        guard !viewController.isAttachmentsFull, !isConversationImageLimitReached else { return }
        let attachment = AIChatImageAttachment(image: image, fileName: fileName)
        viewController.addAttachment(attachment)
    }

    func removeAttachment(id: UUID) {
        viewController.removeAttachment(id: id)
    }

    func clearAttachments() {
        guard !viewController.currentAttachments.isEmpty else { return }
        viewController.removeAllAttachments()
    }

    func updateImageButtonVisibility() {
        let supportsImages = selectedModelSupportsImageUpload
        viewController.isImageButtonHidden = !supportsImages
        viewController.modelSupportsImageAttachments = supportsImages
        updateImageButtonEnabledState()
    }

}

// MARK: - UnifiedToggleInputViewControllerDelegate

extension UnifiedToggleInputCoordinator: UnifiedToggleInputViewControllerDelegate {

    func unifiedToggleInputVCDidTapWhileCollapsed(_ vc: UnifiedToggleInputViewController) {
        showExpanded(inputMode: inputMode)
    }

    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didSubmitText text: String, mode: TextEntryMode) {
        commitCurrentToggleState()

        switch mode {
        case .search:
            if case .aiTab = displayState {
                hide()
            } else if isOmnibarSession {
                deactivateToOmnibar()
            }
            delegate?.unifiedToggleInputDidSubmitQuery(text)
            didSubmitQuery.send(text)
        case .aiChat:
            let tools = toolsController.selectedToolsForSubmission()
            let images = selectedModelSupportsImageUpload
                ? UnifiedToggleInputImageEncoder.encode(viewController.currentAttachments)
                : nil
            let configuration = promptSubmissionConfiguration
            clearAttachments()
            hasSubmittedPrompt = true
            updateModelChipVisibility()
            syncHasSubmittedPromptToHandler()
            resetToolsSelection()
            if isOmnibarSession {
                deactivateToOmnibar()
            } else {
                // showCollapsed has no dismiss hook; clear synchronously.
                setText("")
                showCollapsed()
            }
            if let userScript = boundUserScript {
                userScript.submitPrompt(text, images: images, modelId: configuration.modelId, tools: tools, reasoningEffort: configuration.reasoningEffort)
            } else {
                delegate?.unifiedToggleInputDidSubmitPrompt(text, modelId: configuration.modelId, tools: tools, reasoningEffort: configuration.reasoningEffort, images: images)
            }
        }
    }

    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didChangeText text: String) {
        currentText = text
        textState = text.isEmpty ? .empty : .userTyped
        textChangeSubject.send(text)
    }

    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didChangeMode mode: TextEntryMode) {
        updateInputMode(mode, animated: true)
    }

    func unifiedToggleInputVCDidTapSearchGoTo(_ vc: UnifiedToggleInputViewController) {
        showExpanded(inputMode: .search)
    }

    func unifiedToggleInputVCDidTapAttach(_ vc: UnifiedToggleInputViewController) {
        presentAttachmentOptions()
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
    }

    func unifiedToggleInputVCDidChangeHeight(_ vc: UnifiedToggleInputViewController) {
        delegate?.unifiedToggleInputDidChangeHeight()
    }

    func unifiedToggleInputVCDidTapInlineDismiss(_ vc: UnifiedToggleInputViewController) {
        // The inline X dismisses the same way the floating X does — forward to the
        // content container's shared handler so both controls route through one path.
        contentViewController.onDismissRequested?()
    }
}

private extension UnifiedToggleInputCoordinator {

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
        viewController.isModelChipHidden = hasSubmittedPrompt
        updateReasoningPicker()
    }

    func syncHasSubmittedPromptToHandler() {
        switchBarHandler.hasSubmittedPrompt = hasSubmittedPrompt
    }

    func resetSessionState() {
        isNewChatPending = false
        // While the UTI is hidden, dismiss completion owns the visible text — clearing here would flash the placeholder.
        if isActive {
            setText("")
        }
        aiChatStatus = .unknown
        aiChatInputBoxVisibility = .unknown
        attachmentUsage = nil
        hasSubmittedPrompt = false
        resetToolsSelection()
        updateModelChipVisibility()
        syncHasSubmittedPromptToHandler()
        clearAttachments()
    }

    // MARK: Toolbar

    func updateToolbarAIVoiceChat() {
        viewController.isToolbarAIVoiceChatActive = viewController.handler.isAIVoiceChatEnabled && inputMode == .aiChat
    }

    func applyToolbarPresentation() {
        refreshToolsPresentation()
    }

    // MARK: Tools

    func handleModelsUpdated() {
        toolsController.clearSelectionIfUnsupported(for: modelStore)
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
    }

    func resetToolsSelection() {
        toolsController.clearSelection()
        refreshToolsPresentation()
    }

    func handleToolsMenuSelection(_ identifier: UTIToolsMenu.Item.Identifier) {
        switch identifier {
        case .customizeResponses:
            viewController.handler.customizeResponsesButtonTapped()
        case .webSearch:
            toolsController.toggleSelection(for: .webSearch, modelStore: modelStore)
            refreshToolsPresentation()
        }
    }

    func updateImageButtonEnabledState() {
        let canAttachMore = remainingImagesForPicker > 0 && !viewController.isGenerating
        viewController.isImageButtonEnabled = canAttachMore
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
                self?.delegate?.unifiedToggleInputDidRequestVoiceSearch()
            }
            .store(in: &cancellables)
    }
}
