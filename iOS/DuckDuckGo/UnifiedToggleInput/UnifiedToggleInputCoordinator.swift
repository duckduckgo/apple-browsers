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
    case inline(InlineState)

    enum AITabState: Equatable {
        case collapsed
        case expanded
    }

    enum InlineState: Equatable {
        case active
        case inactive
    }
}

enum UnifiedToggleInputIntent: Equatable {
    case showCollapsed
    case showExpanded
    case showInlineEditing(expandedHeight: CGFloat)
    case showInlineInactive
    case showInlineActive
    case hideInlineEditing
    case hide
}

// MARK: - Coordinator

/// Pure state machine managing the unified toggle input lifecycle and FE bridge via `AIChatInputBoxHandling`.
/// Drives the view controller through `UnifiedToggleInputViewControllerDelegate` and emits
/// `UnifiedToggleInputIntent`s for MainVC to manage container-level layout (visibility, keyboard constraints).
///
/// Does not access the view hierarchy directly — all UI manipulation goes through the view controller.
@MainActor
final class UnifiedToggleInputCoordinator: AIChatInputBoxHandling {

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

    /// The managed view controller. Access for installation only — query coordinator properties for state.
    private(set) var viewController: UnifiedToggleInputViewController
    private(set) var contentViewController: UnifiedInputContentContainerViewController
    weak var delegate: UnifiedToggleInputDelegate?

    private(set) var isToggleEnabled: Bool
    private(set) var displayState: UnifiedToggleInputDisplayState = .hidden
    private(set) var textState: InputTextState = .empty
    private(set) var inputMode: TextEntryMode = .aiChat

    var currentText: String { viewController.text }
    var hasActiveChat: Bool { boundUserScript != nil }
    var switchBarHandler: SwitchBarHandling { viewController.handler }

    // MARK: - Model Picker

    private let modelsService: AIChatModelsProviding
    private var preferences: AIChatPreferencesPersisting
    var models: [AIChatModel] = []
    private var modelsFetchTask: Task<Void, Never>?
    private(set) var hasSubmittedPrompt = false

    var persistedModelId: String {
        preferences.selectedModelId ?? models.first(where: { $0.entityHasAccess })?.id ?? ""
    }

    var selectedModelSupportsImageUpload: Bool {
        guard !models.isEmpty else { return true }
        return models.first(where: { $0.id == persistedModelId })?.supportsImageUpload ?? true
    }

    var isInlineEditingSession: Bool {
        if case .inline = displayState { return true }
        return false
    }

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

    // MARK: - Initialization

    init(
        isToggleEnabled: Bool,
        modelsService: AIChatModelsProviding = AIChatModelsService(),
        preferences: AIChatPreferencesPersisting = AIChatPreferencesPersistor()
    ) {
        self.isToggleEnabled = isToggleEnabled
        self.modelsService = modelsService
        self.preferences = preferences
        viewController = UnifiedToggleInputViewController(isToggleEnabled: isToggleEnabled)
        contentViewController = UnifiedInputContentContainerViewController(switchBarHandler: viewController.handler)
        viewController.delegate = self
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
        resetSessionState()
    }

    // MARK: - AI Tab Display State Management

    func showCollapsed() {
        displayState = .aiTab(.collapsed)
        viewController.setExpanded(false, animated: false)
        viewController.deactivateInput()
        intentSubject.send(.showCollapsed)
    }

    func showExpanded(prefilledText: String? = nil, inputMode: TextEntryMode = .aiChat) {
        displayState = .aiTab(.expanded)
        self.inputMode = inputMode
        viewController.setInputMode(inputMode, animated: false)
        fetchModels()

        if let prefilledText, !prefilledText.isEmpty {
            viewController.text = prefilledText
            textState = .prefilledSelected
        }

        viewController.setExpanded(true, animated: false)
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
        viewController.deactivateInput()
        viewController.setExpanded(false, animated: false)
        contentViewController.setInlineHeaderDisplayMode(.hidden)
        intentSubject.send(.hide)
    }

    // MARK: - Inline Editing State Management

    func activateInlineEditing(prefilledText: String? = nil, inputMode: TextEntryMode = .search, cardPosition: UnifiedToggleInputCardPosition = .top) {
        let effectiveInputMode = isToggleEnabled ? inputMode : .search
        displayState = .inline(.active)
        self.inputMode = effectiveInputMode
        hasSubmittedPrompt = false
        updateModelChipVisibility()
        fetchModels()
        viewController.cardPosition = cardPosition
        viewController.usesInlineEditingMargins = (cardPosition == .top)
        viewController.isTopBarPosition = (cardPosition == .top)
        viewController.setInputMode(effectiveInputMode, animated: false)
        viewController.showsDismissButton = (cardPosition == .top)

        if let text = prefilledText, !text.isEmpty {
            viewController.text = text
            textState = .prefilledSelected
        }

        viewController.isToolbarSubmitHidden = (cardPosition == .top)

        viewController.setExpanded(true, animated: false)
        contentViewController.setInlineHeaderDisplayMode(.active)
        let height = inlineEditingHeight()
        intentSubject.send(.showInlineEditing(expandedHeight: height))

        DispatchQueue.main.async { [weak self] in
            guard let self, case .inline(.active) = displayState else { return }
            viewController.activateInput()
            if textState == .prefilledSelected {
                viewController.selectAllText()
            }
        }
    }

