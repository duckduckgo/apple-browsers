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
import PrivacyConfig
import enum Common.DevicePlatform

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
    var buttonState: SwitchBarButtonState { get }
    var isTopBarPosition: Bool { get }
    var isToggleEnabled: Bool { get }
    var isFireTab: Bool { get }

    var isUsingExpandedBottomBarHeight: Bool { get }
    var isUsingFadeOutAnimation: Bool { get }

    var hasSubmittedPrompt: Bool { get set }
    var hasSubmittedPromptPublisher: AnyPublisher<Bool, Never> { get }

    var currentTextPublisher: AnyPublisher<String, Never> { get }
    var toggleStatePublisher: AnyPublisher<TextEntryMode, Never> { get }
    var textSubmissionPublisher: AnyPublisher<(text: String, mode: TextEntryMode), Never> { get }
    var microphoneButtonTappedPublisher: AnyPublisher<Void, Never> { get }
    var clearButtonTappedPublisher: AnyPublisher<Void, Never> { get }
    var searchGoToButtonTappedPublisher: AnyPublisher<Void, Never> { get }
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
    func searchGoToButtonTapped()
    func stopGeneratingButtonTapped()
    func updateBarPosition(isTop: Bool)
}

extension SwitchBarHandling {
    func saveToggleState() {}
    func stopGeneratingButtonTapped() {}
}

// MARK: - SwitchBarHandler Implementation
final class SwitchBarHandler: SwitchBarHandling {

    // MARK: - Dependencies
    private let voiceSearchHelper: VoiceSearchHelperProtocol
    private let toggleModeStorage: ToggleModeStoring
    private let aiChatSettings: AIChatSettingsProvider
    private let funnelState: SwitchBarFunnelProviding
    private var sessionStateMetrics: SessionStateMetricsProviding
    private let featureFlagger: FeatureFlagger
    private let voiceShortcutFeature: DuckAIVoiceShortcutFeatureProviding

    // MARK: - Published Properties
    @Published private(set) var currentText: String = ""
    @Published private(set) var currentToggleState: TextEntryMode = .search
    @Published private(set) var hasUserInteractedWithText: Bool = false
    @Published private(set) var isCurrentTextValidURL: Bool = false
    @Published private(set) var buttonState: SwitchBarButtonState = .noButtons

    var hasSubmittedPrompt: Bool = false
    var hasSubmittedPromptPublisher: AnyPublisher<Bool, Never> { Just(false).eraseToAnyPublisher() }

    // MARK: - Mode Usage Detection
    private static var hasUsedSearchInSession = false
    private static var hasUsedAIChatInSession = false

    private(set) var isTopBarPosition: Bool = true
    let isFireTab: Bool

    var isToggleEnabled: Bool {
        return true
    }

    var isUsingExpandedBottomBarHeight: Bool {
        isUsingFadeOutAnimation && !isTopBarPosition
    }

    var isUsingFadeOutAnimation: Bool {
        guard featureFlagger.isFeatureOn(.unifiedToggleInput) else {
            return devicePlatform.isIphone
        }
        return false
    }

    var isVoiceSearchEnabled: Bool {
        voiceSearchHelper.isVoiceSearchEnabled
    }
    
    var modeParameters: [String: String] {
        ["mode": currentToggleState.rawValue]
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

    var searchGoToButtonTappedPublisher: AnyPublisher<Void, Never> {
        searchGoToButtonTappedSubject.eraseToAnyPublisher()
    }

    var currentButtonStatePublisher: AnyPublisher<SwitchBarButtonState, Never> {
        $buttonState.eraseToAnyPublisher()
    }

    private let textSubmissionSubject = PassthroughSubject<(text: String, mode: TextEntryMode), Never>()
    private let microphoneButtonTappedSubject = PassthroughSubject<Void, Never>()
    private let clearButtonTappedSubject = PassthroughSubject<Void, Never>()
    private let searchGoToButtonTappedSubject = PassthroughSubject<Void, Never>()
    private var backgroundObserver: NSObjectProtocol?
    private let devicePlatform: DevicePlatformProviding.Type

    init(voiceSearchHelper: VoiceSearchHelperProtocol,
         aiChatSettings: AIChatSettingsProvider,
         toggleModeStorage: ToggleModeStoring = ToggleModeStorage(),
         initialToggleState: TextEntryMode? = nil,
         funnelState: SwitchBarFunnelProviding = SwitchBarFunnel(storage: UserDefaults.standard),
         sessionStateMetrics: SessionStateMetricsProviding,
         featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         devicePlatform: DevicePlatformProviding.Type = DevicePlatform.self,
         voiceShortcutFeature: DuckAIVoiceShortcutFeatureProviding = DuckAIVoiceShortcutFeature(),
         isFireTab: Bool) {
        self.voiceSearchHelper = voiceSearchHelper
        self.aiChatSettings = aiChatSettings
        self.toggleModeStorage = toggleModeStorage
        self.funnelState = funnelState
        self.sessionStateMetrics = sessionStateMetrics
        self.featureFlagger = featureFlagger
        self.devicePlatform = devicePlatform
        self.voiceShortcutFeature = voiceShortcutFeature
        self.isFireTab = isFireTab

        applyDefaultOmnibarMode(override: initialToggleState)

        // Set up app lifecycle observers to reset session flags
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.sessionStateMetrics.finalizeSession()
            Self.resetSessionFlags()
        }
    }

