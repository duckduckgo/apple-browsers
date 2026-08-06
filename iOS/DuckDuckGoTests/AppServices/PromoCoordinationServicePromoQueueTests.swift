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

import UIKit
import Foundation
import Combine
import Core
import FeatureFlags_iOS
import PrivacyConfig
import Testing
import PersistenceTestingUtils
@testable import DuckDuckGo

@MainActor
@Suite("Promo Coordination - Service Promo Queue")
final class PromoCoordinationServicePromoQueueTests {
    private let launchSourceManagerMock: MockLaunchSourceManager
    private let contextualOnboardingMock: MockContextualOnboardingStatusProvider
    private let managerMock: MockModalPromptCoordinationManager
    private let presenterMock: MockModalPromptPresenter
    private let featureFlaggerMock: MockFeatureFlagger
    private let promoQueueLeaseArbiter: PromoQueueLeaseArbiter
    private var sut: PromoCoordinationService!

    init() {
        launchSourceManagerMock = MockLaunchSourceManager()
        contextualOnboardingMock = MockContextualOnboardingStatusProvider(hasSeenOnboarding: true)
        managerMock = MockModalPromptCoordinationManager()
        presenterMock = MockModalPromptPresenter()
        featureFlaggerMock = MockFeatureFlagger()
        promoQueueLeaseArbiter = PromoQueueLeaseArbiter()
    }

    @available(iOS 16, *)
    @Test("Debug Snapshot Reports Effective Feature, Manager, And Arbiter State", .timeLimit(.minutes(1)))
    func promoQueueDebugSnapshotReflectsLiveCoordinationState() {
        featureFlaggerMock.enabledFeatureFlags = [.promoPresentationCoordination]
        managerMock.hasPendingModalPrompt = true
        sut = PromoCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )

        let firstIdentity = VisiblePromoIdentity(surfaceID: UUID(), promoType: .remoteMessage, promoID: "first")
        let secondIdentity = VisiblePromoIdentity(surfaceID: UUID(), promoType: .remoteMessage, promoID: "second")
        guard case .acquired(let firstLease) = promoQueueLeaseArbiter.acquireVisiblePromoLease(for: firstIdentity),
              case .acquired(let secondLease) = promoQueueLeaseArbiter.acquireVisiblePromoLease(for: secondIdentity) else {
            Issue.record("Expected visible promo lease acquisition")
            return
        }

        var snapshot = sut.promoQueueDebugSnapshot
        #expect(snapshot.isFeatureEnabled)
        #expect(snapshot.featureState == .enabled)
        #expect(!snapshot.hasModalLease)
        #expect(snapshot.modalAttemptPhase == .idle)
        #expect(snapshot.hasPendingModalPrompt)
        #expect(snapshot.activeVisiblePromoLeaseCount == 2)

        firstLease.release()
        secondLease.release()
        guard case .acquired(let modalLease) = promoQueueLeaseArbiter.acquireModalLease() else {
            Issue.record("Expected modal lease acquisition")
            return
        }
        managerMock.modalAttemptPhase = .evaluating(modalLease.attemptIdentity)

