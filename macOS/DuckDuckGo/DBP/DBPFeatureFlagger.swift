//
//  DBPFeatureFlagger.swift
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
import DataBrokerProtectionCore
import DataBrokerProtection_macOS
import BrowserServicesKit
import FeatureFlags

final class DBPFeatureFlagger: DBPFeatureFlagging {
    private let featureFlagger: FeatureFlagger

    var isRemoteBrokerDeliveryFeatureOn: Bool {
        featureFlagger.isFeatureOn(.dbpRemoteBrokerDelivery)
    }

    var isEmailConfirmationDecouplingFeatureOn: Bool {
        featureFlagger.isFeatureOn(.dbpEmailConfirmationDecoupling)
    }

    init(featureFlagger: FeatureFlagger) {
        self.featureFlagger = featureFlagger
    }

    init(configurationManager: DataBrokerProtection_macOS.ConfigurationManager,
         privacyConfigurationManager: PrivacyConfigurationManaging) {
        let featureFlagger = DefaultFeatureFlagger(
            internalUserDecider: privacyConfigurationManager.internalUserDecider,
            privacyConfigManager: privacyConfigurationManager,
            localOverrides: FeatureFlagLocalOverrides(
                keyValueStore: UserDefaults.config,
                actionHandler: FeatureFlagOverridesPublishingHandler<FeatureFlag>()
            ),
            experimentManager: nil,
            for: FeatureFlag.self
        )
        self.featureFlagger = featureFlagger
    }
}
