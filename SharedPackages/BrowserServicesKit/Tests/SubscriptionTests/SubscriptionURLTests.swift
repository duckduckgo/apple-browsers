//
//  SubscriptionURLTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import XCTest
@testable import Subscription
import SubscriptionTestingUtilities

final class SubscriptionURLTests: XCTestCase {

    func testExpectedDefaultBaseSubscriptionURLForProduction() throws {
        // Given
        let expectedURL = URL(string: "https://duckduckgo.com/subscriptions")!

        // When
        let url = SubscriptionURL.baseURL.subscriptionURL(environment: .production)

        // Then
        XCTAssertEqual(url, expectedURL)
    }

    func testExpectedDefaultBaseSubscriptionURLForStaging() throws {
        // Given
        let expectedURL = URL(string: "https://duckduckgo.com/subscriptions?environment=staging")!

        // When
        let url = SubscriptionURL.baseURL.subscriptionURL(environment: .staging)

        // Then
        XCTAssertEqual(url, expectedURL)
    }

    func testProductionURLs() throws {
        let allURLTypes: [SubscriptionURL] = [.baseURL,
                                              .purchase,
                                              .welcome,
                                              .activationFlow,
                                              .activationFlowAddEmailStep,
                                              .activationFlowLinkViaEmailStep,
                                              .activationFlowSuccess,
                                              .manageEmail,
                                              .identityTheftRestoration,
                                              .plans,
                                              .addEmail,
                                              .addEmailSuccess,
                                              .upgradeToTier("pro")]

        for urlType in allURLTypes {
            // When
            let url = urlType.subscriptionURL(environment: .production)

            // Then
            let environmentParameter = url.getParameter(named: "environment")
            XCTAssertEqual (environmentParameter, nil, "Wrong environment parameter for \(url.absoluteString)")
        }
    }

    func testStagingURLs() throws {
        let allURLTypes: [SubscriptionURL] = [.baseURL,
                                              .purchase,
                                              .welcome,
                                              .activationFlow,
                                              .activationFlowAddEmailStep,
                                              .activationFlowLinkViaEmailStep,
                                              .activationFlowSuccess,
                                              .manageEmail,
                                              .identityTheftRestoration,
                                              .plans,
                                              .addEmail,
                                              .addEmailSuccess,
                                              .upgradeToTier("pro")]

        for urlType in allURLTypes {
            // When
            let url = urlType.subscriptionURL(environment: .staging)

            // Then
            let environmentParameter = url.getParameter(named: "environment")
            XCTAssertEqual (environmentParameter, "staging", "Wrong environment parameter for \(url.absoluteString)")
        }
    }

    func testIdentityTheftRestorationURLForProduction() throws {
        // Given
        let expectedURL = URL(string: "https://duckduckgo.com/identity-theft-restoration")!

        // When
        let url = SubscriptionURL.identityTheftRestoration.subscriptionURL(environment: .production)

        // Then
        XCTAssertEqual(url, expectedURL)
    }

    func testPlansURLForProduction() throws {
        // Given
        let expectedURL = URL(string: "https://duckduckgo.com/subscriptions/plans")!

        // When
        let url = SubscriptionURL.plans.subscriptionURL(environment: .production)

        // Then
        XCTAssertEqual(url, expectedURL)
    }

    func testPlansURLForStaging() throws {
        // Given
        let expectedURL = URL(string: "https://duckduckgo.com/subscriptions/plans?environment=staging")!

        // When
        let url = SubscriptionURL.plans.subscriptionURL(environment: .staging)

        // Then
        XCTAssertEqual(url, expectedURL)
    }

    func testSubscriptionPurchaseFlowPathContainsPath() throws {
        XCTAssertTrue(SubscriptionPurchaseFlowPath.contains("/subscriptions"))
        XCTAssertTrue(SubscriptionPurchaseFlowPath.contains("/subscriptions/plans"))
        XCTAssertTrue(SubscriptionPurchaseFlowPath.contains("/pro"))
        XCTAssertTrue(SubscriptionPurchaseFlowPath.contains("/pro/plans"))
        XCTAssertFalse(SubscriptionPurchaseFlowPath.contains("/subscriptions/manage"))
    }

    func testSubscriptionPurchaseFlowPathIdentifiesPlansPaths() throws {
        XCTAssertTrue(SubscriptionPurchaseFlowPath.isPlansPath("/subscriptions/plans"))
        XCTAssertTrue(SubscriptionPurchaseFlowPath.isPlansPath("/pro/plans"))
        XCTAssertFalse(SubscriptionPurchaseFlowPath.isPlansPath("/subscriptions"))
        XCTAssertFalse(SubscriptionPurchaseFlowPath.isPlansPath("/pro"))
    }

