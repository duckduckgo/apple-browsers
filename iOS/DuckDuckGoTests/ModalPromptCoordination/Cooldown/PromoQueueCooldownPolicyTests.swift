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
    func modalToRemoteMessageBoundary(elapsed: TimeInterval, isEligible: Bool) throws {
        let clock = TimeTraveller(date: referenceDate.addingTimeInterval(elapsed))
        let modalStore = InMemoryPromptCooldownStore()
        modalStore.lastPresentationTimestamp = referenceDate.timeIntervalSince1970
        let policy = makePolicy(clock: clock, modalStore: modalStore)
        let expectedBoundary = referenceDate.addingTimeInterval(PromoQueueCooldownPolicy.remoteMessageTargetInterval)

        let result = policy.reserveRemoteMessageAdmission(for: makeIdentity())

        if isEligible {
            let reservation = try requireReservation(from: result)
            #expect(reservation.release())
        } else {
            #expect(try requireBlockedBoundary(from: result) == expectedBoundary)
        }
    }

    @Test(
        "RMF to RMF uses an inclusive global ten-minute boundary",
        arguments: [
            (599, false),
            (600, true),
            (601, true),
        ] as [(TimeInterval, Bool)]
    )
    func remoteMessageToRemoteMessageBoundary(elapsed: TimeInterval, isEligible: Bool) throws {
        let clock = TimeTraveller(date: referenceDate.addingTimeInterval(elapsed))
        let remoteMessageStore = RemoteMessageCooldownStoreSpy()
        remoteMessageStore.storedTimestamp = referenceDate.timeIntervalSince1970
        let policy = makePolicy(clock: clock, remoteMessageStore: remoteMessageStore)
        let expectedBoundary = referenceDate.addingTimeInterval(PromoQueueCooldownPolicy.remoteMessageTargetInterval)

        let result = policy.reserveRemoteMessageAdmission(for: makeIdentity())

        if isEligible {
            let reservation = try requireReservation(from: result)
            #expect(reservation.release())
        } else {
            #expect(try requireBlockedBoundary(from: result) == expectedBoundary)
        }
    }

    @Test(
        "RMF to modal uses an inclusive fixed twenty-four-hour boundary",
        arguments: [
            (86_399, false),
            (86_400, true),
            (86_401, true),
        ] as [(TimeInterval, Bool)]
    )
    func remoteMessageToModalBoundary(elapsed: TimeInterval, isEligible: Bool) throws {
        let clock = TimeTraveller(date: referenceDate.addingTimeInterval(elapsed))
        let remoteMessageStore = RemoteMessageCooldownStoreSpy()
        remoteMessageStore.storedTimestamp = referenceDate.timeIntervalSince1970
        let policy = makePolicy(clock: clock, remoteMessageStore: remoteMessageStore)
        let expectedBoundary = referenceDate.addingTimeInterval(PromoQueueCooldownPolicy.modalAfterRemoteMessageInterval)

        let result = policy.evaluateModalAdmission()

        if isEligible {
            #expect(result == .eligible)
        } else {
            #expect(result == .blocked(until: expectedBoundary))
        }
    }

    @Test("RMF admission uses the later modal or RMF target boundary")
    func remoteMessageAdmissionUsesMaximumBoundary() throws {
        let lastModalAppearance = referenceDate
        let lastRemoteMessageAppearance = referenceDate.addingTimeInterval(5 * 60)
        let expectedBoundary = lastRemoteMessageAppearance.addingTimeInterval(PromoQueueCooldownPolicy.remoteMessageTargetInterval)
        let clock = TimeTraveller(
            date: lastModalAppearance.addingTimeInterval(PromoQueueCooldownPolicy.remoteMessageTargetInterval)
        )
        let modalStore = InMemoryPromptCooldownStore()
        modalStore.lastPresentationTimestamp = lastModalAppearance.timeIntervalSince1970
        let remoteMessageStore = RemoteMessageCooldownStoreSpy()
        remoteMessageStore.storedTimestamp = lastRemoteMessageAppearance.timeIntervalSince1970
        let policy = makePolicy(
            clock: clock,
            modalStore: modalStore,
            remoteMessageStore: remoteMessageStore
        )

        #expect(policy.snapshot.nextRemoteMessageEligibility == expectedBoundary)
        #expect(try requireBlockedBoundary(from: policy.reserveRemoteMessageAdmission(for: makeIdentity())) == expectedBoundary)

        clock.setNowDate(expectedBoundary)
        let reservation = try requireReservation(from: policy.reserveRemoteMessageAdmission(for: makeIdentity()))
        #expect(reservation.release())
    }

    @Test("Backward wall-clock movement conservatively extends remaining cooldown")
    func backwardClockMovementExtendsCooldown() throws {
        let clock = TimeTraveller(date: referenceDate)
        let remoteMessageStore = RemoteMessageCooldownStoreSpy()
        let policy = makePolicy(clock: clock, remoteMessageStore: remoteMessageStore)
        let reservation = try requireReservation(from: policy.reserveRemoteMessageAdmission(for: makeIdentity()))
        #expect(reservation.confirm())

        clock.advanceBy(5 * 60)
        clock.setNowDate(referenceDate.addingTimeInterval(-5 * 60))

        let expectedRemoteMessageBoundary = referenceDate.addingTimeInterval(PromoQueueCooldownPolicy.remoteMessageTargetInterval)
        let expectedModalBoundary = referenceDate.addingTimeInterval(PromoQueueCooldownPolicy.modalAfterRemoteMessageInterval)
        #expect(
            try requireBlockedBoundary(from: policy.reserveRemoteMessageAdmission(for: makeIdentity()))
                == expectedRemoteMessageBoundary
        )
        #expect(policy.evaluateModalAdmission() == .blocked(until: expectedModalBoundary))
    }

    @Test("Persisted RMF history is restored by a new store and policy")
    func persistedRemoteMessageHistorySurvivesRelaunch() throws {
        let keyValueStore = try MockKeyValueFileStore()
        let clock = TimeTraveller(date: referenceDate)
        var firstPolicy: PromoQueueCooldownPolicy? = PromoQueueCooldownPolicy(
            modalPresentationStore: InMemoryPromptCooldownStore(),
            remoteMessagePresentationStore: PromoQueueRemoteMessageCooldownKeyValueFilesStore(keyValueStore: keyValueStore),
            dateProvider: clock.getDate
        )
        let unwrappedFirstPolicy = try #require(firstPolicy)
        let reservation = try requireReservation(
            from: unwrappedFirstPolicy.reserveRemoteMessageAdmission(for: makeIdentity())
        )
        #expect(reservation.confirm())
        firstPolicy = nil

        clock.advanceBy(1)
        let relaunchedPolicy = PromoQueueCooldownPolicy(
            modalPresentationStore: InMemoryPromptCooldownStore(),
            remoteMessagePresentationStore: PromoQueueRemoteMessageCooldownKeyValueFilesStore(keyValueStore: keyValueStore),
            dateProvider: clock.getDate
        )

        #expect(relaunchedPolicy.snapshot.lastConfirmedRemoteMessageAppearance == referenceDate)
        #expect(relaunchedPolicy.snapshot.provisionalRemoteMessageIdentity == nil)
        #expect(
            try requireBlockedBoundary(from: relaunchedPolicy.reserveRemoteMessageAdmission(for: makeIdentity()))
                == referenceDate.addingTimeInterval(PromoQueueCooldownPolicy.remoteMessageTargetInterval)
        )
        #expect(
            relaunchedPolicy.evaluateModalAdmission()
                == .blocked(until: referenceDate.addingTimeInterval(PromoQueueCooldownPolicy.modalAfterRemoteMessageInterval))
        )
    }

    @Test("One provisional reservation serializes RMF admission across IDs and surfaces")
    func provisionalReservationIsGlobalAcrossRemoteMessageIdentities() throws {
        let clock = TimeTraveller(date: referenceDate)
        let policy = makePolicy(clock: clock)
        let firstSurfaceID = UUID()
        let firstIdentity = makeIdentity(surfaceID: firstSurfaceID, promoID: "message-a")
        let firstReservation = try requireReservation(
            from: policy.reserveRemoteMessageAdmission(for: firstIdentity)
        )

        let differentIDResult = policy.reserveRemoteMessageAdmission(
            for: makeIdentity(surfaceID: firstSurfaceID, promoID: "message-b")
        )
        let differentSurfaceResult = policy.reserveRemoteMessageAdmission(
            for: makeIdentity(surfaceID: UUID(), promoID: "message-c")
        )

        guard case .provisionalReservationInProgress = differentIDResult else {
            throw TestError.expectedProvisionalReservationInProgress
        }
        guard case .provisionalReservationInProgress = differentSurfaceResult else {
            throw TestError.expectedProvisionalReservationInProgress
        }
        #expect(policy.snapshot.provisionalRemoteMessageIdentity == firstIdentity)
        #expect(firstReservation.release())
    }

    @Test("Withdrawing an unconfirmed reservation does not write RMF history")
    func withdrawingReservationDoesNotWriteHistory() throws {
        let clock = TimeTraveller(date: referenceDate)
        let remoteMessageStore = RemoteMessageCooldownStoreSpy()
        let policy = makePolicy(clock: clock, remoteMessageStore: remoteMessageStore)
        let reservation = try requireReservation(from: policy.reserveRemoteMessageAdmission(for: makeIdentity()))

        #expect(reservation.release())

        #expect(remoteMessageStore.writeCount == 0)
        #expect(remoteMessageStore.storedTimestamp == nil)
        #expect(policy.snapshot.provisionalRemoteMessageIdentity == nil)
        #expect(!reservation.release())
        #expect(!reservation.confirm())
    }

    @Test("Stale reservation tokens cannot confirm or release a replacement")
    func staleReservationTokensCannotMutateReplacement() throws {
        let clock = TimeTraveller(date: referenceDate)
        let remoteMessageStore = RemoteMessageCooldownStoreSpy()
        let policy = makePolicy(clock: clock, remoteMessageStore: remoteMessageStore)
        let staleConfirmation = try requireReservation(
            from: policy.reserveRemoteMessageAdmission(for: makeIdentity(promoID: "stale-confirmation"))
        )
        policy.resetTransientState()
        let replacementAfterConfirmation = try requireReservation(
            from: policy.reserveRemoteMessageAdmission(for: makeIdentity(promoID: "replacement-after-confirmation"))
        )

        #expect(!staleConfirmation.confirm())
        #expect(policy.snapshot.provisionalRemoteMessageIdentity?.promoID == "replacement-after-confirmation")
        #expect(replacementAfterConfirmation.release())

        let staleRelease = try requireReservation(
            from: policy.reserveRemoteMessageAdmission(for: makeIdentity(promoID: "stale-release"))
        )
        policy.resetTransientState()
        let replacementAfterRelease = try requireReservation(
            from: policy.reserveRemoteMessageAdmission(for: makeIdentity(promoID: "replacement-after-release"))
        )

        #expect(!staleRelease.release())
        #expect(policy.snapshot.provisionalRemoteMessageIdentity?.promoID == "replacement-after-release")
        #expect(replacementAfterRelease.confirm())
        #expect(remoteMessageStore.writeCount == 1)
        #expect(remoteMessageStore.storedTimestamp == referenceDate.timeIntervalSince1970)
    }

    @Test("A matching reservation confirms and persists exactly once")
    func matchingReservationConfirmsOnce() throws {
        let clock = TimeTraveller(date: referenceDate)
        let remoteMessageStore = RemoteMessageCooldownStoreSpy()
        let policy = makePolicy(clock: clock, remoteMessageStore: remoteMessageStore)
        let reservation = try requireReservation(from: policy.reserveRemoteMessageAdmission(for: makeIdentity()))

        #expect(reservation.confirm())
        #expect(!reservation.confirm())
        #expect(!reservation.release())

        #expect(remoteMessageStore.writeCount == 1)
        #expect(remoteMessageStore.storedTimestamp == referenceDate.timeIntervalSince1970)
        #expect(policy.snapshot.lastConfirmedRemoteMessageAppearance == referenceDate)
        #expect(policy.snapshot.provisionalRemoteMessageIdentity == nil)
    }

    @Test("Reset clears provisional state while retaining confirmed history")
    func resetTransientStateRetainsConfirmedHistory() throws {
        let lastModalAppearance = referenceDate
        let lastRemoteMessageAppearance = referenceDate.addingTimeInterval(60)
        let clock = TimeTraveller(
            date: lastRemoteMessageAppearance.addingTimeInterval(PromoQueueCooldownPolicy.modalAfterRemoteMessageInterval)
        )
        let modalStore = InMemoryPromptCooldownStore()
        modalStore.lastPresentationTimestamp = lastModalAppearance.timeIntervalSince1970
        let remoteMessageStore = RemoteMessageCooldownStoreSpy()
        remoteMessageStore.storedTimestamp = lastRemoteMessageAppearance.timeIntervalSince1970
        let policy = makePolicy(
            clock: clock,
            modalStore: modalStore,
            remoteMessageStore: remoteMessageStore
        )
        let reservation = try requireReservation(
            from: policy.reserveRemoteMessageAdmission(for: makeIdentity(promoID: "provisional"))
        )

        policy.resetTransientState()

        #expect(policy.snapshot.provisionalRemoteMessageIdentity == nil)
        #expect(policy.snapshot.lastConfirmedModalAppearance == lastModalAppearance)
        #expect(policy.snapshot.lastConfirmedRemoteMessageAppearance == lastRemoteMessageAppearance)
        #expect(modalStore.lastPresentationTimestamp == lastModalAppearance.timeIntervalSince1970)
        #expect(remoteMessageStore.storedTimestamp == lastRemoteMessageAppearance.timeIntervalSince1970)
        #expect(remoteMessageStore.writeCount == 0)
        #expect(!reservation.confirm())
        #expect(!reservation.release())
    }

    @Test("Iteration-one cooldown intervals are fixed compiled constants")
    func compiledCooldownConstantsMatchIterationOnePolicy() {
        #expect(PromoQueueCooldownPolicy.remoteMessageTargetInterval == 10 * 60)
        #expect(PromoQueueCooldownPolicy.modalAfterRemoteMessageInterval == 24 * 60 * 60)
    }

    private func makePolicy(
        clock: TimeTraveller,
        modalStore: InMemoryPromptCooldownStore = InMemoryPromptCooldownStore(),
        remoteMessageStore: RemoteMessageCooldownStoreSpy = RemoteMessageCooldownStoreSpy()
    ) -> PromoQueueCooldownPolicy {
        PromoQueueCooldownPolicy(
            modalPresentationStore: modalStore,
            remoteMessagePresentationStore: remoteMessageStore,
            dateProvider: clock.getDate
        )
    }

    private func makeIdentity(
        surfaceID: UUID = UUID(),
        promoID: String = "message-a"
    ) -> VisiblePromoIdentity {
        VisiblePromoIdentity(
            surfaceID: surfaceID,
            promoType: .remoteMessage,
            promoID: promoID
        )
    }

    private func requireReservation(
        from result: PromoQueueRemoteMessageCooldownReservationResult
    ) throws -> PromoQueueRemoteMessageCooldownReservation {
        guard case .reserved(let reservation) = result else {
            throw TestError.expectedReservation
        }
        return reservation
    }

    private func requireBlockedBoundary(
        from result: PromoQueueRemoteMessageCooldownReservationResult
    ) throws -> Date {
        guard case .blocked(let boundary) = result else {
            throw TestError.expectedBlockedBoundary
        }
        return boundary
    }
}

private enum TestError: Error {
    case expectedReservation
    case expectedBlockedBoundary
    case expectedProvisionalReservationInProgress
}

private final class RemoteMessageCooldownStoreSpy: PromoQueueRemoteMessageCooldownStoring {
    var storedTimestamp: TimeInterval?
    private(set) var writeCount = 0

    var lastConfirmedRemoteMessageTimestamp: TimeInterval? {
        get { storedTimestamp }
        set {
            writeCount += 1
            storedTimestamp = newValue
        }
    }
}
