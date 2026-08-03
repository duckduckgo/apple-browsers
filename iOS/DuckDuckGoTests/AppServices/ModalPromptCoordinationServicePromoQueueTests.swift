//
//  ModalPromptCoordinationServicePromoQueueTests.swift
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
import Combine
import Core
import PrivacyConfig
import Testing
import PersistenceTestingUtils
@testable import DuckDuckGo

@MainActor
@Suite("Modal Prompt Coordination - Service Promo Queue")
final class ModalPromptCoordinationServicePromoQueueTests {
    private let launchSourceManagerMock: MockLaunchSourceManager
    private let contextualOnboardingMock: MockContextualOnboardingStatusProvider
    private let managerMock: MockModalPromptCoordinationManager
    private let presenterMock: MockModalPromptPresenter
    private let featureFlaggerMock: MockFeatureFlagger
    private let promoQueueLeaseArbiter: PromoQueueLeaseArbiter
    private var sut: ModalPromptCoordinationService!

    init() {
        launchSourceManagerMock = MockLaunchSourceManager()
        contextualOnboardingMock = MockContextualOnboardingStatusProvider(hasSeenOnboarding: true)
        managerMock = MockModalPromptCoordinationManager()
        presenterMock = MockModalPromptPresenter()
        featureFlaggerMock = MockFeatureFlagger()
        promoQueueLeaseArbiter = PromoQueueLeaseArbiter()
    }

    // MARK: - Promo Queue Admission

    // The arbiter reclaims a lease whose token has deallocated, so a test that needs a lease to keep holding its slot
    // must bind the token and keep it alive for as long as the assertions depend on it. Discarding it is not inert.

    @available(iOS 16, *)
    @Test("Enabled Modal Evaluation Acquires Lease Before Calling Manager", .timeLimit(.minutes(1)))
    func whenPromoQueueIsEnabledThenManagerReceivesAcquiredLease() {
        featureFlaggerMock.enabledFeatureFlags = [.promoPresentationCoordination]
        launchSourceManagerMock.source = .standard
        presenterMock.presentedViewController = nil
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )

        sut.presentModalPromptIfNeeded(from: presenterMock)

