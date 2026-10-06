//
//  DuckAISubscriptionUpsellPresenterTests.swift
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

import AIChat
@_spi(Testing) import PixelKit
import SubscriptionTestingUtilities
import XCTest
@testable import DuckDuckGo

final class DuckAISubscriptionUpsellPresenterTests: XCTestCase {

    private var notificationCenter: NotificationCenter!
    private var sut: DuckAISubscriptionUpsellPresenter!
    private var subscriptionManager: SubscriptionManagerMock!

    override func setUp() {
        super.setUp()
        notificationCenter = NotificationCenter()
        subscriptionManager = SubscriptionManagerMock()
        sut = DuckAISubscriptionUpsellPresenter(
            policy: DuckAISubscriptionUpsellPolicy(subscriptionManager: subscriptionManager),
            notificationCenter: notificationCenter)
    }

    override func tearDown() {
        sut = nil
        notificationCenter = nil
        subscriptionManager = nil
        super.tearDown()
    }

    func testPresentPurchaseFlowFromReasoningPickerInAddressBarPostsSubscriptionFlowWithAddressBarOrigin() {
        let expectation = expectation(forNotification: .settingsDeepLinkNotification, object: nil, notificationCenter: notificationCenter) { notification in
            guard let deepLink = notification.object as? SettingsViewModel.SettingsDeepLinkSection,
                  case .subscriptionFlow(let components) = deepLink else {
                return false
            }
            return self.hasQueryItem(in: components, name: "featurePage", value: "duckai")
                && self.hasQueryItem(in: components, name: "origin", value: "funnel_addressbar_ios__reasoningdropdown")
        }

        sut.presentPurchaseFlow(source: .reasoningPicker, isAITabState: false)

        wait(for: [expectation], timeout: 1.0)
    }

    func testPresentUpgradeFlowFromReasoningPickerInAddressBarPostsPlanChangeFlowWithAddressBarOrigin() {
        let expectation = expectation(forNotification: .settingsDeepLinkNotification, object: nil, notificationCenter: notificationCenter) { notification in
            guard let deepLink = notification.object as? SettingsViewModel.SettingsDeepLinkSection,
                  case .subscriptionPlanChangeFlow(let components) = deepLink else {
                return false
            }
            return self.hasQueryItem(in: components, name: "origin", value: "funnel_addressbar_ios__reasoningdropdown")
        }

        sut.presentUpgradeFlow(source: .reasoningPicker, isAITabState: false)

        wait(for: [expectation], timeout: 1.0)
    }

    func testPresentPurchaseFlowFromReasoningPickerInAITabUsesDuckAIOrigin() {
        let expectation = expectation(forNotification: .settingsDeepLinkNotification, object: nil, notificationCenter: notificationCenter) { notification in
            guard let deepLink = notification.object as? SettingsViewModel.SettingsDeepLinkSection,
                  case .subscriptionFlow(let components) = deepLink else {
                return false
            }
            return self.hasQueryItem(in: components, name: "origin", value: "funnel_duckai_ios__reasoningdropdown")
        }

        sut.presentPurchaseFlow(source: .reasoningPicker, isAITabState: true)

        wait(for: [expectation], timeout: 1.0)
    }

    func testPresentPurchaseFlowFromModelPickerInAddressBarUsesModelPickerOrigin() {
        let expectation = expectation(forNotification: .settingsDeepLinkNotification, object: nil, notificationCenter: notificationCenter) { notification in
            guard let deepLink = notification.object as? SettingsViewModel.SettingsDeepLinkSection,
                  case .subscriptionFlow(let components) = deepLink else {
                return false
            }
            return self.hasQueryItem(in: components, name: "origin", value: "funnel_addressbar_ios__modelpicker")
        }

        sut.presentPurchaseFlow(source: .modelPicker, isAITabState: false)

        wait(for: [expectation], timeout: 1.0)
    }