    func testCustomBaseSubscriptionURLForPlansURL() throws {
        // Given
        let customBaseURL = URL(string: "https://dax.duck.co/subscriptions")!
        let expectedURL = URL(string: "https://dax.duck.co/subscriptions/plans")!

        // When
        let url = SubscriptionURL.plans.subscriptionURL(withCustomBaseURL: customBaseURL, environment: .production)

        // Then
        XCTAssertEqual(url, expectedURL)
    }

    // MARK: - Upgrade To Tier URL Tests (Dynamic Tier)

    func testUpgradeToTierURLWithProTier() throws {
        // Given
        let expectedURL = URL(string: "https://duckduckgo.com/subscriptions/plans?tier=pro")!

        // When
        let url = SubscriptionURL.upgradeToTier("pro").subscriptionURL(environment: .production)

        // Then
        XCTAssertEqual(url, expectedURL)
    }

    func testUpgradeToTierURLWithPlusTier() throws {
        // Given - dynamic tier from backend
        let expectedURL = URL(string: "https://duckduckgo.com/subscriptions/plans?tier=plus")!

        // When
        let url = SubscriptionURL.upgradeToTier("plus").subscriptionURL(environment: .production)

        // Then
        XCTAssertEqual(url, expectedURL)
    }

    func testUpgradeToTierURLForStaging() throws {
        // Given
        let expectedURL = URL(string: "https://duckduckgo.com/subscriptions/plans?tier=plus&environment=staging")!

        // When
        let url = SubscriptionURL.upgradeToTier("plus").subscriptionURL(environment: .staging)

        // Then
        XCTAssertEqual(url, expectedURL)
    }

    func testCustomBaseSubscriptionURLForUpgradeToTierURL() throws {
        // Given
        let customBaseURL = URL(string: "https://dax.duck.co/subscriptions")!
        let expectedURL = URL(string: "https://dax.duck.co/subscriptions/plans?tier=plus")!

        // When
        let url = SubscriptionURL.upgradeToTier("plus").subscriptionURL(withCustomBaseURL: customBaseURL, environment: .production)

        // Then
        XCTAssertEqual(url, expectedURL)
    }

    func testStaticURLs() throws {
        let faqProductionURL = SubscriptionURL.faq.subscriptionURL(environment: .production)
        let faqStagingURL = SubscriptionURL.faq.subscriptionURL(environment: .staging)

        XCTAssertEqual(faqStagingURL, faqProductionURL)
        XCTAssertEqual(faqProductionURL.absoluteString, "https://duckduckgo.com/duckduckgo-help-pages/privacy-pro/")

        let manageSubscriptionsInAppStoreProductionURL = SubscriptionURL.manageSubscriptionsInAppStore.subscriptionURL(environment: .production)
        let manageSubscriptionsInAppStoreStagingURL = SubscriptionURL.manageSubscriptionsInAppStore.subscriptionURL(environment: .staging)

        XCTAssertEqual(manageSubscriptionsInAppStoreStagingURL, manageSubscriptionsInAppStoreProductionURL)
        XCTAssertEqual(manageSubscriptionsInAppStoreProductionURL.absoluteString, "macappstores://apps.apple.com/account/subscriptions")
    }

    func testURLForComparisonRemovingEnvironment() throws {
        let url = URL(string: "https://duckduckgo.com/subscriptions?environment=staging")!
        let expectedURL = URL(string: "https://duckduckgo.com/subscriptions")!

        XCTAssertEqual(url.forComparison(), expectedURL)
    }

    func testURLForComparisonRemovesOrigin() throws {
        let url = URL(string: "https://duckduckgo.com/subscriptions?origin=test")!
        let expectedURL = URL(string: "https://duckduckgo.com/subscriptions")!

        XCTAssertEqual(url.forComparison(), expectedURL)
    }

    func testURLForComparisonRemovesEnvironmentAndOrigin() throws {
        let url = URL(string: "https://duckduckgo.com/subscriptions?environment=staging&origin=test")!
        let expectedURL = URL(string: "https://duckduckgo.com/subscriptions")!

        XCTAssertEqual(url.forComparison(), expectedURL)
    }

