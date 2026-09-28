//
//  AIChatModelPublicAccessTier.swift
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

import Foundation

/// The lowest publicly-marketed subscription tier a model or reasoning effort requires. Distinct
/// from `AIChatUserTier`, which also includes the non-public `.internal` case. `String`-backed so
/// the raw values ("free"/"plus"/"pro") can be used directly as pixel parameters.
public enum AIChatModelPublicAccessTier: String, Hashable, Sendable {
    case free
    case plus
    case pro
}

public extension AIChatModel {
    var lowestPublicAccessTier: AIChatModelPublicAccessTier? {
        lowestPublicAccessTier(from: accessTier)
    }

    func lowestPublicAccessTier(for effort: AIChatReasoningEffort) -> AIChatModelPublicAccessTier? {
        guard let accessTier = accessTier(for: effort) else { return nil }
        return lowestPublicAccessTier(from: accessTier)
    }

    private func lowestPublicAccessTier(from accessTier: [String]) -> AIChatModelPublicAccessTier? {
        if accessTier.contains(AIChatUserTier.free.rawValue) {
            return .free
        }
        if accessTier.contains(AIChatUserTier.plus.rawValue) {
            return .plus
        }
        if accessTier.contains(AIChatUserTier.pro.rawValue) {
            return .pro
        }
        return nil
    }
}

/// The subscription upsell flow that a gated Duck.ai selection should route to.
public enum DuckAISubscriptionUpsellingFlow: Sendable {
    case purchase
    case upgrade
    case none
}

public extension AIChatUserTier {
    func upgradeFlow(for requiredTier: AIChatModelPublicAccessTier) -> DuckAISubscriptionUpsellingFlow {
        switch (self, requiredTier) {
        case (.plus, .pro):
            return .upgrade
        case (.free, .plus), (.free, .pro):
            return .purchase
        default:
            return .none
        }
    }
}
