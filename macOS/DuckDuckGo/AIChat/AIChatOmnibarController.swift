//
//  AIChatOmnibarController.swift
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

import Cocoa
import Combine
import AIChat
import URLPredictor
import PixelKit

protocol AIChatOmnibarControllerDelegate: AnyObject {
    func aiChatOmnibarControllerDidSubmit(_ controller: AIChatOmnibarController)
    func aiChatOmnibarController(_ controller: AIChatOmnibarController, didRequestNavigationToURL url: URL)
}

/// Controller that manages the state and actions for the AI Chat omnibar.
/// This controller is shared between AIChatOmnibarContainerViewController and AIChatOmnibarTextContainerViewController
/// to coordinate text input and submission.
final class AIChatOmnibarController {
    @Published private(set) var currentText: String = ""
    weak var delegate: AIChatOmnibarControllerDelegate?
    private let aiChatTabOpener: AIChatTabOpening
    private let promptHandler: AIChatPromptHandler
    private let sharedTextState: AddressBarSharedTextState
    private var cancellables = Set<AnyCancellable>()
    private var isUpdatingFromSharedState = false

    // MARK: - Initialization

    init(
        aiChatTabOpener: AIChatTabOpening,
        sharedTextState: AddressBarSharedTextState,
        promptHandler: AIChatPromptHandler = .shared
    ) {
        self.aiChatTabOpener = aiChatTabOpener
        self.sharedTextState = sharedTextState
        self.promptHandler = promptHandler

        subscribeToSharedTextState()
    }

    // MARK: - Public Methods

    /// Updates the current text being typed by the user
    /// - Parameter text: The new text value
    func updateText(_ text: String) {
        currentText = text
        if !isUpdatingFromSharedState {
            sharedTextState.updateText(text, markInteraction: true)
        }
    }

    // MARK: - Private Methods

    private func subscribeToSharedTextState() {
        sharedTextState.$text
            .sink { [weak self] newText in
                guard let self = self else { return }
                if self.currentText != newText && self.sharedTextState.hasUserInteractedWithText {
                    self.isUpdatingFromSharedState = true
                    self.currentText = newText
                    self.isUpdatingFromSharedState = false
                }
            }
            .store(in: &cancellables)
    }

    func submit() {
        guard !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let trimmedText = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if let navigableURL = classifyAsNavigableURL(trimmedText) {
            PixelKit.fire(AIChatPixel.aiChatAddressBarAIChatSubmitURL, frequency: .dailyAndCount, includeAppVersionParameter: true)
            currentText = ""
            delegate?.aiChatOmnibarController(self, didRequestNavigationToURL: navigableURL)
            return
        }

        PixelKit.fire(AIChatPixel.aiChatAddressBarAIChatSubmitPrompt, frequency: .dailyAndCount, includeAppVersionParameter: true)

        let nativePrompt = AIChatNativePrompt.queryPrompt(trimmedText, autoSubmit: true)
        promptHandler.setData(nativePrompt)

        Task { @MainActor in
            aiChatTabOpener.openAIChatTab(
                with: .query(trimmedText, shouldAutoSubmit: true),
                behavior: .currentTab
            )
        }

        currentText = ""
        delegate?.aiChatOmnibarControllerDidSubmit(self)
    }

    /// Checks if the input text is a navigable URL (not a search query).
    /// Returns the URL if it should be navigated to, nil if it should be treated as an AI chat query.
    private func classifyAsNavigableURL(_ text: String) -> URL? {
        do {
            switch try Classifier.classify(input: text) {
            case .navigate(let url):
                return url
            case .search:
                return nil
            }
        } catch {
            return nil
        }
    }
}
