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
    case showOmnibarEditing(expandedHeight: CGFloat, pendingExpandedHeight: CGFloat? = nil)
    case showOmnibarInactive
    case showOmnibarActive
    case hideOmnibarEditing
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

private let utiLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.duckduckgo", category: "UTI")

// MARK: - Coordinator

@MainActor
final class UnifiedToggleInputCoordinator: NSObject, AIChatInputBoxHandling {

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
        utiLog.debug("Coordinator.init - isToggleEnabled: \(isToggleEnabled, privacy: .public)")
        self.isToggleEnabled = isToggleEnabled
        self.modelStore = UTIModelStore(
            modelsService: modelsService,
            preferences: preferences,
            subscriptionManager: subscriptionManager
        )
        viewController = UnifiedToggleInputViewController(isToggleEnabled: isToggleEnabled)
        contentViewController = UnifiedInputContentContainerViewController(switchBarHandler: viewController.handler)
        floatingSubmitViewController = UnifiedToggleInputFloatingSubmitViewController()
        super.init()
        viewController.delegate = self
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
            utiLog.debug("Coordinator.init 🔀 found cachedLabel=\(cachedLabel, privacy: .public)")
            viewController.modelName = cachedLabel
        } else {
            utiLog.debug("Coordinator.init 🔀 no cached model short name")
        }
    }

    // MARK: - Tab Binding

    func bindToTab(_ userScript: AIChatUserScript, hasExistingChat: Bool = false) {
        utiLog.debug("Coordinator.bindToTab - hasExistingChat: \(hasExistingChat, privacy: .public)")
        let newIdentifier = ObjectIdentifier(userScript)
        if boundUserScriptIdentifier == newIdentifier {
            utiLog.debug("Coordinator.bindToTab 🔀 sameIdentifier=true, rebinding existing script")
            boundUserScript = userScript
            userScript.inputBoxHandler = self
            syncChipVisibility(hasExistingChat: hasExistingChat)
            return
        }
        let hadPreviousScript = boundUserScriptIdentifier != nil
        utiLog.debug("Coordinator.bindToTab 🔀 sameIdentifier=false, hadPreviousScript=\(hadPreviousScript, privacy: .public)")
        boundUserScript?.inputBoxHandler = nil
        boundUserScript = userScript
        boundUserScriptIdentifier = newIdentifier
        userScript.inputBoxHandler = self
        if hadPreviousScript {
            utiLog.debug("Coordinator.bindToTab → calling resetSessionState (had previous script)")
            resetSessionState()
        }
        syncChipVisibility(hasExistingChat: hasExistingChat)
    }

    func unbind() {
        utiLog.debug("Coordinator.unbind")
        boundUserScript?.inputBoxHandler = nil
        boundUserScript = nil
        boundUserScriptIdentifier = nil
        resetSessionState()
    }

    private var isNewChatPending = false

    private func syncChipVisibility(hasExistingChat: Bool) {
        utiLog.debug("Coordinator.syncChipVisibility - hasExistingChat: \(hasExistingChat, privacy: .public), isNewChatPending: \(self.isNewChatPending, privacy: .public), hasSubmittedPrompt: \(self.hasSubmittedPrompt, privacy: .public)")
        if isNewChatPending && hasExistingChat {
            utiLog.debug("Coordinator.syncChipVisibility ↩️ guard: isNewChatPending=true && hasExistingChat=true, skipping update")
            return
        }
        isNewChatPending = false
        let shouldHide = hasExistingChat || hasSubmittedPrompt
        guard hasSubmittedPrompt != shouldHide else {
            utiLog.debug("Coordinator.syncChipVisibility ↩️ guard: hasSubmittedPrompt already equals shouldHide=\(shouldHide, privacy: .public)")
            return
        }
        utiLog.debug("Coordinator.syncChipVisibility 🔀 updating hasSubmittedPrompt=\(shouldHide, privacy: .public)")
        hasSubmittedPrompt = shouldHide
        utiLog.debug("Coordinator.syncChipVisibility → calling updateModelChipVisibility + syncHasSubmittedPromptToHandler")
        updateModelChipVisibility()
        syncHasSubmittedPromptToHandler()
    }

    // MARK: - AI Tab State

    func showCollapsed() {
        let oldDisplayState = self.displayState
        displayState = .aiTab(.collapsed)
        utiLog.debug("Coordinator.showCollapsed - displayState: \(String(describing: oldDisplayState), privacy: .public) → \(String(describing: self.displayState), privacy: .public)")
        inputMode = .aiChat
        isInputVisibleForKeyboard = true

        let renderState = computeRenderState()

        utiLog.debug("Coordinator.showCollapsed → viewController.apply + deactivateInput")
        viewController.apply(renderState.viewConfig, animated: false)
        viewController.deactivateInput()
        viewController.isCustomizeResponsesButtonHidden = false
        utiLog.debug("Coordinator.showCollapsed → firing intentSubject(.showCollapsed)")
        intentSubject.send(.showCollapsed)
    }

    func showExpanded(prefilledText: String? = nil, inputMode: TextEntryMode = .aiChat) {
        let oldDisplayState = self.displayState
        displayState = .aiTab(.expanded)
        self.inputMode = inputMode
        utiLog.debug("Coordinator.showExpanded - displayState: \(String(describing: oldDisplayState), privacy: .public) → \(String(describing: self.displayState), privacy: .public), inputMode: \(String(describing: inputMode), privacy: .public)")
        isInputVisibleForKeyboard = true

        let renderState = computeRenderState()

        utiLog.debug("Coordinator.showExpanded → viewController.apply")
        viewController.apply(renderState.viewConfig, animated: false)
        viewController.isCustomizeResponsesButtonHidden = false
        utiLog.debug("Coordinator.showExpanded → fetchModels")
        fetchModels()

        if let prefilledText, !prefilledText.isEmpty {
            utiLog.debug("Coordinator.showExpanded 🔀 prefilledText is non-empty, setting text + prefilledSelected")
            setText(prefilledText)
            textState = .prefilledSelected
        } else {
            utiLog.debug("Coordinator.showExpanded 🔀 no prefilled text")
        }

        utiLog.debug("Coordinator.showExpanded → firing intentSubject(.showExpanded)")
        intentSubject.send(.showExpanded)
        DispatchQueue.main.async { [weak self] in
            guard let self, case .aiTab(.expanded) = self.displayState else {
                utiLog.debug("Coordinator.showExpanded ↩️ guard: self is nil or displayState is no longer .aiTab(.expanded)")
                return
            }
            utiLog.debug("Coordinator.showExpanded → viewController.activateInput (first attempt)")
            self.viewController.activateInput()
            if !self.viewController.isInputFirstResponder {
                utiLog.debug("Coordinator.showExpanded 🔀 isInputFirstResponder=false, scheduling retry")
                DispatchQueue.main.async { [weak self] in
                    guard let self, case .aiTab(.expanded) = self.displayState else {
                        utiLog.debug("Coordinator.showExpanded ↩️ guard: self is nil or displayState changed on retry")
                        return
                    }
                    utiLog.debug("Coordinator.showExpanded → viewController.activateInput (retry)")
                    self.viewController.activateInput()
                }
            } else {
                utiLog.debug("Coordinator.showExpanded 🔀 isInputFirstResponder=true, no retry needed")
            }
            if self.textState == .prefilledSelected {
                utiLog.debug("Coordinator.showExpanded 🔀 textState=prefilledSelected → selectAllText")
                self.viewController.selectAllText()
            }
        }
    }

    func hide() {
        let oldDisplayState = self.displayState
        displayState = .hidden
        utiLog.debug("Coordinator.hide - displayState: \(String(describing: oldDisplayState), privacy: .public) → \(String(describing: self.displayState), privacy: .public)")
        isInputVisibleForKeyboard = true

        let renderState = computeRenderState()
        utiLog.debug("Coordinator.hide → viewController.apply + deactivateInput")
        viewController.apply(renderState.viewConfig, animated: false)
        viewController.deactivateInput()
        viewController.isCustomizeResponsesButtonHidden = true
        utiLog.debug("Coordinator.hide → contentViewController.setDismissButtonVisible(\(renderState.isContentVisible, privacy: .public))")
        contentViewController.setDismissButtonVisible(renderState.isContentVisible)
        utiLog.debug("Coordinator.hide → firing intentSubject(.hide)")
        intentSubject.send(.hide)
    }

    // MARK: - Omnibar State

    func activateFromOmnibar(prefilledText: String? = nil, inputMode: TextEntryMode = .search, cardPosition: UnifiedToggleInputCardPosition = .top) {
        let oldDisplayState = self.displayState
        let effectiveInputMode = isToggleEnabled ? inputMode : .search
        displayState = .omnibar(.active)
        self.inputMode = effectiveInputMode
        self.cardPosition = cardPosition
        utiLog.debug("Coordinator.activateFromOmnibar - displayState: \(String(describing: oldDisplayState), privacy: .public) → \(String(describing: self.displayState), privacy: .public), inputMode: \(String(describing: effectiveInputMode), privacy: .public), cardPosition: \(String(describing: cardPosition), privacy: .public), isToggleEnabled: \(self.isToggleEnabled, privacy: .public)")
        viewController.handler.hidesVoiceButton = false
        isInputVisibleForKeyboard = true
        hasSubmittedPrompt = false
        updateModelChipVisibility()
        syncHasSubmittedPromptToHandler()

        viewController.setExpanded(false, animated: false)
        let renderState = computeRenderState()
        utiLog.debug("Coordinator.activateFromOmnibar → viewController.apply")
        viewController.apply(renderState.viewConfig, animated: false)
        viewController.isCustomizeResponsesButtonHidden = true
        utiLog.debug("Coordinator.activateFromOmnibar → fetchModels")
        fetchModels()

        if let text = prefilledText, !text.isEmpty {
            utiLog.debug("Coordinator.activateFromOmnibar 🔀 prefilledText is non-empty, setting text + prefilledSelected")
            setText(text)
            textState = .prefilledSelected
        } else {
            utiLog.debug("Coordinator.activateFromOmnibar 🔀 no prefilled text")
        }

        utiLog.debug("Coordinator.activateFromOmnibar → contentViewController.setDismissButtonVisible(\(renderState.isContentVisible, privacy: .public))")
        contentViewController.setDismissButtonVisible(renderState.isContentVisible)
        let expandedHeight = omnibarEditingHeight()

        if cardPosition == .top && isToggleEnabled {
            utiLog.debug("Coordinator.activateFromOmnibar 🔀 cardPosition=top && isToggleEnabled=true, using toggleHidden height")
            viewController.setExpanded(false, animated: false)
            viewController.setExpandedWithToggleHidden(true)
            let toggleHiddenHeight = omnibarEditingHeight()
            utiLog.debug("Coordinator.activateFromOmnibar → firing intentSubject(.showOmnibarEditing) expandedHeight=\(toggleHiddenHeight, privacy: .public), pendingExpandedHeight=\(expandedHeight, privacy: .public)")
            intentSubject.send(.showOmnibarEditing(expandedHeight: toggleHiddenHeight, pendingExpandedHeight: expandedHeight))
        } else if cardPosition == .top {
            utiLog.debug("Coordinator.activateFromOmnibar 🔀 cardPosition=top && isToggleEnabled=false, using omnibarMatching height")
            viewController.setExpanded(false, animated: false)
            viewController.setExpandedWithToggleHidden(true)
            let omnibarMatchingHeight = omnibarEditingHeight()
            utiLog.debug("Coordinator.activateFromOmnibar → firing intentSubject(.showOmnibarEditing) expandedHeight=\(omnibarMatchingHeight, privacy: .public)")
            intentSubject.send(.showOmnibarEditing(expandedHeight: omnibarMatchingHeight))
        } else {
            utiLog.debug("Coordinator.activateFromOmnibar 🔀 cardPosition=bottom, using direct expandedHeight=\(expandedHeight, privacy: .public)")
            utiLog.debug("Coordinator.activateFromOmnibar → firing intentSubject(.showOmnibarEditing)")
            intentSubject.send(.showOmnibarEditing(expandedHeight: expandedHeight))
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, case .omnibar(.active) = displayState else {
                utiLog.debug("Coordinator.activateFromOmnibar ↩️ guard: self is nil or displayState is no longer .omnibar(.active)")
                return
            }
            utiLog.debug("Coordinator.activateFromOmnibar → viewController.activateInput")
            viewController.activateInput()
            if textState == .prefilledSelected {
                utiLog.debug("Coordinator.activateFromOmnibar 🔀 textState=prefilledSelected → selectAllText")
                viewController.selectAllText()
            }
        }
    }

    func deactivateToOmnibar(resetView: Bool = true) {
        guard isOmnibarSession else {
            utiLog.debug("Coordinator.deactivateToOmnibar ↩️ guard: isOmnibarSession=false")
            return
        }
        let oldDisplayState = self.displayState
        displayState = .hidden
        utiLog.debug("Coordinator.deactivateToOmnibar - displayState: \(String(describing: oldDisplayState), privacy: .public) → \(String(describing: self.displayState), privacy: .public), resetView: \(resetView, privacy: .public)")
        cardPosition = .bottom
        isInputVisibleForKeyboard = true
        setText("")
        clearAttachments()

        if resetView {
            utiLog.debug("Coordinator.deactivateToOmnibar 🔀 resetView=true → apply + deactivateInput + setDismissButtonVisible")
            let renderState = computeRenderState()
            viewController.apply(renderState.viewConfig, animated: false)
            viewController.deactivateInput()
            contentViewController.setDismissButtonVisible(renderState.isContentVisible)
        } else {
            utiLog.debug("Coordinator.deactivateToOmnibar 🔀 resetView=false → deactivateInput only + setDismissButtonVisible")
            viewController.deactivateInput()
            let renderState = computeRenderState()
            contentViewController.setDismissButtonVisible(renderState.isContentVisible)
        }
        utiLog.debug("Coordinator.deactivateToOmnibar → firing intentSubject(.hideOmnibarEditing)")
        intentSubject.send(.hideOmnibarEditing)
    }

    func updateToggleEnabled(_ enabled: Bool) {
        guard enabled != isToggleEnabled else {
            utiLog.debug("Coordinator.updateToggleEnabled ↩️ guard: enabled=\(enabled, privacy: .public) already matches isToggleEnabled")
            return
        }
        utiLog.debug("Coordinator.updateToggleEnabled - isToggleEnabled: \(self.isToggleEnabled, privacy: .public) → \(enabled, privacy: .public)")
        isToggleEnabled = enabled
        utiLog.debug("Coordinator.updateToggleEnabled → viewController.updateToggleEnabled")
        viewController.updateToggleEnabled(enabled)
        if !enabled, isOmnibarSession {
            utiLog.debug("Coordinator.updateToggleEnabled 🔀 enabled=false && isOmnibarSession=true → forcing inputMode=.search")
            inputMode = .search
            viewController.apply(computeRenderState().viewConfig, animated: false)
            utiLog.debug("Coordinator.updateToggleEnabled → firing modeChangeSubject(.search)")
            modeChangeSubject.send(.search)
        }
    }

    func animateOmnibarExpansion(additionalAnimations: (() -> Void)? = nil) {
        utiLog.debug("Coordinator.animateOmnibarExpansion")
        utiLog.debug("Coordinator.animateOmnibarExpansion → viewController.animateToggleReveal")
        viewController.animateToggleReveal(additionalAnimations: additionalAnimations)
    }

    func omnibarEditingHeight() -> CGFloat {
        utiLog.debug("Coordinator.omnibarEditingHeight")
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
        utiLog.debug("Coordinator.setText - text: \(text, privacy: .public)")
        currentText = text
        textState = text.isEmpty ? .empty : .userTyped
        viewController.text = text
    }

    // MARK: - Input Management

    func updateInputMode(_ mode: TextEntryMode, animated: Bool) {
        let oldInputMode = self.inputMode
        let effectiveMode: TextEntryMode = (!isToggleEnabled && isOmnibarSession) ? .search : mode
        inputMode = effectiveMode
        utiLog.debug("Coordinator.updateInputMode - inputMode: \(String(describing: oldInputMode), privacy: .public) → \(String(describing: effectiveMode), privacy: .public), requestedMode: \(String(describing: mode), privacy: .public), isToggleEnabled: \(self.isToggleEnabled, privacy: .public)")
        utiLog.debug("Coordinator.updateInputMode → viewController.setInputMode + modeChangeSubject")
        viewController.setInputMode(effectiveMode, animated: animated)
        modeChangeSubject.send(effectiveMode)
        updateToolbarAIVoiceChat()
        if effectiveMode == .search {
            utiLog.debug("Coordinator.updateInputMode 🔀 effectiveMode=search → clearAttachments")
            clearAttachments()
        }
    }

    func updateAIVoiceChatAvailability(_ enabled: Bool) {
        utiLog.debug("Coordinator.updateAIVoiceChatAvailability - enabled: \(enabled, privacy: .public)")
        utiLog.debug("Coordinator.updateAIVoiceChatAvailability → handler.isAIVoiceChatEnabled=\(enabled, privacy: .public) + updateToolbarAIVoiceChat")
        viewController.handler.isAIVoiceChatEnabled = enabled
        updateToolbarAIVoiceChat()
    }

    private func updateToolbarAIVoiceChat() {
        let isActive = viewController.handler.isAIVoiceChatEnabled && inputMode == .aiChat
        utiLog.debug("Coordinator.updateToolbarAIVoiceChat - inputMode: \(String(describing: self.inputMode), privacy: .public), isAIVoiceChatEnabled: \(self.viewController.handler.isAIVoiceChatEnabled, privacy: .public), result: \(isActive, privacy: .public)")
        viewController.isToolbarAIVoiceChatActive = isActive
    }


    func syncInputModeFromExternalSource(_ mode: TextEntryMode) {
        let oldInputMode = self.inputMode
        let effectiveMode: TextEntryMode = (!isToggleEnabled && isOmnibarSession) ? .search : mode
        let didModeChange = inputMode != effectiveMode
        inputMode = effectiveMode
        utiLog.debug("Coordinator.syncInputModeFromExternalSource - inputMode: \(String(describing: oldInputMode), privacy: .public) → \(String(describing: effectiveMode), privacy: .public), requestedMode: \(String(describing: mode), privacy: .public), didModeChange: \(didModeChange, privacy: .public)")
        if didModeChange || effectiveMode != mode {
            utiLog.debug("Coordinator.syncInputModeFromExternalSource 🔀 didModeChange=\(didModeChange, privacy: .public) || effectiveMode!=mode=\(effectiveMode != mode, privacy: .public) → setInputMode")
            viewController.setInputMode(effectiveMode, animated: false)
        }
        if didModeChange {
            utiLog.debug("Coordinator.syncInputModeFromExternalSource 🔀 didModeChange=true → firing modeChangeSubject + updateToolbarAIVoiceChat")
            modeChangeSubject.send(effectiveMode)
            updateToolbarAIVoiceChat()
        }
    }

    func updateOmnibarInputVisibility(_ isInputVisible: Bool) {
        let oldDisplayState = self.displayState
        isInputVisibleForKeyboard = isInputVisible
        utiLog.debug("Coordinator.updateOmnibarInputVisibility - isInputVisible: \(isInputVisible, privacy: .public), displayState: \(String(describing: oldDisplayState), privacy: .public)")
        let isAITabSearch = displayState == .aiTab(.expanded) && inputMode == .search

        switch (displayState, isInputVisible) {
        case (.omnibar(.active), false):
            utiLog.debug("Coordinator.updateOmnibarInputVisibility 🔀 omnibar(.active)+hidden → transitioning to omnibar(.inactive)")
            displayState = .omnibar(.inactive)
            let renderState = computeRenderState()
            viewController.apply(renderState.viewConfig, animated: false)
            contentViewController.setDismissButtonVisible(renderState.isContentVisible)
            utiLog.debug("Coordinator.updateOmnibarInputVisibility → firing intentSubject(.showOmnibarInactive)")
            intentSubject.send(.showOmnibarInactive)
        case (.omnibar(.inactive), true):
            utiLog.debug("Coordinator.updateOmnibarInputVisibility 🔀 omnibar(.inactive)+visible → transitioning to omnibar(.active)")
            displayState = .omnibar(.active)
            let renderState = computeRenderState()
            viewController.apply(renderState.viewConfig, animated: false)
            contentViewController.setDismissButtonVisible(renderState.isContentVisible)
            utiLog.debug("Coordinator.updateOmnibarInputVisibility → firing intentSubject(.showOmnibarActive)")
            intentSubject.send(.showOmnibarActive)
        case (.aiTab(.expanded), false) where isAITabSearch:
            utiLog.debug("Coordinator.updateOmnibarInputVisibility 🔀 aiTab(.expanded)+search+hidden → updating render state")
            let renderState = computeRenderState()
            viewController.apply(renderState.viewConfig, animated: false)
            contentViewController.setDismissButtonVisible(renderState.isContentVisible)
        case (.aiTab(.expanded), true) where isAITabSearch:
            utiLog.debug("Coordinator.updateOmnibarInputVisibility 🔀 aiTab(.expanded)+search+visible → updating render state")
            let renderState = computeRenderState()
            viewController.apply(renderState.viewConfig, animated: false)
            contentViewController.setDismissButtonVisible(renderState.isContentVisible)
        default:
            utiLog.debug("Coordinator.updateOmnibarInputVisibility 🔀 default branch, no action for displayState=\(String(describing: self.displayState), privacy: .public), isInputVisible=\(isInputVisible, privacy: .public)")
            break
        }
    }

    func activateInput() {
        utiLog.debug("Coordinator.activateInput")
        utiLog.debug("Coordinator.activateInput → viewController.activateInput")
        viewController.activateInput()
    }

    func dismissOmnibarKeyboard() {
        utiLog.debug("Coordinator.dismissOmnibarKeyboard - displayState: \(String(describing: self.displayState), privacy: .public)")
        switch displayState {
        case .omnibar(.active), .aiTab(.expanded):
            utiLog.debug("Coordinator.dismissOmnibarKeyboard 🔀 displayState allows deactivation → deactivateInput")
            viewController.deactivateInput()
        default:
            utiLog.debug("Coordinator.dismissOmnibarKeyboard 🔀 displayState=\(String(describing: self.displayState), privacy: .public), no deactivation needed")
            return
        }
    }

    func updateVoiceSearchAvailability(_ enabled: Bool) {
        utiLog.debug("Coordinator.updateVoiceSearchAvailability - enabled: \(enabled, privacy: .public)")
        utiLog.debug("Coordinator.updateVoiceSearchAvailability 📐 isVoiceSearchAvailable=\(enabled, privacy: .public)")
        viewController.isVoiceSearchAvailable = enabled
    }

    func clearText() {
        utiLog.debug("Coordinator.clearText")
        setText("")
    }

    func stopGeneratingButtonTapped() {
        utiLog.debug("Coordinator.stopGeneratingButtonTapped")
        utiLog.debug("Coordinator.stopGeneratingButtonTapped → viewController.handler.stopGeneratingButtonTapped")
        viewController.handler.stopGeneratingButtonTapped()
    }

    // MARK: - External Submissions

    var hasBoundUserScript: Bool {
        boundUserScript != nil
    }

    func submitVoicePrompt(_ text: String) {
        utiLog.debug("Coordinator.submitVoicePrompt")
        guard let userScript = boundUserScript else {
            utiLog.debug("Coordinator.submitVoicePrompt ↩️ guard: boundUserScript is nil")
            return
        }
        let modelId = hasSubmittedPrompt ? nil : persistedModelId
        utiLog.debug("Coordinator.submitVoicePrompt 🔀 hasSubmittedPrompt=\(self.hasSubmittedPrompt, privacy: .public), modelId=\(String(describing: modelId), privacy: .public)")
        hasSubmittedPrompt = true
        updateModelChipVisibility()
        syncHasSubmittedPromptToHandler()
        showCollapsed()
        utiLog.debug("Coordinator.submitVoicePrompt → userScript.submitPrompt")
        userScript.submitPrompt(text, images: nil, modelId: modelId)
    }

    func handleExternalSubmission(_ type: ExternalSubmissionType) {
        utiLog.debug("Coordinator.handleExternalSubmission - type: \(String(describing: type), privacy: .public), displayState: \(String(describing: self.displayState), privacy: .public)")
        switch displayState {
        case .omnibar:
            utiLog.debug("Coordinator.handleExternalSubmission 🔀 displayState=omnibar → deactivateToOmnibar")
            deactivateToOmnibar()
        case .aiTab:
            switch type {
            case .query:
                utiLog.debug("Coordinator.handleExternalSubmission 🔀 displayState=aiTab, type=query → hide")
                hide()
            case .prompt:
                utiLog.debug("Coordinator.handleExternalSubmission 🔀 displayState=aiTab, type=prompt → showCollapsed")
                showCollapsed()
            }
        case .hidden:
            utiLog.debug("Coordinator.handleExternalSubmission 🔀 displayState=hidden, no action")
            break
        }
    }

    // MARK: - Content & Layout

    func pushContentInsets() {
        let utiHeight = viewController.view.frame.height
        utiLog.debug("Coordinator.pushContentInsets - cardPosition: \(String(describing: self.cardPosition), privacy: .public), utiHeight: \(utiHeight, privacy: .public)")
        if cardPosition == .top {
            utiLog.debug("Coordinator.pushContentInsets 📐 cardPosition=top → setContentInset(top: \(utiHeight, privacy: .public), bottom: 0)")
            contentViewController.setContentInset(top: utiHeight, bottom: 0)
        } else {
            utiLog.debug("Coordinator.pushContentInsets 📐 cardPosition=bottom → setContentInset(top: 0, bottom: \(utiHeight, privacy: .public))")
            contentViewController.setContentInset(top: 0, bottom: utiHeight)
        }
    }

    func syncContentInputMode(_ mode: TextEntryMode, animated: Bool = true) {
        utiLog.debug("Coordinator.syncContentInputMode - mode: \(String(describing: mode), privacy: .public)")
        contentViewController.setInputMode(mode, animated: animated)
    }

    func applyDismissButtonVisibility() {
        utiLog.debug("Coordinator.applyDismissButtonVisibility")
        let renderState = computeRenderState()
        utiLog.debug("Coordinator.applyDismissButtonVisibility → contentViewController.setDismissButtonVisible(\(renderState.isContentVisible, privacy: .public))")
        contentViewController.setDismissButtonVisible(renderState.isContentVisible)
    }

    // MARK: - Render State

    func computeRenderState() -> UTIRenderState {
        utiLog.debug("Coordinator.computeRenderState - displayState: \(String(describing: self.displayState), privacy: .public), inputMode: \(String(describing: self.inputMode), privacy: .public)")
        let isExpanded: Bool
        let isInputVisible: Bool
        let isContentVisible: Bool
        let inactiveAppearance: Bool

        switch displayState {
        case .hidden:
            utiLog.debug("Coordinator.computeRenderState 🔀 case .hidden")
            isExpanded = false
            isInputVisible = false
            isContentVisible = false
            inactiveAppearance = false

        case .aiTab(.collapsed):
            utiLog.debug("Coordinator.computeRenderState 🔀 case .aiTab(.collapsed)")
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
            utiLog.debug("Coordinator.computeRenderState 🔀 case .aiTab(.expanded) - isAIChatOnAITab=\(isAIChatOnAITab, privacy: .public), isSearchOnAITab=\(isSearchOnAITab, privacy: .public), isSearchKeyboardHidden=\(isSearchKeyboardHidden, privacy: .public)")
            inactiveAppearance = isSearchKeyboardHidden

        case .omnibar(.active):
            utiLog.debug("Coordinator.computeRenderState 🔀 case .omnibar(.active)")
            isExpanded = true
            isInputVisible = true
            isContentVisible = true
            inactiveAppearance = false

        case .omnibar(.inactive):
            utiLog.debug("Coordinator.computeRenderState 🔀 case .omnibar(.inactive) - cardPosition=\(String(describing: self.cardPosition), privacy: .public)")
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
        utiLog.debug("Coordinator.fetchModels")
        modelStore.fetchModels()
    }

    func startNewChat() {
        utiLog.debug("Coordinator.startNewChat")
        isNewChatPending = true
        hasSubmittedPrompt = false
        utiLog.debug("Coordinator.startNewChat → updateModelChipVisibility + syncHasSubmittedPromptToHandler + clearAttachments + setText")
        updateModelChipVisibility()
        syncHasSubmittedPromptToHandler()
        clearAttachments()
        setText("")
        attachmentUsage = nil
    }

    func updateSelectedModel(_ modelId: String) {
        utiLog.debug("Coordinator.updateSelectedModel - modelId: \(modelId, privacy: .public)")
        utiLog.debug("Coordinator.updateSelectedModel → modelStore.updateSelectedModel + updateModelChipLabel + updateImageButtonVisibility")
        modelStore.updateSelectedModel(modelId)
        updateModelChipLabel()
        updateImageButtonVisibility()
    }

    private func buildModelMenuDescription() -> UnifiedToggleInputModelMenu {
        utiLog.debug("Coordinator.buildModelMenuDescription")
        return UnifiedToggleInputModelMenu.build(
            models: modelStore.models,
            selectedId: modelStore.persistedModelId,
            isBottomAnchored: viewController.cardPosition == .bottom,
            hasActiveSubscription: modelStore.subscriptionState.hasActiveSubscription,
            advancedSectionTitle: modelStore.subscriptionState.hasActiveSubscription
                ? UserText.aiChatAdvancedModelsSectionHeader
                : UserText.aiChatAdvancedModelsMenuTitle,
            basicSectionTitle: UserText.aiChatBasicModelsSectionHeader
        )
    }

    private func buildModelPickerMenu() -> UIMenu {
        utiLog.debug("Coordinator.buildModelPickerMenu")
        let description = buildModelMenuDescription()
        let modelLookup = Dictionary(uniqueKeysWithValues: modelStore.models.map { ($0.id, $0) })

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
        utiLog.debug("Coordinator.updateModelChipLabel")
        let selectedId = modelStore.persistedModelId
        let shortName = modelStore.models.first(where: { $0.id == selectedId })?.shortName
        if let shortName {
            utiLog.debug("Coordinator.updateModelChipLabel 🔀 found shortName=\(shortName, privacy: .public) for selectedId=\(String(describing: selectedId), privacy: .public)")
            viewController.modelName = shortName
            modelStore.cacheSelectedModelShortName(shortName)
        } else {
            utiLog.debug("Coordinator.updateModelChipLabel 🔀 no shortName found for selectedId=\(String(describing: selectedId), privacy: .public)")
        }
        let hasModels = !modelStore.models.isEmpty
        utiLog.debug("Coordinator.updateModelChipLabel → setting modelPickerMenu, hasModels=\(hasModels, privacy: .public)")
        viewController.modelPickerMenu = hasModels ? buildModelPickerMenu() : nil
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
        utiLog.debug("Coordinator.presentAttachmentOptions - remaining: \(self.remainingImagesForPicker, privacy: .public)")
        let remaining = remainingImagesForPicker
        guard let scene = viewController.view.window?.windowScene,
              let root = scene.keyWindow?.rootViewController else {
            utiLog.debug("Coordinator.presentAttachmentOptions ↩️ guard: windowScene or rootViewController is nil")
            return
        }

        let imageActionsDisabled = remaining <= 0
        utiLog.debug("Coordinator.presentAttachmentOptions 🔀 imageActionsDisabled=\(imageActionsDisabled, privacy: .public)")

        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            let action = UIAlertAction(title: UserText.aiChatAttachmentOptionTakePhoto, style: .default) { [weak self] _ in
                self?.presentCamera(from: root)
            }
            action.isEnabled = !imageActionsDisabled
            sheet.addAction(action)
        }

        let chooseAction = UIAlertAction(title: UserText.aiChatAttachmentOptionChoosePhoto, style: .default) { [weak self] _ in
            self?.presentPhotoPicker(from: root, remaining: remaining)
        }
        chooseAction.isEnabled = !imageActionsDisabled
        sheet.addAction(chooseAction)

        sheet.addAction(UIAlertAction(title: UserText.actionCancel, style: .cancel))

        if let popover = sheet.popoverPresentationController {
            popover.sourceView = viewController.attachButtonView
        }

        root.present(sheet, animated: true)
    }

    private func presentCamera(from presenter: UIViewController) {
        utiLog.debug("Coordinator.presentCamera")
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        presenter.present(picker, animated: true)
    }

    private func presentPhotoPicker(from presenter: UIViewController, remaining: Int) {
        utiLog.debug("Coordinator.presentPhotoPicker - remaining: \(remaining, privacy: .public)")
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = remaining
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        presenter.present(picker, animated: true)
    }

    private func expandIfOnAITab() {
        utiLog.debug("Coordinator.expandIfOnAITab - displayState: \(String(describing: self.displayState), privacy: .public)")
        if case .aiTab = displayState {
            utiLog.debug("Coordinator.expandIfOnAITab 🔀 isAITab=true → showExpanded")
            showExpanded()
        } else {
            utiLog.debug("Coordinator.expandIfOnAITab 🔀 isAITab=false, no expansion")
        }
    }

    func addImageAttachment(image: UIImage, fileName: String) {
        utiLog.debug("Coordinator.addImageAttachment - fileName: \(fileName, privacy: .public)")
        guard !viewController.isAttachmentsFull, !isConversationImageLimitReached else {
            utiLog.debug("Coordinator.addImageAttachment ↩️ guard: isAttachmentsFull=\(self.viewController.isAttachmentsFull, privacy: .public), isConversationImageLimitReached=\(self.isConversationImageLimitReached, privacy: .public)")
            return
        }
        let attachment = AIChatImageAttachment(image: image, fileName: fileName)
        utiLog.debug("Coordinator.addImageAttachment → viewController.addAttachment")
        viewController.addAttachment(attachment)
    }

    func removeAttachment(id: UUID) {
        utiLog.debug("Coordinator.removeAttachment - id: \(id, privacy: .public)")
        viewController.removeAttachment(id: id)
    }

    func clearAttachments() {
        utiLog.debug("Coordinator.clearAttachments")
        viewController.removeAllAttachments()
    }

    func updateImageButtonVisibility() {
        let supportsImages = selectedModelSupportsImageUpload
        utiLog.debug("Coordinator.updateImageButtonVisibility - supportsImages: \(supportsImages, privacy: .public)")
        utiLog.debug("Coordinator.updateImageButtonVisibility 📐 isImageButtonHidden=\(!supportsImages, privacy: .public)")
        viewController.isImageButtonHidden = !supportsImages
        if !supportsImages {
            utiLog.debug("Coordinator.updateImageButtonVisibility 🔀 supportsImages=false → clearAttachments")
            clearAttachments()
        }
    }

    // MARK: - Subscriptions

    private func subscribeToGeneratingState() {
        utiLog.debug("Coordinator.subscribeToGeneratingState")
        $aiChatStatus
            .map { status in
                status == .loading || status == .streaming || status == .startStreamNewPrompt
            }
            .removeDuplicates()
            .sink { [weak self] isGenerating in
                guard let self else {
                    utiLog.debug("Coordinator.subscribeToGeneratingState ↩️ guard: self is nil")
                    return
                }
                utiLog.debug("Coordinator.subscribeToGeneratingState → viewController.isGenerating=\(isGenerating, privacy: .public)")
                self.viewController.isGenerating = isGenerating
            }
            .store(in: &cancellables)
    }

    private func subscribeToStopGeneratingTap() {
        utiLog.debug("Coordinator.subscribeToStopGeneratingTap")
        viewController.handler.stopGeneratingButtonTappedPublisher
            .sink { [weak self] in
                utiLog.debug("Coordinator.subscribeToStopGeneratingTap → firing didPressStopGeneratingButton")
                self?.didPressStopGeneratingButton.send()
            }
            .store(in: &cancellables)
    }

    private func subscribeToAttachmentUsageChanges() {
        utiLog.debug("Coordinator.subscribeToAttachmentUsageChanges")
        $attachmentUsage
            .removeDuplicates()
            .sink { [weak self] _ in
                utiLog.debug("Coordinator.subscribeToAttachmentUsageChanges → updateImageButtonVisibility")
                self?.updateImageButtonVisibility()
            }
            .store(in: &cancellables)
    }

    private func subscribeToCustomizeResponsesTap() {
        utiLog.debug("Coordinator.subscribeToCustomizeResponsesTap")
        viewController.handler.customizeResponsesButtonTappedPublisher
            .sink { [weak self] in
                guard let self else {
                    utiLog.debug("Coordinator.subscribeToCustomizeResponsesTap ↩️ guard: self is nil")
                    return
                }
                utiLog.debug("Coordinator.subscribeToCustomizeResponsesTap → firing didPressCustomizeResponsesButton + showCollapsed")
                self.didPressCustomizeResponsesButton.send()
                self.showCollapsed()
            }
            .store(in: &cancellables)
    }

    private func subscribeToVoiceSearchTap() {
        utiLog.debug("Coordinator.subscribeToVoiceSearchTap")
        viewController.handler.microphoneButtonTappedPublisher
            .sink { [weak self] in
                utiLog.debug("Coordinator.subscribeToVoiceSearchTap → delegate.unifiedToggleInputDidRequestVoiceSearch")
                self?.delegate?.unifiedToggleInputDidRequestVoiceSearch()
            }
            .store(in: &cancellables)
    }

    // MARK: - State Reset

    private func updateModelChipVisibility() {
        utiLog.debug("Coordinator.updateModelChipVisibility - hasSubmittedPrompt: \(self.hasSubmittedPrompt, privacy: .public)")
        utiLog.debug("Coordinator.updateModelChipVisibility 📐 isModelChipHidden=\(self.hasSubmittedPrompt, privacy: .public)")
        viewController.isModelChipHidden = hasSubmittedPrompt
    }

    private func syncHasSubmittedPromptToHandler() {
        utiLog.debug("Coordinator.syncHasSubmittedPromptToHandler - hasSubmittedPrompt: \(self.hasSubmittedPrompt, privacy: .public)")
        switchBarHandler.hasSubmittedPrompt = hasSubmittedPrompt
    }

    private func resetSessionState() {
        utiLog.debug("Coordinator.resetSessionState")
        utiLog.debug("Coordinator.resetSessionState → clearing all session state: isNewChatPending, text, aiChatStatus, attachmentUsage, hasSubmittedPrompt")
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
        utiLog.debug("Coordinator.unifiedToggleInputVCDidTapWhileCollapsed - inputMode: \(String(describing: self.inputMode), privacy: .public)")
        utiLog.debug("Coordinator.unifiedToggleInputVCDidTapWhileCollapsed → showExpanded")
        showExpanded(inputMode: inputMode)
    }

    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didSubmitText text: String, mode: TextEntryMode) {
        utiLog.debug("Coordinator.didSubmitText - mode: \(String(describing: mode), privacy: .public), displayState: \(String(describing: self.displayState), privacy: .public)")
        setText("")

        switch mode {
        case .search:
            utiLog.debug("Coordinator.didSubmitText 🔀 mode=search")
            if case .aiTab = displayState {
                utiLog.debug("Coordinator.didSubmitText 🔀 displayState=aiTab → hide")
                hide()
            } else if isOmnibarSession {
                utiLog.debug("Coordinator.didSubmitText 🔀 isOmnibarSession=true → deactivateToOmnibar")
                deactivateToOmnibar()
            }
            utiLog.debug("Coordinator.didSubmitText → delegate.unifiedToggleInputDidSubmitQuery + didSubmitQuery.send")
            delegate?.unifiedToggleInputDidSubmitQuery(text)
            didSubmitQuery.send(text)
        case .aiChat:
            utiLog.debug("Coordinator.didSubmitText 🔀 mode=aiChat, hasSubmittedPrompt=\(self.hasSubmittedPrompt, privacy: .public)")
            let images = UnifiedToggleInputImageEncoder.encode(viewController.currentAttachments)
            let modelId = hasSubmittedPrompt ? nil : persistedModelId
            clearAttachments()
            hasSubmittedPrompt = true
            updateModelChipVisibility()
            syncHasSubmittedPromptToHandler()
            if isOmnibarSession {
                utiLog.debug("Coordinator.didSubmitText 🔀 isOmnibarSession=true → deactivateToOmnibar")
                deactivateToOmnibar()
            } else {
                utiLog.debug("Coordinator.didSubmitText 🔀 isOmnibarSession=false → showCollapsed")
                showCollapsed()
            }
            if let userScript = boundUserScript {
                utiLog.debug("Coordinator.didSubmitText → userScript.submitPrompt (modelId=\(String(describing: modelId), privacy: .public))")
                userScript.submitPrompt(text, images: images, modelId: modelId)
            } else {
                utiLog.debug("Coordinator.didSubmitText → delegate.unifiedToggleInputDidSubmitPrompt (modelId=\(String(describing: modelId), privacy: .public))")
                delegate?.unifiedToggleInputDidSubmitPrompt(text, modelId: modelId, images: images)
            }
        }
    }

    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didChangeText text: String) {
        let newTextState: InputTextState = text.isEmpty ? .empty : .userTyped
        utiLog.debug("Coordinator.didChangeText - textState: \(String(describing: self.textState), privacy: .public) → \(String(describing: newTextState), privacy: .public)")
        currentText = text
        textState = newTextState
        utiLog.debug("Coordinator.didChangeText → firing textChangeSubject")
        textChangeSubject.send(text)
    }

    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didChangeMode mode: TextEntryMode) {
        utiLog.debug("Coordinator.didChangeMode - mode: \(String(describing: mode), privacy: .public)")
        utiLog.debug("Coordinator.didChangeMode → updateInputMode")
        updateInputMode(mode, animated: true)
    }

    func unifiedToggleInputVCDidTapSearchGoTo(_ vc: UnifiedToggleInputViewController) {
        utiLog.debug("Coordinator.didTapSearchGoTo")
        utiLog.debug("Coordinator.didTapSearchGoTo → showExpanded(inputMode: .search)")
        showExpanded(inputMode: .search)
    }

    func unifiedToggleInputVCDidTapAttach(_ vc: UnifiedToggleInputViewController) {
        utiLog.debug("Coordinator.didTapAttach")
        utiLog.debug("Coordinator.didTapAttach → presentAttachmentOptions")
        presentAttachmentOptions()
    }

    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didRemoveAttachment id: UUID) {
        utiLog.debug("Coordinator.didRemoveAttachment - id: \(id, privacy: .public)")
        utiLog.debug("Coordinator.didRemoveAttachment → removeAttachment")
        removeAttachment(id: id)
    }

    func unifiedToggleInputVCDidChangeAttachments(_ vc: UnifiedToggleInputViewController) {
        utiLog.debug("Coordinator.didChangeAttachments")
        utiLog.debug("Coordinator.didChangeAttachments → firing attachmentsChangeSubject")
        attachmentsChangeSubject.send()
    }

    func unifiedToggleInputVCDidChangeHeight(_ vc: UnifiedToggleInputViewController) {
        utiLog.debug("Coordinator.didChangeHeight")
        utiLog.debug("Coordinator.didChangeHeight → delegate.unifiedToggleInputDidChangeHeight")
        delegate?.unifiedToggleInputDidChangeHeight()
    }
}

