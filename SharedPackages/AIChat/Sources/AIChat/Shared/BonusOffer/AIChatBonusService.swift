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

import Combine
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
    /// Emits the record after every write that changes it, so native can push it to every Duck.ai tab with `submitAIChatBonusRecord`.
    ///
    /// Delivers on the main queue, in the order the writes happened.
    var recordPublisher: AnyPublisher<AIChatBonusRecord, Never> { get }

    /// Returns the stored record, after ending the boost if it has expired.
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
///
/// Every read first ends a boost that has expired, so its Bonus ID doesn't stay on the device after expiry.
public final class AIChatBonusService: @unchecked Sendable {
    private let store: AIChatBonusStoring
    private let pixelFiring: AIChatBonusPixelFiring
    private let now: () -> Date
    private let makeBonusId: () -> String
    private let lock = NSLock()
    /// Set when a permanent delete failed, so the next access retries it.
    private var isDeletePending = false
    private let recordSubject = PassthroughSubject<AIChatBonusRecord, Never>()

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

    public var recordPublisher: AnyPublisher<AIChatBonusRecord, Never> {
        // Sent while the lock is held, so values go out in write order. Delivered asynchronously on main, so a
        // subscriber never runs inside the writer's lock and can call back into the service without deadlocking.
        recordSubject
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

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
            try write(claimedRecord)
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

// MARK: - AIChatBonusStateProviding

extension AIChatBonusService: AIChatBonusStateProviding {

    public func isBoostActive(at date: Date) throws -> Bool {
        try record()?.isBoostActive(at: date) ?? false
    }

}

// MARK: - App lifecycle

public extension AIChatBonusService {

    /// Deletes the record for good (e.g. App re-install).
    ///
    /// Publishes nothing. If the delete fails, every later read or write retries it first, and throws while it
    /// keeps failing, so the record is never returned again.
    ///
    /// - Throws: `AIChatBonusStoreError` when the record can't be deleted.
    func permanentlyDeleteRecord() throws {
        try withLock { try permanentlyDelete() }
    }

    /// Ends the boost if it has expired, clearing its Bonus ID.
    ///
    /// Duck.ai ends an expired boost itself, but only while it's open. Every read and write here already does it too.
    /// Called when neither may happen soon, e.g. when the app becomes active.
    /// With Duck.ai closed, the change reaches it the next time it loads and reads the record.
    ///
    /// - Throws: `AIChatBonusStoreError` when the record can't be read. A failed write while ending the boost
    ///   doesn't throw: the next read tries again.
    func endBoostIfExpired() throws {
        try withLock { _ = endExpiredBoostIfNeeded(for: try storedRecord()) }
    }

}

// MARK: - Locking

private extension AIChatBonusService {

    /// Locks and runs `body`.
    ///
    /// Reports and re-throws any store error, so every failure is reported in one place.
    ///
    /// - Parameters:
    ///   - caller: The public method calling it, for the log.
    ///   - block: The work to do while holding the lock.
    /// - Returns: What `block` returns.
    func withLock<Result>(caller: String = #function, _ block: () throws -> Result) throws -> Result {
        lock.lock()
        defer { lock.unlock() }

        do {
            return try block()
        } catch {
            reportStoreFailure(error, caller: caller)
            throw error
        }
    }

    /// Locks, reads the current record and hands it to block, which may change it through `write(_:)`.
    /// Holds the lock until `block` returns, so no other change can slip in between its read and its write.
    ///
    /// - Parameters:
    ///   - caller: The public method calling it, for the log.
    ///   - block: The block to apply to the current record, or `nil` when the device has none.
    /// - Returns: What `block` returns.
    func withLockedRecord<Result>(
        caller: String = #function,
        _ block: (AIChatBonusRecord?) throws -> Result
    ) throws -> Result {
        try withLock(caller: caller) {
            // Reads the record and ends the boost if it has expired
            let currentRecord = endExpiredBoostIfNeeded(for: try storedRecord())
            return try block(currentRecord)
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
                try write(updated)
                Logger.aiChat.debug("Duck.ai bonus: \(caller, privacy: .public) stored")
            }
        }
    }

}

// MARK: - Store access

private extension AIChatBonusService {

    /// The record as stored, after retrying a delete that failed earlier.
    ///
    /// Throws while that delete keeps failing, so a record that should be gone is never returned.
    func storedRecord() throws -> AIChatBonusRecord? {
        if isDeletePending {
            try store.delete()
            isDeletePending = false
            Logger.aiChat.debug("Duck.ai bonus: deleted the record on retry")
        }
        return try store.read()
    }

    /// Writes `record` and publishes it. Sent inside the lock, so pushes follow the order of the writes.
    func write(_ record: AIChatBonusRecord) throws {
        try store.write(record)
        recordSubject.send(record)
    }

    /// Ends the boost in `record` if it has expired, applying the same change as `aiChatBonusEnd`.
    ///
    /// - Parameter record: The stored record.
    /// - Returns: The ended record, or `record` unchanged when there's no expired boost or the write fails.
    func endExpiredBoostIfNeeded(for record: AIChatBonusRecord?) -> AIChatBonusRecord? {
        // If boost has not expired return the record
        guard
            let record,
            record.hasBoostExpired(at: now()),
            case .write(let ended) = AIChatBonusRecordRules.end(record)
        else {
            return record
        }

        do {
            try write(ended)
            Logger.aiChat.debug("Duck.ai bonus: ended an expired boost")
            return ended
        } catch {
            reportStoreFailure(error)
            // Duck.ai checks the expiry itself, so a failed cleanup mustn't fail the read. The next read tries again.
            return record
        }
    }

    /// Deletes the record.
    ///
    /// On failure, marks the delete as pending so `storedRecord()` retries it, then re-throws.
    func permanentlyDelete() throws {
        do {
            try store.delete()
            isDeletePending = false
            Logger.aiChat.debug("Duck.ai bonus: deleted the record")
        } catch {
            isDeletePending = true
            throw error
        }
    }

}

// MARK: - Helpers

private extension AIChatBonusService {

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
