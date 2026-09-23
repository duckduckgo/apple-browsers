//
//  SessionFeatureFlagger.swift
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

import Combine
import FeatureFlags_iOS
import PrivacyConfig

/// Keeps site permissions fixed for this launch while forwarding live values for other flags.
final class SessionFeatureFlagger: FeatureFlagger {
    private let base: FeatureFlagger
    private let isSitePermissionsEnabled: Bool
    private let isSitePermissionsEnabledWithoutOverride: Bool

    init(base: FeatureFlagger) {
        self.base = base
        isSitePermissionsEnabled = base.isFeatureOn(for: FeatureFlag.sitePermissions, allowOverride: true)
        isSitePermissionsEnabledWithoutOverride = base.isFeatureOn(for: FeatureFlag.sitePermissions, allowOverride: false)
    }

    var internalUserDecider: InternalUserDecider { base.internalUserDecider }
    var localOverrides: FeatureFlagLocalOverriding? { base.localOverrides }
    var updatesPublisher: AnyPublisher<Void, Never> { base.updatesPublisher }
    var allActiveExperiments: Experiments { base.allActiveExperiments }

    func isFeatureOn<Flag: FeatureFlagDescribing>(for featureFlag: Flag, allowOverride: Bool) -> Bool {
        if (featureFlag as? FeatureFlag) == .sitePermissions {
            return allowOverride ? isSitePermissionsEnabled : isSitePermissionsEnabledWithoutOverride
        }
        return base.isFeatureOn(for: featureFlag, allowOverride: allowOverride)
    }

    func resolveCohort<Flag: FeatureFlagDescribing>(for featureFlag: Flag, allowOverride: Bool) -> (any FeatureFlagCohortDescribing)? {
        base.resolveCohort(for: featureFlag, allowOverride: allowOverride)
    }

    func assignedCohort<Flag: FeatureFlagDescribing>(for featureFlag: Flag, allowOverride: Bool) -> (any FeatureFlagCohortDescribing)? {
        base.assignedCohort(for: featureFlag, allowOverride: allowOverride)
    }
}
