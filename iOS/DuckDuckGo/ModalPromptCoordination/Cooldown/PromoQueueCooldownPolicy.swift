//
//  PromoQueueCooldownPolicy.swift
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

import Foundation
import Persistence

struct PromoQueueCooldownSnapshot: Equatable {
    let lastConfirmedModalAppearance: Date?
    let lastConfirmedRemoteMessageAppearance: Date?
    let nextRemoteMessageEligibility: Date?
    let nextModalEligibility: Date?

    static let empty = PromoQueueCooldownSnapshot(
        lastConfirmedModalAppearance: nil,
        lastConfirmedRemoteMessageAppearance: nil,
        nextRemoteMessageEligibility: nil,
        nextModalEligibility: nil
    )
}

enum PromoQueueCooldownDecision: Equatable {
    case eligible
    case blocked(until: Date)
}

@MainActor
protocol PromoQueueRemoteMessageCooldownStoring: AnyObject {
    var lastConfirmedRemoteMessageTimestamp: TimeInterval? { get set }
}

@MainActor
final class PromoQueueRemoteMessageCooldownKeyValueFilesStore: PromoQueueRemoteMessageCooldownStoring {

    enum StorageKey {
        static let lastConfirmedRemoteMessageTimestamp = "com.duckduckgo.promo-queue.last-confirmed-remote-message-timestamp"
    }

    private enum CachedTimestamp {
        case unavailable
        case value(TimeInterval?)
    }

    private let keyValueStore: ThrowingKeyValueStoring
    private var lastSuccessfulRead: CachedTimestamp = .unavailable
    private var locallyWrittenValue: CachedTimestamp = .unavailable

    init(keyValueStore: ThrowingKeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    var lastConfirmedRemoteMessageTimestamp: TimeInterval? {
        get {
            if case .value(let timestamp) = locallyWrittenValue {
                return timestamp
            }

            do {
                let timestamp = try keyValueStore.object(forKey: StorageKey.lastConfirmedRemoteMessageTimestamp) as? TimeInterval
                lastSuccessfulRead = .value(timestamp)
                return timestamp
            } catch {
                Logger.modalPrompt.error("[Promo Queue] - Failed to read the last confirmed RMF timestamp.")
                guard case .value(let timestamp) = lastSuccessfulRead else {
                    return nil
                }
                return timestamp
            }
        }
        set {
            // A confirmed appearance must remain authoritative for this process even if persistence is temporarily unavailable.
            locallyWrittenValue = .value(newValue)
            lastSuccessfulRead = .value(newValue)

            do {
                try keyValueStore.set(newValue, forKey: StorageKey.lastConfirmedRemoteMessageTimestamp)
            } catch {
                Logger.modalPrompt.error("[Promo Queue] - Failed to write the last confirmed RMF timestamp.")
            }
        }
    }

    /// Returns the timestamp that production admission would currently observe without changing its fallback cache.
    ///
    /// In particular, a successful persistence read made only for diagnostics must not become the fallback for a
    /// later production read failure. Locally confirmed appearances remain authoritative for the current process.
    fileprivate func lastConfirmedRemoteMessageTimestampForPromoQueueDiagnostics() -> TimeInterval? {
        if case .value(let timestamp) = locallyWrittenValue {
            return timestamp
        }

        do {
            return try keyValueStore.object(forKey: StorageKey.lastConfirmedRemoteMessageTimestamp) as? TimeInterval
        } catch {
            guard case .value(let timestamp) = lastSuccessfulRead else {
                return nil
            }
            return timestamp
        }
    }
}

@MainActor
protocol PromoQueueCooldownDebugSnapshotProviding: AnyObject {
    func snapshot(now: Date) -> PromoQueueCooldownSnapshot
}

/// Builds the debug cooldown projection through non-reporting, non-mutating reads.
/// Production admission deliberately continues to use `PromoQueueCooldownPolicy` and its failure semantics.
@MainActor
final class PromoQueueCooldownDebugSnapshotProvider: PromoQueueCooldownDebugSnapshotProviding {
    private let modalPresentationStore: PromptCooldownKeyValueFilesStore
    private let remoteMessagePresentationStore: PromoQueueRemoteMessageCooldownKeyValueFilesStore

