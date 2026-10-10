//
//  AIChatBonusService.swift
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
import os.log

/// The bonus record operations Duck.ai can trigger through the bridge: one per message in the contract.
///
/// Duck.ai can end a boost but never delete the record, so there's no delete here. Every method throws
/// when the record can't be read or written. A caller that gets an error must not send Duck.ai a
/// record, not even `record: null`: the bridge replies with its standard error instead.
///
/// Only the two requests return the record, for the bridge's reply. The notifications expect no reply:
/// Duck.ai learns the new record from the push native sends to every Duck.ai tab after a write.
public protocol AIChatBonusMessageHandling {

    /// Returns the stored record.
    ///
    /// Handles `getAIChatBonusRecord`, which Duck.ai sends when it loads, to find out where the offer stands.
    ///
    /// - Returns: The stored record, or `nil` when the device has none.
    /// - Throws: `AIChatBonusStoreError` when the record can't be read.
    func record() throws -> AIChatBonusRecord?

    /// Claims the offer: mints a Bonus ID and stores it with the campaign.
    ///
    /// Handles `getAIChatNewBonusRecord`, which Duck.ai sends when the user taps Claim, before it calls
    /// `/redeem` with the Bonus ID. Mints nothing while a campaign is stored, whether the boost is
    /// pending, active or ended, and returns the stored record instead.
    ///
    /// - Parameter campaignName: The campaign being claimed, from Duck.ai.
    /// - Returns: The record after the claim: the new one, or the stored one when a campaign was already there.
    /// - Throws: `AIChatBonusStoreError` when the record can't be read or written.
    func claim(campaignName: String) throws -> AIChatBonusRecord

    /// Applies the result of a `/redeem` call to the Bonus ID it was for.
    ///
    /// Handles `aiChatBonusRedeemOutcome`. Ignored unless `outcome` is for the stored Bonus ID, so a late
    /// result can't bring back a boost that has already ended.
    ///
    /// - Parameter outcome: The result Duck.ai reported.
    /// - Throws: `AIChatBonusStoreError` when the record can't be read or written.
    func applyRedeemOutcome(_ outcome: AIChatBonusRedeemOutcome) throws

    /// Marks the offer as dismissed.
    ///
    /// Handles `aiChatBonusDismiss`, which Duck.ai sends when the activation modal is closed without
    /// claiming. Gates only Duck.ai's mini promo.
    ///
    /// - Throws: `AIChatBonusStoreError` when the record can't be read or written.
    func dismiss() throws

    /// Ends the boost, keeping only the campaign so this install can't claim it again.
    ///
    /// Handles `aiChatBonusEnd`, which Duck.ai sends when the boost expired, was opted out of or was
    /// replaced by a subscription. Ignored when no Bonus ID is stored.
    ///
    /// - Throws: `AIChatBonusStoreError` when the record can't be read or written.
    func end() throws
}

/// The single owner of the bonus record. Every change goes through here, never straight to the store.
///
/// Each change is atomic: read, mutation from `AIChatBonusRecordRules` followed by a write.
public final class AIChatBonusService: @unchecked Sendable {
    private let store: AIChatBonusStoring
    private let pixelFiring: AIChatBonusPixelFiring
    private let now: () -> Date
    private let makeBonusId: () -> String
    private let lock = NSLock()

    /// Create a new instance of the `AIChatBonusService` with the specified parameters.
    /// - Parameters:
    ///   - store: The underlying store for the record.
    ///   - pixelFiring: Reports store failures. Each app passes its own; the default reports nothing.
    ///   - now: A date provider, injectable for tests.
    ///   - makeBonusId: A function that Mints a Bonus ID when needed.
    public init(
        store: AIChatBonusStoring = AIChatBonusStore(),
        pixelFiring: AIChatBonusPixelFiring = NullAIChatBonusPixelFiring(),
        now: @escaping () -> Date = Date.init,
        makeBonusId: @escaping () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.store = store
        self.now = now
        self.makeBonusId = makeBonusId
        self.pixelFiring = pixelFiring
    }

}

// MARK: - AIChatBonusMessageHandling

extension AIChatBonusService: AIChatBonusMessageHandling {

    public func record() throws -> AIChatBonusRecord? {
        try withLockedRecord { $0 }
    }

    public func claim(campaignName: String) throws -> AIChatBonusRecord {
        try withLockedRecord { current in
            let claimedRecord = AIChatBonusRecordRules.claim(current, campaignName: campaignName, bonusId: makeBonusId())
            guard claimedRecord != current else {
                Logger.aiChat.debug("Duck.ai bonus: claim kept the stored record")
                return claimedRecord
            }
            try store.write(claimedRecord)
            Logger.aiChat.debug("Duck.ai bonus: claim stored")
            return claimedRecord
        }
    }

    public func applyRedeemOutcome(_ outcome: AIChatBonusRedeemOutcome) throws {
        try apply { AIChatBonusRecordRules.applyRedeemOutcome(outcome, to: $0, nowMilliseconds: nowMilliseconds()) }
    }

    public func dismiss() throws {
        try apply(AIChatBonusRecordRules.dismiss)
    }

    public func end() throws {
        try apply(AIChatBonusRecordRules.end)
    }

}

// MARK: - Private

private extension AIChatBonusService {

    /// Locks, reads the record and hands it to `mutation`, which may write through the store. Holds the lock
    /// until `mutation` returns, so no other change can slip in between its read and its write.
    ///
    /// Reports and re-throws any store error, so every read and write is reported in one place.
    ///
    /// - Parameters:
    ///   - caller: The public method calling it, for the log. Filled in by the compiler.
    ///   - mutation: The mutation to apply to the stored record, or `nil` when the device has none.
    /// - Returns: What `block` returns.
    func withLockedRecord<Result>(
        caller: String = #function,
        _ mutation: (AIChatBonusRecord?) throws -> Result
    ) throws -> Result {
        lock.lock()
        defer { lock.unlock() }

        do {
            return try mutation(try store.read())
        } catch {
            reportStoreFailure(error, caller: caller)
            throw error
        }
    }

    /// Reads the record, applies `rule` and writes the result if it differs from what's stored.
    ///
    /// - Parameters:
    ///   - caller: The public method applying the rule, for the log.
    ///   - rule: Decides what to do with the stored record.
    func apply(
        caller: String = #function,
        _ rule: (AIChatBonusRecord?) -> AIChatBonusRecordUpdate
    ) throws {
        try withLockedRecord(caller: caller) { current in
            switch rule(current) {
            case .ignore(let reason):
                Logger.aiChat.debug("Duck.ai bonus: \(caller, privacy: .public) ignored, reason=\(reason.rawValue, privacy: .public)")
            case .write(let updated):
                guard updated != current else { return }
                try store.write(updated)
                Logger.aiChat.debug("Duck.ai bonus: \(caller, privacy: .public) stored")
            }
        }
    }

    /// Logs a store failure and fires the debug pixel, then leaves it to the caller to decide what to do.
    ///
    /// - Parameters:
    ///   - error: The error the store threw.
    ///   - caller: The method that hit it, for the log.
    func reportStoreFailure(_ error: Error, caller: String = #function) {
        Logger.aiChat.error("Duck.ai bonus: \(caller, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        pixelFiring.fire(.storeFailed(error))
    }

    /// Epoch milliseconds, the unit Duck.ai uses for every timestamp in the record.
    func nowMilliseconds() -> Double {
        now().timeIntervalSince1970 * 1000
    }
}
