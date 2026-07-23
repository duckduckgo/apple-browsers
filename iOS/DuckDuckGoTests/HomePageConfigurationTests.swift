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

import Testing
import Core
import Foundation
import RemoteMessaging
import RemoteMessagingTestsUtils
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
    @Test(
        "Two appearances before shown storage completes fire two shown pixels and one unique pixel",
        .timeLimit(.minutes(1))
    )
    func twoAppearancesBeforeShownStorageCompletesHaveOneUniqueWinner() async {
        let store = SuspendedShownRemoteMessagingStore()
        defer {
            store.completePendingShownUpdate()
        }
        let pixelReporter = HomePageMessageShownPixelReporterMock()
        let sut = HomePageConfiguration(
            remoteMessagingStore: store,
            subscriptionDataReporter: MockSubscriptionDataReporter(),
            isStillOnboarding: { false },
            shownPixelReporter: pixelReporter
        )
        let message = HomeMessage.remoteMessage(
            remoteMessage: RemoteMessageModel(
                id: "message-a",
                surfaces: .newTabPage,
                content: nil,
                matchingRules: [],
                exclusionRules: [],
                isMetricsEnabled: true
            )
        )

        sut.didAppear(message)
        sut.didAppear(message)
        await store.waitForPendingShownUpdate()

        #expect(pixelReporter.shownCount == 2)
        #expect(pixelReporter.uniqueShownCount == 1)
        #expect(store.shownUpdateCallCount == 1)
        #expect(store.hasShownRemoteMessage(withID: "message-a") == false)

        store.completePendingShownUpdate()
        await store.waitForCompletedShownUpdate()

        #expect(store.hasShownRemoteMessage(withID: "message-a"))
    }

    @available(iOS 16, *)
    @Test(
        "Legacy republish during a pending shown write consults the session reservation",
        .timeLimit(.minutes(1))
    )
    func legacyRepublishBeforeShownStorageCompletesDoesNotRefireUnique() async {
        let store = SuspendedShownRemoteMessagingStore()
        defer {
            store.completePendingShownUpdate()
        }
        let pixelReporter = HomePageMessageShownPixelReporterMock()
        let sut = HomePageConfiguration(
            remoteMessagingStore: store,
            subscriptionDataReporter: MockSubscriptionDataReporter(),
            isStillOnboarding: { false },
            shownPixelReporter: pixelReporter
        )
        let message = HomeMessage.remoteMessage(
            remoteMessage: RemoteMessageModel(
                id: "message-a",
                surfaces: .newTabPage,
                content: nil,
                matchingRules: [],
                exclusionRules: [],
                isMetricsEnabled: true
            )
        )

        sut.didAppear(message)
        await store.waitForPendingShownUpdate()

        // This second call represents the eager legacy republish immediately after
        // promo queue is disabled, while the first async store write is suspended.
        sut.didAppear(message)

        #expect(pixelReporter.shownCount == 2)
        #expect(pixelReporter.uniqueShownCount == 1)
        #expect(store.shownUpdateCallCount == 1)
        #expect(store.hasShownRemoteMessage(withID: "message-a") == false)

        store.completePendingShownUpdate()
        await store.waitForCompletedShownUpdate()
    }

    @Test("An already persisted message fires normal shown without unique shown or another store update")
    func alreadyPersistedMessageDoesNotFireUniqueOrUpdateStore() {
        let store = MockRemoteMessagingStore(shownRemoteMessagesIDs: ["message-a"])
        let pixelReporter = HomePageMessageShownPixelReporterMock()
        let sut = HomePageConfiguration(
            remoteMessagingStore: store,
            subscriptionDataReporter: MockSubscriptionDataReporter(),
            isStillOnboarding: { false },
            shownPixelReporter: pixelReporter
        )
        let message = HomeMessage.remoteMessage(
            remoteMessage: RemoteMessageModel(
                id: "message-a",
                surfaces: .newTabPage,
                content: nil,
                matchingRules: [],
                exclusionRules: [],
                isMetricsEnabled: true
            )
        )

        sut.didAppear(message)

        #expect(pixelReporter.shownCount == 1)
        #expect(pixelReporter.uniqueShownCount == 0)
        #expect(store.updateRemoteMessageCalls == 0)
    }
}

final class HomePageMessageShownPixelReporterMock: HomePageMessageShownPixelReporting {
    private(set) var firedPixels = [Pixel.Event]()

    var shownCount: Int {
        firedPixels.filter { $0.name == Pixel.Event.remoteMessageShown.name }.count
    }

    var uniqueShownCount: Int {
        firedPixels.filter { $0.name == Pixel.Event.remoteMessageShownUnique.name }.count
    }

