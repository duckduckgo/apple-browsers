//
//  AIChatBonusRecord.swift
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

/// Represents the device's single record for the Duck.ai limit extension promo.
///
/// Native only stores it and hands it to Duck.ai, which derives the promo state from it.
public struct AIChatBonusRecord: Codable, Equatable, Sendable {
    /// The campaign name.
    ///
    /// Set on claim and kept after the boost ends, so this install can't claim the same campaign again.
    public var campaignName: String?

    /// The unique identifier for the bonus offer.
    public var bonusId: String?

    /// `true` if the offer activation modal was dismissed without claiming. Gates only the Duck.ai mini promo.
    public var dismissed: Bool

    /// The terms of the offer. Written on redeem success.
    public var terms: Terms?

    /// Epoch milliseconds of the last redeem outcome received for `bonusId`.
    public var lastRedeemAttemptAt: Double?

    public init(
        campaignName: String? = nil,
        bonusId: String? = nil,
        dismissed: Bool = false,
        terms: Terms? = nil,
        lastRedeemAttemptAt: Double? = nil
    ) {
        self.campaignName = campaignName
        self.bonusId = bonusId
        self.dismissed = dismissed
        self.terms = terms
        self.lastRedeemAttemptAt = lastRedeemAttemptAt
    }

    /// Returns `true` if the record is one Duck.ai would reject. The store never writes such a record, and reports a stored one as unavailable.
    ///
    /// Two rules, both mirroring Duck.ai's own validation:
    /// - `terms ⇒ bonusId ⇒ campaignName`: terms need a Bonus ID, and a Bonus ID needs a campaign.
    /// - `campaignName` and `bonusId` are either absent or non-empty. Duck.ai rejects a payload with an empty one, and nothing would ever clear such a record, so the offer would stay hidden for good.
    ///
    /// Every combination of the three optional fields, and the state Duck.ai derives from each. `dismissed` can be set on any of them.
    ///
    /// | campaignName | bonusId | terms | State |
    /// |---|---|---|---|
    /// | ✗ | ✗ | ✗ | never claimed |
    /// | ✓ | ✗ | ✗ | ended |
    /// | ✓ | ✓ | ✗ | pending |
    /// | ✓ | ✓ | ✓ | active, or ended once `expiresAt` passes |
    /// | ✗ | ✓ | any | invalid: Bonus ID without a campaign |
    /// | any | ✗ | ✓ | invalid: terms without a Bonus ID |
    /// | `""` | any | any | invalid: empty campaign name |
    /// | any | `""` | any | invalid: empty Bonus ID |
    ///
    /// - never claimed: Duck.ai works out eligible or ineligible on its own.
    /// - ended: expired, opted out, subscribed, or a definitive redeem failure after terms were stored.
    ///   `campaignName` is kept so this install can't claim again.
    /// - pending: claimed, waiting for the server to confirm the redeem.
    var breaksInvariant: Bool {
        // Present but empty.
        let hasEmptyIdentifier = campaignName == "" || bonusId == ""
        let hasBonusIdWithoutCampaign = bonusId != nil && campaignName == nil
        let hasTermsWithoutBonusId = bonusId == nil && terms != nil

        return hasEmptyIdentifier || hasBonusIdWithoutCampaign || hasTermsWithoutBonusId
    }
}

public extension AIChatBonusRecord {

    /// Represents The boost terms confirmed by the server on a successful redeem.
    struct Terms: Codable, Equatable, Sendable {
        /// Factor applied to the Duck.ai chat limits while the boost is active, e.g. `2` for double.
        public let multiplier: Double

        /// Epoch milliseconds, as Duck.ai sends and expects it. Kept ms so it is lossless.
        let expiresAtMilliseconds: Double

        /// Seconds since 1970.
        public var expiresAt: TimeInterval {
            expiresAtMilliseconds / 1000
        }

        /// - Parameter expiresAt: Seconds since 1970.
        public init(multiplier: Double, expiresAt: TimeInterval) {
            self.multiplier = multiplier
            self.expiresAtMilliseconds = expiresAt * 1000
        }

        private enum CodingKeys: String, CodingKey {
            case multiplier
            case expiresAtMilliseconds = "expiresAt"
        }
    }

}

/// Represents the Bonus payload for every request and every push sends to Duck.ai
public struct AIChatBonusRecordPayload: Encodable, Equatable, Sendable {
    /// `nil` when the device has no record yet.
    public let record: AIChatBonusRecord?

    /// First install, within the install window.
    public let isNewInstall: Bool

    /// `true` if Duck.ai is enabled; false otherwise.
    public let aiChatEnabled: Bool

    public init(record: AIChatBonusRecord?, isNewInstall: Bool, aiChatEnabled: Bool) {
        self.record = record
        self.isNewInstall = isNewInstall
        self.aiChatEnabled = aiChatEnabled
    }

    // MARK: - Encodable

    private enum CodingKeys: String, CodingKey {
        case record
        case isNewInstall
        case aiChatEnabled
    }

    // Synthesized encoding omits a nil `record`; Duck.ai expects an explicit `null`.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(record, forKey: .record)
        try container.encode(isNewInstall, forKey: .isNewInstall)
        try container.encode(aiChatEnabled, forKey: .aiChatEnabled)
    }
}
