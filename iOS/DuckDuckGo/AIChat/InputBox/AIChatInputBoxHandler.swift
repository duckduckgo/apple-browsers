//
//  AIChatInputBoxHandler.swift
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
import SwiftUI

protocol AIChatInputBoxHandling {
    // Publishers
    var didPressFireButton: PassthroughSubject<Void, Never> { get }
    var didPressNewChatButton: PassthroughSubject<Void, Never> { get }
    var didSubmitText: PassthroughSubject<String, Never> { get }
    var didPressStopGeneratingButton: PassthroughSubject<Void, Never> { get }

    var aiChatStatus: AIChatStatusValue { get set }
    var aiChatInputBoxVisibility: AIChatInputBoxVisibility { get set }

    // Methods
    func fireButtonPressed()
    func newChatButtonPressed()
    func submitText(_ text: String)
}

enum AIChatStatusValue: String, Codable {
    case startStreamNewPrompt = "start_stream:new_prompt"
    case loading
    case streaming
    case error
    case ready
    case blocked
    case unknown
}

enum AIChatInputBoxVisibility: String, Codable {
    case hidden
    case visible
    case unknown
}

struct AIChatStatus: Codable {
    let status: AIChatStatusValue
}

final class AIChatInputBoxHandler: AIChatInputBoxHandling {
    let didPressFireButton = PassthroughSubject<Void, Never>()
    let didPressNewChatButton = PassthroughSubject<Void, Never>()
    let didPressStopGeneratingButton = PassthroughSubject<Void, Never>()
    let didSubmitText = PassthroughSubject<String, Never>()

    @MainActor
    var aiChatInputBoxVisibility: AIChatInputBoxVisibility = .unknown {
        didSet {
            inputBoxViewModel.visibility = aiChatInputBoxVisibility
        }
    }

    @MainActor
    var aiChatStatus: AIChatStatusValue = .unknown {
        didSet {
            updateStatus()
        }
    }

    private let inputBoxViewModel: AIChatInputBoxViewModel
    private var cancellables = Set<AnyCancellable>()

    init(inputBoxViewModel: AIChatInputBoxViewModel) {
        self.inputBoxViewModel = inputBoxViewModel
        setupBindings()
    }

    // MARK: - Private Methods
    private func setupBindings() {
        inputBoxViewModel.didPressFireButton
            .sink { [weak self] in
                self?.didPressFireButton.send()
            }
            .store(in: &cancellables)

        inputBoxViewModel.didPressNewChatButton
            .sink { [weak self] in
                self?.didPressNewChatButton.send()
            }
            .store(in: &cancellables)

        inputBoxViewModel.didSubmitText
            .sink { [weak self] text in
                self?.didSubmitText.send(text)
            }
            .store(in: &cancellables)

        inputBoxViewModel.didPressStopGenerating
            .sink { [weak self] _ in
                self?.didPressStopGeneratingButton.send()
            }
            .store(in: &cancellables)
    }

    @MainActor
    private func updateStatus() {
        withAnimation {
            switch aiChatStatus {
            case .startStreamNewPrompt, .error, .ready, .blocked:
                inputBoxViewModel.state = .ready
            case .loading, .streaming:
                inputBoxViewModel.state = .waitingForGeneration
            case .unknown:
                inputBoxViewModel.state = .unknown
            }
        }
    }

    // MARK: - Public Methods
    func fireButtonPressed() {
        inputBoxViewModel.fireButtonPressed()
    }

    func newChatButtonPressed() {
        inputBoxViewModel.newChatButtonPressed()
    }

    func submitText(_ text: String) {
        inputBoxViewModel.submitText(text)
    }
}
