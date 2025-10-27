//
//  SERPSettingsProvider.swift
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
import Common
import AIChat
import Persistence
import UserScript
import BrowserServicesKit
import SERPSettings

final class SERPSettingsProvider: SERPSettingsProviding {
    var keyValueStore: ThrowingKeyValueStoring
    var eventMapper: EventMapping<SERPSettingsError>?
    var aiChatProvider: AIChatSettingsProvider

    private let featureFlagger: FeatureFlagger

    init(keyValueStore: ThrowingKeyValueStoring,
         eventMapper: EventMapping<SERPSettingsError>? = nil,
         aiChatProvider: AIChatSettingsProvider,
         featureFlagger: FeatureFlagger) {
        self.keyValueStore = keyValueStore
        self.eventMapper = eventMapper
        self.aiChatProvider = aiChatProvider
        self.featureFlagger = featureFlagger
    }

    func buildMessageOriginRules() -> [HostnameMatchingRule] {
        var rules: [HostnameMatchingRule] = []
        if let ddgDomain = URL.ddg.host {
            rules.append(.exact(hostname: ddgDomain))
        }
        return rules
    }

    func isSERPSettingsFeatureOn() -> Bool {
        return false
    }
}
