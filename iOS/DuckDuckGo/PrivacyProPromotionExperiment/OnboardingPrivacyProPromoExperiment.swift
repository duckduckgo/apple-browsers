//
//  OnboardingPrivacyProPromoExperiment.swift
//  DuckDuckGo
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

import BrowserServicesKit
import Core
import PixelKit
import Subscription

protocol OnboardingPrivacyProPromoExperimenting {
    func getCohortIfEnabled() -> PrivacyProOnboardingCTAMarch25Cohort?

    /// Fires a pixel when the onboarding promotion is shown.
    func fireImpressionPixel()

    /// Fires a pixel when the onboarding promotion is tapped.
    func fireTapPixel()

    /// Fires a pixel when the onboarding promotion is dismissed.
    func fireDismissPixel()

    /// Fires a pixel when a monthly subscription is started.
    func fireSubscriptionStartedMonthlyPixel()

    /// Fires a pixel when a yearly subscription is started.
    func fireSubscriptionStartedYearlyPixel()
}

struct OnboardingPrivacyProPromoExperiment: OnboardingPrivacyProPromoExperimenting {

     /// Constants used in the experiment.
    enum Constants {
        /// Unique identifier for the subfeature being tested.
        static let subfeatureIdentifier = FeatureFlag.privacyProOnboardingCTAMarch25.rawValue

        /// Metric identifiers for various user actions during the experiment.
        static let metricImpressions = "onboardingPromotionImpression"
        static let metricTap = "onboardingPromotionTap"
        static let metricDismiss = "onboardingPromotionDismiss"
        static let metricSubscriptionStartedMonthly = "subscriptionStartedMonthly"
        static let metricSubscriptionStartedYearly = "subscriptionStartedYearly"

        /// Conversion window in days for tracking user actions.
        static let conversionWindowDays = 0...7
    }

    /// A feature flagging service for managing feature flag experiments.
    private let featureFlagger: FeatureFlagger

    /// A type responsible for firing experiment-related analytics pixels.
    private let experimentPixelFirer: ExperimentPixelFiring.Type

    private let subscriptionManager: SubscriptionManager

    init(featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         experimentPixelFirer: ExperimentPixelFiring.Type = PixelKit.self,
         subscriptionManager: SubscriptionManager = AppDependencyProvider.shared.subscriptionManager) {
        self.featureFlagger = featureFlagger
        self.experimentPixelFirer = experimentPixelFirer
        self.subscriptionManager = subscriptionManager
    }

    func getCohortIfEnabled() -> PrivacyProOnboardingCTAMarch25Cohort? {

        return .treatment

        // TODO: Check PP eligibility
        guard subscriptionManager.canPurchasePrivacyPro else { return nil }

        return featureFlagger.resolveCohort(for: FeatureFlag.privacyProOnboardingCTAMarch25)
                as? PrivacyProOnboardingCTAMarch25Cohort
    }

    func fireImpressionPixel() {
        experimentPixelFirer.fireExperimentPixel(for: Constants.subfeatureIdentifier,
                                     metric: Constants.metricImpressions,
                                     conversionWindowDays: Constants.conversionWindowDays,
                                     value: "true")
    }

    func fireTapPixel() {
        experimentPixelFirer.fireExperimentPixel(for: Constants.subfeatureIdentifier,
                                     metric: Constants.metricTap,
                                     conversionWindowDays: Constants.conversionWindowDays,
                                     value: "true")
    }

    func fireDismissPixel() {
        experimentPixelFirer.fireExperimentPixel(for: Constants.subfeatureIdentifier,
                                     metric: Constants.metricDismiss,
                                     conversionWindowDays: Constants.conversionWindowDays,
                                     value: "true")
    }

    func fireSubscriptionStartedMonthlyPixel() {
        experimentPixelFirer.fireExperimentPixel(for: Constants.subfeatureIdentifier,
                                     metric: Constants.metricSubscriptionStartedMonthly,
                                     conversionWindowDays: Constants.conversionWindowDays,
                                     value: "true")
    }

    func fireSubscriptionStartedYearlyPixel() {
        experimentPixelFirer.fireExperimentPixel(for: Constants.subfeatureIdentifier,
                                     metric: Constants.metricSubscriptionStartedYearly,
                                     conversionWindowDays: Constants.conversionWindowDays,
                                     value: "true")
    }
}