    func testPresentPurchaseFlowFromChatHeaderPlateCarriesFeaturePageAndFreeLabelOrigin() {
        let expectation = expectation(forNotification: .settingsDeepLinkNotification, object: nil, notificationCenter: notificationCenter) { notification in
            guard let deepLink = notification.object as? SettingsViewModel.SettingsDeepLinkSection,
                  case .subscriptionFlow(let components) = deepLink else {
                return false
            }
            return self.hasQueryItem(in: components, name: "featurePage", value: "duckai")
                && self.hasQueryItem(in: components, name: "origin", value: "funnel_duckai_ios__freelabel")
        }

        sut.presentPurchaseFlow(origin: .duckAIFreeLabel)

        wait(for: [expectation], timeout: 1.0)
    }

    func testUnavailablePurchaseRejectsBothEntryPointsAndGatedRouting() {
        subscriptionManager.hasAppStoreProductsAvailable = false
        let pixelKit = PixelKitMock()
        let notification = expectation(forNotification: .settingsDeepLinkNotification, object: nil, notificationCenter: notificationCenter)
        notification.isInverted = true

        sut.presentPurchaseFlow(source: .modelPicker, isAITabState: true)
        sut.presentPurchaseFlow(origin: .duckAIFreeLabel)
        for source in [SubscriptionFlowSource.modelPicker, .reasoningPicker] {
            XCTAssertFalse(sut.routeGatedSelection(requiredTier: .plus, userTier: .free, source: source,
                                                   isAITabState: true, firing: UTIPixelFiring(pixelKit: { pixelKit })))
        }
        XCTAssertTrue(pixelKit.actualFireCalls.isEmpty)

        wait(for: [notification], timeout: 0.1)
    }

    func testPlusUpgradeStillRoutesWhenAppStoreProductsAreUnavailable() {
        subscriptionManager.hasAppStoreProductsAvailable = false
        let notification = expectation(forNotification: .settingsDeepLinkNotification, object: nil, notificationCenter: notificationCenter) {
            guard let section = $0.object as? SettingsViewModel.SettingsDeepLinkSection,
                  case .subscriptionPlanChangeFlow = section else { return false }
            return true
        }

        XCTAssertTrue(sut.routeGatedSelection(requiredTier: .pro, userTier: .plus, source: .reasoningPicker, isAITabState: true))

        wait(for: [notification], timeout: 1)
    }

    // MARK: - Helpers

    private func hasQueryItem(in components: URLComponents?, name: String, value: String) -> Bool {
        components?.queryItems?.contains { $0.name == name && $0.value == value } == true
    }
}

final class DuckAISubscriptionUpsellPolicyTests: XCTestCase {
    func testVisibilityReadsCurrentEligibilityAndPreservesSubscriberUpsells() {
        let manager = SubscriptionManagerMock()
        manager.hasAppStoreProductsAvailable = false
        let policy = DuckAISubscriptionUpsellPolicy(subscriptionManager: manager)

        XCTAssertFalse(policy.isPurchaseEligible)
        XCTAssertFalse(policy.allowsUpsell(for: .free))
        XCTAssertTrue(policy.allowsUpsell(for: .plus))
        XCTAssertTrue(policy.allowsUpsell(for: .pro))

        manager.hasAppStoreProductsAvailable = true
        XCTAssertTrue(policy.isPurchaseEligible)
        XCTAssertTrue(policy.allowsUpsell(for: .free))

        manager.hasAppStoreProductsAvailable = false
        XCTAssertFalse(policy.isPurchaseEligible)
        XCTAssertFalse(policy.allowsUpsell(for: .free))
    }

    func testStripeEligibilityUsesManagerDecisionWithoutAppStoreProducts() {
        let manager = SubscriptionManagerMock()
        manager.currentEnvironment = .init(serviceEnvironment: .staging, purchasePlatform: .stripe)
        manager.hasAppStoreProductsAvailable = false

        XCTAssertTrue(DuckAISubscriptionUpsellPolicy(subscriptionManager: manager).allowsUpsell(for: .free))
    }
}