// MARK: - PHPickerViewControllerDelegate

extension UnifiedToggleInputCoordinator: PHPickerViewControllerDelegate {

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        utiLog.debug("Coordinator.picker(didFinishPicking:) - count: \(results.count, privacy: .public)")
        picker.dismiss(animated: true)
        expandIfOnAITab()
        for result in results {
            let provider = result.itemProvider
            guard provider.canLoadObject(ofClass: UIImage.self) else {
                utiLog.debug("Coordinator.picker(didFinishPicking:) ↩️ guard: provider cannot load UIImage, skipping item")
                continue
            }
            provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                guard let image = object as? UIImage else {
                    utiLog.debug("Coordinator.picker(didFinishPicking:) ↩️ guard: loaded object is not UIImage")
                    return
                }
                let fileName = provider.suggestedName ?? "image"
                utiLog.debug("Coordinator.picker(didFinishPicking:) → addImageAttachment fileName=\(fileName, privacy: .public)")
                DispatchQueue.main.async {
                    self?.addImageAttachment(image: image, fileName: fileName)
                }
            }
        }
    }
}

// MARK: - UIImagePickerControllerDelegate

extension UnifiedToggleInputCoordinator: UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        utiLog.debug("Coordinator.imagePickerController(didFinishPickingMediaWithInfo:)")
        picker.dismiss(animated: true)
        expandIfOnAITab()
        guard let image = info[.originalImage] as? UIImage else {
            utiLog.debug("Coordinator.imagePickerController ↩️ guard: .originalImage not found in info")
            return
        }
        utiLog.debug("Coordinator.imagePickerController → addImageAttachment(photo)")
        addImageAttachment(image: image, fileName: "photo")
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        utiLog.debug("Coordinator.imagePickerControllerDidCancel")
        picker.dismiss(animated: true)
        expandIfOnAITab()
    }
}
