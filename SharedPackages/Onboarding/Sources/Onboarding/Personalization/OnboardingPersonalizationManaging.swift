//
//  OnboardingPersonalizationManaging.swift
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

/// Represents an AI model the user can pick as their default during onboarding.
///
/// Keeps the Onboarding and AIChat packages decoupled: it carries only a stable ``id`` — which the
/// concrete, platform-specific manager maps onto whatever the underlying AI Chat store expects — and
/// a user-facing ``name``.
public struct OnboardingAIModel: Equatable, Identifiable {
    /// Stable identifier used by the concrete manager to persist the selection. Opaque to onboarding.
    public let id: String
    /// The user-facing display name (e.g. "ChatGPT").
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

// MARK: - Per-screen slices

/// The `.browserPrivately` setup step.
public protocol OnboardingSearchPersonalizing: AnyObject {
    /// Whether the browser records and shows recently visited sites.
    var isRecentlyVisitedSitesEnabled: Bool { get }
    /// Whether Safe Search filtering is on.
    var isSafeSearchEnabled: Bool { get }

    /// Enables or disables recently visited sites.
    func setRecentlyVisitedSites(_ enabled: Bool)
    /// Turns Safe Search filtering on or off.
    func setSafeSearch(_ enabled: Bool)
}

/// The first `.privateAIChat` setup step to select an AI model.
public protocol OnboardingAIChatModelPersonalizing: AnyObject {
    /// Persists `model` as the user's selected AI chat model.
    func setAIChatModel(_ model: OnboardingAIModel)
}

/// The second `.privateAIChat` setup step.
public protocol OnboardingAIChatNewTabPersonalizing: AnyObject {
    /// Whether new tabs default to opening with AI chat rather than search.
    var doesNewTabOpenWithAIChat: Bool { get }
    /// Sets whether new tabs default to opening with AI chat.
    func setNewTabOpensWithAIChat(_ opensWithAIChat: Bool)
}

/// The first `.noAI` setup step (Search Assist + AI-generated images).
public protocol OnboardingSearchAIFeaturesPersonalizing: AnyObject {
    /// Whether Search Assist (AI-assisted answers) is on.
    var isSearchAssistEnabled: Bool { get }
    /// Whether AI-generated images are *hidden*.
    var areAIGeneratedImagesHidden: Bool { get }

    /// Turns Search Assist on or off.
    func setSearchAssist(_ enabled: Bool)
    /// Sets whether AI-generated images are hidden.
    func setAIGeneratedImagesHidden(_ hidden: Bool)
}

/// The second `.noAI` setup step.
public protocol OnboardingDuckAIPersonalizing: AnyObject {
    /// Whether Duck.ai (AI Chat) is enabled.
    var isDuckAIEnabled: Bool { get }
    /// Enables or disables Duck.ai.
    func setDuckAIEnabled(_ enabled: Bool)
}

/// The `.blockAds` setup step.
public protocol OnboardingAdBlockingPersonalizing: AnyObject {
    /// Whether ad blocking on YouTube is enabled.
    var isYouTubeAdBlockingEnabled: Bool { get }
    /// Whether Duck Player is enabled for YouTube.
    var isDuckPlayerEnabled: Bool { get }

    /// Enables or disables ad blocking on YouTube.
    func setYouTubeAdBlocking(_ enabled: Bool)
    /// Enables or disables Duck Player.
    func setDuckPlayer(_ enabled: Bool)
}

/// Injected into `OnboardingIntroViewModel`, applied once when the reason is picked to perform initial setup.
public protocol OnboardingPersonalizationDefaultsApplying: AnyObject {
    /// Applies the presented defaults for the picked reason
    func applyDefaults(for reason: OnboardingDownloadReason)
}

// MARK: - Facade

/// A single facade over the several unrelated stores that back the tailored onboarding steps.
///
/// The interface is segregated per screen so each screen's view model is injected with only the slice it needs.
public protocol OnboardingPersonalizationManaging: OnboardingSearchPersonalizing,
                                                   OnboardingAIChatModelPersonalizing,
                                                   OnboardingAIChatNewTabPersonalizing,
                                                   OnboardingSearchAIFeaturesPersonalizing,
                                                   OnboardingDuckAIPersonalizing,
                                                   OnboardingAdBlockingPersonalizing,
                                                   OnboardingPersonalizationDefaultsApplying {}
