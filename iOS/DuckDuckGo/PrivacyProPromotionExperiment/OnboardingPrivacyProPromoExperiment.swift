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

/// Protocol defining the interface for the Privacy Pro onboarding promotion experiment.
protocol OnboardingPrivacyProPromoExperimenting {
    /// Returns the experiment cohort if the feature is enabled, nil otherwise.
    func getCohortIfEnabled() -> PrivacyProOnboardingCTAMarch25Cohort?

    /// Returns the URL components for the experiment.
    func redirectURLComponents() -> URLComponents?

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

/// Implementation of the Privacy Pro onboarding promotion experiment that manages feature flagging,
/// analytics tracking, and checking subscription state for the PP Onboarding CTA experiment.
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

        /// The origin parameter value for the experiment.
        static let origin = "funnel_onboarding_ios"
    }

    /// A feature flagging service for managing feature flag experiments.
    private let featureFlagger: FeatureFlagger

    /// A type responsible for firing experiment-related analytics pixels.
    private let experimentPixelFirer: ExperimentPixelFiring.Type

    /// A manager for handling variant assignments.
    private let variantManager: VariantManager

    init(featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         experimentPixelFirer: ExperimentPixelFiring.Type = PixelKit.self,
         variantManager: VariantManager = DefaultVariantManager()) {
        self.featureFlagger = featureFlagger
        self.experimentPixelFirer = experimentPixelFirer
        self.variantManager = variantManager
    }

    /// Returns the experiment cohort if the feature is enabled, nil otherwise.
    func getCohortIfEnabled() -> PrivacyProOnboardingCTAMarch25Cohort? {

        // Exclude returning users from experiment enrollment
        guard variantManager.isNewUser else { return nil }

        return featureFlagger.resolveCohort(for: FeatureFlag.privacyProOnboardingCTAMarch25)
                as? PrivacyProOnboardingCTAMarch25Cohort
    }

    /// Returns the URL components for the experiment.
    func redirectURLComponents() -> URLComponents? {
        SubscriptionURL.purchaseURLComponentsWithOrigin(SubscriptionFunnelOrigin.onboarding.rawValue)
    }

    /// Fires a pixel when the onboarding promotion is shown.
    func fireImpressionPixel() {
        experimentPixelFirer.fireExperimentPixel(for: Constants.subfeatureIdentifier,
                                     metric: Constants.metricImpressions,
                                     conversionWindowDays: Constants.conversionWindowDays,
                                     value: "true")
    }

    /// Fires a pixel when the onboarding promotion is tapped.
    func fireTapPixel() {
        experimentPixelFirer.fireExperimentPixel(for: Constants.subfeatureIdentifier,
                                     metric: Constants.metricTap,
                                     conversionWindowDays: Constants.conversionWindowDays,
                                     value: "true")
    }

    /// Fires a pixel when the onboarding promotion is dismissed.
    func fireDismissPixel() {
        experimentPixelFirer.fireExperimentPixel(for: Constants.subfeatureIdentifier,
                                     metric: Constants.metricDismiss,
                                     conversionWindowDays: Constants.conversionWindowDays,
                                     value: "true")
    }

    /// Fires a pixel when a monthly subscription is started.
    func fireSubscriptionStartedMonthlyPixel() {
        experimentPixelFirer.fireExperimentPixel(for: Constants.subfeatureIdentifier,
                                     metric: Constants.metricSubscriptionStartedMonthly,
                                     conversionWindowDays: Constants.conversionWindowDays,
                                     value: "true")
    }

    /// Fires a pixel when a yearly subscription is started.
    func fireSubscriptionStartedYearlyPixel() {
        experimentPixelFirer.fireExperimentPixel(for: Constants.subfeatureIdentifier,
                                     metric: Constants.metricSubscriptionStartedYearly,
                                     conversionWindowDays: Constants.conversionWindowDays,
                                     value: "true")
    }
}

/// Extension providing user type determination functionality.
extension VariantManager {
    /// Indicates whether the current user is a new user based on their variant assignment.
    var isNewUser: Bool {
        currentVariant?.name != VariantIOS.returningUser.name
    }
}
