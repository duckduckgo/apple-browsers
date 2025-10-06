//
//  AttributedMetricFeatureFlags.swift
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
import BrowserServicesKit

public enum AttributedMetricFeatureFlags: String, FeatureFlagDescribing {
    case behaviorMetricsEnabled

    public var defaultValue: Bool {
        switch self {
        case .behaviorMetricsEnabled:
            return false
        }
    }

    public var supportsLocalOverriding: Bool {
        switch self {
        case .behaviorMetricsEnabled:
            return true
        }
    }

    public var source: BrowserServicesKit.FeatureFlagSource {
        switch self {
        case .behaviorMetricsEnabled:
            return .remoteReleasable(.subfeature(BehaviorMetricsSubfeature.behaviorMetricsEnabled))
        }
    }

    public var cohortType: (any BrowserServicesKit.FeatureFlagCohortDescribing.Type)? { nil }
}
