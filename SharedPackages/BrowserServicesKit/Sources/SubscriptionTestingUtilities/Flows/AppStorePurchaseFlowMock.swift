//
//  AppStorePurchaseFlowMock.swift
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

import Foundation
import Subscription

public final class AppStorePurchaseFlowMock: AppStorePurchaseFlow {
    public var purchaseSubscriptionResult: Result<PurchaseResult, AppStorePurchaseFlowError>?
    public var completeSubscriptionPurchaseResult: Result<PurchaseUpdate, AppStorePurchaseFlowError>?
    public var changeTierResult: Result<TransactionJWS, AppStorePurchaseFlowError>?

    public var purchaseSubscriptionCalled = false
    public var purchaseSubscriptionIncludeProTier: Bool?
    public var changeTierCalled = false
    public var changeTierSubscriptionIdentifier: String?
    public var completeSubscriptionAdditionalParams: [String: String]?

    public init() { }

    public func purchaseSubscription(with subscriptionIdentifier: String, includeProTier: Bool) async -> Result<PurchaseResult, AppStorePurchaseFlowError> {
        purchaseSubscriptionCalled = true
        purchaseSubscriptionIncludeProTier = includeProTier
        return purchaseSubscriptionResult!
    }

    @discardableResult
    public func completeSubscriptionPurchase(with transactionJWS: TransactionJWS, additionalParams: [String: String]?) async -> Result<PurchaseUpdate, AppStorePurchaseFlowError> {
        self.completeSubscriptionAdditionalParams = additionalParams
        return completeSubscriptionPurchaseResult!
    }

    public func changeTier(to subscriptionIdentifier: String) async -> Result<TransactionJWS, AppStorePurchaseFlowError> {
        changeTierCalled = true
        changeTierSubscriptionIdentifier = subscriptionIdentifier
        return changeTierResult!
    }
}
