//
//  StripePurchaseFlowV2Tests.swift
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
import Networking

final class StripePurchaseFlowV2Tests: XCTestCase {

    private struct Constants {
        static let accessToken = UUID().uuidString
        static let externalID = UUID().uuidString
        static let email = "dax@duck.com"
    }

    var subscriptionManager: SubscriptionManagerMockV2!
    var stripePurchaseFlow: StripePurchaseFlowV2!

    override func setUpWithError() throws {
        subscriptionManager = SubscriptionManagerMockV2()
        stripePurchaseFlow = DefaultStripePurchaseFlowV2(subscriptionManager: subscriptionManager)
    }

    override func tearDownWithError() throws {
        subscriptionManager = nil
        stripePurchaseFlow = nil
    }

    // MARK: - Tests for subscriptionOptions

    func testSubscriptionOptionsSuccess() async throws {
        // Given
        subscriptionManager.productsResponse = .success(SubscriptionMockFactory.productsItems)

        // When
        let result = await stripePurchaseFlow.subscriptionOptions()

        // Then
        switch result {
        case .success(let success):
            XCTAssertEqual(success.platform, SubscriptionPlatformName.stripe)
            XCTAssertEqual(success.options.count, SubscriptionMockFactory.productsItems.count)
            XCTAssertEqual(success.features.count, 4)
            let allFeatures = [Entitlement.ProductName.networkProtection,
                               Entitlement.ProductName.dataBrokerProtection,
                               Entitlement.ProductName.identityTheftRestoration,
                               Entitlement.ProductName.paidAIChat]
            let allNames = success.features.compactMap({ feature in feature.name })

            for feature in allFeatures {
                XCTAssertTrue(allNames.contains(feature.subscriptionEntitlement))
            }
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        }
    }

}
