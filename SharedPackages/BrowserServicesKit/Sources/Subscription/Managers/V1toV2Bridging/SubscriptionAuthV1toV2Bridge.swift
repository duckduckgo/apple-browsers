//
//  SubscriptionAuthV1toV2Bridge.swift
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

import Foundation
import Combine
import Common
import Networking
import os.log

/// Temporary bridge between auth v1 and v2, this is implemented by SubscriptionManager V1 and V2
public protocol SubscriptionAuthV1toV2Bridge: SubscriptionTokenProvider, SubscriptionAuthenticationStateProvider {

//    var hasAppStoreProductsAvailable: Bool { get }
    /// Publisher that emits a boolean value indicating whether the user can purchase through the App Store.
//    var hasAppStoreProductsAvailablePublisher: AnyPublisher<Bool, Never> { get }
//    @discardableResult func getSubscription(cachePolicy: SubscriptionCachePolicy) async throws -> DuckDuckGoSubscription
//    func isSubscriptionPresent() -> Bool
//    func url(for type: SubscriptionURL) -> URL
//    var email: String? { get }
//    var currentEnvironment: SubscriptionEnvironment { get }
//    func urlForPurchaseFromRedirect(redirectURLComponents: URLComponents, tld: TLD) -> URL

    

    var currentStorefrontRegion: SubscriptionRegion? { get }
}


extension DefaultSubscriptionManagerV2: SubscriptionAuthV1toV2Bridge {

    

//    public var email: String? { userEmail }

    

    
}