        #expect(managerMock.capturedModalLease != nil)
        #expect(promoQueueLeaseArbiter.snapshot.hasModalLease)
    }

    @available(iOS 16, *)
    @Test("Visible Promo Denial Does Not Reach Modal Manager", .timeLimit(.minutes(1)))
    func whenVisiblePromoOwnsSlotThenModalManagerIsNotCalled() throws {
        featureFlaggerMock.enabledFeatureFlags = [.promoPresentationCoordination]
        launchSourceManagerMock.source = .standard
        presenterMock.presentedViewController = nil
        let visibleIdentity = VisiblePromoIdentity(
            surfaceID: UUID(),
            promoType: .remoteMessage,
            promoID: "rmf"
        )
        guard case .acquired(let visibleLease) = promoQueueLeaseArbiter.acquireVisiblePromoLease(for: visibleIdentity) else {
            Issue.record("Expected visible promo lease acquisition")
            return
        }
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )

        sut.presentModalPromptIfNeeded(from: presenterMock)

        #expect(!managerMock.didCallPresentModalPromptIfNeeded)
        #expect(promoQueueLeaseArbiter.snapshot.visiblePromoIdentities == [visibleIdentity])
        _ = visibleLease
    }

    @available(iOS 16, *)
    @Test("Visible Promo Denial Never Queries A Real Provider Chain", .timeLimit(.minutes(1)))
    func whenVisiblePromoOwnsSlotThenProvidersAreNotQueried() throws {
        featureFlaggerMock.enabledFeatureFlags = [.promoPresentationCoordination]
        launchSourceManagerMock.source = .standard
        presenterMock.presentedViewController = nil
        let provider = MockModalPromptProvider()
        let providers = ModalPromptProviders(
            newAddressBarPicker: provider,
            defaultBrowser: provider,
            winBackOffer: provider,
            subscriptionPromo: provider,
            subscriptionPromoExistingUser: provider,
            whatsNew: provider,
            cookiePopupProtectionOptIn: provider
        )
        let visibleIdentity = VisiblePromoIdentity(
            surfaceID: UUID(),
            promoType: .remoteMessage,
            promoID: "rmf"
        )
        guard case .acquired(let visibleLease) = promoQueueLeaseArbiter.acquireVisiblePromoLease(for: visibleIdentity) else {
            Issue.record("Expected visible promo lease acquisition")
            return
        }
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            keyValueStore: try MockKeyValueFileStore(),
            contextualOnboardingStatusProvider: contextualOnboardingMock,
            privacyConfigManager: MockPrivacyConfigurationManager(),
            providers: providers,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )

        sut.presentModalPromptIfNeeded(from: presenterMock)

        #expect(!provider.didCallProvideModalPrompt)
        #expect(!presenterMock.didCallPresent)
        _ = visibleLease
    }

    @available(iOS 16, *)
    @Test("Disabled Modal Evaluation Uses Legacy Manager Path Without Lease", .timeLimit(.minutes(1)))
    func whenPromoQueueIsDisabledThenLegacyManagerPathIsUnchanged() {
        launchSourceManagerMock.source = .standard
        presenterMock.presentedViewController = nil
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )

        sut.presentModalPromptIfNeeded(from: presenterMock)

        #expect(managerMock.didCallPresentModalPromptIfNeeded)
        #expect(managerMock.capturedModalLease == nil)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(managerMock.reconcilePresentedModalCallCount == 0)
    }

    @available(iOS 16, *)
    @Test("Released Modal Lease Does Not Retry Active Registrations A Second Time", .timeLimit(.minutes(1)))
    func whenManagerReleasesModalLeaseThenActiveRegistrationsRetryOnce() {
        featureFlaggerMock.enabledFeatureFlags = [.promoPresentationCoordination]
        launchSourceManagerMock.source = .standard
        presenterMock.presentedViewController = nil
        managerMock.coordinatedPresentationDisposition = .released
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )
        // Both surfaces are genuinely active but have nothing left to admit, which is what lets the evaluation reach the
        // manager at all: a surface that claimed the slot in the pre-gate pass would block the modal lease instead.
        let firstTarget = MockNewTabPagePromoRetryTarget()
        let secondTarget = MockNewTabPagePromoRetryTarget()
        let firstRegistration = sut.registerVisiblePromoRetry(for: UUID(), target: firstTarget)
        let secondRegistration = sut.registerVisiblePromoRetry(for: UUID(), target: secondTarget)

        sut.presentModalPromptIfNeeded(from: presenterMock)

        // The pre-gate pass is the only pass. A synchronous `.released` decision sees exactly the arbiter state that
        // pass already saw, so retrying on it would refresh RMF selection from the store twice on one foreground.
        #expect(firstTarget.retryCount == 1)
        #expect(secondTarget.retryCount == 1)
        #expect(managerMock.didCallPresentModalPromptIfNeeded)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
        _ = (firstRegistration, secondRegistration)
    }

    @available(iOS 16, *)
    @Test("Visible Admission Checkpoint Admits Triggering Surface Before Retrying Other Surface", .timeLimit(.minutes(1)))
    func whenVisibleAdmissionReleasesDetachedModalThenTriggeringSurfaceWinsBeforeRetrySnapshot() {
        featureFlaggerMock.enabledFeatureFlags = [.promoPresentationCoordination]
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )
        guard case .acquired(let modalLease) = promoQueueLeaseArbiter.acquireModalLease() else {
            Issue.record("Expected modal lease acquisition")
            return
        }
        managerMock.reconcilePresentedModalResult = true
        managerMock.onReconcilePresentedModal = {
            modalLease.release()
        }
        let triggeringSurfaceID = UUID()
        let otherSurfaceID = UUID()
        let triggeringTarget = MockNewTabPagePromoRetryTarget()
        let otherTarget = MockNewTabPagePromoRetryTarget()
        // A real NTP surface keeps the token it was admitted with, and the arbiter reclaims a slot whose token has
        // deallocated, so the retried surface has to keep its token for the slot to stay taken.
        otherTarget.identityToAdmitOnRetry = VisiblePromoIdentity(
            surfaceID: otherSurfaceID,
            promoType: .remoteMessage,
            promoID: "other"
        )
        let triggeringRegistration = sut.registerVisiblePromoRetry(
            for: triggeringSurfaceID,
            target: triggeringTarget
        )
        let otherRegistration = sut.registerVisiblePromoRetry(
            for: otherSurfaceID,
            target: otherTarget
        )
        _ = (triggeringRegistration, otherRegistration)

        let result = sut.admitVisiblePromo(
            VisiblePromoIdentity(surfaceID: triggeringSurfaceID, promoType: .remoteMessage, promoID: "trigger")
        )

        guard case .acquired = result else {
            Issue.record("Expected triggering visible promo to acquire before retries")
            return
        }
        #expect(triggeringTarget.retryCount == 0)
        #expect(otherTarget.retryCount == 1)
        #expect(otherTarget.retainedLease != nil)
        #expect(promoQueueLeaseArbiter.snapshot.visiblePromoCount == 2)
    }

    @available(iOS 16, *)
    @Test("Stale Registration Cannot Remove Or Invoke Its Replacement", .timeLimit(.minutes(1)))
    func whenRegistrationIsReplacedThenOldTokenCannotRemoveReplacement() {
        featureFlaggerMock.enabledFeatureFlags = [.promoPresentationCoordination]
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )
        let surfaceID = UUID()
        let firstTarget = MockNewTabPagePromoRetryTarget()
        let replacementTarget = MockNewTabPagePromoRetryTarget()
        let firstRegistration = sut.registerVisiblePromoRetry(for: surfaceID, target: firstTarget)
        let replacementRegistration = sut.registerVisiblePromoRetry(for: surfaceID, target: replacementTarget)

        firstRegistration.deregister()
        launchSourceManagerMock.source = .URL
        presenterMock.presentedViewController = nil
        sut.presentModalPromptIfNeeded(from: presenterMock)
        _ = replacementRegistration

        #expect(firstTarget.retryCount == 0)
        #expect(replacementTarget.retryCount == 1)
    }

    // MARK: - Visible Promo Admission Results

    @available(iOS 16, *)
    @Test("Disabled Feature Refuses Visible Promo Admission Without Arbitrating", .timeLimit(.minutes(1)))
    func whenPromoQueueIsDisabledThenVisibleAdmissionIsRefusedWithoutTakingALease() {
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )

        let result = sut.admitVisiblePromo(
            VisiblePromoIdentity(surfaceID: UUID(), promoType: .remoteMessage, promoID: "rmf")
        )

        guard case .featureDisabled = result else {
            Issue.record("Expected admission to be refused while the promoPresentationCoordination flag is off")
            return
        }
        // The refusal has to come before arbitration, not through it. An NTP holding a coordination lease with the flag
        // off would make `acquireModalLease` answer `.blockedByVisiblePromos` and silently suppress every launch modal
        // for flag-off users, so the modal slot must still be free afterwards.
        #expect(managerMock.reconcilePresentedModalCallCount == 0)
        #expect(promoQueueLeaseArbiter.snapshot.visiblePromoIdentities.isEmpty)
        guard case .acquired(let modalLease) = promoQueueLeaseArbiter.acquireModalLease() else {
            Issue.record("Expected the modal slot to stay free for the legacy launch modal path")
            return
        }
        _ = modalLease
    }

    @available(iOS 16, *)
    @Test("Coordinated Modal Attempt Blocks Visible Promo Admission", .timeLimit(.minutes(1)))
    func whenModalAttemptOwnsSlotThenVisibleAdmissionIsBlockedByModal() {
        featureFlaggerMock.enabledFeatureFlags = [.promoPresentationCoordination]
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )
        guard case .acquired(let modalLease) = promoQueueLeaseArbiter.acquireModalLease() else {
            Issue.record("Expected modal lease acquisition")
            return
        }

        let result = sut.admitVisiblePromo(
            VisiblePromoIdentity(surfaceID: UUID(), promoType: .remoteMessage, promoID: "rmf")
        )

        guard case .blockedByModal = result else {
            Issue.record("Expected a coordinated modal attempt to block visible promo admission")
            return
        }
        // Admission reconciles the exact modal root before asking the arbiter, so a modal that has already gone away
        // cannot keep blocking; here it has not, so the refusal stands and no visible lease is taken.
        #expect(managerMock.reconcilePresentedModalCallCount == 1)
        #expect(promoQueueLeaseArbiter.snapshot.visiblePromoIdentities.isEmpty)
        _ = modalLease
    }

    @available(iOS 16, *)
    @Test("Occupied Surface Slot Refuses A Second Promo And Names Its Occupant", .timeLimit(.minutes(1)))
    func whenSurfaceSlotIsOccupiedThenVisibleAdmissionCarriesTheOccupyingIdentity() {
        featureFlaggerMock.enabledFeatureFlags = [.promoPresentationCoordination]
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )
        let surfaceID = UUID()
        let occupyingIdentity = VisiblePromoIdentity(surfaceID: surfaceID, promoType: .remoteMessage, promoID: "first")
        guard case .acquired(let occupyingLease) = sut.admitVisiblePromo(occupyingIdentity) else {
            Issue.record("Expected the first visible promo to be admitted")
            return
        }

        let result = sut.admitVisiblePromo(
            VisiblePromoIdentity(surfaceID: surfaceID, promoType: .remoteMessage, promoID: "second")
        )

        guard case .occupiedSurfaceSlot(let reportedIdentity) = result else {
            Issue.record("Expected the occupied surface slot to refuse a second promo")
            return
        }
        // The refusal names the promo that actually holds the slot, not the one that asked for it.
        #expect(reportedIdentity == occupyingIdentity)
        #expect(promoQueueLeaseArbiter.snapshot.visiblePromoIdentities == [occupyingIdentity])
        _ = occupyingLease
    }

    @available(iOS 16, *)
    @Test("Releasing A Visible Promo Lease Frees Its Surface Slot", .timeLimit(.minutes(1)))
    func whenVisiblePromoLeaseIsReleasedThenTheSurfaceSlotIsReacquirable() {
        featureFlaggerMock.enabledFeatureFlags = [.promoPresentationCoordination]
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )
        let identity = VisiblePromoIdentity(surfaceID: UUID(), promoType: .remoteMessage, promoID: "rmf")
        guard case .acquired(let lease) = sut.admitVisiblePromo(identity) else {
            Issue.record("Expected the visible promo to be admitted")
            return
        }
        #expect(promoQueueLeaseArbiter.snapshot.visiblePromoIdentities == [identity])

        sut.releaseVisiblePromoLease(lease)

        // Withdrawing a promo has to hand the slot back, so the same surface can admit the next message for it.
        #expect(promoQueueLeaseArbiter.snapshot.visiblePromoIdentities.isEmpty)
        guard case .acquired(let reacquiredLease) = sut.admitVisiblePromo(identity) else {
            Issue.record("Expected the freed surface slot to be re-acquirable")
            return
        }
        #expect(promoQueueLeaseArbiter.snapshot.visiblePromoIdentities == [identity])
        _ = reacquiredLease
    }

    // MARK: - Promo Queue Feature State

    @available(iOS 16, *)
    @Test("Initial Promo Queue State Is Seeded Before Subscription Updates", .timeLimit(.minutes(1)))
    func whenPromoQueueIsInitiallyEnabledThenInitialStateIsEnabled() {
        featureFlaggerMock.enabledFeatureFlags = [.promoPresentationCoordination]
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )

        #expect(sut.promoQueueFeatureState == .enabled)
        #expect(managerMock.promoQueueWillTransitionTargets.isEmpty)
        #expect(managerMock.promoQueueDidTransitionTargets.isEmpty)
        #expect(featureFlaggerMock.updatesPublisherSubscriptionCount == 1)
    }

    @available(iOS 16, *)
    @Test("Promo Queue State Is Re-read After Feature Subscription Is Established", .timeLimit(.minutes(1)))
    func whenPromoQueueChangesDuringFeatureSubscriptionThenSubscribedStateWins() {
        let featureFlagger = ModalPromptCoordinationSubscriptionHookFeatureFlagger()
        featureFlagger.onUpdatesPublisherSubscription = { [weak featureFlagger] in
            featureFlagger?.isPromoPresentationCoordinationEnabled = true
            featureFlagger?.triggerUpdate()
        }

        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlagger,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )

        #expect(sut.promoQueueFeatureState == .enabled)
        #expect(managerMock.promoQueueWillTransitionTargets == [.enabled])
        #expect(managerMock.promoQueueDidTransitionTargets == [.enabled])
        #expect(featureFlagger.updatesPublisherSubscriptionCount == 1)
        #expect(featureFlagger.promoPresentationCoordinationReadCount == 2)
    }

    @available(iOS 16, *)
    @Test("Promo Queue Feature Updates Are Deduplicated", .timeLimit(.minutes(1)))
    func whenFeatureFlagPublishesDuplicateValuesThenOnlyEffectiveChangesTransition() async {
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )
        let outstandingIdentity = VisiblePromoIdentity(
            surfaceID: UUID(),
            promoType: .remoteMessage,
            promoID: "rmf"
        )
        guard case .acquired(let outstandingLease) = promoQueueLeaseArbiter.acquireVisiblePromoLease(for: outstandingIdentity) else {
            Issue.record("Expected visible promo lease acquisition")
            return
        }

        featureFlaggerMock.triggerUpdate()
        await waitForFeatureFlagUpdateDelivery()
        #expect(managerMock.promoQueueWillTransitionTargets.isEmpty)
        // A deduplicated update never reaches the arbiter, so the outstanding lease survives it.
        #expect(promoQueueLeaseArbiter.snapshot.visiblePromoIdentities == [outstandingIdentity])

        featureFlaggerMock.enabledFeatureFlags = [.promoPresentationCoordination]
        featureFlaggerMock.triggerUpdate()
        await waitForFeatureFlagUpdateDelivery()
        // The one effective change transitions, and a transition invalidates every lease.
        #expect(promoQueueLeaseArbiter.snapshot.visiblePromoIdentities.isEmpty)
        guard case .acquired(let reacquiredLease) = promoQueueLeaseArbiter.acquireVisiblePromoLease(for: outstandingIdentity) else {
            Issue.record("Expected visible promo lease acquisition after the transition")
            return
        }
        featureFlaggerMock.triggerUpdate()
        await waitForFeatureFlagUpdateDelivery()

        #expect(managerMock.promoQueueWillTransitionTargets == [.enabled])
        #expect(managerMock.promoQueueDidTransitionTargets == [.enabled])
        #expect(sut.promoQueueFeatureState == .enabled)
        #expect(featureFlaggerMock.updatesPublisherSubscriptionCount == 1)
        #expect(promoQueueLeaseArbiter.snapshot.visiblePromoIdentities == [outstandingIdentity])
        _ = (outstandingLease, reacquiredLease)
    }

    @available(iOS 16, *)
    @Test("Promo Queue Feature Subscription Is Cancelled With Service", .timeLimit(.minutes(1)))
    func whenServiceIsReleasedThenFeatureUpdatesStop() async {
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )
        weak var weakService = sut

        sut = nil
        #expect(weakService == nil)

        featureFlaggerMock.enabledFeatureFlags = [.promoPresentationCoordination]
        featureFlaggerMock.triggerUpdate()
        await waitForFeatureFlagUpdateDelivery()

        #expect(managerMock.promoQueueWillTransitionTargets.isEmpty)
        #expect(managerMock.promoQueueDidTransitionTargets.isEmpty)
    }

    @available(iOS 16, *)
    @Test("Promo Queue Transition Barrier Rejects Reentrant Modal Evaluation In Both Directions", .timeLimit(.minutes(1)))
    func whenTransitionCallbacksReenterModalEvaluationThenEvaluationWaitsForBarrier() async {
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )
        launchSourceManagerMock.source = .standard
        presenterMock.presentedViewController = nil

        var statesObservedDuringCallbacks = [PromoQueueFeatureState]()
        managerMock.onPromoQueueWillTransition = { [weak self] _ in
            guard let self else { return }
            statesObservedDuringCallbacks.append(sut.promoQueueFeatureState)
            sut.presentModalPromptIfNeeded(from: presenterMock)
        }
        managerMock.onPromoQueueDidTransition = { [weak self] _ in
            guard let self else { return }
            statesObservedDuringCallbacks.append(sut.promoQueueFeatureState)
            sut.presentModalPromptIfNeeded(from: presenterMock)
        }

        featureFlaggerMock.enabledFeatureFlags = [.promoPresentationCoordination]
        featureFlaggerMock.triggerUpdate()
        await waitForFeatureFlagUpdateDelivery()
        featureFlaggerMock.enabledFeatureFlags = []
        featureFlaggerMock.triggerUpdate()
        await waitForFeatureFlagUpdateDelivery()

        #expect(managerMock.callCount == 0)
        #expect(
            statesObservedDuringCallbacks == [
                .transitioning(to: .enabled),
                .transitioning(to: .enabled),
                .transitioning(to: .disabled),
                .transitioning(to: .disabled),
            ]
        )
        #expect(sut.promoQueueFeatureState == .disabled)
    }

    @available(iOS 16, *)
    @Test("Promo Queue Transition Barrier Rejects Visible Promo Admission In Both Directions", .timeLimit(.minutes(1)))
    func whenTransitionCallbacksAdmitVisiblePromoThenAdmissionWaitsForBarrier() async {
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )

        var admissionAttemptsDuringCallbacks = 0
        var refusalsDuringCallbacks = 0
        let admitDuringTransition: @MainActor (PromoQueueFeatureTargetState) -> Void = { [weak self] _ in
            guard let self else { return }
            admissionAttemptsDuringCallbacks += 1
            let result = sut.admitVisiblePromo(
                VisiblePromoIdentity(surfaceID: UUID(), promoType: .remoteMessage, promoID: "rmf")
            )
            if case .unavailableDuringTransition = result {
                refusalsDuringCallbacks += 1
            }
        }
        managerMock.onPromoQueueWillTransition = admitDuringTransition
        managerMock.onPromoQueueDidTransition = admitDuringTransition

        featureFlaggerMock.enabledFeatureFlags = [.promoPresentationCoordination]
        featureFlaggerMock.triggerUpdate()
        await waitForFeatureFlagUpdateDelivery()
        featureFlaggerMock.enabledFeatureFlags = []
        featureFlaggerMock.triggerUpdate()
        await waitForFeatureFlagUpdateDelivery()

        // Both callbacks of both transitions re-enter admission, and every one of the four must be refused: only the
        // transition routine's own re-adoption and retry steps may mutate arbiter state while the barrier is up.
        #expect(admissionAttemptsDuringCallbacks == 4)
        #expect(refusalsDuringCallbacks == 4)
        #expect(managerMock.reconcilePresentedModalCallCount == 0)
        #expect(promoQueueLeaseArbiter.snapshot.visiblePromoIdentities.isEmpty)
        #expect(sut.promoQueueFeatureState == .disabled)
    }

    @available(iOS 16, *)
    @Test("Enable Retry Keeps Public Barrier Up And Uses Transition Admission", .timeLimit(.minutes(1)))
    func whenEnablingRetriesActiveVisiblePromoThenOnlyTransitionAdmissionCanAcquire() async {
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )
        launchSourceManagerMock.source = .standard
        presenterMock.presentedViewController = nil

        let surfaceID = UUID()
        let publicIdentity = VisiblePromoIdentity(
            surfaceID: UUID(),
            promoType: .remoteMessage,
            promoID: "public-reentrant"
        )
        let transitionIdentity = VisiblePromoIdentity(
            surfaceID: surfaceID,
            promoType: .remoteMessage,
            promoID: "transition-retry"
        )
        let retryTarget = MockNewTabPagePromoRetryTarget()
        var stateObservedDuringRetry: PromoQueueFeatureState?
        var publicAdmissionResult = VisiblePromoAdmissionResult.featureDisabled
        retryTarget.identityToAdmitOnRetry = transitionIdentity
        retryTarget.onRetry = { [weak self] in
            guard let self else { return }
            stateObservedDuringRetry = sut.promoQueueFeatureState
            publicAdmissionResult = sut.admitVisiblePromo(publicIdentity)
            sut.presentModalPromptIfNeeded(from: presenterMock)
        }
        let registration = sut.registerVisiblePromoRetry(for: surfaceID, target: retryTarget)

        featureFlaggerMock.enabledFeatureFlags = [.promoPresentationCoordination]
        featureFlaggerMock.triggerUpdate()
        await waitForFeatureFlagUpdateDelivery()

        #expect(retryTarget.retryCount == 1)
        #expect(stateObservedDuringRetry == .transitioning(to: .enabled))
        guard case .unavailableDuringTransition = publicAdmissionResult else {
            Issue.record("Expected public visible-promo admission to remain blocked during the retry callback")
            return
        }
        #expect(managerMock.callCount == 0)
        #expect(managerMock.reconcilePresentedModalCallCount == 1)
        #expect(retryTarget.retainedLease != nil)
        #expect(promoQueueLeaseArbiter.snapshot.visiblePromoIdentities == [transitionIdentity])
        #expect(sut.promoQueueFeatureState == .enabled)
        _ = registration
    }

    private func waitForFeatureFlagUpdateDelivery() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

}

