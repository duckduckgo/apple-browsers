//
//  HomePageConfigurationTests.swift
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

import Combine
import Foundation
import RemoteMessaging
import RemoteMessagingTestsUtils
import Testing
@testable import DuckDuckGo

@MainActor
struct HomePageConfigurationTests {

    @Test("Check Home Page Configuration Fetches Remote Messages With NewTabPage Surface")
    func checkFetchRemoteMessagesWithTheRightSurface() async throws {
        // GIVEN
        let storeMock = MockRemoteMessagingStore()

        // WHEN
        let sut = HomePageConfiguration(variantManager: nil, remoteMessagingStore: storeMock, subscriptionDataReporter: MockSubscriptionDataReporter(), isStillOnboarding: { false })

        // THEN
        #expect(storeMock.fetchScheduledRemoteMessageCalls == 1)
        #expect(storeMock.capturedSurfaces == .newTabPage)

        // GIVEN
        storeMock.fetchScheduledRemoteMessageCalls = 0
        storeMock.capturedSurfaces = nil

        // WHEN
        sut.refresh()

        // THEN
        #expect(storeMock.fetchScheduledRemoteMessageCalls == 1)
        #expect(storeMock.capturedSurfaces == .newTabPage)
    }

    @available(iOS 16, *)
    @Test("When refreshed after idle and an idle message exists, triggerFilter is .specific(.afterIdle)", .timeLimit(.minutes(1)))
    func refreshAfterIdleWithIdleMessageAvailable() {
        // GIVEN
        let storeMock = MockRemoteMessagingStore()
        storeMock.scheduledRemoteMessage = RemoteMessageModel(
            id: "idle-msg", surfaces: .newTabPage, content: nil, matchingRules: [], exclusionRules: [], isMetricsEnabled: false)
        let sut = HomePageConfiguration(variantManager: nil, remoteMessagingStore: storeMock, subscriptionDataReporter: MockSubscriptionDataReporter(), isStillOnboarding: { false })
        storeMock.capturedTriggerFilter = nil

        // WHEN
        sut.refresh(openedAfterIdle: true)

        // THEN
        #expect(storeMock.capturedTriggerFilter == .specific(.afterIdle))
    }

    @available(iOS 16, *)
    @Test("When refreshed after idle and no idle message exists, falls back to .noTrigger", .timeLimit(.minutes(1)))
    func refreshAfterIdleFallsBackToNoTrigger() {
        // GIVEN
        let storeMock = MockRemoteMessagingStore()
        let sut = HomePageConfiguration(variantManager: nil, remoteMessagingStore: storeMock, subscriptionDataReporter: MockSubscriptionDataReporter(), isStillOnboarding: { false })
        storeMock.capturedTriggerFilter = nil

        // WHEN
        sut.refresh(openedAfterIdle: true)

        // THEN — no idle message found, so it falls back to .noTrigger
        #expect(storeMock.capturedTriggerFilter == .noTrigger)
    }

    @available(iOS 16, *)
    @Test("When refreshed with openedAfterIdle false, triggerFilter is .noTrigger", .timeLimit(.minutes(1)))
    func refreshWithOpenedAfterIdleFalsePassesNoTrigger() {
        // GIVEN
        let storeMock = MockRemoteMessagingStore()
        let sut = HomePageConfiguration(variantManager: nil, remoteMessagingStore: storeMock, subscriptionDataReporter: MockSubscriptionDataReporter(), isStillOnboarding: { false })
        storeMock.capturedTriggerFilter = nil

        // WHEN
        sut.refresh(openedAfterIdle: false)

        // THEN
        #expect(storeMock.capturedTriggerFilter == .noTrigger)
    }

    @available(iOS 16, *)
    @Test("When refreshed without parameter, triggerFilter is .noTrigger (backward compat)", .timeLimit(.minutes(1)))
    func refreshWithoutParameterPassesNoTrigger() {
        // GIVEN
        let storeMock = MockRemoteMessagingStore()
        let sut = HomePageConfiguration(variantManager: nil, remoteMessagingStore: storeMock, subscriptionDataReporter: MockSubscriptionDataReporter(), isStillOnboarding: { false })
        storeMock.capturedTriggerFilter = nil

        // WHEN
        sut.refresh()

        // THEN
        #expect(storeMock.capturedTriggerFilter == .noTrigger)
    }

