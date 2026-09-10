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
}

enum PromoQueueCooldownDecision: Equatable {
    case eligible
    case blocked(until: Date)
}

@MainActor
protocol PromoQueueRemoteMessageHistory: AnyObject {
    var lastConfirmedAppearance: Date? { get }

    func recordConfirmedAppearance(at date: Date)
    func reset()
}

@MainActor
final class PromoQueueRemoteMessageHistoryStore: PromoQueueRemoteMessageHistory {

    enum StorageKey: String {
        case lastConfirmedAppearance = "com.duckduckgo.promo-queue.last-confirmed-remote-message-timestamp"
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

    var lastConfirmedAppearance: Date? {
        timestamp.map(Date.init(timeIntervalSince1970:))
    }

    func recordConfirmedAppearance(at date: Date) {
        setTimestamp(date.timeIntervalSince1970)
    }

    func reset() {
        locallyWrittenValue = .value(nil)
        lastSuccessfulRead = .value(nil)

        do {
            try keyValueStore.removeObject(forKey: StorageKey.lastConfirmedAppearance.rawValue)
        } catch {
            Logger.modalPrompt.error("[Promo Queue] - Failed to reset the last confirmed RMF timestamp.")
        }
    }

    private var timestamp: TimeInterval? {
        if case .value(let timestamp) = locallyWrittenValue {
            return timestamp
        }

        do {
            let timestamp = try keyValueStore.object(forKey: StorageKey.lastConfirmedAppearance.rawValue) as? TimeInterval
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

    private func setTimestamp(_ timestamp: TimeInterval) {
        locallyWrittenValue = .value(timestamp)
        lastSuccessfulRead = .value(timestamp)

        do {
            try keyValueStore.set(timestamp, forKey: StorageKey.lastConfirmedAppearance.rawValue)
        } catch {
            Logger.modalPrompt.error("[Promo Queue] - Failed to write the last confirmed RMF timestamp.")
        }
    }
}

@MainActor
protocol PromoQueueCooldownPolicying: AnyObject {
    var snapshot: PromoQueueCooldownSnapshot { get }

    func evaluateRemoteMessageAdmission() -> PromoQueueCooldownDecision
    func evaluateModalAdmission() -> PromoQueueCooldownDecision
    func recordConfirmedRemoteMessageAppearance()
    func resetModalCooldown()
    func resetRemoteMessageCooldown()
}

@MainActor
final class PromoQueueCooldownPolicy: PromoQueueCooldownPolicying {
    static let remoteMessageTargetInterval: TimeInterval = 10 * 60
    static let modalAfterRemoteMessageInterval: TimeInterval = 24 * 60 * 60

    private let modalPresentationStore: PromptCooldownStore
    private let remoteMessageHistory: PromoQueueRemoteMessageHistory
    private let dateProvider: () -> Date

    init(
        modalPresentationStore: PromptCooldownStore,
        remoteMessageHistory: PromoQueueRemoteMessageHistory,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.modalPresentationStore = modalPresentationStore
        self.remoteMessageHistory = remoteMessageHistory
        self.dateProvider = dateProvider
    }

    var snapshot: PromoQueueCooldownSnapshot {
        let lastModalAppearance = modalPresentationStore.lastPresentationTimestamp.map(Date.init(timeIntervalSince1970:))
        let lastRemoteMessageAppearance = remoteMessageHistory.lastConfirmedAppearance
        let remoteMessageBoundaries = [lastModalAppearance, lastRemoteMessageAppearance]
            .compactMap { $0?.addingTimeInterval(Self.remoteMessageTargetInterval) }

        return PromoQueueCooldownSnapshot(
            lastConfirmedModalAppearance: lastModalAppearance,
            lastConfirmedRemoteMessageAppearance: lastRemoteMessageAppearance,
            nextRemoteMessageEligibility: remoteMessageBoundaries.max(),
            nextModalEligibility: lastRemoteMessageAppearance?.addingTimeInterval(Self.modalAfterRemoteMessageInterval)
        )
    }

    func evaluateRemoteMessageAdmission() -> PromoQueueCooldownDecision {
        decision(nextEligibility: snapshot.nextRemoteMessageEligibility)
    }

    func evaluateModalAdmission() -> PromoQueueCooldownDecision {
        decision(nextEligibility: snapshot.nextModalEligibility)
    }

    func recordConfirmedRemoteMessageAppearance() {
        remoteMessageHistory.recordConfirmedAppearance(at: dateProvider())
    }

    func resetModalCooldown() {
        modalPresentationStore.lastPresentationTimestamp = nil
    }

    func resetRemoteMessageCooldown() {
        remoteMessageHistory.reset()
    }

    private func decision(nextEligibility: Date?) -> PromoQueueCooldownDecision {
        guard let nextEligibility, dateProvider() < nextEligibility else {
            return .eligible
        }
        return .blocked(until: nextEligibility)
    }
}
