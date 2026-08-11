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

@MainActor
@Suite("Promo Queue - Directional Cooldown Policy")
final class PromoQueueCooldownPolicyTests {
    private let referenceDate = Date(timeIntervalSince1970: 1_775_000_000)

    @Test(
        "Modal to RMF uses an inclusive ten-minute boundary",
        arguments: [
            (599, false),
            (600, true),
            (601, true),
        ] as [(TimeInterval, Bool)]
    )
    func whenEvaluatingModalToRemoteMessageBoundaryThenEligibilityIsCorrect(elapsed: TimeInterval, isEligible: Bool) {
        let modalStore = PromptCooldownStoreSpy(timestamp: referenceDate.timeIntervalSince1970)
        let policy = makePolicy(modalStore: modalStore)
        let boundary = referenceDate.addingTimeInterval(PromoQueueCooldownPolicy.remoteMessageTargetInterval)

        let decision = policy.evaluateRemoteMessageAdmission(now: referenceDate.addingTimeInterval(elapsed))

        expect(decision, isEligible: isEligible, boundary: boundary)
    }

    @Test(
        "RMF to RMF uses an inclusive ten-minute boundary",
        arguments: [
            (599, false),
            (600, true),
            (601, true),
        ] as [(TimeInterval, Bool)]
    )
    func whenEvaluatingRemoteMessageToRemoteMessageBoundaryThenEligibilityIsCorrect(elapsed: TimeInterval, isEligible: Bool) {
        let remoteMessageStore = RemoteMessageCooldownStoreSpy(timestamp: referenceDate.timeIntervalSince1970)
        let policy = makePolicy(remoteMessageStore: remoteMessageStore)
        let boundary = referenceDate.addingTimeInterval(PromoQueueCooldownPolicy.remoteMessageTargetInterval)

        let decision = policy.evaluateRemoteMessageAdmission(now: referenceDate.addingTimeInterval(elapsed))

        expect(decision, isEligible: isEligible, boundary: boundary)
    }

    @Test(
        "RMF to modal uses an inclusive twenty-four-hour boundary",
        arguments: [
            (86_399, false),
            (86_400, true),
            (86_401, true),
        ] as [(TimeInterval, Bool)]
    )
    func whenEvaluatingRemoteMessageToModalBoundaryThenEligibilityIsCorrect(elapsed: TimeInterval, isEligible: Bool) {
        let remoteMessageStore = RemoteMessageCooldownStoreSpy(timestamp: referenceDate.timeIntervalSince1970)
        let policy = makePolicy(remoteMessageStore: remoteMessageStore)
        let boundary = referenceDate.addingTimeInterval(PromoQueueCooldownPolicy.modalAfterRemoteMessageInterval)

        let decision = policy.evaluateModalAdmission(now: referenceDate.addingTimeInterval(elapsed))

        expect(decision, isEligible: isEligible, boundary: boundary)
    }

    @Test("RMF admission uses the later modal or RMF boundary")
    func whenBothHistoriesExistThenRemoteMessageAdmissionUsesMaximumBoundary() {
        let historyPairs = [
            (modal: referenceDate, remoteMessage: referenceDate.addingTimeInterval(-300)),
            (modal: referenceDate.addingTimeInterval(-300), remoteMessage: referenceDate),
            (modal: referenceDate, remoteMessage: referenceDate),
        ]

        for histories in historyPairs {
            let modalStore = PromptCooldownStoreSpy(timestamp: histories.modal.timeIntervalSince1970)
            let remoteMessageStore = RemoteMessageCooldownStoreSpy(timestamp: histories.remoteMessage.timeIntervalSince1970)
            let policy = makePolicy(modalStore: modalStore, remoteMessageStore: remoteMessageStore)
            let expectedBoundary = max(histories.modal, histories.remoteMessage)
                .addingTimeInterval(PromoQueueCooldownPolicy.remoteMessageTargetInterval)

            let snapshot = policy.snapshot(now: referenceDate)

            #expect(snapshot.nextRemoteMessageEligibility == expectedBoundary)
            #expect(policy.evaluateRemoteMessageAdmission(now: referenceDate) == .blocked(until: expectedBoundary))
        }
    }

