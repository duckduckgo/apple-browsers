//
//  ModalPromptCoordinationManagerPromoQueueTests.swift
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

import UIKit
import Foundation
import Testing
@testable import DuckDuckGo

@MainActor
@Suite("Modal Prompt Coordination - Coordination Manager Promo Queue")
final class ModalPromptCoordinationManagerPromoQueueTests {
    private let cooldownManagerMock: MockPromptCooldownManager
    private let schedulerMock: MockModalPromptScheduler
    private let presenterMock: MockModalPromptPresenter
    private let promoQueueLeaseArbiter: PromoQueueLeaseArbiter
    private var sut: ModalPromptCoordinationManager!

    init() {
        cooldownManagerMock = MockPromptCooldownManager()
        schedulerMock = MockModalPromptScheduler()
        presenterMock = MockModalPromptPresenter()
        promoQueueLeaseArbiter = PromoQueueLeaseArbiter()
    }

    // MARK: - Promo Queue Attempt Phases

    @available(iOS 16, *)
    @Test("Coordinated Cooldown Releases Lease Without Querying Providers", .timeLimit(.minutes(1)))
    func whenCoordinatedAttemptIsInCooldownThenLeaseIsReleasedSynchronously() throws {
        cooldownManagerMock.cooldownInfoToReturn = .inCoolDown
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        let lease = try acquireModalLease()

        let disposition = sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)

