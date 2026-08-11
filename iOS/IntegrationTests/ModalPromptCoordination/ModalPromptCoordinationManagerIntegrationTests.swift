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

import Foundation
import FoundationExtensions
import Persistence
import PersistenceTestingUtils
import RemoteMessaging
import Testing
@testable import DuckDuckGo

@MainActor
@Suite("Modal Prompt Coordination - Integration Tests")
final class ModalPromptCoordinationManagerIntegrationTests {
    private let timeTraveller: TimeTraveller
    private let keyValueStore: MockKeyValueFileStore
    private let cooldownStore: PromptCooldownKeyValueFilesStore
    private let cooldownIntervalProvider: MockPromptCooldownIntervalProvider
    private let cooldownManager: PromptCooldownManager
    private let promoQueueCooldownPolicy: PromoQueueCooldownPolicy
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
        let remoteMessageCooldownStore = PromoQueueRemoteMessageCooldownKeyValueFilesStore(keyValueStore: keyValueStore)
        cooldownIntervalProvider = MockPromptCooldownIntervalProvider() // Cooldown Interval 24h
        cooldownManager = PromptCooldownManager(
            presentationStore: cooldownStore,
            cooldownIntervalProvider: cooldownIntervalProvider,
            dateProvider: timeTraveller.getDate
        )
        promoQueueCooldownPolicy = PromoQueueCooldownPolicy(
            modalPresentationStore: cooldownStore,
            remoteMessagePresentationStore: remoteMessageCooldownStore
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

    @available(iOS 16, *)
    @Test("After-Idle RMF Waits For Modal Release And Full Foreground Readiness", .timeLimit(.minutes(1)))
    func whenAfterIdleRemoteMessageWaitsBehindCommittedModalThenReadinessAdmitsIt() async {
        let scheduler = MockModalPromptScheduler()
        let provider = MockModalPromptProvider()
        let manager = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManager,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            modalPromptScheduling: scheduler
        )
        let launchSourceManager = MockLaunchSourceManager()
        launchSourceManager.source = .standard
        presenterMock.presentedViewController = nil
        let service = PromoCoordinationService(
            launchSourceManager: launchSourceManager,
            modalPromptCoordinationManager: manager,
            promoCoordinationMode: .coordinated,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            promoQueueCooldownPolicy: promoQueueCooldownPolicy,
            dateProvider: timeTraveller.getDate
        )

        service.applicationDidBecomeActive()
        service.presentModalPromptIfNeeded(
            from: presenterMock,
            readinessToken: service.captureForegroundReadinessToken()
        )

        guard case .committed = manager.modalAttemptPhase else {
            Issue.record("Expected the modal to retain the global owner through its scheduled presentation window")
            return
        }
        #expect(promoQueueLeaseArbiter.snapshot.hasModalLease)

        let surfaceID = UUID()
        let messageID = "after-idle-rmf"
        let fixture = makeRemoteMessageModel(
            messageID: messageID,
            surfaceID: surfaceID,
            coordinator: service,
            isOpenedAfterIdle: true
        )
        let messagesModel = fixture.model
        let messagesConfiguration = fixture.configuration
        defer {
            messagesModel.tearDown()
        }
        messagesModel.setSurfaceAttachmentProvider { true }
        messagesModel.load()
        service.setSelectedRemoteMessageRendererID(surfaceID)
        messagesModel.setSurfaceLifecycleReady(true)

        #expect(messagesConfiguration.lastRefreshOpenedAfterIdle == true)
        #expect(messagesConfiguration.refreshCallCount == 1)
        #expect(messagesModel.homeMessageViewModels.isEmpty)
        #expect(coordinatedRemoteMessageRenderSession(in: messagesModel) == nil)
        #expect(messagesConfiguration.appearanceCallCount == 0)
        #expect(promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(service.remoteMessageCoordinationSnapshot.state == .idle)
        #expect(service.remoteMessageCoordinationSnapshot.registeredRendererCount == 1)
        #expect(service.remoteMessageCoordinationSnapshot.eligibleRendererCount == 1)

        // Fire the committed attempt while inactive. The real manager releases its owner and invokes the service's
        // release callback, but renderer reconciliation remains closed throughout the background transition.
        service.applicationWillResignActive()
        scheduler.executeScheduledBlock()

        #expect(manager.modalAttemptPhase == .idle)
        #expect(manager.shouldSuppressOtherSessionPromos)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == nil)
        #expect(messagesConfiguration.refreshCallCount == 1)
        #expect(messagesModel.homeMessageViewModels.isEmpty)
        #expect(messagesConfiguration.appearanceCallCount == 0)

        service.applicationDidEnterBackground()
        service.applicationDidBecomeActive()

        #expect(messagesConfiguration.refreshCallCount == 1)
        #expect(messagesModel.homeMessageViewModels.isEmpty)
        #expect(messagesConfiguration.appearanceCallCount == 0)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == nil)

        service.presentModalPromptIfNeeded(
            from: presenterMock,
            readinessToken: service.captureForegroundReadinessToken()
        )

        #expect(messagesConfiguration.refreshCallCount == 1)
        #expect(messagesConfiguration.lastRefreshOpenedAfterIdle == true)
        #expect(messagesModel.homeMessageViewModels.map(\.messageId) == [messageID])
        #expect(messagesConfiguration.appearanceCallCount == 0)
        #expect(messagesConfiguration.lastAppearedHomeMessage == nil)
        guard let sessionID = service.remoteMessageCoordinationSnapshot.sessionID else {
            Issue.record("Expected the after-idle renderer to receive a logical remote-message session")
            return
        }
        let expectedSession = PromoQueueRemoteMessageSession(id: sessionID, messageID: messageID)
        guard let renderSession = coordinatedRemoteMessageRenderSession(in: messagesModel) else {
            Issue.record("Expected direct coordinated remote-message content after readiness")
            return
        }
        #expect(service.remoteMessageCoordinationSnapshot.state == .owned)
        #expect(service.remoteMessageCoordinationSnapshot.rendererID == surfaceID)
        #expect(renderSession.presentation.session == expectedSession)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .remoteMessage(expectedSession))

        messagesModel.setSurfaceLifecycleReady(false)
        await waitForMainQueueSettlement()
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == nil)
    }

    @available(iOS 16, *)
    @Test("Appearance After Renderer Deselection Records No Queue Confirmation Or RMF Accounting", .timeLimit(.minutes(1)))
    func whenDeselectedRemoteMessagePresentationReportsAppearanceThenAccountingRemainsUnchanged() async {
        let manager = ModalPromptCoordinationManager(
            providers: [],
            cooldownManager: cooldownManager,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            modalPromptScheduling: schedulerMock
        )
        let service = PromoCoordinationService(
            launchSourceManager: MockLaunchSourceManager(),
            modalPromptCoordinationManager: manager,
            promoCoordinationMode: .coordinated,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            promoQueueCooldownPolicy: promoQueueCooldownPolicy,
            dateProvider: timeTraveller.getDate
        )
        service.applicationDidBecomeActive()
        service.presentModalPromptIfNeeded(
            from: presenterMock,
            readinessToken: service.captureForegroundReadinessToken()
        )

        let surfaceID = UUID()
        let messageID = "stale-appearance"
        let fixture = makeRemoteMessageModel(
            messageID: messageID,
            surfaceID: surfaceID,
            coordinator: service
        )
        defer {
            fixture.model.tearDown()
        }
        fixture.model.setSurfaceAttachmentProvider { true }
        fixture.model.load()
        service.setSelectedRemoteMessageRendererID(surfaceID)
        fixture.model.setSurfaceLifecycleReady(true)

        guard let renderSession = coordinatedRemoteMessageRenderSession(in: fixture.model) else {
            Issue.record("Expected the selected renderer to publish a remote-message presentation")
            return
        }
        guard let sessionID = service.remoteMessageCoordinationSnapshot.sessionID else {
            Issue.record("Expected the selected renderer to own a logical remote-message session")
            return
        }
        let logicalSession = PromoQueueRemoteMessageSession(id: sessionID, messageID: messageID)
        #expect(fixture.configuration.appearanceCallCount == 0)
        #expect(!service.remoteMessageCoordinationSnapshot.isQueueAppearanceConfirmed)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .remoteMessage(logicalSession))

        service.setSelectedRemoteMessageRendererID(nil)

        let drainingSnapshot = service.remoteMessageCoordinationSnapshot
        #expect(drainingSnapshot.state == .draining)
        #expect(drainingSnapshot.sessionID == sessionID)
        #expect(!drainingSnapshot.isQueueAppearanceConfirmed)
        #expect(fixture.model.homeMessageViewModels.isEmpty)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .remoteMessage(logicalSession))

        renderSession.viewModel.onDidAppear()

        #expect(fixture.configuration.appearanceCallCount == 0)
        #expect(fixture.configuration.lastAppearedHomeMessage == nil)
        #expect(!service.remoteMessageCoordinationSnapshot.isQueueAppearanceConfirmed)
        #expect(service.remoteMessageCoordinationSnapshot.isPresentationAppearanceReported == false)

        await waitForMainQueueSettlement()

        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == nil)
        #expect(fixture.configuration.appearanceCallCount == 0)
        #expect(fixture.configuration.lastAppearedHomeMessage == nil)
    }

    @available(iOS 16, *)
    @Test("Two Real NTP Models Handoff The Same Message Only After Exact Removal Settlement", .timeLimit(.minutes(1)))
    func whenSelectedRemoteMessageRendererChangesThenSameMessageSessionTransfersAfterSettlement() async {
        let manager = ModalPromptCoordinationManager(
            providers: [],
            cooldownManager: cooldownManager,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            modalPromptScheduling: schedulerMock
        )
        let service = PromoCoordinationService(
            launchSourceManager: MockLaunchSourceManager(),
            modalPromptCoordinationManager: manager,
            promoCoordinationMode: .coordinated,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            promoQueueCooldownPolicy: promoQueueCooldownPolicy,
            dateProvider: timeTraveller.getDate
        )
        service.applicationDidBecomeActive()
        service.presentModalPromptIfNeeded(
            from: presenterMock,
            readinessToken: service.captureForegroundReadinessToken()
        )
        promoQueueCooldownPolicy.recordConfirmedRemoteMessageAppearance(at: timeTraveller.getDate())
        let firstSurfaceID = UUID()
        let secondSurfaceID = UUID()
        let messageID = "shared-message"
        let firstFixture = makeRemoteMessageModel(
            messageID: messageID,
            surfaceID: firstSurfaceID,
            coordinator: service
        )
        let firstModel = firstFixture.model
        let secondFixture = makeRemoteMessageModel(
            messageID: messageID,
            surfaceID: secondSurfaceID,
            coordinator: service
        )
        let secondModel = secondFixture.model
        defer {
            firstModel.tearDown()
            secondModel.tearDown()
        }

        firstModel.setSurfaceAttachmentProvider { true }
        secondModel.setSurfaceAttachmentProvider { true }
        firstModel.load()
        secondModel.load()
        service.setSelectedRemoteMessageRendererID(firstSurfaceID)
        firstModel.setSurfaceLifecycleReady(true)
        secondModel.setSurfaceLifecycleReady(true)

        #expect(coordinatedRemoteMessageRenderSession(in: firstModel) == nil)
        #expect(firstModel.homeMessageViewModels.isEmpty)
        #expect(firstFixture.configuration.appearanceCallCount == 0)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == nil)

        timeTraveller.advanceBy(.minutes(10))

        #expect(coordinatedRemoteMessageRenderSession(in: firstModel) == nil)
        #expect(firstFixture.configuration.appearanceCallCount == 0)

        firstModel.refresh()

        let firstOwnedSnapshot = service.remoteMessageCoordinationSnapshot
        guard let firstSessionID = firstOwnedSnapshot.sessionID,
              let firstPresentationID = firstOwnedSnapshot.presentationID else {
            Issue.record("Expected the first real NTP model to own a remote-message presentation after cooldown")
            return
        }
        let logicalSession = PromoQueueRemoteMessageSession(id: firstSessionID, messageID: messageID)
        guard let firstRenderSession = coordinatedRemoteMessageRenderSession(in: firstModel) else {
            Issue.record("Expected the first real NTP model to publish direct coordinated content")
            return
        }
        #expect(firstOwnedSnapshot.state == .owned)
        #expect(firstOwnedSnapshot.rendererID == firstSurfaceID)
        #expect(firstRenderSession.presentation.session == logicalSession)
        #expect(firstRenderSession.presentation.id == firstPresentationID)
        #expect(firstModel.homeMessageViewModels.map(\.messageId) == [messageID])
        #expect(coordinatedRemoteMessageRenderSession(in: secondModel) == nil)
        #expect(secondModel.homeMessageViewModels.isEmpty)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .remoteMessage(logicalSession))
        #expect(firstFixture.configuration.appearanceCallCount == 0)
        #expect(secondFixture.configuration.appearanceCallCount == 0)
        #expect(!firstOwnedSnapshot.isQueueAppearanceConfirmed)
        #expect(firstOwnedSnapshot.isPresentationAppearanceReported == false)

        firstRenderSession.viewModel.onDidAppear()

        let firstConfirmationDate = timeTraveller.getDate()
        let firstConfirmedSnapshot = service.remoteMessageCoordinationSnapshot
        #expect(firstFixture.configuration.appearanceCallCount == 1)
        #expect(secondFixture.configuration.appearanceCallCount == 0)
        #expect(firstConfirmedSnapshot.sessionID == firstSessionID)
        #expect(firstConfirmedSnapshot.presentationID == firstPresentationID)
        #expect(firstConfirmedSnapshot.isQueueAppearanceConfirmed)
        #expect(firstConfirmedSnapshot.isPresentationAppearanceReported == true)

        firstRenderSession.viewModel.onDidAppear()

        #expect(firstFixture.configuration.appearanceCallCount == 1)
        #expect(secondFixture.configuration.appearanceCallCount == 0)
        #expect(service.remoteMessageCoordinationSnapshot.isQueueAppearanceConfirmed)
        #expect(
            promoQueueCooldownPolicy.snapshot(now: firstConfirmationDate).lastConfirmedRemoteMessageAppearance ==
                firstConfirmationDate
        )

        timeTraveller.advanceBy(.minutes(1))
        #expect(
            promoQueueCooldownPolicy.evaluateRemoteMessageAdmission(now: timeTraveller.getDate()) ==
                .blocked(until: firstConfirmationDate.addingTimeInterval(.minutes(10)))
        )

        service.setSelectedRemoteMessageRendererID(secondSurfaceID)

        let drainingSnapshot = service.remoteMessageCoordinationSnapshot
        #expect(drainingSnapshot.state == .draining)
        #expect(drainingSnapshot.sessionID == firstSessionID)
        #expect(drainingSnapshot.presentationID == firstPresentationID)
        #expect(drainingSnapshot.rendererID == firstSurfaceID)
        #expect(drainingSnapshot.removalID != nil)
        #expect(drainingSnapshot.removalTerminal == .sourceRemovedWithoutAnimation)
        #expect(drainingSnapshot.isQueueAppearanceConfirmed)
        #expect(drainingSnapshot.isPresentationAppearanceReported == true)
        #expect(coordinatedRemoteMessageRenderSession(in: firstModel) == nil)
        #expect(coordinatedRemoteMessageRenderSession(in: secondModel) == nil)
        #expect(firstModel.homeMessageViewModels.isEmpty)
        #expect(secondModel.homeMessageViewModels.isEmpty)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .remoteMessage(logicalSession))

        await waitForMainQueueSettlement()

        let transferredSnapshot = service.remoteMessageCoordinationSnapshot
        guard let transferredRenderSession = coordinatedRemoteMessageRenderSession(in: secondModel) else {
            Issue.record("Expected the second real NTP model to publish the transferred presentation")
            return
        }
        #expect(transferredSnapshot.state == .owned)
        #expect(transferredSnapshot.messageID == messageID)
        #expect(transferredSnapshot.sessionID == firstSessionID)
        #expect(transferredSnapshot.presentationID != firstPresentationID)
        #expect(transferredSnapshot.rendererID == secondSurfaceID)
        #expect(transferredSnapshot.isQueueAppearanceConfirmed)
        #expect(transferredSnapshot.isPresentationAppearanceReported == false)
        #expect(transferredRenderSession.presentation.session == logicalSession)
        #expect(transferredRenderSession.presentation.id == transferredSnapshot.presentationID)
        #expect(firstModel.homeMessageViewModels.isEmpty)
        #expect(secondModel.homeMessageViewModels.map(\.messageId) == [messageID])
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .remoteMessage(logicalSession))

        transferredRenderSession.viewModel.onDidAppear()

        let transferredConfirmedSnapshot = service.remoteMessageCoordinationSnapshot
        #expect(firstFixture.configuration.appearanceCallCount == 1)
        #expect(secondFixture.configuration.appearanceCallCount == 1)
        #expect(transferredConfirmedSnapshot.sessionID == firstSessionID)
        #expect(transferredConfirmedSnapshot.presentationID == transferredRenderSession.presentation.id)
        #expect(transferredConfirmedSnapshot.isQueueAppearanceConfirmed)
        #expect(transferredConfirmedSnapshot.isPresentationAppearanceReported == true)

        transferredRenderSession.viewModel.onDidAppear()

        #expect(firstFixture.configuration.appearanceCallCount == 1)
        #expect(secondFixture.configuration.appearanceCallCount == 1)
        #expect(service.remoteMessageCoordinationSnapshot.sessionID == firstSessionID)
        #expect(service.remoteMessageCoordinationSnapshot.isQueueAppearanceConfirmed)
        #expect(
            promoQueueCooldownPolicy.snapshot(now: timeTraveller.getDate()).lastConfirmedRemoteMessageAppearance ==
                firstConfirmationDate
        )
    }

    @available(iOS 16, *)
    @Test("A Different RMF Message Starts A Fresh Logical Session After Removal Settlement", .timeLimit(.minutes(1)))
    func whenSelectedRendererHasDifferentMessageThenItReceivesAFreshSessionAfterSettlement() async {
        let manager = ModalPromptCoordinationManager(
            providers: [],
            cooldownManager: cooldownManager,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            modalPromptScheduling: schedulerMock
        )
        let service = PromoCoordinationService(
            launchSourceManager: MockLaunchSourceManager(),
            modalPromptCoordinationManager: manager,
            promoCoordinationMode: .coordinated,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            promoQueueCooldownPolicy: promoQueueCooldownPolicy,
            dateProvider: timeTraveller.getDate
        )
        service.applicationDidBecomeActive()
        service.presentModalPromptIfNeeded(
            from: presenterMock,
            readinessToken: service.captureForegroundReadinessToken()
        )
        let firstMessageID = "first-message"
        let secondMessageID = "second-message"
        let firstSurfaceID = UUID()
        let secondSurfaceID = UUID()
        let firstFixture = makeRemoteMessageModel(
            messageID: firstMessageID,
            surfaceID: firstSurfaceID,
            coordinator: service
        )
        let secondFixture = makeRemoteMessageModel(
            messageID: secondMessageID,
            surfaceID: secondSurfaceID,
            coordinator: service
        )
        defer {
            firstFixture.model.tearDown()
            secondFixture.model.tearDown()
        }

        firstFixture.model.setSurfaceAttachmentProvider { true }
        secondFixture.model.setSurfaceAttachmentProvider { true }
        firstFixture.model.load()
        secondFixture.model.load()
        service.setSelectedRemoteMessageRendererID(firstSurfaceID)
        firstFixture.model.setSurfaceLifecycleReady(true)
        secondFixture.model.setSurfaceLifecycleReady(true)

        guard let firstSessionID = service.remoteMessageCoordinationSnapshot.sessionID else {
            Issue.record("Expected the first message to own a logical session")
            return
        }
        let firstLogicalSession = PromoQueueRemoteMessageSession(id: firstSessionID, messageID: firstMessageID)
        #expect(service.remoteMessageCoordinationSnapshot.messageID == firstMessageID)
        #expect(firstFixture.model.homeMessageViewModels.map(\.messageId) == [firstMessageID])
        #expect(coordinatedRemoteMessageRenderSession(in: firstFixture.model)?.presentation.session.id == firstSessionID)
        #expect(secondFixture.model.homeMessageViewModels.isEmpty)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .remoteMessage(firstLogicalSession))

        service.setSelectedRemoteMessageRendererID(secondSurfaceID)

        #expect(service.remoteMessageCoordinationSnapshot.state == .draining)
        #expect(service.remoteMessageCoordinationSnapshot.sessionID == firstSessionID)
        #expect(secondFixture.model.homeMessageViewModels.isEmpty)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .remoteMessage(firstLogicalSession))

        await waitForMainQueueSettlement()

        guard let secondSessionID = service.remoteMessageCoordinationSnapshot.sessionID else {
            Issue.record("Expected the different message to acquire a fresh logical session")
            return
        }
        let secondLogicalSession = PromoQueueRemoteMessageSession(id: secondSessionID, messageID: secondMessageID)
        #expect(service.remoteMessageCoordinationSnapshot.state == .owned)
        #expect(service.remoteMessageCoordinationSnapshot.messageID == secondMessageID)
        #expect(secondSessionID != firstSessionID)
        #expect(firstFixture.model.homeMessageViewModels.isEmpty)
        #expect(secondFixture.model.homeMessageViewModels.map(\.messageId) == [secondMessageID])
        #expect(coordinatedRemoteMessageRenderSession(in: secondFixture.model)?.presentation.session == secondLogicalSession)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .remoteMessage(secondLogicalSession))
    }

    private func makeRemoteMessageModel(
        messageID: String,
        surfaceID: UUID,
        coordinator: NewTabPagePromoCoordinating,
        isOpenedAfterIdle: Bool = false,
        remoteMessageRemovalPath: NewTabPageRemoteMessageRemovalPath = .synchronousSourceClear
    ) -> (model: NewTabPageMessagesModel, configuration: HomePageMessagesConfigurationMock) {
        let configuration = HomePageMessagesConfigurationMock(
            homeMessages: [makeRemoteMessage(messageID: messageID)]
        )
        let model = NewTabPageMessagesModel(
            homePageMessagesConfiguration: configuration,
            surfaceID: surfaceID,
            notificationCenter: NotificationCenter(),
            messageActionHandler: MockRemoteMessagingActionHandler(),
            imageLoader: MockRemoteMessagingImageLoader(),
            promoCoordinator: coordinator,
            remoteMessageRemovalPath: remoteMessageRemovalPath,
            isOpenedAfterIdle: { isOpenedAfterIdle }
        )
        return (model, configuration)
    }

    private func makeRemoteMessage(messageID: String) -> HomeMessage {
        .remoteMessage(
            remoteMessage: RemoteMessageModel(
                id: messageID,
                surfaces: .newTabPage,
                content: .small(titleText: messageID, descriptionText: "Body"),
                matchingRules: [],
                exclusionRules: [],
                isMetricsEnabled: true
            )
        )
    }

    private func coordinatedRemoteMessageRenderSession(
        in model: NewTabPageMessagesModel
    ) -> NewTabPageRemoteMessageRenderSession? {
        model.homeMessageRenderItems.lazy.compactMap { item in
            guard case .coordinatedRemoteMessage(let renderSession) = item.content else {
                return nil
            }
            return renderSession
        }.first
    }

    private func waitForMainQueueSettlement() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
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