    @Test("Coordinated initialization defers RMF selection until explicit preparation")
    func coordinatedInitializationDefersSelection() {
        let store = FilteredRemoteMessagingStore(noTriggerMessage: makeRemoteMessage(id: "message"))
        let gate = MockPromoGate()

        let sut = makeCoordinatedConfiguration(store: store, gate: gate)

        #expect(store.fetchedTriggerFilters.isEmpty)
        #expect(gate.acquiredMessageIDs.isEmpty)
        #expect(sut.homeMessages.isEmpty)

        sut.prepareForNTP(openedAfterIdle: false)

        #expect(store.fetchedTriggerFilters == [.noTrigger])
        #expect(gate.acquiredMessageIDs == ["message"])
        #expect(sut.homeMessages == [.remoteMessage(remoteMessage: makeRemoteMessage(id: "message"))])
    }

    @Test("Disabled preparation neither selects nor arms a later store refresh")
    func disabledPreparationDoesNotArmRefresh() async {
        let notificationCenter = NotificationCenter()
        let store = FilteredRemoteMessagingStore(noTriggerMessage: makeRemoteMessage(id: "message"))
        let gate = MockPromoGate()
        let sut = makeCoordinatedConfiguration(
            store: store,
            gate: gate,
            isRMFAdmissionEnabled: false,
            notificationCenter: notificationCenter
        )

        sut.prepareForNTP(openedAfterIdle: true)
        sut.handleAppForegrounded()
        notificationCenter.post(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange, object: nil)
        await Task.yield()

        #expect(store.fetchedTriggerFilters.isEmpty)
        #expect(gate.acquiredMessageIDs.isEmpty)

        sut.prepareForNTP(openedAfterIdle: false)

        #expect(store.fetchedTriggerFilters == [.noTrigger])
        #expect(gate.acquiredMessageIDs == ["message"])
    }

    @Test("After-idle fallback pins the actual no-trigger filter for the ownership")
    func afterIdleFallbackPinsActualFilter() {
        let original = makeRemoteMessage(id: "original")
        let replacement = makeRemoteMessage(id: "replacement")
        let store = FilteredRemoteMessagingStore(noTriggerMessage: original)
        let gate = MockPromoGate()
        let sut = makeCoordinatedConfiguration(store: store, gate: gate)

        sut.prepareForNTP(openedAfterIdle: true)
        store.afterIdleMessage = replacement
        store.fetchedTriggerFilters.removeAll()

        sut.prepareForNTP(openedAfterIdle: true)

        #expect(store.fetchedTriggerFilters == [.noTrigger])
        #expect(gate.acquiredMessageIDs == ["original"])
        #expect(sut.homeMessages == [.remoteMessage(remoteMessage: original)])
    }

    @Test("Unsupported content is rejected before gate acquisition")
    func unsupportedContentDoesNotAcquire() {
        let unsupported = makeRemoteMessage(id: "unsupported", content: nil)
        let store = FilteredRemoteMessagingStore(noTriggerMessage: unsupported)
        let gate = MockPromoGate()
        let sut = makeCoordinatedConfiguration(store: store, gate: gate)

        sut.prepareForNTP(openedAfterIdle: false)

        #expect(gate.acquiredMessageIDs.isEmpty)
        #expect(sut.homeMessages.isEmpty)
    }

    @Test("A coordinated store refresh retries a denied candidate with the last preparation policy")
    func storeRefreshRetriesDeniedCandidate() async {
        let notificationCenter = NotificationCenter()
        let message = makeRemoteMessage(id: "after-idle")
        let store = FilteredRemoteMessagingStore(afterIdleMessage: message)
        let gate = MockPromoGate()
        gate.grantsAcquisition = false
        let sut = makeCoordinatedConfiguration(store: store, gate: gate, notificationCenter: notificationCenter)

        sut.prepareForNTP(openedAfterIdle: true)
        #expect(sut.homeMessages.isEmpty)

        gate.grantsAcquisition = true
        store.fetchedTriggerFilters.removeAll()
        notificationCenter.post(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange, object: nil)
        await Task.yield()

        #expect(store.fetchedTriggerFilters == [.specific(.afterIdle)])
        #expect(gate.acquiredMessageIDs == ["after-idle", "after-idle"])
        #expect(sut.homeMessages == [.remoteMessage(remoteMessage: message)])
    }