        #expect(disposition == .released)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(sut.modalAttemptPhase == .idle)
        #expect(!provider.didCallProvideModalPrompt)
    }

    @available(iOS 16, *)
    @Test("Coordinated No Provider Releases Lease", .timeLimit(.minutes(1)))
    func whenNoCoordinatedProviderReturnsPromptThenLeaseIsReleasedSynchronously() throws {
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider(shouldReturnPrompt: false)
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        let lease = try acquireModalLease()

        let disposition = sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)

        #expect(disposition == .released)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(provider.didCallProvideModalPrompt)
        #expect(!sut.hasActiveOrPendingModalAttempt)
    }

    @available(iOS 16, *)
    @Test("Coordinated Selection Respects Provider Eligibility And Order", .timeLimit(.minutes(1)))
    func whenCoordinatedProvidersHaveDifferentEligibilityThenFirstEligiblePromptIsSelected() throws {
        // Every provider here forces its own answer, so this covers the eligibility gate and provider order only. The
        // onboarding gate itself is covered separately, by a provider that uses the protocol's default implementation.
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let ineligibleProvider = MockModalPromptProvider()
        ineligibleProvider.isEligibleToPresentResult = false
        let selectedProvider = MockModalPromptProvider()
        selectedProvider.isEligibleToPresentResult = true
        let lowerPriorityProvider = MockModalPromptProvider()
        lowerPriorityProvider.isEligibleToPresentResult = true
        sut = ModalPromptCoordinationManager(
            providers: [ineligibleProvider, selectedProvider, lowerPriorityProvider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: false),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        let lease = try acquireModalLease()

        let disposition = sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)

        #expect(disposition == .retained)
        #expect(ineligibleProvider.capturedIsOnboardingComplete == false)
        #expect(!ineligibleProvider.didCallProvideModalPrompt)
        #expect(selectedProvider.capturedIsOnboardingComplete == false)
        #expect(selectedProvider.didCallProvideModalPrompt)
        #expect(lowerPriorityProvider.capturedIsOnboardingComplete == nil)
        #expect(!lowerPriorityProvider.didCallProvideModalPrompt)

        schedulerMock.executeScheduledBlock()

        #expect(!ineligibleProvider.didCallDidPresentModal)
        #expect(selectedProvider.didCallDidPresentModal)
        #expect(!lowerPriorityProvider.didCallDidPresentModal)
    }

    @available(iOS 16, *)
    @Test("Coordinated Selection Gates A Default-Gated Provider On Incomplete Onboarding", .timeLimit(.minutes(1)))
    func whenOnboardingIsIncompleteThenDefaultGatedCoordinatedProviderIsNotAsked() throws {
        // GIVEN a provider that leaves `isEligibleToPresent(isOnboardingComplete:)` to the protocol's default
        // implementation, which is what every real provider does.
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: false),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        let lease = try acquireModalLease()

        // WHEN
        let disposition = sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)

        // THEN — incomplete onboarding gates the provider out before it is ever asked for a prompt, and the lease goes
        // straight back so a waiting promo is not blocked by an attempt that can never present.
        #expect(disposition == .released)
        #expect(provider.capturedIsOnboardingComplete == false)
        #expect(!provider.didCallProvideModalPrompt)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(sut.modalAttemptPhase == .idle)
        #expect(!sut.hasActiveOrPendingModalAttempt)
        #expect(!schedulerMock.didCallSchedule)
    }

    @available(iOS 16, *)
    @Test("Same Lease Attempt Moves From Committed To Presentation Active", .timeLimit(.minutes(1)))
    func whenCoordinatedPromptIsSelectedThenSameAttemptIdentityMovesThroughPhases() throws {
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        let lease = try acquireModalLease()

        let disposition = sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)

        #expect(disposition == .retained)
        #expect(sut.modalAttemptPhase == .committed(lease.attemptIdentity))
        #expect(!sut.didActuallyPresentModalPromptThisSession)
        #expect(sut.didPresentModalPromptThisSession)

        schedulerMock.executeScheduledBlock()

        #expect(sut.modalAttemptPhase == .presentationActive(lease.attemptIdentity))
        #expect(sut.didActuallyPresentModalPromptThisSession)
        #expect(promoQueueLeaseArbiter.snapshot.modalAttemptIdentity == lease.attemptIdentity)
    }

    @available(iOS 16, *)
    @Test("Detached Presented Root Releases The Modal Lease", .timeLimit(.minutes(1)))
    func whenPresentedRootIsDetachedThenReconciliationReleasesLease() throws {
        // GIVEN
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        let scheduler = BlockReleasingModalPromptScheduler()
        let attachmentChecker = MockModalPromptRootAttachmentChecker()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: scheduler,
            rootAttachmentChecker: attachmentChecker
        )
        let lease = try acquireModalLease()
        let exactRoot = UIViewController()
        provider.modalConfigurationToReturn = ModalPromptConfiguration(viewController: exactRoot)
        attachmentChecker.markAttached(exactRoot)

        _ = sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)
        scheduler.executeAndReleaseScheduledBlock()

        #expect(sut.modalAttemptPhase == .presentationActive(lease.attemptIdentity))
        #expect(!sut.reconcilePresentedModal())
        #expect(promoQueueLeaseArbiter.snapshot.hasModalLease)

        // WHEN UIKit detaches the exact root.
        attachmentChecker.attachedRoots.remove(ObjectIdentifier(exactRoot))

        // THEN the lease is released rather than pinned until the next foreground.
        #expect(sut.reconcilePresentedModal())
        #expect(sut.modalAttemptPhase == .idle)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
    }

    @available(iOS 16, *)
    @Test("Attached Root Is Adopted Without Re-Presentation", .timeLimit(.minutes(1)))
    func whenSelectedRootIsAlreadyAttachedThenPreflightAdoptsIt() throws {
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        let exactRoot = UIViewController()
        provider.modalConfigurationToReturn = ModalPromptConfiguration(viewController: exactRoot)
        let intendedHost = UIViewController()
        presenterMock.modalPromptPresentationViewController = intendedHost
        let attachmentChecker = MockModalPromptRootAttachmentChecker()
        attachmentChecker.markAttached(intendedHost)
        attachmentChecker.markAttached(exactRoot)
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock,
            rootAttachmentChecker: attachmentChecker
        )
        let lease = try acquireModalLease()

        _ = sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)
        schedulerMock.executeScheduledBlock()

        #expect(!presenterMock.didCallPresent)
        #expect(sut.modalAttemptPhase == .presentationActive(lease.attemptIdentity))
        #expect(promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(sut.didActuallyPresentModalPromptThisSession)
        #expect(provider.didPresentModalCallCount == 1)
        #expect(cooldownManagerMock.recordLastPromptPresentationTimestampCallCount == 1)
    }

    @available(iOS 16, *)
    @Test("Attachment Verification Retains Lease For Attached Root", .timeLimit(.minutes(1)))
    func whenPresentedRootAttachesThenVerificationRetainsLease() throws {
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        let exactRoot = UIViewController()
        provider.modalConfigurationToReturn = ModalPromptConfiguration(viewController: exactRoot)
        let intendedHost = UIViewController()
        presenterMock.modalPromptPresentationViewController = intendedHost
        presenterMock.shouldCompletePresentation = false
        let attachmentChecker = MockModalPromptRootAttachmentChecker()
        attachmentChecker.markAttached(intendedHost)
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock,
            rootAttachmentChecker: attachmentChecker
        )
        let lease = try acquireModalLease()

        _ = sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)
        schedulerMock.executeScheduledBlock()
        attachmentChecker.markAttached(exactRoot)
        schedulerMock.executeNextMainTurnBlock()

        #expect(sut.modalAttemptPhase == .presentationActive(lease.attemptIdentity))
        #expect(promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(!sut.reconcilePresentedModal())
    }

    @available(iOS 16, *)
    @Test("Accepted Presentation Does Not Retain Detached Root", .timeLimit(.minutes(1)))
    func whenAcceptedRootDeallocatesThenReconciliationReleasesLease() throws {
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        var exactRoot: UIViewController? = UIViewController()
        weak var weakExactRoot = exactRoot
        provider.modalConfigurationToReturn = ModalPromptConfiguration(viewController: try #require(exactRoot))
        let scheduler = BlockReleasingModalPromptScheduler()
        let attachmentChecker = MockModalPromptRootAttachmentChecker()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: scheduler,
            rootAttachmentChecker: attachmentChecker
        )
        let lease = try acquireModalLease()

        _ = sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)
        scheduler.executeAndReleaseScheduledBlock()
        let presentedRootIdentifier = ObjectIdentifier(try #require(exactRoot))
        attachmentChecker.markAttached(try #require(exactRoot))
        scheduler.executeAndReleaseScheduledBlock()

        #expect(sut.modalAttemptPhase == .presentationActive(lease.attemptIdentity))
        #expect(promoQueueLeaseArbiter.snapshot.hasModalLease)

        attachmentChecker.attachedRoots.remove(presentedRootIdentifier)
        provider.modalConfigurationToReturn = nil
        presenterMock.reset()
        exactRoot = nil

        #expect(weakExactRoot == nil)
        #expect(sut.reconcilePresentedModal())
        #expect(sut.modalAttemptPhase == .idle)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
    }

    @available(iOS 16, *)
    @Test("Disable Releases Coordination But Preserves Actual History And Visible Controller", .timeLimit(.minutes(1)))
    func whenFeatureDisablesAfterPresentationThenHistoryAndUIKitModalRemain() throws {
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        let lease = try acquireModalLease()
        _ = sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)
        schedulerMock.executeScheduledBlock()
        let presentedRoot = presenterMock.capturedViewController

        sut.promoQueueWillTransition(to: .disabled)

        #expect(sut.modalAttemptPhase == .idle)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(sut.didActuallyPresentModalPromptThisSession)
        #expect(presenterMock.capturedViewController === presentedRoot)
    }

    @available(iOS 16, *)
    @Test("Disable During Present Animation Preserves Actual History", .timeLimit(.minutes(1)))
    func whenFeatureDisablesDuringPresentAnimationThenActualHistoryIsPreserved() throws {
        // GIVEN
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        let exactRoot = UIViewController()
        provider.modalConfigurationToReturn = ModalPromptConfiguration(viewController: exactRoot)
        let deferredPresenter = DeferredCompletionModalPromptPresenter()
        // This test's premise is that the modal really is on screen animating in. The deferred presenter cannot
        // reproduce that on its own — it never hands the root to UIKit — so the checker states the premise explicitly
        // instead of leaving it to whatever the real attachment predicate happens to answer for a detached controller.
        let attachmentChecker = MockModalPromptRootAttachmentChecker()
        deferredPresenter.onPresent = {
            attachmentChecker.markAttached(exactRoot)
        }
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock,
            rootAttachmentChecker: attachmentChecker
        )
        let lease = try acquireModalLease()
        _ = sut.presentModalPromptIfNeeded(from: deferredPresenter, with: lease)
        schedulerMock.executeScheduledBlock()
        let presentedRoot = deferredPresenter.capturedViewController

        // The presentation is in flight: the modal is on screen but UIKit has not run the completion yet.
        #expect(deferredPresenter.didCallPresent)
        #expect(presentedRoot === exactRoot)
        #expect(sut.modalAttemptPhase == .presentationActive(lease.attemptIdentity))
        #expect(!sut.didActuallyPresentModalPromptThisSession)
        #expect(sut.didPresentModalPromptThisSession)

        // WHEN
        sut.promoQueueWillTransition(to: .disabled)

        // THEN
        #expect(sut.modalAttemptPhase == .idle)
        #expect(sut.didActuallyPresentModalPromptThisSession)
        #expect(sut.didPresentModalPromptThisSession)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(deferredPresenter.capturedViewController === presentedRoot)

        // WHEN the withheld UIKit completion finally lands, session history stays latched.
        deferredPresenter.completePendingPresentation()

        // THEN
        #expect(sut.modalAttemptPhase == .idle)
        #expect(sut.didPresentModalPromptThisSession)
        #expect(provider.didCallDidPresentModal)
    }

    @available(iOS 16, *)
    @Test("Disable After Refused Presentation Does Not Latch Actual History", .timeLimit(.minutes(1)))
    func whenPresentationWasRefusedThenDisablingDoesNotLatchActualHistory() throws {
        // GIVEN
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        let exactRoot = UIViewController()
        provider.modalConfigurationToReturn = ModalPromptConfiguration(viewController: exactRoot)
        // UIKit silently refused the presentation: `present` was called, the root never became attached, and the
        // completion never runs. The attempt still reaches `.presentationActive` because that happens before `present`.
        let deferredPresenter = DeferredCompletionModalPromptPresenter()
        let attachmentChecker = MockModalPromptRootAttachmentChecker()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock,
            rootAttachmentChecker: attachmentChecker
        )
        let lease = try acquireModalLease()
        _ = sut.presentModalPromptIfNeeded(from: deferredPresenter, with: lease)
        schedulerMock.executeScheduledBlock()

        #expect(deferredPresenter.didCallPresent)
        #expect(sut.modalAttemptPhase == .presentationActive(lease.attemptIdentity))
        #expect(!sut.didActuallyPresentModalPromptThisSession)

        // WHEN
        sut.promoQueueWillTransition(to: .disabled)

        // THEN — the transition consults attachment for the exact selected root, and a modal that never appeared must
        // not suppress every other promo for the rest of the session.
        #expect(attachmentChecker.didQuery(exactRoot))
        #expect(sut.modalAttemptPhase == .idle)
        #expect(!sut.didActuallyPresentModalPromptThisSession)
        #expect(!sut.didPresentModalPromptThisSession)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
    }

    @available(iOS 16, *)
    @Test("Enabling Re-Adopts Attached Root Observed On Legacy Path", .timeLimit(.minutes(1)))
    func whenLegacyRootIsAttachedThenEnablingReAdoptsModalLease() {
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        let exactRoot = UIViewController()
        provider.modalConfigurationToReturn = ModalPromptConfiguration(viewController: exactRoot)
        let attachmentChecker = MockModalPromptRootAttachmentChecker()
        let intendedHost = UIViewController()
        presenterMock.modalPromptPresentationViewController = intendedHost
        attachmentChecker.markAttached(exactRoot)
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock,
            rootAttachmentChecker: attachmentChecker
        )
        sut.presentModalPromptIfNeeded(from: presenterMock)
        schedulerMock.executeScheduledBlock()

        sut.promoQueueWillTransition(to: .enabled)
        promoQueueLeaseArbiter.invalidateAllLeases()
        sut.promoQueueDidTransition(to: .enabled)

        #expect(promoQueueLeaseArbiter.snapshot.hasModalLease)
        guard case .presentationActive = sut.modalAttemptPhase else {
            Issue.record("Expected attached legacy root to be re-adopted as presentation active")
            return
        }
    }

    // MARK: - Safe Scheduling And Lifecycle

    @available(iOS 16, *)
    @Test("Lifecycle Hooks Are No-Ops For A Legacy Presentation", .timeLimit(.minutes(1)))
    func whenLifecycleHooksRunDuringLegacyDelayThenModalStillPresentsWithoutCoordination() {
        // GIVEN a flag-off attempt scheduled through the legacy overload, so no lease exists for the lifecycle hooks to
        // move to pending or release.
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        let exactRoot = UIViewController()
        provider.modalConfigurationToReturn = ModalPromptConfiguration(viewController: exactRoot)
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // WHEN
        sut.applicationWillResignActive()
        sut.applicationDidEnterBackground()
        sut.applicationDidBecomeActive()
        schedulerMock.executeScheduledBlock()

        // THEN the legacy presentation lands exactly as it does without the feature: the delayed block was neither
        // cancelled nor retained as pending coordinated work, and the arbiter was never involved.
        #expect(presenterMock.didCallPresent)
        #expect(presenterMock.capturedViewController === exactRoot)
        #expect(provider.didPresentModalCallCount == 1)
        #expect(!sut.hasActiveOrPendingModalAttempt)
        #expect(sut.modalAttemptPhase == .idle)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(promoQueueLeaseArbiter.snapshot.visiblePromoCount == 0)
    }

    @available(iOS 16, *)
    @Test("Temporary Inactivity Moves Delayed Presentation To Pending", .timeLimit(.minutes(1)))
    func whenAppTemporarilyResignsActiveDuringDelayThenPreparedItemIsRetriedWithoutReevaluation() throws {
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        var releaseNotificationCount = 0
        sut.setCoordinatedAttemptReleaseHandler {
            releaseNotificationCount += 1
        }
        let lease = try acquireModalLease()
        _ = sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)

        sut.applicationWillResignActive()
        schedulerMock.executeScheduledBlock()

        #expect(!presenterMock.didCallPresent)
        #expect(sut.modalAttemptPhase == .idle)
        #expect(sut.hasActiveOrPendingModalAttempt)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(releaseNotificationCount == 1)

        sut.applicationDidBecomeActive()
        let retryLease = try acquireModalLease()
        let retryDisposition = sut.presentModalPromptIfNeeded(from: presenterMock, with: retryLease)

        #expect(retryDisposition == .retained)
        #expect(provider.provideModalPromptCallCount == 1)
        #expect(sut.modalAttemptPhase == .committed(retryLease.attemptIdentity))

        schedulerMock.executeScheduledBlock()

        #expect(presenterMock.didCallPresent)
        #expect(sut.modalAttemptPhase == .presentationActive(retryLease.attemptIdentity))
    }

    @available(iOS 16, *)
    @Test("Background Moves Committed Work To Pending And Cancelled Delay Cannot Present", .timeLimit(.minutes(1)))
    func whenAppBackgroundsDuringDelayThenPreparedItemIsRetriedBeforeProviders() throws {
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        let firstLease = try acquireModalLease()
        _ = sut.presentModalPromptIfNeeded(from: presenterMock, with: firstLease)

        sut.applicationWillResignActive()

        #expect(sut.modalAttemptPhase == .committed(firstLease.attemptIdentity))
        #expect(promoQueueLeaseArbiter.snapshot.modalAttemptIdentity == firstLease.attemptIdentity)

        sut.applicationDidEnterBackground()

        #expect(sut.modalAttemptPhase == .idle)
        #expect(sut.hasActiveOrPendingModalAttempt)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(!provider.didCallDidPresentModal)

        schedulerMock.executeScheduledBlock(includingCancelled: true)
        #expect(!presenterMock.didCallPresent)

        sut.applicationDidBecomeActive()
        let retryLease = try acquireModalLease()
        let retryDisposition = sut.presentModalPromptIfNeeded(from: presenterMock, with: retryLease)

        #expect(retryDisposition == .retained)
        #expect(provider.provideModalPromptCallCount == 1)
        #expect(sut.modalAttemptPhase == .committed(retryLease.attemptIdentity))
    }

    @available(iOS 16, *)
    @Test("Disabling Clears Pending Work And Restores Fresh Legacy Evaluation", .timeLimit(.minutes(1)))
    func whenPreparedPromptIsPendingThenDisablingClearsItBeforeLegacyEvaluation() throws {
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        let lease = try acquireModalLease()
        _ = sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)
        sut.applicationDidEnterBackground()

        sut.promoQueueWillTransition(to: .disabled)
        promoQueueLeaseArbiter.invalidateAllLeases()
        sut.promoQueueDidTransition(to: .disabled)
        schedulerMock.executeScheduledBlock(includingCancelled: true)

        #expect(!sut.hasActiveOrPendingModalAttempt)
        #expect(!sut.didPresentModalPromptThisSession)
        #expect(!presenterMock.didCallPresent)
        #expect(provider.provideModalPromptCallCount == 1)

        cooldownManagerMock.cooldownInfoToReturn = .inCoolDown
        sut.presentModalPromptIfNeeded(from: presenterMock)

        #expect(provider.provideModalPromptCallCount == 1)
        #expect(!presenterMock.didCallPresent)

        let freshRoot = UIViewController()
        provider.modalConfigurationToReturn = ModalPromptConfiguration(viewController: freshRoot)
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        sut.presentModalPromptIfNeeded(from: presenterMock)
        schedulerMock.executeScheduledBlock()

        #expect(presenterMock.didCallPresent)
        #expect(presenterMock.capturedViewController === freshRoot)
        #expect(provider.provideModalPromptCallCount == 2)
    }

    @available(iOS 16, *)
    @Test("Invalid Pending Prompt Is Replaced By Its Provider In Priority Order", .timeLimit(.minutes(1)))
    func whenPendingPromptBecomesInvalidThenRetrySelectsReplacementFromSameProvider() throws {
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        let replacementRoot = UIViewController()
        provider.replacementModalConfigurationToReturn = ModalPromptConfiguration(viewController: replacementRoot)
        let lowerPriorityProvider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider, lowerPriorityProvider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        let firstLease = try acquireModalLease()
        _ = sut.presentModalPromptIfNeeded(from: presenterMock, with: firstLease)
        sut.applicationDidEnterBackground()
        provider.isPreparedModalPromptStillValidResult = false
        sut.applicationDidBecomeActive()

        let retryLease = try acquireModalLease()
        let disposition = sut.presentModalPromptIfNeeded(from: presenterMock, with: retryLease)

        #expect(disposition == .retained)
        #expect(provider.provideModalPromptCallCount == 1)
        #expect(provider.isPreparedModalPromptStillValidCallCount == 1)
        #expect(provider.provideReplacementModalPromptCallCount == 1)
        #expect(lowerPriorityProvider.provideModalPromptCallCount == 0)
        #expect(!presenterMock.didCallPresent)
        #expect(sut.modalAttemptPhase == .committed(retryLease.attemptIdentity))
        #expect(promoQueueLeaseArbiter.snapshot.modalAttemptIdentity == retryLease.attemptIdentity)
        #expect(!cooldownManagerMock.didCallRecordLastPromptPresentationTimestamp)

        schedulerMock.executeScheduledBlock(includingCancelled: true)
        schedulerMock.executeScheduledBlock()

        #expect(presenterMock.capturedViewController === replacementRoot)
    }

    @available(iOS 16, *)
    @Test("Invalid Pending Prompt Releases When No Other Provider Is Eligible", .timeLimit(.minutes(1)))
    func whenPendingPromptBecomesInvalidThenRetryDoesNotAskItForAnotherController() throws {
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        provider.isPreparedModalPromptStillValidResult = true
        provider.isRetainedPreparedModalPromptStillValidResult = false
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        let firstLease = try acquireModalLease()
        _ = sut.presentModalPromptIfNeeded(from: presenterMock, with: firstLease)
        sut.applicationDidEnterBackground()
        sut.applicationDidBecomeActive()

        let retryLease = try acquireModalLease()
        let disposition = sut.presentModalPromptIfNeeded(from: presenterMock, with: retryLease)

        #expect(disposition == .released)
        #expect(provider.provideModalPromptCallCount == 1)
        #expect(provider.isPreparedModalPromptStillValidCallCount == 0)
        #expect(provider.isRetainedPreparedModalPromptStillValidCallCount == 1)
        #expect(provider.provideReplacementModalPromptCallCount == 1)
        #expect(!presenterMock.didCallPresent)
        #expect(!sut.hasActiveOrPendingModalAttempt)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
    }

    @available(iOS 16, *)
    @Test("Valid Pending Prompt Is Retried Before Newly Eligible Providers", .timeLimit(.minutes(1)))
    func whenHigherPriorityProviderBecomesEligibleThenValidPendingPromptIsRetriedFirst() throws {
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let higherPriorityProvider = MockModalPromptProvider(shouldReturnPrompt: false)
        let pendingProvider = MockModalPromptProvider()
        let pendingRoot = UIViewController()
        pendingProvider.modalConfigurationToReturn = ModalPromptConfiguration(viewController: pendingRoot)
        sut = ModalPromptCoordinationManager(
            providers: [higherPriorityProvider, pendingProvider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        let firstLease = try acquireModalLease()
        _ = sut.presentModalPromptIfNeeded(from: presenterMock, with: firstLease)
        sut.applicationDidEnterBackground()
        higherPriorityProvider.modalConfigurationToReturn = ModalPromptConfiguration(viewController: UIViewController())
        sut.applicationDidBecomeActive()

        let retryLease = try acquireModalLease()
        let disposition = sut.presentModalPromptIfNeeded(from: presenterMock, with: retryLease)

        #expect(disposition == .retained)
        #expect(higherPriorityProvider.provideModalPromptCallCount == 1)
        #expect(pendingProvider.provideModalPromptCallCount == 1)
        #expect(pendingProvider.isPreparedModalPromptStillValidCallCount == 1)
        #expect(sut.modalAttemptPhase == .committed(retryLease.attemptIdentity))

        schedulerMock.executeScheduledBlock(includingCancelled: true)
        schedulerMock.executeScheduledBlock()

        #expect(presenterMock.capturedViewController === pendingRoot)
    }

    @available(iOS 16, *)
    @Test("Invalid Prepared Prompt Is Discarded Immediately Before Presentation", .timeLimit(.minutes(1)))
    func whenPreparedPromptBecomesInvalidDuringDelayThenItIsNotPresentedOrRetained() throws {
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        var releaseNotificationCount = 0
        sut.setCoordinatedAttemptReleaseHandler {
            releaseNotificationCount += 1
        }
        let lease = try acquireModalLease()
        _ = sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)
        provider.isPreparedModalPromptStillValidResult = false

        schedulerMock.executeScheduledBlock()

        #expect(provider.provideModalPromptCallCount == 1)
        #expect(provider.isPreparedModalPromptStillValidCallCount == 1)
        #expect(!presenterMock.didCallPresent)
        #expect(!provider.didCallDidPresentModal)
        #expect(!cooldownManagerMock.didCallRecordLastPromptPresentationTimestamp)
        #expect(!sut.hasActiveOrPendingModalAttempt)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(releaseNotificationCount == 1)
    }

    @available(iOS 16, *)
    @Test("Changed Provider Eligibility Invalidates Prepared Prompt", .timeLimit(.minutes(1)))
    func whenOnboardingEligibilityChangesDuringDelayThenPreparedPromptIsDiscarded() throws {
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let onboardingStatusProvider = MockContextualOnboardingStatusProvider(hasSeenOnboarding: true)
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: onboardingStatusProvider,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        let lease = try acquireModalLease()
        _ = sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)
        onboardingStatusProvider.hasSeenOnboarding = false

        schedulerMock.executeScheduledBlock()

        #expect(provider.provideModalPromptCallCount == 1)
        #expect(provider.capturedIsOnboardingComplete == false)
        #expect(provider.isPreparedModalPromptStillValidCallCount == 0)
        #expect(!presenterMock.didCallPresent)
        #expect(!sut.hasActiveOrPendingModalAttempt)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
    }

    @available(iOS 16, *)
    @Test("Presentation Route Is Resolved At Fire Time", .timeLimit(.minutes(1)))
    func whenPresentationHostChangesDuringDelayThenCurrentRouteIsUsed() throws {
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        let originalHost = UIViewController()
        let currentHost = UIViewController()
        presenterMock.modalPromptPresentationViewController = originalHost
        let attachmentChecker = MockModalPromptRootAttachmentChecker()
        attachmentChecker.markAttached(originalHost)
        attachmentChecker.markAttached(currentHost)
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock,
            rootAttachmentChecker: attachmentChecker
        )
        let lease = try acquireModalLease()
        _ = sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)
        presenterMock.modalPromptPresentationViewController = currentHost

        schedulerMock.executeScheduledBlock()

        #expect(presenterMock.didCallPresent)
        #expect(attachmentChecker.didQuery(currentHost))
        #expect(!attachmentChecker.didQuery(originalHost))
        #expect(sut.modalAttemptPhase == .presentationActive(lease.attemptIdentity))
        #expect(promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(provider.provideModalPromptCallCount == 1)
    }

    @available(iOS 16, *)
    @Test("In-Flight Presentation Retains Lease Until Late Root Attachment", .timeLimit(.minutes(1)))
    func whenPresentationRelationshipExistsThenLeaseIsRetainedUntilRootAttaches() throws {
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        let exactRoot = UIViewController()
        provider.modalConfigurationToReturn = ModalPromptConfiguration(viewController: exactRoot)
        let attachmentChecker = MockModalPromptRootAttachmentChecker()
        let intendedHost = UIViewController()
        presenterMock.modalPromptPresentationViewController = intendedHost
        attachmentChecker.markAttached(intendedHost)
        presenterMock.shouldCompletePresentation = false
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock,
            rootAttachmentChecker: attachmentChecker
        )
        let lease = try acquireModalLease()
        _ = sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)
        schedulerMock.executeScheduledBlock()

        // UIKit publishes this relationship synchronously when it accepts `present`, before the transition finishes
        // attaching the destination root to a window.
        presenterMock.presentedViewController = exactRoot
        schedulerMock.executeNextMainTurnBlock()

        #expect(sut.modalAttemptPhase == .presentationActive(lease.attemptIdentity))
        #expect(promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(!sut.didActuallyPresentModalPromptThisSession)
        #expect(!sut.reconcilePresentedModal())
        guard case .blockedByModal = promoQueueLeaseArbiter.acquireVisiblePromoLease(for: makeVisiblePromoIdentity()) else {
            Issue.record("Expected the in-flight modal presentation to keep blocking visible promo admission")
            return
        }

        attachmentChecker.markAttached(exactRoot)
        presenterMock.capturedCompletion?()

        #expect(!sut.reconcilePresentedModal())
        #expect(sut.modalAttemptPhase == .presentationActive(lease.attemptIdentity))
        #expect(promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(sut.didActuallyPresentModalPromptThisSession)
        #expect(provider.didPresentModalCallCount == 1)
        #expect(cooldownManagerMock.recordLastPromptPresentationTimestampCallCount == 1)
        guard case .blockedByModal = promoQueueLeaseArbiter.acquireVisiblePromoLease(for: makeVisiblePromoIdentity()) else {
            Issue.record("Expected reconciliation to block visible promo admission with the restored modal lease")
            return
        }
    }

    @available(iOS 16, *)
    @Test("Refused Presentation Releases Lease Without A UIKit Presentation Relationship", .timeLimit(.minutes(1)))
    func whenPresentationHasNoAttachmentOrPresentationRelationshipThenLeaseIsReleased() throws {
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        let exactRoot = UIViewController()
        provider.modalConfigurationToReturn = ModalPromptConfiguration(viewController: exactRoot)
        let attachmentChecker = MockModalPromptRootAttachmentChecker()
        let intendedHost = UIViewController()
        presenterMock.modalPromptPresentationViewController = intendedHost
        attachmentChecker.markAttached(intendedHost)
        presenterMock.shouldCompletePresentation = false
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock,
            rootAttachmentChecker: attachmentChecker
        )
        let modalLease = try acquireModalLease()
        _ = sut.presentModalPromptIfNeeded(from: presenterMock, with: modalLease)
        schedulerMock.executeScheduledBlock()
        schedulerMock.executeNextMainTurnBlock()
        let visibleIdentity = makeVisiblePromoIdentity()
        guard case .acquired(let visibleLease) = promoQueueLeaseArbiter.acquireVisiblePromoLease(for: visibleIdentity) else {
            Issue.record("Expected visible promo admission after UIKit refused the modal presentation")
            return
        }

        #expect(sut.modalAttemptPhase == .idle)
        #expect(sut.hasActiveOrPendingModalAttempt)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(promoQueueLeaseArbiter.snapshot.visiblePromoIdentities == [visibleIdentity])
        #expect(!sut.didActuallyPresentModalPromptThisSession)
        #expect(provider.didPresentModalCallCount == 0)
        #expect(cooldownManagerMock.recordLastPromptPresentationTimestampCallCount == 0)
        _ = visibleLease
    }

    @available(iOS 16, *)
    @Test("Accepted Deferred Completion Accounts After Feature Disable", .timeLimit(.minutes(1)))
    func whenFeatureDisablesAfterUIKitAcceptsThenDeferredCompletionStillRecordsExactlyOnce() throws {
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        let exactRoot = UIViewController()
        provider.modalConfigurationToReturn = ModalPromptConfiguration(viewController: exactRoot)
        let attachmentChecker = MockModalPromptRootAttachmentChecker()
        let intendedHost = UIViewController()
        presenterMock.modalPromptPresentationViewController = intendedHost
        attachmentChecker.markAttached(intendedHost)
        presenterMock.shouldCompletePresentation = false
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock,
            rootAttachmentChecker: attachmentChecker
        )
        let lease = try acquireModalLease()
        _ = sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)
        schedulerMock.executeScheduledBlock()
        attachmentChecker.markAttached(exactRoot)
        let acceptedCompletion = presenterMock.capturedCompletion

        sut.promoQueueWillTransition(to: .disabled)
        promoQueueLeaseArbiter.invalidateAllLeases()
        sut.promoQueueDidTransition(to: .disabled)
        acceptedCompletion?()
        acceptedCompletion?()

        #expect(sut.didActuallyPresentModalPromptThisSession)
        #expect(provider.didPresentModalCallCount == 1)
        #expect(cooldownManagerMock.didCallRecordLastPromptPresentationTimestamp)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
    }

    @available(iOS 16, *)
    @Test("Inactive Next-Turn Verification Is Retried After Becoming Active", .timeLimit(.minutes(1)))
    func whenAppBackgroundsAfterUIKitCallThenUnverifiedLeaseIsRecheckedAfterBecomingActive() throws {
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        presenterMock.shouldCompletePresentation = false
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        var releaseNotificationCount = 0
        sut.setCoordinatedAttemptReleaseHandler {
            releaseNotificationCount += 1
        }
        let lease = try acquireModalLease()
        _ = sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)
        schedulerMock.executeScheduledBlock()

        sut.applicationDidEnterBackground()
        schedulerMock.executeNextMainTurnBlock()

        #expect(sut.modalAttemptPhase == .presentationActive(lease.attemptIdentity))
        #expect(promoQueueLeaseArbiter.snapshot.modalAttemptIdentity == lease.attemptIdentity)
        #expect(releaseNotificationCount == 0)

        sut.applicationDidBecomeActive()
        schedulerMock.executeNextMainTurnBlock()

        #expect(sut.modalAttemptPhase == .idle)
        #expect(sut.hasActiveOrPendingModalAttempt)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(releaseNotificationCount == 1)
    }

    private func acquireModalLease() throws -> PromoQueueModalLease {
        guard case .acquired(let lease) = promoQueueLeaseArbiter.acquireModalLease() else {
            throw TestError.expectedAcquiredLease
        }
        return lease
    }

    private func makeVisiblePromoIdentity() -> VisiblePromoIdentity {
        VisiblePromoIdentity(
            surfaceID: UUID(),
            promoType: .remoteMessage,
            promoID: "message"
        )
    }
}