        snapshot = sut.promoQueueDebugSnapshot
        #expect(snapshot.hasModalLease)
        #expect(snapshot.modalAttemptPhase == .evaluating(modalLease.attemptIdentity))
        #expect(snapshot.activeVisiblePromoLeaseCount == 0)
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
        sut = PromoCoordinationService(
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
        sut = PromoCoordinationService(
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
        sut = PromoCoordinationService(
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
        sut = PromoCoordinationService(
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
        sut = PromoCoordinationService(
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
    @Test("Visible Admission Checkpoint Reserves Triggering Surface Before Retrying Other Surface", .timeLimit(.minutes(1)))
    func whenVisibleAdmissionReleasesDetachedModalThenTriggeringSurfaceReservesBeforeRetrySnapshot() {
        featureFlaggerMock.enabledFeatureFlags = [.promoPresentationCoordination]
        sut = PromoCoordinationService(
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
        // The triggering surface takes the one global provisional reservation before the retry snapshot runs, so the
        // other surface must remain blocked until that first admission confirms or withdraws.
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
        #expect(otherTarget.retainedLease == nil)
        #expect(promoQueueLeaseArbiter.snapshot.visiblePromoCount == 1)
    }

    @available(iOS 16, *)
    @Test("Stale Registration Cannot Remove Or Invoke Its Replacement", .timeLimit(.minutes(1)))
    func whenRegistrationIsReplacedThenOldTokenCannotRemoveReplacement() {
        featureFlaggerMock.enabledFeatureFlags = [.promoPresentationCoordination]
        sut = PromoCoordinationService(
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

    @available(iOS 16, *)
    @Test("Failed Pre-Visible Attempt Synchronously Retries Active Registrations", .timeLimit(.minutes(1)))
    func whenManagerNotifiesPreVisibleReleaseThenActiveRegistrationsRetry() {
        featureFlaggerMock.enabledFeatureFlags = [.promoPresentationCoordination]
        sut = PromoCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )
        let target = MockNewTabPagePromoRetryTarget()
        let registration = sut.registerVisiblePromoRetry(for: UUID(), target: target)

        managerMock.coordinatedAttemptReleaseHandler?()

        #expect(target.retryCount == 1)
        _ = registration
    }

    @available(iOS 16, *)
    @Test("Inactive Visible Promo Registrations Are Skipped Until Active", .timeLimit(.minutes(1)))
    func whenManagerNotifiesPreVisibleReleaseThenOnlyActiveRegistrationsRetry() {
        featureFlaggerMock.enabledFeatureFlags = [.promoPresentationCoordination]
        sut = PromoCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )
        let target = MockNewTabPagePromoRetryTarget()
        target.isActiveForPromoRetry = false
        let registration = sut.registerVisiblePromoRetry(for: UUID(), target: target)

        managerMock.coordinatedAttemptReleaseHandler?()
        #expect(target.retryCount == 0)

        target.isActiveForPromoRetry = true
        managerMock.coordinatedAttemptReleaseHandler?()
        #expect(target.retryCount == 1)
        _ = registration
    }

    @available(iOS 16, *)
    @Test("Lifecycle Events Are Forwarded Without Invalidating Arbiter Leases", .timeLimit(.minutes(1)))
    func whenServiceMovesBetweenActiveInactiveAndBackgroundThenManagerOwnsModalMigration() {
        featureFlaggerMock.enabledFeatureFlags = [.promoPresentationCoordination]
        sut = PromoCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )
        let identity = VisiblePromoIdentity(
            surfaceID: UUID(),
            promoType: .remoteMessage,
            promoID: "rmf"
        )
        guard case .acquired(let visibleLease) = promoQueueLeaseArbiter.acquireVisiblePromoLease(for: identity) else {
            Issue.record("Expected visible promo lease acquisition")
            return
        }
        sut.applicationWillResignActive()
        sut.applicationDidBecomeActive()
        sut.applicationWillResignActive()
        sut.applicationDidEnterBackground()

        #expect(managerMock.applicationWillResignActiveCallCount == 2)
        #expect(managerMock.applicationDidEnterBackgroundCallCount == 1)
        #expect(managerMock.applicationDidBecomeActiveCallCount == 1)
        #expect(promoQueueLeaseArbiter.snapshot.visiblePromoIdentities == [identity])
        _ = visibleLease
    }

    // MARK: - Visible Promo Admission Results

    @available(iOS 16, *)
    @Test("Disabled Feature Refuses Visible Promo Admission Without Arbitrating", .timeLimit(.minutes(1)))
    func whenPromoQueueIsDisabledThenVisibleAdmissionIsRefusedWithoutTakingALease() {
        sut = PromoCoordinationService(
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
        sut = PromoCoordinationService(
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
        sut = PromoCoordinationService(
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
        sut = PromoCoordinationService(
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

        sut.releaseVisiblePromoAdmission(lease)

        // Withdrawing a promo has to hand the slot back, so the same surface can admit the next message for it.
        #expect(promoQueueLeaseArbiter.snapshot.visiblePromoIdentities.isEmpty)
        guard case .acquired(let reacquiredLease) = sut.admitVisiblePromo(identity) else {
            Issue.record("Expected the freed surface slot to be re-acquirable")
            return
        }
        #expect(promoQueueLeaseArbiter.snapshot.visiblePromoIdentities == [identity])
        _ = reacquiredLease
    }

    @available(iOS 16, *)
    @Test("NTP Transition Snapshot Callbacks Bracket Lease Invalidation", .timeLimit(.minutes(1)))
    func whenPromoQueueTransitionsThenSnapshotCallbacksBracketInvalidation() async {
        sut = PromoCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )
        let target = MockNewTabPagePromoRetryTarget()
        let registration = sut.registerVisiblePromoRetry(for: UUID(), target: target)
        var callbackStates = [PromoQueueFeatureState]()
        var callbackVisibleLeaseCounts = [Int]()
        target.onWillTransition = { [weak self] _ in
            guard let self else { return }
            callbackStates.append(sut.promoQueueFeatureState)
            callbackVisibleLeaseCounts.append(promoQueueLeaseArbiter.snapshot.visiblePromoCount)
        }
        target.onDidTransition = { [weak self] _ in
            guard let self else { return }
            callbackStates.append(sut.promoQueueFeatureState)
            callbackVisibleLeaseCounts.append(promoQueueLeaseArbiter.snapshot.visiblePromoCount)
        }

        featureFlaggerMock.enabledFeatureFlags = [.promoPresentationCoordination]
        featureFlaggerMock.triggerUpdate()
        await waitForFeatureFlagUpdateDelivery()

        #expect(target.events == ["will-enable", "did-enable", "retry"])
        #expect(callbackStates == [.transitioning(to: .enabled), .transitioning(to: .enabled)])

        target.events.removeAll()
        callbackStates.removeAll()
        callbackVisibleLeaseCounts.removeAll()
        let identity = VisiblePromoIdentity(surfaceID: UUID(), promoType: .remoteMessage, promoID: "rmf")
        guard case .acquired(let lease) = promoQueueLeaseArbiter.acquireVisiblePromoLease(for: identity) else {
            Issue.record("Expected visible promo lease acquisition")
            return
        }

        featureFlaggerMock.enabledFeatureFlags = []
        featureFlaggerMock.triggerUpdate()
        await waitForFeatureFlagUpdateDelivery()

        #expect(target.events == ["will-disable", "did-disable"])
        #expect(callbackStates == [.transitioning(to: .disabled), .transitioning(to: .disabled)])
        #expect(callbackVisibleLeaseCounts == [1, 0])
        _ = (registration, lease)
    }

    // MARK: - Directional Cooldowns

    @available(iOS 16, *)
    @Test("RMF To Modal Cooldown Blocks Before Manager Evaluation And Admits At Boundary", .timeLimit(.minutes(1)))
    func whenRemoteMessageWasConfirmedThenModalWaitsForExactTwentyFourHourBoundary() {
        let confirmedAppearance = Date(timeIntervalSince1970: 1_000_000)
        let clock = PromoQueueCooldownTestClock(now: confirmedAppearance)
        let modalStore = PromoQueueModalHistoryStoreMock()
        let remoteMessageStore = PromoQueueRemoteMessageHistoryStoreMock()
        remoteMessageStore.lastConfirmedRemoteMessageTimestamp = clock.now.timeIntervalSince1970
        let cooldownPolicy = PromoQueueCooldownPolicy(
            modalPresentationStore: modalStore,
            remoteMessagePresentationStore: remoteMessageStore,
            dateProvider: { clock.now }
        )
        featureFlaggerMock.enabledFeatureFlags = [.promoPresentationCoordination]
        launchSourceManagerMock.source = .standard
        presenterMock.presentedViewController = nil
        managerMock.coordinatedPresentationDisposition = .released
        sut = PromoCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            promoQueueCooldownPolicy: cooldownPolicy
        )

        clock.now = clock.now.addingTimeInterval(PromoQueueCooldownPolicy.modalAfterRemoteMessageInterval - 1)
        sut.presentModalPromptIfNeeded(from: presenterMock)

        #expect(managerMock.callCount == 0)
        #expect(managerMock.capturedModalLease == nil)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)

        clock.now = confirmedAppearance.addingTimeInterval(PromoQueueCooldownPolicy.modalAfterRemoteMessageInterval)
        sut.presentModalPromptIfNeeded(from: presenterMock)

        #expect(managerMock.callCount == 1)
        #expect(managerMock.capturedModalLease != nil)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
    }

    @available(iOS 16, *)
    @Test("RMF Cooldown Returns Boundary And Schedules One Exact Retry", .timeLimit(.minutes(1)))
    func whenRemoteMessageAdmissionIsInCooldownThenOneRetryRunsAtExactBoundary() {
        let confirmedAppearance = Date(timeIntervalSince1970: 2_000_000)
        let clock = PromoQueueCooldownTestClock(now: confirmedAppearance)
        let modalStore = PromoQueueModalHistoryStoreMock()
        let remoteMessageStore = PromoQueueRemoteMessageHistoryStoreMock()
        remoteMessageStore.lastConfirmedRemoteMessageTimestamp = confirmedAppearance.timeIntervalSince1970
        let cooldownPolicy = PromoQueueCooldownPolicy(
            modalPresentationStore: modalStore,
            remoteMessagePresentationStore: remoteMessageStore,
            dateProvider: { clock.now }
        )
        let scheduler = PromoQueueCooldownSchedulerMock()
        featureFlaggerMock.enabledFeatureFlags = [.promoPresentationCoordination]
        sut = PromoCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            promoQueueCooldownPolicy: cooldownPolicy,
            promoQueueCooldownScheduler: scheduler
        )
        let surfaceID = UUID()
        let identity = VisiblePromoIdentity(surfaceID: surfaceID, promoType: .remoteMessage, promoID: "rmf")
        let target = MockNewTabPagePromoRetryTarget()
        target.identityToAdmitOnRetry = identity
        let registration = sut.registerVisiblePromoRetry(for: surfaceID, target: target)
        let expectedBoundary = confirmedAppearance.addingTimeInterval(PromoQueueCooldownPolicy.remoteMessageTargetInterval)

        let firstResult = sut.admitVisiblePromo(identity)
        let duplicateResult = sut.admitVisiblePromo(identity)

        guard case .blockedByCooldown(let firstBoundary) = firstResult,
              case .blockedByCooldown(let duplicateBoundary) = duplicateResult else {
            Issue.record("Expected both RMF admission attempts to return the cooldown boundary")
            return
        }
        #expect(firstBoundary == expectedBoundary)
        #expect(duplicateBoundary == expectedBoundary)
        #expect(scheduler.scheduleCallCount == 1)
        #expect(scheduler.pendingDates == [expectedBoundary])
        #expect(sut.promoQueueDebugSnapshot.scheduledRemoteMessageRetry == expectedBoundary)

        clock.now = expectedBoundary
        scheduler.fire(at: expectedBoundary)

        #expect(target.retryCount == 1)
        #expect(target.retainedLease != nil)
        #expect(promoQueueLeaseArbiter.snapshot.visiblePromoIdentities == [identity])
        #expect(scheduler.pendingDates.isEmpty)
        #expect(sut.promoQueueDebugSnapshot.scheduledRemoteMessageRetry == nil)
        _ = registration
    }

    @available(iOS 16, *)
    @Test("Confirming Provisional RMF Serializes Other Surface Until Cooldown Boundary", .timeLimit(.minutes(1)))
    func whenFirstSurfaceConfirmsThenOtherSurfaceRetriesIntoGlobalCooldown() {
        let clock = PromoQueueCooldownTestClock(now: Date(timeIntervalSince1970: 3_000_000))
        let modalStore = PromoQueueModalHistoryStoreMock()
        let remoteMessageStore = PromoQueueRemoteMessageHistoryStoreMock()
        let cooldownPolicy = PromoQueueCooldownPolicy(
            modalPresentationStore: modalStore,
            remoteMessagePresentationStore: remoteMessageStore,
            dateProvider: { clock.now }
        )
        let scheduler = PromoQueueCooldownSchedulerMock()
        featureFlaggerMock.enabledFeatureFlags = [.promoPresentationCoordination]
        sut = PromoCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            promoQueueCooldownPolicy: cooldownPolicy,
            promoQueueCooldownScheduler: scheduler
        )
        let firstIdentity = VisiblePromoIdentity(surfaceID: UUID(), promoType: .remoteMessage, promoID: "first")
        let secondIdentity = VisiblePromoIdentity(surfaceID: UUID(), promoType: .remoteMessage, promoID: "second")
        let secondTarget = MockNewTabPagePromoRetryTarget()
        secondTarget.identityToAdmitOnRetry = secondIdentity
        let secondRegistration = sut.registerVisiblePromoRetry(for: secondIdentity.surfaceID, target: secondTarget)

        guard case .acquired(let firstAdmission) = sut.admitVisiblePromo(firstIdentity) else {
            Issue.record("Expected the first RMF surface to reserve admission")
            return
        }
        guard case .blockedByProvisionalReservation = sut.admitVisiblePromo(secondIdentity) else {
            Issue.record("Expected the second RMF surface to be serialized behind the provisional owner")
            return
        }

        #expect(firstAdmission.confirmAppearance())

        let expectedBoundary = clock.now.addingTimeInterval(PromoQueueCooldownPolicy.remoteMessageTargetInterval)
        #expect(remoteMessageStore.lastConfirmedRemoteMessageTimestamp == clock.now.timeIntervalSince1970)
        #expect(secondTarget.retryCount == 1)
        #expect(secondTarget.retainedLease == nil)
        #expect(scheduler.pendingDates == [expectedBoundary])
        #expect(promoQueueLeaseArbiter.snapshot.visiblePromoIdentities == [firstIdentity])
        #expect(cooldownPolicy.snapshot.provisionalRemoteMessageIdentity == nil)
        _ = secondRegistration
    }

    @available(iOS 16, *)
    @Test("Withdrawing Provisional RMF Immediately Retries Other Surface Without History", .timeLimit(.minutes(1)))
    func whenFirstSurfaceWithdrawsBeforeAppearanceThenOtherSurfaceCanReserveImmediately() {
        let clock = PromoQueueCooldownTestClock(now: Date(timeIntervalSince1970: 4_000_000))
        let modalStore = PromoQueueModalHistoryStoreMock()
        let remoteMessageStore = PromoQueueRemoteMessageHistoryStoreMock()
        let cooldownPolicy = PromoQueueCooldownPolicy(
            modalPresentationStore: modalStore,
            remoteMessagePresentationStore: remoteMessageStore,
            dateProvider: { clock.now }
        )
        let scheduler = PromoQueueCooldownSchedulerMock()
        featureFlaggerMock.enabledFeatureFlags = [.promoPresentationCoordination]
        sut = PromoCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            promoQueueCooldownPolicy: cooldownPolicy,
            promoQueueCooldownScheduler: scheduler
        )
        let firstIdentity = VisiblePromoIdentity(surfaceID: UUID(), promoType: .remoteMessage, promoID: "first")
        let secondIdentity = VisiblePromoIdentity(surfaceID: UUID(), promoType: .remoteMessage, promoID: "second")
        let secondTarget = MockNewTabPagePromoRetryTarget()
        secondTarget.identityToAdmitOnRetry = secondIdentity
        let secondRegistration = sut.registerVisiblePromoRetry(for: secondIdentity.surfaceID, target: secondTarget)

        guard case .acquired(let firstAdmission) = sut.admitVisiblePromo(firstIdentity) else {
            Issue.record("Expected the first RMF surface to reserve admission")
            return
        }
        guard case .blockedByProvisionalReservation = sut.admitVisiblePromo(secondIdentity) else {
            Issue.record("Expected the second RMF surface to be serialized behind the provisional owner")
            return
        }

        sut.releaseVisiblePromoAdmission(firstAdmission)

        #expect(remoteMessageStore.lastConfirmedRemoteMessageTimestamp == nil)
        #expect(secondTarget.retryCount == 1)
        #expect(secondTarget.retainedLease != nil)
        #expect(scheduler.scheduleCallCount == 0)
        #expect(promoQueueLeaseArbiter.snapshot.visiblePromoIdentities == [secondIdentity])
        #expect(cooldownPolicy.snapshot.provisionalRemoteMessageIdentity == secondIdentity)
        _ = secondRegistration
    }

    @available(iOS 16, *)
    @Test("Feature Off Bypasses Cooldown Policy Reservations And Retry Timer", .timeLimit(.minutes(1)))
    func whenFeatureIsOffThenLegacyPathsNeverConsultDirectionalCooldownState() {
        let cooldownPolicy = PromoQueueCooldownPolicySpy()
        let scheduler = PromoQueueCooldownSchedulerMock()
        launchSourceManagerMock.source = .standard
        presenterMock.presentedViewController = nil
        sut = PromoCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            promoQueueCooldownPolicy: cooldownPolicy,
            promoQueueCooldownScheduler: scheduler
        )

        let visibleResult = sut.admitVisiblePromo(
            VisiblePromoIdentity(surfaceID: UUID(), promoType: .remoteMessage, promoID: "rmf")
        )
        sut.presentModalPromptIfNeeded(from: presenterMock)
        _ = sut.promoQueueDebugSnapshot

        guard case .featureDisabled = visibleResult else {
            Issue.record("Expected disabled RMF admission to use the legacy feature-off result")
            return
        }
        #expect(managerMock.didCallPresentModalPromptIfNeeded)
        #expect(managerMock.capturedModalLease == nil)
        #expect(cooldownPolicy.snapshotReadCount == 0)
        #expect(cooldownPolicy.modalEvaluationCount == 0)
        #expect(cooldownPolicy.remoteMessageReservationCount == 0)
        #expect(cooldownPolicy.resetTransientStateCount == 0)
        #expect(scheduler.scheduleCallCount == 0)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(promoQueueLeaseArbiter.snapshot.visiblePromoIdentities.isEmpty)
    }

    @available(iOS 16, *)
    @Test("Live Disable Clears Cooldown Timer And Reservation But Preserves History", .timeLimit(.minutes(1)))
    func whenFeatureIsDisabledLiveThenOnlyTransientCooldownStateIsCleared() async {
        let confirmedModalAppearance = Date(timeIntervalSince1970: 4_900_000)
        let confirmedRemoteMessageAppearance = Date(timeIntervalSince1970: 5_000_000)
        let clock = PromoQueueCooldownTestClock(now: confirmedRemoteMessageAppearance)
        let modalStore = PromoQueueModalHistoryStoreMock()
        modalStore.lastPresentationTimestamp = confirmedModalAppearance.timeIntervalSince1970
        let remoteMessageStore = PromoQueueRemoteMessageHistoryStoreMock()
        remoteMessageStore.lastConfirmedRemoteMessageTimestamp = confirmedRemoteMessageAppearance.timeIntervalSince1970
        let cooldownPolicy = PromoQueueCooldownPolicy(
            modalPresentationStore: modalStore,
            remoteMessagePresentationStore: remoteMessageStore,
            dateProvider: { clock.now }
        )
        let scheduler = PromoQueueCooldownSchedulerMock()
        featureFlaggerMock.enabledFeatureFlags = [.promoPresentationCoordination]
        sut = PromoCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            promoQueueCooldownPolicy: cooldownPolicy,
            promoQueueCooldownScheduler: scheduler
        )
        let blockedIdentity = VisiblePromoIdentity(surfaceID: UUID(), promoType: .remoteMessage, promoID: "blocked")
        let blockedTarget = MockNewTabPagePromoRetryTarget()
        blockedTarget.identityToAdmitOnRetry = blockedIdentity
        let registration = sut.registerVisiblePromoRetry(for: blockedIdentity.surfaceID, target: blockedTarget)

        guard case .blockedByCooldown = sut.admitVisiblePromo(blockedIdentity) else {
            Issue.record("Expected the first surface to establish an RMF cooldown retry")
            return
        }
        let expectedBoundary = confirmedRemoteMessageAppearance.addingTimeInterval(PromoQueueCooldownPolicy.remoteMessageTargetInterval)
        #expect(scheduler.pendingDates == [expectedBoundary])

        clock.now = expectedBoundary
        let provisionalIdentity = VisiblePromoIdentity(surfaceID: UUID(), promoType: .remoteMessage, promoID: "provisional")
        guard case .acquired(let provisionalAdmission) = sut.admitVisiblePromo(provisionalIdentity) else {
            Issue.record("Expected a provisional RMF admission at the inclusive boundary")
            return
        }
        #expect(cooldownPolicy.snapshot.provisionalRemoteMessageIdentity == provisionalIdentity)

        featureFlaggerMock.enabledFeatureFlags = []
        featureFlaggerMock.triggerUpdate()
        await waitForFeatureFlagUpdateDelivery()

        #expect(sut.promoQueueFeatureState == .disabled)
        #expect(sut.promoQueueDebugSnapshot.scheduledRemoteMessageRetry == nil)
        #expect(scheduler.pendingDates.isEmpty)
        #expect(cooldownPolicy.snapshot.provisionalRemoteMessageIdentity == nil)
        #expect(modalStore.lastPresentationTimestamp == confirmedModalAppearance.timeIntervalSince1970)
        #expect(remoteMessageStore.lastConfirmedRemoteMessageTimestamp == confirmedRemoteMessageAppearance.timeIntervalSince1970)
        #expect(!provisionalAdmission.confirmAppearance())
        #expect(promoQueueLeaseArbiter.snapshot.visiblePromoIdentities.isEmpty)
        _ = registration
    }

    // MARK: - Promo Queue Feature State

    @available(iOS 16, *)
    @Test("Initial Promo Queue State Is Seeded Before Subscription Updates", .timeLimit(.minutes(1)))
    func whenPromoQueueIsInitiallyEnabledThenInitialStateIsEnabled() {
        featureFlaggerMock.enabledFeatureFlags = [.promoPresentationCoordination]
        sut = PromoCoordinationService(
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

        sut = PromoCoordinationService(
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
        sut = PromoCoordinationService(
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
        sut = PromoCoordinationService(
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
        sut = PromoCoordinationService(
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
        sut = PromoCoordinationService(
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
        // transition routine's own manager re-adoption may mutate arbiter state while the barrier is up.
        #expect(admissionAttemptsDuringCallbacks == 4)
        #expect(refusalsDuringCallbacks == 4)
        #expect(managerMock.reconcilePresentedModalCallCount == 0)
        #expect(promoQueueLeaseArbiter.snapshot.visiblePromoIdentities.isEmpty)
        #expect(sut.promoQueueFeatureState == .disabled)
    }

    @available(iOS 16, *)
    @Test("Feature State Publisher Emits Enabled Only After Transition Barrier Is Lowered", .timeLimit(.minutes(1)))
    func whenLiveEnableCompletesThenPublishedEnabledStateCanUsePublicAdmission() async {
        sut = PromoCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )
        let identity = VisiblePromoIdentity(surfaceID: UUID(), promoType: .remoteMessage, promoID: "rmf")
        var publishedStates = [PromoQueueFeatureState]()
        var retainedLease: PromoQueueVisiblePromoAdmission?
        let cancellable = sut.promoQueueFeatureStatePublisher.sink { [weak self] state in
            guard let self else { return }
            publishedStates.append(state)
            if state == .enabled, case .acquired(let lease) = sut.admitVisiblePromo(identity) {
                retainedLease = lease
            }
        }

        featureFlaggerMock.enabledFeatureFlags = [.promoPresentationCoordination]
        featureFlaggerMock.triggerUpdate()
        await waitForFeatureFlagUpdateDelivery()

        #expect(publishedStates == [.disabled, .transitioning(to: .enabled), .enabled])
        #expect(retainedLease != nil)
        withExtendedLifetime((cancellable, retainedLease)) {}
    }

    private func waitForFeatureFlagUpdateDelivery() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

}

private final class PromoQueueCooldownTestClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

private final class PromoQueueModalHistoryStoreMock: PromptCooldownStore {
    var lastPresentationTimestamp: TimeInterval?
}

private final class PromoQueueRemoteMessageHistoryStoreMock: PromoQueueRemoteMessageCooldownStoring {
    var lastConfirmedRemoteMessageTimestamp: TimeInterval?
}

@MainActor
private final class PromoQueueCooldownPolicySpy: PromoQueueCooldownPolicying {
    private(set) var snapshotReadCount = 0
    private(set) var modalEvaluationCount = 0
    private(set) var remoteMessageReservationCount = 0
    private(set) var resetTransientStateCount = 0

    var snapshot: PromoQueueCooldownSnapshot {
        snapshotReadCount += 1
        return PromoQueueCooldownSnapshot(
            lastConfirmedModalAppearance: nil,
            lastConfirmedRemoteMessageAppearance: nil,
            nextRemoteMessageEligibility: nil,
            nextModalEligibility: nil,
            provisionalRemoteMessageIdentity: nil
        )
    }

    func evaluateModalAdmission() -> PromoQueueModalCooldownAdmissionResult {
        modalEvaluationCount += 1
        return .eligible
    }

    func reserveRemoteMessageAdmission(for identity: VisiblePromoIdentity) -> PromoQueueRemoteMessageCooldownReservationResult {
        remoteMessageReservationCount += 1
        return .provisionalReservationInProgress
    }

    func resetTransientState() {
        resetTransientStateCount += 1
    }
}

@MainActor
private final class PromoQueueCooldownSchedulerMock: PromoQueueCooldownScheduling {
    private final class Request {
        let date: Date
        let execute: @MainActor () -> Void
        var isPending = true

        init(date: Date, execute: @escaping @MainActor () -> Void) {
            self.date = date
            self.execute = execute
        }
    }

    private var requests = [Request]()

    private(set) var scheduleCallCount = 0

    var pendingDates: [Date] {
        requests.filter(\.isPending).map(\.date)
    }

    func schedule(at date: Date, execute: @escaping @MainActor () -> Void) -> PromoQueueCooldownScheduledTask {
        scheduleCallCount += 1
        let request = Request(date: date, execute: execute)
        requests.append(request)
        return PromoQueueCooldownScheduledTask {
            request.isPending = false
        }
    }

    func fire(at date: Date) {
        guard let request = requests.first(where: { $0.isPending && $0.date == date }) else {
            Issue.record("Expected a pending cooldown retry at \(date)")
            return
        }

        request.isPending = false
        request.execute()
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
    var onWillTransition: (@MainActor (PromoQueueFeatureTargetState) -> Void)?
    var onDidTransition: (@MainActor (PromoQueueFeatureTargetState) -> Void)?
    var events = [String]()
    private(set) var retryCount = 0
    private(set) var retainedLease: PromoQueueVisiblePromoAdmission?

    func retryVisiblePromoAdmission(using admissionHandler: VisiblePromoAdmissionHandler) {
        retryCount += 1
        events.append("retry")
        guard let identityToAdmitOnRetry else {
            return
        }

        if case .acquired(let lease) = admissionHandler(identityToAdmitOnRetry) {
            retainedLease = lease
        }
    }

    func promoQueueWillTransition(to targetState: PromoQueueFeatureTargetState) {
        events.append("will-\(targetState.eventName)")
        onWillTransition?(targetState)
    }

    func promoQueueDidTransition(to targetState: PromoQueueFeatureTargetState) {
        events.append("did-\(targetState.eventName)")
        onDidTransition?(targetState)
    }
}

private extension PromoQueueFeatureTargetState {
    var eventName: String {
        switch self {
        case .disabled: return "disable"
        case .enabled: return "enable"
        }
    }
}
