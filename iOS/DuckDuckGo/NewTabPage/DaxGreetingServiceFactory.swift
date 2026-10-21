//
//  DaxGreetingServiceFactory.swift
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

import AIChat
import PrivacyConfig
import WebExtensions
import Foundation

@MainActor
enum DaxGreetingServiceFactory {
    static func makeService(activityStore: DaxGreetingActivityStore?,
                            privacyConfigurationManager: PrivacyConfigurationManaging,
                            aiChatSettings: AIChatSettingsProvider,
                            adBlockingAvailability: AdBlockingAvailabilityProviding) -> DaxGreetingService {
        DaxGreetingService(contextProvider: { date, calendar in
            var context = activityStore?.context(at: date, calendar: calendar) ?? DaxGreetingContext()
            context.isAIChatEnabled = aiChatSettings.isAIChatEnabled
            context.isTrackerOrAdBlockingEnabled = privacyConfigurationManager.privacyConfig.isEnabled(featureKey: .contentBlocking)
                || adBlockingAvailability.isEnabled
            return context
        })
    }
}
