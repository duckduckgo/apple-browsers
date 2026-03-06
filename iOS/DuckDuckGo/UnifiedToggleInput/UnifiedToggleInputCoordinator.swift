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

private let utiCoordLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "UTI-Constraint")

// MARK: - State Types

enum InputTextState {
    case empty
    case prefilledSelected
    case userTyped
}

enum UTIDisplayState: Equatable {
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

enum UnifiedToggleInputIntent {
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

    @Published var aiChatStatus: AIChatStatusValue = .unknown {
        didSet {
            switch aiChatStatus {
            case .startStreamNewPrompt, .loading, .streaming, .error, .blocked:
                hasEverStreamed = true
            case .ready, .unknown:
                break
            }
        }
    }
    @Published var aiChatInputBoxVisibility: AIChatInputBoxVisibility = .unknown

    // MARK: - Properties

    /// The managed view controller. Access for installation only — query coordinator properties for state.
    private(set) var viewController: UnifiedToggleInputViewController
    weak var delegate: UnifiedToggleInputDelegate?

    private(set) var isToggleEnabled: Bool
    private(set) var displayState: UTIDisplayState = .hidden
    private(set) var textState: InputTextState = .empty
    private(set) var inputMode: TextEntryMode = .aiChat
    private var originalCardPosition: UnifiedToggleInputCardPosition = .top
    private(set) var hasEverStreamed = false

    var currentText: String { viewController.text }
    var hasActiveChat: Bool { boundUserScript != nil }
    var switchBarHandler: SwitchBarHandling { viewController.handler }

    var isInlineEditingActive: Bool {
        if case .inline = displayState { return true }
        return false
    }