    @Test("One store notification selects once and synchronously converges all source consumers")
    func storeNotificationConvergesTwoModelsAndDirectConsumer() async {
        let notificationCenter = NotificationCenter()
        let message = makeRemoteMessage(id: "message")
        let store = FilteredRemoteMessagingStore(noTriggerMessage: message)
        let gate = MockPromoGate()
        gate.grantsAcquisition = false
        let sut = makeCoordinatedConfiguration(store: store, gate: gate, notificationCenter: notificationCenter)
        sut.prepareForNTP(openedAfterIdle: false)

        let firstModel = makeMessagesModel(configuration: sut, notificationCenter: notificationCenter)
        let secondModel = makeMessagesModel(configuration: sut, notificationCenter: notificationCenter)
        firstModel.load()
        secondModel.load()
        var directConsumerMessages: [HomeMessage] = []
        var directConsumerCallCount = 0
        let cancellable = sut.contentDidChangePublisher.sink {
            directConsumerCallCount += 1
            directConsumerMessages = sut.homeMessages
        }

        gate.grantsAcquisition = true
        store.fetchedTriggerFilters.removeAll()
        notificationCenter.post(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange, object: nil)
        await Task.yield()

        #expect(store.fetchedTriggerFilters == [.noTrigger])
        #expect(gate.acquiredMessageIDs == ["message", "message"])
        #expect(firstModel.homeMessageViewModels.map(\.messageId) == ["message"])
        #expect(secondModel.homeMessageViewModels.map(\.messageId) == ["message"])
        #expect(directConsumerMessages == [.remoteMessage(remoteMessage: message)])
        #expect(directConsumerCallCount == 1)
        withExtendedLifetime(cancellable) {}
    }

    @Test("A modal-owned slot prevents RMF publication and store mutation")
    func modalOwnershipBlocksRemoteMessageAdmission() throws {
        let message = makeRemoteMessage(id: "message")
        let store = FilteredRemoteMessagingStore(noTriggerMessage: message)
        let gate = MockPromoGate()
        guard case .acquired(let modalLease) = gate.arbiter.acquireModalLease() else {
            Issue.record("Expected the test modal lease to acquire")
            return
        }
        let sut = makeCoordinatedConfiguration(store: store, gate: gate)

        sut.prepareForNTP(openedAfterIdle: false)

        #expect(sut.homeMessages.isEmpty)
        #expect(store.dismissedMessageIDs.isEmpty)
        #expect(store.updatedShownMessageIDs.isEmpty)
        #expect(gate.arbiter.snapshot.hasModalLease)
        _ = modalLease
    }

    @Test("The complete ownership context is retained before RMF publication")
    func ownershipIsRetainedBeforePublication() {
        let message = makeRemoteMessage(id: "message")
        let store = FilteredRemoteMessagingStore(noTriggerMessage: message)
        let gate = MockPromoGate()
        let sut = makeCoordinatedConfiguration(store: store, gate: gate)
        var contextAtPublication: HomeMessagePresentationContext?
        var ownerAtPublication: PromoQueueLeaseOwnerSnapshot?
        let cancellable = sut.contentDidChangePublisher.sink {
            contextAtPublication = sut.presentationContext(for: .remoteMessage(remoteMessage: message))
            ownerAtPublication = gate.arbiter.snapshot.owner
        }

        sut.prepareForNTP(openedAfterIdle: false)

        #expect(contextAtPublication != nil)
        #expect(ownerAtPublication != nil)
        withExtendedLifetime(cancellable) {}
    }

