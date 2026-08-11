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
}

@MainActor
protocol PromoQueueCooldownPolicying: AnyObject {
    func evaluateRemoteMessageAdmission(now: Date) -> PromoQueueCooldownDecision
    func evaluateModalAdmission(now: Date) -> PromoQueueCooldownDecision
    func recordConfirmedRemoteMessageAppearance(at date: Date)
    func snapshot(now: Date) -> PromoQueueCooldownSnapshot
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
        let nextEligibility = snapshot(now: now).nextRemoteMessageEligibility
        return decision(now: now, nextEligibility: nextEligibility)
    }

    func evaluateModalAdmission(now: Date) -> PromoQueueCooldownDecision {
        let nextEligibility = snapshot(now: now).nextModalEligibility
        return decision(now: now, nextEligibility: nextEligibility)
    }

    func recordConfirmedRemoteMessageAppearance(at date: Date) {
        remoteMessagePresentationStore.lastConfirmedRemoteMessageTimestamp = date.timeIntervalSince1970
    }

    func snapshot(now _: Date) -> PromoQueueCooldownSnapshot {
        let lastModalAppearance = modalPresentationStore.lastPresentationTimestamp.map(Date.init(timeIntervalSince1970:))
        let lastRemoteMessageAppearance = remoteMessagePresentationStore.lastConfirmedRemoteMessageTimestamp.map(Date.init(timeIntervalSince1970:))

        let remoteMessageBoundaries = [lastModalAppearance, lastRemoteMessageAppearance]
            .compactMap { $0?.addingTimeInterval(Self.remoteMessageTargetInterval) }

        return PromoQueueCooldownSnapshot(
            lastConfirmedModalAppearance: lastModalAppearance,
            lastConfirmedRemoteMessageAppearance: lastRemoteMessageAppearance,
            nextRemoteMessageEligibility: remoteMessageBoundaries.max(),
            nextModalEligibility: lastRemoteMessageAppearance?.addingTimeInterval(Self.modalAfterRemoteMessageInterval)
        )
    }

    private func decision(now: Date, nextEligibility: Date?) -> PromoQueueCooldownDecision {
        guard let nextEligibility, now < nextEligibility else {
            return .eligible
        }
        return .blocked(until: nextEligibility)
    }
}
