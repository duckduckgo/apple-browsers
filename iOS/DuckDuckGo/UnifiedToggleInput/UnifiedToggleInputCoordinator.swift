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

    var isActive: Bool {
        displayState != .hidden
    }

    var shouldCollapseOnKeyboardDismiss: Bool {
        displayState == .aiTab(.expanded) && inputMode == .aiChat
    }

    private var cancellables = Set<AnyCancellable>()
    private weak var boundUserScript: AIChatUserScript?
    private var boundUserScriptIdentifier: ObjectIdentifier?
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
        duckAiNativeStorageHandler: DuckAiNativeStorageHandling? = nil,
        modelsService: AIChatModelsProviding = AIChatModelsService(),
        preferences: AIChatPreferencesPersisting = AIChatPreferencesPersistor(),
        subscriptionManager: any SubscriptionManager = AppDependencyProvider.shared.subscriptionManager
    ) {
        self.isToggleEnabled = isToggleEnabled
        self.modelStore = UTIModelStore(
            modelsService: modelsService,
            preferences: preferences,
            subscriptionManager: subscriptionManager
        )
        viewController = UnifiedToggleInputViewController(isToggleEnabled: isToggleEnabled)
        contentViewController = UnifiedInputContentContainerViewController(
            switchBarHandler: viewController.handler,
            duckAiNativeStorageHandler: duckAiNativeStorageHandler
        )
        floatingSubmitViewController = UnifiedToggleInputFloatingSubmitViewController()
        super.init()
        viewController.delegate = self
        attachmentPresenter.onExpandIfNeeded = { [weak self] in
            self?.expandIfOnAITab()
        }
        attachmentPresenter.onImagePicked = { [weak self] image, fileName in
            self?.addImageAttachment(image: image, fileName: fileName)
        }
        modelStore.onModelsUpdated = { [weak self] in
            self?.updateModelChipLabel()
            self?.updateImageButtonVisibility()
        }
        subscribeToGeneratingState()
        subscribeToStopGeneratingTap()
        subscribeToCustomizeResponsesTap()
        subscribeToVoiceSearchTap()
        subscribeToAttachmentUsageChanges()
        viewController.isCustomizeResponsesButtonHidden = true

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

    private func syncChipVisibility(hasExistingChat: Bool) {
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

    // MARK: - AI Tab State

    func showCollapsed() {
        cancelTopOmnibarKeyboardPresentationFallback()
        isAwaitingTopOmnibarKeyboardPresentation = false
        displayState = .aiTab(.collapsed)
        inputMode = .aiChat
        isInputVisibleForKeyboard = true

        let renderState = computeRenderState()

        viewController.apply(renderState.viewConfig, animated: false)
        viewController.deactivateInput()
        viewController.isCustomizeResponsesButtonHidden = false
        intentSubject.send(.showCollapsed)
    }

    func showExpanded(prefilledText: String? = nil, inputMode: TextEntryMode = .aiChat) {
        cancelTopOmnibarKeyboardPresentationFallback()
        isAwaitingTopOmnibarKeyboardPresentation = false
        displayState = .aiTab(.expanded)
        self.inputMode = inputMode
        isInputVisibleForKeyboard = true

        let renderState = computeRenderState()

        viewController.apply(renderState.viewConfig, animated: false)
        viewController.isCustomizeResponsesButtonHidden = false
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

        let renderState = computeRenderState()
        viewController.apply(renderState.viewConfig, animated: false)
        viewController.deactivateInput()
        viewController.isCustomizeResponsesButtonHidden = true
        contentViewController.setDismissButtonVisible(renderState.isContentVisible)
        intentSubject.send(.hide)
    }

    // MARK: - Omnibar State

    func activateFromOmnibar(prefilledText: String? = nil, inputMode: TextEntryMode = .search, cardPosition: UnifiedToggleInputCardPosition = .top) {
        let effectiveInputMode = isToggleEnabled ? inputMode : .search
        cancelTopOmnibarKeyboardPresentationFallback()
        isAwaitingTopOmnibarKeyboardPresentation = cardPosition == .top
        displayState = .omnibar(.active)
        self.inputMode = effectiveInputMode
        self.cardPosition = cardPosition
        viewController.handler.hidesVoiceButton = false
        updateToolbarAIVoiceChat()
        isInputVisibleForKeyboard = true
        hasSubmittedPrompt = false
        updateModelChipVisibility()
        syncHasSubmittedPromptToHandler()

        viewController.setExpanded(false, animated: false)
        let renderState = computeRenderState()
        viewController.apply(renderState.viewConfig, animated: false)
        viewController.isCustomizeResponsesButtonHidden = true
        fetchModels()

        if let text = prefilledText, !text.isEmpty {
            setText(text)
            textState = .prefilledSelected
        }

        contentViewController.setDismissButtonVisible(renderState.isContentVisible)
        let expandedHeight = omnibarEditingHeight()

        if cardPosition == .top && isToggleEnabled {
            viewController.setExpanded(false, animated: false)
            viewController.setExpandedWithToggleHidden(true)
            let toggleHiddenHeight = omnibarEditingHeight()
            intentSubject.send(.showOmnibarEditing(expandedHeight: toggleHiddenHeight, pendingExpandedHeight: expandedHeight))
        } else if cardPosition == .top {
            viewController.setExpanded(false, animated: false)
            viewController.setExpandedWithToggleHidden(true)
            let omnibarMatchingHeight = omnibarEditingHeight()
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
        cancelTopOmnibarKeyboardPresentationFallback()
        isAwaitingTopOmnibarKeyboardPresentation = false
        displayState = .hidden
        cardPosition = .bottom
        isInputVisibleForKeyboard = true
        setText("")
        clearAttachments()

        if resetView {
            let renderState = computeRenderState()
            viewController.apply(renderState.viewConfig, animated: false)
            viewController.deactivateInput()
            contentViewController.setDismissButtonVisible(renderState.isContentVisible)
        } else {
            viewController.deactivateInput()
            let renderState = computeRenderState()
            contentViewController.setDismissButtonVisible(renderState.isContentVisible)
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
            modeChangeSubject.send(.search)
        }
    }

    func animateOmnibarExpansion(additionalAnimations: (() -> Void)? = nil) {
        viewController.animateToggleReveal(additionalAnimations: additionalAnimations)
    }

    func omnibarEditingHeight() -> CGFloat {
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
        if didModeChange, effectiveMode == .search {
            clearAttachments()
        }
    }

    func updateAIVoiceChatAvailability(_ enabled: Bool) {
        viewController.handler.isAIVoiceChatEnabled = enabled
        floatingSubmitViewController.isAIVoiceChatEnabled = enabled
        updateToolbarAIVoiceChat()
    }

    private func updateToolbarAIVoiceChat() {
        viewController.isToolbarAIVoiceChatActive = viewController.handler.isAIVoiceChatEnabled && inputMode == .aiChat
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
        }
        updateToolbarAIVoiceChat()
    }

    func updateOmnibarInputVisibility(_ isInputVisible: Bool) {
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
            contentViewController.setDismissButtonVisible(renderState.isContentVisible)
            intentSubject.send(.showOmnibarActive)
        case (.omnibar(.active), true):
            cancelTopOmnibarKeyboardPresentationFallback()
            isAwaitingTopOmnibarKeyboardPresentation = false
        case (.aiTab(.expanded), false) where isAITabSearch:
            let renderState = computeRenderState()
            viewController.apply(renderState.viewConfig, animated: false)
            contentViewController.setDismissButtonVisible(renderState.isContentVisible)
        case (.aiTab(.expanded), true) where isAITabSearch:
            let renderState = computeRenderState()
            viewController.apply(renderState.viewConfig, animated: false)
            contentViewController.setDismissButtonVisible(renderState.isContentVisible)
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

    func updateVoiceSearchAvailability(_ enabled: Bool) {
        viewController.isVoiceSearchAvailable = enabled
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
        viewController.apply(renderState.viewConfig, animated: false)
        contentViewController.setDismissButtonVisible(renderState.isContentVisible)
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
        let modelId = hasSubmittedPrompt ? nil : persistedModelId
        hasSubmittedPrompt = true
        updateModelChipVisibility()
        syncHasSubmittedPromptToHandler()
        showCollapsed()
        userScript.submitPrompt(text, images: nil, modelId: modelId)
    }

    func handleExternalSubmission(_ type: ExternalSubmissionType) {
        switch displayState {
        case .omnibar:
            deactivateToOmnibar()
        case .aiTab:
            switch type {
            case .query: hide()
            case .prompt: showCollapsed()
            }
        case .hidden:
            break
        }
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
        contentViewController.setDismissButtonVisible(renderState.isContentVisible)
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
    var selectedModelSupportsImageUpload: Bool { modelStore.selectedModelSupportsImageUpload }

    func fetchModels() {
        modelStore.fetchModels()
    }

    func startNewChat() {
        isNewChatPending = true
        hasSubmittedPrompt = false
        updateModelChipVisibility()
        syncHasSubmittedPromptToHandler()
        clearAttachments()
        setText("")
        attachmentUsage = nil
    }

    func updateSelectedModel(_ modelId: String) {
        modelStore.updateSelectedModel(modelId)
        updateModelChipLabel()
        updateImageButtonVisibility()
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

    private func updateImageButtonEnabledState() {
        let canAttachMore = remainingImagesForPicker > 0 && !viewController.isGenerating
        viewController.isImageButtonEnabled = canAttachMore
    }

    // MARK: - Subscriptions

    private func subscribeToGeneratingState() {
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

    private func subscribeToStopGeneratingTap() {
        viewController.handler.stopGeneratingButtonTappedPublisher
            .sink { [weak self] in
                self?.didPressStopGeneratingButton.send()
            }
            .store(in: &cancellables)
    }

    private func subscribeToAttachmentUsageChanges() {
        $attachmentUsage
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.updateImageButtonVisibility()
            }
            .store(in: &cancellables)
    }

    private func subscribeToCustomizeResponsesTap() {
        viewController.handler.customizeResponsesButtonTappedPublisher
            .sink { [weak self] in
                guard let self else { return }
                self.didPressCustomizeResponsesButton.send()
                self.showCollapsed()
            }
            .store(in: &cancellables)
    }

    private func subscribeToVoiceSearchTap() {
        viewController.handler.microphoneButtonTappedPublisher
            .sink { [weak self] in
                self?.delegate?.unifiedToggleInputDidRequestVoiceSearch()
            }
            .store(in: &cancellables)
    }

    // MARK: - State Reset

    private func updateModelChipVisibility() {
        viewController.isModelChipHidden = hasSubmittedPrompt
    }

    private func syncHasSubmittedPromptToHandler() {
        switchBarHandler.hasSubmittedPrompt = hasSubmittedPrompt
    }

    private func resetSessionState() {
        isNewChatPending = false
        setText("")
        aiChatStatus = .unknown
        aiChatInputBoxVisibility = .unknown
        attachmentUsage = nil
        hasSubmittedPrompt = false
        updateModelChipVisibility()
        syncHasSubmittedPromptToHandler()
        clearAttachments()
    }
}

// MARK: - UnifiedToggleInputViewControllerDelegate

extension UnifiedToggleInputCoordinator: UnifiedToggleInputViewControllerDelegate {

    func unifiedToggleInputVCDidTapWhileCollapsed(_ vc: UnifiedToggleInputViewController) {
        showExpanded(inputMode: inputMode)
    }

    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didSubmitText text: String, mode: TextEntryMode) {
        setText("")

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
            let images = selectedModelSupportsImageUpload
                ? UnifiedToggleInputImageEncoder.encode(viewController.currentAttachments)
                : nil
            let modelId = hasSubmittedPrompt ? nil : persistedModelId
            clearAttachments()
            hasSubmittedPrompt = true
            updateModelChipVisibility()
            syncHasSubmittedPromptToHandler()
            if isOmnibarSession {
                deactivateToOmnibar()
            } else {
                showCollapsed()
            }
            if let userScript = boundUserScript {
                userScript.submitPrompt(text, images: images, modelId: modelId)
            } else {
                delegate?.unifiedToggleInputDidSubmitPrompt(text, modelId: modelId, images: images)
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
}
