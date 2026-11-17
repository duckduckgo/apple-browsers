//
//  SubscriptionExperimentAttributionProviderTests.swift
//  DuckDuckGoTests
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

import BrowserServicesKit
import FeatureFlags_iOS
import Foundation
import PrivacyConfig
@testable import DuckDuckGo
@testable import Subscription
import XCTest

final class DefaultSubscriptionExperimentAttributionProviderTests: XCTestCase {
    func testWhenCollectingExperimentsThenNonSubscriptionParentsAreExcludedForPrivacy() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(allActiveExperiments: [
            "subscriptionExperiment": ExperimentData(
                parentID: PrivacyFeature.privacyPro.rawValue,
                cohortID: "treatment",
                enrollmentDate: Date()),
            "serpExperiment": ExperimentData(
                parentID: PrivacyFeature.contentScopeExperiments.rawValue,
                cohortID: "control",
                enrollmentDate: Date())
        ], featuresStub: [FeatureFlag.subscriptionConcurrentExperiments.rawValue: true])
        let provider = DefaultSubscriptionExperimentAttributionProvider(featureFlagger: featureFlagger)

        let attribution = provider.attribution(from: makeSelection())

        XCTAssertEqual(attribution, .multiple([
            SubscriptionExperiment(experimentName: "subscriptionExperiment", experimentCohort: "treatment")
        ]))
    }

    func testWhenPrivacyProExperimentsAreCollectedThenOrderingIsDeterministic() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(allActiveExperiments: [
            "second": ExperimentData(parentID: PrivacyFeature.privacyPro.rawValue, cohortID: "control", enrollmentDate: Date()),
            "first": ExperimentData(parentID: PrivacyFeature.privacyPro.rawValue, cohortID: "treatment", enrollmentDate: Date())
        ], featuresStub: [FeatureFlag.subscriptionConcurrentExperiments.rawValue: true])
        let provider = DefaultSubscriptionExperimentAttributionProvider(featureFlagger: featureFlagger)

        let attribution = provider.attribution(from: makeSelection())

        XCTAssertEqual(attribution, .multiple([
            SubscriptionExperiment(experimentName: "first", experimentCohort: "treatment"),
            SubscriptionExperiment(experimentName: "second", experimentCohort: "control")
        ]))
    }

    func testWhenThereAreNoActiveExperimentsThenAttributionIsOmitted() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(featuresStub: [FeatureFlag.subscriptionConcurrentExperiments.rawValue: true])
        let provider = DefaultSubscriptionExperimentAttributionProvider(featureFlagger: featureFlagger)

        XCTAssertNil(provider.attribution(from: makeSelection()))
    }

    func testWhenPaywallEntryWrapsMultipleExperimentsThenEntryIsAppended() {
        let experiment = SubscriptionExperiment(experimentName: "onboardingVPNDownloadReasonExperiment", experimentCohort: "treatment")
        let provider = PaywallEntryExperimentAttributionProvider(
            wrapping: StubAttributionProvider(attribution: .multiple([experiment])),
            entry: PaywallEntryExperimentAttributionProvider.vpnOnboardingPaywallEntry)

        XCTAssertEqual(provider.attribution(from: makeSelection()), .multiple([
            experiment,
            SubscriptionExperiment(experimentName: "vpnOnboardingPaywall", experimentCohort: "treatment")
        ]))
    }

    func testWhenPaywallEntryWrapsLegacyAttributionThenItIsUnchanged() {
        let legacy = PurchaseExperimentAttribution.legacy(SubscriptionExperiment(experimentName: "fe", experimentCohort: "a"))
        let provider = PaywallEntryExperimentAttributionProvider(
            wrapping: StubAttributionProvider(attribution: legacy),
            entry: PaywallEntryExperimentAttributionProvider.vpnOnboardingPaywallEntry)

        XCTAssertEqual(provider.attribution(from: makeSelection()), legacy)
    }

    func testWhenPaywallEntryWrapsNoAttributionThenNothingIsSent() {
        let provider = PaywallEntryExperimentAttributionProvider(
            wrapping: StubAttributionProvider(attribution: nil),
            entry: PaywallEntryExperimentAttributionProvider.vpnOnboardingPaywallEntry)

        XCTAssertNil(provider.attribution(from: makeSelection()))
    }

    func testWhenPaywallEntryIsAlreadyPresentThenItIsNotDuplicated() {
        let entry = PaywallEntryExperimentAttributionProvider.vpnOnboardingPaywallEntry
        let provider = PaywallEntryExperimentAttributionProvider(
            wrapping: StubAttributionProvider(attribution: .multiple([entry])),
            entry: entry)

        XCTAssertEqual(provider.attribution(from: makeSelection()), .multiple([entry]))
    }

    private func makeSelection() -> DefaultSubscriptionPagesUseSubscriptionFeature.SubscriptionSelection {
        DefaultSubscriptionPagesUseSubscriptionFeature.SubscriptionSelection(
            id: "product",
            experiment: nil,
            experiments: nil,
            scheduleNotification: nil)
    }
}

private struct StubAttributionProvider: SubscriptionExperimentAttributionProviding {
    let attribution: PurchaseExperimentAttribution?

    func attribution(from selection: DefaultSubscriptionPagesUseSubscriptionFeature.SubscriptionSelection) -> PurchaseExperimentAttribution? {
        attribution
    }
}
