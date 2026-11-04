//
//  MockAIChatBonusRecord.swift
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
@testable import AIChat

enum AIChatBonusRecordMock {
    static let campaignName = "launch"
    static let bonusId = "8a7b9c1d-2e3f-4a5b-8c6d-7e8f9a0b1c2d"
    static let otherBonusId = "1f2e3d4c-5b6a-4987-8a6b-5c4d3e2f1a0b"
    static let terms = AIChatBonusRecord.Terms(multiplier: 2, expiresAt: 1_790_000_000)

    /// Never claimed, but the activation modal was closed.
    static let dismissedOnly = AIChatBonusRecord(dismissed: true)
    /// Claimed, waiting for the redeem outcome.
    static let pending = AIChatBonusRecord(campaignName: campaignName, bonusId: bonusId)
    /// Redeemed: the boost is on until `terms.expiresAt`.
    static let active = AIChatBonusRecord(campaignName: campaignName, bonusId: bonusId, terms: terms, lastRedeemAttemptAt: 1_780_000_000_000)
    /// Expired, opted out of or replaced by a subscription. Only the campaign is left.
    static let ended = AIChatBonusRecord(campaignName: campaignName)
}

extension AIChatBonusRecord {

    /// A copy with `change` applied, so a test's expectation names only what changed.
    func with(_ change: (inout AIChatBonusRecord) -> Void) -> AIChatBonusRecord {
        var copy = self
        change(&copy)
        return copy
    }
}