    @Test("Same ownership keeps identity while background reacquisition changes it")
    func ownershipIdentityLifecycle() {
        let message = makeRemoteMessage(id: "message")
        let store = FilteredRemoteMessagingStore(noTriggerMessage: message)
        let gate = MockPromoGate()
        let sut = makeCoordinatedConfiguration(store: store, gate: gate)

        sut.prepareForNTP(openedAfterIdle: false)
        let firstContext = sut.presentationContext(for: .remoteMessage(remoteMessage: message))

        sut.prepareForNTP(openedAfterIdle: true)
        let refreshedContext = sut.presentationContext(for: .remoteMessage(remoteMessage: message))

        sut.handleAppBackgrounded()
        sut.handleAppForegrounded()
        sut.prepareForNTP(openedAfterIdle: false)
        let reacquiredContext = sut.presentationContext(for: .remoteMessage(remoteMessage: message))

        #expect(firstContext == refreshedContext)
        #expect(firstContext != reacquiredContext)
        #expect(gate.acquiredMessageIDs == ["message", "message"])
    }

    @Test("Only the first current appearance confirms history and stale appearance is ignored")
    func appearanceIsIdentityCheckedAndConfirmedOnce() {
        let message = makeRemoteMessage(id: "message")
        let store = FilteredRemoteMessagingStore(noTriggerMessage: message)
        let gate = MockPromoGate()
        let sut = makeCoordinatedConfiguration(store: store, gate: gate)
        sut.prepareForNTP(openedAfterIdle: false)
        let context = sut.presentationContext(for: .remoteMessage(remoteMessage: message))

        sut.didAppear(.remoteMessage(remoteMessage: message), presentationContext: context)
        sut.didAppear(.remoteMessage(remoteMessage: message), presentationContext: context)
        sut.handleAppBackgrounded()
        sut.didAppear(.remoteMessage(remoteMessage: message), presentationContext: context)

        #expect(gate.cooldownPolicy.recordConfirmedRemoteMessageAppearanceCallCount == 1)
        #expect(store.hasShownRemoteMessageCallCount == 1)
    }

    @Test("An appeared RMF records real history once and is cooldown-blocked after background")
    func appearedRemoteMessageIsCooldownBlockedAfterBackground() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let message = makeRemoteMessage(id: "message")
        let store = FilteredRemoteMessagingStore(noTriggerMessage: message)
        let history = RecordingPromoQueueRemoteMessageHistory()
        let arbiter = PromoQueueLeaseArbiter()
        let policy = PromoQueueCooldownPolicy(
            modalPresentationStore: MockPromptCooldownStore(),
            remoteMessageHistory: history,
            dateProvider: { now }
        )
        let service = makePromoCoordinationService(arbiter: arbiter, cooldownPolicy: policy)
        let sut = HomePageConfiguration(
            remoteMessagingStore: store,
            subscriptionDataReporter: MockSubscriptionDataReporter(),
            isStillOnboarding: { false },
            promoGate: service
        )

        sut.prepareForNTP(openedAfterIdle: false)
        let context = sut.presentationContext(for: .remoteMessage(remoteMessage: message))
        sut.didAppear(.remoteMessage(remoteMessage: message), presentationContext: context)
        sut.didAppear(.remoteMessage(remoteMessage: message), presentationContext: context)
        while store.updatedShownMessageIDs.isEmpty {
            await Task.yield()
        }

        var ownerAtBackgroundSignal: PromoQueueLeaseOwnerSnapshot?
        let cancellable = sut.contentDidChangePublisher.sink {
            ownerAtBackgroundSignal = arbiter.snapshot.owner
        }
        sut.handleAppBackgrounded()
        sut.handleAppForegrounded()
        sut.prepareForNTP(openedAfterIdle: false)

