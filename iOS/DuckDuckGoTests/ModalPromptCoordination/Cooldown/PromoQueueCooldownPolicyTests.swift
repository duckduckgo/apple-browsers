//
//  PromoQueueCooldownPolicyTests.swift
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
import PersistenceTestingUtils
import Testing
@testable import DuckDuckGo

enum DirectionalCooldown: Sendable {
    case modalToRemoteMessage
    case remoteMessageToRemoteMessage
    case remoteMessageToModal
}

struct DirectionalCooldownScenario: Sendable {
    let direction: DirectionalCooldown
    let elapsed: TimeInterval
    let isEligible: Bool
}

@MainActor
@Suite("Promo Queue - Directional Cooldown Policy")
final class PromoQueueCooldownPolicyTests {
    private let referenceDate = Date(timeIntervalSince1970: 1_775_000_000)

    @available(iOS 16, *)
    @Test(
        "Directional cooldowns use inclusive approved boundaries",
        .timeLimit(.minutes(1)),
        arguments: [
            DirectionalCooldownScenario(direction: .modalToRemoteMessage, elapsed: 599, isEligible: false),
            DirectionalCooldownScenario(direction: .modalToRemoteMessage, elapsed: 600, isEligible: true),
            DirectionalCooldownScenario(direction: .modalToRemoteMessage, elapsed: 601, isEligible: true),
            DirectionalCooldownScenario(direction: .remoteMessageToRemoteMessage, elapsed: 599, isEligible: false),
            DirectionalCooldownScenario(direction: .remoteMessageToRemoteMessage, elapsed: 600, isEligible: true),
            DirectionalCooldownScenario(direction: .remoteMessageToRemoteMessage, elapsed: 601, isEligible: true),
            DirectionalCooldownScenario(direction: .remoteMessageToModal, elapsed: 86_399, isEligible: false),
            DirectionalCooldownScenario(direction: .remoteMessageToModal, elapsed: 86_400, isEligible: true),
            DirectionalCooldownScenario(direction: .remoteMessageToModal, elapsed: 86_401, isEligible: true),
        ]
    )
    func directionalCooldownBoundaries(_ scenario: DirectionalCooldownScenario) {
        let modalStore = PromptCooldownStoreSpy()
        let remoteMessageHistory = RemoteMessageHistorySpy()
        let interval: TimeInterval
        let policy: PromoQueueCooldownPolicy

        switch scenario.direction {
        case .modalToRemoteMessage:
            modalStore.lastPresentationTimestamp = referenceDate.timeIntervalSince1970
            interval = PromoQueueCooldownPolicy.remoteMessageTargetInterval
        case .remoteMessageToRemoteMessage:
            remoteMessageHistory.recordConfirmedAppearance(at: referenceDate)
            interval = PromoQueueCooldownPolicy.remoteMessageTargetInterval
        case .remoteMessageToModal:
            remoteMessageHistory.recordConfirmedAppearance(at: referenceDate)
            interval = PromoQueueCooldownPolicy.modalAfterRemoteMessageInterval
        }

        let now = referenceDate.addingTimeInterval(scenario.elapsed)
        policy = PromoQueueCooldownPolicy(
            modalPresentationStore: modalStore,
            remoteMessageHistory: remoteMessageHistory,
            dateProvider: { now }
        )
        let decision = switch scenario.direction {
        case .modalToRemoteMessage, .remoteMessageToRemoteMessage:
            policy.evaluateRemoteMessageAdmission()
        case .remoteMessageToModal:
            policy.evaluateModalAdmission()
        }

        if scenario.isEligible {
            #expect(decision == .eligible)
        } else {
            #expect(decision == .blocked(until: referenceDate.addingTimeInterval(interval)))
        }
    }

