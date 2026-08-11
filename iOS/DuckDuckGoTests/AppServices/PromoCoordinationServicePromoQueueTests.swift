//
//  PromoCoordinationServicePromoQueueTests.swift
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
import Testing
import UIKit
@testable import DuckDuckGo

@MainActor
@Suite("Promo Coordination - Service Promo Queue")
final class PromoCoordinationServicePromoQueueTests {
    private let launchSourceManagerMock = MockLaunchSourceManager()
    private let managerMock = MockModalPromptCoordinationManager()
    private let presenterMock = MockModalPromptPresenter()
    private let promoQueueLeaseArbiter = PromoQueueLeaseArbiter()
    private let promoQueueCooldownPolicy = MockPromoQueueCooldownPolicy()
    private let promoQueueCooldownDebugSnapshotProvider = MockPromoQueueCooldownDebugSnapshotProvider()
    private var currentDate = Date(timeIntervalSince1970: 1_800_000_000)
    private var sut: PromoCoordinationService!

    // MARK: - Debug Snapshot

    @available(iOS 16, *)
    @Test("The coordinated debug snapshot projects the service-owned logical RMF lifecycle", .timeLimit(.minutes(1)))
    func whenDebugSnapshotIsReadThenItProjectsTheLogicalRemoteMessageLifecycle() async {
        let lastModalAppearance = currentDate.addingTimeInterval(-900)
        let lastRemoteMessageAppearance = currentDate.addingTimeInterval(-300)
        let cooldownSnapshot = PromoQueueCooldownSnapshot(
            lastConfirmedModalAppearance: lastModalAppearance,
            lastConfirmedRemoteMessageAppearance: lastRemoteMessageAppearance,
            nextRemoteMessageEligibility: lastRemoteMessageAppearance.addingTimeInterval(600),
            nextModalEligibility: lastRemoteMessageAppearance.addingTimeInterval(86_400)
        )
        promoQueueCooldownDebugSnapshotProvider.snapshotToReturn = cooldownSnapshot
        managerMock.hasPendingModalPrompt = true
        managerMock.shouldSuppressOtherSessionPromos = true
        makeSUT()

        let rendererID = UUID()
        let fixture = registerRenderer(rendererID: rendererID, messageID: "debug-owner", shouldSelect: true)
        guard let presentation = fixture.renderer.shownPresentations.first else {
            Issue.record("Expected the service to publish its logical RMF owner")
            return
        }
        #expect(fixture.registration.confirmAppearance(
            sessionID: presentation.session.id,
            presentationID: presentation.id,
            isAttachedToWindow: true
        ) == .accepted)

        let remoteMessageAdmissionDates = promoQueueCooldownPolicy.remoteMessageAdmissionDates
        let modalAdmissionDates = promoQueueCooldownPolicy.modalAdmissionDates
        let confirmedRemoteMessageAppearanceDates = promoQueueCooldownPolicy.confirmedRemoteMessageAppearanceDates
        var snapshot = sut.promoQueueDebugSnapshot
        #expect(snapshot.mode == .coordinated)
        #expect(snapshot.activeOwner == .remoteMessage(presentation.session))
        #expect(snapshot.remoteMessageCoordination.state == .owned)
        #expect(snapshot.remoteMessageCoordination.messageID == presentation.session.messageID)
        #expect(snapshot.remoteMessageCoordination.sessionID == presentation.session.id)
        #expect(snapshot.remoteMessageCoordination.rendererID == rendererID)
        #expect(snapshot.remoteMessageCoordination.registrationGenerationID != nil)
        #expect(snapshot.remoteMessageCoordination.presentationID == presentation.id)
        #expect(snapshot.remoteMessageCoordination.isQueueAppearanceConfirmed)
        #expect(snapshot.remoteMessageCoordination.isPresentationAppearanceReported == true)
        #expect(snapshot.remoteMessageCoordination.removalID == nil)
        #expect(snapshot.remoteMessageCoordination.removalTerminal == nil)
        #expect(snapshot.remoteMessageCoordination.drainContinuation == nil)
        #expect(snapshot.remoteMessageCoordination.registeredRendererCount == 1)
        #expect(snapshot.remoteMessageCoordination.eligibleRendererCount == 1)
        #expect(snapshot.modalAttemptPhase == .idle)
        #expect(snapshot.hasPendingModalPrompt)
        #expect(snapshot.shouldSuppressOtherSessionPromos)
        #expect(snapshot.isApplicationActive)
        #expect(!snapshot.isWaitingForForegroundInteractionReadiness)
        #expect(snapshot.cooldown == cooldownSnapshot)
        #expect(promoQueueCooldownDebugSnapshotProvider.snapshotDates == [currentDate])
        #expect(promoQueueCooldownPolicy.snapshotDates.isEmpty)
        #expect(promoQueueCooldownPolicy.remoteMessageAdmissionDates == remoteMessageAdmissionDates)
        #expect(promoQueueCooldownPolicy.modalAdmissionDates == modalAdmissionDates)
        #expect(promoQueueCooldownPolicy.confirmedRemoteMessageAppearanceDates == confirmedRemoteMessageAppearanceDates)

        fixture.registration.update(candidate: .available(messageID: "debug-owner"), isLocallyReady: false)

        snapshot = sut.promoQueueDebugSnapshot
        #expect(snapshot.activeOwner == .remoteMessage(presentation.session))
        #expect(snapshot.remoteMessageCoordination.state == .draining)
        #expect(snapshot.remoteMessageCoordination.sessionID == presentation.session.id)
        #expect(snapshot.remoteMessageCoordination.presentationID == presentation.id)
        #expect(snapshot.remoteMessageCoordination.removalID != nil)
        #expect(snapshot.remoteMessageCoordination.removalTerminal == nil)
        #expect(snapshot.remoteMessageCoordination.drainContinuation == .transferSameMessageIfAvailable)
        #expect(snapshot.remoteMessageCoordination.eligibleRendererCount == 0)

        fixture.renderer.isRemoteMessageRendererAttachedToWindow = false
        fixture.renderer.finishLastRemoval(using: fixture.registration, terminal: .hostDetached)

        snapshot = sut.promoQueueDebugSnapshot
        #expect(snapshot.remoteMessageCoordination.state == .draining)
        #expect(snapshot.remoteMessageCoordination.removalTerminal == .hostDetached)
        #expect(snapshot.activeOwner == .remoteMessage(presentation.session))

        await waitForMainQueueSettlement()

        snapshot = sut.promoQueueDebugSnapshot
        #expect(snapshot.activeOwner == nil)
        #expect(snapshot.remoteMessageCoordination.state == .idle)
        #expect(snapshot.remoteMessageCoordination.registeredRendererCount == 1)
        #expect(snapshot.remoteMessageCoordination.eligibleRendererCount == 0)
        #expect(promoQueueCooldownDebugSnapshotProvider.snapshotDates == [
            currentDate,
            currentDate,
            currentDate,
            currentDate
        ])
        #expect(promoQueueCooldownPolicy.snapshotDates.isEmpty)
        #expect(promoQueueCooldownPolicy.remoteMessageAdmissionDates == remoteMessageAdmissionDates)
        #expect(promoQueueCooldownPolicy.modalAdmissionDates == modalAdmissionDates)
        #expect(promoQueueCooldownPolicy.confirmedRemoteMessageAppearanceDates == confirmedRemoteMessageAppearanceDates)
        fixture.registration.deregister()
    }

    @available(iOS 16, *)
    @Test("The legacy debug snapshot does not read Promo Queue history", .timeLimit(.minutes(1)))
    func whenLegacyDebugSnapshotIsReadThenCooldownHistoryRemainsUntouched() {
        promoQueueCooldownDebugSnapshotProvider.snapshotToReturn = PromoQueueCooldownSnapshot(
            lastConfirmedModalAppearance: currentDate,
            lastConfirmedRemoteMessageAppearance: currentDate,
            nextRemoteMessageEligibility: currentDate,
            nextModalEligibility: currentDate
        )
        managerMock.hasPendingModalPrompt = true
        managerMock.shouldSuppressOtherSessionPromos = true
        makeSUT(mode: .legacy, readyForInteractions: false)

        let snapshot = sut.promoQueueDebugSnapshot

        #expect(snapshot.mode == .legacy)
        #expect(snapshot.activeOwner == nil)
        #expect(snapshot.remoteMessageCoordination.state == .idle)
        #expect(snapshot.remoteMessageCoordination.registeredRendererCount == 0)
        #expect(snapshot.remoteMessageCoordination.eligibleRendererCount == 0)
        #expect(snapshot.modalAttemptPhase == .idle)
        #expect(snapshot.hasPendingModalPrompt)
        #expect(snapshot.shouldSuppressOtherSessionPromos)
        #expect(!snapshot.isApplicationActive)
        #expect(snapshot.isWaitingForForegroundInteractionReadiness)
        #expect(snapshot.cooldown == .empty)
        #expect(promoQueueCooldownDebugSnapshotProvider.snapshotDates.isEmpty)
        #expect(promoQueueCooldownPolicy.snapshotDates.isEmpty)
    }

    // MARK: - Modal Mutual Exclusion

    @available(iOS 16, *)
    @Test("Coordinated modal evaluation acquires the global owner before calling the manager", .timeLimit(.minutes(1)))
    func whenModalIsEvaluatedThenManagerReceivesAcquiredLease() {
        launchSourceManagerMock.source = .standard
        presenterMock.presentedViewController = nil
        var ownerDuringPolicyEvaluation: PromoQueueActiveOwnerSnapshot?
        promoQueueCooldownPolicy.onEvaluateModalAdmission = { [promoQueueLeaseArbiter] _ in
            ownerDuringPolicyEvaluation = promoQueueLeaseArbiter.snapshot.activeOwner
        }
        makeSUT()

        presentModalPromptIfNeeded()

        guard let lease = managerMock.capturedModalLease else {
            Issue.record("Expected the manager to retain the modal lease")
            return
        }
        #expect(ownerDuringPolicyEvaluation == .modal(lease.attemptIdentity))
        #expect(promoQueueCooldownPolicy.modalAdmissionDates == [currentDate])
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .modal(lease.attemptIdentity))
    }

    @available(iOS 16, *)
    @Test("A logical remote-message owner blocks modal evaluation", .timeLimit(.minutes(1)))
    func whenRemoteMessageOwnsGlobalSlotThenModalManagerIsNotCalled() {
        launchSourceManagerMock.source = .standard
        presenterMock.presentedViewController = nil
        makeSUT()
        let fixture = registerRenderer(messageID: "owner", shouldSelect: true)
        let presentation = fixture.renderer.shownPresentations.first
        managerMock.resetRecordedInteractions()

        presentModalPromptIfNeeded()

        #expect(presentation != nil)
        #expect(!managerMock.didCallPresentModalPromptIfNeeded)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == presentation.map { .remoteMessage($0.session) })
        _ = fixture.registration
    }

    @available(iOS 16, *)
    @Test("Legacy modal evaluation bypasses the arbiter", .timeLimit(.minutes(1)))
    func whenPromoQueueIsLegacyThenManagerUsesLeaseFreePath() {
        launchSourceManagerMock.source = .standard
        presenterMock.presentedViewController = nil
        makeSUT(mode: .legacy)

        presentModalPromptIfNeeded()

        #expect(managerMock.didCallPresentModalPromptIfNeeded)
        #expect(managerMock.capturedModalLease == nil)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == nil)
        #expect(promoQueueCooldownPolicy.modalAdmissionDates.isEmpty)
    }

    @available(iOS 16, *)
    @Test("Modal cooldown denial releases the lease and retries only at a later checkpoint", .timeLimit(.minutes(1)))
    func whenModalCooldownInitiallyBlocksThenASecondEvaluationCanAcquire() {
        launchSourceManagerMock.source = .standard
        presenterMock.presentedViewController = nil
        let initialDate = currentDate
        let eligibilityDate = initialDate.addingTimeInterval(60)
        promoQueueCooldownPolicy.modalAdmissionDecisionProvider = { now in
            now < eligibilityDate ? .blocked(until: eligibilityDate) : .eligible
        }
        makeSUT()

        presentModalPromptIfNeeded()

        #expect(!managerMock.didCallPresentModalPromptIfNeeded)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == nil)
        #expect(promoQueueCooldownPolicy.modalAdmissionDates == [currentDate])

        currentDate = eligibilityDate.addingTimeInterval(1)

        #expect(!managerMock.didCallPresentModalPromptIfNeeded)
        #expect(promoQueueCooldownPolicy.modalAdmissionDates.count == 1)

        presentModalPromptIfNeeded()

        #expect(managerMock.didCallPresentModalPromptIfNeeded)
        #expect(managerMock.capturedModalLease != nil)
        #expect(promoQueueCooldownPolicy.modalAdmissionDates == [initialDate, currentDate])
    }

    // MARK: - Selection And Acquisition

    @available(iOS 16, *)
    @Test("The service owns the logical lease before renderer publication", .timeLimit(.minutes(1)))
    func whenRendererIsAuthorizedThenLogicalLeaseAlreadyExists() {
        var ownerDuringPolicyEvaluation: PromoQueueActiveOwnerSnapshot?
        promoQueueCooldownPolicy.onEvaluateRemoteMessageAdmission = { [promoQueueLeaseArbiter] _ in
            ownerDuringPolicyEvaluation = promoQueueLeaseArbiter.snapshot.activeOwner
        }
        makeSUT()
        let renderer = ControllableRemoteMessageRenderer()
        var ownerObservedDuringShow: PromoQueueActiveOwnerSnapshot?
        renderer.onShow = { [promoQueueLeaseArbiter] _ in
            ownerObservedDuringShow = promoQueueLeaseArbiter.snapshot.activeOwner
        }
        let fixture = registerRenderer(renderer: renderer, messageID: "message", shouldSelect: true)

        guard let presentation = renderer.shownPresentations.first else {
            Issue.record("Expected the renderer to be authorized")
            return
        }
        #expect(ownerDuringPolicyEvaluation == .remoteMessage(presentation.session))
        #expect(promoQueueCooldownPolicy.remoteMessageAdmissionDates == [currentDate])
        #expect(ownerObservedDuringShow == .remoteMessage(presentation.session))
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .remoteMessage(presentation.session))
        _ = fixture.registration
    }

    @available(iOS 16, *)
    @Test("Locally ready renderers remain fail closed until one is explicitly selected", .timeLimit(.minutes(1)))
    func whenSelectionIsNilThenNoLocallyReadyRendererIsPublished() {
        makeSUT()
        let first = registerRenderer(messageID: "first", shouldSelect: false)
        let second = registerRenderer(messageID: "second", shouldSelect: false)

        #expect(first.renderer.shownPresentations.isEmpty)
        #expect(second.renderer.shownPresentations.isEmpty)
        #expect(sut.remoteMessageCoordinationSnapshot.selectedRemoteMessageRendererID == nil)
        #expect(sut.remoteMessageCoordinationSnapshot.eligibleRendererCount == 0)
        #expect(sut.remoteMessageCoordinationSnapshot.renderers.map(\.isLocallyReady) == [true, true])
        #expect(sut.remoteMessageCoordinationSnapshot.renderers.map(\.isEffectivelyEligible) == [false, false])
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == nil)
        _ = (first.registration, second.registration)
    }

    @available(iOS 16, *)
    @Test("An unknown selected renderer ID remains fail closed", .timeLimit(.minutes(1)))
    func whenSelectedRendererIDIsUnknownThenRegisteredRenderersRemainIneligible() {
        makeSUT()
        let fixture = registerRenderer(messageID: "message", shouldSelect: false)
        let unknownRendererID = UUID()

        sut.setSelectedRemoteMessageRendererID(unknownRendererID)

        #expect(fixture.renderer.shownPresentations.isEmpty)
        #expect(sut.remoteMessageCoordinationSnapshot.selectedRemoteMessageRendererID == unknownRendererID)
        #expect(sut.remoteMessageCoordinationSnapshot.eligibleRendererCount == 0)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == nil)

        let selectedFixture = registerRenderer(
            rendererID: unknownRendererID,
            messageID: "selected-message",
            shouldSelect: false)

        #expect(selectedFixture.renderer.shownPresentations.count == 1)
        #expect(sut.remoteMessageCoordinationSnapshot.rendererID == unknownRendererID)
        _ = (fixture.registration, selectedFixture.registration)
    }

    @available(iOS 16, *)
    @Test("Selecting one renderer authorizes only that renderer", .timeLimit(.minutes(1)))
    func whenRendererIsSelectedThenOnlyThatRendererPublishes() {
        makeSUT()
        let first = registerRenderer(messageID: "message", shouldSelect: false)
        let second = registerRenderer(messageID: "message", shouldSelect: false)

        sut.setSelectedRemoteMessageRendererID(second.rendererID)

        #expect(first.renderer.shownPresentations.isEmpty)
        #expect(second.renderer.shownPresentations.count == 1)
        #expect(sut.remoteMessageCoordinationSnapshot.rendererID == second.rendererID)
        #expect(sut.remoteMessageCoordinationSnapshot.eligibleRendererCount == 1)
        _ = (first.registration, second.registration)
    }

    @available(iOS 16, *)
    @Test("Repeated selected renderer updates are deduplicated", .timeLimit(.minutes(1)))
    func whenSelectedRendererIDIsRepeatedThenItDoesNotRepublish() {
        makeSUT()
        let fixture = registerRenderer(messageID: "message", shouldSelect: false)

        sut.setSelectedRemoteMessageRendererID(fixture.rendererID)
        let snapshotAfterSelection = sut.remoteMessageCoordinationSnapshot
        sut.setSelectedRemoteMessageRendererID(fixture.rendererID)

        #expect(fixture.renderer.shownPresentations.count == 1)
        #expect(fixture.renderer.hideRequests.isEmpty)
        #expect(sut.remoteMessageCoordinationSnapshot == snapshotAfterSelection)
        _ = fixture.registration
    }

    @available(iOS 16, *)
    @Test("A modal owner blocks all renderer publication", .timeLimit(.minutes(1)))
    func whenModalOwnsGlobalSlotThenRendererIsNotShown() throws {
        makeSUT()
        let modalLease = try acquiredModalLease()

        let fixture = registerRenderer(messageID: "message", shouldSelect: true)

        #expect(fixture.renderer.shownPresentations.isEmpty)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .modal(modalLease.attemptIdentity))
        #expect(promoQueueCooldownPolicy.remoteMessageAdmissionDates.isEmpty)
        _ = fixture.registration
    }

    @available(iOS 16, *)
    @Test("Remote-message cooldown denial retains the candidate for a later checkpoint", .timeLimit(.minutes(1)))
    func whenRemoteMessageCooldownInitiallyBlocksThenAReleaseCheckpointRetriesTheCandidate() {
        let initialDate = currentDate
        let eligibilityDate = initialDate.addingTimeInterval(10 * 60)
        promoQueueCooldownPolicy.remoteMessageAdmissionDecisionProvider = { now in
            now < eligibilityDate ? .blocked(until: eligibilityDate) : .eligible
        }
        makeSUT()

        let fixture = registerRenderer(messageID: "message", shouldSelect: true)

        #expect(fixture.renderer.shownPresentations.isEmpty)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == nil)
        #expect(promoQueueCooldownPolicy.remoteMessageAdmissionDates == [initialDate])

        currentDate = eligibilityDate.addingTimeInterval(1)

        #expect(fixture.renderer.shownPresentations.isEmpty)
        #expect(promoQueueCooldownPolicy.remoteMessageAdmissionDates == [initialDate])

        managerMock.coordinatedAttemptReleaseHandler?()

        #expect(fixture.renderer.shownPresentations.count == 1)
        #expect(promoQueueCooldownPolicy.remoteMessageAdmissionDates == [initialDate, currentDate])
        #expect(promoQueueLeaseArbiter.snapshot.remoteMessageSession == fixture.renderer.shownPresentations.first?.session)
        _ = fixture.registration
    }

    @available(iOS 16, *)
    @Test("Selection before interaction readiness authorizes exactly one renderer", .timeLimit(.minutes(1)))
    func whenSeveralRenderersAreWaitingThenOnlySelectedRendererIsAuthorizedAfterReadiness() {
        makeSUT(readyForInteractions: false)
        sut.applicationDidBecomeActive()
        let first = registerRenderer(messageID: "message", shouldSelect: true)
        let second = registerRenderer(messageID: "message", shouldSelect: false)

        makeReadyForInteractions()

        #expect(first.renderer.shownPresentations.count == 1)
        #expect(second.renderer.shownPresentations.isEmpty)
        #expect(promoQueueLeaseArbiter.snapshot.remoteMessageSession == first.renderer.shownPresentations.first?.session)
        _ = (first.registration, second.registration)
    }

    @available(iOS 16, *)
    @Test("A selected renderer rejection does not fall through to an unselected renderer", .timeLimit(.minutes(1)))
    func whenSelectedRendererRejectsThenUnselectedRendererIsNotAuthorized() {
        makeSUT(readyForInteractions: false)
        sut.applicationDidBecomeActive()
        let rejectingRenderer = ControllableRemoteMessageRenderer()
        rejectingRenderer.showResults = [false]
        let first = registerRenderer(renderer: rejectingRenderer, messageID: "message", shouldSelect: true)
        let second = registerRenderer(messageID: "message", shouldSelect: false)

        makeReadyForInteractions()

        #expect(first.renderer.shownPresentations.count == 1)
        #expect(second.renderer.shownPresentations.isEmpty)
        #expect(promoQueueCooldownPolicy.remoteMessageAdmissionDates.count == 1)
        #expect(promoQueueCooldownPolicy.confirmedRemoteMessageAppearanceDates.isEmpty)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == nil)
        _ = (first.registration, second.registration)
    }

    @available(iOS 16, *)
    @Test("All renderer rejections release without publishing", .timeLimit(.minutes(1)))
    func whenEveryMatchingRendererRejectsThenLogicalOwnerIsReleased() {
        makeSUT(readyForInteractions: false)
        sut.applicationDidBecomeActive()
        let firstRenderer = ControllableRemoteMessageRenderer()
        firstRenderer.showResults = [false]
        let secondRenderer = ControllableRemoteMessageRenderer()
        secondRenderer.showResults = [false]
        let first = registerRenderer(renderer: firstRenderer, messageID: "message", shouldSelect: false)
        let second = registerRenderer(renderer: secondRenderer, messageID: "message", shouldSelect: false)

        makeReadyForInteractions()
        sut.setSelectedRemoteMessageRendererID(first.rendererID)
        sut.setSelectedRemoteMessageRendererID(second.rendererID)

        #expect(firstRenderer.shownPresentations.count == 1)
        #expect(secondRenderer.shownPresentations.count == 1)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == nil)
        #expect(promoQueueCooldownPolicy.confirmedRemoteMessageAppearanceDates.isEmpty)
        _ = (first.registration, second.registration)
    }

    @available(iOS 16, *)
    @Test("An occupied renderer rejection fails closed", .timeLimit(.minutes(1)))
    func whenRejectingRendererReportsPublishedContentThenOwnerIsRetained() {
        makeSUT(readyForInteractions: false)
        sut.applicationDidBecomeActive()
        let occupiedRenderer = ControllableRemoteMessageRenderer()
        occupiedRenderer.showResults = [false]
        occupiedRenderer.hasPublishedRemoteMessagePresentation = true
        occupiedRenderer.retainsPublishedContentOnRejection = true
        let first = registerRenderer(renderer: occupiedRenderer, messageID: "message", shouldSelect: true)
        let second = registerRenderer(messageID: "message", shouldSelect: false)

        makeReadyForInteractions()

        #expect(first.renderer.shownPresentations.count == 1)
        #expect(first.renderer.hasPublishedRemoteMessagePresentation)
        #expect(second.renderer.shownPresentations.isEmpty)
        #expect(sut.remoteMessageCoordinationSnapshot.state == .owned)
        #expect(promoQueueLeaseArbiter.snapshot.remoteMessageSession == first.renderer.shownPresentations.first?.session)
        _ = (first.registration, second.registration)
    }

    // MARK: - Appearance

    @available(iOS 16, *)
    @Test("Appearance is accepted once per physical presentation and never releases ownership", .timeLimit(.minutes(1)))
    func whenCurrentPresentationAppearsThenOnlyItsFirstTruthfulAppearanceIsAccepted() {
        makeSUT()
        let fixture = registerRenderer(messageID: "message", shouldSelect: true)
        guard let presentation = fixture.renderer.shownPresentations.first else {
            Issue.record("Expected an authorized presentation")
            return
        }

        let firstResult = fixture.registration.confirmAppearance(
            sessionID: presentation.session.id,
            presentationID: presentation.id,
            isAttachedToWindow: true
        )
        let confirmationDate = currentDate
        currentDate = currentDate.addingTimeInterval(60)
        let duplicateResult = fixture.registration.confirmAppearance(
            sessionID: presentation.session.id,
            presentationID: presentation.id,
            isAttachedToWindow: true
        )

        #expect(firstResult == .accepted)
        #expect(duplicateResult == .rejected)
        #expect(promoQueueCooldownPolicy.confirmedRemoteMessageAppearanceDates == [confirmationDate])
        #expect(sut.remoteMessageCoordinationSnapshot.isQueueAppearanceConfirmed)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .remoteMessage(presentation.session))
        _ = fixture.registration
    }

    @available(iOS 16, *)
    @Test("Detached, stale, and draining appearances are rejected", .timeLimit(.minutes(1)))
    func whenAppearanceIsNotForTheCurrentVisiblePresentationThenItIsRejected() {
        makeSUT()
        let fixture = registerRenderer(messageID: "message", shouldSelect: true)
        guard let presentation = fixture.renderer.shownPresentations.first else {
            Issue.record("Expected an authorized presentation")
            return
        }

        #expect(fixture.registration.confirmAppearance(
            sessionID: presentation.session.id,
            presentationID: presentation.id,
            isAttachedToWindow: false
        ) == .rejected)
        #expect(fixture.registration.confirmAppearance(
            sessionID: UUID(),
            presentationID: presentation.id,
            isAttachedToWindow: true
        ) == .rejected)

        fixture.registration.update(candidate: .available(messageID: "message"), isLocallyReady: false)

        #expect(fixture.registration.confirmAppearance(
            sessionID: presentation.session.id,
            presentationID: presentation.id,
            isAttachedToWindow: true
        ) == .rejected)
        #expect(promoQueueCooldownPolicy.confirmedRemoteMessageAppearanceDates.isEmpty)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .remoteMessage(presentation.session))
        _ = fixture.registration
    }

    @available(iOS 16, *)
    @Test("Appearance after deselection is rejected while the exact owner drains", .timeLimit(.minutes(1)))
    func whenOwnedRendererIsDeselectedThenItsAppearanceIsRejected() {
        makeSUT()
        let fixture = registerRenderer(messageID: "message", shouldSelect: true)
        guard let presentation = fixture.renderer.shownPresentations.first else {
            Issue.record("Expected an authorized presentation")
            return
        }

        sut.setSelectedRemoteMessageRendererID(nil)

        #expect(sut.remoteMessageCoordinationSnapshot.state == .draining)
        #expect(fixture.renderer.hideRequests.count == 1)
        #expect(fixture.registration.confirmAppearance(
            sessionID: presentation.session.id,
            presentationID: presentation.id,
            isAttachedToWindow: true
        ) == .rejected)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .remoteMessage(presentation.session))
        _ = fixture.registration
    }

    // MARK: - Draining And Transfer

    @available(iOS 16, *)
    @Test("A same-message transfer retains one logical session until exact removal settles", .timeLimit(.minutes(1)))
    func whenSelectedRendererLosesEligibilityThenSuccessorWaitsForTerminal() async {
        makeSUT()
        let first = registerRenderer(messageID: "message", shouldSelect: true)
        let second = registerRenderer(messageID: "message", shouldSelect: false)
        guard let outgoingPresentation = first.renderer.shownPresentations.first else {
            Issue.record("Expected the first renderer to own the session")
            return
        }
        let firstConfirmationDate = currentDate
        #expect(first.registration.confirmAppearance(
            sessionID: outgoingPresentation.session.id,
            presentationID: outgoingPresentation.id,
            isAttachedToWindow: true
        ) == .accepted)

        sut.setSelectedRemoteMessageRendererID(second.rendererID)

        #expect(first.renderer.hideRequests.count == 1)
        #expect(second.renderer.shownPresentations.isEmpty)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .remoteMessage(outgoingPresentation.session))

        first.renderer.finishLastRemoval(using: first.registration)

        #expect(second.renderer.shownPresentations.isEmpty)
        await waitForMainQueueSettlement()

        #expect(second.renderer.shownPresentations.count == 1)
        #expect(second.renderer.shownPresentations.first?.session == outgoingPresentation.session)
        #expect(second.renderer.shownPresentations.first?.id != outgoingPresentation.id)
        guard let successorPresentation = second.renderer.shownPresentations.first else {
            Issue.record("Expected the successor presentation")
            return
        }
        currentDate = currentDate.addingTimeInterval(60)
        #expect(second.registration.confirmAppearance(
            sessionID: successorPresentation.session.id,
            presentationID: successorPresentation.id,
            isAttachedToWindow: true
        ) == .accepted)
        #expect(promoQueueCooldownPolicy.confirmedRemoteMessageAppearanceDates == [firstConfirmationDate])
        #expect(promoQueueCooldownPolicy.remoteMessageAdmissionDates.count == 1)
        #expect(sut.remoteMessageCoordinationSnapshot.isQueueAppearanceConfirmed)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .remoteMessage(outgoingPresentation.session))
        _ = (first.registration, second.registration)
    }

    @available(iOS 16, *)
    @Test("Rapid selection changes drain the owner and ultimately publish only the latest renderer", .timeLimit(.minutes(1)))
    func whenSelectionChangesRapidlyThenOnlyTheLatestSuccessorPublishes() async {
        makeSUT()
        let first = registerRenderer(messageID: "message", shouldSelect: true)
        let second = registerRenderer(messageID: "message", shouldSelect: false)
        let third = registerRenderer(messageID: "message", shouldSelect: false)
        guard let outgoingPresentation = first.renderer.shownPresentations.first else {
            Issue.record("Expected the first renderer to own the session")
            return
        }

        sut.setSelectedRemoteMessageRendererID(second.rendererID)
        sut.setSelectedRemoteMessageRendererID(third.rendererID)

        #expect(first.renderer.hideRequests.count == 1)
        #expect(second.renderer.shownPresentations.isEmpty)
        #expect(third.renderer.shownPresentations.isEmpty)

        first.renderer.finishLastRemoval(using: first.registration)
        await waitForMainQueueSettlement()

        #expect(second.renderer.shownPresentations.isEmpty)
        #expect(third.renderer.shownPresentations.count == 1)
        #expect(third.renderer.shownPresentations.first?.session == outgoingPresentation.session)
        #expect(sut.remoteMessageCoordinationSnapshot.rendererID == third.rendererID)
        _ = (first.registration, second.registration, third.registration)
    }

    @available(iOS 16, *)
    @Test("A transfer retries a rejecting successor under the same logical lease", .timeLimit(.minutes(1)))
    func whenFirstTransferSuccessorRejectsThenNextSuccessorKeepsTheSession() async {
        makeSUT()
        let outgoing = registerRenderer(messageID: "message", shouldSelect: true)
        let rejectingRenderer = ControllableRemoteMessageRenderer()
        rejectingRenderer.showResults = [false]
        let rejectingSuccessor = registerRenderer(renderer: rejectingRenderer, messageID: "message", shouldSelect: false)
        let acceptingSuccessor = registerRenderer(messageID: "message", shouldSelect: false)
        guard let outgoingPresentation = outgoing.renderer.shownPresentations.first else {
            Issue.record("Expected the outgoing renderer to own the session")
            return
        }

        rejectingRenderer.onShow = { [weak self] _ in
            self?.sut.setSelectedRemoteMessageRendererID(acceptingSuccessor.rendererID)
        }
        sut.setSelectedRemoteMessageRendererID(rejectingSuccessor.rendererID)
        outgoing.renderer.finishLastRemoval(using: outgoing.registration)
        await waitForMainQueueSettlement()

        #expect(rejectingRenderer.shownPresentations.count == 1)
        #expect(!rejectingRenderer.hasPublishedRemoteMessagePresentation)
        #expect(acceptingSuccessor.renderer.shownPresentations.count == 1)
        #expect(rejectingRenderer.shownPresentations.first?.session == outgoingPresentation.session)
        #expect(acceptingSuccessor.renderer.shownPresentations.first?.session == outgoingPresentation.session)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .remoteMessage(outgoingPresentation.session))
        _ = (outgoing.registration, rejectingSuccessor.registration, acceptingSuccessor.registration)
    }

    @available(iOS 16, *)
    @Test("A successor registered after terminal settlement starts a fresh session", .timeLimit(.minutes(1)))
    func whenMatchingSuccessorRegistersAfterReleaseThenItGetsFreshSession() async {
        makeSUT()
        let outgoing = registerRenderer(messageID: "message", shouldSelect: true)
        guard let outgoingPresentation = outgoing.renderer.shownPresentations.first else {
            Issue.record("Expected the outgoing renderer to own the session")
            return
        }
        let outgoingConfirmationDate = currentDate
        #expect(outgoing.registration.confirmAppearance(
            sessionID: outgoingPresentation.session.id,
            presentationID: outgoingPresentation.id,
            isAttachedToWindow: true
        ) == .accepted)

        outgoing.registration.update(candidate: .available(messageID: "message"), isLocallyReady: false)
        outgoing.renderer.finishLastRemoval(using: outgoing.registration)
        await waitForMainQueueSettlement()

        #expect(sut.remoteMessageCoordinationSnapshot.state == .idle)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == nil)

        let successor = registerRenderer(messageID: "message", shouldSelect: true)
        guard let successorPresentation = successor.renderer.shownPresentations.first else {
            Issue.record("Expected the late successor to acquire a session")
            return
        }

        #expect(successorPresentation.session.messageID == outgoingPresentation.session.messageID)
        #expect(successorPresentation.session.id != outgoingPresentation.session.id)
        currentDate = currentDate.addingTimeInterval(60)
        #expect(successor.registration.confirmAppearance(
            sessionID: successorPresentation.session.id,
            presentationID: successorPresentation.id,
            isAttachedToWindow: true
        ) == .accepted)
        #expect(promoQueueCooldownPolicy.confirmedRemoteMessageAppearanceDates == [outgoingConfirmationDate, currentDate])
        #expect(promoQueueCooldownPolicy.remoteMessageAdmissionDates.count == 2)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .remoteMessage(successorPresentation.session))
        _ = (outgoing.registration, successor.registration)
    }

    @available(iOS 16, *)
    @Test("An exact old terminal callback is inert after a fresh same-message session acquires", .timeLimit(.minutes(1)))
    func whenOldExactTerminalReplaysAfterFreshSessionThenNewOwnerIsUnchanged() async {
        makeSUT()
        let outgoing = registerRenderer(messageID: "message", shouldSelect: true)
        guard let outgoingPresentation = outgoing.renderer.shownPresentations.first else {
            Issue.record("Expected the outgoing renderer to own the session")
            return
        }

        outgoing.registration.update(candidate: .none, isLocallyReady: false)
        guard let oldHideRequest = outgoing.renderer.hideRequests.last else {
            Issue.record("Expected a pending old hide request")
            return
        }
        outgoing.renderer.finishLastRemoval(using: outgoing.registration)
        await waitForMainQueueSettlement()

        let successor = registerRenderer(messageID: "message", shouldSelect: true)
        guard let successorPresentation = successor.renderer.shownPresentations.first else {
            Issue.record("Expected a fresh same-message session")
            return
        }
        #expect(successorPresentation.session.id != outgoingPresentation.session.id)

        outgoing.registration.removalDidReachTerminal(
            sessionID: outgoingPresentation.session.id,
            presentationID: outgoingPresentation.id,
            removalID: oldHideRequest.removalID,
            terminal: .animationCompleted
        )
        await waitForMainQueueSettlement()

        #expect(sut.remoteMessageCoordinationSnapshot.state == .owned)
        #expect(sut.remoteMessageCoordinationSnapshot.sessionID == successorPresentation.session.id)
        #expect(sut.remoteMessageCoordinationSnapshot.presentationID == successorPresentation.id)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .remoteMessage(successorPresentation.session))
        _ = (outgoing.registration, successor.registration)
    }

    @available(iOS 16, *)
    @Test("Different-message replacement starts a fresh logical session", .timeLimit(.minutes(1)))
    func whenWaitingRendererHasDifferentMessageThenItAcquiresAfterOldSessionEnds() async {
        makeSUT()
        let first = registerRenderer(messageID: "first", shouldSelect: true)
        let second = registerRenderer(messageID: "second", shouldSelect: false)
        guard let firstPresentation = first.renderer.shownPresentations.first else {
            Issue.record("Expected the first renderer to own the session")
            return
        }

        sut.setSelectedRemoteMessageRendererID(second.rendererID)
        first.renderer.finishLastRemoval(using: first.registration)
        await waitForMainQueueSettlement()

        guard let secondPresentation = second.renderer.shownPresentations.first else {
            Issue.record("Expected the different message to acquire after release")
            return
        }
        #expect(secondPresentation.session.messageID == "second")
        #expect(secondPresentation.session.id != firstPresentation.session.id)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .remoteMessage(secondPresentation.session))
        _ = (first.registration, second.registration)
    }

    @available(iOS 16, *)
    @Test("Candidate invalidation ends the old session instead of resurrecting it", .timeLimit(.minutes(1)))
    func whenSelectedCandidateBecomesNilThenSameIDWaiterGetsFreshSession() async {
        makeSUT()
        let first = registerRenderer(messageID: "message", shouldSelect: true)
        let second = registerRenderer(messageID: "message", shouldSelect: false)
        guard let oldPresentation = first.renderer.shownPresentations.first else {
            Issue.record("Expected the first renderer to own the session")
            return
        }

        first.registration.update(candidate: .none, isLocallyReady: false)
        sut.setSelectedRemoteMessageRendererID(second.rendererID)
        first.renderer.finishLastRemoval(using: first.registration)
        await waitForMainQueueSettlement()

        guard let replacementPresentation = second.renderer.shownPresentations.first else {
            Issue.record("Expected the waiting candidate to make a fresh admission")
            return
        }
        #expect(replacementPresentation.session.messageID == oldPresentation.session.messageID)
        #expect(replacementPresentation.session.id != oldPresentation.session.id)
        _ = (first.registration, second.registration)
    }

    @available(iOS 16, *)
    @Test("The outgoing renderer may be selected again only after terminal settlement", .timeLimit(.minutes(1)))
    func whenOutgoingRendererBecomesEligibleDuringDrainThenItIsReconsideredAfterTerminal() async {
        makeSUT()
        let fixture = registerRenderer(messageID: "message", shouldSelect: true)
        guard let firstPresentation = fixture.renderer.shownPresentations.first else {
            Issue.record("Expected an authorized presentation")
            return
        }

        fixture.registration.update(candidate: .available(messageID: "message"), isLocallyReady: false)
        fixture.registration.update(candidate: .available(messageID: "message"), isLocallyReady: true)

        #expect(fixture.renderer.shownPresentations.count == 1)
        fixture.renderer.finishLastRemoval(using: fixture.registration)
        await waitForMainQueueSettlement()

        #expect(fixture.renderer.shownPresentations.count == 2)
        #expect(fixture.renderer.shownPresentations.last?.session == firstPresentation.session)
        #expect(fixture.renderer.shownPresentations.last?.id != firstPresentation.id)
        _ = fixture.registration
    }

    @available(iOS 16, *)
    @Test("Missing removal terminal fails closed", .timeLimit(.minutes(1)))
    func whenOutgoingRendererNeverReportsTerminalThenItKeepsBlockingAllPromos() {
        launchSourceManagerMock.source = .standard
        presenterMock.presentedViewController = nil
        makeSUT()
        let first = registerRenderer(messageID: "first", shouldSelect: true)
        let second = registerRenderer(messageID: "second", shouldSelect: false)
        guard let presentation = first.renderer.shownPresentations.first else {
            Issue.record("Expected the first renderer to own the session")
            return
        }

        first.registration.update(candidate: .available(messageID: "first"), isLocallyReady: false)
        managerMock.resetRecordedInteractions()
        presentModalPromptIfNeeded()

        #expect(first.renderer.hideRequests.count == 1)
        #expect(second.renderer.shownPresentations.isEmpty)
        #expect(!managerMock.didCallPresentModalPromptIfNeeded)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .remoteMessage(presentation.session))
        _ = (first.registration, second.registration)
    }

    @available(iOS 16, *)
    @Test("Duplicate and stale removal callbacks are inert", .timeLimit(.minutes(1)))
    func whenRemovalCallbackDoesNotMatchThenItCannotReleaseTheSession() async {
        makeSUT()
        let fixture = registerRenderer(messageID: "message", shouldSelect: true)
        guard let presentation = fixture.renderer.shownPresentations.first else {
            Issue.record("Expected an authorized presentation")
            return
        }
        fixture.registration.update(candidate: .none, isLocallyReady: false)
        guard let hideRequest = fixture.renderer.hideRequests.last else {
            Issue.record("Expected a hide request")
            return
        }

        fixture.registration.removalDidReachTerminal(
            sessionID: presentation.session.id,
            presentationID: presentation.id,
            removalID: UUID(),
            terminal: .animationCompleted
        )
        await waitForMainQueueSettlement()
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .remoteMessage(presentation.session))

        fixture.registration.removalDidReachTerminal(
            sessionID: presentation.session.id,
            presentationID: presentation.id,
            removalID: hideRequest.removalID,
            terminal: .animationCompleted
        )
        fixture.registration.removalDidReachTerminal(
            sessionID: presentation.session.id,
            presentationID: presentation.id,
            removalID: hideRequest.removalID,
            terminal: .animationCompleted
        )
        await waitForMainQueueSettlement()

        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == nil)
        _ = fixture.registration
    }

    @available(iOS 16, *)
    @Test("Hiding before accepted appearance never confirms the queue session", .timeLimit(.minutes(1)))
    func whenPresentationDrainsBeforeAppearanceThenQueueConfirmationStaysFalse() async {
        makeSUT()
        let fixture = registerRenderer(messageID: "message", shouldSelect: true)
        guard let presentation = fixture.renderer.shownPresentations.first else {
            Issue.record("Expected an authorized presentation")
            return
        }

        #expect(!sut.remoteMessageCoordinationSnapshot.isQueueAppearanceConfirmed)
        fixture.registration.update(candidate: .none, isLocallyReady: false)

        #expect(sut.remoteMessageCoordinationSnapshot.state == .draining)
        #expect(!sut.remoteMessageCoordinationSnapshot.isQueueAppearanceConfirmed)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .remoteMessage(presentation.session))

        fixture.renderer.finishLastRemoval(using: fixture.registration)
        #expect(!sut.remoteMessageCoordinationSnapshot.isQueueAppearanceConfirmed)
        await waitForMainQueueSettlement()

        #expect(sut.remoteMessageCoordinationSnapshot.state == .idle)
        #expect(!sut.remoteMessageCoordinationSnapshot.isQueueAppearanceConfirmed)
        #expect(promoQueueCooldownPolicy.confirmedRemoteMessageAppearanceDates.isEmpty)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == nil)
        _ = fixture.registration
    }

    @available(iOS 16, *)
    @Test("Host detachment is accepted only after exact renderer verification", .timeLimit(.minutes(1)))
    func whenHostDetachedTerminalIsReportedThenAttachmentIsRevalidated() async {
        makeSUT()
        let fixture = registerRenderer(messageID: "message", shouldSelect: true)
        guard let presentation = fixture.renderer.shownPresentations.first else {
            Issue.record("Expected an authorized presentation")
            return
        }
        fixture.registration.update(candidate: .none, isLocallyReady: false)

        fixture.renderer.finishLastRemoval(using: fixture.registration, terminal: .hostDetached)
        await waitForMainQueueSettlement()
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .remoteMessage(presentation.session))

        fixture.renderer.isRemoteMessageRendererAttachedToWindow = false
        fixture.renderer.finishLastRemoval(using: fixture.registration, terminal: .hostDetached)
        await waitForMainQueueSettlement()
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == nil)
        _ = fixture.registration
    }

    @available(iOS 16, *)
    @Test("A late animation completion is inert after verified host detachment", .timeLimit(.minutes(1)))
    func whenHostDetachmentSettlesThenLateAnimationCannotAffectTheNextOwner() async {
        makeSUT()
        let outgoing = registerRenderer(messageID: "first", shouldSelect: true)
        let successor = registerRenderer(messageID: "second", shouldSelect: false)
        guard let outgoingPresentation = outgoing.renderer.shownPresentations.first else {
            Issue.record("Expected the outgoing renderer to own the session")
            return
        }

        outgoing.registration.update(candidate: .none, isLocallyReady: false)
        sut.setSelectedRemoteMessageRendererID(successor.rendererID)
        guard let hideRequest = outgoing.renderer.hideRequests.last else {
            Issue.record("Expected a pending hide request")
            return
        }
        outgoing.renderer.isRemoteMessageRendererAttachedToWindow = false
        outgoing.renderer.finishLastRemoval(using: outgoing.registration, terminal: .hostDetached)
        await waitForMainQueueSettlement()

        guard let successorPresentation = successor.renderer.shownPresentations.first else {
            Issue.record("Expected the successor to acquire after verified detachment")
            return
        }
        outgoing.registration.removalDidReachTerminal(
            sessionID: outgoingPresentation.session.id,
            presentationID: outgoingPresentation.id,
            removalID: hideRequest.removalID,
            terminal: .animationCompleted
        )
        await waitForMainQueueSettlement()

        #expect(successorPresentation.session.id != outgoingPresentation.session.id)
        #expect(sut.remoteMessageCoordinationSnapshot.state == .owned)
        #expect(sut.remoteMessageCoordinationSnapshot.sessionID == successorPresentation.session.id)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .remoteMessage(successorPresentation.session))
        _ = (outgoing.registration, successor.registration)
    }

    @available(iOS 16, *)
    @Test("A synchronous removal terminal is coalesced and still waits one main turn", .timeLimit(.minutes(1)))
    func whenHideReportsTerminalSynchronouslyThenSuccessorIsNotPublishedReentrantly() async {
        makeSUT()
        let firstRenderer = ControllableRemoteMessageRenderer()
        let first = registerRenderer(renderer: firstRenderer, messageID: "message", shouldSelect: true)
        let second = registerRenderer(messageID: "message", shouldSelect: false)
        firstRenderer.onHide = { [weak firstRenderer] presentation, removalID in
            firstRenderer?.registration?.removalDidReachTerminal(
                sessionID: presentation.session.id,
                presentationID: presentation.id,
                removalID: removalID,
                terminal: .sourceRemovedWithoutAnimation
            )
        }

        sut.setSelectedRemoteMessageRendererID(second.rendererID)

        #expect(second.renderer.shownPresentations.isEmpty)
        await waitForMainQueueSettlement()
        #expect(second.renderer.shownPresentations.count == 1)
        _ = (first.registration, second.registration)
    }

    // MARK: - Registration And Lifecycle

    @available(iOS 16, *)
    @Test("A non-selected renderer cannot affect the selected session", .timeLimit(.minutes(1)))
    func whenNonSelectedRendererUpdatesOrDeregistersThenOwnerIsUnchanged() {
        makeSUT()
        let selected = registerRenderer(messageID: "message", shouldSelect: true)
        let waiting = registerRenderer(messageID: "message", shouldSelect: false)
        let selectedPresentation = selected.renderer.shownPresentations.first

        waiting.registration.update(candidate: .none, isLocallyReady: false)
        waiting.registration.deregister()

        #expect(selected.renderer.hideRequests.isEmpty)
        #expect(promoQueueLeaseArbiter.snapshot.remoteMessageSession == selectedPresentation?.session)
        _ = selected.registration
    }

    @available(iOS 16, *)
    @Test("A stale registration generation cannot remove its replacement", .timeLimit(.minutes(1)))
    func whenRendererIDIsRegisteredAgainThenOldGenerationUpdatesAreIgnored() {
        makeSUT(readyForInteractions: false)
        sut.applicationDidBecomeActive()
        let rendererID = UUID()
        let stale = registerRenderer(rendererID: rendererID, messageID: "stale", shouldSelect: false)
        let replacement = registerRenderer(rendererID: rendererID, messageID: "replacement", shouldSelect: false)

        stale.registration.update(candidate: .available(messageID: "stale-again"), isLocallyReady: true)
        sut.setSelectedRemoteMessageRendererID(rendererID)
        makeReadyForInteractions()

        #expect(stale.renderer.shownPresentations.isEmpty)
        #expect(replacement.renderer.shownPresentations.first?.session.messageID == "replacement")
        _ = (stale.registration, replacement.registration)
    }

    @available(iOS 16, *)
    @Test("A selected old generation retains its terminal capability after re-registration", .timeLimit(.minutes(1)))
    func whenSelectedRendererIDIsRegisteredAgainThenOldGenerationCanFinishTransfer() async {
        makeSUT()
        let rendererID = UUID()
        let selected = registerRenderer(rendererID: rendererID, messageID: "message", shouldSelect: true)
        let originalSession = selected.renderer.shownPresentations.first?.session

        let replacement = registerRenderer(rendererID: rendererID, messageID: "message", shouldSelect: false)

        #expect(selected.renderer.hideRequests.count == 1)
        #expect(replacement.renderer.shownPresentations.isEmpty)
        selected.renderer.finishLastRemoval(using: selected.registration)
        await waitForMainQueueSettlement()

        #expect(replacement.renderer.shownPresentations.first?.session == originalSession)
        #expect(sut.remoteMessageCoordinationSnapshot.state == .owned)
        _ = replacement.registration
    }

    @available(iOS 16, *)
    @Test("Unexpected selected target loss fails closed", .timeLimit(.minutes(1)))
    func whenSelectedWeakTargetDisappearsThenLogicalOwnerRemainsBlocked() {
        makeSUT()
        var renderer: ControllableRemoteMessageRenderer? = ControllableRemoteMessageRenderer()
        weak var weakRenderer = renderer
        let rendererID = UUID()
        guard let registration = renderer.map({ target in
            sut.registerRemoteMessageRenderer(id: rendererID, target: target)
        }) else {
            Issue.record("Expected renderer construction to succeed")
            return
        }
        renderer?.registration = registration
        registration.update(candidate: .available(messageID: "message"), isLocallyReady: true)
        sut.setSelectedRemoteMessageRendererID(rendererID)
        let session = promoQueueLeaseArbiter.snapshot.remoteMessageSession

        renderer = nil
        registration.update(candidate: .none, isLocallyReady: false)

        #expect(weakRenderer == nil)
        #expect(sut.remoteMessageCoordinationSnapshot.state == .owned)
        #expect(sut.remoteMessageCoordinationSnapshot.registeredRendererCount == 1)
        #expect(promoQueueLeaseArbiter.snapshot.remoteMessageSession == session)
        guard case .blockedByRemoteMessage(let blockedSession) = promoQueueLeaseArbiter.acquireModalLease() else {
            Issue.record("Expected the unexpectedly lost renderer to retain the logical owner")
            return
        }
        #expect(blockedSession == session)
        _ = registration
    }

    @available(iOS 16, *)
    @Test("Selected renderer deregistration retains ownership until exact terminal", .timeLimit(.minutes(1)))
    func whenSelectedRendererDeregistersThenLeaseRemainsUntilRemovalSettles() async {
        makeSUT()
        let fixture = registerRenderer(messageID: "message", shouldSelect: true)
        let presentation = fixture.renderer.shownPresentations.first

        fixture.registration.deregister()

        #expect(fixture.renderer.hideRequests.count == 1)
        #expect(sut.remoteMessageCoordinationSnapshot.selectedRemoteMessageRendererID == fixture.rendererID)
        #expect(sut.remoteMessageCoordinationSnapshot.eligibleRendererCount == 0)
        #expect(promoQueueLeaseArbiter.snapshot.remoteMessageSession == presentation?.session)
        fixture.renderer.finishLastRemoval(using: fixture.registration)
        await waitForMainQueueSettlement()
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == nil)
    }

    @available(iOS 16, *)
    @Test("Background alone retains an existing logical owner", .timeLimit(.minutes(1)))
    func whenApplicationBackgroundsThenOwnedRendererIsNotDrained() {
        makeSUT()
        let fixture = registerRenderer(messageID: "message", shouldSelect: true)
        let presentation = fixture.renderer.shownPresentations.first

        sut.applicationWillResignActive()
        sut.applicationDidEnterBackground()
        sut.applicationDidBecomeActive()

        #expect(fixture.renderer.hideRequests.isEmpty)
        #expect(promoQueueLeaseArbiter.snapshot.remoteMessageSession == presentation?.session)
        #expect(managerMock.applicationWillResignActiveCallCount == 1)
        #expect(managerMock.applicationDidEnterBackgroundCallCount == 1)
        #expect(managerMock.applicationDidBecomeActiveCallCount == 1)
        _ = fixture.registration
    }

    @available(iOS 16, *)
    @Test("Renderer ineligibility still drains an owner while the app is backgrounded", .timeLimit(.minutes(1)))
    func whenRendererBecomesIneligibleInBackgroundThenItsOwnerDrainsNormally() async {
        makeSUT()
        let fixture = registerRenderer(messageID: "message", shouldSelect: true)
        let presentation = fixture.renderer.shownPresentations.first

        sut.applicationWillResignActive()
        sut.applicationDidEnterBackground()

        #expect(fixture.renderer.hideRequests.isEmpty)
        #expect(promoQueueLeaseArbiter.snapshot.remoteMessageSession == presentation?.session)

        fixture.registration.update(candidate: .available(messageID: "message"), isLocallyReady: false)

        #expect(fixture.renderer.hideRequests.count == 1)
        #expect(sut.remoteMessageCoordinationSnapshot.state == .draining)
        #expect(promoQueueLeaseArbiter.snapshot.remoteMessageSession == presentation?.session)

        fixture.renderer.finishLastRemoval(using: fixture.registration)
        await waitForMainQueueSettlement()

        #expect(sut.remoteMessageCoordinationSnapshot.state == .idle)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == nil)
        _ = fixture.registration
    }

    @available(iOS 16, *)
    @Test("Cold start waits for full foreground interaction readiness", .timeLimit(.minutes(1)))
    func whenColdStartIsOnlyActiveThenRendererWaitsForReadinessCheckpoint() {
        makeSUT(readyForInteractions: false)
        sut.applicationDidBecomeActive()
        let fixture = registerRenderer(messageID: "message", shouldSelect: true)

        #expect(fixture.renderer.shownPresentations.isEmpty)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == nil)

        makeReadyForInteractions()

        #expect(fixture.renderer.shownPresentations.count == 1)
        _ = fixture.registration
    }

    @available(iOS 16, *)
    @Test("Modal release is a renderer reconciliation checkpoint", .timeLimit(.minutes(1)))
    func whenModalOwnerReleasesThenWaitingRendererIsReconciled() throws {
        makeSUT()
        let modalLease = try acquiredModalLease()
        let fixture = registerRenderer(messageID: "message", shouldSelect: true)
        #expect(fixture.renderer.shownPresentations.isEmpty)

        modalLease.release()
        managerMock.coordinatedAttemptReleaseHandler?()

        #expect(fixture.renderer.shownPresentations.count == 1)
        _ = fixture.registration
    }

    @available(iOS 16, *)
    @Test("Legacy service registration is inert", .timeLimit(.minutes(1)))
    func whenLegacyServiceIsAskedToRegisterThenItDoesNotArbitrateOrRender() {
        makeSUT(mode: .legacy)
        let fixture = registerRenderer(messageID: "message", shouldSelect: true)

        sut.setSelectedRemoteMessageRendererID(fixture.rendererID)

        #expect(fixture.renderer.shownPresentations.isEmpty)
        #expect(sut.remoteMessageCoordinationSnapshot.selectedRemoteMessageRendererID == nil)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == nil)
        #expect(promoQueueCooldownPolicy.remoteMessageAdmissionDates.isEmpty)
        #expect(promoQueueCooldownPolicy.confirmedRemoteMessageAppearanceDates.isEmpty)
        _ = fixture.registration
    }

    // MARK: - Helpers

    private func makeSUT(mode: PromoCoordinationMode = .coordinated, readyForInteractions: Bool = true) {
        sut = PromoCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            promoCoordinationMode: mode,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            promoQueueCooldownPolicy: promoQueueCooldownPolicy,
            promoQueueCooldownDebugSnapshotProvider: promoQueueCooldownDebugSnapshotProvider,
            dateProvider: { [unowned self] in currentDate }
        )

        guard mode == .coordinated, readyForInteractions else {
            return
        }

        makeReadyForInteractions()
        managerMock.resetRecordedInteractions()
    }

    private func makeReadyForInteractions() {
        let launchSource = launchSourceManagerMock.source
        launchSourceManagerMock.source = .URL
        sut.applicationDidBecomeActive()
        presentModalPromptIfNeeded()
        launchSourceManagerMock.source = launchSource
    }

    private func presentModalPromptIfNeeded() {
        sut.presentModalPromptIfNeeded(
            from: presenterMock,
            readinessToken: sut.captureForegroundReadinessToken()
        )
    }

    private func registerRenderer(
        rendererID: UUID = UUID(),
        renderer: ControllableRemoteMessageRenderer? = nil,
        messageID: String,
        isLocallyReady: Bool = true,
        shouldSelect: Bool
    ) -> RendererFixture {
        let renderer = renderer ?? ControllableRemoteMessageRenderer()
        let registration = sut.registerRemoteMessageRenderer(id: rendererID, target: renderer)
        renderer.registration = registration
        registration.update(candidate: .available(messageID: messageID), isLocallyReady: isLocallyReady)
        if shouldSelect {
            sut.setSelectedRemoteMessageRendererID(rendererID)
        }
        return RendererFixture(rendererID: rendererID, renderer: renderer, registration: registration)
    }

    private func acquiredModalLease() throws -> PromoQueueModalLease {
        guard case .acquired(let lease) = promoQueueLeaseArbiter.acquireModalLease() else {
            throw TestError.expectedModalLease
        }
        return lease
    }

    private func waitForMainQueueSettlement() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}

