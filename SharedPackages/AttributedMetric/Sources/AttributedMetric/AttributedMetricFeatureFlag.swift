//
//  AttributedMetricFeatureFlag.swift
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

/// https://app.asana.com/1/137249556945/project/1113117197328546/task/1211362861225166?focus=true
public enum AttributedMetricFeatureFlag: String {
    case attributedMetrics // general kill switch

    // SubFeatures
    case emitAllMetrics // we don't emit any metric, but we still collect
    case retention // Kill Switch
    case canEmitRetention // we don't emit metric, but we still collect
    case searchDaysAvg // Kill Switch
    case canEmitSearchDaysAvg // we don't emit metric, but we still collect
    case searchCountAvg // Kill Switch
    case canEmitSearchCountAvg // we don't emit metric, but we still collect
    case adClickCountAvg // Kill Switch
    case canEmitAdClickCountAvg // we don't emit metric, but we still collect
    case aiUsageAvg // Kill Switch
    case canEmitAIUsageAvg // we don't emit metric, but we still collect
    case subscriptionRetention // Kill Switch
    case canEmitSubscriptionRetention // we don't emit metric, but we still collect
    case syncDevices // Kill Switch
    case canEmitSyncDevices // we don't emit metric, but we still collect
}

extension AttributedMetricFeatureFlag: FeatureFlagDescribing {

    public var defaultValue: Bool {
        switch self {
        case .attributedMetrics, .emitAllMetrics, .retention, .canEmitRetention,
             .searchDaysAvg, .canEmitSearchDaysAvg, .searchCountAvg, .canEmitSearchCountAvg,
             .adClickCountAvg, .canEmitAdClickCountAvg, .aiUsageAvg, .canEmitAIUsageAvg,
             .subscriptionRetention, .canEmitSubscriptionRetention, .syncDevices, .canEmitSyncDevices:
            return false
        }
    }

    public var supportsLocalOverriding: Bool {
        switch self {
        case .attributedMetrics, .emitAllMetrics, .retention, .canEmitRetention,
             .searchDaysAvg, .canEmitSearchDaysAvg, .searchCountAvg, .canEmitSearchCountAvg,
             .adClickCountAvg, .canEmitAdClickCountAvg, .aiUsageAvg, .canEmitAIUsageAvg,
             .subscriptionRetention, .canEmitSubscriptionRetention, .syncDevices, .canEmitSyncDevices:
            return true
        }
    }

    public var source: BrowserServicesKit.FeatureFlagSource {
        switch self {
        case .attributedMetrics:
            return .remoteReleasable(.feature(.attributedMetrics))
        case .emitAllMetrics:
            return .remoteReleasable(.subfeature(AttributedMetricsSubfeature.emitAllMetrics))
        case .retention:
            return .remoteReleasable(.subfeature(AttributedMetricsSubfeature.retention))
        case .canEmitRetention:
            return .remoteReleasable(.subfeature(AttributedMetricsSubfeature.canEmitRetention))
        case .searchDaysAvg:
            return .remoteReleasable(.subfeature(AttributedMetricsSubfeature.searchDaysAvg))
        case .canEmitSearchDaysAvg:
            return .remoteReleasable(.subfeature(AttributedMetricsSubfeature.canEmitSearchDaysAvg))
        case .searchCountAvg:
            return .remoteReleasable(.subfeature(AttributedMetricsSubfeature.searchCountAvg))
        case .canEmitSearchCountAvg:
            return .remoteReleasable(.subfeature(AttributedMetricsSubfeature.canEmitSearchCountAvg))
        case .adClickCountAvg:
            return .remoteReleasable(.subfeature(AttributedMetricsSubfeature.adClickCountAvg))
        case .canEmitAdClickCountAvg:
            return .remoteReleasable(.subfeature(AttributedMetricsSubfeature.canEmitAdClickCountAvg))
        case .aiUsageAvg:
            return .remoteReleasable(.subfeature(AttributedMetricsSubfeature.aiUsageAvg))
        case .canEmitAIUsageAvg:
            return .remoteReleasable(.subfeature(AttributedMetricsSubfeature.canEmitAIUsageAvg))
        case .subscriptionRetention:
            return .remoteReleasable(.subfeature(AttributedMetricsSubfeature.subscriptionRetention))
        case .canEmitSubscriptionRetention:
            return .remoteReleasable(.subfeature(AttributedMetricsSubfeature.canEmitSubscriptionRetention))
        case .syncDevices:
            return .remoteReleasable(.subfeature(AttributedMetricsSubfeature.syncDevices))
        case .canEmitSyncDevices:
            return .remoteReleasable(.subfeature(AttributedMetricsSubfeature.canEmitSyncDevices))
        }
    }

    public var cohortType: (any BrowserServicesKit.FeatureFlagCohortDescribing.Type)? { nil }
}
