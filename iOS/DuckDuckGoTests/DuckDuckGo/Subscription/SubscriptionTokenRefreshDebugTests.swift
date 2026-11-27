//
//  SubscriptionTokenRefreshDebugTests.swift
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

import BackgroundTasks
import Foundation
import Testing
@testable import DuckDuckGo
import Subscription
@_spi(Testing) import Persistence

struct SubscriptionTokenRefreshDebugTests {

    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Settings

    @available(iOS 16, macOS 13, *)
    @Test("Overrides and the last run are stored, and nil clears them", .timeLimit(.minutes(1)))
    func settingsRoundTrip() {
        let store = InMemoryThrowingKeyValueStore()
        let settings = SubscriptionTokenRefreshDebugSettings(keyValueStore: store)
        let run = SubscriptionTokenRefreshRun(date: date, trigger: .backgroundTask, outcome: "refreshed", nextCheck: date.addingTimeInterval(120))

        settings.maxRefreshTokenAgeOverride = 120
        settings.retryIntervalOverride = 30
        settings.lastRun = run

        let reread = SubscriptionTokenRefreshDebugSettings(keyValueStore: store)
        #expect(reread.maxRefreshTokenAgeOverride == 120)
        #expect(reread.retryIntervalOverride == 30)
        #expect(reread.lastRun == run)

        reread.maxRefreshTokenAgeOverride = nil
        reread.retryIntervalOverride = nil
        reread.lastRun = nil
        #expect(settings.maxRefreshTokenAgeOverride == nil)
        #expect(settings.retryIntervalOverride == nil)
        #expect(settings.lastRun == nil)
    }

    // MARK: - Intervals

    @available(iOS 16, macOS 13, *)
    @Test("Without overrides the keep-alive defaults apply", .timeLimit(.minutes(1)))
    func intervalsDefault() {
        let settings = SubscriptionTokenRefreshDebugSettings(keyValueStore: InMemoryThrowingKeyValueStore())
        let intervals = SubscriptionTokenRefreshIntervals(debugSettings: settings, isInternalUser: { true })

        #expect(intervals.maxRefreshTokenAge() == SubscriptionTokenKeepAlive.defaultMaxRefreshTokenAge)
        #expect(intervals.retryInterval() == SubscriptionTokenKeepAlive.defaultRetryInterval)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Overrides apply to internal users only, read on every call", .timeLimit(.minutes(1)))
    func intervalsInternalOnly() {
        let settings = SubscriptionTokenRefreshDebugSettings(keyValueStore: InMemoryThrowingKeyValueStore())
        var isInternal = true
        let intervals = SubscriptionTokenRefreshIntervals(debugSettings: settings, isInternalUser: { isInternal })
        settings.maxRefreshTokenAgeOverride = 120
        settings.retryIntervalOverride = 30

        #expect(intervals.maxRefreshTokenAge() == 120)
        #expect(intervals.retryInterval() == 30)

        isInternal = false
        #expect(intervals.maxRefreshTokenAge() == SubscriptionTokenKeepAlive.defaultMaxRefreshTokenAge)
        #expect(intervals.retryInterval() == SubscriptionTokenKeepAlive.defaultRetryInterval)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A zero or negative override is ignored", .timeLimit(.minutes(1)))
    func intervalsIgnoreNonPositive() {
        let settings = SubscriptionTokenRefreshDebugSettings(keyValueStore: InMemoryThrowingKeyValueStore())
        let intervals = SubscriptionTokenRefreshIntervals(debugSettings: settings, isInternalUser: { true })
        settings.maxRefreshTokenAgeOverride = 0
        settings.retryIntervalOverride = -5

        #expect(intervals.maxRefreshTokenAge() == SubscriptionTokenKeepAlive.defaultMaxRefreshTokenAge)
        #expect(intervals.retryInterval() == SubscriptionTokenKeepAlive.defaultRetryInterval)
    }

    // MARK: - View model

    @available(iOS 16, macOS 13, *)
    @MainActor
    @Test("Picking intervals stores them and reset clears them with the last run", .timeLimit(.minutes(1)))
    func viewModelStoresAndResets() {
        let settings = SubscriptionTokenRefreshDebugSettings(keyValueStore: InMemoryThrowingKeyValueStore())
        settings.lastRun = SubscriptionTokenRefreshRun(date: date, trigger: .foreground, outcome: "not due", nextCheck: nil)
        let viewModel = makeViewModel(settings: settings)

        viewModel.maxRefreshTokenAge = 120
        viewModel.retryInterval = 30
        #expect(settings.maxRefreshTokenAgeOverride == 120)
        #expect(settings.retryIntervalOverride == 30)

        viewModel.resetToDefaults()
        #expect(settings.maxRefreshTokenAgeOverride == nil)
        #expect(settings.retryIntervalOverride == nil)
        #expect(settings.lastRun == nil)
        #expect(viewModel.lastRun == nil)
    }

    @available(iOS 16, macOS 13, *)
    @MainActor
    @Test("Reload reads the flag, the last run and only this task's pending request", .timeLimit(.minutes(1)))
    func viewModelReload() async {
        let settings = SubscriptionTokenRefreshDebugSettings(keyValueStore: InMemoryThrowingKeyValueStore())
        let run = SubscriptionTokenRefreshRun(date: date, trigger: .debugMenu, outcome: "refreshed", nextCheck: date.addingTimeInterval(120))
        settings.lastRun = run
        let other = BGProcessingTaskRequest(identifier: "com.duckduckgo.app.other")
        let ours = BGProcessingTaskRequest(identifier: SubscriptionTokenRefreshTask.taskIdentifier)
        ours.earliestBeginDate = date.addingTimeInterval(120)
        var requests: [BGTaskRequest] = [other, ours]
        let viewModel = makeViewModel(settings: settings, flagOn: true, pendingRequests: { requests })

        await viewModel.reload()
        #expect(viewModel.isFeatureEnabled)
        #expect(viewModel.isInternalUser)
        #expect(viewModel.lastRun == run)
        #expect(viewModel.pendingTask == .scheduled(date.addingTimeInterval(120)))

        requests = [other]
        await viewModel.reload()
        #expect(viewModel.pendingTask == SubscriptionTokenRefreshDebugViewModel.PendingTask.none)
    }

    @available(iOS 16, macOS 13, *)
    @MainActor
    @Test("Run now posts a run request", .timeLimit(.minutes(1)))
    func viewModelRunNow() {
        let notificationCenter = NotificationCenter()
        var requests = 0
        let observer = notificationCenter.addObserver(forName: .subscriptionTokenRefreshDebugRunRequested, object: nil, queue: nil) { _ in
            requests += 1
        }
        defer { notificationCenter.removeObserver(observer) }
        let viewModel = makeViewModel(settings: SubscriptionTokenRefreshDebugSettings(keyValueStore: InMemoryThrowingKeyValueStore()),
                                      notificationCenter: notificationCenter)

        viewModel.runNow()

        #expect(requests == 1)
    }

    @MainActor
    private func makeViewModel(settings: SubscriptionTokenRefreshDebugSettings,
                               notificationCenter: NotificationCenter = NotificationCenter(),
                               flagOn: Bool = false,
                               pendingRequests: @escaping () async -> [BGTaskRequest] = { [] }) -> SubscriptionTokenRefreshDebugViewModel {
        SubscriptionTokenRefreshDebugViewModel(settings: settings,
                                               notificationCenter: notificationCenter,
                                               isFeatureEnabled: { flagOn },
                                               isInternalUser: { true },
                                               pendingRequests: pendingRequests)
    }
}
