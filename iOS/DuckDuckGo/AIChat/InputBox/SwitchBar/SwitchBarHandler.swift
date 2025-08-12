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
import Persistence
import Core

// MARK: - TextEntryMode Enum
public enum TextEntryMode: String, CaseIterable {
    case search
    case aiChat
}

// MARK: - SwitchBarHandling Protocol
protocol SwitchBarHandling: AnyObject {

    // MARK: - Published Properties
    var currentText: String { get }
    var currentToggleState: TextEntryMode { get }
    var isVoiceSearchEnabled: Bool { get }
    var hasUserInteractedWithText: Bool { get }
    var isCurrentTextValidURL: Bool { get }

    var currentTextPublisher: AnyPublisher<String, Never> { get }
    var toggleStatePublisher: AnyPublisher<TextEntryMode, Never> { get }
    var textSubmissionPublisher: AnyPublisher<(text: String, mode: TextEntryMode), Never> { get }
    var microphoneButtonTappedPublisher: AnyPublisher<Void, Never> { get }
    var hasUserInteractedWithTextPublisher: AnyPublisher<Bool, Never> { get }
    var isCurrentTextValidURLPublisher: AnyPublisher<Bool, Never> { get }

    // MARK: - Methods
    func updateCurrentText(_ text: String)
    func submitText(_ text: String)
    func setToggleState(_ state: TextEntryMode)
    func clearText()
    func microphoneButtonTapped()
    func markUserInteraction()
}

// MARK: - SwitchBarHandler Implementation
final class SwitchBarHandler: SwitchBarHandling {

    // MARK: - Constants
    private enum StorageKey {
        static let toggleState = "SwitchBarHandler.toggleState"
    }

    // MARK: - Dependencies
    private let voiceSearchHelper: VoiceSearchHelperProtocol
    private let storage: KeyValueStoring

    // MARK: - Published Properties
    @Published private(set) var currentText: String = ""
    @Published private(set) var currentToggleState: TextEntryMode = .search
    @Published private(set) var hasUserInteractedWithText: Bool = false
    @Published private(set) var isCurrentTextValidURL: Bool = false

    var isVoiceSearchEnabled: Bool {
        voiceSearchHelper.isVoiceSearchEnabled
    }

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

    var textSubmissionPublisher: AnyPublisher<(text: String, mode: TextEntryMode), Never> {
        textSubmissionSubject.eraseToAnyPublisher()
    }

    var microphoneButtonTappedPublisher: AnyPublisher<Void, Never> {
        microphoneButtonTappedSubject.eraseToAnyPublisher()
    }

    private let textSubmissionSubject = PassthroughSubject<(text: String, mode: TextEntryMode), Never>()
    private let microphoneButtonTappedSubject = PassthroughSubject<Void, Never>()

    init(voiceSearchHelper: VoiceSearchHelperProtocol, storage: KeyValueStoring) {
        self.voiceSearchHelper = voiceSearchHelper
        self.storage = storage
    }

    // MARK: - SwitchBarHandling Implementation
    func updateCurrentText(_ text: String) {
        currentText = text
        /// URL.webUrl converts spaces to %20, but this is not a concern in this context, as we are validating the user's input in the address bar to ensure it is a valid URL.
        isCurrentTextValidURL = !text.contains(where: { $0.isWhitespace }) && URL.webUrl(from: text) != nil
    }

    func submitText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        textSubmissionSubject.send((text: trimmed, mode: currentToggleState))
    }

    func setToggleState(_ state: TextEntryMode) {
        currentToggleState = state
        saveToggleState()
    }

    func clearText() {
        updateCurrentText("")
    }

    func microphoneButtonTapped() {
        microphoneButtonTappedSubject.send(())
    }

    func markUserInteraction() {
        hasUserInteractedWithText = true
    }

    func saveToggleState() {
        storage.set(currentToggleState.rawValue, forKey: StorageKey.toggleState)
    }

    /// Intentionally not called yet, https://app.asana.com/1/137249556945/project/72649045549333/task/1210814996510636?focus=true
    func restoreToggleState() {
        if let storedValue = storage.object(forKey: StorageKey.toggleState) as? String,
           let restoredState = TextEntryMode(rawValue: storedValue) {
            currentToggleState = restoredState
        }
    }
}
