//
//  SubscriptionUserScriptHandler.swift
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

import Subscription
import UserScript

struct SubscriptionUserScriptHandler: SubscriptionUserScriptHandling {

    func handshake(params: Any, message: any UserScriptMessage) async -> HandshakeResponse {
        .init(availableMessages: [.subscriptionDetails], platform: .macos)
    }

    func subscriptionDetails(params: Any, message: any UserScriptMessage) async -> SubscriptionDetails {
        SubscriptionDetails(isSubscribed: true,
                            billingPeriod: "Monthly",
                            startedAt: 0,
                            expiresOrRenewsAt: 0,
                            paymentPlatform: "ddg-internal",
                            status: "Auto-Renewable")
    }
}
