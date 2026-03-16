//
//  TrackerBlockingReason.swift
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

import ContentBlocking

/// Typed representation of reason strings sent by content-scope-scripts tracker-protection.
/// Raw values must match the JS constants in tracker-resolver.js and tracker-protection.js.
public enum TrackerBlockingReason: String {

    // Resolver-level reasons (from tracker-resolver.js)
    case firstParty = "first party"
    case ruleException = "matched rule - exception"
    case defaultIgnore = "default ignore"
    case matchedRuleIgnore = "matched rule - ignore"
    case defaultBlock = "default block"
    case surrogate = "matched rule - surrogate"
    case matchedRuleBlock = "matched rule - block"
    case noMatch = "no match"

    // Feature-level reasons (from tracker-protection.js)
    case unprotectedDomain = "unprotectedDomain"
    case thirdPartyRequest = "thirdPartyRequest"
    case affiliatedThirdPartyRequest = "thirdPartyRequestOwnedByFirstParty"

    /// Map to the native AllowReason used by DetectedRequest / privacy dashboard.
    public var allowReason: AllowReason {
        switch self {
        case .firstParty, .affiliatedThirdPartyRequest:
            return .ownedByFirstParty
        case .ruleException, .defaultIgnore, .matchedRuleIgnore:
            return .ruleException
        case .unprotectedDomain:
            return .protectionDisabled
        default:
            return .otherThirdPartyRequest
        }
    }

    /// True for non-tracker third-party requests that should be routed to the
    /// thirdPartyRequest path, avoiding tracker-only side effects
    /// (ad-click attribution, blocked-tracker stats, FB callback).
    public var isNonTrackerThirdPartyRequest: Bool {
        self == .thirdPartyRequest || self == .affiliatedThirdPartyRequest
    }
}
