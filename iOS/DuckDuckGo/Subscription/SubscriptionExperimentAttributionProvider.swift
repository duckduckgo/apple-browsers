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

/// Produces experiment attribution for a subscription purchase.
protocol SubscriptionExperimentAttributionProviding {
    func attribution(from selection: DefaultSubscriptionPagesUseSubscriptionFeature.SubscriptionSelection) -> PurchaseExperimentAttribution?
}

/// Combines experiments reported by the subscription page with active native subscription experiments.
struct DefaultSubscriptionExperimentAttributionProvider: SubscriptionExperimentAttributionProviding {
    private let featureFlagger: any FeatureFlagger

    init(featureFlagger: any FeatureFlagger) {
        self.featureFlagger = featureFlagger
    }

    /// Returns legacy attribution while concurrent experiments are disabled; otherwise, returns merged FE and native attribution.
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

    /// Returns active Privacy Pro experiments. Other parent features are not eligible for subscription attribution.
    private func activeNativeSubscriptionExperiments() -> [SubscriptionExperiment] {
        featureFlagger.allActiveExperiments
            .filter { $0.value.parentID == PrivacyFeature.privacyPro.rawValue }
            .map {
                SubscriptionExperiment(experimentName: $0.key, experimentCohort: $0.value.cohortID)
            }
            .sorted { $0.experimentName < $1.experimentName }
    }

    /// Merges FE and native experiments, preferring FE when experiment names clash.
    private func merge(
        frontEnd: [SubscriptionExperiment],
        native: [SubscriptionExperiment]
    ) -> [SubscriptionExperiment] {
        var mergedExperiments: [SubscriptionExperiment] = []

        for experiment in frontEnd + native {
            let isAlreadyIncluded = mergedExperiments.contains {
                $0.experimentName == experiment.experimentName
            }

            if !isAlreadyIncluded {
                mergedExperiments.append(experiment)
            }
        }

        return mergedExperiments
    }
}

/// Adds a fixed entry to the experiments sent with purchases made through one paywall, so the backend can report trial
/// conversion and retention for the people who bought there.
struct PaywallEntryExperimentAttributionProvider: SubscriptionExperimentAttributionProviding {

    /// Purchases from the paywall opened by the Try VPN onboarding step. Only the treatment cohort sees that step.
    static let vpnOnboardingPaywallEntry = SubscriptionExperiment(experimentName: "vpnOnboardingPaywall", experimentCohort: "treatment")

    private let wrapped: any SubscriptionExperimentAttributionProviding
    private let entry: SubscriptionExperiment

    init(wrapping wrapped: any SubscriptionExperimentAttributionProviding, entry: SubscriptionExperiment) {
        self.wrapped = wrapped
        self.entry = entry
    }

    /// Appends the entry to `experiments[]`. Legacy attribution (concurrent experiments off) has a single slot and stays as it is.
    func attribution(from selection: DefaultSubscriptionPagesUseSubscriptionFeature.SubscriptionSelection) -> PurchaseExperimentAttribution? {
        let attribution = wrapped.attribution(from: selection)
        guard case .multiple(let experiments) = attribution,
              !experiments.contains(where: { $0.experimentName == entry.experimentName }) else {
            return attribution
        }
        return .multiple(experiments + [entry])
    }
}
