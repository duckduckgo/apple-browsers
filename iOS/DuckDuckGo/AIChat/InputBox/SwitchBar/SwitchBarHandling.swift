//
//  SwitchBarHandling.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

// MARK: - TextEntryMode Enum
public enum TextEntryMode: String, CaseIterable {
    case search
    case aiChat
}

extension TextEntryMode {
    /// Returns the mode the omnibar should actually display, falling back to `.search` when the AI search-input feature is unavailable.
    func displayed(isAIChatSearchInputEnabled: Bool) -> TextEntryMode {
        isAIChatSearchInputEnabled ? self : .search
    }
}

// MARK: - SwitchBarHandling Protocol
protocol SwitchBarHandling: AnyObject {

    // MARK: - Published Properties
    var currentText: String { get }
    var currentToggleState: TextEntryMode { get }
    var isVoiceSearchEnabled: Bool { get }
    var hasUserInteractedWithText: Bool { get }
    var isCurrentTextValidURL: Bool { get }
    var buttonState: SwitchBarButtonState { get }
    var isTopBarPosition: Bool { get }
    var isToggleEnabled: Bool { get }
    var isFireTab: Bool { get }
    var isImageGenerationSelected: Bool { get }

    var isUsingExpandedBottomBarHeight: Bool { get }
    var isUsingFadeOutAnimation: Bool { get }
    var usesExpandedAIChatTextEntryLayout: Bool { get }
    var usesLegacyLayoutMetrics: Bool { get }
    var shouldDisableAutocorrectOnEmpty: Bool { get }

    /// Suppresses the in-pill voice button — used when an external flank already provides one.
    var hidesVoiceButton: Bool { get set }

    /// A spent Duck.ai allowance: the field takes no more text and no prompt can be sent.
    var isInputBlockedByUsageLimit: Bool { get }

    var hasSubmittedPrompt: Bool { get set }
    var hasSubmittedPromptPublisher: AnyPublisher<Bool, Never> { get }
    var submitsAIChatOnKeyboardReturn: Bool { get }
    var submitsAIChatOnKeyboardReturnPublisher: AnyPublisher<Bool, Never> { get }

    var currentTextPublisher: AnyPublisher<String, Never> { get }
    var toggleStatePublisher: AnyPublisher<TextEntryMode, Never> { get }
    var textSubmissionPublisher: AnyPublisher<(text: String, mode: TextEntryMode), Never> { get }
    var microphoneButtonTappedPublisher: AnyPublisher<Void, Never> { get }
    var clearButtonTappedPublisher: AnyPublisher<Void, Never> { get }
    var hasUserInteractedWithTextPublisher: AnyPublisher<Bool, Never> { get }
    var isCurrentTextValidURLPublisher: AnyPublisher<Bool, Never> { get }
    var currentButtonStatePublisher: AnyPublisher<SwitchBarButtonState, Never> { get }

    // Provide toggle mode parameters. Used in pixels.
    var modeParameters: [String: String] { get }

    // MARK: - Methods
    func updateCurrentText(_ text: String)
    func submitText(_ text: String)
    func setToggleState(_ state: TextEntryMode)
    func saveToggleState()
    func clearText()
    func microphoneButtonTapped()
    func markUserInteraction()
    func clearButtonTapped()
    func stopGeneratingButtonTapped()
    func updateBarPosition(isTop: Bool)
}

extension SwitchBarHandling {
    func saveToggleState() {}
    func stopGeneratingButtonTapped() {}
    var isImageGenerationSelected: Bool { false }
    var usesExpandedAIChatTextEntryLayout: Bool { false }
    var usesLegacyLayoutMetrics: Bool { false }
    var submitsAIChatOnKeyboardReturn: Bool { true }
    var isInputBlockedByUsageLimit: Bool { false }
    var submitsAIChatOnKeyboardReturnPublisher: AnyPublisher<Bool, Never> { Just(true).eraseToAnyPublisher() }
}