    func fire(_ pixel: Pixel.Event, withAdditionalParameters parameters: [String: String]) {
        firedPixels.append(pixel)
    }
}

final class SuspendedShownRemoteMessagingStore: RemoteMessagingStoring, @unchecked Sendable {
    private let scheduledRemoteMessage: RemoteMessageModel?
    private let onShownUpdateStarted: () -> Void
    private let onShownUpdateCompleted: () -> Void
    private let lock = NSLock()
    private var shownRemoteMessageIDs = Set<String>()
    private var _shownUpdateCallCount = 0
    private var pendingShownUpdateContinuation: CheckedContinuation<Void, Never>?
    private var pendingShownUpdateWaiters = [CheckedContinuation<Void, Never>]()
    private var completedShownUpdateWaiters = [CheckedContinuation<Void, Never>]()
    private var shownUpdateCompletionRequested = false
    private var didCompleteShownUpdate = false

    var shownUpdateCallCount: Int {
        withLock {
            _shownUpdateCallCount
        }
    }

    init(
        scheduledRemoteMessage: RemoteMessageModel? = nil,
        onShownUpdateStarted: @escaping () -> Void = {},
        onShownUpdateCompleted: @escaping () -> Void = {}
    ) {
        self.scheduledRemoteMessage = scheduledRemoteMessage
        self.onShownUpdateStarted = onShownUpdateStarted
        self.onShownUpdateCompleted = onShownUpdateCompleted
    }

    func saveProcessedResult(_ processorResult: RemoteMessagingConfigProcessor.ProcessorResult) async {}

    func fetchRemoteMessagingConfig() -> RemoteMessagingConfig? {
        nil
    }

    func fetchScheduledRemoteMessage(
        surfaces: RemoteMessageSurfaceType,
        triggerFilter: TriggerFilter
    ) -> RemoteMessageModel? {
        scheduledRemoteMessage
    }

    func hasShownRemoteMessage(withID id: String) -> Bool {
        withLock {
            shownRemoteMessageIDs.contains(id)
        }
    }

    func fetchShownRemoteMessageIDs() -> [String] {
        withLock {
            Array(shownRemoteMessageIDs)
        }
    }

    func dismissRemoteMessage(withID id: String) async {}

    func fetchDismissedRemoteMessageIDs() -> [String] {
        []
    }

    func updateRemoteMessage(withID id: String, asShown shown: Bool) async {
        guard shown else {
            withLock {
                shownRemoteMessageIDs.remove(id)
            }
            return
        }

        withLock {
            _shownUpdateCallCount += 1
        }
        onShownUpdateStarted()

        await withCheckedContinuation { continuation in
            let state = withLock {
                if shownUpdateCompletionRequested {
                    return (shouldResumeUpdate: true, waiters: [CheckedContinuation<Void, Never>]())
                }

                pendingShownUpdateContinuation = continuation
                defer {
                    pendingShownUpdateWaiters.removeAll()
                }
                return (shouldResumeUpdate: false, waiters: pendingShownUpdateWaiters)
            }
            state.waiters.forEach { $0.resume() }
            if state.shouldResumeUpdate {
                continuation.resume()
            }
        }

        let waiters = withLock {
            shownRemoteMessageIDs.insert(id)
            didCompleteShownUpdate = true
            defer {
                completedShownUpdateWaiters.removeAll()
            }
            return completedShownUpdateWaiters
        }
        waiters.forEach { $0.resume() }
        onShownUpdateCompleted()
    }

    func resetRemoteMessages() async {}

    func waitForPendingShownUpdate() async {
        await withCheckedContinuation { continuation in
            let isPending = withLock {
                if pendingShownUpdateContinuation != nil {
                    return true
                }
                pendingShownUpdateWaiters.append(continuation)
                return false
            }
            if isPending {
                continuation.resume()
            }
        }
    }

    func completePendingShownUpdate() {
        let continuation = withLock {
            shownUpdateCompletionRequested = true
            defer {
                pendingShownUpdateContinuation = nil
            }
            return pendingShownUpdateContinuation
        }
        continuation?.resume()
    }

    func waitForCompletedShownUpdate() async {
        await withCheckedContinuation { continuation in
            let isCompleted = withLock {
                if didCompleteShownUpdate {
                    return true
                }
                completedShownUpdateWaiters.append(continuation)
                return false
            }
            if isCompleted {
                continuation.resume()
            }
        }
    }

    private func withLock<Result>(_ operation: () -> Result) -> Result {
        lock.lock()
        defer {
            lock.unlock()
        }
        return operation()
    }
}
