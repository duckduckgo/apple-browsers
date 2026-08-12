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

private enum ApprovedCooldownInterval {
    static let remoteMessageTarget: TimeInterval = 10 * 60
    static let modalAfterRemoteMessage: TimeInterval = 24 * 60 * 60
}

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
        "Directional cooldowns use their inclusive approved boundaries",
        .timeLimit(.minutes(1)),
        arguments: [
            DirectionalCooldownScenario(direction: .modalToRemoteMessage, elapsed: 599, isEligible: false),
            DirectionalCooldownScenario(direction: .modalToRemoteMessage, elapsed: 600, isEligible: true),
            DirectionalCooldownScenario(direction: .remoteMessageToRemoteMessage, elapsed: 599, isEligible: false),
            DirectionalCooldownScenario(direction: .remoteMessageToRemoteMessage, elapsed: 600, isEligible: true),
            DirectionalCooldownScenario(direction: .remoteMessageToModal, elapsed: 86_399, isEligible: false),
            DirectionalCooldownScenario(direction: .remoteMessageToModal, elapsed: 86_400, isEligible: true),
        ]
    )
    func whenEvaluatingDirectionalCooldownBoundaryThenEligibilityIsCorrect(_ scenario: DirectionalCooldownScenario) {
        let decision: PromoQueueCooldownDecision
        let boundary: Date

        switch scenario.direction {
        case .modalToRemoteMessage:
            let modalStore = PromptCooldownStoreSpy(timestamp: referenceDate.timeIntervalSince1970)
            let policy = makePolicy(modalStore: modalStore)
            decision = policy.evaluateRemoteMessageAdmission(now: referenceDate.addingTimeInterval(scenario.elapsed))
            boundary = referenceDate.addingTimeInterval(ApprovedCooldownInterval.remoteMessageTarget)
        case .remoteMessageToRemoteMessage:
            let remoteMessageStore = RemoteMessageCooldownStoreSpy(timestamp: referenceDate.timeIntervalSince1970)
            let policy = makePolicy(remoteMessageStore: remoteMessageStore)
            decision = policy.evaluateRemoteMessageAdmission(now: referenceDate.addingTimeInterval(scenario.elapsed))
            boundary = referenceDate.addingTimeInterval(ApprovedCooldownInterval.remoteMessageTarget)
        case .remoteMessageToModal:
            let remoteMessageStore = RemoteMessageCooldownStoreSpy(timestamp: referenceDate.timeIntervalSince1970)
            let policy = makePolicy(remoteMessageStore: remoteMessageStore)
            decision = policy.evaluateModalAdmission(now: referenceDate.addingTimeInterval(scenario.elapsed))
            boundary = referenceDate.addingTimeInterval(ApprovedCooldownInterval.modalAfterRemoteMessage)
        }

        expect(decision, isEligible: scenario.isEligible, boundary: boundary)
    }

    @available(iOS 16, *)
    @Test(
        "RMF admission uses the later modal or RMF boundary",
        .timeLimit(.minutes(1)),
        arguments: [
            (modalOffset: 0, remoteMessageOffset: -300),
            (modalOffset: -300, remoteMessageOffset: 0),
        ] as [(TimeInterval, TimeInterval)]
    )
    func whenBothHistoriesExistThenRemoteMessageAdmissionUsesMaximumBoundary(
        modalOffset: TimeInterval,
        remoteMessageOffset: TimeInterval
    ) {
        let modalAppearance = referenceDate.addingTimeInterval(modalOffset)
        let remoteMessageAppearance = referenceDate.addingTimeInterval(remoteMessageOffset)
        let modalStore = PromptCooldownStoreSpy(timestamp: modalAppearance.timeIntervalSince1970)
        let remoteMessageStore = RemoteMessageCooldownStoreSpy(timestamp: remoteMessageAppearance.timeIntervalSince1970)
        let policy = makePolicy(modalStore: modalStore, remoteMessageStore: remoteMessageStore)
        let expectedBoundary = max(modalAppearance, remoteMessageAppearance)
            .addingTimeInterval(ApprovedCooldownInterval.remoteMessageTarget)

        #expect(policy.evaluateRemoteMessageAdmission(now: referenceDate) == .blocked(until: expectedBoundary))
    }

    @available(iOS 16, *)
    @Test("No confirmed history allows both targets", .timeLimit(.minutes(1)))
    func whenHistoryIsAbsentThenBothTargetsAreEligible() {
        let policy = makePolicy()

        #expect(policy.evaluateRemoteMessageAdmission(now: referenceDate) == .eligible)
        #expect(policy.evaluateModalAdmission(now: referenceDate) == .eligible)
    }

    @available(iOS 16, *)
    @Test("Modal history is not used for modal admission", .timeLimit(.minutes(1)))
    func whenOnlyModalHistoryExistsThenModalAdmissionRemainsEligible() {
        let modalStore = PromptCooldownStoreSpy(timestamp: referenceDate.timeIntervalSince1970)
        let policy = makePolicy(modalStore: modalStore)

        #expect(policy.evaluateModalAdmission(now: referenceDate) == .eligible)
        #expect(modalStore.readCount == 0)
    }

    @available(iOS 16, *)
    @Test("Future history conservatively extends both cooldowns", .timeLimit(.minutes(1)))
    func whenClockMovesBackwardThenFutureHistoryExtendsCooldowns() {
        let futureModalAppearance = referenceDate.addingTimeInterval(300)
        let futureRemoteMessageAppearance = referenceDate.addingTimeInterval(600)
        let modalStore = PromptCooldownStoreSpy(timestamp: futureModalAppearance.timeIntervalSince1970)
        let remoteMessageStore = RemoteMessageCooldownStoreSpy(timestamp: futureRemoteMessageAppearance.timeIntervalSince1970)
        let policy = makePolicy(modalStore: modalStore, remoteMessageStore: remoteMessageStore)
        let expectedRemoteMessageBoundary = futureRemoteMessageAppearance
            .addingTimeInterval(ApprovedCooldownInterval.remoteMessageTarget)
        let expectedModalBoundary = futureRemoteMessageAppearance
            .addingTimeInterval(ApprovedCooldownInterval.modalAfterRemoteMessage)

        #expect(policy.evaluateRemoteMessageAdmission(now: referenceDate) == .blocked(until: expectedRemoteMessageBoundary))
        #expect(policy.evaluateModalAdmission(now: referenceDate) == .blocked(until: expectedModalBoundary))
    }

    @available(iOS 16, *)
    @Test("Confirmed RMF history persists across policy and store reconstruction", .timeLimit(.minutes(1)))
    func whenPolicyIsReconstructedThenPersistedRemoteMessageHistoryIsObserved() {
        let keyValueStore = MockKeyValueFileStore()
        let firstPolicy = PromoQueueCooldownPolicy(
            modalPresentationStore: PromptCooldownStoreSpy(),
            remoteMessagePresentationStore: PromoQueueRemoteMessageCooldownKeyValueFilesStore(keyValueStore: keyValueStore)
        )
        firstPolicy.recordConfirmedRemoteMessageAppearance(at: referenceDate)

        let reconstructedPolicy = PromoQueueCooldownPolicy(
            modalPresentationStore: PromptCooldownStoreSpy(),
            remoteMessagePresentationStore: PromoQueueRemoteMessageCooldownKeyValueFilesStore(keyValueStore: keyValueStore)
        )
        #expect(
            reconstructedPolicy.evaluateRemoteMessageAdmission(now: referenceDate.addingTimeInterval(1))
                == .blocked(until: referenceDate.addingTimeInterval(ApprovedCooldownInterval.remoteMessageTarget))
        )
        #expect(
            reconstructedPolicy.evaluateModalAdmission(now: referenceDate.addingTimeInterval(1))
                == .blocked(until: referenceDate.addingTimeInterval(ApprovedCooldownInterval.modalAfterRemoteMessage))
        )
    }

    @available(iOS 16, *)
    @Test("Recording an RMF appearance writes only confirmed RMF history", .timeLimit(.minutes(1)))
    func whenRecordingRemoteMessageAppearanceThenTimestampIsStored() {
        let modalStore = PromptCooldownStoreSpy()
        let remoteMessageStore = RemoteMessageCooldownStoreSpy()
        let policy = makePolicy(modalStore: modalStore, remoteMessageStore: remoteMessageStore)

        policy.recordConfirmedRemoteMessageAppearance(at: referenceDate)

        #expect(remoteMessageStore.timestamp == referenceDate.timeIntervalSince1970)
        #expect(remoteMessageStore.writeCount == 1)
        #expect(modalStore.writeCount == 0)
    }

    private func makePolicy(
        modalStore: PromptCooldownStoreSpy? = nil,
        remoteMessageStore: RemoteMessageCooldownStoreSpy? = nil
    ) -> PromoQueueCooldownPolicy {
        PromoQueueCooldownPolicy(
            modalPresentationStore: modalStore ?? PromptCooldownStoreSpy(),
            remoteMessagePresentationStore: remoteMessageStore ?? RemoteMessageCooldownStoreSpy()
        )
    }

    private func expect(_ decision: PromoQueueCooldownDecision, isEligible: Bool, boundary: Date) {
        if isEligible {
            #expect(decision == .eligible)
        } else {
            #expect(decision == .blocked(until: boundary))
        }
    }
}

