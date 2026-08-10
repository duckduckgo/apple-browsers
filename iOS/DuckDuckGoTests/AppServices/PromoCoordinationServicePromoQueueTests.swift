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

import Core
import Foundation
import PersistenceTestingUtils
import PrivacyConfig
import Testing
import UIKit
@testable import DuckDuckGo

@MainActor
@Suite("Promo Coordination - Service Promo Queue")
final class PromoCoordinationServicePromoQueueTests {
    private let launchSourceManagerMock: MockLaunchSourceManager
    private let contextualOnboardingMock: MockContextualOnboardingStatusProvider
    private let managerMock: MockModalPromptCoordinationManager
    private let presenterMock: MockModalPromptPresenter
    private let promoQueueLeaseArbiter: PromoQueueLeaseArbiter
    private var sut: PromoCoordinationService!

    init() {
        launchSourceManagerMock = MockLaunchSourceManager()
        contextualOnboardingMock = MockContextualOnboardingStatusProvider(hasSeenOnboarding: true)
        managerMock = MockModalPromptCoordinationManager()
        presenterMock = MockModalPromptPresenter()
        promoQueueLeaseArbiter = PromoQueueLeaseArbiter()
    }

    // MARK: - Modal Admission

    @available(iOS 16, *)
    @Test("Coordinated Modal Evaluation Acquires The Global Owner Before Calling Manager", .timeLimit(.minutes(1)))
    func whenPromoQueueIsCoordinatedThenManagerReceivesAcquiredLease() {
        launchSourceManagerMock.source = .standard
        presenterMock.presentedViewController = nil
        makeSUT()

        sut.presentModalPromptIfNeeded(from: presenterMock)

        #expect(managerMock.capturedModalLease != nil)
        guard let attemptIdentity = managerMock.capturedModalLease?.attemptIdentity else {
            Issue.record("Expected the manager to retain the modal lease")
            return
        }
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .modal(attemptIdentity))
    }

    @available(iOS 16, *)
    @Test("Visible Global Owner Blocks Modal Manager And Provider Evaluation", .timeLimit(.minutes(1)))
    func whenVisiblePromoOwnsGlobalSlotThenModalProvidersAreNotQueried() throws {
        launchSourceManagerMock.source = .standard
        presenterMock.presentedViewController = nil
        let provider = MockModalPromptProvider()
        let identity = makeIdentity(promoID: "owner")
        guard case .acquired(let visibleLease) = promoQueueLeaseArbiter.acquireVisiblePromoLease(for: identity) else {
            Issue.record("Expected visible owner acquisition")
            return
        }
        let providers = ModalPromptProviders(
            newAddressBarPicker: provider,
            defaultBrowser: provider,
            winBackOffer: provider,
            subscriptionPromo: provider,
            subscriptionPromoExistingUser: provider,
            whatsNew: provider,
            cookiePopupProtectionOptIn: provider
        )
        sut = PromoCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            keyValueStore: try MockKeyValueFileStore(),
            contextualOnboardingStatusProvider: contextualOnboardingMock,
            privacyConfigManager: MockPrivacyConfigurationManager(),
            providers: providers,
            promoCoordinationMode: .coordinated,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )

        sut.presentModalPromptIfNeeded(from: presenterMock)

        #expect(!provider.didCallProvideModalPrompt)
        #expect(!presenterMock.didCallPresent)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .visible(identity))
        _ = visibleLease
    }

    @available(iOS 16, *)
    @Test("Legacy Modal Evaluation Bypasses The Arbiter", .timeLimit(.minutes(1)))
    func whenPromoQueueIsLegacyThenManagerUsesLeaseFreePath() {
        launchSourceManagerMock.source = .standard
        presenterMock.presentedViewController = nil
        makeSUT(mode: .legacy)

        sut.presentModalPromptIfNeeded(from: presenterMock)

        #expect(managerMock.didCallPresentModalPromptIfNeeded)
        #expect(managerMock.capturedModalLease == nil)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == nil)
        #expect(managerMock.reconcilePresentedModalCallCount == 0)
    }

    @available(iOS 16, *)
    @Test("A Mock Released Disposition Does Not Duplicate The Readiness Drain", .timeLimit(.minutes(1)))
    func whenMockManagerReturnsReleasedThenRegistrationsRetryOnlyInTheInitialDrain() {
        launchSourceManagerMock.source = .standard
        presenterMock.presentedViewController = nil
        managerMock.coordinatedPresentationDisposition = .released
        makeSUT()
        let firstTarget = MockNewTabPagePromoRetryTarget()
        let secondTarget = MockNewTabPagePromoRetryTarget()
        let firstRegistration = sut.registerRemoteMessageRetry(for: UUID(), target: firstTarget)
        let secondRegistration = sut.registerRemoteMessageRetry(for: UUID(), target: secondTarget)

        sut.presentModalPromptIfNeeded(from: presenterMock)

        #expect(firstTarget.retryCount == 1)
        #expect(secondTarget.retryCount == 1)
        #expect(managerMock.didCallPresentModalPromptIfNeeded)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == nil)
        _ = (firstRegistration, secondRegistration)
    }

    @available(iOS 16, *)
    @Test("Real No-Provider Release Wakes A Waiter That Became Eligible After Readiness Drain", .timeLimit(.minutes(1)))
    func whenRealManagerFindsNoProviderThenItsReleaseCallbackRetriesExactlyOnce() {
        launchSourceManagerMock.source = .standard
        presenterMock.presentedViewController = nil
        let cooldownManager = MockPromptCooldownManager()
        cooldownManager.cooldownInfoToReturn = .notInCoolDown
        let realManager = ModalPromptCoordinationManager(
            providers: [],
            cooldownManager: cooldownManager,
            onboardingStatusProvider: contextualOnboardingMock,
            modalPromptScheduling: MockModalPromptScheduler()
        )
        sut = PromoCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: realManager,
            promoCoordinationMode: .coordinated,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )
        let identity = makeIdentity(promoID: "late-waiter")
        let target = MockNewTabPagePromoRetryTarget()
        var retainedAdmission: PromoQueueRemoteMessageAdmission?
        target.customRetryHandler = { [weak target] admissionHandler in
            guard let target, target.retryCount > 1 else {
                return
            }
            guard case .acquired(let admission) = admissionHandler(identity) else {
                Issue.record("Expected the real manager's no-provider release to free the owner before notifying")
                return
            }
            retainedAdmission = admission
        }
        let registration = sut.registerRemoteMessageRetry(for: identity.surfaceID, target: target)

        sut.presentModalPromptIfNeeded(from: presenterMock)

        #expect(target.retryCount == 2)
        #expect(retainedAdmission != nil)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .visible(identity))
        _ = registration
    }

    // MARK: - Admission Facade

    @available(iOS 16, *)
    @Test("Legacy Mode Defers RMF Admission Without Arbitrating", .timeLimit(.minutes(1)))
    func whenPromoQueueIsLegacyThenRemoteMessageAdmissionIsDeferred() {
        makeSUT(mode: .legacy)
        let result = sut.admitRemoteMessage(makeIdentity(promoID: "rmf"))

        guard case .deferred = result else {
            Issue.record("Expected legacy mode to bypass coordinated admission")
            return
        }
        #expect(managerMock.reconcilePresentedModalCallCount == 0)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == nil)
    }

    @available(iOS 16, *)
    @Test("Legacy Foreground Lifecycle Does Not Refresh Registered RMF Models", .timeLimit(.minutes(1)))
    func whenLegacyServiceReturnsToForegroundThenRetryRegistryRemainsUnused() {
        makeSUT(mode: .legacy)
        let target = MockNewTabPagePromoRetryTarget()
        let registration = sut.registerRemoteMessageRetry(for: UUID(), target: target)

        sut.applicationWillResignActive()
        sut.applicationDidBecomeActive()
        managerMock.coordinatedAttemptReleaseHandler?()

        #expect(target.retryCount == 0)
        #expect(managerMock.applicationWillResignActiveCallCount == 1)
        #expect(managerMock.applicationDidBecomeActiveCallCount == 1)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == nil)
        _ = registration
    }

    @available(iOS 16, *)
    @Test("Modal Global Owner Is Exposed To RMF As Deferred", .timeLimit(.minutes(1)))
    func whenModalOwnsGlobalSlotThenRemoteMessageAdmissionIsDeferred() {
        makeSUT()
        guard case .acquired(let modalLease) = promoQueueLeaseArbiter.acquireModalLease() else {
            Issue.record("Expected modal owner acquisition")
            return
        }

        let result = sut.admitRemoteMessage(makeIdentity(promoID: "rmf"))

        guard case .deferred = result else {
            Issue.record("Expected the public facade to collapse the modal denial to deferred")
            return
        }
        #expect(managerMock.reconcilePresentedModalCallCount == 1)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .modal(modalLease.attemptIdentity))
    }

    @available(iOS 16, *)
    @Test("Visible Global Owner Defers Every Other Surface Without Changing Owner", .timeLimit(.minutes(1)))
    func whenVisibleOwnerExistsThenAnotherSurfaceIsDeferred() {
        makeSUT()
        let ownerIdentity = makeIdentity(promoID: "owner")
        let waiterIdentity = makeIdentity(promoID: "waiter")
        guard case .acquired(let ownerAdmission) = sut.admitRemoteMessage(ownerIdentity) else {
            Issue.record("Expected initial admission")
            return
        }

        guard case .deferred = sut.admitRemoteMessage(waiterIdentity) else {
            Issue.record("Expected global visible serialization")
            return
        }
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .visible(ownerIdentity))
        _ = ownerAdmission
    }

    @available(iOS 16, *)
    @Test("Detached Modal Reconciliation Completes Requester Admission Before Retrying Others", .timeLimit(.minutes(1)))
    func whenAdmissionReleasesDetachedModalThenRequesterOwnsBeforeRetrySnapshot() {
        makeSUT()
        guard case .acquired(let modalLease) = promoQueueLeaseArbiter.acquireModalLease() else {
            Issue.record("Expected modal owner acquisition")
            return
        }
        managerMock.reconcilePresentedModalResult = true
        managerMock.onReconcilePresentedModal = {
            modalLease.release()
        }
        let requesterIdentity = makeIdentity(promoID: "requester")
        let waiterIdentity = makeIdentity(promoID: "waiter")
        let requesterTarget = MockNewTabPagePromoRetryTarget()
        let waiterTarget = MockNewTabPagePromoRetryTarget()
        waiterTarget.identityToAdmitOnRetry = waiterIdentity
        let requesterRegistration = sut.registerRemoteMessageRetry(
            for: requesterIdentity.surfaceID,
            target: requesterTarget
        )
        let waiterRegistration = sut.registerRemoteMessageRetry(for: waiterIdentity.surfaceID, target: waiterTarget)

        guard case .acquired(let requesterAdmission) = sut.admitRemoteMessage(requesterIdentity) else {
            Issue.record("Expected the triggering surface to acquire before the retry snapshot")
            return
        }

        #expect(requesterTarget.retryCount == 0)
        #expect(waiterTarget.retryCount == 1)
        #expect(waiterTarget.retainedAdmission == nil)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .visible(requesterIdentity))
        _ = (requesterAdmission, requesterRegistration, waiterRegistration)
    }

    @available(iOS 16, *)
    @Test("Stale Modal Verification Cannot Wake Around A Replacement Visible Owner", .timeLimit(.minutes(1)))
    func whenStaleModalVerificationRunsAfterReplacementAcquiresThenItDoesNotDrainOrClearReplacement() {
        launchSourceManagerMock.source = .standard
        presenterMock.presentedViewController = nil
        presenterMock.shouldCompletePresentation = false
        let provider = MockModalPromptProvider()
        let cooldownManager = MockPromptCooldownManager()
        cooldownManager.cooldownInfoToReturn = .notInCoolDown
        let scheduler = MockModalPromptScheduler()
        let realManager = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManager,
            onboardingStatusProvider: contextualOnboardingMock,
            modalPromptScheduling: scheduler
        )
        sut = PromoCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: realManager,
            promoCoordinationMode: .coordinated,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )

        sut.presentModalPromptIfNeeded(from: presenterMock)
        scheduler.executeScheduledBlock()

        let replacementIdentity = makeIdentity(promoID: "replacement")
        guard case .acquired(let replacementAdmission) = sut.admitRemoteMessage(replacementIdentity) else {
            Issue.record("Expected reconciliation to release the detached modal before replacement admission")
            return
        }
        let waiterIdentity = makeIdentity(promoID: "waiter")
        let waiter = MockNewTabPagePromoRetryTarget()
        waiter.identityToAdmitOnRetry = waiterIdentity
        let waiterRegistration = sut.registerRemoteMessageRetry(for: waiterIdentity.surfaceID, target: waiter)

        scheduler.executeNextMainTurnBlock(includingCancelled: true)

        #expect(waiter.retryCount == 0)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .visible(replacementIdentity))
        _ = (replacementAdmission, waiterRegistration)
    }

    @available(iOS 16, *)
    @Test("Admission Release Frees The Global Owner And Duplicate Release Is Inert", .timeLimit(.minutes(1)))
    func whenAdmissionReleasesThenGlobalSlotCanBeReacquired() {
        makeSUT()
        let firstIdentity = makeIdentity(promoID: "first")
        let secondIdentity = makeIdentity(promoID: "second")
        let secondTarget = MockNewTabPagePromoRetryTarget()
        secondTarget.identityToAdmitOnRetry = secondIdentity
        let registration = sut.registerRemoteMessageRetry(for: secondIdentity.surfaceID, target: secondTarget)
        guard case .acquired(let firstAdmission) = sut.admitRemoteMessage(firstIdentity) else {
            Issue.record("Expected initial admission")
            return
        }

        firstAdmission.release()

        #expect(secondTarget.retryCount == 1)
        #expect(secondTarget.retainedAdmission != nil)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .visible(secondIdentity))

        firstAdmission.release()

        #expect(secondTarget.retryCount == 1)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .visible(secondIdentity))
        _ = registration
    }

    @available(iOS 16, *)
    @Test("Visible Release Handoff Never Evaluates Modal Providers", .timeLimit(.minutes(1)))
    func whenVisibleOwnerReleasesThenOnlyRemoteMessageWaitersAreEvaluated() {
        let provider = MockModalPromptProvider()
        let cooldownManager = MockPromptCooldownManager()
        cooldownManager.cooldownInfoToReturn = .notInCoolDown
        let manager = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManager,
            onboardingStatusProvider: contextualOnboardingMock,
            modalPromptScheduling: MockModalPromptScheduler()
        )
        sut = PromoCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: manager,
            promoCoordinationMode: .coordinated,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )
        let ownerIdentity = makeIdentity(promoID: "owner")
        let waiterIdentity = makeIdentity(promoID: "waiter")
        let waiter = MockNewTabPagePromoRetryTarget()
        waiter.identityToAdmitOnRetry = waiterIdentity
        let registration = sut.registerRemoteMessageRetry(for: waiterIdentity.surfaceID, target: waiter)
        guard case .acquired(let ownerAdmission) = sut.admitRemoteMessage(ownerIdentity) else {
            Issue.record("Expected initial admission")
            return
        }

        ownerAdmission.release()

        #expect(!provider.didCallProvideModalPrompt)
        #expect(waiter.retryCount == 1)
        #expect(waiter.retainedAdmission != nil)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .visible(waiterIdentity))
        _ = registration
    }

    // MARK: - Stable Release Handoff

    @available(iOS 16, *)
    @Test("Release Excludes Releaser And Uses Stable Active Registration Order", .timeLimit(.minutes(1)))
    func whenOwnerReleasesThenFirstActiveOtherSurfaceGetsGlobalOwner() {
        makeSUT()
        let ownerIdentity = makeIdentity(promoID: "owner")
        let firstWaiterIdentity = makeIdentity(promoID: "first-waiter")
        let laterWaiterIdentity = makeIdentity(promoID: "later-waiter")
        guard case .acquired(let ownerAdmission) = sut.admitRemoteMessage(ownerIdentity) else {
            Issue.record("Expected initial admission")
            return
        }

        var retryOrder = [String]()
        let ownerTarget = MockNewTabPagePromoRetryTarget()
        ownerTarget.identityToAdmitOnRetry = ownerIdentity
        let ownerRegistration = sut.registerRemoteMessageRetry(for: ownerIdentity.surfaceID, target: ownerTarget)
        let inactiveTarget = MockNewTabPagePromoRetryTarget()
        inactiveTarget.isActiveForPromoRetry = false
        let inactiveRegistration = sut.registerRemoteMessageRetry(for: UUID(), target: inactiveTarget)
        let replacedSurfaceID = UUID()
        let staleTarget = MockNewTabPagePromoRetryTarget()
        let staleRegistration = sut.registerRemoteMessageRetry(for: replacedSurfaceID, target: staleTarget)
        let replacementTarget = MockNewTabPagePromoRetryTarget()
        replacementTarget.isActiveForPromoRetry = false
        let replacementRegistration = sut.registerRemoteMessageRetry(for: replacedSurfaceID, target: replacementTarget)
        let deallocatedRegistration: NewTabPagePromoRetryRegistration
        do {
            let deallocatedTarget = MockNewTabPagePromoRetryTarget()
            deallocatedRegistration = sut.registerRemoteMessageRetry(for: UUID(), target: deallocatedTarget)
        }
        let firstWaiter = MockNewTabPagePromoRetryTarget()
        firstWaiter.identityToAdmitOnRetry = firstWaiterIdentity
        firstWaiter.retryObserver = { retryOrder.append("first") }
        let firstWaiterRegistration = sut.registerRemoteMessageRetry(
            for: firstWaiterIdentity.surfaceID,
            target: firstWaiter
        )
        let laterWaiter = MockNewTabPagePromoRetryTarget()
        laterWaiter.identityToAdmitOnRetry = laterWaiterIdentity
        laterWaiter.retryObserver = { retryOrder.append("later") }
        let laterWaiterRegistration = sut.registerRemoteMessageRetry(
            for: laterWaiterIdentity.surfaceID,
            target: laterWaiter
        )

        ownerAdmission.release()

        #expect(ownerTarget.retryCount == 0)
        #expect(inactiveTarget.retryCount == 0)
        #expect(staleTarget.retryCount == 0)
        #expect(replacementTarget.retryCount == 0)
        #expect(retryOrder == ["first", "later"])
        #expect(firstWaiter.retainedAdmission != nil)
        #expect(laterWaiter.retainedAdmission == nil)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .visible(firstWaiterIdentity))
        #expect(!managerMock.didCallPresentModalPromptIfNeeded)
        _ = (
            ownerRegistration,
            inactiveRegistration,
            staleRegistration,
            replacementRegistration,
            deallocatedRegistration,
            firstWaiterRegistration,
            laterWaiterRegistration
        )
    }

    @available(iOS 16, *)
    @Test("Synchronous Waiter Release Lets Outer Drain Reach The Next Waiter", .timeLimit(.minutes(1)))
    func whenFirstWaiterReleasesSynchronouslyThenLaterWaiterAcquiresInSameDrain() {
        makeSUT()
        let ownerIdentity = makeIdentity(promoID: "owner")
        let rollingBackIdentity = makeIdentity(promoID: "rollback")
        let retainedIdentity = makeIdentity(promoID: "retained")
        guard case .acquired(let ownerAdmission) = sut.admitRemoteMessage(ownerIdentity) else {
            Issue.record("Expected initial admission")
            return
        }
        var retryOrder = [String]()
        let rollingBackTarget = MockNewTabPagePromoRetryTarget()
        rollingBackTarget.retryObserver = { retryOrder.append("rollback") }
        rollingBackTarget.customRetryHandler = { admissionHandler in
            guard case .acquired(let admission) = admissionHandler(rollingBackIdentity) else {
                Issue.record("Expected first waiter acquisition")
                return
            }
            admission.release()
        }
        let retainedTarget = MockNewTabPagePromoRetryTarget()
        retainedTarget.identityToAdmitOnRetry = retainedIdentity
        retainedTarget.retryObserver = { retryOrder.append("retained") }
        let rollingBackRegistration = sut.registerRemoteMessageRetry(
            for: rollingBackIdentity.surfaceID,
            target: rollingBackTarget
        )
        let retainedRegistration = sut.registerRemoteMessageRetry(
            for: retainedIdentity.surfaceID,
            target: retainedTarget
        )

        ownerAdmission.release()

        #expect(retryOrder == ["rollback", "retained"])
        #expect(rollingBackTarget.retryCount == 1)
        #expect(retainedTarget.retryCount == 1)
        #expect(retainedTarget.retainedAdmission != nil)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .visible(retainedIdentity))
        _ = (rollingBackRegistration, retainedRegistration)
    }

    @available(iOS 16, *)
    @Test("Registration Mutation And Nested Checkpoint Defer Replacement Entries", .timeLimit(.minutes(1)))
    func whenRetryMutatesRegistryThenOnlyUntouchedSnapshotEntryAcquires() {
        makeSUT()
        let ownerIdentity = makeIdentity(promoID: "owner")
        let untouchedIdentity = makeIdentity(promoID: "untouched")
        guard case .acquired(let ownerAdmission) = sut.admitRemoteMessage(ownerIdentity) else {
            Issue.record("Expected initial admission")
            return
        }
        let mutatingTarget = MockNewTabPagePromoRetryTarget()
        let selfReplacementTarget = MockNewTabPagePromoRetryTarget()
        let oldTarget = MockNewTabPagePromoRetryTarget()
        let replacementTarget = MockNewTabPagePromoRetryTarget()
        let untouchedTarget = MockNewTabPagePromoRetryTarget()
        untouchedTarget.identityToAdmitOnRetry = untouchedIdentity
        let mutatingSurfaceID = UUID()
        var mutatingRegistration: NewTabPagePromoRetryRegistration? = sut.registerRemoteMessageRetry(
            for: mutatingSurfaceID,
            target: mutatingTarget
        )
        let replacedSurfaceID = UUID()
        let oldRegistration = sut.registerRemoteMessageRetry(for: replacedSurfaceID, target: oldTarget)
        let untouchedRegistration = sut.registerRemoteMessageRetry(
            for: untouchedIdentity.surfaceID,
            target: untouchedTarget
        )
        var selfReplacementRegistration: NewTabPagePromoRetryRegistration?
        var replacementRegistration: NewTabPagePromoRetryRegistration?
        mutatingTarget.customRetryHandler = { [unowned sut = sut!] _ in
            mutatingRegistration?.deregister()
            selfReplacementRegistration = sut.registerRemoteMessageRetry(
                for: mutatingSurfaceID,
                target: selfReplacementTarget
            )
            oldRegistration.deregister()
            replacementRegistration = sut.registerRemoteMessageRetry(
                for: replacedSurfaceID,
                target: replacementTarget
            )
            sut.applicationDidBecomeActive()
        }

        ownerAdmission.release()

        #expect(mutatingTarget.retryCount == 1)
        #expect(selfReplacementTarget.retryCount == 0)
        #expect(oldTarget.retryCount == 0)
        #expect(replacementTarget.retryCount == 0)
        #expect(untouchedTarget.retryCount == 1)
        #expect(untouchedTarget.retainedAdmission != nil)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .visible(untouchedIdentity))
        _ = (
            mutatingRegistration,
            selfReplacementRegistration,
            untouchedRegistration,
            replacementRegistration
        )
    }

    @available(iOS 16, *)
    @Test("Stale Registration Token Cannot Remove Its Replacement", .timeLimit(.minutes(1)))
    func whenRegistrationIsReplacedThenOldTokenCannotRemoveReplacement() {
        makeSUT()
        let surfaceID = UUID()
        let firstTarget = MockNewTabPagePromoRetryTarget()
        let replacementTarget = MockNewTabPagePromoRetryTarget()
        let firstRegistration = sut.registerRemoteMessageRetry(for: surfaceID, target: firstTarget)
        let replacementRegistration = sut.registerRemoteMessageRetry(for: surfaceID, target: replacementTarget)

        firstRegistration.deregister()
        managerMock.coordinatedAttemptReleaseHandler?()

        #expect(firstTarget.retryCount == 0)
        #expect(replacementTarget.retryCount == 1)
        _ = replacementRegistration
    }

    // MARK: - Readiness

    @available(iOS 16, *)
    @Test("Temporary Inactivity Defers Admission And Successful Release Handoff Until Active", .timeLimit(.minutes(1)))
    func whenOwnerReleasesDuringTemporaryInactivityThenReturnPerformsHandoff() {
        makeSUT()
        let ownerIdentity = makeIdentity(promoID: "owner")
        let waiterIdentity = makeIdentity(promoID: "waiter")
        let waiter = MockNewTabPagePromoRetryTarget()
        waiter.identityToAdmitOnRetry = waiterIdentity
        let registration = sut.registerRemoteMessageRetry(for: waiterIdentity.surfaceID, target: waiter)
        guard case .acquired(let ownerAdmission) = sut.admitRemoteMessage(ownerIdentity) else {
            Issue.record("Expected initial admission")
            return
        }

        sut.applicationWillResignActive()
        guard case .deferred = sut.admitRemoteMessage(waiterIdentity) else {
            Issue.record("Expected direct admission to close while inactive")
            return
        }
        ownerAdmission.release()

        #expect(waiter.retryCount == 0)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == nil)

        sut.applicationDidBecomeActive()

        #expect(waiter.retryCount == 1)
        #expect(waiter.retainedAdmission != nil)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .visible(waiterIdentity))
        _ = registration
    }

    @available(iOS 16, *)
    @Test("Background Handoff Waits For Full Foreground Interaction Readiness", .timeLimit(.minutes(1)))
    func whenOwnerReleasesInBackgroundThenReadinessCheckpointPerformsHandoff() {
        launchSourceManagerMock.source = .standard
        presenterMock.presentedViewController = nil
        makeSUT()
        let ownerIdentity = makeIdentity(promoID: "owner")
        let waiterIdentity = makeIdentity(promoID: "waiter")
        let waiter = MockNewTabPagePromoRetryTarget()
        waiter.identityToAdmitOnRetry = waiterIdentity
        let registration = sut.registerRemoteMessageRetry(for: waiterIdentity.surfaceID, target: waiter)
        guard case .acquired(let ownerAdmission) = sut.admitRemoteMessage(ownerIdentity) else {
            Issue.record("Expected initial admission")
            return
        }

        sut.applicationDidEnterBackground()
        ownerAdmission.release()
        sut.applicationDidBecomeActive()

        #expect(waiter.retryCount == 0)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == nil)
        guard case .deferred = sut.admitRemoteMessage(waiterIdentity) else {
            Issue.record("Expected direct admission to wait for UI readiness")
            return
        }

        sut.presentModalPromptIfNeeded(from: presenterMock)

        #expect(waiter.retryCount == 1)
        #expect(waiter.retainedAdmission != nil)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .visible(waiterIdentity))
        #expect(!managerMock.didCallPresentModalPromptIfNeeded)
        _ = registration
    }

    @available(iOS 16, *)
    @Test("Inactive Stale Readiness Cannot Open The Next Foreground", .timeLimit(.minutes(1)))
    func whenStaleReadinessArrivesInBackgroundThenNextForegroundStillWaitsForItsOwnReadiness() {
        launchSourceManagerMock.source = .standard
        presenterMock.presentedViewController = nil
        makeSUT()
        let waiterIdentity = makeIdentity(promoID: "waiter")
        let waiter = MockNewTabPagePromoRetryTarget()
        waiter.identityToAdmitOnRetry = waiterIdentity
        let registration = sut.registerRemoteMessageRetry(for: waiterIdentity.surfaceID, target: waiter)

        sut.applicationDidEnterBackground()
        sut.presentModalPromptIfNeeded(from: presenterMock)

        #expect(waiter.retryCount == 0)
        guard case .deferred = sut.admitRemoteMessage(waiterIdentity) else {
            Issue.record("Expected direct admission to remain closed after stale background readiness")
            return
        }

        sut.applicationDidBecomeActive()

        #expect(waiter.retryCount == 0)
        guard case .deferred = sut.admitRemoteMessage(waiterIdentity) else {
            Issue.record("Expected the new foreground to wait for its own full readiness")
            return
        }

        sut.presentModalPromptIfNeeded(from: presenterMock)

        #expect(waiter.retryCount == 1)
        #expect(waiter.retainedAdmission != nil)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .visible(waiterIdentity))
        #expect(!managerMock.didCallPresentModalPromptIfNeeded)
        _ = registration
    }

    @available(iOS 16, *)
    @Test("Background Retains Existing Visible Owner And Forwards Lifecycle", .timeLimit(.minutes(1)))
    func whenServiceBackgroundsThenExistingAdmissionRemainsOwner() {
        makeSUT()
        let identity = makeIdentity(promoID: "owner")
        guard case .acquired(let admission) = sut.admitRemoteMessage(identity) else {
            Issue.record("Expected visible admission")
            return
        }

        sut.applicationWillResignActive()
        sut.applicationDidEnterBackground()
        sut.applicationDidBecomeActive()

        #expect(managerMock.applicationWillResignActiveCallCount == 1)
        #expect(managerMock.applicationDidEnterBackgroundCallCount == 1)
        #expect(managerMock.applicationDidBecomeActiveCallCount == 1)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .visible(identity))
        _ = admission
    }

    @available(iOS 16, *)
    @Test("Abandoned Admission Is Reclaimed Only At A Later Checkpoint", .timeLimit(.minutes(1)))
    func whenAdmissionDeallocatesThenWaiterRecoversAtExplicitCheckpoint() {
        makeSUT()
        let ownerIdentity = makeIdentity(promoID: "owner")
        let waiterIdentity = makeIdentity(promoID: "waiter")
        let waiter = MockNewTabPagePromoRetryTarget()
        waiter.identityToAdmitOnRetry = waiterIdentity
        let registration = sut.registerRemoteMessageRetry(for: waiterIdentity.surfaceID, target: waiter)
        weak var abandonedAdmission: PromoQueueRemoteMessageAdmission?

        do {
            guard case .acquired(let admission) = sut.admitRemoteMessage(ownerIdentity) else {
                Issue.record("Expected initial admission")
                return
            }
            abandonedAdmission = admission
            guard case .deferred = sut.admitRemoteMessage(waiterIdentity) else {
                Issue.record("Expected waiter deferral")
                return
            }
        }

        #expect(abandonedAdmission == nil)
        #expect(waiter.retryCount == 0)

        sut.applicationDidBecomeActive()

        #expect(waiter.retryCount == 1)
        #expect(waiter.retainedAdmission != nil)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .visible(waiterIdentity))
        _ = registration
    }

    private func makeSUT(mode: PromoCoordinationMode = .coordinated) {
        sut = PromoCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            promoCoordinationMode: mode,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )
    }

    private func makeIdentity(surfaceID: UUID = UUID(), promoID: String) -> VisiblePromoIdentity {
        VisiblePromoIdentity(
            surfaceID: surfaceID,
            promoType: .remoteMessage,
            promoID: promoID
        )
    }
}

@MainActor
private final class MockNewTabPagePromoRetryTarget: NewTabPagePromoRetrying {
    var isActiveForPromoRetry = true
    var identityToAdmitOnRetry: VisiblePromoIdentity?
    var retryObserver: (() -> Void)?
    var customRetryHandler: ((PromoQueueRemoteMessageAdmissionHandler) -> Void)?
    private(set) var retryCount = 0
    private(set) var retainedAdmission: PromoQueueRemoteMessageAdmission?

    func retryRemoteMessageAdmission(using admissionHandler: PromoQueueRemoteMessageAdmissionHandler) {
        retryCount += 1
        retryObserver?()
        if let customRetryHandler {
            customRetryHandler(admissionHandler)
            return
        }

        guard let identityToAdmitOnRetry else {
            return
        }

        switch admissionHandler(identityToAdmitOnRetry) {
        case .acquired(let admission):
            retainedAdmission = admission
        case .deferred:
            break
        }
    }
}