private final class ModalPromptCoordinationSubscriptionHookFeatureFlagger: FeatureFlagger {
    var internalUserDecider: InternalUserDecider = DefaultInternalUserDecider(store: MockInternalUserStoring())
    var localOverrides: FeatureFlagLocalOverriding?
    var allActiveExperiments: Experiments = [:]
    var isPromoPresentationCoordinationEnabled = false
    var onUpdatesPublisherSubscription: (() -> Void)?
    private(set) var updatesPublisherSubscriptionCount = 0
    private(set) var promoPresentationCoordinationReadCount = 0

    private let updatesSubject = PassthroughSubject<Void, Never>()

    var updatesPublisher: AnyPublisher<Void, Never> {
        Deferred { [weak self] () -> AnyPublisher<Void, Never> in
            guard let self else {
                return Empty(completeImmediately: false).eraseToAnyPublisher()
            }

            updatesPublisherSubscriptionCount += 1
            onUpdatesPublisherSubscription?()
            return updatesSubject.eraseToAnyPublisher()
        }
        .eraseToAnyPublisher()
    }

    func triggerUpdate() {
        updatesSubject.send()
    }

    func isFeatureOn<Flag: FeatureFlagDescribing>(for featureFlag: Flag, allowOverride: Bool) -> Bool {
        guard featureFlag.rawValue == FeatureFlag.promoPresentationCoordination.rawValue else {
            return false
        }

        promoPresentationCoordinationReadCount += 1
        return isPromoPresentationCoordinationEnabled
    }

    func resolveCohort<Flag: FeatureFlagDescribing>(
        for featureFlag: Flag,
        allowOverride: Bool
    ) -> (any FeatureFlagCohortDescribing)? {
        nil
    }

    func assignedCohort<Flag: FeatureFlagDescribing>(
        for featureFlag: Flag,
        allowOverride: Bool
    ) -> (any FeatureFlagCohortDescribing)? {
        nil
    }
}

@MainActor
private final class MockNewTabPagePromoRetryTarget: NewTabPagePromoRetrying {
    var isActiveForPromoRetry = true
    var identityToAdmitOnRetry: VisiblePromoIdentity?
    var onRetry: (@MainActor () -> Void)?
    private(set) var retryCount = 0
    private(set) var retainedLease: PromoQueueVisiblePromoLease?

    func retryVisiblePromoAdmission(using admissionHandler: VisiblePromoAdmissionHandler) {
        retryCount += 1
        onRetry?()
        guard let identityToAdmitOnRetry else {
            return
        }

        if case .acquired(let lease) = admissionHandler(identityToAdmitOnRetry) {
            retainedLease = lease
        }
    }
}