@MainActor
@Suite("Promo Queue - Confirmed RMF Cooldown Store")
final class PromoQueueRemoteMessageCooldownStoreTests {
    private let referenceTimestamp: TimeInterval = 1_775_000_000

    @available(iOS 16, *)
    @Test("An initial read failure returns no history and retries later", .timeLimit(.minutes(1)))
    func whenInitialReadFailsThenLaterReadRetriesPersistence() {
        let keyValueStore = MockKeyValueFileStore()
        let persistenceWriter = PromoQueueRemoteMessageCooldownKeyValueFilesStore(keyValueStore: keyValueStore)
        persistenceWriter.lastConfirmedRemoteMessageTimestamp = referenceTimestamp
        keyValueStore.throwOnRead = StoreTestError.read
        let store = PromoQueueRemoteMessageCooldownKeyValueFilesStore(keyValueStore: keyValueStore)

        #expect(store.lastConfirmedRemoteMessageTimestamp == nil)

        keyValueStore.throwOnRead = nil
        #expect(store.lastConfirmedRemoteMessageTimestamp == referenceTimestamp)
    }

    @available(iOS 16, *)
    @Test("A diagnostic read does not warm the production failure fallback", .timeLimit(.minutes(1)))
    func whenDiagnosticReadSucceedsThenLaterProductionReadFailureHasNoFallback() {
        let keyValueStore = MockKeyValueFileStore()
        let persistenceWriter = PromoQueueRemoteMessageCooldownKeyValueFilesStore(keyValueStore: keyValueStore)
        persistenceWriter.lastConfirmedRemoteMessageTimestamp = referenceTimestamp
        let store = PromoQueueRemoteMessageCooldownKeyValueFilesStore(keyValueStore: keyValueStore)
        let debugSnapshotProvider = PromoQueueCooldownDebugSnapshotProvider(
            modalPresentationStore: PromptCooldownKeyValueFilesStore(
                keyValueStore: keyValueStore,
                eventMapper: .init { _, _, _, _ in }
            ),
            remoteMessagePresentationStore: store
        )

        #expect(
            debugSnapshotProvider.snapshot(now: .distantPast).lastConfirmedRemoteMessageAppearance ==
                Date(timeIntervalSince1970: referenceTimestamp)
        )

