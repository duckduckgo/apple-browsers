//
//  ModalPromptCoordinationManagerIntegrationTests.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import FoundationExtensions
import Testing
import Persistence
import PersistenceTestingUtils
@testable import DuckDuckGo

@MainActor
@Suite("Modal Prompt Coordination - Integration Tests")
final class ModalPromptCoordinationManagerIntegrationTests {
    private let timeTraveller: TimeTraveller
    private let keyValueStore: MockKeyValueFileStore
    private let cooldownStore: PromptCooldownKeyValueFilesStore
    private let cooldownIntervalProvider: MockPromptCooldownIntervalProvider
    private let cooldownManager: PromptCooldownManager
    private let schedulerMock: ImmediateScheduler
    private let presenterMock: MockModalPromptPresenter
    private let promoQueueLeaseArbiter: PromoQueueLeaseArbiter
    private var sut: ModalPromptCoordinationManager!

    init() throws {
        let startDate = Date(timeIntervalSince1970: 1761091200) // 22 October 2025 12:00:00 AM GMT
        timeTraveller = TimeTraveller(date: startDate)
        keyValueStore = try MockKeyValueFileStore()
        cooldownStore = PromptCooldownKeyValueFilesStore(
            keyValueStore: keyValueStore,
            eventMapper: .init(mapping: { _, _, _, _ in })
        )
        cooldownIntervalProvider = MockPromptCooldownIntervalProvider() // Cooldown Interval 24h
        cooldownManager = PromptCooldownManager(
            presentationStore: cooldownStore,
            cooldownIntervalProvider: cooldownIntervalProvider,
            dateProvider: timeTraveller.getDate
        )
        schedulerMock = ImmediateScheduler()
        presenterMock = MockModalPromptPresenter()
        promoQueueLeaseArbiter = PromoQueueLeaseArbiter()
    }

    @Test("Check Is In Cooldown After Presenting Prompt")
    func whenPromptIsPresentedThenIsInCooldown() {
        // GIVEN
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManager,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        #expect(!cooldownManager.isInCooldownPeriod)

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN
        #expect(cooldownManager.isInCooldownPeriod)
    }

    @Test(
        "Check Modal Is Blocked During Cooldown Period",
        arguments: [1, 6, 12, 18, 23]  // Hours after first presentation
    )
    func whenWithinCooldownPeriodThenModalIsBlocked(hoursAfterPresentation: Int) {
        // GIVEN
        cooldownStore.lastPresentationTimestamp = timeTraveller.getDate().timeIntervalSince1970
        let firstProvider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [firstProvider],
            cooldownManager: cooldownManager,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        #expect(cooldownManager.isInCooldownPeriod)

        // WHEN - Advance time but stay within 24-hour cooldown
        timeTraveller.advanceBy(.hours(hoursAfterPresentation))
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN
        #expect(cooldownManager.isInCooldownPeriod)
        #expect(!firstProvider.didCallProvideModalPrompt)
        #expect(!firstProvider.didCallDidPresentModal)
        #expect(!presenterMock.didCallPresent)
    }

