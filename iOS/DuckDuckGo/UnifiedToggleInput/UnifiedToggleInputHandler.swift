//
//  UnifiedToggleInputHandler.swift
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

import Combine
import Core
import Foundation

/// Bridges `UnifiedToggleInput` state to `SwitchBarHandling` so `SwitchBarTextEntryView`
/// can be used directly. Any future improvements to the switchbar text entry are inherited automatically.
final class UnifiedToggleInputHandler: SwitchBarHandling {

    // MARK: - SwitchBarHandling — Fixed Values

    private(set) var isTopBarPosition: Bool = false
    let isUsingExpandedBottomBarHeight: Bool = false
    let usesExpandedAIChatTextEntryLayout: Bool = true
    /// The UTI uses the new layout metrics (insets / heights), never the legacy ones.
    let usesLegacyLayoutMetrics: Bool = false
    /// The fadeOutOnToggle experiment applies only to the OmniBar editing state, not here.
    let isUsingFadeOutAnimation: Bool = false
    let shouldDisableAutocorrectOnEmpty: Bool = true
    var modeParameters: [String: String] { ["mode": currentToggleState.rawValue] }
    var isFireTab: Bool

    // MARK: - SwitchBarHandling — Dynamic State

    @Published private(set) var currentText: String = ""
    @Published private(set) var currentToggleState: TextEntryMode = .aiChat
    @Published private(set) var buttonState: SwitchBarButtonState = .noButtons
    @Published private(set) var hasUserInteractedWithText: Bool = false
    @Published private(set) var isCurrentTextValidURL: Bool = false
    @Published var hasSubmittedPrompt: Bool = false
    @Published var submitsAIChatOnKeyboardReturn: Bool = false

    var hasSubmittedPromptPublisher: AnyPublisher<Bool, Never> {
        $hasSubmittedPrompt.eraseToAnyPublisher()
    }

    var submitsAIChatOnKeyboardReturnPublisher: AnyPublisher<Bool, Never> {
        $submitsAIChatOnKeyboardReturn.eraseToAnyPublisher()
    }

    var isGenerating: Bool = false {
        didSet {
            guard isGenerating != oldValue else { return }
            updateButtonState()
        }
    }

    /// When true, the stop-generating button is suppressed regardless of generating state.
    var isOnboardingLocked: Bool = false {
        didSet {
            guard isOnboardingLocked != oldValue else { return }
            updateButtonState()
        }
    }

    var isExpanded: Bool = false {
        didSet {
            guard isExpanded != oldValue else { return }
            updateButtonState()
        }
    }

    var isVoiceSearchEnabled: Bool {
        didSet {
            guard isVoiceSearchEnabled != oldValue else { return }
            updateButtonState()
        }
    }

    var isAIVoiceChatEnabled: Bool = false {
        didSet {
            guard isAIVoiceChatEnabled != oldValue else { return }
            updateButtonState()
        }
    }

    var hidesVoiceButton: Bool = false {
        didSet {
            guard hidesVoiceButton != oldValue else { return }
            updateButtonState()
        }
    }

    var isToggleEnabled: Bool {
        didSet {
            guard isToggleEnabled != oldValue else { return }
            updateButtonState()
        }
    }

    var isAIChatShortcutAvailable: Bool = false {
        didSet {
            guard isAIChatShortcutAvailable != oldValue else { return }
            updateButtonState()
        }
    }

    // MARK: - SwitchBarHandling — Publishers

    var currentTextPublisher: AnyPublisher<String, Never> {
        $currentText.eraseToAnyPublisher()
    }

    var toggleStatePublisher: AnyPublisher<TextEntryMode, Never> {
        $currentToggleState.eraseToAnyPublisher()
    }

    var hasUserInteractedWithTextPublisher: AnyPublisher<Bool, Never> {
        $hasUserInteractedWithText.eraseToAnyPublisher()
    }

    var isCurrentTextValidURLPublisher: AnyPublisher<Bool, Never> {
        $isCurrentTextValidURL.eraseToAnyPublisher()
    }

    var currentButtonStatePublisher: AnyPublisher<SwitchBarButtonState, Never> {
        $buttonState.eraseToAnyPublisher()
    }

    private let textSubmissionSubject = PassthroughSubject<(text: String, mode: TextEntryMode), Never>()
    var textSubmissionPublisher: AnyPublisher<(text: String, mode: TextEntryMode), Never> {
        textSubmissionSubject.eraseToAnyPublisher()
    }