        keyValueStore.throwOnRead = StoreTestError.read
        #expect(store.lastConfirmedRemoteMessageTimestamp == nil)
    }

    @available(iOS 16, *)
    @Test("A failed diagnostic read preserves the production failure fallback", .timeLimit(.minutes(1)))
    func whenProductionCacheExistsThenDiagnosticReadFailureDoesNotChangeIt() {
        let keyValueStore = MockKeyValueFileStore()
        let persistenceWriter = PromoQueueRemoteMessageCooldownKeyValueFilesStore(keyValueStore: keyValueStore)
        persistenceWriter.lastConfirmedRemoteMessageTimestamp = referenceTimestamp
        let store = PromoQueueRemoteMessageCooldownKeyValueFilesStore(keyValueStore: keyValueStore)
        let debugSnapshotProvider = PromoQueueCooldownDebugSnapshotProvider(
            modalPresentationStore: PromptCooldownKeyValueFilesStore(
                keyValueStore: keyValueStore,
                eventMapper: .init { _, _, _, _ in }
            ),
            remoteMessagePresentationStore: store
        )
        #expect(store.lastConfirmedRemoteMessageTimestamp == referenceTimestamp)

        keyValueStore.throwOnRead = StoreTestError.read

        #expect(
            debugSnapshotProvider.snapshot(now: .distantPast).lastConfirmedRemoteMessageAppearance ==
                Date(timeIntervalSince1970: referenceTimestamp)
        )
        #expect(store.lastConfirmedRemoteMessageTimestamp == referenceTimestamp)
    }

    @available(iOS 16, *)
    @Test(
        "A later read failure returns the last successfully read optional timestamp and recovers",
        .timeLimit(.minutes(1)),
        arguments: [nil, 1_775_000_000] as [TimeInterval?]
    )
    func whenReadFailsAfterSuccessThenCachedTimestampIsReturned(lastSuccessfulTimestamp: TimeInterval?) {
        let recoveredTimestamp = referenceTimestamp + 1
        let keyValueStore = MockKeyValueFileStore()
        let persistenceWriter = PromoQueueRemoteMessageCooldownKeyValueFilesStore(keyValueStore: keyValueStore)
        persistenceWriter.lastConfirmedRemoteMessageTimestamp = lastSuccessfulTimestamp
        let store = PromoQueueRemoteMessageCooldownKeyValueFilesStore(keyValueStore: keyValueStore)
        #expect(store.lastConfirmedRemoteMessageTimestamp == lastSuccessfulTimestamp)

        let persistenceMutator = PromoQueueRemoteMessageCooldownKeyValueFilesStore(keyValueStore: keyValueStore)
        persistenceMutator.lastConfirmedRemoteMessageTimestamp = recoveredTimestamp

        keyValueStore.throwOnRead = StoreTestError.read

        #expect(store.lastConfirmedRemoteMessageTimestamp == lastSuccessfulTimestamp)

        keyValueStore.throwOnRead = nil
        #expect(store.lastConfirmedRemoteMessageTimestamp == recoveredTimestamp)
    }

    @available(iOS 16, *)
    @Test("A successful write updates persistence and current-process memory", .timeLimit(.minutes(1)))
    func whenWriteSucceedsThenTimestampIsPersistedAndAuthoritativeInMemory() {
        let keyValueStore = MockKeyValueFileStore()
        let store = PromoQueueRemoteMessageCooldownKeyValueFilesStore(keyValueStore: keyValueStore)

        store.lastConfirmedRemoteMessageTimestamp = referenceTimestamp

        let reconstructedStore = PromoQueueRemoteMessageCooldownKeyValueFilesStore(keyValueStore: keyValueStore)
        #expect(reconstructedStore.lastConfirmedRemoteMessageTimestamp == referenceTimestamp)

        let persistenceMutator = PromoQueueRemoteMessageCooldownKeyValueFilesStore(keyValueStore: keyValueStore)
        persistenceMutator.lastConfirmedRemoteMessageTimestamp = referenceTimestamp - 1
        #expect(store.lastConfirmedRemoteMessageTimestamp == referenceTimestamp)
    }

    @available(iOS 16, *)
    @Test("A failed write remains authoritative only in the current process", .timeLimit(.minutes(1)))
    func whenWriteFailsThenAttemptedTimestampIsKeptInMemoryButNotReconstructed() {
        let persistedTimestamp = referenceTimestamp - 1
        let keyValueStore = MockKeyValueFileStore()
        let persistenceWriter = PromoQueueRemoteMessageCooldownKeyValueFilesStore(keyValueStore: keyValueStore)
        persistenceWriter.lastConfirmedRemoteMessageTimestamp = persistedTimestamp
        let store = PromoQueueRemoteMessageCooldownKeyValueFilesStore(keyValueStore: keyValueStore)
        #expect(store.lastConfirmedRemoteMessageTimestamp == persistedTimestamp)
        let debugSnapshotProvider = PromoQueueCooldownDebugSnapshotProvider(
            modalPresentationStore: PromptCooldownKeyValueFilesStore(
                keyValueStore: keyValueStore,
                eventMapper: .init { _, _, _, _ in }
            ),
            remoteMessagePresentationStore: store
        )
        keyValueStore.throwOnSet = StoreTestError.write

        store.lastConfirmedRemoteMessageTimestamp = referenceTimestamp

        #expect(store.lastConfirmedRemoteMessageTimestamp == referenceTimestamp)
        #expect(
            debugSnapshotProvider.snapshot(now: .distantPast).lastConfirmedRemoteMessageAppearance ==
                Date(timeIntervalSince1970: referenceTimestamp)
        )

        keyValueStore.throwOnSet = nil
        let reconstructedStore = PromoQueueRemoteMessageCooldownKeyValueFilesStore(keyValueStore: keyValueStore)
        #expect(reconstructedStore.lastConfirmedRemoteMessageTimestamp == persistedTimestamp)
    }
}

private enum StoreTestError: Error {
    case read
    case write
}

private final class PromptCooldownStoreSpy: PromptCooldownStore {
    private var storedTimestamp: TimeInterval?
    private(set) var readCount = 0
    private(set) var writeCount = 0

    init(timestamp: TimeInterval? = nil) {
        storedTimestamp = timestamp
    }

    var lastPresentationTimestamp: TimeInterval? {
        get {
            readCount += 1
            return storedTimestamp
        }
        set {
            writeCount += 1
            storedTimestamp = newValue
        }
    }
}

@MainActor
private final class RemoteMessageCooldownStoreSpy: PromoQueueRemoteMessageCooldownStoring {
    private var storedTimestamp: TimeInterval?
    private(set) var readCount = 0
    private(set) var writeCount = 0

    init(timestamp: TimeInterval? = nil) {
        storedTimestamp = timestamp
    }

    var timestamp: TimeInterval? {
        storedTimestamp
    }

    var lastConfirmedRemoteMessageTimestamp: TimeInterval? {
        get {
            readCount += 1
            return storedTimestamp
        }
        set {
            writeCount += 1
            storedTimestamp = newValue
        }
    }
}