    var hasChatStarted: Bool {
        hasEverStreamed
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

    init(isToggleEnabled: Bool) {
        self.isToggleEnabled = isToggleEnabled
        viewController = UnifiedToggleInputViewController(isToggleEnabled: isToggleEnabled)
        viewController.delegate = self
    }

    // MARK: - Tab Binding

    func bindToTab(_ userScript: AIChatUserScript) {
        let newIdentifier = ObjectIdentifier(userScript)
        if boundUserScriptIdentifier == newIdentifier {
            boundUserScript = userScript
            userScript.inputBoxHandler = self
            return
        }
        let hadPreviousScript = boundUserScriptIdentifier != nil
        boundUserScript?.inputBoxHandler = nil
        boundUserScript = userScript
        boundUserScriptIdentifier = newIdentifier
        userScript.inputBoxHandler = self
        if hadPreviousScript {
            resetInputState()
        }
    }

    func unbind() {
        boundUserScript?.inputBoxHandler = nil
        boundUserScript = nil
        resetSessionState()
    }

    // MARK: - AI Tab Display State Management

    func showCollapsed() {
        logUTI("showCollapsed:start")
        displayState = .aiTab(.collapsed)
        viewController.setExpanded(false, animated: false)
        viewController.deactivateInput()
        intentSubject.send(.showCollapsed)
        logUTI("showCollapsed:end")
    }

    func showExpanded(prefilledText: String? = nil, inputMode: TextEntryMode = .aiChat) {
        logUTI("showExpanded:start requestedMode=\(inputMode.rawValue)")
        displayState = .aiTab(.expanded)
        self.inputMode = inputMode
        viewController.setInputMode(inputMode, animated: false)

        if let prefilledText, !prefilledText.isEmpty {
            viewController.text = prefilledText
            textState = .prefilledSelected
        }

        viewController.setExpanded(true, animated: false)
        intentSubject.send(.showExpanded)
        // Match inline-editing ordering: apply layout intent first, then request focus.
        // This avoids keyboard events racing ahead of the expanded container constraints.
        DispatchQueue.main.async { [weak self] in
            guard let self, case .aiTab(.expanded) = self.displayState else { return }
            self.viewController.activateInput()
            if !self.viewController.isInputFirstResponder {
                DispatchQueue.main.async { [weak self] in
                    guard let self, case .aiTab(.expanded) = self.displayState else { return }
                    self.viewController.activateInput()
                    self.logUTI("showExpanded:deferredActivateInputRetry")
                }
            }
            if self.textState == .prefilledSelected {
                self.viewController.selectAllText()
            }
        }
        logUTI("showExpanded:end requestedMode=\(inputMode.rawValue)")
    }

    func hide() {
        logUTI("hide:start")
        displayState = .hidden
        viewController.deactivateInput()
        viewController.setExpanded(false, animated: false)
        intentSubject.send(.hide)
        logUTI("hide:end")
    }

    // MARK: - Inline Editing State Management

    func activateInlineEditing(prefilledText: String? = nil, inputMode: TextEntryMode = .search, cardPosition: UnifiedToggleInputCardPosition = .top) {
        logUTI("activateInlineEditing:start requestedMode=\(inputMode.rawValue) cardPosition=\(String(describing: cardPosition))")
        let effectiveInputMode = isToggleEnabled ? inputMode : .search
        displayState = .inline(.active)
        self.inputMode = effectiveInputMode
        self.originalCardPosition = cardPosition
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
        let height = inlineEditingHeight(for: effectiveInputMode)
        intentSubject.send(.showInlineEditing(expandedHeight: height))

        DispatchQueue.main.async { [weak self] in
            guard let self, case .inline(.active) = displayState else { return }
            viewController.activateInput()
            if textState == .prefilledSelected {
                viewController.selectAllText()
            }
        }
        logUTI("activateInlineEditing:end effectiveMode=\(effectiveInputMode.rawValue)")
    }

    func inlineEditingHeight(for mode: TextEntryMode) -> CGFloat {
        viewController.setInputMode(mode, animated: false)
        let screenWidth = UIScreen.main.bounds.width
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
        logUTI("updateInputMode requested=\(mode.rawValue) effective=\(effectiveMode.rawValue) animated=\(animated)")
    }

    func syncInputModeFromExternalSource(_ mode: TextEntryMode) {
        let effectiveMode: TextEntryMode = isToggleEnabled ? mode : .search
        inputMode = effectiveMode
        if effectiveMode != mode {
            viewController.setInputMode(effectiveMode, animated: false)
        }
        modeChangeSubject.send(effectiveMode)
        logUTI("syncInputModeFromExternalSource requested=\(mode.rawValue) effective=\(effectiveMode.rawValue)")
    }

    func updateVoiceSearchAvailability(_ enabled: Bool) {
        viewController.isVoiceSearchAvailable = enabled
    }

    func activateInput() {
        viewController.activateInput()
    }

    func clearText() {
        viewController.text = ""
        textState = .empty
    }

    func handleExternalQuerySubmission() {
        logUTI("handleExternalQuerySubmission:start")
        switch displayState {
        case .inline:
            deactivateInlineEditing()
        case .aiTab:
            hide()
        case .hidden:
            break
        }
        logUTI("handleExternalQuerySubmission:end")
    }

    func handleExternalPromptSubmission() {
        logUTI("handleExternalPromptSubmission:start")
        switch displayState {
        case .inline:
            deactivateInlineEditing()
        case .aiTab:
            showCollapsed()
        case .hidden:
            break
        }
        logUTI("handleExternalPromptSubmission:end")
    }

    func deactivateInlineEditing() {
        guard isInlineEditingActive else { return }
        logUTI("deactivateInlineEditing:start")
        displayState = .hidden
        viewController.showsDismissButton = false
        viewController.usesInlineEditingMargins = false
        viewController.isTopBarPosition = false
        viewController.isToolbarSubmitHidden = false
        viewController.text = ""
        textState = .empty
        viewController.deactivateInput()
        viewController.setExpanded(false, animated: false)
        intentSubject.send(.hideInlineEditing)
        logUTI("deactivateInlineEditing:end")
    }


    func updateToggleEnabled(_ enabled: Bool) {
        guard enabled != isToggleEnabled else { return }
        isToggleEnabled = enabled
        viewController.updateToggleEnabled(enabled)
        if !enabled, isInlineEditingActive {
            inputMode = .search
            viewController.setInputMode(.search, animated: false)
            modeChangeSubject.send(.search)
        }
        logUTI("updateToggleEnabled enabled=\(enabled)")
    }

    /// Keeps inline editing active/inactive visual state in sync with input visibility.
    /// The caller (MainViewController) decides how input visibility is derived.
    func updateInlineEditingInputVisibility(_ isInputVisible: Bool) {
        if isInputVisible {
            guard case .inline(.inactive) = displayState else { return }
            displayState = .inline(.active)
            if originalCardPosition == .bottom {
                viewController.setInactiveCardAppearance(false)
            }
            intentSubject.send(.showInlineActive)
            logUTI("updateInlineEditingInputVisibility:inactive->active")
            return
        }

        guard case .inline(.active) = displayState else { return }
        displayState = .inline(.inactive)
        if originalCardPosition == .bottom {
            viewController.setInactiveCardAppearance(true)
        }
        intentSubject.send(.showInlineInactive)
        logUTI("updateInlineEditingInputVisibility:active->inactive")
    }

    /// Reconciles AI tab collapsed/expanded state with current input visibility.
    /// The caller (MainViewController) decides how input visibility is derived.
    func reconcileAITabExpansion(withInputVisibility isInputVisible: Bool) {
        switch displayState {
        case .aiTab(.collapsed):
            guard isInputVisible, viewController.isInputFirstResponder else { return }
            showExpanded(inputMode: inputMode)
            logUTI("reconcileAITabExpansion:collapsed->expanded")
        case .aiTab(.expanded):
            guard !isInputVisible, !viewController.isInputFirstResponder else { return }
            showCollapsed()
            logUTI("reconcileAITabExpansion:expanded->collapsed")
        default:
            break
        }
    }

    // MARK: - Private

    private func resetSessionState() {
        viewController.text = ""
        textState = .empty
        aiChatStatus = .unknown
        aiChatInputBoxVisibility = .unknown
    }

    private func resetInputState() {
        resetSessionState()
        hasEverStreamed = false
    }

    private func logUTI(_ event: String) {
        utiCoordLog.debug(
            "UTILogging | Coordinator | \(event, privacy: .public) | displayState=\(String(describing: self.displayState), privacy: .public) inputMode=\(String(describing: self.inputMode), privacy: .public) textState=\(String(describing: self.textState), privacy: .public) toggleEnabled=\(self.isToggleEnabled) hasActiveChat=\(self.hasActiveChat)"
        )
    }
}

// MARK: - UnifiedToggleInputViewControllerDelegate

extension UnifiedToggleInputCoordinator: UnifiedToggleInputViewControllerDelegate {