    @Test("No confirmed history allows both targets")
    func whenHistoryIsAbsentThenBothTargetsAreEligible() {
        let policy = makePolicy()

        #expect(policy.evaluateRemoteMessageAdmission(now: referenceDate) == .eligible)
        #expect(policy.evaluateModalAdmission(now: referenceDate) == .eligible)
        #expect(policy.snapshot(now: referenceDate) == .empty)
    }

    @Test("Modal history is not used for modal admission")
    func whenOnlyModalHistoryExistsThenModalAdmissionRemainsEligible() {
        let modalStore = PromptCooldownStoreSpy(timestamp: referenceDate.timeIntervalSince1970)
        let policy = makePolicy(modalStore: modalStore)

        #expect(policy.evaluateModalAdmission(now: referenceDate) == .eligible)
    }

    @Test("Future history conservatively extends both cooldowns")
    func whenClockMovesBackwardThenFutureHistoryExtendsCooldowns() {
        let futureModalAppearance = referenceDate.addingTimeInterval(300)
        let futureRemoteMessageAppearance = referenceDate.addingTimeInterval(600)
        let modalStore = PromptCooldownStoreSpy(timestamp: futureModalAppearance.timeIntervalSince1970)
        let remoteMessageStore = RemoteMessageCooldownStoreSpy(timestamp: futureRemoteMessageAppearance.timeIntervalSince1970)
        let policy = makePolicy(modalStore: modalStore, remoteMessageStore: remoteMessageStore)
        let expectedRemoteMessageBoundary = futureRemoteMessageAppearance
            .addingTimeInterval(PromoQueueCooldownPolicy.remoteMessageTargetInterval)
        let expectedModalBoundary = futureRemoteMessageAppearance
            .addingTimeInterval(PromoQueueCooldownPolicy.modalAfterRemoteMessageInterval)

        #expect(policy.evaluateRemoteMessageAdmission(now: referenceDate) == .blocked(until: expectedRemoteMessageBoundary))
        #expect(policy.evaluateModalAdmission(now: referenceDate) == .blocked(until: expectedModalBoundary))
    }

    @Test("Confirmed RMF history persists across policy and store reconstruction")
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
        let snapshot = reconstructedPolicy.snapshot(now: referenceDate.addingTimeInterval(1))