private enum TestError: Error {
    case expectedAcquiredLease
}

/// A scheduler that drops its scheduled block as soon as it has run.
///
/// `MockModalPromptScheduler` keeps the executed block forever, and that block strongly captures the committed attempt
/// and therefore the modal root. A retention test needs the fixture to stop being an owner so that only the manager
/// remains a candidate.
private final class BlockReleasingModalPromptScheduler: ModalPromptScheduling {
    private var scheduledBlock: (@MainActor () -> Void)?

    @discardableResult
    func schedule(after delay: TimeInterval, execute: @escaping @MainActor () -> Void) -> ModalPromptScheduledTask {
        scheduledBlock = execute
        return ModalPromptScheduledTask { [weak self] in
            self?.scheduledBlock = nil
        }
    }

    @discardableResult
    func scheduleOnNextMainTurn(execute: @escaping @MainActor () -> Void) -> ModalPromptScheduledTask {
        scheduledBlock = execute
        return ModalPromptScheduledTask { [weak self] in
            self?.scheduledBlock = nil
        }
    }

    @MainActor
    func executeAndReleaseScheduledBlock() {
        let block = scheduledBlock
        scheduledBlock = nil
        block?()
    }
}

/// A presenter that withholds the UIKit presentation completion so an attempt can be observed mid-animation.
@MainActor
private final class DeferredCompletionModalPromptPresenter: ModalPromptPresenter {
    var presentedViewController: UIViewController?
    var modalPromptPresentationViewController: UIViewController?
    var onPresent: (() -> Void)?

