//
//  SubscriptionsUserScriptHandling.swift
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

import UserScript

protocol SubscriptionsUserScriptHandling {
    func subscriptionDetails(params: Any, message: UserScriptMessage) async -> Encodable?
    func handshake(params: Any, message: UserScriptMessage) -> Encodable?
}

struct SubscriptionsUserScriptHandler: SubscriptionsUserScriptHandling {
    public struct AvailableMessageValues: Codable {
        let availableMessages: Bool
        let platform: String
    }

    public struct HandshakeValues: Codable {
        let availableMessages: [String]
        let platform: String
    }

    public func handshake(params: Any, message: UserScriptMessage) -> Encodable? {
        HandshakeValues(availableMessages: ["subscriptionDetails"],
                        platform: "macOS")
    }

    public struct SubscriptionDetailsValues: Codable {
        let isSubscribed: Bool
        let billingPeriod: String?
        let startedAt: Int?
        let expiresOrRenewsAt: Int?
        let paymentPlatform: String?
        let status: String?
    }

    public func subscriptionDetails(params: Any, message: UserScriptMessage) -> Encodable? {
        SubscriptionDetailsValues(isSubscribed: true,
                                  billingPeriod: "Monthly",
                                  startedAt: 0,
                                  expiresOrRenewsAt: 0,
                                  paymentPlatform: "ddg-internal",
                                  status: "Auto-Renewable")
//        SubscriptionDetailsValues(isSubscribed: false,
//                                  billingPeriod: nil,
//                                  startedAt: nil,
//                                  expiresOrRenewsAt: nil,
//                                  paymentPlatform: nil,
//                                  status: nil)
    }
}
