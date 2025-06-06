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
import AIChat

final class AIChatInputBoxHandler: AIChatInputBoxHandling {
    let didPressFireButton = PassthroughSubject<Void, Never>()
    let didPressNewChatButton = PassthroughSubject<Void, Never>()
    let didPressStopGeneratingButton = PassthroughSubject<Void, Never>()
    let didSubmitPrompt = PassthroughSubject<String, Never>()
    let didSubmitQuery = PassthroughSubject<String, Never>()

    @MainActor @Published var aiChatInputBoxVisibility: AIChatInputBoxVisibility = .unknown {
        didSet {
            inputBoxViewModel.visibility = aiChatInputBoxVisibility
        }
    }

    @MainActor @Published var aiChatStatus: AIChatStatusValue = .unknown {
        didSet {
            updateStatus()
        }
    }

    var aiChatStatusPublisher: Published<AIChatStatusValue>.Publisher { $aiChatStatus }
    var aiChatInputBoxVisibilityPublisher: Published<AIChatInputBoxVisibility>.Publisher { $aiChatInputBoxVisibility }

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

        inputBoxViewModel.didSubmitQuery
            .sink { [weak self] text in
                self?.didSubmitQuery.send(text)
            }
            .store(in: &cancellables)

        inputBoxViewModel.didSubmitPrompt
            .sink { [weak self] text in
                self?.didSubmitPrompt.send(text)
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
}
