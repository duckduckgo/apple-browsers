//
//  SubscriptionTokenRefreshTaskTests.swift
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
@_spi(Testing) import Networking
@_spi(Testing) import Persistence
@_spi(Testing) import PixelKit

struct SubscriptionTokenRefreshTaskTests {

    private let issuedAt = Date(timeIntervalSince1970: 1_800_000_000)
    private let identifier = SubscriptionTokenRefreshTask.taskIdentifier

    private func token(issuedAt: Date) -> TokenContainer {
        OAuthTokensFactory.makeTokenContainer(refreshTokenIssuedAt: issuedAt, refreshTokenExpiresAt: issuedAt.addingTimeInterval(.days(30)))
    }

    private struct Fixture {
        let flag: FlagState
        let provider: FakeTokenProvider
        let scheduler: RecordingScheduler
        let notificationCenter: NotificationCenter
        let debugSettings: SubscriptionTokenRefreshDebugSettings
        let internalUser: FlagState
        let pixels: PixelKitMock
        let refreshTask: SubscriptionTokenRefreshTask
    }

    /// Builds the task the way `SubscriptionService` does, with debug overrides that apply while `internalUser` is on.
    private func makeFixture(flagOn: Bool, token: TokenContainer?, now: Date, internalUser: Bool = true) -> Fixture {
        let flag = FlagState(isOn: flagOn)
        let internalUserState = FlagState(isOn: internalUser)
        let provider = FakeTokenProvider(token: token)
        let scheduler = RecordingScheduler()
        let notificationCenter = NotificationCenter()
        let debugSettings = SubscriptionTokenRefreshDebugSettings(keyValueStore: InMemoryThrowingKeyValueStore())
        let intervals = SubscriptionTokenRefreshIntervals(debugSettings: debugSettings, isInternalUser: { internalUserState.isOn })
        let pixels = PixelKitMock()
        let keepAlive = SubscriptionTokenKeepAlive(tokenProvider: provider,
                                                   isEnabled: { flag.isOn },
                                                   maxRefreshTokenAge: intervals.maxRefreshTokenAge,
                                                   retryInterval: intervals.retryInterval,
                                                   now: { now })
        let refreshTask = SubscriptionTokenRefreshTask(keepAlive: keepAlive,
                                                       scheduler: scheduler,
                                                       debugSettings: debugSettings,
                                                       retryInterval: intervals.retryInterval,
                                                       pixelFiring: pixels,
                                                       notificationCenter: notificationCenter,
                                                       now: { now })
        return Fixture(flag: flag, provider: provider, scheduler: scheduler, notificationCenter: notificationCenter,
                       debugSettings: debugSettings, internalUser: internalUserState, pixels: pixels, refreshTask: refreshTask)
    }

    // MARK: - Registration

    @available(iOS 16, macOS 13, *)
    @Test("Registers the launch handler for its identifier once", .timeLimit(.minutes(1)))
    func registersHandler() {
        let fixture = makeFixture(flagOn: true, token: nil, now: issuedAt)

        fixture.refreshTask.register()

        #expect(fixture.scheduler.registeredIdentifiers == [identifier])
    }

    @available(iOS 16, macOS 13, *)
    @Test("The registered launch handler runs the keep-alive and completes the task", .timeLimit(.minutes(1)))
    func launchHandlerCompletesTask() async throws {
        let fixture = makeFixture(flagOn: true, token: token(issuedAt: issuedAt), now: issuedAt.addingTimeInterval(.days(1)))
        fixture.refreshTask.register()
        let task = FakeBGTask(identifier: identifier)

        fixture.scheduler.launch(identifier, task: task)

        try await waitUntil { task.completions == [true] }
        #expect(fixture.scheduler.events == [.submit(issuedAt.addingTimeInterval(.days(15)))])
    }

    // MARK: - Foreground