    private(set) var didCallPresent = false
    private(set) var capturedViewController: UIViewController?
    private var pendingCompletion: (() -> Void)?

    func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)?) {
        didCallPresent = true
        capturedViewController = viewControllerToPresent
        pendingCompletion = completion
        onPresent?()
    }

    func completePendingPresentation() {
        let completion = pendingCompletion
        pendingCompletion = nil
        completion?()
    }
}

/// Models attachment as the set of exact root identities that the test considers attached.
///
/// `queriedRoots` records the root the manager actually asked about, so a test can pin the *subject* of the
/// predicate and not merely its answer — a check resolved against a topmost controller instead of the retained exact
/// root asks about a different object even when both are on screen.
@MainActor
final class MockModalPromptRootAttachmentChecker: ModalPromptRootAttachmentChecking {
    var attachedRoots = Set<ObjectIdentifier>()

    private(set) var queriedRoots: [ObjectIdentifier] = []

    func markAttached(_ root: UIViewController) {
        attachedRoots.insert(ObjectIdentifier(root))
    }

    func didQuery(_ root: UIViewController) -> Bool {
        queriedRoots.contains(ObjectIdentifier(root))
    }

    func isAttached(_ root: UIViewController) -> Bool {
        queriedRoots.append(ObjectIdentifier(root))
        return attachedRoots.contains(ObjectIdentifier(root))
    }
}