    @Test(
        "Check Modal Is Allowed After Cooldown Period Expires",
        arguments: [24, 25, 30, 48, 72]  // Hours after first presentation
    )
    func whenAfterCooldownPeriodThenModalIsAllowed(hoursAfterPresentation: Int) {
        // GIVEN
        cooldownStore.lastPresentationTimestamp = timeTraveller.getDate().timeIntervalSince1970
        let firstProvider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [firstProvider],
            cooldownManager: cooldownManager,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        #expect(cooldownManager.isInCooldownPeriod)

        // WHEN - Advance time past cooldown period
        timeTraveller.advanceBy(.hours(hoursAfterPresentation))

        // THEN
        #expect(!cooldownManager.isInCooldownPeriod)

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)
        #expect(firstProvider.didCallProvideModalPrompt)
        #expect(presenterMock.didCallPresent)
        #expect(firstProvider.didCallDidPresentModal)
    }

    // MARK: - Multiple Presentations Over Time

    @Test("Check Multiple Modals Can Be Presented After Cooldown Interval")
    func whenCooldownIntervalPassAllModalArePresented() {
        // GIVEN
        let provider1 = MockModalPromptProvider()
        let provider2 = MockModalPromptProvider()
        let provider3 = MockModalPromptProvider()

        sut = ModalPromptCoordinationManager(
            providers: [provider1, provider2, provider3],
            cooldownManager: cooldownManager,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )

        // WHEN presenting the first prompt
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN first prompt is presented
        #expect(provider1.didCallDidPresentModal)
        #expect(!provider2.didCallDidPresentModal)
        #expect(!provider3.didCallDidPresentModal)
        #expect(cooldownManager.isInCooldownPeriod)

        // Advance time to 24 hours after presentation (cooldown expired)
        timeTraveller.advanceBy(.hours(24))
        #expect(!cooldownManager.isInCooldownPeriod)

        // Simulate first provider does not have a modal to show
        provider1.modalConfigurationToReturn = nil
        provider1.reset()

        // WHEN presenting the modal again
        provider1.modalConfigurationToReturn = nil
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN second prompt is presented
        #expect(!provider1.didCallDidPresentModal)
        #expect(provider2.didCallDidPresentModal)
        #expect(!provider3.didCallDidPresentModal)
        #expect(cooldownManager.isInCooldownPeriod)

        // Simulate second provider does not have a modal to show
        provider2.modalConfigurationToReturn = nil
        provider2.reset()

        // Advance time to 24 hours after presentation (cooldown expired)
        timeTraveller.advanceBy(.hours(24))
        #expect(!cooldownManager.isInCooldownPeriod)

        // WHEN presenting the first prompt
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN third prompt is presented
        #expect(!provider1.didCallDidPresentModal)
        #expect(!provider2.didCallDidPresentModal)
        #expect(provider3.didCallDidPresentModal)
        #expect(cooldownManager.isInCooldownPeriod)
    }

    @Test("Check Prompt Is Not Presented If Presented During Cooldown")
    func whenModalIsPresentedTooSoonThenItIsNotPresented() {
        // GIVEN
        let provider1 = MockModalPromptProvider()
        let provider2 = MockModalPromptProvider()

        sut = ModalPromptCoordinationManager(
            providers: [provider1, provider2],
            cooldownManager: cooldownManager,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )

        // WHEN presenting the first modal
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN
        #expect(provider1.didCallDidPresentModal)
        #expect(!provider2.didCallDidPresentModal)
        #expect(presenterMock.didCallPresent)
        #expect(cooldownManager.isInCooldownPeriod)

        // Advance time to 12 hours later (still in cooldown)
        timeTraveller.advanceBy(.hours(12))
        #expect(cooldownManager.isInCooldownPeriod)

        // Simulate first provider does not have modal to show
        provider1.reset()
        provider1.modalConfigurationToReturn = nil
        presenterMock.reset()

        // WHEN trying to present again during cooldown
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN no modals are presented
        #expect(!provider1.didCallDidPresentModal)
        #expect(!provider2.didCallDidPresentModal)
        #expect(!presenterMock.didCallPresent)
    }

    // MARK: - Cooldown Info Integration

    @Test("Check Cooldown Info Reports Correct Dates After Presentation")
    func whenModalPresentedThenCooldownInfoIsCorrect() {
        // GIVEN
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManager,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        let presentationTime = timeTraveller.getDate()

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN
        let info = cooldownManager.cooldownInfo
        #expect(info.isInCooldownPeriod)
        #expect(info.lastPresentationDate == presentationTime)
        #expect(info.nextPresentationDate == presentationTime.addingTimeInterval(.hours(24)))
    }

    @Test("Check Cooldown Info Updates After Time Advances")
    func whenTimeAdvancesThenCooldownInfoReflectsNewState() {
        // GIVEN
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManager,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        var lastPresentationTime = timeTraveller.getDate()
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // Advance time to 12 hours later (still in cooldown)
        timeTraveller.advanceBy(.hours(12))

        // WHEN
        let infoWhileInCooldown = cooldownManager.cooldownInfo

        // THEN
        #expect(infoWhileInCooldown.isInCooldownPeriod)
        #expect(infoWhileInCooldown.lastPresentationDate == lastPresentationTime)
        #expect(infoWhileInCooldown.nextPresentationDate == lastPresentationTime.addingTimeInterval(.hours(24)))

        // Advance time to 24 hours after presentation (cooldown expired)
        timeTraveller.advanceBy(.hours(12))

        // WHEN
        let infoAfterCooldownBeforePresentingModalAgain = cooldownManager.cooldownInfo

        // THEN
        #expect(!infoAfterCooldownBeforePresentingModalAgain.isInCooldownPeriod)
        #expect(infoAfterCooldownBeforePresentingModalAgain.lastPresentationDate == lastPresentationTime)
        #expect(infoAfterCooldownBeforePresentingModalAgain.nextPresentationDate == lastPresentationTime.addingTimeInterval(.hours(24)))

        // WHEN
        lastPresentationTime = timeTraveller.getDate()
        sut.presentModalPromptIfNeeded(from: presenterMock)

        let infoAfterCooldownAfterPresentingModalAgain = cooldownManager.cooldownInfo

        // THEN
        #expect(infoAfterCooldownAfterPresentingModalAgain.isInCooldownPeriod)
        #expect(infoAfterCooldownAfterPresentingModalAgain.lastPresentationDate == lastPresentationTime)
        #expect(infoAfterCooldownAfterPresentingModalAgain.nextPresentationDate == lastPresentationTime.addingTimeInterval(.hours(24)))
    }

    // MARK: - Persistence Tests

    @Test("Check Cooldown Persists In Storage")
    func whenModalPresentedThenTimestampIsPersisted() throws {
        // GIVEN
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManager,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        let presentationTime = timeTraveller.getDate()

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN
        let storedTimestamp = try keyValueStore.object(forKey: PromptCooldownKeyValueFilesStore.StorageKey.lastPromptShownTimestamp) as? TimeInterval
        #expect(storedTimestamp == presentationTime.timeIntervalSince1970)
    }

    @Test("Check Cooldown Is Read From Storage")
    func whenManagerCreatedThenCooldownIsReadFromStorage() throws {
        // GIVEN
        #expect(!cooldownManager.isInCooldownPeriod)

        // WHEN
        let pastTime = timeTraveller.getDate().addingTimeInterval(-.hours(12))
        try keyValueStore.set(pastTime.timeIntervalSince1970, forKey: PromptCooldownKeyValueFilesStore.StorageKey.lastPromptShownTimestamp)

        // THEN
        #expect(cooldownManager.isInCooldownPeriod)
        #expect(cooldownManager.cooldownInfo.lastPresentationDate == pastTime)
    }

    // MARK: - Promo Queue Lease Integration

    @available(iOS 16, *)
    @Test("Coordinated Presentation Retains Lease And Records Cooldown", .timeLimit(.minutes(1)))
    func whenCoordinatedPromptPresentsThenLeaseAndPersistentCooldownAreRetained() throws {
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManager,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        guard case .acquired(let lease) = promoQueueLeaseArbiter.acquireModalLease() else {
            Issue.record("Expected modal lease acquisition")
            return
        }

        let disposition = sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)

        #expect(disposition == .retained)
        #expect(promoQueueLeaseArbiter.snapshot.modalAttemptIdentity == lease.attemptIdentity)
        #expect(sut.modalAttemptPhase == .presentationActive(lease.attemptIdentity))
        #expect(sut.didActuallyPresentModalPromptThisSession)
        #expect(cooldownManager.isInCooldownPeriod)
        let storedTimestamp = try keyValueStore.object(
            forKey: PromptCooldownKeyValueFilesStore.StorageKey.lastPromptShownTimestamp
        ) as? TimeInterval
        #expect(storedTimestamp == timeTraveller.getDate().timeIntervalSince1970)
    }

    @available(iOS 16, *)
    @Test("Coordinated Cooldown Denial Releases Lease Before Provider Evaluation", .timeLimit(.minutes(1)))
    func whenPersistentCooldownBlocksCoordinatedAttemptThenLeaseIsReleased() {
        cooldownStore.lastPresentationTimestamp = timeTraveller.getDate().timeIntervalSince1970
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManager,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        guard case .acquired(let lease) = promoQueueLeaseArbiter.acquireModalLease() else {
            Issue.record("Expected modal lease acquisition")
            return
        }

        let disposition = sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)

        #expect(disposition == .released)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(!provider.didCallProvideModalPrompt)
        #expect(!presenterMock.didCallPresent)
    }

    // MARK: - Promo Queue Cross-Surface Integration

    @Test("Foreground Retries Active NTP Before Modal Evaluation")
    func whenActiveNTPRetriesOnForegroundThenItAcquiresBeforeModalProviderEvaluation() {
        let provider = MockModalPromptProvider()
        let manager = makeManager(providers: [provider])
        let service = makeService(manager: manager, promoQueueEnabled: true)
        let surfaceID = UUID()
        let retryTarget = IntegrationPromoRetryTarget()
        var visibleLease: PromoQueueVisiblePromoLease?
        retryTarget.onRetry = { admissionHandler in
            let identity = VisiblePromoIdentity(
                surfaceID: surfaceID,
                promoType: .remoteMessage,
                promoID: "rmf"
            )
            guard case .acquired(let lease) = admissionHandler(identity) else {
                Issue.record("Expected foreground NTP retry to acquire the visible promo lease")
                return
            }
            visibleLease = lease
        }
        let registration = service.registerVisiblePromoRetry(
            for: surfaceID,
            target: retryTarget
        )

        service.applicationDidBecomeActive()
        service.presentModalPromptIfNeeded(from: presenterMock)

        #expect(retryTarget.retryCount == 1)
        #expect(visibleLease != nil)
        #expect(promoQueueLeaseArbiter.snapshot.visiblePromoCount == 1)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(!provider.didCallProvideModalPrompt)
        #expect(!provider.didCallDidPresentModal)
        #expect(!presenterMock.didCallPresent)
        #expect(!cooldownManager.isInCooldownPeriod)
        _ = registration
    }

    @Test("Exact Root Checkpoint Admits Triggering NTP Before Retrying Other Surfaces")
    func whenExactModalRootDetachesThenTriggeringNTPAdmitsBeforeOtherActiveNTPsRetry() {
        let scheduler = MockModalPromptScheduler()
        let attachmentChecker = IntegrationModalRootAttachmentChecker()
        let presentationHost = UIViewController()
        attachmentChecker.attach(presentationHost)
        let presenter = IntegrationAttachingModalPromptPresenter(
            presentationHost: presentationHost,
            attachmentChecker: attachmentChecker
        )
        let exactRoot = UIViewController()
        let provider = MockModalPromptProvider()
        provider.modalConfigurationToReturn = ModalPromptConfiguration(viewController: exactRoot)
        let manager = makeManager(
            providers: [provider],
            scheduler: scheduler,
            attachmentChecker: attachmentChecker
        )
        let service = makeService(manager: manager, promoQueueEnabled: true)

        service.presentModalPromptIfNeeded(from: presenter)

        let firstSurfaceID = UUID()
        let secondSurfaceID = UUID()
        let committedAdmission = service.admitVisiblePromo(
            VisiblePromoIdentity(
                surfaceID: firstSurfaceID,
                promoType: .remoteMessage,
                promoID: "first"
            )
        )
        #expect(committedAdmission.isBlockedByModal)
        guard case .committed = manager.modalAttemptPhase else {
            Issue.record("Expected the modal attempt to remain committed during the scheduling window")
            return
        }

        scheduler.executeScheduledBlock()
        scheduler.executeNextMainTurnBlock()

        #expect(presenter.didCallPresent)
        guard case .presentationActive = manager.modalAttemptPhase else {
            Issue.record("Expected the attached exact root to own the presentation-active modal lease")
            return
        }

        service.applicationDidEnterBackground()
        #expect(promoQueueLeaseArbiter.snapshot.hasModalLease)
        guard case .presentationActive = manager.modalAttemptPhase else {
            Issue.record("Expected backgrounding to preserve the presentation-active modal lease")
            return
        }
        service.applicationDidBecomeActive()

        let nestedChild = UIViewController()
        attachmentChecker.attach(nestedChild, to: exactRoot)
        let nestedFlowAdmission = service.admitVisiblePromo(
            VisiblePromoIdentity(
                surfaceID: firstSurfaceID,
                promoType: .remoteMessage,
                promoID: "first"
            )
        )
        #expect(nestedFlowAdmission.isBlockedByModal)
        #expect(promoQueueLeaseArbiter.snapshot.hasModalLease)

        let firstTarget = IntegrationPromoRetryTarget()
        let secondTarget = IntegrationPromoRetryTarget()
        var secondVisibleLease: PromoQueueVisiblePromoLease?
        secondTarget.onRetry = { admissionHandler in
            let identity = VisiblePromoIdentity(
                surfaceID: secondSurfaceID,
                promoType: .remoteMessage,
                promoID: "second"
            )
            guard case .acquired(let lease) = admissionHandler(identity) else {
                Issue.record("Expected the other active NTP to acquire during the guarded retry snapshot")
                return
            }
            secondVisibleLease = lease
        }
        let firstRegistration = service.registerVisiblePromoRetry(
            for: firstSurfaceID,
            target: firstTarget
        )
        let secondRegistration = service.registerVisiblePromoRetry(
            for: secondSurfaceID,
            target: secondTarget
        )

        attachmentChecker.detach(exactRoot)
        let checkpointAdmission = service.admitVisiblePromo(
            VisiblePromoIdentity(
                surfaceID: firstSurfaceID,
                promoType: .remoteMessage,
                promoID: "first"
            )
        )

        guard case .acquired(let firstVisibleLease) = checkpointAdmission else {
            Issue.record("Expected the triggering NTP to acquire after exact-root detachment")
            return
        }
        #expect(firstTarget.retryCount == 0)
        #expect(secondTarget.retryCount == 1)
        #expect(secondVisibleLease != nil)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(promoQueueLeaseArbiter.snapshot.visiblePromoCount == 2)
        _ = (firstVisibleLease, firstRegistration, secondRegistration)
    }

    @Test("Enabling Re-Adopts Legacy Exact Root Before Active NTP Retry")
    func whenFeatureEnablesWithLegacyModalAttachedThenModalIsReAdoptedBeforeNTPRetry() {
        let scheduler = MockModalPromptScheduler()
        let attachmentChecker = IntegrationModalRootAttachmentChecker()
        let presentationHost = UIViewController()
        attachmentChecker.attach(presentationHost)
        let presenter = IntegrationAttachingModalPromptPresenter(
            presentationHost: presentationHost,
            attachmentChecker: attachmentChecker
        )
        let exactRoot = UIViewController()
        let provider = MockModalPromptProvider()
        provider.modalConfigurationToReturn = ModalPromptConfiguration(viewController: exactRoot)
        let manager = makeManager(
            providers: [provider],
            scheduler: scheduler,
            attachmentChecker: attachmentChecker
        )
        let service = makeService(manager: manager, promoQueueEnabled: false)

        service.presentModalPromptIfNeeded(from: presenter)
        scheduler.executeScheduledBlock()

        #expect(presenter.didCallPresent)
        #expect(provider.didCallDidPresentModal)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)

        let surfaceID = UUID()
        let retryTarget = IntegrationPromoRetryTarget()
        var didTransitionAdmission: VisiblePromoAdmissionResult?
        var retryAdmission: VisiblePromoAdmissionResult?
        retryTarget.onDidTransition = { [weak service] targetState in
            guard let service, targetState == .enabled else { return }
            didTransitionAdmission = service.admitVisiblePromo(
                VisiblePromoIdentity(
                    surfaceID: surfaceID,
                    promoType: .remoteMessage,
                    promoID: "rmf"
                )
            )
        }
        retryTarget.onRetry = { admissionHandler in
            retryAdmission = admissionHandler(
                VisiblePromoIdentity(
                    surfaceID: surfaceID,
                    promoType: .remoteMessage,
                    promoID: "rmf"
                )
            )
        }
        let registration = service.registerVisiblePromoRetry(
            for: surfaceID,
            target: retryTarget
        )

        service.transitionPromoQueueFeature(to: .enabled)

        #expect(retryTarget.events == ["will-enable", "did-enable", "retry"])
        #expect(didTransitionAdmission?.isUnavailableDuringTransition == true)
        #expect(retryAdmission?.isBlockedByModal == true)
        #expect(promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(promoQueueLeaseArbiter.snapshot.visiblePromoCount == 0)
        guard case .presentationActive = manager.modalAttemptPhase else {
            Issue.record("Expected the attached legacy root to be re-adopted before NTP retry")
            return
        }
        _ = registration
    }

    @Test("Disabling Cancels Committed Schedule And Rejects Reentrant Admissions")
    func whenFeatureDisablesDuringCommittedDelayThenStaleWorkCannotPresent() {
        let scheduler = MockModalPromptScheduler()
        let provider = MockModalPromptProvider()
        let manager = makeManager(
            providers: [provider],
            scheduler: scheduler
        )
        let service = makeService(manager: manager, promoQueueEnabled: true)
        let surfaceID = UUID()
        let retryTarget = IntegrationPromoRetryTarget()
        var callbackAdmissions = [VisiblePromoAdmissionResult]()
        retryTarget.onWillTransition = { [weak service] _ in
            guard let service else { return }
            callbackAdmissions.append(service.admitVisiblePromo(
                VisiblePromoIdentity(
                    surfaceID: surfaceID,
                    promoType: .remoteMessage,
                    promoID: "will"
                )
            ))
        }
        retryTarget.onDidTransition = { [weak service] _ in
            guard let service else { return }
            callbackAdmissions.append(service.admitVisiblePromo(
                VisiblePromoIdentity(
                    surfaceID: surfaceID,
                    promoType: .remoteMessage,
                    promoID: "did"
                )
            ))
        }
        let registration = service.registerVisiblePromoRetry(
            for: surfaceID,
            target: retryTarget
        )
        retryTarget.isActiveForPromoRetry = false

        service.presentModalPromptIfNeeded(from: presenterMock)

        guard case .committed = manager.modalAttemptPhase else {
            Issue.record("Expected a committed modal scheduling window")
            return
        }
        #expect(promoQueueLeaseArbiter.snapshot.hasModalLease)

        service.transitionPromoQueueFeature(to: .disabled)
        scheduler.executeScheduledBlock(includingCancelled: true)

        #expect(retryTarget.events == ["will-disable", "did-disable"])
        #expect(callbackAdmissions.count == 2)
        #expect(callbackAdmissions.allSatisfy { $0.isUnavailableDuringTransition })
        #expect(service.admitVisiblePromo(
            VisiblePromoIdentity(
                surfaceID: surfaceID,
                promoType: .remoteMessage,
                promoID: "after"
            )
        ).isFeatureDisabled)
        #expect(manager.modalAttemptPhase == .idle)
        #expect(!manager.hasActiveOrPendingModalAttempt)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(promoQueueLeaseArbiter.snapshot.visiblePromoCount == 0)
        #expect(!presenterMock.didCallPresent)
        #expect(!provider.didCallDidPresentModal)
        #expect(!cooldownManager.isInCooldownPeriod)
        _ = registration
    }

    @Test("Silent UIKit Refusal Retries Active NTP Snapshot Without Recursion")
    func whenPresentedRootNeverAttachesThenTwoActiveNTPsRetryOnceAndRegistrationMutationIsDeferred() {
        let scheduler = MockModalPromptScheduler()
        let attachmentChecker = IntegrationModalRootAttachmentChecker()
        let presentationHost = UIViewController()
        attachmentChecker.attach(presentationHost)
        presenterMock.modalPromptPresentationViewController = presentationHost
        presenterMock.shouldCompletePresentation = false
        let provider = MockModalPromptProvider()
        let manager = makeManager(
            providers: [provider],
            scheduler: scheduler,
            attachmentChecker: attachmentChecker
        )
        let service = makeService(manager: manager, promoQueueEnabled: true)
        let firstSurfaceID = UUID()
        let secondSurfaceID = UUID()
        let firstTarget = IntegrationPromoRetryTarget()
        let secondTarget = IntegrationPromoRetryTarget()
        let replacementTarget = IntegrationPromoRetryTarget()
        firstTarget.isActiveForPromoRetry = false
        secondTarget.isActiveForPromoRetry = false
        var firstVisibleLease: PromoQueueVisiblePromoLease?
        var secondVisibleLease: PromoQueueVisiblePromoLease?
        var firstRegistration: NewTabPagePromoRetryRegistration?
        var replacementRegistration: NewTabPagePromoRetryRegistration?
        firstTarget.onRetry = { [weak service] admissionHandler in
            guard let service else { return }
            guard case .acquired(let lease) = admissionHandler(
                VisiblePromoIdentity(
                    surfaceID: firstSurfaceID,
                    promoType: .remoteMessage,
                    promoID: "first"
                )
            ) else {
                Issue.record("Expected the first active NTP to acquire after silent refusal")
                return
            }
            firstVisibleLease = lease
            firstRegistration?.deregister()
            replacementRegistration = service.registerVisiblePromoRetry(
                for: firstSurfaceID,
                target: replacementTarget
            )
        }
        secondTarget.onRetry = { admissionHandler in
            guard case .acquired(let lease) = admissionHandler(
                VisiblePromoIdentity(
                    surfaceID: secondSurfaceID,
                    promoType: .remoteMessage,
                    promoID: "second"
                )
            ) else {
                Issue.record("Expected the second active NTP to acquire after silent refusal")
                return
            }
            secondVisibleLease = lease
        }
        firstRegistration = service.registerVisiblePromoRetry(
            for: firstSurfaceID,
            target: firstTarget
        )
        let secondRegistration = service.registerVisiblePromoRetry(
            for: secondSurfaceID,
            target: secondTarget
        )

        service.presentModalPromptIfNeeded(from: presenterMock)
        firstTarget.isActiveForPromoRetry = true
        secondTarget.isActiveForPromoRetry = true
        scheduler.executeScheduledBlock()
        scheduler.executeNextMainTurnBlock()

        #expect(presenterMock.didCallPresent)
        #expect(firstTarget.retryCount == 1)
        #expect(secondTarget.retryCount == 1)
        #expect(replacementTarget.retryCount == 0)
        #expect(firstVisibleLease != nil)
        #expect(secondVisibleLease != nil)
        #expect(promoQueueLeaseArbiter.snapshot.visiblePromoCount == 2)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(manager.modalAttemptPhase == .idle)
        #expect(manager.hasActiveOrPendingModalAttempt)
        #expect(!provider.didCallDidPresentModal)
        #expect(!cooldownManager.isInCooldownPeriod)

        service.transitionPromoQueueFeature(to: .disabled)

        #expect(!manager.hasActiveOrPendingModalAttempt)
        #expect(promoQueueLeaseArbiter.snapshot.visiblePromoCount == 0)
        _ = (firstRegistration, replacementRegistration, secondRegistration)
    }

    private func makeManager(
        providers: [any ModalPromptProvider],
        scheduler: ModalPromptScheduling? = nil,
        attachmentChecker: ModalPromptRootAttachmentChecking? = nil
    ) -> ModalPromptCoordinationManager {
        ModalPromptCoordinationManager(
            providers: providers,
            cooldownManager: cooldownManager,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: scheduler,
            rootAttachmentChecker: attachmentChecker
        )
    }

    private func makeService(
        manager: ModalPromptCoordinationManager,
        promoQueueEnabled: Bool
    ) -> PromoCoordinationService {
        let launchSourceManager = MockLaunchSourceManager()
        launchSourceManager.source = .standard
        let featureFlagger = MockFeatureFlagger(
            enabledFeatureFlags: promoQueueEnabled ? [.promoPresentationCoordination] : []
        )
        return PromoCoordinationService(
            launchSourceManager: launchSourceManager,
            modalPromptCoordinationManager: manager,
            featureFlagger: featureFlagger,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )
    }
}

