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
import Foundation
import os.log

private let utiLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.duckduckgo", category: "UTI")

/// Bridges `UnifiedToggleInput` state to `SwitchBarHandling` so `SwitchBarTextEntryView`
/// can be used directly. Any future improvements to the switchbar text entry are inherited automatically.
final class UnifiedToggleInputHandler: SwitchBarHandling {

    // MARK: - SwitchBarHandling — Fixed Values

    var isTopBarPosition: Bool = false
    let isUsingExpandedBottomBarHeight: Bool = false
    /// The fadeOutOnToggle experiment applies only to the OmniBar editing state, not here.
    let isUsingFadeOutAnimation: Bool = false
    let isCurrentTextValidURL: Bool = false
    let modeParameters: [String: String] = [:]
    var isFireTab: Bool = false // TODO: - Handle injecting and updating this. And customizing the new tinput view for fire tabs.

    // MARK: - SwitchBarHandling — Dynamic State

    @Published private(set) var currentText: String = ""
    @Published private(set) var currentToggleState: TextEntryMode = .aiChat
    @Published private(set) var buttonState: SwitchBarButtonState = .noButtons
    @Published private(set) var hasUserInteractedWithText: Bool = false
    @Published var hasSubmittedPrompt: Bool = false

    var hasSubmittedPromptPublisher: AnyPublisher<Bool, Never> {
        $hasSubmittedPrompt.eraseToAnyPublisher()
    }

    var isGenerating: Bool = false {
        didSet {
            utiLog.debug("Handler.isGenerating - \(oldValue, privacy: .public) → \(self.isGenerating, privacy: .public)")
            updateButtonState()
        }
    }

    var isExpanded: Bool = false {
        didSet {
            utiLog.debug("Handler.isExpanded - \(oldValue, privacy: .public) → \(self.isExpanded, privacy: .public)")
            updateButtonState()
        }
    }

    var isVoiceSearchEnabled: Bool {
        didSet {
            utiLog.debug("Handler.isVoiceSearchEnabled - \(oldValue, privacy: .public) → \(self.isVoiceSearchEnabled, privacy: .public)")
            updateButtonState()
        }
    }

    var isAIVoiceChatEnabled: Bool = false {
        didSet {
            utiLog.debug("Handler.isAIVoiceChatEnabled - \(oldValue, privacy: .public) → \(self.isAIVoiceChatEnabled, privacy: .public)")
            updateButtonState()
        }
    }

    var hidesVoiceButton: Bool = false {
        didSet {
            utiLog.debug("Handler.hidesVoiceButton - \(oldValue, privacy: .public) → \(self.hidesVoiceButton, privacy: .public)")
            updateButtonState()
        }
    }

