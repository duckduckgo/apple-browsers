//
//  OnboardingPersonalizationAITests.swift
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

import Testing
import Foundation
@_spi(Testing) import Persistence
import PrivacyConfig
import AIChat
import Onboarding
@testable import DuckDuckGo

// MARK: - AI Chat model (AI Chat: Setup step 1)

@Suite("Onboarding Personalization – AI Model Adapter")
struct OnboardingPersonalizationAIModelTests {

    @Test("Selected model is nil at the start of onboarding")
    func modelIsNilWhenUnset() {
        // GIVEN
        let sut = OnboardingAIModelAdapter()

        // THEN
        #expect(sut.selectedAIModel == nil)
    }

    @Test("Setting a model keeps it for the onboarding session")
    func settingModelKeepsIt() {
        // GIVEN
        let sut = OnboardingAIModelAdapter()

        // WHEN
        sut.selectedAIModel = OnboardingAIModel(id: "claude-x", name: "Claude")

        // THEN
        #expect(sut.selectedAIModel == OnboardingAIModel(id: "claude-x", name: "Claude"))
    }

    @Test("Setting nil clears the model")
    func settingNilClearsModel() {
        // GIVEN
        let sut = OnboardingAIModelAdapter()
        sut.selectedAIModel = OnboardingAIModel(id: "claude-x", name: "Claude")

        // WHEN
        sut.selectedAIModel = nil

        // THEN
        #expect(sut.selectedAIModel == nil)
    }

    @Test("A new onboarding session does not see the model picked in an earlier one")
    func modelDoesNotOutliveTheAdapter() {
        // GIVEN
        OnboardingAIModelAdapter().selectedAIModel = OnboardingAIModel(id: "claude-x", name: "Claude")

        // WHEN
        let sut = OnboardingAIModelAdapter()

        // THEN
        #expect(sut.selectedAIModel == nil)
    }
}

// MARK: - Duck.ai on/off (No AI: Setup step 2)

@Suite("Onboarding Personalization – AI Chat Settings Adapter")
struct OnboardingPersonalizationAIChatTests {

    private func makeAIChatSettings(store: InMemoryKeyValueStore = InMemoryKeyValueStore()) -> AIChatSettings {
        AIChatSettings(
            privacyConfigurationManager: PrivacyConfigurationManagerMock(),
            debugSettings: MockAIChatDebugSettings(),
            keyValueStore: store,
            notificationCenter: NotificationCenter(),
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.aiChatOmnibarDefaultPosition])
        )
    }

    @Test("Enabling Duck.ai enables AI Chat")
    func enablingDuckAIEnablesAIChat() {
        // GIVEN
        let sut = makeAIChatSettings()

        // WHEN
        sut.isDuckAIEnabled = true

        // THEN
        #expect(sut.isDuckAIEnabled)
        #expect(sut.isAIChatEnabled)
    }

    @Test("Disabling Duck.ai turns AI Chat off")
    func disablingDuckAITurnsOffAIChat() {
        // GIVEN
        let sut = makeAIChatSettings()

        // WHEN
        sut.isDuckAIEnabled = false

        // THEN
        #expect(!sut.isDuckAIEnabled)
        #expect(!sut.isAIChatEnabled)
    }

    @Test("Duck.ai reflects the underlying AI Chat state")
    func duckAIReflectsUnderlyingState() {
        // GIVEN
        let sut = makeAIChatSettings()

        // WHEN
        sut.enableAIChat(enable: true)
        // THEN
        #expect(sut.isDuckAIEnabled)

        // WHEN
        sut.enableAIChat(enable: false)
        // THEN
        #expect(!sut.isDuckAIEnabled)
    }

    // MARK: - New-tab default (AI Chat: Setup step 2)

    @Test("Opening new tabs with AI chat sets the omnibar default to Duck.ai")
    func newTabOpensWithAIChatSetsDuckAI() {
        // GIVEN
        let sut = makeAIChatSettings()

        // WHEN
        sut.newTabTabToggleDefaultToAIChat = true

        // THEN
        #expect(sut.defaultOmnibarMode == .duckAI)
        #expect(sut.newTabTabToggleDefaultToAIChat)
    }

    @Test("Not opening new tabs with AI chat sets the omnibar default to Last Used")
    func newTabNotOpeningWithAIChatSetsLastUsed() {
        // GIVEN
        let sut = makeAIChatSettings()

        // WHEN
        sut.newTabTabToggleDefaultToAIChat = false

        // THEN
        #expect(sut.defaultOmnibarMode == .lastUsed)
        #expect(!sut.newTabTabToggleDefaultToAIChat)
    }

    @Test("The new-tab flag reflects the underlying Omnibar default mode")
    func newTabReflectsOmnibarMode() {
        // GIVEN
        let sut = makeAIChatSettings()

        // WHEN
        sut.setDefaultOmnibarMode(.duckAI)
        // THEN
        #expect(sut.newTabTabToggleDefaultToAIChat)

        // WHEN - any non-Duck.ai mode reads as "off"
        sut.setDefaultOmnibarMode(.search)
        // THEN
        #expect(!sut.newTabTabToggleDefaultToAIChat)
    }
}
