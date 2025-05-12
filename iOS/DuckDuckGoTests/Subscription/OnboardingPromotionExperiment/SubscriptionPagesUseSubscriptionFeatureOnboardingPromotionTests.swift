//
//  SubscriptionPagesUseSubscriptionFeatureOnboardingPromotionTests.swift
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
import BrowserServicesKit
import SubscriptionTestingUtilities
import Core
@testable import Subscription
@testable import DuckDuckGo

final class SubscriptionPagesUseSubscriptionFeatureOnboardingPromotionTests: XCTestCase {

    private var sut: (any SubscriptionPagesUseSubscriptionFeature)!

    private var mockSubscriptionManager: SubscriptionManagerMock!
    private var mockAccountManager: AccountManagerMock!
    private var mockStorePurchaseManager: StorePurchaseManagerMock!
    private var mockAppStorePurchaseFlow: AppStorePurchaseFlowMock!

    override func setUpWithError() throws {
        mockAccountManager = AccountManagerMock()
        mockStorePurchaseManager = StorePurchaseManagerMock()
        mockSubscriptionManager = SubscriptionManagerMock(accountManager: mockAccountManager,
                                                      subscriptionEndpointService: SubscriptionEndpointServiceMock(),
                                                      authEndpointService: AuthEndpointServiceMock(),
                                                      storePurchaseManager: mockStorePurchaseManager,
                                                      currentEnvironment: SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore),
                                                      canPurchase: true,
                                                      subscriptionFeatureMappingCache: SubscriptionFeatureMappingCacheMock())

        mockAppStorePurchaseFlow = AppStorePurchaseFlowMock()

        sut = DefaultSubscriptionPagesUseSubscriptionFeature(subscriptionManager: mockSubscriptionManager,
                                                             subscriptionFeatureAvailability: SubscriptionFeatureAvailabilityMock.enabled,
                                                             subscriptionAttributionOrigin: nil,
                                                             appStorePurchaseFlow: mockAppStorePurchaseFlow,
                                                             appStoreRestoreFlow: AppStoreRestoreFlowMock(),
                                                             appStoreAccountManagementFlow: AppStoreAccountManagementFlowMock())
    }
}
