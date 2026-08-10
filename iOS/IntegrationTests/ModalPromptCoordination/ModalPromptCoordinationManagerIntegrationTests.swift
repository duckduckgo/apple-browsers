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
import Persistence
import PersistenceTestingUtils
import RemoteMessaging
import SwiftUI
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
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
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
        ) { _ in }
        let messagesModel = fixture.model
        let messagesConfiguration = fixture.configuration
        messagesModel.setSurfaceAttachmentProvider { true }
        messagesModel.load()
        messagesModel.setSurfaceRenderable(true)
        guard let gate = remoteMessageGate(in: messagesModel) else {
            Issue.record("Expected the after-idle RMF candidate to publish its coordinated gate")
            return
        }
        messagesModel.remoteMessageGateDidAppear(
            gateID: gate.id,
            messageID: gate.messageID,
            mountID: UUID()
        )

        #expect(messagesConfiguration.lastRefreshOpenedAfterIdle == true)
        #expect(messagesConfiguration.refreshCallCount == 1)
        #expect(messagesModel.homeMessageViewModels.isEmpty)
        #expect(gate.renderSession == nil)
        #expect(messagesConfiguration.appearanceCallCount == 0)
        #expect(promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(promoQueueLeaseArbiter.snapshot.visiblePromoIdentity == nil)

        // Fire the committed attempt while inactive. The real manager releases its owner and invokes the service's
        // release callback, but coordinated RMF retry remains closed throughout the background transition.
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

        let expectedIdentity = VisiblePromoIdentity(
            surfaceID: surfaceID,
            promoType: .remoteMessage,
            promoID: messageID
        )
        #expect(messagesConfiguration.refreshCallCount == 2)
        #expect(messagesConfiguration.lastRefreshOpenedAfterIdle == true)
        #expect(messagesModel.homeMessageViewModels.map(\.messageId) == [messageID])
        #expect(remoteMessageRenderSession(in: messagesModel) != nil)
        #expect(messagesConfiguration.appearanceCallCount == 0)
        #expect(messagesConfiguration.lastAppearedHomeMessage == nil)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .visible(expectedIdentity))

        messagesModel.setSurfaceRenderable(false)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == nil)
    }

    @available(iOS 16, *)
    @Test("Two Real NTP Models Handoff Only After SwiftUI Physical Removal", .timeLimit(.minutes(1)))
    func whenFirstMountedRemoteMessageDisappearsThenSecondMountedModelReceivesHandoff() async {
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
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )
        service.applicationDidBecomeActive()
        service.presentModalPromptIfNeeded(
            from: presenterMock,
            readinessToken: service.captureForegroundReadinessToken()
        )
        let firstSurfaceID = UUID()
        let secondSurfaceID = UUID()
        let firstIdentity = VisiblePromoIdentity(
            surfaceID: firstSurfaceID,
            promoType: .remoteMessage,
            promoID: "first"
        )
        let secondIdentity = VisiblePromoIdentity(
            surfaceID: secondSurfaceID,
            promoType: .remoteMessage,
            promoID: "second"
        )
        let lifecycle = TwoModelRemoteMessageLifecycleRecorder()
        let firstFixture = makeRemoteMessageModel(
            messageID: firstIdentity.promoID,
            surfaceID: firstSurfaceID,
            coordinator: service
        ) { [promoQueueLeaseArbiter = self.promoQueueLeaseArbiter] event in
            switch event {
            case .cardDidAppear:
                lifecycle.record(.firstCardDidAppear)
            case .cardDidDisappear:
                lifecycle.ownerAtFirstCardDisappearance = promoQueueLeaseArbiter.snapshot.activeOwner
                lifecycle.record(.firstCardDidDisappear)
            case .gateDidDisappear:
                lifecycle.record(.firstGateDidDisappear)
            case .gateDidAppear:
                break
            }
        }
        let firstModel = firstFixture.model
        let secondFixture = makeRemoteMessageModel(
            messageID: secondIdentity.promoID,
            surfaceID: secondSurfaceID,
            coordinator: service
        ) { event in
            switch event {
            case .gateDidAppear:
                lifecycle.record(.secondGateDidAppear)
            case .cardDidAppear:
                lifecycle.record(.secondCardDidAppear)
            case .cardDidDisappear, .gateDidDisappear:
                break
            }
        }
        let secondModel = secondFixture.model
        let hostState = TwoModelRemoteMessageHostState()
        let hostingController = UIHostingController(
            rootView: TwoModelRemoteMessageGateHost(
                firstModel: firstModel,
                secondModel: secondModel,
                state: hostState
            )
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        defer {
            firstModel.tearDown()
            secondModel.tearDown()
            window.isHidden = true
        }

        firstModel.setSurfaceAttachmentProvider { [weak hostingController] in
            hostingController?.viewIfLoaded?.window != nil
        }
        secondModel.setSurfaceAttachmentProvider { [weak hostingController] in
            hostingController?.viewIfLoaded?.window != nil
        }
        firstModel.load()
        secondModel.load()
        firstModel.setSurfaceRenderable(true)
        secondModel.setSurfaceRenderable(true)
        window.rootViewController = hostingController
        window.isHidden = false

        guard await lifecycle.wait(for: .firstCardDidAppear) else {
            Issue.record("Timed out waiting for the first mounted RMF card to appear")
            return
        }
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .visible(firstIdentity))

        hostState.isSecondGatePresented = true
        guard await lifecycle.wait(for: .secondGateDidAppear) else {
            Issue.record("Timed out waiting for the blocked second RMF gate to appear")
            return
        }

        #expect(remoteMessageRenderSession(in: secondModel) == nil)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .visible(firstIdentity))

        firstFixture.configuration.homeMessages = [makeRemoteMessage(messageID: "first-replacement")]
        firstModel.refresh()
        guard await lifecycle.wait(for: .firstCardDidDisappear) else {
            Issue.record("Timed out waiting for the outgoing first RMF card to disappear")
            return
        }
        guard await lifecycle.wait(for: .firstGateDidDisappear) else {
            Issue.record("Timed out waiting for the outgoing first RMF gate to disappear")
            return
        }

        #expect(lifecycle.ownerAtFirstCardDisappearance == .visible(firstIdentity))

        guard await lifecycle.wait(for: .secondCardDidAppear) else {
            Issue.record("Timed out waiting for the second RMF card to receive the release handoff")
            return
        }

        #expect(firstModel.isActiveForPromoRetry)
        #expect(remoteMessageGate(in: firstModel)?.messageID == "first-replacement")
        #expect(remoteMessageRenderSession(in: firstModel) == nil)
        #expect(remoteMessageRenderSession(in: secondModel) != nil)
        #expect(promoQueueLeaseArbiter.snapshot.activeOwner == .visible(secondIdentity))
    }

    private func makeRemoteMessageModel(
        messageID: String,
        surfaceID: UUID,
        coordinator: NewTabPagePromoCoordinating,
        isOpenedAfterIdle: Bool = false,
        lifecycleObserver: @escaping (NewTabPageRemoteMessageLifecycleEvent) -> Void
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
            remoteMessageLifecycleObserver: lifecycleObserver,
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

    private func remoteMessageRenderSession(
        in model: NewTabPageMessagesModel
    ) -> NewTabPageRemoteMessageRenderSession? {
        remoteMessageGate(in: model)?.renderSession
    }

    private func remoteMessageGate(in model: NewTabPageMessagesModel) -> NewTabPageRemoteMessageGate? {
        model.homeMessageRenderItems.lazy.compactMap { item in
            guard case .remoteMessageGate(let gate) = item.content else {
                return nil
            }
            return gate
        }.first
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
private final class TwoModelRemoteMessageLifecycleRecorder {
    enum Event: Hashable {
        case firstCardDidAppear
        case firstCardDidDisappear
        case firstGateDidDisappear
        case secondGateDidAppear
        case secondCardDidAppear
    }

    var ownerAtFirstCardDisappearance: PromoQueueActiveOwnerSnapshot?

    private var recordedEvents = Set<Event>()

    func record(_ event: Event) {
        recordedEvents.insert(event)
    }

    func wait(for event: Event) async -> Bool {
        for _ in 0..<200 {
            if recordedEvents.contains(event) {
                return true
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        return recordedEvents.contains(event)
    }
}

@MainActor
private final class TwoModelRemoteMessageHostState: ObservableObject {
    @Published var isSecondGatePresented = false
}

private struct TwoModelRemoteMessageGateHost: View {
    @ObservedObject var firstModel: NewTabPageMessagesModel
    @ObservedObject var secondModel: NewTabPageMessagesModel
    @ObservedObject var state: TwoModelRemoteMessageHostState

    var body: some View {
        VStack {
            if let gate = remoteMessageGate(in: firstModel) {
                NewTabPageRemoteMessageGateMountView(
                    gate: gate,
                    messagesModel: firstModel,
                    maximumWidth: 320
                )
                .id(gate.id)
            }

            if state.isSecondGatePresented,
               let gate = remoteMessageGate(in: secondModel) {
                NewTabPageRemoteMessageGateMountView(
                    gate: gate,
                    messagesModel: secondModel,
                    maximumWidth: 320
                )
                .id(gate.id)
            }
        }
    }

    private func remoteMessageGate(in model: NewTabPageMessagesModel) -> NewTabPageRemoteMessageGate? {
        model.homeMessageRenderItems.lazy.compactMap { item in
            guard case .remoteMessageGate(let gate) = item.content else {
                return nil
            }
            return gate
        }.first
    }
}