    var isToggleEnabled: Bool {
        didSet {
            utiLog.debug("Handler.isToggleEnabled - \(oldValue, privacy: .public) → \(self.isToggleEnabled, privacy: .public)")
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
        Just(false).eraseToAnyPublisher()
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

    private let clearButtonTappedSubject = PassthroughSubject<Void, Never>()
    var clearButtonTappedPublisher: AnyPublisher<Void, Never> {
        clearButtonTappedSubject.eraseToAnyPublisher()
    }

    private let searchGoToButtonTappedSubject = PassthroughSubject<Void, Never>()
    var searchGoToButtonTappedPublisher: AnyPublisher<Void, Never> {
        searchGoToButtonTappedSubject.eraseToAnyPublisher()
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

    init(isVoiceSearchEnabled: Bool, isToggleEnabled: Bool = true) {
        utiLog.debug("Handler.init - isVoiceSearchEnabled: \(isVoiceSearchEnabled, privacy: .public), isToggleEnabled: \(isToggleEnabled, privacy: .public)")
        self.isVoiceSearchEnabled = isVoiceSearchEnabled
        self.isToggleEnabled = isToggleEnabled
        updateButtonState()
    }

    // MARK: - SwitchBarHandling — Methods

    func updateCurrentText(_ text: String) {
        utiLog.debug("Handler.updateCurrentText - length: \(text.count, privacy: .public)")
        currentText = text
        utiLog.debug("Handler.updateCurrentText → calling updateButtonState")
        updateButtonState()
    }

    func submitText(_ text: String) {
        utiLog.debug("Handler.submitText - mode: \(String(describing: self.currentToggleState), privacy: .public)")
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            utiLog.debug("Handler.submitText ↩️ guard: trimmed text is empty")
            return
        }
        utiLog.debug("Handler.submitText → sending textSubmission, mode=\(String(describing: self.currentToggleState), privacy: .public)")
        textSubmissionSubject.send((text: trimmed, mode: currentToggleState))
    }

    func setToggleState(_ state: TextEntryMode) {
        utiLog.debug("Handler.setToggleState - \(String(describing: self.currentToggleState), privacy: .public) → \(String(describing: state), privacy: .public)")
        currentToggleState = state
        updateButtonState()
    }

    func clearText() {
        utiLog.debug("Handler.clearText")
        updateCurrentText("")
    }

    func microphoneButtonTapped() {
        utiLog.debug("Handler.microphoneButtonTapped")
        microphoneButtonTappedSubject.send()
    }

    func markUserInteraction() {
        utiLog.debug("Handler.markUserInteraction")
        hasUserInteractedWithText = true
    }

    func clearButtonTapped() {
        utiLog.debug("Handler.clearButtonTapped")
        clearButtonTappedSubject.send()
    }

    func searchGoToButtonTapped() {
        utiLog.debug("Handler.searchGoToButtonTapped")
        searchGoToButtonTappedSubject.send()
    }

    func stopGeneratingButtonTapped() {
        utiLog.debug("Handler.stopGeneratingButtonTapped")
        stopGeneratingButtonTappedSubject.send()
    }

    func customizeResponsesButtonTapped() {
        utiLog.debug("Handler.customizeResponsesButtonTapped")
        customizeResponsesButtonTappedSubject.send()
    }

    func updateBarPosition(isTop: Bool) {
        utiLog.debug("Handler.updateBarPosition - isTop: \(isTop, privacy: .public)")
    }

    // MARK: - Private

    private func updateButtonState() {
        let oldButtonState = buttonState
        let voiceAvailable = !hidesVoiceButton && isVoiceSearchEnabled && !(isAIVoiceChatEnabled && currentToggleState == .aiChat)
        utiLog.debug("Handler.updateButtonState - voiceAvailable=\(voiceAvailable, privacy: .public), isGenerating=\(self.isGenerating, privacy: .public), isExpanded=\(self.isExpanded, privacy: .public), isToggleEnabled=\(self.isToggleEnabled, privacy: .public), textEmpty=\(self.currentText.isEmpty, privacy: .public)")

        if isGenerating && !isExpanded && currentToggleState == .aiChat && !isToggleEnabled {
            utiLog.debug("Handler.updateButtonState 🔀 generating+collapsed+aiChat+noToggle → stopGeneratingAndSearchGoTo")
            buttonState = .stopGeneratingAndSearchGoTo
        } else if isGenerating && !isExpanded && currentToggleState == .aiChat {
            utiLog.debug("Handler.updateButtonState 🔀 generating+collapsed+aiChat → stopGeneratingOnly")
            buttonState = .stopGeneratingOnly
        } else if !currentText.isEmpty {
            utiLog.debug("Handler.updateButtonState 🔀 hasText → clearOnly")
            buttonState = .clearOnly
        } else if !isToggleEnabled && currentToggleState == .aiChat && !isExpanded {
            utiLog.debug("Handler.updateButtonState 🔀 noToggle+aiChat+collapsed, voiceAvailable=\(voiceAvailable, privacy: .public)")
            buttonState = voiceAvailable ? .voiceAndSearchGoTo : .searchGoToOnly
        } else if voiceAvailable {
            utiLog.debug("Handler.updateButtonState 🔀 voiceAvailable → voiceOnly")
            buttonState = .voiceOnly
        } else {
            utiLog.debug("Handler.updateButtonState 🔀 fallthrough → noButtons")
            buttonState = .noButtons
        }
        utiLog.debug("Handler.updateButtonState - \(String(describing: oldButtonState), privacy: .public) → \(String(describing: self.buttonState), privacy: .public)")
    }
}
