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
import PhotosUI
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
    case showOmnibarEditing(expandedHeight: CGFloat)
    case showOmnibarInactive
    case showOmnibarActive
    case hideOmnibarEditing
    case hide
}

// MARK: - Subscription State

struct SubscriptionState {
    let userTier: AIChatUserTier
    let hasActiveSubscription: Bool

    static let free = SubscriptionState(userTier: .free, hasActiveSubscription: false)
}

// MARK: - Coordinator

@MainActor
final class UnifiedToggleInputCoordinator: AIChatInputBoxHandling {

    private static let maxImageAttachments = 3

    // MARK: - AIChatInputBoxHandling

    let didPressFireButton = PassthroughSubject<Void, Never>()
    let didPressNewChatButton = PassthroughSubject<Void, Never>()
    let didSubmitPrompt = PassthroughSubject<String, Never>()
    let didSubmitQuery = PassthroughSubject<String, Never>()
    let didPressStopGeneratingButton = PassthroughSubject<Void, Never>()

    var aiChatStatusPublisher: Published<AIChatStatusValue>.Publisher { $aiChatStatus }
    var aiChatInputBoxVisibilityPublisher: Published<AIChatInputBoxVisibility>.Publisher { $aiChatInputBoxVisibility }

    @Published var aiChatStatus: AIChatStatusValue = .unknown
    @Published var aiChatInputBoxVisibility: AIChatInputBoxVisibility = .unknown

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

    var currentText: String { viewController.text }
    var hasActiveChat: Bool { boundUserScript != nil }
    var switchBarHandler: SwitchBarHandling { viewController.handler }

    // MARK: - Model Picker

    private let modelsService: AIChatModelsProviding
    private var preferences: AIChatPreferencesPersisting
    private let subscriptionManager: any SubscriptionManager
    var models: [AIChatModel] = []
    private var modelsFetchTask: Task<Void, Never>?
    private(set) var hasSubmittedPrompt = false
    private(set) var subscriptionState: SubscriptionState = .free

    var persistedModelId: String? {
        let id = preferences.selectedModelId
        if let id, !models.isEmpty {
            if let model = models.first(where: { $0.id == id }) {
                return model.entityHasAccess ? id : firstAccessibleModelId
            }
            return firstAccessibleModelId
        }
        return id ?? firstAccessibleModelId
    }

    var currentModelId: String? {
        preferences.selectedModelId
    }

    var selectedModelSupportsImageUpload: Bool {
        guard !models.isEmpty else { return false }
        return models.first(where: { $0.id == persistedModelId })?.supportsImageUpload ?? false
    }

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

    private var firstAccessibleModelId: String? {
        models.first(where: { $0.entityHasAccess })?.id
    }

    private var cancellables = Set<AnyCancellable>()

