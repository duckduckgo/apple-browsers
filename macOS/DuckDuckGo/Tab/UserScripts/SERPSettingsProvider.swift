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

final class SERPSettingsProvider: SERPSettingsProviding {
    private let featureFlagger: FeatureFlagger
    private let _eventMapper: EventMapping<SERPSettingsError>?

    var keyValueStore: ThrowingKeyValueStoring
    var aiChatPreferencesStorage: AIChatPreferencesStorage
    var settingsQueue: DispatchQueue = DispatchQueue(label: "com.duckduckgo.serp.settings")

    var eventMapper: EventMapping<SERPSettingsError>? {
        _eventMapper
    }

    init(aiStorage: AIChatPreferencesStorage = DefaultAIChatPreferencesStorage(),
         featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger,
         keyValueStore: ThrowingKeyValueStoring = NSApp.delegateTyped.keyValueStore,
         eventMapper: EventMapping<SERPSettingsError>? = SERPSettingsEventHandler()) {
        self.aiChatPreferencesStorage = aiStorage
        self.featureFlagger = featureFlagger
        self.keyValueStore = keyValueStore
        self._eventMapper = eventMapper
    }

    func buildMessageOriginRules() -> [HostnameMatchingRule] {
        var rules: [HostnameMatchingRule] = []

        if let ddgDomain = URL.duckDuckGo.host {
            rules.append(.exact(hostname: ddgDomain))
        }

        return rules
    }

    func isSERPSettingsFeatureOn() -> Bool {
        return true // TODO: To be feature flagged
    }
}