    @available(iOS 16, macOS 13, *)
    @Test("On with a young token: schedules a network-requiring task for when the refresh token turns 15 days old", .timeLimit(.minutes(1)))
    func schedulesForRefreshDate() async {
        let fixture = makeFixture(flagOn: true, token: token(issuedAt: issuedAt), now: issuedAt.addingTimeInterval(.days(1)))

        await fixture.refreshTask.refreshAndSchedule().value

        #expect(fixture.scheduler.events == [.submit(issuedAt.addingTimeInterval(.days(15)))])
        let request = fixture.scheduler.submittedRequests.first as? BGProcessingTaskRequest
        #expect(request?.identifier == identifier)
        #expect(request?.requiresNetworkConnectivity == true)
        #expect(!fixture.provider.requestedPolicies.contains(.localForceRefresh))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Off from the start: cancels any scheduled task and reads nothing", .timeLimit(.minutes(1)))
    func offCancels() async {
        let fixture = makeFixture(flagOn: false, token: token(issuedAt: issuedAt), now: issuedAt.addingTimeInterval(.days(20)))

        await fixture.refreshTask.refreshAndSchedule().value

        #expect(fixture.scheduler.events == [.cancel])
        #expect(fixture.provider.requestedPolicies.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("No token: cancels any scheduled task", .timeLimit(.minutes(1)))
    func noTokenCancels() async {
        let fixture = makeFixture(flagOn: true, token: nil, now: issuedAt)

        await fixture.refreshTask.refreshAndSchedule().value

        #expect(fixture.scheduler.events == [.cancel])
    }

    @available(iOS 16, macOS 13, *)
    @Test("on > off > on: schedules, cancels, then schedules again", .timeLimit(.minutes(1)))
    func onOffOn() async {
        let fixture = makeFixture(flagOn: true, token: token(issuedAt: issuedAt), now: issuedAt.addingTimeInterval(.days(1)))
        let refreshDate = issuedAt.addingTimeInterval(.days(15))

        await fixture.refreshTask.refreshAndSchedule().value
        fixture.flag.isOn = false
        await fixture.refreshTask.refreshAndSchedule().value
        fixture.flag.isOn = true
        await fixture.refreshTask.refreshAndSchedule().value

        #expect(fixture.scheduler.events == [.submit(refreshDate), .cancel, .submit(refreshDate)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("off > on > off: cancels, schedules, then cancels again", .timeLimit(.minutes(1)))
    func offOnOff() async {
        let fixture = makeFixture(flagOn: false, token: token(issuedAt: issuedAt), now: issuedAt.addingTimeInterval(.days(1)))

        await fixture.refreshTask.refreshAndSchedule().value
        fixture.flag.isOn = true
        await fixture.refreshTask.refreshAndSchedule().value
        fixture.flag.isOn = false
        await fixture.refreshTask.refreshAndSchedule().value

        #expect(fixture.scheduler.events == [.cancel, .submit(issuedAt.addingTimeInterval(.days(15))), .cancel])
    }

    // MARK: - Background task

    @available(iOS 16, macOS 13, *)
    @Test("Launched with a due token: refreshes, schedules the next check and completes successfully", .timeLimit(.minutes(1)))
    func backgroundRefresh() async {
        let now = issuedAt.addingTimeInterval(.days(15))
        let fixture = makeFixture(flagOn: true, token: token(issuedAt: issuedAt), now: now)
        fixture.provider.refreshedToken = token(issuedAt: now)
        let task = FakeBGTask(identifier: identifier)

        await fixture.refreshTask.handle(task).value

        #expect(fixture.provider.requestedPolicies.contains(.localForceRefresh))
        #expect(fixture.scheduler.events == [.submit(now.addingTimeInterval(.days(15)))])
        #expect(task.completions == [true])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Launched while off: completes, cancels and doesn't reschedule", .timeLimit(.minutes(1)))
    func backgroundWhileOff() async {
        let fixture = makeFixture(flagOn: false, token: token(issuedAt: issuedAt), now: issuedAt.addingTimeInterval(.days(20)))
        let task = FakeBGTask(identifier: identifier)

        await fixture.refreshTask.handle(task).value

        #expect(fixture.provider.requestedPolicies.isEmpty)
        #expect(fixture.scheduler.events == [.cancel])
        #expect(task.completions == [true])
    }

    @available(iOS 16, macOS 13, *)
    @Test("A failed background refresh is retried after 6 hours and completes unsuccessfully", .timeLimit(.minutes(1)))
    func backgroundFailure() async {
        let now = issuedAt.addingTimeInterval(.days(16))
        let fixture = makeFixture(flagOn: true, token: token(issuedAt: issuedAt), now: now)
        fixture.provider.refreshError = URLError(.notConnectedToInternet)
        let task = FakeBGTask(identifier: identifier)

        await fixture.refreshTask.handle(task).value

        #expect(fixture.scheduler.events == [.submit(now.addingTimeInterval(.hours(6)))])
        #expect(task.completions == [false])
    }

    @available(iOS 16, macOS 13, *)
    @Test("A background run that can't read the token keeps the task scheduled, 6 hours later", .timeLimit(.minutes(1)))
    func backgroundUnreadableToken() async {
        let now = issuedAt.addingTimeInterval(.days(16))
        let fixture = makeFixture(flagOn: true, token: token(issuedAt: issuedAt), now: now)
        fixture.provider.stateOverride = .readError
        let task = FakeBGTask(identifier: identifier)

        await fixture.refreshTask.handle(task).value

        #expect(fixture.scheduler.events == [.submit(now.addingTimeInterval(.hours(6)))])
        #expect(task.completions == [false])
        #expect(fixture.provider.requestedPolicies.isEmpty)

        fixture.provider.stateOverride = nil
        fixture.provider.refreshedToken = token(issuedAt: now)
        await fixture.refreshTask.handle(FakeBGTask(identifier: identifier)).value
        #expect(fixture.provider.requestedPolicies.contains(.localForceRefresh))
        #expect(fixture.scheduler.events.last == .submit(now.addingTimeInterval(.days(15))))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Expiring during the refresh: completes once, unsuccessfully, and reschedules after 6 hours", .timeLimit(.minutes(1)))
    func backgroundExpiration() async {
        let now = issuedAt.addingTimeInterval(.days(16))
        let fixture = makeFixture(flagOn: true, token: token(issuedAt: issuedAt), now: now)
        fixture.provider.refreshedToken = token(issuedAt: now)
        let gate = Gate()
        fixture.provider.beforeForceRefresh = { await gate.wait() }
        let task = FakeBGTask(identifier: identifier)

        let work = fixture.refreshTask.handle(task)
        await fixture.provider.waitForForceRefresh()
        task.expirationHandler?()
        await gate.open()
        await work.value

        #expect(task.completions == [false])
        #expect(fixture.scheduler.events == [.submit(now.addingTimeInterval(.hours(6)))])
    }

    // MARK: - Session changes

    @available(iOS 16, macOS 13, *)
    @Test("Sign-out cancels the scheduled task, also while off", .timeLimit(.minutes(1)))
    func signOutCancels() async {
        let fixture = makeFixture(flagOn: true, token: token(issuedAt: issuedAt), now: issuedAt.addingTimeInterval(.days(1)))
        fixture.refreshTask.register()
        await fixture.refreshTask.refreshAndSchedule().value

        fixture.flag.isOn = false
        fixture.provider.token = nil
        fixture.notificationCenter.post(name: .accountDidSignOut, object: nil)

        #expect(fixture.scheduler.events == [.submit(issuedAt.addingTimeInterval(.days(15))), .cancel])

        fixture.flag.isOn = true
        await fixture.refreshTask.refreshAndSchedule().value
        #expect(fixture.scheduler.events.last == .cancel)
        #expect(!fixture.provider.requestedPolicies.contains(.localForceRefresh))
    }

    @available(iOS 16, macOS 13, *)
    @Test("No token schedules nothing; a sign-in afterwards schedules the task for the new session", .timeLimit(.minutes(1)))
    func signInSchedules() async throws {
        let now = issuedAt.addingTimeInterval(.hours(1))
        let fixture = makeFixture(flagOn: true, token: nil, now: now)
        fixture.refreshTask.register()

        await fixture.refreshTask.refreshAndSchedule().value
        #expect(fixture.scheduler.events == [.cancel])
        #expect(fixture.scheduler.submittedRequests.isEmpty)

        fixture.provider.token = token(issuedAt: issuedAt)
        fixture.notificationCenter.post(name: .accountDidSignIn, object: nil)

        try await waitUntil { fixture.scheduler.events == [.cancel, .submit(issuedAt.addingTimeInterval(.days(15)))] }
        #expect(fixture.debugSettings.lastRun?.trigger == .signIn)
        #expect(!fixture.provider.requestedPolicies.contains(.localForceRefresh))
    }

    // MARK: - Run record

    @available(iOS 16, macOS 13, *)
    @Test("Each run records its trigger, outcome and next check, and posts didRun", .timeLimit(.minutes(1)))
    func recordsRuns() async throws {
        let now = issuedAt.addingTimeInterval(.days(15))
        let fixture = makeFixture(flagOn: true, token: token(issuedAt: issuedAt), now: now)
        fixture.provider.refreshedToken = token(issuedAt: now)
        var didRunCount = 0
        let observer = fixture.notificationCenter.addObserver(forName: .subscriptionTokenRefreshDidRun, object: nil, queue: nil) { _ in
            didRunCount += 1
        }
        defer { fixture.notificationCenter.removeObserver(observer) }

        await fixture.refreshTask.refreshAndSchedule(trigger: .foreground).value
        #expect(fixture.debugSettings.lastRun == SubscriptionTokenRefreshRun(date: now, trigger: .foreground, outcome: "refreshed",
                                                                             nextCheck: now.addingTimeInterval(.days(15))))

        let task = FakeBGTask(identifier: identifier)
        await fixture.refreshTask.handle(task).value
        #expect(fixture.debugSettings.lastRun == SubscriptionTokenRefreshRun(date: now, trigger: .backgroundTask, outcome: "not due",
                                                                             nextCheck: now.addingTimeInterval(.days(15))))
        #expect(didRunCount == 2)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Sign-out records nothing: the next run after it records no token and a cancelled task", .timeLimit(.minutes(1)))
    func signOutThenRunRecordsNoToken() async {
        let fixture = makeFixture(flagOn: true, token: token(issuedAt: issuedAt), now: issuedAt.addingTimeInterval(.days(1)))
        fixture.refreshTask.register()
        await fixture.refreshTask.refreshAndSchedule().value

        fixture.provider.token = nil
        fixture.notificationCenter.post(name: .accountDidSignOut, object: nil)
        await fixture.refreshTask.refreshAndSchedule().value

        #expect(fixture.debugSettings.lastRun?.outcome == "no token")
        #expect(fixture.debugSettings.lastRun?.nextCheck == nil)
    }

    // MARK: - Debug menu

    @available(iOS 16, macOS 13, *)
    @Test("A debug run request runs the keep-alive and records the debug trigger", .timeLimit(.minutes(1)))
    func debugRunRequest() async throws {
        let fixture = makeFixture(flagOn: true, token: token(issuedAt: issuedAt), now: issuedAt.addingTimeInterval(.days(1)))
        fixture.refreshTask.register()

        fixture.notificationCenter.post(name: .subscriptionTokenRefreshDebugRunRequested, object: nil)

        try await waitUntil { fixture.debugSettings.lastRun?.trigger == .debugMenu }
        #expect(fixture.debugSettings.lastRun?.outcome == "not due")
        #expect(fixture.scheduler.events == [.submit(issuedAt.addingTimeInterval(.days(15)))])
    }

    @available(iOS 16, macOS 13, *)
    @Test("A debug run request while off records disabled and cancels the task", .timeLimit(.minutes(1)))
    func debugRunRequestWhileOff() async throws {
        let fixture = makeFixture(flagOn: false, token: token(issuedAt: issuedAt), now: issuedAt.addingTimeInterval(.days(20)))
        fixture.refreshTask.register()

        fixture.notificationCenter.post(name: .subscriptionTokenRefreshDebugRunRequested, object: nil)

        try await waitUntil { fixture.debugSettings.lastRun?.trigger == .debugMenu }
        #expect(fixture.debugSettings.lastRun?.outcome == "disabled")
        #expect(fixture.scheduler.events == [.cancel])
        #expect(fixture.provider.requestedPolicies.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A shorter refresh token age set in the debug menu refreshes and schedules with it from the next run", .timeLimit(.minutes(1)))
    func debugMaxAgeOverride() async {
        let now = issuedAt.addingTimeInterval(.minutes(3))
        let fixture = makeFixture(flagOn: true, token: token(issuedAt: issuedAt), now: now)
        fixture.provider.refreshedToken = token(issuedAt: now)

        await fixture.refreshTask.refreshAndSchedule().value
        #expect(fixture.scheduler.events == [.submit(issuedAt.addingTimeInterval(.days(15)))])

        fixture.debugSettings.maxRefreshTokenAgeOverride = .minutes(2)
        await fixture.refreshTask.refreshAndSchedule().value

        #expect(fixture.provider.requestedPolicies.contains(.localForceRefresh))
        #expect(fixture.scheduler.events.last == .submit(now.addingTimeInterval(.minutes(2))))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Debug overrides are ignored for a user who isn't internal, and apply again once they are", .timeLimit(.minutes(1)))
    func debugOverrideNotInternal() async {
        let now = issuedAt.addingTimeInterval(.minutes(3))
        let fixture = makeFixture(flagOn: true, token: token(issuedAt: issuedAt), now: now, internalUser: false)
        fixture.debugSettings.maxRefreshTokenAgeOverride = .minutes(2)
        fixture.provider.refreshedToken = token(issuedAt: now)

        await fixture.refreshTask.refreshAndSchedule().value
        #expect(!fixture.provider.requestedPolicies.contains(.localForceRefresh))
        #expect(fixture.scheduler.events == [.submit(issuedAt.addingTimeInterval(.days(15)))])

        fixture.internalUser.isOn = true
        await fixture.refreshTask.refreshAndSchedule().value
        #expect(fixture.provider.requestedPolicies.contains(.localForceRefresh))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Expiring during the refresh reschedules after the retry interval set in the debug menu", .timeLimit(.minutes(1)))
    func expirationUsesRetryOverride() async {
        let now = issuedAt.addingTimeInterval(.days(16))
        let fixture = makeFixture(flagOn: true, token: token(issuedAt: issuedAt), now: now)
        fixture.debugSettings.retryIntervalOverride = 30
        fixture.provider.refreshedToken = token(issuedAt: now)
        let gate = Gate()
        fixture.provider.beforeForceRefresh = { await gate.wait() }
        let task = FakeBGTask(identifier: identifier)

        let work = fixture.refreshTask.handle(task)
        await fixture.provider.waitForForceRefresh()
        task.expirationHandler?()
        await gate.open()
        await work.value

        #expect(fixture.scheduler.events == [.submit(now.addingTimeInterval(30))])
    }

    // MARK: - Pixel

    private func pixel(_ trigger: SubscriptionTokenRefreshRun.Trigger, _ result: SubscriptionTokenRefreshPixel.Result) -> ExpectedFireCall {
        ExpectedFireCall(pixel: SubscriptionTokenRefreshPixel.run(trigger: trigger, result: result), frequency: .standard)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A foreground refresh fires the pixel with its trigger and result", .timeLimit(.minutes(1)))
    func pixelForegroundRefresh() async {
        let now = issuedAt.addingTimeInterval(.days(15))
        let fixture = makeFixture(flagOn: true, token: token(issuedAt: issuedAt), now: now)
        fixture.provider.refreshedToken = token(issuedAt: now)

        await fixture.refreshTask.refreshAndSchedule(trigger: .foreground).value

        #expect(fixture.pixels.actualFireCalls == [pixel(.foreground, .refreshed)])
        let fired = fixture.pixels.actualFireCalls.first?.pixel
        #expect(fired?.name == "subscription_auth-background-refresh_run")
        #expect(fired?.parameters == ["trigger": "foreground", "result": "refreshed"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Foreground and sign-in runs with nothing to refresh fire nothing", .timeLimit(.minutes(1)))
    func pixelQuietForegroundRuns() async throws {
        let fixture = makeFixture(flagOn: true, token: token(issuedAt: issuedAt), now: issuedAt.addingTimeInterval(.days(1)))
        fixture.refreshTask.register()

        await fixture.refreshTask.refreshAndSchedule(trigger: .foreground).value
        fixture.notificationCenter.post(name: .accountDidSignIn, object: nil)
        try await waitUntil { fixture.debugSettings.lastRun?.trigger == .signIn }
        fixture.provider.token = nil
        await fixture.refreshTask.refreshAndSchedule(trigger: .foreground).value

        #expect(fixture.pixels.actualFireCalls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A failed foreground refresh fires the pixel", .timeLimit(.minutes(1)))
    func pixelForegroundFailure() async {
        let fixture = makeFixture(flagOn: true, token: token(issuedAt: issuedAt), now: issuedAt.addingTimeInterval(.days(16)))
        fixture.provider.refreshError = URLError(.notConnectedToInternet)

        await fixture.refreshTask.refreshAndSchedule(trigger: .foreground).value

        #expect(fixture.pixels.actualFireCalls == [pixel(.foreground, .failed)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Every background run fires the pixel, including the ones with nothing to refresh", .timeLimit(.minutes(1)))
    func pixelBackgroundRuns() async {
        let now = issuedAt.addingTimeInterval(.days(1))
        let fixture = makeFixture(flagOn: true, token: token(issuedAt: issuedAt), now: now)

        await fixture.refreshTask.handle(FakeBGTask(identifier: identifier)).value
        fixture.provider.stateOverride = .readError
        await fixture.refreshTask.handle(FakeBGTask(identifier: identifier)).value
        fixture.provider.stateOverride = nil
        fixture.provider.token = nil
        await fixture.refreshTask.handle(FakeBGTask(identifier: identifier)).value

        #expect(fixture.pixels.actualFireCalls == [pixel(.backgroundTask, .notDue),
                                                   pixel(.backgroundTask, .failed),
                                                   pixel(.backgroundTask, .noToken)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("A background task that expires mid-refresh fires expired once and nothing for the discarded run", .timeLimit(.minutes(1)))
    func pixelBackgroundExpiration() async {
        let now = issuedAt.addingTimeInterval(.days(16))
        let fixture = makeFixture(flagOn: true, token: token(issuedAt: issuedAt), now: now)
        fixture.provider.refreshedToken = token(issuedAt: now)
        let gate = Gate()
        fixture.provider.beforeForceRefresh = { await gate.wait() }
        let task = FakeBGTask(identifier: identifier)

        let work = fixture.refreshTask.handle(task)
        await fixture.provider.waitForForceRefresh()
        task.expirationHandler?()
        await gate.open()
        await work.value

        #expect(fixture.pixels.actualFireCalls == [pixel(.backgroundTask, .expired)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("on > off > on: no pixel while off, pixels again once back on", .timeLimit(.minutes(1)))
    func pixelFlagTransitions() async {
        let now = issuedAt.addingTimeInterval(.days(1))
        let fixture = makeFixture(flagOn: true, token: token(issuedAt: issuedAt), now: now)

        await fixture.refreshTask.handle(FakeBGTask(identifier: identifier)).value
        fixture.flag.isOn = false
        await fixture.refreshTask.handle(FakeBGTask(identifier: identifier)).value
        await fixture.refreshTask.refreshAndSchedule(trigger: .debugMenu).value
        fixture.flag.isOn = true
        await fixture.refreshTask.handle(FakeBGTask(identifier: identifier)).value

        #expect(fixture.pixels.actualFireCalls == [pixel(.backgroundTask, .notDue), pixel(.backgroundTask, .notDue)])
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async throws {
        for _ in 0..<1000 where !condition() {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(condition())
    }
}

// MARK: - Test doubles

private final class FlagState: @unchecked Sendable {
    var isOn: Bool
    init(isOn: Bool) { self.isOn = isOn }
}

/// A one-shot gate that suspends callers of `wait()` until `open()` is called.
private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

private final class FakeTokenProvider: SubscriptionTokenRefreshing, @unchecked Sendable {
    var token: TokenContainer?
    var refreshedToken: TokenContainer?
    var refreshError: Error?
    var beforeForceRefresh: (() async -> Void)?
    var stateOverride: LocalSubscriptionTokenState?
    private(set) var requestedPolicies: [AuthTokensCachePolicy] = []
    private var forceRefreshStarted = false

    init(token: TokenContainer?) {
        self.token = token
    }

    func localTokenState() -> LocalSubscriptionTokenState {
        if let stateOverride { return stateOverride }
        return token == nil ? .missing : .present
    }

    func getTokenContainer(policy: AuthTokensCachePolicy) async throws -> TokenContainer {
        requestedPolicies.append(policy)
        if policy == .localForceRefresh {
            forceRefreshStarted = true
            await beforeForceRefresh?()
            if let refreshError { throw refreshError }
            token = refreshedToken ?? token
        }
        guard let token else { throw SubscriptionManagerError.noTokenAvailable }
        return token
    }

    func waitForForceRefresh() async {
        while !forceRefreshStarted {
            await Task.yield()
        }
    }
}

private final class RecordingScheduler: BGTaskScheduling {
    enum Event: Equatable {
        case submit(Date?)
        case cancel
    }

    private(set) var registeredIdentifiers: [String] = []
    private(set) var events: [Event] = []
    private(set) var submittedRequests: [BGTaskRequest] = []
    private var launchHandlers: [String: (BGTaskInterface) -> Void] = [:]

    func register(forTaskWithIdentifier identifier: String, launchHandler: @escaping (BGTaskInterface) -> Void) -> Bool {
        registeredIdentifiers.append(identifier)
        launchHandlers[identifier] = launchHandler
        return true
    }

    func submit(_ taskRequest: BGTaskRequest) throws {
        submittedRequests.append(taskRequest)
        events.append(.submit(taskRequest.earliestBeginDate))
    }

    func cancel(taskRequestWithIdentifier identifier: String) {
        events.append(.cancel)
    }

    func getPendingTaskRequests(completionHandler: @escaping ([BGTaskRequest]) -> Void) {
        completionHandler(submittedRequests)
    }

    func pendingTaskRequests() async -> [BGTaskRequest] {
        submittedRequests
    }

    /// Calls the launch handler registered for `identifier`, as the system does when it launches the task.
    func launch(_ identifier: String, task: BGTaskInterface) {
        launchHandlers[identifier]?(task)
    }
}

private final class FakeBGTask: BGTaskInterface {
    let identifier: String
    var expirationHandler: (() -> Void)?
    private(set) var completions: [Bool] = []

    init(identifier: String) {
        self.identifier = identifier
    }

    func setTaskCompleted(success: Bool) {
        completions.append(success)
    }
}