        #expect(history.recordedDates == [now])
        #expect(store.hasShownRemoteMessageCallCount == 1)
        #expect(store.updatedShownMessageIDs == ["message"])
        #expect(ownerAtBackgroundSignal != nil)
        #expect(sut.homeMessages.isEmpty)
        #expect(arbiter.snapshot.owner == nil)
        withExtendedLifetime(cancellable) {}
    }

    @Test("A never-appeared RMF can reacquire after background without writing history")
    func neverAppearedRemoteMessageCanReacquireAfterBackground() {
        let message = makeRemoteMessage(id: "message")
        let store = FilteredRemoteMessagingStore(noTriggerMessage: message)
        let history = RecordingPromoQueueRemoteMessageHistory()
        let arbiter = PromoQueueLeaseArbiter()
        let policy = PromoQueueCooldownPolicy(
            modalPresentationStore: MockPromptCooldownStore(),
            remoteMessageHistory: history
        )
        let service = makePromoCoordinationService(arbiter: arbiter, cooldownPolicy: policy)
        let sut = HomePageConfiguration(
            remoteMessagingStore: store,
            subscriptionDataReporter: MockSubscriptionDataReporter(),
            isStillOnboarding: { false },
            promoGate: service
        )

        sut.prepareForNTP(openedAfterIdle: false)
        let firstContext = sut.presentationContext(for: .remoteMessage(remoteMessage: message))
        sut.handleAppBackgrounded()
        sut.handleAppForegrounded()
        sut.prepareForNTP(openedAfterIdle: false)
        let secondContext = sut.presentationContext(for: .remoteMessage(remoteMessage: message))

        #expect(history.recordedDates.isEmpty)
        #expect(firstContext != secondContext)
        #expect(secondContext != nil)
        #expect(arbiter.snapshot.owner != nil)
    }

    @Test("A dismissal made stale while awaiting cannot release a reacquired same-ID owner")
    func staleDismissalCompletionCannotReleaseReacquiredOwner() async {
        let notificationCenter = NotificationCenter()
        let message = makeRemoteMessage(id: "message")
        let store = FilteredRemoteMessagingStore(noTriggerMessage: message)
        let gate = MockPromoGate()
        let sut = makeCoordinatedConfiguration(store: store, gate: gate, notificationCenter: notificationCenter)
        sut.prepareForNTP(openedAfterIdle: false)
        let oldContext = sut.presentationContext(for: .remoteMessage(remoteMessage: message))
        var dismissalContinuation: CheckedContinuation<Void, Never>?
        var reconciliationNotificationCount = 0
        var ownerAtReconciliationNotification: PromoQueueLeaseOwnerSnapshot?
        let notificationObserver = notificationCenter.addObserver(
            forName: RemoteMessagingStore.Notifications.remoteMessagesDidChange,
            object: nil,
            queue: nil
        ) { _ in
            MainActor.assumeIsolated {
                reconciliationNotificationCount += 1
                ownerAtReconciliationNotification = gate.arbiter.snapshot.owner
            }
        }
        store.dismissRemoteMessageHandler = {
            await withCheckedContinuation { continuation in
                dismissalContinuation = continuation
            }
        }

        let dismissalTask = Task {
            await sut.dismissHomeMessage(
                .remoteMessage(remoteMessage: message),
                presentationContext: oldContext
            )
        }
        while dismissalContinuation == nil {
            await Task.yield()
        }

        sut.handleAppBackgrounded()
        sut.handleAppForegrounded()
        sut.prepareForNTP(openedAfterIdle: false)
        let newContext = sut.presentationContext(for: .remoteMessage(remoteMessage: message))
        dismissalContinuation?.resume()
        await dismissalTask.value

        #expect(reconciliationNotificationCount == 1)
        #expect(ownerAtReconciliationNotification != nil)

        await Task.yield()

        #expect(oldContext != newContext)
        #expect(sut.presentationContext(for: .remoteMessage(remoteMessage: message)) == nil)
        #expect(gate.arbiter.snapshot.owner == nil)
        #expect(store.dismissedMessageIDs == ["message"])
        notificationCenter.removeObserver(notificationObserver)
    }

    @Test("Ordered teardown signals while the old lease still owns the slot")
    func teardownSignalsBeforeRelease() async {
        let notificationCenter = NotificationCenter()
        let message = makeRemoteMessage(id: "message")
        let store = FilteredRemoteMessagingStore(noTriggerMessage: message)
        let gate = MockPromoGate()
        let sut = makeCoordinatedConfiguration(store: store, gate: gate, notificationCenter: notificationCenter)
        sut.prepareForNTP(openedAfterIdle: false)

        var ownerAtSignal: PromoQueueLeaseOwnerSnapshot?
        let cancellable = sut.contentDidChangePublisher.sink {
            ownerAtSignal = gate.arbiter.snapshot.owner
        }
        store.noTriggerMessage = nil

        notificationCenter.post(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange, object: nil)
        await Task.yield()

        #expect(ownerAtSignal != nil)
        #expect(gate.arbiter.snapshot.owner == nil)
        #expect(sut.homeMessages.isEmpty)
        withExtendedLifetime(cancellable) {}
    }

    @Test("Replacement unpublishes before releasing the old owner, then publishes a new identity")
    func replacementUsesOrderedTeardownAndFreshIdentity() async {
        let notificationCenter = NotificationCenter()
        let original = makeRemoteMessage(id: "original")
        let replacement = makeRemoteMessage(id: "replacement")
        let store = FilteredRemoteMessagingStore(noTriggerMessage: original)
        let gate = MockPromoGate()
        let sut = makeCoordinatedConfiguration(store: store, gate: gate, notificationCenter: notificationCenter)
        sut.prepareForNTP(openedAfterIdle: false)
        let originalContext = sut.presentationContext(for: .remoteMessage(remoteMessage: original))
        var ownersAtSignal: [PromoQueueLeaseOwnerSnapshot?] = []
        let cancellable = sut.contentDidChangePublisher.sink {
            ownersAtSignal.append(gate.arbiter.snapshot.owner)
        }

        store.noTriggerMessage = replacement
        notificationCenter.post(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange, object: nil)
        await Task.yield()
        let replacementContext = sut.presentationContext(for: .remoteMessage(remoteMessage: replacement))

        #expect(ownersAtSignal.count == 2)
        #expect(ownersAtSignal[0] != nil)
        #expect(ownersAtSignal[1] != nil)
        #expect(originalContext != replacementContext)
        #expect(sut.homeMessages == [.remoteMessage(remoteMessage: replacement)])
        withExtendedLifetime(cancellable) {}
    }

    @Test("Onboarding suppression unpublishes before releasing current ownership")
    func onboardingSuppressionUsesOrderedTeardown() async {
        let notificationCenter = NotificationCenter()
        let message = makeRemoteMessage(id: "message")
        let store = FilteredRemoteMessagingStore(noTriggerMessage: message)
        let gate = MockPromoGate()
        var isStillOnboarding = false
        let sut = HomePageConfiguration(
            remoteMessagingStore: store,
            subscriptionDataReporter: MockSubscriptionDataReporter(),
            isStillOnboarding: { isStillOnboarding },
            promoGate: gate,
            notificationCenter: notificationCenter
        )
        sut.prepareForNTP(openedAfterIdle: false)
        var ownerAtSignal: PromoQueueLeaseOwnerSnapshot?
        let cancellable = sut.contentDidChangePublisher.sink {
            ownerAtSignal = gate.arbiter.snapshot.owner
        }

        isStillOnboarding = true
        notificationCenter.post(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange, object: nil)
        await Task.yield()

        #expect(ownerAtSignal != nil)
        #expect(gate.arbiter.snapshot.owner == nil)
        #expect(sut.homeMessages.isEmpty)
        withExtendedLifetime(cancellable) {}
    }

    private func makeCoordinatedConfiguration(
        store: RemoteMessagingStoring,
        gate: MockPromoGate,
        isRMFAdmissionEnabled: Bool = true,
        notificationCenter: NotificationCenter = NotificationCenter()
    ) -> HomePageConfiguration {
        HomePageConfiguration(
            remoteMessagingStore: store,
            subscriptionDataReporter: MockSubscriptionDataReporter(),
            isStillOnboarding: { false },
            promoGate: gate,
            isRMFAdmissionEnabled: isRMFAdmissionEnabled,
            notificationCenter: notificationCenter
        )
    }

    private func makeRemoteMessage(
        id: String,
        content: RemoteMessageModelType? = .small(titleText: "Title", descriptionText: "Description")
    ) -> RemoteMessageModel {
        RemoteMessageModel(
            id: id,
            surfaces: .newTabPage,
            content: content,
            matchingRules: [],
            exclusionRules: [],
            isMetricsEnabled: false
        )
    }

    private func makeMessagesModel(
        configuration: HomePageMessagesConfiguration,
        notificationCenter: NotificationCenter
    ) -> NewTabPageMessagesModel {
        NewTabPageMessagesModel(
            homePageMessagesConfiguration: configuration,
            notificationCenter: notificationCenter,
            messageActionHandler: RemoteMessagingActionHandler(
                lastSearchStateRefresher: RemoteMessagingSurveyLastSearchStateRefresher()
            ),
            imageLoader: MockRemoteMessagingImageLoader()
        )
    }

    private func makePromoCoordinationService(
        arbiter: PromoQueueLeaseArbiter,
        cooldownPolicy: PromoQueueCooldownPolicying
    ) -> PromoCoordinationService {
        PromoCoordinationService(
            launchSourceManager: MockLaunchSourceManager(),
            modalPromptCoordinationManager: MockModalPromptCoordinationManager(),
            mode: .coordinated,
            promoQueueLeaseArbiter: arbiter,
            promoQueueCooldownPolicy: cooldownPolicy
        )
    }

}

