//
//  SubscriptionExperimentAttributionProvider.swift
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

import FeatureFlags_iOS
import PrivacyConfig
import Subscription

protocol SubscriptionExperimentAttributionProviding {
    func attribution(from selection: DefaultSubscriptionPagesUseSubscriptionFeature.SubscriptionSelection) -> PurchaseExperimentAttribution?
}

struct DefaultSubscriptionExperimentAttributionProvider: SubscriptionExperimentAttributionProviding {
    private let featureFlagger: any FeatureFlagger

    init(featureFlagger: any FeatureFlagger) {
        self.featureFlagger = featureFlagger
    }

    func attribution(from selection: DefaultSubscriptionPagesUseSubscriptionFeature.SubscriptionSelection) -> PurchaseExperimentAttribution? {
        guard featureFlagger.isFeatureOn(.subscriptionConcurrentExperiments) else {
            // FE mirrors the first eligible assignment into this field for clients on the legacy contract.
            return selection.experiment.map { .legacy($0.subscriptionExperiment) }
        }

        let frontEndExperiments = selection.experiments.flatMap { $0.isEmpty ? nil : $0 }
            ?? selection.experiment.map { [$0] }
            ?? []
        let experiments = merge(
            frontEnd: frontEndExperiments.map(\.subscriptionExperiment),
            native: activeNativeSubscriptionExperiments())

        return experiments.isEmpty ? nil : .multiple(experiments)
    }

    private func activeNativeSubscriptionExperiments() -> [SubscriptionExperiment] {
        featureFlagger.allActiveExperiments
            // This boundary prevents cohorts from unrelated parent features, including SERP experiments,
            // from being linked to a user's subscription confirmation request.
            .filter { $0.value.parentID == PrivacyFeature.privacyPro.rawValue }
            .map {
                SubscriptionExperiment(experimentName: $0.key, experimentCohort: $0.value.cohortID)
            }
            .sorted { $0.experimentName < $1.experimentName }
    }

    private func merge(frontEnd: [SubscriptionExperiment], native: [SubscriptionExperiment]) -> [SubscriptionExperiment] {
        var experimentNames = Set<String>()
        var mergedExperiments: [SubscriptionExperiment] = []

        for experiment in frontEnd where experimentNames.insert(experiment.experimentName).inserted {
            mergedExperiments.append(experiment)
        }

        for experiment in native {
            if experimentNames.insert(experiment.experimentName).inserted {
                mergedExperiments.append(experiment)
            }
        }

        return mergedExperiments
    }
}

struct LegacySubscriptionExperimentAttributionProvider: SubscriptionExperimentAttributionProviding {
    func attribution(from selection: DefaultSubscriptionPagesUseSubscriptionFeature.SubscriptionSelection) -> PurchaseExperimentAttribution? {
        selection.experiment.map { .legacy($0.subscriptionExperiment) }
    }
}
