//
//  AIChatInputBoxViewModel.swift
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

final class AIChatInputBoxViewModel: ObservableObject {

    enum ChatState {
        case ready
        case waitingForGeneration
        case unknown
    }

    enum InputMode: String, CaseIterable, Identifiable {
         case search
         case chat = "duck.ai"

         var id: Self { self }
     }

    @Published var inputText: String = ""
    @Published var state: ChatState = .unknown
    @Published var visibility: AIChatInputBoxVisibility = .unknown
    @Published var inputMode: InputMode = .chat {
        didSet {
            removeExtraLines()
        }
    }

    // MARK: - Publishers
    let didPressFireButton = PassthroughSubject<Void, Never>()
    let didPressNewChatButton = PassthroughSubject<Void, Never>()
    let didSubmitPrompt = PassthroughSubject<String, Never>()
    let didSubmitQuery = PassthroughSubject<String, Never>()
    let didPressStopGenerating = PassthroughSubject<Void, Never>()

    // MARK: - Public Methods
    func clearText() {
        inputText = ""
    }

    func fireButtonPressed() {
        didPressFireButton.send()
    }

    func newChatButtonPressed() {
        didPressNewChatButton.send()
    }

    func submitText(_ text: String) {
        if inputMode == .chat {
            didSubmitPrompt.send(text)
        } else {
            didSubmitQuery.send(text)
        }
    }

    func stopGenerating() {
        didPressStopGenerating.send()
    }

    // MARK: - Private Methods
    private func removeExtraLines() {
        /// Should just remove the extra lines in the future, leaving it like this for now
        inputText = ""
    }

}