    // MARK: - SwitchBarHandling Implementation
    func updateCurrentText(_ text: String) {
        currentText = text
        isCurrentTextValidURL = URL.isValidAddressBarURLInput(text)
        updateButtonState(currentText: text)
    }

    func submitText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // Process funnel step
        processSubmissionFunnelStep(mode: currentToggleState)
        
        // Process session activity
        processSessionActivity(mode: currentToggleState)
        textSubmissionSubject.send((text: trimmed, mode: currentToggleState))
    }

    func setToggleState(_ state: TextEntryMode) {
        // Only fire pixel if the state is actually changing
        let isStateChanging = currentToggleState != state

        currentToggleState = state
        updateButtonState(currentText: currentText)

        if isStateChanging {
            fireModeSwitchedPixel(to: state)
        }
    }

    func updateBarPosition(isTop: Bool) {
        isTopBarPosition = isTop
        updateButtonState(currentText: currentText)
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

    func searchGoToButtonTapped() {
        searchGoToButtonTappedSubject.send(())
    }

    private func updateButtonState(currentText: String) {
        if !currentText.isEmpty {
            buttonState = .clearOnly
        } else if voiceSearchHelper.isVoiceSearchEnabled
                    && !(currentToggleState == .aiChat && voiceShortcutFeature.isAvailable) {
            if isUsingFadeOutAnimation || !isTopBarPosition {
                buttonState = .voiceOnly
            } else {
                buttonState = .noButtons
            }
        } else {
            buttonState = .noButtons
        }
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
    
    private func processSessionActivity(mode: TextEntryMode) {
        let previouslyUsedBothModes = Self.hasUsedSearchInSession && Self.hasUsedAIChatInSession
        
        // Record activity for session metrics
        switch mode {
        case .search:
            sessionStateMetrics.incrementActivity(.searchSubmitted)
            Self.hasUsedSearchInSession = true
        case .aiChat:
            sessionStateMetrics.incrementActivity(.promptSubmitted)
            Self.hasUsedAIChatInSession = true
        }
        
        // Fire pixel only when user achieves both-mode usage for the first time in this session
        let nowUsesBothModes = Self.hasUsedSearchInSession && Self.hasUsedAIChatInSession
        if nowUsesBothModes && !previouslyUsedBothModes {
            DailyPixel.fireDailyAndCount(pixel: .aiChatExperimentalOmnibarSessionBothModes)
        }
    }

    func saveToggleState() {
        toggleModeStorage.save(currentToggleState)
    }

    private func applyDefaultOmnibarMode(override: TextEntryMode? = nil) {
        currentToggleState = override ?? aiChatSettings.defaultOmnibarMode.resolvedTextEntryMode {
            toggleModeStorage.restore()
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
    
    // MARK: - Pixels
    
    private func fireModeSwitchedPixel(to state: TextEntryMode) {
        let direction = state == .search ? "to_search" : "to_duckai"
        let hadText = !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let parameters = [
            "direction": direction,
            "had_text": String(hadText),
            "default_position": aiChatSettings.defaultOmnibarMode.rawValue
        ]
        Pixel.fire(pixel: .aiChatExperimentalOmnibarModeSwitched, withAdditionalParameters: parameters)
    }
}