    func testURLForComparisonRemovesEnvironmentAndOriginButRetainsOtherParameters() throws {
        let url = URL(string: "https://duckduckgo.com/subscriptions?environment=staging&foo=bar&origin=test")!
        let expectedURL = URL(string: "https://duckduckgo.com/subscriptions?foo=bar")!

        XCTAssertEqual(url.forComparison(), expectedURL)
    }

    func testURLForComparisonRemovesMonthlyFreeTrialExperimentCohort() throws {
        let url = URL(string: "https://duckduckgo.com/subscriptions?experiment_mobileannualtrials2_ios=control")!
        let expectedURL = URL(string: "https://duckduckgo.com/subscriptions")!

        XCTAssertEqual(url.forComparison(), expectedURL)
    }

    func testCustomBaseSubscriptionURLForProduction() throws {
        // Given
        let customBaseURL = URL(string: "https://dax.duck.co/subscriptions-test")!

        // When
        let url = SubscriptionURL.baseURL.subscriptionURL(withCustomBaseURL: customBaseURL, environment: .production)

        // Then
        XCTAssertEqual(url, customBaseURL)
    }

    func testCustomBaseSubscriptionURLForActivationFlowURL() throws {
        // Given
        let customBaseURL = URL(string: "https://dax.duck.co/subscriptions")!
        let expectedURL = customBaseURL.appendingPathComponent("activation-flow")

        // When
        let url = SubscriptionURL.activationFlow.subscriptionURL(withCustomBaseURL: customBaseURL, environment: .production)

        // Then
        XCTAssertEqual(url, expectedURL)
    }

    func testCustomBaseSubscriptionURLForIdentityTheftRestorationURL() throws {
        // Given
        let customBaseURL = URL(string: "https://dax.duck.co/subscriptions")!
        let expectedURL = URL(string: "https://dax.duck.co/identity-theft-restoration")!

        // When
        let url = SubscriptionURL.identityTheftRestoration.subscriptionURL(withCustomBaseURL: customBaseURL, environment: .production)

        // Then
        XCTAssertEqual(url, expectedURL)
    }

    func testPurchaseURLComponentsWithOriginForProduction() throws {
        // Given
        let origin = "funnel_appsettings_ios"
        let expectedURL = URL(string: "https://duckduckgo.com/subscriptions?origin=funnel_appsettings_ios")!

        // When
        let components = SubscriptionURL.purchaseURLComponentsWithOrigin(origin, environment: .production)

        // Then
        XCTAssertNotNil(components)
        XCTAssertEqual(components?.url, expectedURL)
    }

    func testPurchaseURLComponentsWithOriginForStaging() throws {
        // Given
        let origin = "funnel_appsettings_ios"
        let expectedURL = URL(string: "https://duckduckgo.com/subscriptions?environment=staging&origin=funnel_appsettings_ios")!

        // When
        let components = SubscriptionURL.purchaseURLComponentsWithOrigin(origin, environment: .staging)

        // Then
        XCTAssertNotNil(components)
        XCTAssertEqual(components?.url, expectedURL)
    }

    func testPurchaseURLComponentsWithOriginWithEmptyOrigin() throws {
        // Given
        let origin = ""
        let expectedURL = URL(string: "https://duckduckgo.com/subscriptions?origin=")!

        // When
        let components = SubscriptionURL.purchaseURLComponentsWithOrigin(origin, environment: .production)

        // Then
        XCTAssertNotNil(components)
        XCTAssertEqual(components?.url, expectedURL)
    }

    func testPurchaseURLComponentsWithOriginAndFeaturePageForProduction() throws {
        // Given
        let origin = "funnel_appsettings_ios"
        let featurePage = "duckai"
        let expectedURL = URL(string: "https://duckduckgo.com/subscriptions?origin=funnel_appsettings_ios&featurePage=duckai")!

        // When
        let components = SubscriptionURL.purchaseURLComponentsWithOriginAndFeaturePage(origin: origin, featurePage: featurePage, environment: .production)

        // Then
        XCTAssertNotNil(components)
        XCTAssertEqual(components?.url, expectedURL)
    }

    func testPurchaseURLComponentsWithOriginAndFeaturePageForStaging() throws {
        // Given
        let origin = "funnel_appsettings_ios"
        let featurePage = "duckai"
        let expectedURL = URL(string: "https://duckduckgo.com/subscriptions?environment=staging&origin=funnel_appsettings_ios&featurePage=duckai")!

        // When
        let components = SubscriptionURL.purchaseURLComponentsWithOriginAndFeaturePage(origin: origin, featurePage: featurePage, environment: .staging)

        // Then
        XCTAssertNotNil(components)
        XCTAssertEqual(components?.url, expectedURL)
    }