    @available(iOS 16, *)
    @Test("Future timestamps conservatively remain in cooldown", .timeLimit(.minutes(1)))
    func futureTimestampRemainsInCooldown() {
        let remoteMessageHistory = RemoteMessageHistorySpy()
        let futureAppearance = referenceDate.addingTimeInterval(60)
        remoteMessageHistory.recordConfirmedAppearance(at: futureAppearance)
        let policy = PromoQueueCooldownPolicy(
            modalPresentationStore: PromptCooldownStoreSpy(),
            remoteMessageHistory: remoteMessageHistory,
            dateProvider: { self.referenceDate }
        )

        #expect(
            policy.evaluateRemoteMessageAdmission() == .blocked(
                until: futureAppearance.addingTimeInterval(PromoQueueCooldownPolicy.remoteMessageTargetInterval)
            )
        )
        #expect(
            policy.evaluateModalAdmission() == .blocked(
                until: futureAppearance.addingTimeInterval(PromoQueueCooldownPolicy.modalAfterRemoteMessageInterval)
            )
        )
    }

    @available(iOS 16, *)
    @Test("RMF history keeps successful reads and failed writes authoritative in process", .timeLimit(.minutes(1)))
    func storageFailureFallback() {
        let key = PromoQueueRemoteMessageHistoryStore.StorageKey.lastConfirmedAppearance.rawValue
        let persistedDate = referenceDate.addingTimeInterval(-60)
        let keyValueStore = InMemoryThrowingKeyValueStore(
            underlyingDict: [key: persistedDate.timeIntervalSince1970]
        )
        let history = PromoQueueRemoteMessageHistoryStore(keyValueStore: keyValueStore)
        #expect(history.lastConfirmedAppearance == persistedDate)

        keyValueStore.throwOnRead = StoreError.read
        #expect(history.lastConfirmedAppearance == persistedDate)

        keyValueStore.throwOnSet = StoreError.write
        history.recordConfirmedAppearance(at: referenceDate)
        #expect(history.lastConfirmedAppearance == referenceDate)
        #expect(keyValueStore.underlyingDict[key] as? TimeInterval == persistedDate.timeIntervalSince1970)

        keyValueStore.throwOnRead = nil
        keyValueStore.throwOnSet = nil
        let reconstructedHistory = PromoQueueRemoteMessageHistoryStore(keyValueStore: keyValueStore)
        #expect(reconstructedHistory.lastConfirmedAppearance == persistedDate)
    }

    @available(iOS 16, *)
    @Test("A durable write failure still confirms the service-owned lease once", .timeLimit(.minutes(1)))
    func leaseConfirmationSurvivesDurableWriteFailure() throws {
        let keyValueStore = InMemoryThrowingKeyValueStore()
        keyValueStore.throwOnSet = StoreError.write
        let history = PromoQueueRemoteMessageHistoryStore(keyValueStore: keyValueStore)
        let policy = PromoQueueCooldownPolicy(
            modalPresentationStore: PromptCooldownStoreSpy(),
            remoteMessageHistory: history,
            dateProvider: { self.referenceDate }
        )
        let arbiter = PromoQueueLeaseArbiter()
        guard case .acquired(let arbiterLease) = arbiter.acquireRemoteMessageLease(for: "message") else {
            throw StoreError.acquisition
        }
        let lease = PromoQueueRemoteMessageLease(arbiterLease: arbiterLease, cooldownPolicy: policy)

        #expect(lease.markShown())
        #expect(!lease.markShown())
        #expect(history.lastConfirmedAppearance == referenceDate)
    }
}

private enum StoreError: Error {
    case read
    case write
    case acquisition
}

private final class PromptCooldownStoreSpy: PromptCooldownStore {
    var lastPresentationTimestamp: TimeInterval?
}

@MainActor
private final class RemoteMessageHistorySpy: PromoQueueRemoteMessageHistory {
    private(set) var lastConfirmedAppearance: Date?

    func recordConfirmedAppearance(at date: Date) {
        lastConfirmedAppearance = date
    }

    func reset() {
        lastConfirmedAppearance = nil
    }
}