    func inlineEditingHeight() -> CGFloat {
        let screenWidth = viewController.view.window?.bounds.width ?? viewController.view.bounds.width
        let height = viewController.view.systemLayoutSizeFitting(
            CGSize(width: screenWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        return height
    }

    func updateInputMode(_ mode: TextEntryMode, animated: Bool) {
        let effectiveMode: TextEntryMode = isToggleEnabled ? mode : .search
        inputMode = effectiveMode
        viewController.setInputMode(effectiveMode, animated: animated)
        modeChangeSubject.send(effectiveMode)
    }

    func updateVoiceSearchAvailability(_ enabled: Bool) {
        viewController.isVoiceSearchAvailable = enabled
    }

    func activateInput() {
        viewController.activateInput()
    }

    func syncInputModeFromExternalSource(_ mode: TextEntryMode) {
        let effectiveMode: TextEntryMode = isToggleEnabled ? mode : .search
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
        case .inline:
            deactivateInlineEditing()
        case .aiTab:
            hide()
        case .hidden:
            break
        }
    }

    func handleExternalPromptSubmission() {
        switch displayState {
        case .inline:
            deactivateInlineEditing()
        case .aiTab:
            showCollapsed()
        case .hidden:
            break
        }
    }

    func deactivateInlineEditing() {
        guard isInlineEditingSession else { return }
        displayState = .hidden
        viewController.showsDismissButton = false
        viewController.usesInlineEditingMargins = false
        viewController.isTopBarPosition = false
        viewController.isToolbarSubmitHidden = false
        viewController.cardPosition = .bottom
        viewController.setInactiveCardAppearance(false)
        viewController.text = ""
        textState = .empty
        viewController.deactivateInput()
        viewController.setExpanded(false, animated: false)
        contentViewController.setInlineHeaderDisplayMode(.hidden)
        intentSubject.send(.hideInlineEditing)
    }

    func updateToggleEnabled(_ enabled: Bool) {
        guard enabled != isToggleEnabled else { return }
        isToggleEnabled = enabled
        viewController.updateToggleEnabled(enabled)
        if !enabled, isInlineEditingSession {
            inputMode = .search
            viewController.setInputMode(.search, animated: false)
            modeChangeSubject.send(.search)
        }
    }

    func updateInlineEditingInputVisibility(_ isInputVisible: Bool) {
        switch (displayState, isInputVisible) {
        case (.inline(.active), false):
            displayState = .inline(.inactive)
            if viewController.cardPosition == .bottom {
                viewController.setInactiveCardAppearance(true)
            }
            contentViewController.setInlineHeaderDisplayMode(.inactive)
            intentSubject.send(.showInlineInactive)
        case (.inline(.inactive), true):
            displayState = .inline(.active)
            if viewController.cardPosition == .bottom {
                viewController.setInactiveCardAppearance(false)
            }
            contentViewController.setInlineHeaderDisplayMode(.active)
            intentSubject.send(.showInlineActive)
        default:
            break
        }
    }

    func dismissInlineKeyboard() {
        guard case .inline(.active) = displayState else { return }
        viewController.deactivateInput()
    }

    func updateContentHeaderForAITab(shouldOverlay: Bool) {
        contentViewController.setInlineHeaderDisplayMode(shouldOverlay ? .active : .hidden)
    }

    func syncContentInputMode(_ mode: TextEntryMode, animated: Bool = true) {
        contentViewController.setInputMode(mode, animated: animated)
    }

    // MARK: - Model Picker Actions

    func fetchModels() {
        modelsFetchTask?.cancel()
        modelsFetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let remoteModels = try await modelsService.fetchModels()
                guard !Task.isCancelled else { return }
                self.models = remoteModels.map { AIChatModel(remoteModel: $0) }
                self.updateModelChipLabel()
            } catch {
                os_log(.error, "Failed to fetch models: %{public}@", error.localizedDescription)
            }
        }
    }

    func startNewChat() {
        hasSubmittedPrompt = false
        updateModelChipVisibility()
    }

    func updateSelectedModel(_ modelId: String) {
        preferences.selectedModelId = modelId
        updateModelChipLabel()
    }

    private func buildModelMenuDescription() -> UnifiedToggleInputModelMenu {
        UnifiedToggleInputModelMenu.build(
            models: models,
            selectedId: persistedModelId,
            isBottomAnchored: viewController.cardPosition == .bottom,
            advancedSectionTitle: UserText.aiChatAdvancedModelsMenuTitle
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
        let name = models.first(where: { $0.id == selectedId })?.name
        if let name {
            viewController.modelName = name
        }
        viewController.modelPickerMenu = models.isEmpty ? nil : buildModelPickerMenu()
    }

    // MARK: - Private

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
            } else if isInlineEditingSession {
                deactivateInlineEditing()
            }
            delegate?.unifiedToggleInputDidSubmitQuery(text)
            didSubmitQuery.send(text)
        case .aiChat:
            hasSubmittedPrompt = true
            updateModelChipVisibility()
            if isInlineEditingSession {
                deactivateInlineEditing()
            } else {
                showCollapsed()
            }
            if boundUserScript != nil {
                didSubmitPrompt.send(text)
            } else {
                delegate?.unifiedToggleInputDidSubmitPrompt(text, modelId: persistedModelId)
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

    func unifiedToggleInputVCDidTapDismiss(_ vc: UnifiedToggleInputViewController) {
        deactivateInlineEditing()
    }
}
