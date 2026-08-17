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

    @available(iOS 16, *)
    @Test("Coordinated initialization defers RMF selection until explicit preparation", .timeLimit(.minutes(1)))
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

    @available(iOS 16, *)
    @Test("Background launch with an attached NTP acquires at the foreground-ready checkpoint", .timeLimit(.minutes(1)))
    func backgroundLaunchWithAttachedNTPPreparesWhenForegroundReady() {
        let store = FilteredRemoteMessagingStore(noTriggerMessage: makeRemoteMessage(id: "message"))
        let gate = MockPromoGate()
        let sut = makeCoordinatedConfiguration(
            store: store,
            gate: gate,
            isRMFAdmissionEnabled: false
        )

        sut.prepareForNTP(openedAfterIdle: true)

        #expect(store.fetchedTriggerFilters.isEmpty)
        #expect(gate.acquiredMessageIDs.isEmpty)

        sut.handleAppForegrounded()
        sut.prepareForNTP(openedAfterIdle: false)

        #expect(store.fetchedTriggerFilters == [.noTrigger])
        #expect(gate.acquiredMessageIDs == ["message"])
        #expect(sut.homeMessages == [.remoteMessage(remoteMessage: makeRemoteMessage(id: "message"))])
    }

    @available(iOS 16, *)
    @Test("Ownerless foreground without an attached NTP remains inert", .timeLimit(.minutes(1)))
    func ownerlessForegroundWithoutAttachedNTPRemainsInert() async {
        let notificationCenter = NotificationCenter()
        let store = FilteredRemoteMessagingStore(noTriggerMessage: makeRemoteMessage(id: "message"))
        let gate = MockPromoGate()
        let sut = makeCoordinatedConfiguration(
            store: store,
            gate: gate,
            isRMFAdmissionEnabled: false,
            notificationCenter: notificationCenter
        )

        sut.handleAppForegrounded()
        notificationCenter.post(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange, object: nil)
        await Task.yield()

        #expect(store.fetchedTriggerFilters.isEmpty)
        #expect(gate.acquiredMessageIDs.isEmpty)
        #expect(sut.homeMessages.isEmpty)
    }

    @available(iOS 16, *)
    @Test("After-idle fallback pins the actual no-trigger filter for the ownership", .timeLimit(.minutes(1)))
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

    @available(iOS 16, *)
    @Test("Unsupported content is rejected before gate acquisition", .timeLimit(.minutes(1)))
    func unsupportedContentDoesNotAcquire() {
        let unsupported = makeRemoteMessage(id: "unsupported", content: nil)
        let store = FilteredRemoteMessagingStore(noTriggerMessage: unsupported)
        let gate = MockPromoGate()
        let sut = makeCoordinatedConfiguration(store: store, gate: gate)

        sut.prepareForNTP(openedAfterIdle: false)

        #expect(gate.acquiredMessageIDs.isEmpty)
        #expect(sut.homeMessages.isEmpty)
    }

    @available(iOS 16, *)
    @Test("A coordinated store refresh retries a denied candidate with the last preparation policy", .timeLimit(.minutes(1)))
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

    @available(iOS 16, *)
    @Test("A store notification cannot acquire after the last NTP host deactivates, but reactivation can", .timeLimit(.minutes(1)))
    func storeNotificationAfterLastHostDeactivationDoesNotAcquireButReactivationDoes() async {
        let notificationCenter = NotificationCenter()
        let message = makeRemoteMessage(id: "message")
        let store = FilteredRemoteMessagingStore()
        let gate = MockPromoGate()
        let sut = makeCoordinatedConfiguration(store: store, gate: gate, notificationCenter: notificationCenter)

        sut.prepareForNTP(openedAfterIdle: false, host: .newTabPage)
        sut.deactivateNTPHost(.newTabPage)
        store.noTriggerMessage = message
        store.fetchedTriggerFilters.removeAll()

        notificationCenter.post(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange, object: nil)
        await Task.yield()

        #expect(store.fetchedTriggerFilters.isEmpty)
        #expect(gate.acquiredMessageIDs.isEmpty)
        #expect(gate.arbiter.snapshot.owner == nil)
        #expect(sut.homeMessages.isEmpty)

        sut.prepareForNTP(openedAfterIdle: false, host: .newTabPage)

        #expect(store.fetchedTriggerFilters == [.noTrigger])
        #expect(gate.acquiredMessageIDs == ["message"])
        #expect(sut.homeMessages == [.remoteMessage(remoteMessage: message)])
    }

    @available(iOS 16, *)
    @Test("A store notification acquires while an eligible NTP host remains active", .timeLimit(.minutes(1)))
    func storeNotificationAcquiresWhileEligibleHostRemainsActive() async {
        let notificationCenter = NotificationCenter()
        let message = makeRemoteMessage(id: "message")
        let store = FilteredRemoteMessagingStore()
        let gate = MockPromoGate()
        let sut = makeCoordinatedConfiguration(store: store, gate: gate, notificationCenter: notificationCenter)

        sut.prepareForNTP(openedAfterIdle: false, host: .newTabPage)
        store.noTriggerMessage = message
        store.fetchedTriggerFilters.removeAll()

        notificationCenter.post(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange, object: nil)
        await Task.yield()

        #expect(store.fetchedTriggerFilters == [.noTrigger])
        #expect(gate.acquiredMessageIDs == ["message"])
        #expect(sut.homeMessages == [.remoteMessage(remoteMessage: message)])
    }

    @available(iOS 16, *)
    @Test("Deactivating the most recent NTP host restores the remaining host policy", .timeLimit(.minutes(1)))
    func deactivatingMostRecentHostFallsBackToRemainingHostPolicy() async {
        let notificationCenter = NotificationCenter()
        let message = makeRemoteMessage(id: "message")
        let store = FilteredRemoteMessagingStore()
        let gate = MockPromoGate()
        let sut = makeCoordinatedConfiguration(store: store, gate: gate, notificationCenter: notificationCenter)

        sut.prepareForNTP(openedAfterIdle: false, host: .newTabPage)
        sut.prepareForNTP(openedAfterIdle: true, host: .unifiedInput)
        sut.deactivateNTPHost(.unifiedInput)
        store.noTriggerMessage = message
        store.fetchedTriggerFilters.removeAll()

        notificationCenter.post(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange, object: nil)
        await Task.yield()

        #expect(store.fetchedTriggerFilters == [.noTrigger])
        #expect(gate.acquiredMessageIDs == ["message"])
        #expect(sut.homeMessages == [.remoteMessage(remoteMessage: message)])
    }

    @available(iOS 16, *)
    @Test("One store notification selects once and synchronously converges all source consumers", .timeLimit(.minutes(1)))
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

    @available(iOS 16, *)
    @Test("A modal-owned slot prevents RMF publication and store mutation", .timeLimit(.minutes(1)))
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

    @available(iOS 16, *)
    @Test("The complete ownership context is retained before RMF publication", .timeLimit(.minutes(1)))
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

    @available(iOS 16, *)
    @Test("A published RMF keeps publication, identity, and lease through background and foreground", .timeLimit(.minutes(1)))
    func ownershipSurvivesBackgroundAndForeground() {
        let message = makeRemoteMessage(id: "message")
        let store = FilteredRemoteMessagingStore(noTriggerMessage: message)
        let gate = MockPromoGate()
        let sut = makeCoordinatedConfiguration(store: store, gate: gate)

        sut.prepareForNTP(openedAfterIdle: false)
        let context = sut.presentationContext(for: .remoteMessage(remoteMessage: message))
        let owner = gate.arbiter.snapshot.owner
        var contentDidChangeCount = 0
        let cancellable = sut.contentDidChangePublisher.sink {
            contentDidChangeCount += 1
        }

        sut.handleAppBackgrounded()
        #expect(sut.homeMessages == [.remoteMessage(remoteMessage: message)])
        #expect(sut.presentationContext(for: .remoteMessage(remoteMessage: message)) == context)
        #expect(gate.arbiter.snapshot.owner == owner)

        sut.handleAppForegrounded()
        sut.prepareForNTP(openedAfterIdle: false)

        #expect(sut.homeMessages == [.remoteMessage(remoteMessage: message)])
        #expect(sut.presentationContext(for: .remoteMessage(remoteMessage: message)) == context)
        #expect(gate.arbiter.snapshot.owner == owner)
        #expect(gate.acquiredMessageIDs == ["message"])
        #expect(contentDidChangeCount == 0)
        withExtendedLifetime(cancellable) {}
    }

    @available(iOS 16, *)
    @Test("Only the first appearance is confirmed across background and foreground", .timeLimit(.minutes(1)))
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
        sut.handleAppForegrounded()
        sut.didAppear(.remoteMessage(remoteMessage: message), presentationContext: context)

        #expect(gate.cooldownPolicy.recordConfirmedRemoteMessageAppearanceCallCount == 1)
        #expect(store.hasShownRemoteMessageCallCount == 1)
        #expect(sut.presentationContext(for: .remoteMessage(remoteMessage: message)) == context)
    }

    @available(iOS 16, *)
    @Test("An owned RMF survives host disappearance and foreground with one appearance", .timeLimit(.minutes(1)))
    func ownedRemoteMessageSurvivesHostDeactivationAndForegroundWithOneAppearance() {
        let message = makeRemoteMessage(id: "message")
        let store = FilteredRemoteMessagingStore(noTriggerMessage: message)
        let gate = MockPromoGate()
        let sut = makeCoordinatedConfiguration(store: store, gate: gate)

        sut.prepareForNTP(openedAfterIdle: false, host: .newTabPage)
        let context = sut.presentationContext(for: .remoteMessage(remoteMessage: message))
        sut.didAppear(.remoteMessage(remoteMessage: message), presentationContext: context)

        sut.deactivateNTPHost(.newTabPage)
        sut.handleAppBackgrounded()
        sut.handleAppForegrounded()
        sut.didAppear(.remoteMessage(remoteMessage: message), presentationContext: context)

        #expect(sut.homeMessages == [.remoteMessage(remoteMessage: message)])
        #expect(sut.presentationContext(for: .remoteMessage(remoteMessage: message)) == context)
        #expect(gate.arbiter.snapshot.owner != nil)
        #expect(gate.acquiredMessageIDs == ["message"])
        #expect(gate.cooldownPolicy.recordConfirmedRemoteMessageAppearanceCallCount == 1)
        #expect(store.hasShownRemoteMessageCallCount == 1)
    }

    @available(iOS 16, *)
    @Test("An appeared RMF keeps history and blocks modal evaluation after foreground", .timeLimit(.minutes(1)))
    func appearedRemoteMessageRetainsOwnershipAndBlocksModalAfterForeground() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let message = makeRemoteMessage(id: "message")
        let store = FilteredRemoteMessagingStore(noTriggerMessage: message)
        let (shownPersistenceEvents, shownPersistenceContinuation) = AsyncStream.makeStream(of: Void.self)
        defer { shownPersistenceContinuation.finish() }
        store.onShownPersistence = { persistedMessageID in
            guard persistedMessageID == message.id else { return }
            shownPersistenceContinuation.yield()
            shownPersistenceContinuation.finish()
        }
        let history = RecordingPromoQueueRemoteMessageHistory()
        let arbiter = PromoQueueLeaseArbiter()
        let policy = PromoQueueCooldownPolicy(
            modalPresentationStore: MockPromptCooldownStore(),
            remoteMessageHistory: history,
            dateProvider: { now }
        )
        let launchSourceManager = MockLaunchSourceManager()
        launchSourceManager.source = .standard
        let modalManager = MockModalPromptCoordinationManager()
        let service = PromoCoordinationService(
            launchSourceManager: launchSourceManager,
            modalPromptCoordinationManager: modalManager,
            mode: .coordinated,
            promoQueueLeaseArbiter: arbiter,
            promoQueueCooldownPolicy: policy
        )
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
        let owner = arbiter.snapshot.owner
        var shownPersistenceIterator = shownPersistenceEvents.makeAsyncIterator()
        guard await shownPersistenceIterator.next() != nil else {
            Issue.record("Expected shown persistence to be invoked")
            return
        }

        sut.handleAppBackgrounded()
        sut.handleAppForegrounded()
        service.presentModalPromptIfNeeded(from: MockModalPromptPresenter())

        #expect(history.recordedDates == [now])
        #expect(store.hasShownRemoteMessageCallCount == 1)
        #expect(store.updatedShownMessageIDs == ["message"])
        #expect(sut.homeMessages == [.remoteMessage(remoteMessage: message)])
        #expect(sut.presentationContext(for: .remoteMessage(remoteMessage: message)) == context)
        #expect(arbiter.snapshot.owner == owner)
        #expect(!modalManager.didCallPresentModalPromptIfNeeded)
    }

    @available(iOS 16, *)
    @Test("A never-appeared RMF keeps ownership through background without writing history", .timeLimit(.minutes(1)))
    func neverAppearedRemoteMessageRetainsOwnershipAcrossBackground() {
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
        let context = sut.presentationContext(for: .remoteMessage(remoteMessage: message))
        let owner = arbiter.snapshot.owner
        sut.handleAppBackgrounded()
        sut.handleAppForegrounded()

        #expect(history.recordedDates.isEmpty)
        #expect(sut.presentationContext(for: .remoteMessage(remoteMessage: message)) == context)
        #expect(arbiter.snapshot.owner == owner)
        #expect(sut.homeMessages == [.remoteMessage(remoteMessage: message)])
    }

    @available(iOS 16, *)
    @Test("Backgrounding without an owner cannot acquire and foregrounding remains inert", .timeLimit(.minutes(1)))
    func backgroundWithoutOwnerDoesNotAcquire() async {
        let notificationCenter = NotificationCenter()
        let store = FilteredRemoteMessagingStore(noTriggerMessage: makeRemoteMessage(id: "message"))
        let gate = MockPromoGate()
        let sut = makeCoordinatedConfiguration(store: store, gate: gate, notificationCenter: notificationCenter)

        sut.handleAppBackgrounded()
        sut.prepareForNTP(openedAfterIdle: false)
        notificationCenter.post(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange, object: nil)
        await Task.yield()
        sut.handleAppForegrounded()

        #expect(store.fetchedTriggerFilters.isEmpty)
        #expect(gate.acquiredMessageIDs.isEmpty)
        #expect(sut.homeMessages.isEmpty)
    }

    @available(iOS 16, *)
    @Test("An inactive store refresh retains the same valid owner", .timeLimit(.minutes(1)))
    func inactiveStoreRefreshRetainsValidOwner() async {
        let notificationCenter = NotificationCenter()
        let message = makeRemoteMessage(id: "message")
        let store = FilteredRemoteMessagingStore(noTriggerMessage: message)
        let gate = MockPromoGate()
        let sut = makeCoordinatedConfiguration(store: store, gate: gate, notificationCenter: notificationCenter)
        sut.prepareForNTP(openedAfterIdle: false)
        let context = sut.presentationContext(for: .remoteMessage(remoteMessage: message))
        let owner = gate.arbiter.snapshot.owner
        store.fetchedTriggerFilters.removeAll()

        sut.handleAppBackgrounded()
        notificationCenter.post(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange, object: nil)
        await Task.yield()

        #expect(store.fetchedTriggerFilters == [.noTrigger])
        #expect(gate.acquiredMessageIDs == ["message"])
        #expect(sut.presentationContext(for: .remoteMessage(remoteMessage: message)) == context)
        #expect(gate.arbiter.snapshot.owner == owner)
        #expect(sut.homeMessages == [.remoteMessage(remoteMessage: message)])
    }

    @available(iOS 16, *)
    @Test("An inactive replacement releases the old owner without acquiring the replacement", .timeLimit(.minutes(1)))
    func inactiveReplacementDoesNotAcquire() async {
        let notificationCenter = NotificationCenter()
        let original = makeRemoteMessage(id: "original")
        let replacement = makeRemoteMessage(id: "replacement")
        let store = FilteredRemoteMessagingStore(noTriggerMessage: original)
        let gate = MockPromoGate()
        let sut = makeCoordinatedConfiguration(store: store, gate: gate, notificationCenter: notificationCenter)
        sut.prepareForNTP(openedAfterIdle: false)

        sut.handleAppBackgrounded()
        store.noTriggerMessage = replacement
        notificationCenter.post(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange, object: nil)
        await Task.yield()

        #expect(gate.acquiredMessageIDs == ["original"])
        #expect(gate.arbiter.snapshot.owner == nil)
        #expect(sut.homeMessages.isEmpty)

        sut.handleAppForegrounded()

        #expect(gate.acquiredMessageIDs == ["original"])
        #expect(sut.homeMessages.isEmpty)
    }

    @available(iOS 16, *)
    @Test("Foreground revalidation releases an invalid owner before modal evaluation", .timeLimit(.minutes(1)))
    func foregroundReleasesInvalidOwnerBeforeModalEvaluation() {
        let message = makeRemoteMessage(id: "message")
        let store = FilteredRemoteMessagingStore(noTriggerMessage: message)
        let arbiter = PromoQueueLeaseArbiter()
        let cooldownPolicy = MockPromoQueueCooldownPolicy()
        let launchSourceManager = MockLaunchSourceManager()
        launchSourceManager.source = .standard
        let modalManager = MockModalPromptCoordinationManager()
        let service = PromoCoordinationService(
            launchSourceManager: launchSourceManager,
            modalPromptCoordinationManager: modalManager,
            mode: .coordinated,
            promoQueueLeaseArbiter: arbiter,
            promoQueueCooldownPolicy: cooldownPolicy
        )
        let sut = HomePageConfiguration(
            remoteMessagingStore: store,
            subscriptionDataReporter: MockSubscriptionDataReporter(),
            isStillOnboarding: { false },
            promoGate: service
        )
        sut.prepareForNTP(openedAfterIdle: false)

        sut.handleAppBackgrounded()
        store.noTriggerMessage = nil
        sut.handleAppForegrounded()
        service.presentModalPromptIfNeeded(from: MockModalPromptPresenter())

        #expect(sut.homeMessages.isEmpty)
        #expect(modalManager.didCallPresentModalPromptIfNeeded)
        #expect(arbiter.snapshot.hasModalLease)
    }

    @available(iOS 16, *)
    @Test("Legacy lifecycle hooks leave RMF behavior unchanged", .timeLimit(.minutes(1)))
    func legacyLifecycleHooksAreNoOp() {
        let message = makeRemoteMessage(id: "message")
        let store = FilteredRemoteMessagingStore(noTriggerMessage: message)
        let sut = HomePageConfiguration(
            remoteMessagingStore: store,
            subscriptionDataReporter: MockSubscriptionDataReporter(),
            isStillOnboarding: { false }
        )
        let homeMessages = sut.homeMessages

        sut.prepareForNTP(openedAfterIdle: true, host: .unifiedInput)
        sut.deactivateNTPHost(.unifiedInput)
        sut.handleAppBackgrounded()
        sut.handleAppForegrounded()

        #expect(sut.homeMessages == homeMessages)
        #expect(sut.homeMessages == [.remoteMessage(remoteMessage: message)])
        #expect(store.fetchedTriggerFilters == [.noTrigger])
    }

    @available(iOS 16, *)
    @Test("A dismissal made stale while awaiting cannot release a reacquired same-ID owner", .timeLimit(.minutes(1)))
    func staleDismissalCompletionCannotReleaseReacquiredOwner() async {
        let notificationCenter = NotificationCenter()
        let message = makeRemoteMessage(id: "message")
        let store = FilteredRemoteMessagingStore(noTriggerMessage: message)
        let gate = MockPromoGate()
        let sut = makeCoordinatedConfiguration(store: store, gate: gate, notificationCenter: notificationCenter)
        sut.prepareForNTP(openedAfterIdle: false)
        let oldContext = sut.presentationContext(for: .remoteMessage(remoteMessage: message))
        let (dismissalEnteredEvents, dismissalEnteredContinuation) = AsyncStream.makeStream(of: Void.self)
        let (dismissalResumeEvents, dismissalResumeContinuation) = AsyncStream.makeStream(of: Void.self)
        store.dismissRemoteMessageHandler = {
            dismissalEnteredContinuation.yield()
            dismissalEnteredContinuation.finish()
            var dismissalResumeIterator = dismissalResumeEvents.makeAsyncIterator()
            _ = await dismissalResumeIterator.next()
        }

        let dismissalTask = Task {
            await sut.dismissHomeMessage(
                .remoteMessage(remoteMessage: message),
                presentationContext: oldContext
            )
        }
        defer {
            dismissalEnteredContinuation.finish()
            dismissalResumeContinuation.finish()
            dismissalTask.cancel()
        }
        var dismissalEnteredIterator = dismissalEnteredEvents.makeAsyncIterator()
        guard await dismissalEnteredIterator.next() != nil else {
            Issue.record("Expected dismissal persistence to begin")
            return
        }

        store.noTriggerMessage = nil
        notificationCenter.post(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange, object: nil)
        await Task.yield()
        store.noTriggerMessage = message
        sut.prepareForNTP(openedAfterIdle: false)
        let newContext = sut.presentationContext(for: .remoteMessage(remoteMessage: message))
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
        defer { notificationCenter.removeObserver(notificationObserver) }
        dismissalResumeContinuation.yield()
        dismissalResumeContinuation.finish()
        await dismissalTask.value

        #expect(reconciliationNotificationCount == 1)
        #expect(ownerAtReconciliationNotification != nil)

        await Task.yield()

        #expect(oldContext != newContext)
        #expect(sut.presentationContext(for: .remoteMessage(remoteMessage: message)) == nil)
        #expect(gate.arbiter.snapshot.owner == nil)
        #expect(store.dismissedMessageIDs == ["message"])
    }

    @available(iOS 16, *)
    @Test("Ordered teardown signals while the old lease still owns the slot", .timeLimit(.minutes(1)))
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

    @available(iOS 16, *)
    @Test("Replacement unpublishes before releasing the old owner, then publishes a new identity", .timeLimit(.minutes(1)))
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

    @available(iOS 16, *)
    @Test("Onboarding suppression unpublishes before releasing current ownership", .timeLimit(.minutes(1)))
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
    var onShownPersistence: ((String) -> Void)?

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
            onShownPersistence?(id)
        } else {
            shownMessageIDs.remove(id)
        }
    }

    func resetRemoteMessages() async {}
}
