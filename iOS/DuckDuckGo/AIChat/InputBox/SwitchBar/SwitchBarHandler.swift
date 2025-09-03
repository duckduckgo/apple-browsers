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
import UIKit
import AIChat

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
    var clearButtonTappedPublisher: AnyPublisher<Void, Never> { get }
    var hasUserInteractedWithTextPublisher: AnyPublisher<Bool, Never> { get }
    var isCurrentTextValidURLPublisher: AnyPublisher<Bool, Never> { get }

    // MARK: - Methods
    func updateCurrentText(_ text: String)
    func submitText(_ text: String)
    func setToggleState(_ state: TextEntryMode)
    func clearText()
    func microphoneButtonTapped()
    func markUserInteraction()
    func clearButtonTapped()
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
    private let aiChatSettings: AIChatSettingsProvider
    private let funnelState: SwitchBarFunnelProviding

    // MARK: - Published Properties
    @Published private(set) var currentText: String = ""
    @Published private(set) var currentToggleState: TextEntryMode = .search
    @Published private(set) var hasUserInteractedWithText: Bool = false
    @Published private(set) var isCurrentTextValidURL: Bool = false
    
    // MARK: - Mode Usage Detection
    private static var hasUsedSearchInSession = false
    private static var hasUsedAIChatInSession = false

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

    var clearButtonTappedPublisher: AnyPublisher<Void, Never> {
        clearButtonTappedSubject.eraseToAnyPublisher()
    }

    private let textSubmissionSubject = PassthroughSubject<(text: String, mode: TextEntryMode), Never>()
    private let microphoneButtonTappedSubject = PassthroughSubject<Void, Never>()
    private let clearButtonTappedSubject = PassthroughSubject<Void, Never>()
    private var backgroundObserver: NSObjectProtocol?

    init(voiceSearchHelper: VoiceSearchHelperProtocol, storage: KeyValueStoring, aiChatSettings: AIChatSettingsProvider, funnelState: SwitchBarFunnelProviding = SwitchBarFunnel(storage: UserDefaults.standard)) {
        self.voiceSearchHelper = voiceSearchHelper
        self.storage = storage
        self.aiChatSettings = aiChatSettings
        self.funnelState = funnelState
        
        // Set up app lifecycle observers to reset session flags
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            Self.resetSessionFlags()
        }
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
        
        // Process funnel step
        processSubmissionFunnelStep(mode: currentToggleState)
        
        updateModeUsage(currentToggleState)
        textSubmissionSubject.send((text: trimmed, mode: currentToggleState))
    }

    func setToggleState(_ state: TextEntryMode) {
        // Only fire pixel if the state is actually changing
        let isStateChanging = currentToggleState != state
        
        currentToggleState = state
        saveToggleState()
        
        if isStateChanging {
            Pixel.fire(pixel: .aiChatExperimentalOmnibarModeSwitched)
        }
    }

    func clearText() {
        updateCurrentText("")
    }

    func microphoneButtonTapped() {
        microphoneButtonTappedSubject.send(())
    }

    func markUserInteraction() {
        let isFirstInteraction = !hasUserInteractedWithText
        hasUserInteractedWithText = true
        
        // Process first interaction funnel step (if this is the first text interaction in this session)
        if isFirstInteraction {
            funnelState.processStep(.firstInteraction)
        }
    }

    func clearButtonTapped() {
        clearButtonTappedSubject.send(())
    }
    
    
    /// Process funnel step when user submits text
    private func processSubmissionFunnelStep(mode: TextEntryMode) {
        switch mode {
        case .search:
            funnelState.processStep(.searchSubmitted)
        case .aiChat:
            funnelState.processStep(.promptSubmitted)
        }
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
    
    deinit {
        if let observer = backgroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Session Management
    private static func resetSessionFlags() {
        hasUsedSearchInSession = false
        hasUsedAIChatInSession = false
    }
    
    // MARK: - Mode Usage Detection  
    private func updateModeUsage(_ mode: TextEntryMode) {
        let previouslyUsedBothModes = Self.hasUsedSearchInSession && Self.hasUsedAIChatInSession
        
        switch mode {
        case .search:
            Self.hasUsedSearchInSession = true
        case .aiChat:
            Self.hasUsedAIChatInSession = true
        }
        
        // Fire pixel only when user achieves both-mode usage for the first time in this session
        let nowUsesBothModes = Self.hasUsedSearchInSession && Self.hasUsedAIChatInSession
        if nowUsesBothModes && !previouslyUsedBothModes {
            DailyPixel.fireDailyAndCount(pixel: .aiChatExperimentalOmnibarSessionBothModes)
        }
    }
}
