//
//  OnboardingSubscriptionUpsellEligibilityTests.swift
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

import FeatureFlags_macOS
@_spi(Testing) import Networking
import PrivacyConfig
import Subscription
import SubscriptionTestingUtilities
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class OnboardingSubscriptionUpsellEligibilityTests: XCTestCase {

    private var featureFlagger: MockFeatureFlagger!
    private var subscriptionManager: SubscriptionManagerMock!
    private var sut: OnboardingSubscriptionUpsellEligibility!

    override func setUp() {
        super.setUp()
        featureFlagger = MockFeatureFlagger()
        subscriptionManager = SubscriptionManagerMock()
        subscriptionManager.currentEnvironment = .init(serviceEnvironment: .staging, purchasePlatform: .appStore)
        subscriptionManager.hasAppStoreProductsAvailable = true
        subscriptionManager.hasResolvedAppStoreProducts = true
        subscriptionManager.resultTokenContainer = nil
        sut = OnboardingSubscriptionUpsellEligibility(featureFlagger: featureFlagger, subscriptionManager: subscriptionManager)
    }

    override func tearDown() {
        sut = nil
        subscriptionManager = nil
        featureFlagger = nil
        super.tearDown()
    }

    func testWhenPurchaseEligibleAndNotSubscribedThenEligible() {
        XCTAssertEqual(sut.isUserEligible, true)
    }

    func testWhenProductsResolvedButUnavailableThenNotEligible() {
        subscriptionManager.hasAppStoreProductsAvailable = false

        XCTAssertEqual(sut.isUserEligible, false)
    }

    func testWhenProductsNotResolvedYetThenEligibilityIsUnknown() {
        subscriptionManager.hasAppStoreProductsAvailable = false
        subscriptionManager.hasResolvedAppStoreProducts = false

        XCTAssertNil(sut.isUserEligible)
    }

    func testWhenAlreadySignedInThenNotEligible() {
        subscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()

        XCTAssertEqual(sut.isUserEligible, false)
    }

    func testUpsellFollowsTheRemoteFlag() {
        featureFlagger.featuresStub[FeatureFlag.onboardingSubscriptionUpsell.rawValue] = true
        XCTAssertTrue(sut.isUpsellEnabled)

        featureFlagger.featuresStub[FeatureFlag.onboardingSubscriptionUpsell.rawValue] = false
        XCTAssertFalse(sut.isUpsellEnabled)
    }
}
