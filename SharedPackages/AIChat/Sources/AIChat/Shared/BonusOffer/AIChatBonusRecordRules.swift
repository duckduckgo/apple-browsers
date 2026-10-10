//
//  AIChatBonusRecordRules.swift
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

/// The result of a `/redeem` call, as Duck.ai reports it through `aiChatBonusRedeemOutcome`.
public enum AIChatBonusRedeemOutcome: Equatable, Sendable {
    /// The server granted the boost on these terms.
    case success(bonusId: String, terms: AIChatBonusRecord.Terms)

    /// The server refused the redeem.
    /// A definitive failure means the Bonus ID will never be granted, e.g. the campaign ended; a non-definitive one may succeed on a later attempt.
    case failure(bonusId: String, isDefinitive: Bool)

    var bonusId: String {
        switch self {
        case .success(let bonusId, _), .failure(let bonusId, _):
            return bonusId
        }
    }
}

/// What a rule decided to do with the stored record.
enum AIChatBonusRecordUpdate: Equatable {
    /// Store this record in place of the current one.
    case write(AIChatBonusRecord)
    /// Leave the stored record as it is: the contract says to ignore this message.
    case ignore(IgnoreReason)

    /// Why a message was ignored
    enum IgnoreReason: String, Equatable {
        /// A redeem outcome or an end with no Bonus ID stored.
        case noBonusId
        /// A redeem outcome for a Bonus ID other than the stored one.
        case bonusIdMismatch
    }
}

/// How each Duck.ai message changes the record.
///
/// Native never derives the promo state. These rules only keep the record consistent and make sure
/// a late or repeated message can't bring back a Bonus ID that has already been cleared.
enum AIChatBonusRecordRules {

    /// Claims the offer: mints a Bonus ID and pairs it with the campaign in a new record.
    ///
    /// Handles `getAIChatNewBonusRecord`, which Duck.ai sends when the user taps Claim, before it calls
    /// `/redeem` with the Bonus ID. The record is stored first so a crash during `/redeem` leaves an ID
    /// Duck.ai can submit again. Until the outcome arrives the boost is pending: no terms yet.
    ///
    /// Keeps the stored record while a campaign is stored, whether the boost is pending, active or ended:
    /// the claim was already made, and an ended campaign can't be claimed again on this install.
    ///
    /// The new record carries over `dismissed`, so a user who dismissed the offer earlier still
    /// doesn't see the mini promo.
    ///
    /// - Parameters:
    ///   - record: The stored record, or `nil` when the device has none (first claim).
    ///   - campaignName: The campaign being claimed, from Duck.ai.
    ///   - bonusId: The freshly minted Bonus ID.
    /// - Returns: The record to return to Duck.ai: the stored one when a campaign is already there, otherwise a new one.
    static func claim(
        _ record: AIChatBonusRecord?,
        campaignName: String,
        bonusId: String
    ) -> AIChatBonusRecord {
        // Do not mint a bonus id again if already minted
        if let record, record.campaignName != nil { return record }

        // We don't set `lastRedeemAttemptAt`is only set on redeem.
        return AIChatBonusRecord(
            campaignName: campaignName,
            bonusId: bonusId,
            dismissed: record?.dismissed ?? false
        )
    }

    /// Applies the result of a `/redeem` call to the Bonus ID it was for.
    ///
    /// Handles `aiChatBonusRedeemOutcome`. An outcome for any other Bonus ID is dropped, so a late
    /// result can't bring back a boost that was ended, opted out of or replaced by a subscription in
    /// the meantime. Otherwise:
    /// - Success: stores the terms, replacing any already stored.
    /// - Definitive failure with terms stored: the boost has ended, so clears the Bonus ID and terms
    ///   and keeps the campaign.
    /// - Definitive failure without terms: the claim never went through, so clears the Bonus ID and
    ///   the campaign, and the offer can be claimed again.
    /// - Non-definitive failure: changes nothing else.
    ///
    /// Every applied outcome sets `lastRedeemAttemptAt`, which spaces out Duck.ai's silent retries.
    ///
    /// - Parameters:
    ///   - outcome: The result Duck.ai reported.
    ///   - record: The stored record, or `nil` when the device has none.
    ///   - nowMilliseconds: The current time in epoch milliseconds, stored as `lastRedeemAttemptAt`.
    /// - Returns: The updated record to write, `.ignore(.noBonusId)` when none is stored, or
    ///   `.ignore(.bonusIdMismatch)` when the outcome is for another Bonus ID.
    static func applyRedeemOutcome(
        _ outcome: AIChatBonusRedeemOutcome,
        to record: AIChatBonusRecord?,
        nowMilliseconds: Double
    ) -> AIChatBonusRecordUpdate {
        guard var record, let storedBonusId = record.bonusId else { return .ignore(.noBonusId) }
        guard storedBonusId == outcome.bonusId else { return .ignore(.bonusIdMismatch) }

        switch outcome {
        case .success(_, let terms):
            // Overwrites terms already stored, e.g. a replay that returned the server's current grant.
            record.terms = terms
        case .failure(_, isDefinitive: true):
            if record.terms != nil {
                // The boost was active: it has ended. Keep the campaign so it can't be claimed again.
                record.bonusId = nil
                record.terms = nil
            } else {
                // The claim never went through: back to unclaimed, so the offer can be claimed again (E.g. campaign not available anymore or not found).
                record.bonusId = nil
                record.campaignName = nil
            }
        case .failure(_, isDefinitive: false):
            // Nothing changes but the attempt time, which spaces out Duck.ai's silent retries.
            break
        }
        record.lastRedeemAttemptAt = nowMilliseconds
        return .write(record)
    }

    /// Marks the offer as dismissed.
    ///
    /// Handles `aiChatBonusDismiss`, sent when the activation modal is closed without claiming.
    ///
    /// - Parameter record: The stored record, or `nil` when the device has none.
    /// - Returns: The record to write.
    static func dismiss(_ record: AIChatBonusRecord?) -> AIChatBonusRecordUpdate {
        var record = record ?? AIChatBonusRecord()
        record.dismissed = true
        return .write(record)
    }

    /// Ends the boost, keeping only the campaign.
    ///
    /// Handles `aiChatBonusEnd`, sent when the boost expired, was opted out of or was replaced by a
    /// subscription. Clears the Bonus ID, terms, `lastRedeemAttemptAt` and `dismissed`.
    /// Keeping the campaign means this install can't claim the same offer again.
    ///
    /// - Parameter record: The stored record, or `nil` when the device has none.
    /// - Returns: The record to write, or `.ignore(.noBonusId)` when there's no Bonus ID to clear, so a
    ///   repeated end changes nothing.
    static func end(_ record: AIChatBonusRecord?) -> AIChatBonusRecordUpdate {
        guard let record, record.bonusId != nil else { return .ignore(.noBonusId) }

        return .write(AIChatBonusRecord(campaignName: record.campaignName))
    }
}
