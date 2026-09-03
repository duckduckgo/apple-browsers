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

    // MARK: - First paywall, performance-optimized

    // With `performanceOptimizedPaywalls` on, the two entry points this app opens itself become:
    //
    //     VPN      (no featurePage)      /subscriptions/new/mobile/vpn
    //     Duck.ai  (featurePage=duckai)  /subscriptions/new/mobile/duckai
    //
    //     trial=true|false   always stated
    //     pir=false          only when the offering excludes Personal Information Removal
    //     origin             unchanged
    //
    // Everything else keeps today's URL: other featurePages, intercepted `/pro` links, desktop.

    func testFirstPaywallURLsWhenPerformanceOptimizedPaywallsIsOn() throws {
        // Given
        let vpn = SubscriptionURL.purchase.subscriptionURL(environment: .production)
        let duckai = try XCTUnwrap(SubscriptionURL.purchaseURLComponentsWithOriginAndFeaturePage(origin: nil,
                                                                                                featurePage: "duckai",
                                                                                                environment: .production)?.url)

        let cases: [(url: URL, isTrialEligible: Bool, isPIRAvailable: Bool, expected: String)] = [
            (vpn, false, true, "https://duckduckgo.com/subscriptions/new/mobile/vpn?trial=false"),
            (vpn, true, true, "https://duckduckgo.com/subscriptions/new/mobile/vpn?trial=true"),
            (vpn, false, false, "https://duckduckgo.com/subscriptions/new/mobile/vpn?trial=false&pir=false"),
            (vpn, true, false, "https://duckduckgo.com/subscriptions/new/mobile/vpn?trial=true&pir=false"),
            (duckai, false, true, "https://duckduckgo.com/subscriptions/new/mobile/duckai?trial=false"),
            (duckai, true, true, "https://duckduckgo.com/subscriptions/new/mobile/duckai?trial=true"),
            (duckai, false, false, "https://duckduckgo.com/subscriptions/new/mobile/duckai?trial=false&pir=false"),
            (duckai, true, false, "https://duckduckgo.com/subscriptions/new/mobile/duckai?trial=true&pir=false")
        ]

        for testCase in cases {
            // When
            let url = SubscriptionURL.performanceOptimizedPaywallURL(basedOn: testCase.url,
                                                                     isTrialEligible: testCase.isTrialEligible,
                                                                     isPersonalInformationRemovalAvailable: testCase.isPIRAvailable)

            // Then
            XCTAssertEqual(url?.absoluteString, testCase.expected)
        }
    }

    /// `trial` and `pir` pick what the page reveals, not which page it is, so screen matching has to
    /// ignore them.
    func testForComparisonIgnoresFirstPaywallStateParameters() throws {
        let page = URL(string: "https://duckduckgo.com/subscriptions/new/mobile/vpn")!
        let pageWithState = URL(string: "https://duckduckgo.com/subscriptions/new/mobile/vpn?trial=true&pir=false")!

        XCTAssertEqual(pageWithState.forComparison(), page.forComparison())
    }

    func testFirstPaywallURLKeepsOriginAndDropsFeaturePage() throws {
        // Given
        let origin = "funnel_appsettings_ios"
        let purchaseURL = try XCTUnwrap(SubscriptionURL.purchaseURLComponentsWithOriginAndFeaturePage(origin: origin,
                                                                                                     featurePage: "duckai",
                                                                                                     environment: .production)?.url)

        // When
        let url = SubscriptionURL.performanceOptimizedPaywallURL(basedOn: purchaseURL,
                                                                 isTrialEligible: true,
                                                                 isPersonalInformationRemovalAvailable: true)

        // Then
        XCTAssertEqual(url?.absoluteString,
                       "https://duckduckgo.com/subscriptions/new/mobile/duckai?origin=funnel_appsettings_ios&trial=true")
    }

    func testFirstPaywallURLKeepsStagingEnvironment() throws {
        // Given
        let purchaseURL = SubscriptionURL.purchase.subscriptionURL(environment: .staging)

        // When
        let url = SubscriptionURL.performanceOptimizedPaywallURL(basedOn: purchaseURL,
                                                                 isTrialEligible: false,
                                                                 isPersonalInformationRemovalAvailable: true)

        // Then
        XCTAssertEqual(url?.absoluteString,
                       "https://duckduckgo.com/subscriptions/new/mobile/vpn?environment=staging&trial=false")
    }

    func testFirstPaywallURLUsesCustomBaseURL() throws {
        // Given
        let customBaseURL = URL(string: "https://sdz0qh1x-80.eun1.devtunnels.ms/subscriptions")!
        let purchaseURL = SubscriptionURL.purchase.subscriptionURL(withCustomBaseURL: customBaseURL, environment: .production)

        // When
        let url = SubscriptionURL.performanceOptimizedPaywallURL(basedOn: purchaseURL,
                                                                 isTrialEligible: true,
                                                                 isPersonalInformationRemovalAvailable: true)

        // Then
        XCTAssertEqual(url?.absoluteString,
                       "https://sdz0qh1x-80.eun1.devtunnels.ms/subscriptions/new/mobile/vpn?trial=true")
    }

    func testFirstPaywallURLUsesConfiguredPaths() throws {
        // Given
        let paths = SubscriptionURL.PerformanceOptimizedPaywallPaths(vpn: "/subscriptions/v2/vpn",
                                                                    duckai: "/subscriptions/v2/duckai")
        let purchaseURL = SubscriptionURL.purchase.subscriptionURL(environment: .production)

        // When
        let url = SubscriptionURL.performanceOptimizedPaywallURL(basedOn: purchaseURL,
                                                                 paths: paths,
                                                                 isTrialEligible: false,
                                                                 isPersonalInformationRemovalAvailable: true)

        // Then
        XCTAssertEqual(url?.absoluteString, "https://duckduckgo.com/subscriptions/v2/vpn?trial=false")
    }

    func testFirstPaywallURLIsNotProducedForOtherFeaturePages() throws {
        // Given
        let purchaseURL = try XCTUnwrap(SubscriptionURL.purchaseURLComponentsWithOriginAndFeaturePage(
            origin: nil,
            featurePage: SubscriptionURL.FeaturePage.winback,
            environment: .production
        )?.url)

        // When
        let url = SubscriptionURL.performanceOptimizedPaywallURL(basedOn: purchaseURL,
                                                                 isTrialEligible: true,
                                                                 isPersonalInformationRemovalAvailable: true)

        // Then
        XCTAssertNil(url)
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