@MainActor
private final class RecordingPromoQueueRemoteMessageHistory: PromoQueueRemoteMessageHistory {
    private(set) var recordedDates: [Date] = []

    var lastConfirmedAppearance: Date? {
        recordedDates.last
    }

    func recordConfirmedAppearance(at date: Date) {
        recordedDates.append(date)
    }

    func reset() {
        recordedDates.removeAll()
    }
}

@MainActor
private final class MockPromoGate: PromoGating {
    let mode = PromoCoordinationMode.coordinated
    let arbiter = PromoQueueLeaseArbiter()
    let cooldownPolicy = MockPromoQueueCooldownPolicy()
    var grantsAcquisition = true
    private(set) var acquiredMessageIDs: [String] = []

    func tryAcquireRemoteMessageLease(for messageID: String) -> PromoQueueRemoteMessageLease? {
        acquiredMessageIDs.append(messageID)
        guard grantsAcquisition,
              case .acquired(let arbiterLease) = arbiter.acquireRemoteMessageLease(for: messageID) else {
            return nil
        }
        return PromoQueueRemoteMessageLease(arbiterLease: arbiterLease, cooldownPolicy: cooldownPolicy)
    }
}

private final class FilteredRemoteMessagingStore: RemoteMessagingStoring {
    var afterIdleMessage: RemoteMessageModel?
    var noTriggerMessage: RemoteMessageModel?
    var shownMessageIDs: Set<String> = []
    var fetchedTriggerFilters: [TriggerFilter] = []
    private(set) var dismissedMessageIDs: [String] = []
    private(set) var updatedShownMessageIDs: [String] = []
    private(set) var hasShownRemoteMessageCallCount = 0
    var dismissRemoteMessageHandler: (() async -> Void)?

