//
//  OnboardingPersonalizationStores.swift
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

/// Provider ports that back ``OnboardingPersonalizationManager``.
/// Decouples the Onboarding package from `AIChat`, `SERPSettings`, and other features.
/// Each platform conforms its own stores to these ports at its composition root, and any
/// value translation the store needs (e.g. an iOS `Bool` → a Duck Player youtube-mode enum) lives in
/// that per-platform conformance, not in the shared manager.

/// Backed by the platform's app settings (recently-visited sites, Duck Player).
public protocol OnboardingAppSettingsPersonalizationStore: AnyObject {
    /// Whether the browser records and shows recently visited sites.
    var recentlyVisitedSitesEnabled: Bool { get set }
    /// Whether Duck Player is enabled for YouTube.
    var isDuckPlayerEnabled: Bool { get set }
}

/// Backed by the platform's SERP settings blob.
public protocol OnboardingSERPPersonalizationStore: AnyObject {
    /// Whether Safe Search filtering is on. Enabling selects the platform's default filtering level; disabling turns filtering off.
    var isSafeSearchEnabled: Bool { get set }
    /// Whether Search Assist (AI-assisted answers) is on. Enabling selects the platform's default frequency; disabling turns it off.
    var isSearchAssistEnabled: Bool { get set }
    /// Whether AI-generated images are *hidden* in results.
    var areAIGeneratedImagesHidden: Bool { get set }
}

/// Backed by the platform's AI Chat feature settings (Duck.ai availability, new-tab behaviour).
public protocol OnboardingAIChatPersonalizationStore: AnyObject {
    /// Whether Duck.ai is enabled.
    var isDuckAIEnabled: Bool { get set }
    /// Whether new tabs default to opening with AI chat rather than search toggle.
    var newTabTabToggleDefaultToAIChat: Bool { get set }
}

/// Backed by the platform's AI Chat model preference.
public protocol OnboardingAIModelPersonalizationStore: AnyObject {
    /// The persisted model, or `nil` when none has been chosen.
    var selectedAIModel: OnboardingAIModel? { get set }
}

/// Backed by the platform's YouTube ad-blocking setting.
public protocol OnboardingYouTubeAdBlockingPersonalizationStore: AnyObject {
    /// Whether ad blocking on YouTube is enabled.
    var isYouTubeAdBlockingEnabled: Bool { get set }
}
