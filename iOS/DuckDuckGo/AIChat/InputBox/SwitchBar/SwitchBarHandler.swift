//
//  SwitchBarHandler.swift
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

import Foundation
import Combine

// MARK: - TextEntryMode Enum
public enum TextEntryMode {
    case search
    case aiChat
}

// MARK: - SwitchBarHandling Protocol
protocol SwitchBarHandling: AnyObject {

    // MARK: - Published Properties
    var currentText: String { get }
    var currentToggleState: TextEntryMode { get }

    var currentTextPublisher: AnyPublisher<String, Never> { get }
    var toggleStatePublisher: AnyPublisher<TextEntryMode, Never> { get }
    var textSubmissionPublisher: AnyPublisher<(text: String, mode: TextEntryMode), Never> { get }

    // MARK: - Methods
    func updateCurrentText(_ text: String)
    func submitText(_ text: String)
    func setToggleState(_ state: TextEntryMode)
    func clearText()
}

// MARK: - SwitchBarHandler Implementation
final class SwitchBarHandler: SwitchBarHandling {

    // MARK: - Published Properties
    @Published private(set) var currentText: String = ""
    @Published private(set) var currentToggleState: TextEntryMode = .search

    var currentTextPublisher: AnyPublisher<String, Never> {
        $currentText.eraseToAnyPublisher()
    }

    var toggleStatePublisher: AnyPublisher<TextEntryMode, Never> {
        $currentToggleState.eraseToAnyPublisher()
    }

    var textSubmissionPublisher: AnyPublisher<(text: String, mode: TextEntryMode), Never> {
        textSubmissionSubject.eraseToAnyPublisher()
    }

    private let textSubmissionSubject = PassthroughSubject<(text: String, mode: TextEntryMode), Never>()

    init() { }

    // MARK: - SwitchBarHandling Implementation
    func updateCurrentText(_ text: String) {
        currentText = text
    }

    func submitText(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        textSubmissionSubject.send((text: text, mode: currentToggleState))
    }

    func setToggleState(_ state: TextEntryMode) {
        currentToggleState = state
    }

    func clearText() {
        updateCurrentText("")
    }
}
