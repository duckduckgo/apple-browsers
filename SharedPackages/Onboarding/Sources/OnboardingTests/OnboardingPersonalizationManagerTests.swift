//
//  OnboardingPersonalizationManagerTests.swift
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
@testable import Onboarding

@Suite("Onboarding Personalization Manager")
struct OnboardingPersonalizationManagerTests {

    private func makeManager(
        appSettings: MockOnboardingAppSettingsStore = .init(),
        serpSettings: MockOnboardingSERPStore = .init(),
        aiChatSettings: MockOnboardingAIChatStore = .init(),
        aiModelSettings: MockOnboardingAIModelStore = .init(),
        youTubeAdBlocking: MockOnboardingYouTubeAdBlockingStore = .init()
    ) -> OnboardingPersonalizationManager {
        OnboardingPersonalizationManager(
            appSettings: appSettings,
            serpSettings: serpSettings,
            aiChatSettings: aiChatSettings,
            aiModelSettings: aiModelSettings,
            youTubeAdBlocking: youTubeAdBlocking
        )
    }

    // MARK: - Search step

    @Test("Recently-visited reads and writes the app settings store")
    func recentlyVisitedSites() {
        // GIVEN
        let appSettings = MockOnboardingAppSettingsStore()
        appSettings.recentlyVisitedSitesEnabled = true
        let manager = makeManager(appSettings: appSettings)
        #expect(manager.isRecentlyVisitedSitesEnabled)

        // WHEN
        manager.setRecentlyVisitedSites(false)

        // THEN
        #expect(!appSettings.recentlyVisitedSitesEnabled)
        #expect(!manager.isRecentlyVisitedSitesEnabled)
    }

    @Test("Safe search reads and writes the SERP store")
    func safeSearch() {
        // GIVEN
        let serpSettings = MockOnboardingSERPStore()
        serpSettings.isSafeSearchEnabled = false
        let manager = makeManager(serpSettings: serpSettings)
        #expect(!manager.isSafeSearchEnabled)

        // WHEN
        manager.setSafeSearch(true)

        // THEN
        #expect(serpSettings.isSafeSearchEnabled)
        #expect(manager.isSafeSearchEnabled)
    }

    // MARK: - AI Chat model step

    @Test("Setting the model writes it to the store")
    func setAIModel() {
        // GIVEN
        let store = MockOnboardingAIModelStore()
        let manager = makeManager(aiModelSettings: store)
        let model = OnboardingAIModel(id: "mistral", name: "Mistral")

        // WHEN
        manager.setAIChatModel(model)

        // THEN
        #expect(store.selectedAIModel == model)
    }

    // MARK: - AI Chat new-tab step

    @Test("New-tab-opens-with-AI-chat reads and writes the AI chat store")
    func newTabOpensWithAIChat() {
        // GIVEN
        let store = MockOnboardingAIChatStore()
        store.newTabTabToggleDefaultToAIChat = false
        let manager = makeManager(aiChatSettings: store)
        #expect(!manager.doesNewTabOpenWithAIChat)

        // WHEN
        manager.setNewTabOpensWithAIChat(true)

        // THEN
        #expect(store.newTabTabToggleDefaultToAIChat)
    }

    // MARK: - No AI step 1

    @Test("Search Assist reads and writes the SERP store")
    func searchAssist() {
        // GIVEN
        let serpSettings = MockOnboardingSERPStore()
        serpSettings.isSearchAssistEnabled = true
        let manager = makeManager(serpSettings: serpSettings)
        #expect(manager.isSearchAssistEnabled)

        // WHEN
        manager.setSearchAssist(false)

        // THEN
        #expect(!serpSettings.isSearchAssistEnabled)
    }

    @Test("Hide-AI-generated-images reads and writes the SERP store (store truth)")
    func hideAIGeneratedImages() {
        // GIVEN
        let serpSettings = MockOnboardingSERPStore()
        serpSettings.areAIGeneratedImagesHidden = false
        let manager = makeManager(serpSettings: serpSettings)
        #expect(!manager.areAIGeneratedImagesHidden)

        // WHEN
        manager.setAIGeneratedImagesHidden(true)

        // THEN
        #expect(serpSettings.areAIGeneratedImagesHidden)
    }

    // MARK: - No AI step 2

    @Test("Duck.ai on/off reads and writes the AI chat store")
    func duckAIEnabled() {
        // GIVEN
        let store = MockOnboardingAIChatStore()
        store.isDuckAIEnabled = true
        let manager = makeManager(aiChatSettings: store)
        #expect(manager.isDuckAIEnabled)

        // WHEN
        manager.setDuckAIEnabled(false)

        // THEN
        #expect(!store.isDuckAIEnabled)
    }

    // MARK: - Block Ads step

    @Test("YouTube ad blocking reads and writes its store")
    func youTubeAdBlocking() {
        // GIVEN
        let store = MockOnboardingYouTubeAdBlockingStore()
        store.isYouTubeAdBlockingEnabled = true
        let manager = makeManager(youTubeAdBlocking: store)
        #expect(manager.isYouTubeAdBlockingEnabled)

        // WHEN
        manager.setYouTubeAdBlocking(false)

        // THEN
        #expect(!store.isYouTubeAdBlockingEnabled)
    }

    @Test("Duck Player reads and writes the app settings store")
    func duckPlayer() {
        // GIVEN
        let appSettings = MockOnboardingAppSettingsStore()
        appSettings.isDuckPlayerEnabled = false
        let manager = makeManager(appSettings: appSettings)
        #expect(!manager.isDuckPlayerEnabled)

        // WHEN
        manager.setDuckPlayer(true)

        // THEN
        #expect(appSettings.isDuckPlayerEnabled)
    }

    // MARK: - applyDefaults

    @Test("applyDefaults for .noAI disables both Search AI features")
    func applyDefaultsNoAI() {
        // GIVEN
        let serpSettings = MockOnboardingSERPStore()
        serpSettings.isSearchAssistEnabled = true
        serpSettings.areAIGeneratedImagesHidden = false
        let manager = makeManager(serpSettings: serpSettings)

        // WHEN
        manager.applyDefaults(for: .noAI)

        // THEN
        #expect(!serpSettings.isSearchAssistEnabled)
        #expect(serpSettings.areAIGeneratedImagesHidden)
    }

    @Test(
        "applyDefaults is a no-op for the reasons that already match app defaults",
        arguments: [OnboardingDownloadReason.browserPrivately, .privateAIChat, .blockAds]
    )
    func applyDefaultsOtherReasonsAreNoOp(reason: OnboardingDownloadReason) {
        // GIVEN
        let serpSettings = MockOnboardingSERPStore()
        let appSettings = MockOnboardingAppSettingsStore()
        let aiChatSettings = MockOnboardingAIChatStore()
        let manager = makeManager(appSettings: appSettings, serpSettings: serpSettings, aiChatSettings: aiChatSettings)

        // WHEN
        manager.applyDefaults(for: reason)

        // THEN
        #expect(serpSettings.setCallCount == 0)
        #expect(appSettings.setCallCount == 0)
        #expect(aiChatSettings.setCallCount == 0)
    }
}
