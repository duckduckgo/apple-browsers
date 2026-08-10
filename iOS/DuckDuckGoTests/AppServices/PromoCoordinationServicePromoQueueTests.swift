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
import Core
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
    private let promoQueueLeaseArbiter: PromoQueueLeaseArbiter
    private var sut: PromoCoordinationService!

    init() {
        launchSourceManagerMock = MockLaunchSourceManager()
        contextualOnboardingMock = MockContextualOnboardingStatusProvider(hasSeenOnboarding: true)
        managerMock = MockModalPromptCoordinationManager()
        presenterMock = MockModalPromptPresenter()
        promoQueueLeaseArbiter = PromoQueueLeaseArbiter()
    }

    // MARK: - Promo Queue Admission

    // The arbiter reclaims a lease whose token has deallocated, so a test that needs a lease to keep holding its slot
    // must bind the token and keep it alive for as long as the assertions depend on it. Discarding it is not inert.

    @available(iOS 16, *)
    @Test("Enabled Modal Evaluation Acquires Lease Before Calling Manager", .timeLimit(.minutes(1)))
    func whenPromoQueueIsEnabledThenManagerReceivesAcquiredLease() {
        launchSourceManagerMock.source = .standard
        presenterMock.presentedViewController = nil
        sut = PromoCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            promoCoordinationMode: .coordinated,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )

        sut.presentModalPromptIfNeeded(from: presenterMock)

        #expect(managerMock.capturedModalLease != nil)
        #expect(promoQueueLeaseArbiter.snapshot.hasModalLease)
    }

    @available(iOS 16, *)
    @Test("Visible Promo Denial Does Not Reach Modal Manager", .timeLimit(.minutes(1)))
    func whenVisiblePromoOwnsSlotThenModalManagerIsNotCalled() throws {
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
            promoCoordinationMode: .coordinated,
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
            promoCoordinationMode: .coordinated,
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
            promoCoordinationMode: .legacy,
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
        launchSourceManagerMock.source = .standard
        presenterMock.presentedViewController = nil
        managerMock.coordinatedPresentationDisposition = .released
        sut = PromoCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            promoCoordinationMode: .coordinated,
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
        sut = PromoCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            promoCoordinationMode: .coordinated,
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
        sut = PromoCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            promoCoordinationMode: .coordinated,
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
        sut = PromoCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            promoCoordinationMode: .coordinated,
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
        sut = PromoCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            promoCoordinationMode: .coordinated,
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
        sut = PromoCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            promoCoordinationMode: .coordinated,
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
            promoCoordinationMode: .legacy,
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
        sut = PromoCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            promoCoordinationMode: .coordinated,
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
        sut = PromoCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            promoCoordinationMode: .coordinated,
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
        sut = PromoCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            promoCoordinationMode: .coordinated,
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

}

@MainActor
private final class MockNewTabPagePromoRetryTarget: NewTabPagePromoRetrying {
    var isActiveForPromoRetry = true
    var identityToAdmitOnRetry: VisiblePromoIdentity?
    var events = [String]()
    private(set) var retryCount = 0
    private(set) var retainedLease: PromoQueueVisiblePromoLease?

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

}