    private let microphoneButtonTappedSubject = PassthroughSubject<Void, Never>()
    var microphoneButtonTappedPublisher: AnyPublisher<Void, Never> {
        microphoneButtonTappedSubject.eraseToAnyPublisher()
    }

    private let aiVoiceChatButtonTappedSubject = PassthroughSubject<Void, Never>()
    var aiVoiceChatButtonTappedPublisher: AnyPublisher<Void, Never> {
        aiVoiceChatButtonTappedSubject.eraseToAnyPublisher()
    }

    private let clearButtonTappedSubject = PassthroughSubject<Void, Never>()
    var clearButtonTappedPublisher: AnyPublisher<Void, Never> {
        clearButtonTappedSubject.eraseToAnyPublisher()
    }

    private let stopGeneratingButtonTappedSubject = PassthroughSubject<Void, Never>()
    var stopGeneratingButtonTappedPublisher: AnyPublisher<Void, Never> {
        stopGeneratingButtonTappedSubject.eraseToAnyPublisher()
    }

    private let customizeResponsesButtonTappedSubject = PassthroughSubject<Void, Never>()
    var customizeResponsesButtonTappedPublisher: AnyPublisher<Void, Never> {
        customizeResponsesButtonTappedSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    init(isVoiceSearchEnabled: Bool,
         isToggleEnabled: Bool = true,
         isAIChatShortcutAvailable: Bool = false,
         isFireTab: Bool = false) {
        self.isVoiceSearchEnabled = isVoiceSearchEnabled
        self.isToggleEnabled = isToggleEnabled
        self.isAIChatShortcutAvailable = isAIChatShortcutAvailable
        self.isFireTab = isFireTab
        updateButtonState()
    }

    // MARK: - SwitchBarHandling — Methods

    func updateCurrentText(_ text: String) {
        guard currentText != text else { return }
        currentText = text
        isCurrentTextValidURL = URL.isValidAddressBarURLInput(text)
        updateButtonState()
    }

    func submitText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        textSubmissionSubject.send((text: trimmed, mode: currentToggleState))
    }

    func submitAIChatAttachmentOnlyPrompt() {
        textSubmissionSubject.send((text: "", mode: .aiChat))
    }

    func setToggleState(_ state: TextEntryMode) {
        guard currentToggleState != state else { return }
        currentToggleState = state
        updateButtonState()
    }

    func clearText() {
        updateCurrentText("")
    }

    func microphoneButtonTapped() {
        microphoneButtonTappedSubject.send()
    }

    func aiVoiceChatButtonTapped() {
        aiVoiceChatButtonTappedSubject.send()
    }

    func markUserInteraction() {
        guard !hasUserInteractedWithText else { return }
        hasUserInteractedWithText = true
    }

    func resetInteractionState() {
        guard hasUserInteractedWithText else { return }
        hasUserInteractedWithText = false
    }

    func clearButtonTapped() {
        clearButtonTappedSubject.send()
    }

    func stopGeneratingButtonTapped() {
        stopGeneratingButtonTappedSubject.send()
    }

    func customizeResponsesButtonTapped() {
        customizeResponsesButtonTappedSubject.send()
    }

    func updateBarPosition(isTop: Bool) {
        guard isTopBarPosition != isTop else { return }
        isTopBarPosition = isTop
        updateButtonState()
    }

    // MARK: - Private

    private func updateButtonState() {
        let aiVoiceChatAvailable = !isExpanded && isAIVoiceChatEnabled && currentToggleState == .aiChat
        let voiceAvailable = !hidesVoiceButton && (isVoiceSearchEnabled || aiVoiceChatAvailable)
        let nextButtonState: SwitchBarButtonState

        if isGenerating && !isExpanded && currentToggleState == .aiChat && !isOnboardingLocked {
            nextButtonState = .stopGeneratingOnly
        } else if !currentText.isEmpty && !isToggleEnabled && currentToggleState == .search && isAIChatShortcutAvailable {
            nextButtonState = .clearAndAIChatShortcut
        } else if !currentText.isEmpty {
            nextButtonState = .clearOnly
        } else if !isToggleEnabled && currentToggleState == .search && isAIChatShortcutAvailable {
            nextButtonState = voiceAvailable ? .voiceAndAIChatShortcut : .aiChatShortcutOnly
        } else if voiceAvailable {
            nextButtonState = .voiceOnly
        } else {
            nextButtonState = .noButtons
        }

        guard buttonState != nextButtonState else { return }
        buttonState = nextButtonState
    }
}
