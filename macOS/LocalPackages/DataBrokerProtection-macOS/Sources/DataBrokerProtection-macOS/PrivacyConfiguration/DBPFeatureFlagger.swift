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
import PrivacyConfig
import FeatureFlags_macOS
import WideEvent

public final class DBPFeatureFlagger: DBPMacOSFeatureFlagging {
    fileprivate let featureFlagger: FeatureFlagger

    public var isForegroundRunningOnAppActiveFeatureOn: Bool {
        // Not relevant to macOS
        return false
    }

    public var isContinuedProcessingFeatureOn: Bool {
        // Continued processing is iOS-only.
        false
    }

    public var isWebViewUserAgentOn: Bool {
        featureFlagger.isFeatureOn(.dbpWebViewUserAgent)
    }

    public var isOptOutRetryErrorFrequencyExperimentOn: Bool {
        featureFlagger.isFeatureOn(.dbpOptOutRetryError96Hours)
    }

    public var isPerformanceMetricsOn: Bool {
        featureFlagger.isFeatureOn(.dbpPerformanceMetrics)
    }

    public var isExtractedProfileRefreshOn: Bool {
        featureFlagger.isFeatureOn(.dbpExtractedProfileRefresh)
    }

    public var isSchedulerDeferralHandlingEnabled: Bool {
        featureFlagger.isFeatureOn(.dbpSchedulerDeferralHandling)
    }

    public init(featureFlagger: FeatureFlagger) {
        self.featureFlagger = featureFlagger
    }

    public init(configurationManager: ConfigurationManager,
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
    public func isEnabled(_ flag: WideEventFeatureFlag) -> Bool {
        // There are no flags defined currently, but please replace this with a switch statement when a new flag is added.
        return true
    }
}