        #expect(snapshot.lastConfirmedRemoteMessageAppearance == referenceDate)
        #expect(
            reconstructedPolicy.evaluateRemoteMessageAdmission(now: referenceDate.addingTimeInterval(1))
                == .blocked(until: referenceDate.addingTimeInterval(PromoQueueCooldownPolicy.remoteMessageTargetInterval))
        )
        #expect(
            reconstructedPolicy.evaluateModalAdmission(now: referenceDate.addingTimeInterval(1))
                == .blocked(until: referenceDate.addingTimeInterval(PromoQueueCooldownPolicy.modalAfterRemoteMessageInterval))
        )
    }

    @Test("Snapshot derives history and boundaries without writing either store")
    func whenTakingSnapshotThenValuesAreDerivedWithoutSideEffects() {
        let modalAppearance = referenceDate.addingTimeInterval(-300)
        let remoteMessageAppearance = referenceDate.addingTimeInterval(-120)
        let modalStore = PromptCooldownStoreSpy(timestamp: modalAppearance.timeIntervalSince1970)
        let remoteMessageStore = RemoteMessageCooldownStoreSpy(timestamp: remoteMessageAppearance.timeIntervalSince1970)
        let policy = makePolicy(modalStore: modalStore, remoteMessageStore: remoteMessageStore)

        let snapshot = policy.snapshot(now: referenceDate)

        #expect(
            snapshot == PromoQueueCooldownSnapshot(
                lastConfirmedModalAppearance: modalAppearance,
                lastConfirmedRemoteMessageAppearance: remoteMessageAppearance,
                nextRemoteMessageEligibility: remoteMessageAppearance.addingTimeInterval(PromoQueueCooldownPolicy.remoteMessageTargetInterval),
                nextModalEligibility: remoteMessageAppearance.addingTimeInterval(PromoQueueCooldownPolicy.modalAfterRemoteMessageInterval)
            )
        )
        #expect(modalStore.readCount == 1)
        #expect(modalStore.writeCount == 0)
        #expect(remoteMessageStore.readCount == 1)
        #expect(remoteMessageStore.writeCount == 0)
    }

    @Test("Recording an RMF appearance writes only confirmed RMF history")
    func whenRecordingRemoteMessageAppearanceThenTimestampIsStored() {
        let modalStore = PromptCooldownStoreSpy()
        let remoteMessageStore = RemoteMessageCooldownStoreSpy()
        let policy = makePolicy(modalStore: modalStore, remoteMessageStore: remoteMessageStore)

        policy.recordConfirmedRemoteMessageAppearance(at: referenceDate)

        #expect(remoteMessageStore.timestamp == referenceDate.timeIntervalSince1970)
        #expect(remoteMessageStore.writeCount == 1)
        #expect(modalStore.writeCount == 0)
    }

    @Test("Iteration-one cooldown intervals are fixed constants")
    func whenInspectingIntervalsThenTheyMatchTheApprovedPolicy() {
        #expect(PromoQueueCooldownPolicy.remoteMessageTargetInterval == 10 * 60)
        #expect(PromoQueueCooldownPolicy.modalAfterRemoteMessageInterval == 24 * 60 * 60)
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

    @Test("An initial read failure returns no history and retries later")
    func whenInitialReadFailsThenLaterReadRetriesPersistence() {
        let keyValueStore = MockKeyValueFileStore(
            underlyingDict: [
                PromoQueueRemoteMessageCooldownKeyValueFilesStore.StorageKey.lastConfirmedRemoteMessageTimestamp: referenceTimestamp
            ]
        )
        keyValueStore.throwOnRead = StoreTestError.read
        let store = PromoQueueRemoteMessageCooldownKeyValueFilesStore(keyValueStore: keyValueStore)

        #expect(store.lastConfirmedRemoteMessageTimestamp == nil)

        keyValueStore.throwOnRead = nil
        #expect(store.lastConfirmedRemoteMessageTimestamp == referenceTimestamp)
    }

    @Test("A diagnostic read does not warm the production failure fallback")
    func whenDiagnosticReadSucceedsThenLaterProductionReadFailureHasNoFallback() {
        let keyValueStore = MockKeyValueFileStore()
        let persistenceWriter = PromoQueueRemoteMessageCooldownKeyValueFilesStore(keyValueStore: keyValueStore)
        persistenceWriter.lastConfirmedRemoteMessageTimestamp = referenceTimestamp
        let store = PromoQueueRemoteMessageCooldownKeyValueFilesStore(keyValueStore: keyValueStore)

        #expect(store.lastConfirmedRemoteMessageTimestampForPromoQueueDiagnostics() == referenceTimestamp)

        keyValueStore.throwOnRead = StoreTestError.read
        #expect(store.lastConfirmedRemoteMessageTimestamp == nil)
    }

    @Test("A failed diagnostic read preserves the production failure fallback")
    func whenProductionCacheExistsThenDiagnosticReadFailureDoesNotChangeIt() {
        let keyValueStore = MockKeyValueFileStore()
        let persistenceWriter = PromoQueueRemoteMessageCooldownKeyValueFilesStore(keyValueStore: keyValueStore)
        persistenceWriter.lastConfirmedRemoteMessageTimestamp = referenceTimestamp
        let store = PromoQueueRemoteMessageCooldownKeyValueFilesStore(keyValueStore: keyValueStore)
        #expect(store.lastConfirmedRemoteMessageTimestamp == referenceTimestamp)

        keyValueStore.throwOnRead = StoreTestError.read

        #expect(store.lastConfirmedRemoteMessageTimestampForPromoQueueDiagnostics() == referenceTimestamp)
        #expect(store.lastConfirmedRemoteMessageTimestamp == referenceTimestamp)
    }

    @Test("Diagnostics preserve the current-process authoritative RMF value")
    func whenPersistenceWriteFailsThenDiagnosticReadUsesLocallyConfirmedValue() {
        let persistedTimestamp = referenceTimestamp - 1
        let keyValueStore = MockKeyValueFileStore()
        let persistenceWriter = PromoQueueRemoteMessageCooldownKeyValueFilesStore(keyValueStore: keyValueStore)
        persistenceWriter.lastConfirmedRemoteMessageTimestamp = persistedTimestamp
        let store = PromoQueueRemoteMessageCooldownKeyValueFilesStore(keyValueStore: keyValueStore)
        keyValueStore.throwOnSet = StoreTestError.write

        store.lastConfirmedRemoteMessageTimestamp = referenceTimestamp

        #expect(store.lastConfirmedRemoteMessageTimestampForPromoQueueDiagnostics() == referenceTimestamp)
        keyValueStore.throwOnSet = nil
        let reconstructedStore = PromoQueueRemoteMessageCooldownKeyValueFilesStore(keyValueStore: keyValueStore)
        #expect(reconstructedStore.lastConfirmedRemoteMessageTimestamp == persistedTimestamp)
    }

    @Test(
        "A later read failure returns the last successfully read optional timestamp and recovers",
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

    @Test("A successful nil read is cached for a later failure")
    func whenNilReadSucceedsThenLaterFailureReturnsCachedNil() {
        let keyValueStore = MockKeyValueFileStore()
        let store = PromoQueueRemoteMessageCooldownKeyValueFilesStore(keyValueStore: keyValueStore)
        #expect(store.lastConfirmedRemoteMessageTimestamp == nil)

        keyValueStore.underlyingDict[
            PromoQueueRemoteMessageCooldownKeyValueFilesStore.StorageKey.lastConfirmedRemoteMessageTimestamp
        ] = referenceTimestamp
        keyValueStore.throwOnRead = StoreTestError.read

        #expect(store.lastConfirmedRemoteMessageTimestamp == nil)

        keyValueStore.throwOnRead = nil
        #expect(store.lastConfirmedRemoteMessageTimestamp == referenceTimestamp)
    }

    @Test("A successful write updates persistence and current-process memory")
    func whenWriteSucceedsThenTimestampIsPersistedAndAuthoritativeInMemory() {
        let key = PromoQueueRemoteMessageCooldownKeyValueFilesStore.StorageKey.lastConfirmedRemoteMessageTimestamp
        let keyValueStore = MockKeyValueFileStore()
        let store = PromoQueueRemoteMessageCooldownKeyValueFilesStore(keyValueStore: keyValueStore)

        store.lastConfirmedRemoteMessageTimestamp = referenceTimestamp

        #expect(keyValueStore.underlyingDict[key] as? TimeInterval == referenceTimestamp)
        keyValueStore.underlyingDict[key] = referenceTimestamp - 1
        #expect(store.lastConfirmedRemoteMessageTimestamp == referenceTimestamp)
    }

    @Test("A failed write remains authoritative only in the current process")
    func whenWriteFailsThenAttemptedTimestampIsKeptInMemoryButNotReconstructed() {
        let key = PromoQueueRemoteMessageCooldownKeyValueFilesStore.StorageKey.lastConfirmedRemoteMessageTimestamp
        let persistedTimestamp = referenceTimestamp - 1
        let keyValueStore = MockKeyValueFileStore(underlyingDict: [key: persistedTimestamp])
        let store = PromoQueueRemoteMessageCooldownKeyValueFilesStore(keyValueStore: keyValueStore)
        #expect(store.lastConfirmedRemoteMessageTimestamp == persistedTimestamp)
        keyValueStore.throwOnSet = StoreTestError.write

        store.lastConfirmedRemoteMessageTimestamp = referenceTimestamp

        #expect(store.lastConfirmedRemoteMessageTimestamp == referenceTimestamp)
        #expect(keyValueStore.underlyingDict[key] as? TimeInterval == persistedTimestamp)

        keyValueStore.throwOnSet = nil
        let reconstructedStore = PromoQueueRemoteMessageCooldownKeyValueFilesStore(keyValueStore: keyValueStore)
        #expect(reconstructedStore.lastConfirmedRemoteMessageTimestamp == persistedTimestamp)
    }

    @Test("A persisted write is observed after store reconstruction")
    func whenStoreIsReconstructedThenPersistedTimestampIsObserved() {
        let keyValueStore = MockKeyValueFileStore()
        let firstStore = PromoQueueRemoteMessageCooldownKeyValueFilesStore(keyValueStore: keyValueStore)
        firstStore.lastConfirmedRemoteMessageTimestamp = referenceTimestamp

        let reconstructedStore = PromoQueueRemoteMessageCooldownKeyValueFilesStore(keyValueStore: keyValueStore)

        #expect(reconstructedStore.lastConfirmedRemoteMessageTimestamp == referenceTimestamp)
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
