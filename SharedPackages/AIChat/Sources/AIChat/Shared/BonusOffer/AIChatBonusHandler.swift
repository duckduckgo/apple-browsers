//
//  AIChatBonusHandler.swift
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

import Combine
import Common
import Foundation
import os.log

/// The bridge entry points for handling the messages Duck.ai sends for the bonus offer limit extension.
///
/// Requests return the payload to reply with, or `nil` when the params are invalid or the record can't be read or written.
/// Notifications return nothing: Duck.ai learns the new record from the push that follows a write.
public protocol AIChatBonusHandling {
    /// The payload to push to Duck.ai with `submitAIChatBonusRecord`, sent after every change to the record.
    var recordPayloadPublisher: AnyPublisher<AIChatBonusRecordPayload, Never> { get }

    /// Handles `getAIChatBonusRecord`, which Duck.ai sends when it loads.
    ///
    /// - Returns: The stored record with the install facts, or `nil` when the record can't be read.
    func getAIChatBonusRecord() -> AIChatBonusRecordPayload?

    /// Handles `getAIChatNewBonusRecord { campaignName }`, which Duck.ai sends when the user taps Claim.
    ///
    /// - Parameter params: The message params, as the bridge received them.
    /// - Returns: The record after the claim with the install facts, or `nil` when the params are invalid
    ///   or the record can't be read or written. A failed write never returns a Bonus ID.
    func getAIChatNewBonusRecord(params: Any) -> AIChatBonusRecordPayload?

    /// Handles `aiChatBonusRedeemOutcome`, which Duck.ai sends with the result of a `/redeem` call.
    ///
    /// - Parameter params: The message params, as the bridge received them. Dropped when invalid.
    func aiChatBonusRedeemOutcome(params: Any)

    /// Handles `aiChatBonusDismiss { campaignName }`, which Duck.ai sends when the activation modal is closed without claiming.
    ///
    /// - Parameter params: The message params, as the bridge received them. Dropped when invalid.
    func aiChatBonusDismiss(params: Any)

    /// Handles `aiChatBonusEnd`, which Duck.ai sends when the boost expired, was opted out of or was replaced by a subscription.
    func aiChatBonusEnd()
}

/// Decodes the bonus offer messages, hands them to the service and builds the replies.
public final class AIChatBonusHandler {
    private let service: AIChatBonusMessageHandling
    private let factsProvider: AIChatBonusFactsProviding

    /// Initializes a new instance with the specified parameters.
    /// - Parameters:
    ///   - service: The single owner of the bonus record. Pass the app's one shared instance, never a new one per tab:
    ///     its lock only serialises changes made through that instance.
    ///   - factsProvider: The install facts sent with every record.
    public init(service: AIChatBonusMessageHandling, factsProvider: AIChatBonusFactsProviding) {
        self.service = service
        self.factsProvider = factsProvider
    }
}

// MARK: - AIChatBonusHandling

extension AIChatBonusHandler: AIChatBonusHandling {

    public func getAIChatBonusRecord() -> AIChatBonusRecordPayload? {
        do {
            // `try?` would turn "no record" into a failed reply: the device has no record until the user claims, and Duck.ai still needs the facts.
            let record = try service.record()
            return payload(for: record)
        } catch {
            return nil
        }
    }

    public func getAIChatNewBonusRecord(params: Any) -> AIChatBonusRecordPayload? {
        guard let request: CampaignNameParams = decode(params) else { return nil }
        guard let record = try? service.claim(campaignName: request.campaignName) else { return nil }
        return payload(for: record)
    }

    public func aiChatBonusRedeemOutcome(params: Any) {
        guard let request: RedeemOutcomeParams = decode(params) else { return }
        // The service already logs and reports store errors; there's no reply to send.
        try? service.applyRedeemOutcome(request.outcome)
    }

    public func aiChatBonusDismiss(params: Any) {
        guard let request: CampaignNameParams = decode(params) else { return }
        // The service already logs and reports store errors; there's no reply to send.
        try? service.dismiss(campaignName: request.campaignName)
    }

    public func aiChatBonusEnd() {
        // The service already logs and reports store errors; there's no reply to send.
        try? service.end()
    }

    public var recordPayloadPublisher: AnyPublisher<AIChatBonusRecordPayload, Never> {
        service.recordPublisher
            .map(payload(for:))
            .eraseToAnyPublisher()
    }
}

// MARK: - Private

private extension AIChatBonusHandler {

    func payload(for record: AIChatBonusRecord?) -> AIChatBonusRecordPayload {
        AIChatBonusRecordPayload(
            record: record,
            isNewInstall: factsProvider.isNewInstall,
            aiChatEnabled: factsProvider.isAIChatEnabled
        )
    }

    /// Decodes `params`, logging which message was dropped when they don't match the contract.
    func decode<Params: Decodable>(_ params: Any, caller: String = #function) -> Params? {
        guard let decoded: Params = DecodableHelper.decode(from: params) else {
            Logger.aiChat.error("Duck.ai bonus: \(caller, privacy: .public) dropped, invalid params")
            return nil
        }
        return decoded
    }
}

// MARK: - Params

/// `getAIChatNewBonusRecord` and `aiChatBonusDismiss` params: `{ campaignName }`.
private struct CampaignNameParams: Decodable {
    let campaignName: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        campaignName = try container.decode(String.self, forKey: .campaignName)
        // No campaign has an empty name, and a claim with one would break the record invariant.
        guard !campaignName.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .campaignName, in: container, debugDescription: "Empty campaign name")
        }
    }

    private enum CodingKeys: String, CodingKey {
        case campaignName
    }
}

/// `aiChatBonusRedeemOutcome` params, one of:
/// - `{ bonusId, result: 'success', grant: { campaignName, multiplier, expiresAt } }`
/// - `{ bonusId, result: 'failure', reason, definitive }`
///
/// `reason` isn't decoded: `definitive` alone decides what happens to the record, and a reason FE adds later mustn't make native drop the outcome.
/// Pixels get the reason from the `aiChatBonusRedeemResult` metric Duck.ai sends through `reportMetric`.
private struct RedeemOutcomeParams: Decodable {
    let outcome: AIChatBonusRedeemOutcome

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let bonusId = try container.decode(String.self, forKey: .bonusId)

        switch try container.decode(RedeemResult.self, forKey: .result) {
        case .success:
            let grant = try container.decode(Grant.self, forKey: .grant)
            outcome = .success(bonusId: bonusId, terms: grant.terms)
        case .failure:
            let isDefinitive = try container.decode(Bool.self, forKey: .definitive)
            outcome = .failure(bonusId: bonusId, isDefinitive: isDefinitive)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case bonusId
        case result
        case grant
        case definitive
    }

    private enum RedeemResult: String, Decodable {
        case success
        case failure
    }

    /// The server's `/redeem` grant, which Duck.ai forwards unchanged: `{ campaignName, multiplier, expiresAt }`.
    /// Only `multiplier` and `expiresAt` (epoch milliseconds) are stored, as the record's terms.
    private struct Grant: Decodable {
        /// Decoded to mirror the payload, but not stored: the record keeps the campaign it was claimed with, and Duck.ai expects `terms` back with only `multiplier` and `expiresAt`. Kept here in case a future requirement needs it.
        let campaignName: String
        let terms: AIChatBonusRecord.Terms

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            campaignName = try container.decode(String.self, forKey: .campaignName)
            terms = try AIChatBonusRecord.Terms(from: decoder)
        }

        private enum CodingKeys: String, CodingKey {
            case campaignName
        }
    }
}