// MARK: - Helpers

@MainActor
private final class ImmediateScheduler: ModalPromptScheduling {
    @discardableResult
    func schedule(after delay: TimeInterval, execute: @escaping @MainActor () -> Void) -> ModalPromptScheduledTask {
        execute()
        return ModalPromptScheduledTask()
    }

    @discardableResult
    func scheduleOnNextMainTurn(execute: @escaping @MainActor () -> Void) -> ModalPromptScheduledTask {
        execute()
        return ModalPromptScheduledTask()
    }
}

@MainActor
private final class IntegrationPromoRetryTarget: NewTabPagePromoRetrying {
    var isActiveForPromoRetry = true
    var onRetry: (@MainActor (VisiblePromoAdmissionHandler) -> Void)?
    var onWillTransition: (@MainActor (PromoQueueFeatureTargetState) -> Void)?
    var onDidTransition: (@MainActor (PromoQueueFeatureTargetState) -> Void)?

    private(set) var retryCount = 0
    private(set) var events = [String]()

    func retryVisiblePromoAdmission(using admissionHandler: VisiblePromoAdmissionHandler) {
        retryCount += 1
        events.append("retry")
        onRetry?(admissionHandler)
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

@MainActor
private final class IntegrationModalRootAttachmentChecker: ModalPromptRootAttachmentChecking {
    private var attachedRoots = Set<ObjectIdentifier>()
    private var intendedHosts = [ObjectIdentifier: ObjectIdentifier]()

    func attach(_ root: UIViewController, to intendedHost: UIViewController? = nil) {
        let rootIdentifier = ObjectIdentifier(root)
        attachedRoots.insert(rootIdentifier)
        intendedHosts[rootIdentifier] = intendedHost.map(ObjectIdentifier.init)
    }

    func detach(_ root: UIViewController) {
        let rootIdentifier = ObjectIdentifier(root)
        attachedRoots.remove(rootIdentifier)
        intendedHosts[rootIdentifier] = nil
    }

    func isAttached(_ root: UIViewController) -> Bool {
        attachedRoots.contains(ObjectIdentifier(root))
    }

    func isAttached(_ root: UIViewController, to intendedPresenter: UIViewController?) -> Bool {
        guard isAttached(root), let intendedPresenter else {
            return isAttached(root)
        }

        return intendedHosts[ObjectIdentifier(root)] == ObjectIdentifier(intendedPresenter)
    }
}

@MainActor
private final class IntegrationAttachingModalPromptPresenter: ModalPromptPresenter {
    let modalPromptPresentationViewController: UIViewController?
    var presentedViewController: UIViewController?
    private(set) var didCallPresent = false

    private let attachmentChecker: IntegrationModalRootAttachmentChecker

    init(
        presentationHost: UIViewController,
        attachmentChecker: IntegrationModalRootAttachmentChecker
    ) {
        modalPromptPresentationViewController = presentationHost
        self.attachmentChecker = attachmentChecker
    }

    func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)?) {
        didCallPresent = true
        attachmentChecker.attach(
            viewControllerToPresent,
            to: modalPromptPresentationViewController
        )
        completion?()
    }
}

private extension PromoQueueFeatureTargetState {
    var eventName: String {
        switch self {
        case .disabled:
            return "disable"
        case .enabled:
            return "enable"
        }
    }
}

private extension VisiblePromoAdmissionResult {
    var isBlockedByModal: Bool {
        if case .blockedByModal = self {
            return true
        }
        return false
    }

    var isFeatureDisabled: Bool {
        if case .featureDisabled = self {
            return true
        }
        return false
    }

    var isUnavailableDuringTransition: Bool {
        if case .unavailableDuringTransition = self {
            return true
        }
        return false
    }
}
