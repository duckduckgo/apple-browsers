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
import PrivacyConfig
import FeatureFlags
import PixelKit

final class DBPFeatureFlagger: DBPFeatureFlagging {
    fileprivate let featureFlagger: FeatureFlagger

    var isRemoteBrokerDeliveryFeatureOn: Bool {
        featureFlagger.isFeatureOn(.dbpRemoteBrokerDelivery)
    }

    var isEmailConfirmationDecouplingFeatureOn: Bool {
        featureFlagger.isFeatureOn(.dbpEmailConfirmationDecoupling)
    }

    var isForegroundRunningOnAppActiveFeatureOn: Bool {
        // Not relevant to macOS
        return false
    }

    var isForegroundRunningWhenDashboardOpenFeatureOn: Bool {
        // Not relevant to macOS
        return false
    }

    var isClickActionDelayReductionOptimizationOn: Bool {
        featureFlagger.isFeatureOn(.dbpClickActionDelayReductionOptimization)
    }

    var isWideEventPOSTEndpointOn: Bool {
        featureFlagger.isFeatureOn(.wideEventPostEndpoint)
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

extension DBPFeatureFlagger: WideEventFeatureFlagProviding {
    func isEnabled(_ flag: WideEventFeatureFlag) -> Bool {
        switch flag {
        case .postEndpoint:
#if DEBUG || REVIEW || ALPHA
            return false
#else
            return featureFlagger.isFeatureOn(.wideEventPostEndpoint)
#endif
        }
    }
}