    func testPurchaseURLComponentsWithNilOriginAndFeaturePage() throws {
        // Given
        let expectedURL = URL(string: "https://duckduckgo.com/subscriptions")!

        // When
        let components = SubscriptionURL.purchaseURLComponentsWithOriginAndFeaturePage(origin: nil, featurePage: nil, environment: .production)

        // Then
        XCTAssertNotNil(components)
        XCTAssertEqual(components?.url, expectedURL)
    }

    func testPurchaseURLComponentsWithOnlyFeaturePage() throws {
        // Given
        let featurePage = "duckai"
        let expectedURL = URL(string: "https://duckduckgo.com/subscriptions?featurePage=duckai")!

        // When
        let components = SubscriptionURL.purchaseURLComponentsWithOriginAndFeaturePage(origin: nil, featurePage: featurePage, environment: .production)

        // Then
        XCTAssertNotNil(components)
        XCTAssertEqual(components?.url, expectedURL)
    }

    // MARK: - First paywall, performance-optimized (not implemented)

    // The `performanceOptimizedPaywalls` flag is wired but unread. When it is on, the two first-paywall
    // entry points this app opens itself have to be opened at a URL that names the page and states
    // what the page would otherwise resolve after mount, instead of `/subscriptions` plus a
    // `featurePage` item.
    //
    //     entry point                     URL
    //     ---------------------------------------------------------------------------------
    //     VPN      (no featurePage)       /subscriptions/new/mobile/vpn
    //     Duck.ai  (featurePage=duckai)   /subscriptions/new/mobile/duckai
    //
    //     query item   values                when
    //     ---------------------------------------------------------------------------------
    //     trial        true | false          always, whichever it is
    //     pir          false                 only when the offering excludes Personal Information
    //                                        Removal; the page shows PIR unless told otherwise
    //     origin       unchanged             carried as it is today
    //
    // So the full set is eight URLs, e.g.
    //
    //     https://duckduckgo.com/subscriptions/new/mobile/vpn?trial=false
    //     https://duckduckgo.com/subscriptions/new/mobile/duckai?trial=true&pir=false
    //
    // `trial` is whether the offering includes a free trial; `pir` is whether it includes Personal
    // Information Removal, which is sold in the USA storefront and not in the rest of the world. Both
    // have to be settled before the URL is opened — that is the whole point, since the page ships
    // both CTA labels and both feature lists and reveals one from the URL. Where they are read from,
    // whether the store is allowed to be waited on, and what happens when it never answers are open
    // questions, deliberately not answered here.
    //
    // What must not move: `pir`, `stripe` and `winback` featurePages, intercepted `/pro` links, and
    // every desktop entry point stay on the URL they use today. The first two create or refresh a
    // cart account on mount, which would make a load-time comparison measure the network.

    /// Skipped until something produces the URLs above. Delete the `XCTSkipIf` to see it fail, then
    /// replace the `XCTFail` with assertions against whatever ends up building them.
    func testFirstPaywallURLsWhenPerformanceOptimizedPaywallsIsOn() throws {
        try XCTSkipIf(true, "Pending: the server-rendered first paywall is not implemented")

        let required = [
            "https://duckduckgo.com/subscriptions/new/mobile/vpn?trial=false",
            "https://duckduckgo.com/subscriptions/new/mobile/vpn?trial=true",
            "https://duckduckgo.com/subscriptions/new/mobile/vpn?trial=false&pir=false",
            "https://duckduckgo.com/subscriptions/new/mobile/vpn?trial=true&pir=false",
            "https://duckduckgo.com/subscriptions/new/mobile/duckai?trial=false",
            "https://duckduckgo.com/subscriptions/new/mobile/duckai?trial=true",
            "https://duckduckgo.com/subscriptions/new/mobile/duckai?trial=false&pir=false",
            "https://duckduckgo.com/subscriptions/new/mobile/duckai?trial=true&pir=false"
        ]

        XCTFail("Nothing produces the server-rendered first paywall URLs yet: \(required.joined(separator: ", "))")
    }