    init(
        modalPresentationStore: PromptCooldownKeyValueFilesStore,
        remoteMessagePresentationStore: PromoQueueRemoteMessageCooldownKeyValueFilesStore
    ) {
        self.modalPresentationStore = modalPresentationStore
        self.remoteMessagePresentationStore = remoteMessagePresentationStore
    }

    func snapshot(now _: Date) -> PromoQueueCooldownSnapshot {
        PromoQueueCooldownSnapshot.make(
            lastModalTimestamp: modalPresentationStore.lastPresentationTimestampForPromoQueueDiagnostics(),
            lastRemoteMessageTimestamp: remoteMessagePresentationStore
                .lastConfirmedRemoteMessageTimestampForPromoQueueDiagnostics()
        )
    }
}

@MainActor
protocol PromoQueueCooldownPolicying: AnyObject {
    func evaluateRemoteMessageAdmission(now: Date) -> PromoQueueCooldownDecision
    func evaluateModalAdmission(now: Date) -> PromoQueueCooldownDecision
    func recordConfirmedRemoteMessageAppearance(at date: Date)
}

@MainActor
final class PromoQueueCooldownPolicy: PromoQueueCooldownPolicying {
    static let remoteMessageTargetInterval: TimeInterval = 10 * 60
    static let modalAfterRemoteMessageInterval: TimeInterval = 24 * 60 * 60

    private let modalPresentationStore: PromptCooldownStore
    private let remoteMessagePresentationStore: PromoQueueRemoteMessageCooldownStoring

    init(
        modalPresentationStore: PromptCooldownStore,
        remoteMessagePresentationStore: PromoQueueRemoteMessageCooldownStoring
    ) {
        self.modalPresentationStore = modalPresentationStore
        self.remoteMessagePresentationStore = remoteMessagePresentationStore
    }

    func evaluateRemoteMessageAdmission(now: Date) -> PromoQueueCooldownDecision {
        let lastAppearance = [
            modalPresentationStore.lastPresentationTimestamp,
            remoteMessagePresentationStore.lastConfirmedRemoteMessageTimestamp,
        ]
            .compactMap { $0 }
            .map(Date.init(timeIntervalSince1970:))
            .max()
        let nextEligibility = lastAppearance?.addingTimeInterval(Self.remoteMessageTargetInterval)
        return decision(now: now, nextEligibility: nextEligibility)
    }

    func evaluateModalAdmission(now: Date) -> PromoQueueCooldownDecision {
        let nextEligibility = remoteMessagePresentationStore.lastConfirmedRemoteMessageTimestamp
            .map { Date(timeIntervalSince1970: $0).addingTimeInterval(Self.modalAfterRemoteMessageInterval) }
        return decision(now: now, nextEligibility: nextEligibility)
    }

    func recordConfirmedRemoteMessageAppearance(at date: Date) {
        remoteMessagePresentationStore.lastConfirmedRemoteMessageTimestamp = date.timeIntervalSince1970
    }

    private func decision(now: Date, nextEligibility: Date?) -> PromoQueueCooldownDecision {
        guard let nextEligibility, now < nextEligibility else {
            return .eligible
        }
        return .blocked(until: nextEligibility)
    }
}

private extension PromoQueueCooldownSnapshot {
    @MainActor
    static func make(
        lastModalTimestamp: TimeInterval?,
        lastRemoteMessageTimestamp: TimeInterval?
    ) -> PromoQueueCooldownSnapshot {
        let lastModalAppearance = lastModalTimestamp.map(Date.init(timeIntervalSince1970:))
        let lastRemoteMessageAppearance = lastRemoteMessageTimestamp.map(Date.init(timeIntervalSince1970:))
        let remoteMessageBoundaries = [lastModalAppearance, lastRemoteMessageAppearance]
            .compactMap { $0?.addingTimeInterval(PromoQueueCooldownPolicy.remoteMessageTargetInterval) }

        return PromoQueueCooldownSnapshot(
            lastConfirmedModalAppearance: lastModalAppearance,
            lastConfirmedRemoteMessageAppearance: lastRemoteMessageAppearance,
            nextRemoteMessageEligibility: remoteMessageBoundaries.max(),
            nextModalEligibility: lastRemoteMessageAppearance?.addingTimeInterval(PromoQueueCooldownPolicy.modalAfterRemoteMessageInterval)
        )
    }
}
