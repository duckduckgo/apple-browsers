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
        didSet { updateButtonState() }
    }

    var isExpanded: Bool = false {
        didSet { updateButtonState() }
    }

    var isVoiceSearchEnabled: Bool {
        didSet { updateButtonState() }
    }

    var isToggleEnabled: Bool {
        didSet { updateButtonState() }
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
        self.isVoiceSearchEnabled = isVoiceSearchEnabled
        self.isToggleEnabled = isToggleEnabled
        updateButtonState()
    }

    // MARK: - SwitchBarHandling — Methods

    func updateCurrentText(_ text: String) {
        currentText = text
        updateButtonState()
    }

    func submitText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        textSubmissionSubject.send((text: trimmed, mode: currentToggleState))
    }

    func setToggleState(_ state: TextEntryMode) {
        currentToggleState = state
        updateButtonState()
    }

    func clearText() {
        updateCurrentText("")
    }

    func microphoneButtonTapped() {
        microphoneButtonTappedSubject.send()
    }

    func markUserInteraction() {
        hasUserInteractedWithText = true
    }

    func clearButtonTapped() {
        clearButtonTappedSubject.send()
    }

    func searchGoToButtonTapped() {
        searchGoToButtonTappedSubject.send()
    }

    func stopGeneratingButtonTapped() {
        stopGeneratingButtonTappedSubject.send()
    }

    func customizeResponsesButtonTapped() {
        customizeResponsesButtonTappedSubject.send()
    }

    func updateBarPosition(isTop: Bool) {}

    // MARK: - Private

    private func updateButtonState() {
        if isGenerating && !isExpanded && currentToggleState == .aiChat && !isToggleEnabled {
            buttonState = .stopGeneratingAndSearchGoTo
        } else if isGenerating && !isExpanded && currentToggleState == .aiChat {
            buttonState = .stopGeneratingOnly
        } else if !currentText.isEmpty {
            buttonState = .clearOnly
        } else if !isToggleEnabled && currentToggleState == .aiChat && !isExpanded {
            buttonState = isVoiceSearchEnabled ? .voiceAndSearchGoTo : .searchGoToOnly
        } else if isVoiceSearchEnabled {
            buttonState = .voiceOnly
        } else {
            buttonState = .noButtons
        }
    }
}
