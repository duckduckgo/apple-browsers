//
//  SubscriptionExperiment.swift
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

/// Identifies an experiment and cohort attributed to a subscription purchase.
public struct SubscriptionExperiment: Codable, Equatable, Hashable {
    public let experimentName: String
    public let experimentCohort: String

    public init(experimentName: String, experimentCohort: String) {
        self.experimentName = experimentName
        self.experimentCohort = experimentCohort
    }
}

/// Selects the purchase attribution format: `legacy` supports one experiment, while `multiple` supports several.
public enum PurchaseExperimentAttribution: Equatable {
    case legacy(SubscriptionExperiment)
    case multiple([SubscriptionExperiment])
}
