//
//  OnboardingPrivacyProPromotionHelpingTests.swift
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
import Core
import SubscriptionTestingUtilities
@testable import DuckDuckGo

final class OnboardingPrivacyProPromotionHelpingTests: XCTestCase {

    private var sut: OnboardingPrivacyProPromotionHelping!
    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockSubscriptionAuthV1toV2Bridge: SubscriptionAuthV1toV2BridgeMock!
    private var mockPixelFiring: PixelFiringMock!

    override func setUpWithError() throws {
        mockFeatureFlagger = MockFeatureFlagger()
        mockSubscriptionAuthV1toV2Bridge = SubscriptionAuthV1toV2BridgeMock()
        
        sut = OnboardingPrivacyProPromotionHelper(
            featureFlagger: mockFeatureFlagger,
            subscriptionManager: mockSubscriptionAuthV1toV2Bridge,
            pixelFiring: PixelFiringMock.self
        )
    }

    override func tearDownWithError() throws {
        sut = nil
        mockFeatureFlagger = nil
        mockSubscriptionAuthV1toV2Bridge = nil
        PixelFiringMock.tearDown()
    }

    // MARK: - shouldDisplay Tests

    func testShouldDisplayWhenFeatureFlagEnabledAndCanPurchase() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [FeatureFlag.privacyProOnboardingPromotion]
        mockSubscriptionAuthV1toV2Bridge.canPurchase = true

        // When
        let result = sut.shouldDisplay

        // Then
        XCTAssertTrue(result)
    }

    func testShouldNotDisplayWhenFeatureFlagDisabled() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = []
        mockSubscriptionAuthV1toV2Bridge.canPurchase = true

        // When
        let result = sut.shouldDisplay

        // Then
        XCTAssertFalse(result)
    }

    func testShouldNotDisplayWhenCannotPurchase() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [FeatureFlag.privacyProOnboardingPromotion]
        mockSubscriptionAuthV1toV2Bridge.canPurchase = false

        // When
        let result = sut.shouldDisplay

        // Then
        XCTAssertFalse(result)
    }

    // MARK: - Pixel Firing Tests

    func testFireImpressionPixel() {
        // When
        sut.fireImpressionPixel()

        // Then
        XCTAssertEqual(PixelFiringMock.allPixelsFired.count, 1)
        XCTAssertEqual(PixelFiringMock.allPixelsFired.first?.pixelName, Pixel.Event.privacyProOnboardingPromotionImpression.name)
    }

    func testFireTapPixel() {
        // When
        sut.fireTapPixel()

        // Then
        XCTAssertEqual(PixelFiringMock.allPixelsFired.count, 1)
        XCTAssertEqual(PixelFiringMock.allPixelsFired.first?.pixelName, Pixel.Event.privacyProOnboardingPromotionTap.name)
    }

    func testFireDismissPixel() {
        // When
        sut.fireDismissPixel()

        // Then
        XCTAssertEqual(PixelFiringMock.allPixelsFired.count, 1)
        XCTAssertEqual(PixelFiringMock.allPixelsFired.first?.pixelName, Pixel.Event.privacyProOnboardingPromotionDismiss.name)
    }

    // MARK: - Redirect URL Tests

    func testRedirectURLComponents() {
        // When
        let components = sut.redirectURLComponents()

        // Then
        XCTAssertNotNil(components)
        XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "origin" })?.value, OnboardingPrivacyProPromotionHelper.Constants.origin)
    }
}
