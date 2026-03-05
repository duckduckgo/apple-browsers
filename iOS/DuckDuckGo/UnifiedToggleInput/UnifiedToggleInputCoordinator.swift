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

// MARK: - State Types

enum InputTextState {
    case empty
    case prefilledSelected
    case userTyped
}

enum InputDisplayState {
    case hidden
    case collapsed
    case expanded
}

enum UnifiedToggleInputIntent {
    case showCollapsed
    case showExpanded
    case hide
}

// MARK: - Coordinator

/// Pure state machine managing the unified toggle input lifecycle and FE bridge via `AIChatInputBoxHandling`.
/// Drives the view controller through `UnifiedToggleInputViewControllerDelegate` and emits
/// `UnifiedToggleInputIntent`s for MainVC to manage container-level layout (visibility, keyboard constraints).
///
/// Does not access the view hierarchy directly — all UI manipulation goes through the view controller.
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
    weak var delegate: UnifiedToggleInputDelegate?

    private(set) var displayState: InputDisplayState = .hidden
    private(set) var textState: InputTextState = .empty
    private(set) var inputMode: TextEntryMode = .aiChat

    var currentText: String { viewController.text }
    var hasActiveChat: Bool { boundUserScript != nil }

    private weak var boundUserScript: AIChatUserScript?

    private let intentSubject = PassthroughSubject<UnifiedToggleInputIntent, Never>()
    var intentPublisher: AnyPublisher<UnifiedToggleInputIntent, Never> {
        intentSubject.eraseToAnyPublisher()
    }

    private let textChangeSubject = PassthroughSubject<String, Never>()
    var textChangePublisher: AnyPublisher<String, Never> {
        textChangeSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    init() {
        viewController = UnifiedToggleInputViewController()
        viewController.delegate = self
    }

    // MARK: - Tab Binding

    func bindToTab(_ userScript: AIChatUserScript) {
        guard boundUserScript !== userScript else { return }
        boundUserScript?.inputBoxHandler = nil
        boundUserScript = userScript
        userScript.inputBoxHandler = self
    }

    func unbind() {
        boundUserScript?.inputBoxHandler = nil
        boundUserScript = nil
        resetInputState()
    }

    // MARK: - Display State Management

    func showCollapsed() {
        displayState = .collapsed
        viewController.setExpanded(false, animated: false)
        viewController.deactivateInput()
        intentSubject.send(.showCollapsed)
    }

    func showExpanded(prefilledText: String? = nil, inputMode: TextEntryMode = .aiChat) {
        displayState = .expanded
        self.inputMode = inputMode
        viewController.setInputMode(inputMode, animated: false)

        if let prefilledText, !prefilledText.isEmpty {
            viewController.text = prefilledText
            textState = .prefilledSelected
        }

        viewController.setExpanded(true, animated: false)
        intentSubject.send(.showExpanded)
        viewController.activateInput()

        if textState == .prefilledSelected {
            DispatchQueue.main.async { [weak self] in
                self?.viewController.selectAllText()
            }
        }
    }

    func hide() {
        displayState = .hidden
        viewController.deactivateInput()
        viewController.setExpanded(false, animated: false)
        intentSubject.send(.hide)
    }

    // MARK: - Private

    private func resetInputState() {
        viewController.text = ""
        textState = .empty
        aiChatStatus = .unknown
        aiChatInputBoxVisibility = .unknown
    }
}

// MARK: - UnifiedToggleInputViewControllerDelegate

extension UnifiedToggleInputCoordinator: UnifiedToggleInputViewControllerDelegate {

    func unifiedToggleInputVCDidTapWhileCollapsed(_ vc: UnifiedToggleInputViewController) {
        showExpanded(inputMode: .aiChat)
    }

    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didSubmitText text: String, mode: TextEntryMode) {
        vc.text = ""
        textState = .empty

        switch mode {
        case .search:
            delegate?.unifiedToggleInputDidSubmitQuery(text)
            didSubmitQuery.send(text)
        case .aiChat:
            showCollapsed()
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
    }

    func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didChangeMode mode: TextEntryMode) {
        inputMode = mode
    }

    func unifiedToggleInputVCDidTapVoice(_ vc: UnifiedToggleInputViewController) {
        delegate?.unifiedToggleInputDidRequestVoiceSearch()
    }
}
