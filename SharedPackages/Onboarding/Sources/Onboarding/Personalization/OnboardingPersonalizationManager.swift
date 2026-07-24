//
//  OnboardingPersonalizationManager.swift
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

import Foundation

/// A facade over the several unrelated stores that back the tailored onboarding steps.
public final class OnboardingPersonalizationManager: OnboardingPersonalizationManaging {
    private let appSettings: OnboardingAppSettingsPersonalizationStore
    private let serpSettings: OnboardingSERPPersonalizationStore
    private let aiChatSettings: OnboardingAIChatPersonalizationStore
    private let aiModelSettings: OnboardingAIModelPersonalizationStore
    private let youTubeAdBlocking: OnboardingYouTubeAdBlockingPersonalizationStore

    public init(
        appSettings: OnboardingAppSettingsPersonalizationStore,
        serpSettings: OnboardingSERPPersonalizationStore,
        aiChatSettings: OnboardingAIChatPersonalizationStore,
        aiModelSettings: OnboardingAIModelPersonalizationStore,
        youTubeAdBlocking: OnboardingYouTubeAdBlockingPersonalizationStore
    ) {
        self.appSettings = appSettings
        self.serpSettings = serpSettings
        self.aiChatSettings = aiChatSettings
        self.aiModelSettings = aiModelSettings
        self.youTubeAdBlocking = youTubeAdBlocking
    }
}

// MARK: - OnboardingPersonalizationDefaultsApplying

extension OnboardingPersonalizationManager {

    public func applyDefaults(for reason: OnboardingDownloadReason) {
        switch reason {
        case .noAI:
            // The only reason whose presented toggles diverge from the app's existing defaults:
            // both Search AI features start off.
            setSearchAssist(false)
            setAIGeneratedImagesHidden(true)
        case .browserPrivately, .privateAIChat, .blockAds:
            // Presented toggles already match the app's existing defaults; nothing to override.
            break
        }
    }

}

// MARK: - OnboardingSearchPersonalizing

extension OnboardingPersonalizationManager {

    public var isRecentlyVisitedSitesEnabled: Bool {
        appSettings.recentlyVisitedSitesEnabled
    }

    public var isSafeSearchEnabled: Bool {
        serpSettings.isSafeSearchEnabled
    }

    public func setRecentlyVisitedSites(_ enabled: Bool) {
        appSettings.recentlyVisitedSitesEnabled = enabled
    }

    public func setSafeSearch(_ enabled: Bool) {
        serpSettings.isSafeSearchEnabled = enabled
    }

}

// MARK: - OnboardingAIChatModelPersonalizing

extension OnboardingPersonalizationManager {

    public func setAIChatModel(_ model: OnboardingAIModel) {
        aiModelSettings.selectedAIModel = model
    }

}

// MARK: - OnboardingAIChatNewTabPersonalizing

extension OnboardingPersonalizationManager {

    public var doesNewTabOpenWithAIChat: Bool {
        aiChatSettings.newTabTabToggleDefaultToAIChat
    }

    public func setNewTabOpensWithAIChat(_ opensWithAIChat: Bool) {
        aiChatSettings.newTabTabToggleDefaultToAIChat = opensWithAIChat
    }

}

// MARK: - OnboardingSearchAIFeaturesPersonalizing

extension OnboardingPersonalizationManager {

    public var isSearchAssistEnabled: Bool {
        serpSettings.isSearchAssistEnabled
    }

    public var areAIGeneratedImagesHidden: Bool {
        serpSettings.areAIGeneratedImagesHidden
    }

    public func setSearchAssist(_ enabled: Bool) {
        serpSettings.isSearchAssistEnabled = enabled
    }

    public func setAIGeneratedImagesHidden(_ hidden: Bool) {
        serpSettings.areAIGeneratedImagesHidden = hidden
    }

}

// MARK: - OnboardingDuckAIPersonalizing

extension OnboardingPersonalizationManager {

    public var isDuckAIEnabled: Bool {
        aiChatSettings.isDuckAIEnabled
    }

    public func setDuckAIEnabled(_ enabled: Bool) {
        aiChatSettings.isDuckAIEnabled = enabled
    }

}

// MARK: - OnboardingAdBlockingPersonalizing

extension OnboardingPersonalizationManager {

    public var isYouTubeAdBlockingEnabled: Bool {
        youTubeAdBlocking.isYouTubeAdBlockingEnabled
    }

    public var isDuckPlayerEnabled: Bool {
        appSettings.isDuckPlayerEnabled
    }

    public func setYouTubeAdBlocking(_ enabled: Bool) {
        youTubeAdBlocking.isYouTubeAdBlockingEnabled = enabled
    }

    public func setDuckPlayer(_ enabled: Bool) {
        appSettings.isDuckPlayerEnabled = enabled
    }

}