    init(afterIdleMessage: RemoteMessageModel? = nil, noTriggerMessage: RemoteMessageModel? = nil) {
        self.afterIdleMessage = afterIdleMessage
        self.noTriggerMessage = noTriggerMessage
    }

    func saveProcessedResult(_ processorResult: RemoteMessagingConfigProcessor.ProcessorResult) async {}
    func fetchRemoteMessagingConfig() -> RemoteMessagingConfig? { nil }

    func fetchScheduledRemoteMessage(surfaces: RemoteMessageSurfaceType, triggerFilter: TriggerFilter) -> RemoteMessageModel? {
        fetchedTriggerFilters.append(triggerFilter)
        let candidate: RemoteMessageModel?
        switch triggerFilter {
        case .specific(.afterIdle):
            candidate = afterIdleMessage
        case .noTrigger:
            candidate = noTriggerMessage
        case .any:
            candidate = afterIdleMessage ?? noTriggerMessage
        }
        guard let candidate, !dismissedMessageIDs.contains(candidate.id) else {
            return nil
        }
        return candidate
    }

    func hasShownRemoteMessage(withID id: String) -> Bool {
        hasShownRemoteMessageCallCount += 1
        return shownMessageIDs.contains(id)
    }

    func fetchShownRemoteMessageIDs() -> [String] {
        Array(shownMessageIDs)
    }

    func dismissRemoteMessage(withID id: String) async {
        await dismissRemoteMessageHandler?()
        dismissedMessageIDs.append(id)
    }

    func fetchDismissedRemoteMessageIDs() -> [String] {
        dismissedMessageIDs
    }

    func updateRemoteMessage(withID id: String, asShown shown: Bool) async {
        updatedShownMessageIDs.append(id)
        if shown {
            shownMessageIDs.insert(id)
        } else {
            shownMessageIDs.remove(id)
        }
    }

    func resetRemoteMessages() async {}
}