    func unifiedToggleInputVCDidTapWhileCollapsed(_ vc: UnifiedToggleInputViewController) {
        logUTI("unifiedToggleInputVCDidTapWhileCollapsed")
        showExpanded(inputMode: inputMode)
    }

    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didSubmitText text: String, mode: TextEntryMode) {
        logUTI("unifiedToggleInputVC:didSubmitText mode=\(mode.rawValue)")
        vc.text = ""
        textState = .empty

        let effectiveMode = inputMode
        if effectiveMode != mode {
            logUTI("unifiedToggleInputVC:submitModeMismatch submitted=\(mode.rawValue) effective=\(effectiveMode.rawValue)")
        }

        switch effectiveMode {
        case .search:
            if case .aiTab = displayState {
                hide()
            } else if isInlineEditingActive {
                deactivateInlineEditing()
            }
            delegate?.unifiedToggleInputDidSubmitQuery(text)
            didSubmitQuery.send(text)
        case .aiChat:
            if isInlineEditingActive {
                deactivateInlineEditing()
            } else {
                showCollapsed()
            }
            if boundUserScript != nil {
                didSubmitPrompt.send(text)
            } else {
                delegate?.unifiedToggleInputDidSubmitPrompt(text)
            }
        }
    }

    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didChangeText text: String) {
        textState = text.isEmpty ? .empty : .userTyped
        textChangeSubject.send(text)
        logUTI("unifiedToggleInputVC:didChangeText count=\(text.count)")
    }

    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didChangeMode mode: TextEntryMode) {
        logUTI("unifiedToggleInputVC:didChangeMode mode=\(mode.rawValue)")
        updateInputMode(mode, animated: false)
    }

    func unifiedToggleInputVCDidTapVoice(_ vc: UnifiedToggleInputViewController) {
        logUTI("unifiedToggleInputVCDidTapVoice")
        delegate?.unifiedToggleInputDidRequestVoiceSearch()
    }

    func unifiedToggleInputVCDidTapDismiss(_ vc: UnifiedToggleInputViewController) {
        logUTI("unifiedToggleInputVCDidTapDismiss")
        deactivateInlineEditing()
    }
}
