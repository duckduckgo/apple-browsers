//
//  SERPSettingsProvider.swift
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

import AppKit
import Foundation
import SERPSettings
import UserScript
import AIChat
import BrowserServicesKit
import Persistence
import Common

/// macOS implementation of SERP settings provider.
///
/// This class provides the concrete implementation of `SERPSettingsProviding`
/// for macOS, integrating with the app's storage, AI preferences, and feature flags.
///
/// ## Architecture
///
/// - **Storage**: Uses the app's global key-value store for persistence
/// - **AI Features**: Queries `AIChatPreferencesStorage` for AI feature state
/// - **Error Reporting**: Integrates with `SERPSettingsEventHandler` for pixel tracking
/// - **Security**: Restricts message origins to DuckDuckGo domains
///
/// ## Thread Safety
///
/// All storage operations are serialized through a dedicated serial queue
/// to ensure thread-safe access to the underlying key-value store.
///
final class SERPSettingsProvider: SERPSettingsProviding {
    /// Feature flagger for controlling SERP settings availability.
    ///
    /// Currently unused but reserved for future feature flag integration.
    private let featureFlagger: FeatureFlagger

    /// Internal storage for the event mapper.
    ///
    /// Stored separately to allow the computed property to provide optional access.
    private let _eventMapper: EventMapping<SERPSettingsError>?

    /// Key-value store for persistent settings storage.
    ///
    /// Defaults to the app's global key-value store, which uses UserDefaults
    /// for macOS application settings.
    var keyValueStore: ThrowingKeyValueStoring?

    /// AI chat preferences storage for querying AI feature state.
    ///
    /// Used to determine the value of `isAIChatEnabled`.
    var aiChatPreferencesStorage: AIChatPreferencesStorage

    /// Optional event mapper for error reporting.
    ///
    /// When set, storage errors are reported as pixels through `SERPSettingsEventHandler`.
    var eventMapper: EventMapping<SERPSettingsError>? {
        _eventMapper
    }

    /// Creates a new SERP settings provider with dependency injection.
    ///
    /// All parameters have sensible defaults that use the app's global singletons,
    /// making this convenient for production use while remaining testable.
    ///
    /// - Parameters:
    ///   - aiStorage: Storage for AI chat preferences (defaults to global storage)
    ///   - featureFlagger: Feature flag controller (defaults to app delegate)
    ///   - keyValueStore: Persistent storage (defaults to app delegate's store)
    ///   - eventMapper: Error event handler (defaults to new `SERPSettingsEventHandler`)
    init(aiStorage: AIChatPreferencesStorage = DefaultAIChatPreferencesStorage(),
         featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger,
         keyValueStore: ThrowingKeyValueStoring = NSApp.delegateTyped.keyValueStore,
         eventMapper: EventMapping<SERPSettingsError>? = SERPSettingsEventHandler()) {
        self.aiChatPreferencesStorage = aiStorage
        self.featureFlagger = featureFlagger
        self.keyValueStore = keyValueStore
        self._eventMapper = eventMapper
    }

    /// Builds message origin rules for security validation.
    ///
    /// Restricts SERP settings messages to only be accepted from DuckDuckGo domains.
    /// This prevents malicious sites from reading or modifying user settings.
    ///
    /// - Returns: Array containing the DuckDuckGo hostname rule
    func buildMessageOriginRules() -> [HostnameMatchingRule] {
        var rules: [HostnameMatchingRule] = []

        if let ddgDomain = URL.duckDuckGo.host {
            rules.append(.exact(hostname: ddgDomain))
        }

        return rules
    }

    /// Determines if SERP settings synchronization is enabled.
    ///
    /// Currently always returns `true`. This will be connected to a feature flag
    /// in a future update to allow remote control of the feature.
    ///
    /// - Returns: `true` (feature is always enabled)
    func isSERPSettingsFeatureOn() -> Bool {
        return featureFlagger.isFeatureOn(.storeSerpSettings)
    }
}
