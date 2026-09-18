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

import BrowserServicesKit
import FeatureFlags_iOS
import PrivacyConfig
import WebExtensions

@MainActor
enum DaxGreetingServiceFactory {
    static func makeService(activityStore: DaxGreetingActivityStore?,
                            privacyConfigurationManager: PrivacyConfigurationManaging,
                            appSettings: AppSettings,
                            adBlockingAvailability: AdBlockingAvailabilityProviding,
                            maliciousSiteProtectionPreferencesManager: MaliciousSiteProtectionPreferencesManaging,
                            featureFlagger: FeatureFlagger,
                            appearanceProvider: @escaping () -> DaxGreetingContext.Appearance?) -> DaxGreetingService {
        DaxGreetingService(contextProvider: { date, calendar in
            let appearance = appearanceProvider()
            var context = activityStore?.context(at: date, calendar: calendar, appearance: appearance)
                ?? DaxGreetingContext(appearance: appearance)
            let privacyConfig = privacyConfigurationManager.privacyConfig
            context.isTrackerProtectionEnabled = privacyConfig.isEnabled(featureKey: .contentBlocking)
            context.isCookiePopupProtectionEnabled = appSettings.cookiePopupPreference.isBlockingEnabled
                && privacyConfig.isEnabled(featureKey: .autoconsent)
            context.isAdBlockingEnabled = adBlockingAvailability.isEnabled
            context.isScamProtectionEnabled = maliciousSiteProtectionPreferencesManager.isMaliciousSiteProtectionOn
                && featureFlagger.isFeatureOn(.maliciousSiteProtection)
                && featureFlagger.isFeatureOn(.scamSiteProtection)
            return context
        })
    }
}
