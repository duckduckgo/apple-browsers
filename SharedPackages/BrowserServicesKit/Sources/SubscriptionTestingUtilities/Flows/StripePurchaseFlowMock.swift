//
//  StripePurchaseFlowMock.swift
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

public final class StripePurchaseFlowMock: StripePurchaseFlow {
    public var subscriptionOptionsResult: Result<SubscriptionOptions, StripePurchaseFlowError>
    public var subscriptionTierOptionsResult: Result<SubscriptionTierOptions, StripePurchaseFlowError>?
    public var prepareSubscriptionPurchaseResult: Result<PrepareResult, StripePurchaseFlowError>
    public var subscriptionTierOptionsIncludeProTierCalled: Bool?

    public init(subscriptionOptionsResult: Result<SubscriptionOptions, StripePurchaseFlowError>,
                prepareSubscriptionPurchaseResult: Result<PrepareResult, StripePurchaseFlowError>,
                subscriptionTierOptionsResult: Result<SubscriptionTierOptions, StripePurchaseFlowError>? = nil) {
        self.subscriptionOptionsResult = subscriptionOptionsResult
        self.prepareSubscriptionPurchaseResult = prepareSubscriptionPurchaseResult
        self.subscriptionTierOptionsResult = subscriptionTierOptionsResult
    }

    public func subscriptionOptions() async -> Result<SubscriptionOptions, StripePurchaseFlowError> {
        subscriptionOptionsResult
    }

    public func subscriptionTierOptions(includeProTier: Bool) async -> Result<SubscriptionTierOptions, StripePurchaseFlowError> {
        subscriptionTierOptionsIncludeProTierCalled = includeProTier
        return subscriptionTierOptionsResult ?? .failure(.noProductsFound)
    }

    public func prepareSubscriptionPurchase(emailAccessToken: String?) async -> Result<PrepareResult, StripePurchaseFlowError> {
        prepareSubscriptionPurchaseResult
    }

    public func completeSubscriptionPurchase() async {

    }
}