    /// Skipped until the state items are ignored when matching screens. `trial` and `pir` choose what
    /// the page reveals, not which page it is, so every "am I on the purchase screen?" check — and
    /// the offer-screen impression that the whole comparison is read from — has to see through them.
    ///
    /// This one is a real assertion already: delete the `XCTSkipIf` and it fails against today's
    /// `forComparison()`.
    func testForComparisonIgnoresFirstPaywallStateParameters() throws {
        try XCTSkipIf(true, "Pending: forComparison() does not ignore trial and pir yet")

        let page = URL(string: "https://duckduckgo.com/subscriptions/new/mobile/vpn")!
        let pageWithState = URL(string: "https://duckduckgo.com/subscriptions/new/mobile/vpn?trial=true&pir=false")!

        XCTAssertEqual(pageWithState.forComparison(), page.forComparison())
    }

    func testPurchaseURLComponentsWithOnlyOrigin() throws {
        // Given
        let origin = "funnel_appsettings_ios"
        let expectedURL = URL(string: "https://duckduckgo.com/subscriptions?origin=funnel_appsettings_ios")!

        // When
        let components = SubscriptionURL.purchaseURLComponentsWithOriginAndFeaturePage(origin: origin, featurePage: nil, environment: .production)

        // Then
        XCTAssertNotNil(components)
        XCTAssertEqual(components?.url, expectedURL)
    }

    func testPurchaseURLComponentsWithEmptyOriginAndFeaturePage() throws {
        // Given
        let origin = ""
        let featurePage = ""
        let expectedURL = URL(string: "https://duckduckgo.com/subscriptions?origin=&featurePage=")!

        // When
        let components = SubscriptionURL.purchaseURLComponentsWithOriginAndFeaturePage(origin: origin, featurePage: featurePage, environment: .production)

        // Then
        XCTAssertNotNil(components)
        XCTAssertEqual(components?.url, expectedURL)
    }

    // MARK: - plansURLComponents Tests

    func testPlansURLComponentsForProduction() throws {
        // Given
        let origin = "funnel_appsettings_ios"
        let expectedURL = URL(string: "https://duckduckgo.com/subscriptions/plans?origin=funnel_appsettings_ios")!

        // When
        let components = SubscriptionURL.plansURLComponents(origin, environment: .production)

        // Then
        XCTAssertNotNil(components)
        XCTAssertEqual(components?.url, expectedURL)
    }

    func testPlansURLComponentsForStaging() throws {
        // Given
        let origin = "funnel_appsettings_ios"
        let expectedURL = URL(string: "https://duckduckgo.com/subscriptions/plans?environment=staging&origin=funnel_appsettings_ios")!

        // When
        let components = SubscriptionURL.plansURLComponents(origin, environment: .staging)

        // Then
        XCTAssertNotNil(components)
        XCTAssertEqual(components?.url, expectedURL)
    }

    func testPlansURLComponentsWithTierForProduction() throws {
        // Given
        let origin = "funnel_appsettings_ios"
        let expectedURL = URL(string: "https://duckduckgo.com/subscriptions/plans?origin=funnel_appsettings_ios&tier=pro")!

        // When
        let components = SubscriptionURL.plansURLComponents(origin, tier: "pro", environment: .production)

        // Then
        XCTAssertNotNil(components)
        XCTAssertEqual(components?.url, expectedURL)
    }

    func testPlansURLComponentsWithTierForStaging() throws {
        // Given
        let origin = "funnel_appsettings_ios"
        let expectedURL = URL(string: "https://duckduckgo.com/subscriptions/plans?environment=staging&origin=funnel_appsettings_ios&tier=pro")!

        // When
        let components = SubscriptionURL.plansURLComponents(origin, tier: "pro", environment: .staging)

        // Then
        XCTAssertNotNil(components)
        XCTAssertEqual(components?.url, expectedURL)
    }

    func testPlansURLComponentsWithDynamicTier() throws {
        // Given - tier comes from backend's available upgrade tiers
        let origin = "funnel_appsettings_ios"
        let dynamicTier = "plus"  // Example: backend returns "plus" as available upgrade tier
        let expectedURL = URL(string: "https://duckduckgo.com/subscriptions/plans?origin=funnel_appsettings_ios&tier=plus")!

        // When
        let components = SubscriptionURL.plansURLComponents(origin, tier: dynamicTier, environment: .production)

        // Then
        XCTAssertNotNil(components)
        XCTAssertEqual(components?.url, expectedURL)
    }

    func testPlansURLComponentsWithEmptyOrigin() throws {
        // Given
        let origin = ""
        let expectedURL = URL(string: "https://duckduckgo.com/subscriptions/plans?origin=")!

        // When
        let components = SubscriptionURL.plansURLComponents(origin, environment: .production)

        // Then
        XCTAssertNotNil(components)
        XCTAssertEqual(components?.url, expectedURL)
    }
}
