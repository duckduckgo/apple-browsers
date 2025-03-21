//
//  OnboardingPrivacyProPromoExperimentTests.swift
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

import XCTest
@testable import DuckDuckGo
import PixelExperimentKit
import BrowserServicesKit
import Subscription
import SubscriptionTestingUtilities
import Core

final class OnboardingPrivacyProPromoExperimentTests: XCTestCase {

    private var sut: OnboardingPrivacyProPromoExperiment!
    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockVariantManager: MockVariantManager!

    override func setUpWithError() throws {
        mockFeatureFlagger = MockFeatureFlagger()
        mockVariantManager = MockVariantManager()
        sut = OnboardingPrivacyProPromoExperiment(featureFlagger: mockFeatureFlagger,
                                                  experimentPixelFirer: MockExperimentPixelFirer.self,
                                                  variantManager: mockVariantManager)
        MockExperimentPixelFirer.reset()
    }

    func testGetCohortIfEnabled_WhenNewUser_ReturnsTreatment() {
        // Given
        mockVariantManager.currentVariant = nil
        mockFeatureFlagger.cohortToReturn = PrivacyProOnboardingCTAMarch25Cohort.treatment
        sut = OnboardingPrivacyProPromoExperiment(featureFlagger: mockFeatureFlagger,
                                                  experimentPixelFirer: MockExperimentPixelFirer.self,
                                                  variantManager: mockVariantManager)


        // When
        let cohort = sut.getCohortIfEnabled()

        // Then
        XCTAssertEqual(cohort, .treatment)
    }

    func testGetCohortIfEnabled_WhenReturningUser_ReturnsNil() {
        // Given
        mockVariantManager.currentVariant = VariantIOS.returningUser
        mockFeatureFlagger.cohortToReturn = PrivacyProOnboardingCTAMarch25Cohort.treatment
        sut = OnboardingPrivacyProPromoExperiment(featureFlagger: mockFeatureFlagger,
                                                  experimentPixelFirer: MockExperimentPixelFirer.self,
                                                  variantManager: mockVariantManager)

        // When
        let cohort = sut.getCohortIfEnabled()

        // Then
        XCTAssertNil(cohort)
    }

    func testFireImpressionPixel_FiresCorrectPixel() {
        // When
        sut.fireImpressionPixel()

        // Then
        XCTAssertEqual(MockExperimentPixelFirer.firedMetrics.count, 1)
        let firedPixel = MockExperimentPixelFirer.firedMetrics.first
        XCTAssertEqual(firedPixel?.metric, "onboardingPromotionImpression")
        XCTAssertEqual(firedPixel?.value, "true")
    }

    func testFireTapPixel_FiresCorrectPixel() {
        // When
        sut.fireTapPixel()

        // Then
        XCTAssertEqual(MockExperimentPixelFirer.firedMetrics.count, 1)
        let firedPixel = MockExperimentPixelFirer.firedMetrics.first
        XCTAssertEqual(firedPixel?.metric, "onboardingPromotionTap")
        XCTAssertEqual(firedPixel?.value, "true")
    }

    func testFireDismissPixel_FiresCorrectPixel() {
        // When
        sut.fireDismissPixel()

        // Then
        XCTAssertEqual(MockExperimentPixelFirer.firedMetrics.count, 1)
        let firedPixel = MockExperimentPixelFirer.firedMetrics.first
        XCTAssertEqual(firedPixel?.metric, "onboardingPromotionDismiss")
        XCTAssertEqual(firedPixel?.value, "true")
    }

    func testFireSubscriptionStartedMonthlyPixel_FiresCorrectPixel() {
        // When
        sut.fireSubscriptionStartedMonthlyPixel()

        // Then
        XCTAssertEqual(MockExperimentPixelFirer.firedMetrics.count, 1)
        let firedPixel = MockExperimentPixelFirer.firedMetrics.first
        XCTAssertEqual(firedPixel?.metric, "subscriptionStartedMonthly")
        XCTAssertEqual(firedPixel?.value, "true")
    }

    func testFireSubscriptionStartedYearlyPixel_FiresCorrectPixel() {
        // When
        sut.fireSubscriptionStartedYearlyPixel()

        // Then
        XCTAssertEqual(MockExperimentPixelFirer.firedMetrics.count, 1)
        let firedPixel = MockExperimentPixelFirer.firedMetrics.first
        XCTAssertEqual(firedPixel?.metric, "subscriptionStartedYearly")
        XCTAssertEqual(firedPixel?.value, "true")
    }

    func testRedirectURLComponents_ReturnsCorrectlyFormattedURL() {
        // When
        let components = sut.redirectURLComponents()
        
        // Then
        XCTAssertNotNil(components)
        XCTAssertEqual(components?.scheme, "https")
        XCTAssertEqual(components?.host, "duckduckgo.com")
        XCTAssertEqual(components?.path, "/subscriptions")
        
        // Verify origin parameter
        let originItem = components?.queryItems?.first { $0.name == "origin" }
        XCTAssertNotNil(originItem)
        XCTAssertEqual(originItem?.value, OnboardingPrivacyProPromoExperiment.Constants.origin)
    }
}

private final class MockExperimentPixelFirer: ExperimentPixelFiring {
    struct FiredPixel {
        let subfeatureID: SubfeatureID
        let metric: String
        let conversionWindow: ConversionWindow
        let value: String
    }

    static private(set) var firedMetrics: [FiredPixel] = []

    static func fireExperimentPixel(for subfeatureID: SubfeatureID,
                                    metric: String,
                                    conversionWindowDays: ConversionWindow,
                                    value: String) {
        let firedPixel = FiredPixel(
            subfeatureID: subfeatureID,
            metric: metric,
            conversionWindow: conversionWindowDays,
            value: value
        )
        firedMetrics.append(firedPixel)
    }

    static func reset() {
        firedMetrics.removeAll()
    }
}
