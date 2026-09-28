//
//  AIChatUserTier+Subscription.swift
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
import Subscription

extension AIChatUserTier {

    /// The customer's Duck.ai tier, resolved from their subscription. Anything other than an active tiered
    /// subscription — including a failed lookup — resolves to `.free`.
    static func resolve(from subscriptionManager: any SubscriptionManager) async -> AIChatUserTier {
        do {
            guard let subscription = try await subscriptionManager.getSubscription(),
                  subscription.isActive,
                  let tier = subscription.tier else {
                return .free
            }
            switch tier {
            case .plus: return .plus
            case .pro: return .pro
            }
        } catch {
            return .free
        }
    }
}