@MainActor
private struct RendererFixture {
    let rendererID: UUID
    let renderer: ControllableRemoteMessageRenderer
    let registration: NewTabPagePromoRendererRegistration
}

@MainActor
private final class MockPromoQueueCooldownDebugSnapshotProvider: PromoQueueCooldownDebugSnapshotProviding {
    var snapshotToReturn: PromoQueueCooldownSnapshot = .empty
    private(set) var snapshotDates = [Date]()

    func snapshot(now: Date) -> PromoQueueCooldownSnapshot {
        snapshotDates.append(now)
        return snapshotToReturn
    }
}

@MainActor
private final class ControllableRemoteMessageRenderer: NewTabPagePromoRendering {
    struct HideRequest {
        let presentation: PromoQueueRemoteMessagePresentation
        let removalID: UUID
    }

    var isRemoteMessageRendererAttachedToWindow = true
    var hasPublishedRemoteMessagePresentation = false
    var retainsPublishedContentOnRejection = false
    var showResults = [Bool]()
    var onShow: ((PromoQueueRemoteMessagePresentation) -> Void)?
    var onHide: ((PromoQueueRemoteMessagePresentation, UUID) -> Void)?
    var registration: NewTabPagePromoRendererRegistration?
    private(set) var shownPresentations = [PromoQueueRemoteMessagePresentation]()
    private(set) var hideRequests = [HideRequest]()

    func showRemoteMessage(_ presentation: PromoQueueRemoteMessagePresentation) -> Bool {
        shownPresentations.append(presentation)
        onShow?(presentation)
        let result = showResults.isEmpty ? true : showResults.removeFirst()
        if result || !retainsPublishedContentOnRejection {
            hasPublishedRemoteMessagePresentation = result
        }
        return result
    }

    func hideRemoteMessage(
        _ presentation: PromoQueueRemoteMessagePresentation,
        removalID: UUID
    ) {
        hideRequests.append(HideRequest(presentation: presentation, removalID: removalID))
        onHide?(presentation, removalID)
    }

    func finishLastRemoval(
        using registration: NewTabPagePromoRendererRegistration,
        terminal: PromoQueueRemoteMessageRemovalTerminal = .animationCompleted
    ) {
        guard let request = hideRequests.last else {
            Issue.record("Expected a pending hide request")
            return
        }
        hasPublishedRemoteMessagePresentation = false
        registration.removalDidReachTerminal(
            sessionID: request.presentation.session.id,
            presentationID: request.presentation.id,
            removalID: request.removalID,
            terminal: terminal
        )
    }
}

private enum TestError: Error {
    case expectedModalLease
}