    private weak var boundUserScript: AIChatUserScript?
    private var boundUserScriptIdentifier: ObjectIdentifier?

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
        modelsService: AIChatModelsProviding = AIChatModelsService(),
        preferences: AIChatPreferencesPersisting = AIChatPreferencesPersistor(),
        subscriptionManager: any SubscriptionManager = AppDependencyProvider.shared.subscriptionManager
    ) {
        self.isToggleEnabled = isToggleEnabled
        self.modelsService = modelsService
        self.preferences = preferences
        self.subscriptionManager = subscriptionManager
        viewController = UnifiedToggleInputViewController(isToggleEnabled: isToggleEnabled)
        contentViewController = UnifiedInputContentContainerViewController(switchBarHandler: viewController.handler)
        floatingSubmitViewController = UnifiedToggleInputFloatingSubmitViewController()
        viewController.delegate = self
        subscribeToGeneratingState()
        subscribeToStopGeneratingTap()

        if let cachedLabel = preferences.selectedModelShortName {
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
        syncChipVisibility(hasExistingChat: hasExistingChat)
        if hadPreviousScript {
            resetInputState()
        }
    }

    private func syncChipVisibility(hasExistingChat: Bool) {
        let shouldHide = hasExistingChat
        guard hasSubmittedPrompt != shouldHide else { return }
        hasSubmittedPrompt = shouldHide
        updateModelChipVisibility()
    }

    func unbind() {
        boundUserScript?.inputBoxHandler = nil
        boundUserScript = nil
        boundUserScriptIdentifier = nil
        hasSubmittedPrompt = false
        updateModelChipVisibility()
        clearAttachments()
        resetSessionState()
    }

    // MARK: - AI Tab Display State Management

    func showCollapsed() {
        displayState = .aiTab(.collapsed)
        inputMode = .aiChat
        isInputVisibleForKeyboard = true

        let renderState = computeRenderState()

        viewController.apply(renderState.viewConfig, animated: false)
        viewController.deactivateInput()
        intentSubject.send(.showCollapsed)
    }

    func showExpanded(prefilledText: String? = nil, inputMode: TextEntryMode = .aiChat) {
        displayState = .aiTab(.expanded)
        self.inputMode = inputMode
        isInputVisibleForKeyboard = true

        let renderState = computeRenderState()

        viewController.apply(renderState.viewConfig, animated: false)
        fetchModels()

        if let prefilledText, !prefilledText.isEmpty {
            viewController.text = prefilledText
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
        displayState = .hidden
        isInputVisibleForKeyboard = true

        let renderState = computeRenderState()
        viewController.apply(renderState.viewConfig, animated: false)
        viewController.deactivateInput()
        contentViewController.setHeaderDisplayMode(renderState.headerDisplayMode)
        intentSubject.send(.hide)
    }

    // MARK: - Omnibar Editing State Management

    func activateFromOmnibar(prefilledText: String? = nil, inputMode: TextEntryMode = .search, cardPosition: UnifiedToggleInputCardPosition = .top) {
        let effectiveInputMode = isToggleEnabled ? inputMode : .search
        displayState = .omnibar(.active)
        self.inputMode = effectiveInputMode
        self.cardPosition = cardPosition
        isInputVisibleForKeyboard = true
        hasSubmittedPrompt = false
        updateModelChipVisibility()

        let renderState = computeRenderState()
        viewController.apply(renderState.viewConfig, animated: false)
        fetchModels()

        if let text = prefilledText, !text.isEmpty {
            viewController.text = text
            textState = .prefilledSelected
        }

        contentViewController.setHeaderDisplayMode(renderState.headerDisplayMode)
        let height = omnibarEditingHeight()
        intentSubject.send(.showOmnibarEditing(expandedHeight: height))

        DispatchQueue.main.async { [weak self] in
            guard let self, case .omnibar(.active) = displayState else { return }
            viewController.activateInput()
            if textState == .prefilledSelected {
                viewController.selectAllText()
            }
        }
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

    func updateInputMode(_ mode: TextEntryMode, animated: Bool) {
        let effectiveMode: TextEntryMode = (!isToggleEnabled && isOmnibarSession) ? .search : mode
        inputMode = effectiveMode
        viewController.setInputMode(effectiveMode, animated: animated)
        modeChangeSubject.send(effectiveMode)
        if effectiveMode == .search {
            clearAttachments()
        }
    }

    func updateVoiceSearchAvailability(_ enabled: Bool) {
        viewController.isVoiceSearchAvailable = enabled
    }

    func activateInput() {
        viewController.activateInput()
    }

    func stopGeneratingButtonTapped() {
        viewController.handler.stopGeneratingButtonTapped()
    }

    func syncInputModeFromExternalSource(_ mode: TextEntryMode) {
        let effectiveMode: TextEntryMode = (!isToggleEnabled && isOmnibarSession) ? .search : mode
        let didModeChange = inputMode != effectiveMode
        inputMode = effectiveMode
        if didModeChange || effectiveMode != mode {
            viewController.setInputMode(effectiveMode, animated: false)
        }
        if didModeChange {
            modeChangeSubject.send(effectiveMode)
        }
    }

    func clearText() {
        viewController.text = ""
        textState = .empty
    }

    func handleExternalQuerySubmission() {
        switch displayState {
        case .omnibar:
            deactivateToOmnibar()
        case .aiTab:
            hide()
        case .hidden:
            break
        }
    }

    func handleExternalPromptSubmission() {
        switch displayState {
        case .omnibar:
            deactivateToOmnibar()
        case .aiTab:
            showCollapsed()
        case .hidden:
            break
        }
    }

    func deactivateToOmnibar() {
        guard isOmnibarSession else { return }
        displayState = .hidden
        cardPosition = .bottom
        isInputVisibleForKeyboard = true
        viewController.text = ""
        textState = .empty
        clearAttachments()

        let renderState = computeRenderState()
        viewController.apply(renderState.viewConfig, animated: false)
        viewController.deactivateInput()

        contentViewController.setHeaderDisplayMode(renderState.headerDisplayMode)
        intentSubject.send(.hideOmnibarEditing)
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

    func updateOmnibarInputVisibility(_ isInputVisible: Bool) {
        isInputVisibleForKeyboard = isInputVisible
        let isAITabSearch = displayState == .aiTab(.expanded) && inputMode == .search

        switch (displayState, isInputVisible) {
        case (.omnibar(.active), false):
            displayState = .omnibar(.inactive)
            let renderState = computeRenderState()
            viewController.apply(renderState.viewConfig, animated: false)
            contentViewController.setHeaderDisplayMode(renderState.headerDisplayMode)
            intentSubject.send(.showOmnibarInactive)
        case (.omnibar(.inactive), true):
            displayState = .omnibar(.active)
            let renderState = computeRenderState()
            viewController.apply(renderState.viewConfig, animated: false)
            contentViewController.setHeaderDisplayMode(renderState.headerDisplayMode)
            intentSubject.send(.showOmnibarActive)
        case (.aiTab(.expanded), false) where isAITabSearch:
            let renderState = computeRenderState(isOnAITab: true)
            viewController.apply(renderState.viewConfig, animated: false)
            contentViewController.setHeaderDisplayMode(renderState.headerDisplayMode)
        case (.aiTab(.expanded), true) where isAITabSearch:
            let renderState = computeRenderState(isOnAITab: true)
            viewController.apply(renderState.viewConfig, animated: false)
            contentViewController.setHeaderDisplayMode(renderState.headerDisplayMode)
        default:
            break
        }
    }

    func dismissOmnibarKeyboard() {
        switch displayState {
        case .omnibar(.active), .aiTab(.expanded):
            viewController.deactivateInput()
        default:
            return
        }
    }

    func applyContentHeaderFromRenderState(isOnAITab: Bool) {
        let renderState = computeRenderState(isOnAITab: isOnAITab)
        contentViewController.setHeaderDisplayMode(renderState.headerDisplayMode)
    }

    func syncContentInputMode(_ mode: TextEntryMode, animated: Bool = true) {
        contentViewController.setInputMode(mode, animated: animated)
    }

    // MARK: - Render State

    func computeRenderState(isOnAITab: Bool = false) -> UTIRenderState {
        let isExpanded: Bool
        let isInputVisible: Bool
        let isContentVisible: Bool
        let headerDisplayMode: UnifiedInputContentContainerViewController.HeaderDisplayMode
        let inactiveAppearance: Bool

        switch displayState {
        case .hidden:
            isExpanded = false
            isInputVisible = false
            isContentVisible = false
            headerDisplayMode = .hidden
            inactiveAppearance = false

        case .aiTab(.collapsed):
            isExpanded = false
            isInputVisible = true
            isContentVisible = false
            headerDisplayMode = .hidden
            inactiveAppearance = false

        case .aiTab(.expanded):
            isExpanded = true
            isInputVisible = true
            let isAIChatOnAITab = isOnAITab && inputMode == .aiChat
            isContentVisible = !isAIChatOnAITab
            let isSearchOnAITab = isOnAITab && inputMode == .search
            let isSearchKeyboardHidden = isSearchOnAITab && !isInputVisibleForKeyboard
            headerDisplayMode = isSearchOnAITab && isContentVisible
                ? (isSearchKeyboardHidden ? .inactive : .active)
                : .hidden
            inactiveAppearance = isSearchKeyboardHidden

        case .omnibar(.active):
            isExpanded = true
            isInputVisible = true
            isContentVisible = true
            headerDisplayMode = .active
            inactiveAppearance = false

        case .omnibar(.inactive):
            isExpanded = true
            isInputVisible = true
            isContentVisible = true
            headerDisplayMode = .inactive
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
            showsDismissButton: cardPosition == .top && isOmnibarSession,
            isToolbarSubmitHidden: cardPosition == .top && isOmnibarSession,
            inactiveAppearance: inactiveAppearance,
            isFloatingSubmitVisible: isFloatingSubmitVisible,
            headerDisplayMode: headerDisplayMode,
            contentInputMode: inputMode,
            inputMode: inputMode
        )
    }

    // MARK: - Model Picker Actions

    func fetchModels() {
        modelsFetchTask?.cancel()
        modelsFetchTask = Task { [weak self] in
            guard let self else { return }
            let state = await self.resolveSubscriptionState()
            guard !Task.isCancelled else { return }
            self.subscriptionState = state
            do {
                let remoteModels = try await modelsService.fetchModels()
                guard !Task.isCancelled else { return }
                self.models = Self.resolveModels(from: remoteModels, userTier: state.userTier)
                self.clearStaleModelSelectionIfNeeded()
                self.updateModelChipLabel()
                self.updateImageButtonVisibility()
            } catch {
                os_log(.error, "Failed to fetch models: %{public}@", error.localizedDescription)
            }
        }
    }

    func startNewChat() {
        hasSubmittedPrompt = false
        updateModelChipVisibility()
        clearAttachments()
    }

    func updateSelectedModel(_ modelId: String) {
        preferences.selectedModelId = modelId
        preferences.selectedModelShortName = models.first(where: { $0.id == modelId })?.shortName
        updateModelChipLabel()
        updateImageButtonVisibility()
    }

    private func buildModelMenuDescription() -> UnifiedToggleInputModelMenu {
        UnifiedToggleInputModelMenu.build(
            models: models,
            selectedId: persistedModelId,
            isBottomAnchored: viewController.cardPosition == .bottom,
            hasActiveSubscription: subscriptionState.hasActiveSubscription,
            advancedSectionTitle: subscriptionState.hasActiveSubscription
                ? UserText.aiChatAdvancedModelsSectionHeader
                : UserText.aiChatAdvancedModelsMenuTitle,
            basicSectionTitle: UserText.aiChatBasicModelsSectionHeader
        )
    }

    private func buildModelPickerMenu() -> UIMenu {
        let description = buildModelMenuDescription()
        let modelLookup = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })

        let uiSections: [UIMenu] = description.sections.map { section in
            let actions = section.items.map { item -> UIAction in
                let model = modelLookup[item.modelId]
                return UIAction(
                    title: item.name,
                    image: model?.menuIcon,
                    attributes: item.isDisabled ? .disabled : [],
                    state: item.isSelected ? .on : .off
                ) { [weak self] _ in
                    self?.updateSelectedModel(item.modelId)
                }
            }

            var options: UIMenu.Options = .displayInline
            if !section.items.contains(where: { $0.isDisabled }) {
                options.insert(.singleSelection)
            }

            return UIMenu(title: section.title, options: options, children: actions)
        }

        return UIMenu(children: uiSections)
    }

    private func updateModelChipLabel() {
        let selectedId = persistedModelId
        let shortName = models.first(where: { $0.id == selectedId })?.shortName
        if let shortName {
            viewController.modelName = shortName
            preferences.selectedModelShortName = shortName
        }
        viewController.modelPickerMenu = models.isEmpty ? nil : buildModelPickerMenu()
    }

    // MARK: - Model Resolution

    static func resolveModels(from remoteModels: [AIChatRemoteModel], userTier: AIChatUserTier) -> [AIChatModel] {
        remoteModels.map { remote in
            if remote.accessTier.isEmpty {
                return AIChatModel(
                    id: remote.id,
                    name: remote.name,
                    shortName: remote.modelShortName,
                    provider: .from(id: remote.id, providerString: remote.provider),
                    supportsImageUpload: remote.supportsImageUpload,
                    supportedImageFormats: remote.supportsImageUpload ? ["png", "jpeg", "webp"] : [],
                    entityHasAccess: remote.entityHasAccess,
                    accessTier: remote.accessTier
                )
            }
            return AIChatModel(remoteModel: remote, userTier: userTier)
        }
    }

    // MARK: - Subscription Resolution

    nonisolated private func resolveSubscriptionState() async -> SubscriptionState {
        do {
            let subscription = try await subscriptionManager.getSubscription(cachePolicy: .cacheFirst)
            guard subscription.isActive, let tier = subscription.tier else {
                return .free
            }
            let userTier: AIChatUserTier
            switch tier {
            case .plus: userTier = .plus
            case .pro: userTier = .pro
            }
            return SubscriptionState(userTier: userTier, hasActiveSubscription: true)
        } catch {
            return .free
        }
    }

    // MARK: - Stale Selection Clearing

    private func clearStaleModelSelectionIfNeeded() {
        guard let selectedId = preferences.selectedModelId, !models.isEmpty else { return }

        let selectedModel = models.first(where: { $0.id == selectedId })
        let isStale = selectedModel == nil || selectedModel?.entityHasAccess == false

        if isStale {
            preferences.selectedModelId = nil
            preferences.selectedModelShortName = nil
        }
    }

    // MARK: - Image Attachments

    func presentImagePicker() {
        let remaining = Self.maxImageAttachments - viewController.currentAttachments.count
        guard remaining > 0 else { return }
        guard let scene = viewController.view.window?.windowScene,
              let root = scene.keyWindow?.rootViewController else { return }
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = remaining
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        root.present(picker, animated: true)
    }

    func addImageAttachment(image: UIImage, fileName: String) {
        guard !viewController.isAttachmentsFull else { return }
        let attachment = AIChatImageAttachment(image: image, fileName: fileName)
        viewController.addAttachment(attachment)
    }

    func removeAttachment(id: UUID) {
        viewController.removeAttachment(id: id)
    }

    func clearAttachments() {
        viewController.removeAllAttachments()
    }

    func updateImageButtonVisibility() {
        let supportsImages = selectedModelSupportsImageUpload
        viewController.isImageButtonHidden = !supportsImages
        if !supportsImages {
            clearAttachments()
        }
    }

    // MARK: - Private

    private func subscribeToGeneratingState() {
        $aiChatStatus
            .map { status in
                status == .loading || status == .streaming || status == .startStreamNewPrompt
            }
            .removeDuplicates()
            .sink { [weak self] isGenerating in
                guard let self else { return }
                self.viewController.isGenerating = isGenerating
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

    private func updateModelChipVisibility() {
        viewController.isModelChipHidden = hasSubmittedPrompt
    }

    private func resetSessionState() {
        viewController.text = ""
        textState = .empty
        aiChatStatus = .unknown
        aiChatInputBoxVisibility = .unknown
    }

    private func resetInputState() {
        resetSessionState()
    }
}

// MARK: - UnifiedToggleInputViewControllerDelegate

extension UnifiedToggleInputCoordinator: UnifiedToggleInputViewControllerDelegate {

    func unifiedToggleInputVCDidTapWhileCollapsed(_ vc: UnifiedToggleInputViewController) {
        showExpanded(inputMode: inputMode)
    }

    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didSubmitText text: String, mode: TextEntryMode) {
        vc.text = ""
        textState = .empty

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
            let images = UnifiedToggleInputImageEncoder.encode(viewController.currentAttachments)
            let modelId = hasSubmittedPrompt ? nil : persistedModelId
            clearAttachments()
            hasSubmittedPrompt = true
            updateModelChipVisibility()
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
        textState = text.isEmpty ? .empty : .userTyped
        textChangeSubject.send(text)
    }

    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didChangeMode mode: TextEntryMode) {
        updateInputMode(mode, animated: false)
    }

    func unifiedToggleInputVCDidTapVoice(_ vc: UnifiedToggleInputViewController) {
        delegate?.unifiedToggleInputDidRequestVoiceSearch()
    }

    func unifiedToggleInputVCDidTapSearchGoTo(_ vc: UnifiedToggleInputViewController) {
        showExpanded(inputMode: .search)
    }

    func unifiedToggleInputVCDidTapDismiss(_ vc: UnifiedToggleInputViewController) {
        if case .aiTab = displayState {
            showCollapsed()
        } else {
            deactivateToOmnibar()
        }
    }

    func unifiedToggleInputVCDidTapAttach(_ vc: UnifiedToggleInputViewController) {
        presentImagePicker()
    }

    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didRemoveAttachment id: UUID) {
        removeAttachment(id: id)
    }

    func unifiedToggleInputVCDidChangeAttachments(_ vc: UnifiedToggleInputViewController) {
        attachmentsChangeSubject.send()
    }
}

// MARK: - PHPickerViewControllerDelegate

extension UnifiedToggleInputCoordinator: PHPickerViewControllerDelegate {

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        for result in results {
            let provider = result.itemProvider
            guard provider.canLoadObject(ofClass: UIImage.self) else { continue }
            provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                guard let image = object as? UIImage else { return }
                let fileName = provider.suggestedName ?? "image"
                DispatchQueue.main.async {
                    self?.addImageAttachment(image: image, fileName: fileName)
                }
            }
        }
    }
}
