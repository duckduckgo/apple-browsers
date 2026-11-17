//
//  SyncAuditLogBackgroundTaskTests.swift
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
import FeatureFlags_iOS
import UIKit
import UserNotifications
@_spi(Testing) import Persistence
import XCTest
@testable import DDGSync
@testable import DuckDuckGo

@MainActor
final class SyncAuditLogBackgroundTaskTests: XCTestCase {
    private var sync: MockDDGSyncing!
    private var flags: MockFeatureFlagger!
    private var scheduler: AuditBackgroundScheduler!
    private var notifications: NotificationCenter!
    private var subject: SyncAuditLogBackgroundTask!
    private var notificationPermissions: MockUNUserNotificationCenter!
    private var settings: SyncNotificationSettings!
    private var application: MockBackgroundRefreshApplication!

    override func setUpWithError() throws {
        sync = MockDDGSyncing(authState: .initializing, isSyncInProgress: false)
        sync.account = SyncAccount(deviceId: "this", deviceName: "Phone", deviceType: "phone", userId: "account",
                                   primaryKey: Data(), secretKey: Data(), token: "token", state: .active)
        sync.isAuditLogPollingAvailableStub = true
        flags = MockFeatureFlagger(enabledFeatureFlags: [.syncLoginAuditLog, .syncLoginNotification, .syncAuditLogBackgroundPolling])
        scheduler = AuditBackgroundScheduler()
        notifications = NotificationCenter()
        notificationPermissions = MockUNUserNotificationCenter()
        settings = SyncNotificationSettings(storage: MockKeyValueStore().keyedStoring(), notificationCenter: notificationPermissions,
                                            changes: notifications)
        application = MockBackgroundRefreshApplication()
        subject = SyncAuditLogBackgroundTask(syncService: sync, featureFlagger: flags,
                                             scheduler: scheduler, notificationCenter: notifications,
                                             notificationSettings: settings, application: application)
    }

    private func waitForScheduling() async {
        let submitted = expectation(description: "Background refresh scheduled")
        scheduler.onSubmit = { submitted.fulfill() }
        subject.start()
        await fulfillment(of: [submitted], timeout: 1)
        scheduler.onSubmit = nil
    }

    func testRegistersOnceAndSchedulesRefreshThreeHoursLaterWithoutInitializingSync() async throws {
        let before = Date()
        await waitForScheduling()
        subject.start()
        XCTAssertEqual(scheduler.registrationCount, 1)
        let request = try XCTUnwrap(scheduler.submitted.first as? BGAppRefreshTaskRequest)
        XCTAssertEqual(request.identifier, SyncAuditLogBackgroundTask.identifier)
        let date = try XCTUnwrap(request.earliestBeginDate)
        XCTAssertGreaterThanOrEqual(date.timeIntervalSince(before), 3 * 60 * 60)
        XCTAssertLessThanOrEqual(date.timeIntervalSinceNow, 3 * 60 * 60)
        XCTAssertEqual(sync.initializeIfNeededCallCount, 0)
        XCTAssertEqual(sync.pollAuditLogCallCount, 0)
        XCTAssertEqual(sync.authState, .initializing)
    }

    func testAllThreeFlagsAreRequiredAndEnablingAtRuntimeSchedulesRefresh() async {
        for disabledFlag: FeatureFlag in [.syncLoginAuditLog, .syncLoginNotification, .syncAuditLogBackgroundPolling] {
            flags.enabledFeatureFlags.removeAll { $0 == disabledFlag }
        }
        subject.start()
        XCTAssertEqual(scheduler.registrationCount, 1)
        XCTAssertTrue(scheduler.submitted.isEmpty)

        let submitted = expectation(description: "Runtime enable schedules refresh")
        scheduler.onSubmit = { submitted.fulfill() }
        let unexpectedSubmit = expectation(description: "The background flag alone must not schedule")
        unexpectedSubmit.isInverted = true
        scheduler.onSubmit = { unexpectedSubmit.fulfill() }
        flags.enabledFeatureFlags = [.syncAuditLogBackgroundPolling]
        flags.triggerUpdate()
        await fulfillment(of: [unexpectedSubmit], timeout: 0.1)
        let missingNotificationFlag = expectation(description: "The notification flag is also required")
        missingNotificationFlag.isInverted = true
        scheduler.onSubmit = { missingNotificationFlag.fulfill() }
        flags.enabledFeatureFlags = [.syncLoginAuditLog, .syncAuditLogBackgroundPolling]
        flags.triggerUpdate()
        await fulfillment(of: [missingNotificationFlag], timeout: 0.1)
        scheduler.onSubmit = { submitted.fulfill() }
        flags.enabledFeatureFlags.append(.syncLoginNotification)
        flags.triggerUpdate()
        await fulfillment(of: [submitted], timeout: 1)
        XCTAssertEqual(scheduler.submitted.count, 1)
    }

    func testExistingRequestIsNotPostponedOnBackgroundEntry() async {
        let original = BGAppRefreshTaskRequest(identifier: SyncAuditLogBackgroundTask.identifier)
        original.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        scheduler.pending = [original]
        let unexpectedSubmit = expectation(description: "Do not replace the existing request")
        unexpectedSubmit.isInverted = true
        scheduler.onSubmit = { unexpectedSubmit.fulfill() }
        subject.start()
        notifications.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        await fulfillment(of: [unexpectedSubmit], timeout: 0.1)
        XCTAssertTrue(scheduler.pending.first === original)
    }

    func testSyncDisabledCancelsOnlyTheAuditRequestAndSchedulesAgainWhenEnabled() async {
        let unrelated = BGAppRefreshTaskRequest(identifier: "another-feature")
        scheduler.pending = [unrelated]
        await waitForScheduling()
        let cancelled = expectation(description: "Sync disabled cancels its request")
        scheduler.onCancel = { cancelled.fulfill() }
        sync.isAuditLogPollingAvailableStub = false
        sync.authState = .inactive
        await fulfillment(of: [cancelled], timeout: 1)
        scheduler.onCancel = nil
        XCTAssertEqual(scheduler.pending.map(\.identifier), ["another-feature"])

        let submitted = expectation(description: "Sync enabled schedules again")
        scheduler.onSubmit = { submitted.fulfill() }
        sync.isAuditLogPollingAvailableStub = true
        sync.authState = .active
        await fulfillment(of: [submitted], timeout: 1)
        XCTAssertEqual(sync.initializeIfNeededCallCount, 0)
    }

    func testLockedStorageKeepsAnotherRefreshOpportunity() async {
        sync.isAuditLogPollingAvailableError = SyncError.failedToReadSecureStore(status: -25308)
        await waitForScheduling()
        XCTAssertEqual(scheduler.pending.count, 1)
        XCTAssertNotNil(sync.account)
        XCTAssertFalse(sync.disconnectCalled)
        XCTAssertEqual(sync.initializeIfNeededCallCount, 0)
    }

    func testStorageBecomingUnavailableStopsCurrentWorkAndKeepsTheNextRefresh() async {
        await waitForScheduling()
        let started = expectation(description: "Poll started")
        let rescheduled = expectation(description: "Next refresh queued")
        let completed = expectation(description: "Storage failure completes the system task")
        let unwound = expectation(description: "Cancelled request unwound")
        var response: CheckedContinuation<Void, Never>?
        sync.pollAuditLogHandler = {
            await withCheckedContinuation { response = $0; started.fulfill() }
            defer { unwound.fulfill() }
            try Task.checkCancellation()
            return true
        }
        scheduler.onSubmit = { rescheduled.fulfill() }
        let task = AuditBackgroundTask()
        task.onCompletion = { completed.fulfill() }
        scheduler.launch(task)
        await fulfillment(of: [started, rescheduled], timeout: 1)
        scheduler.onSubmit = nil

        sync.isAuditLogPollingAvailableError = SyncError.failedToReadSecureStore(status: -25308)
        flags.triggerUpdate()
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(task.results, [false])
        XCTAssertEqual(scheduler.pending.map(\.identifier), [SyncAuditLogBackgroundTask.identifier])
        XCTAssertNotNil(sync.account)
        XCTAssertFalse(sync.disconnectCalled)
        response?.resume()
        await fulfillment(of: [unwound], timeout: 1)
    }

    func testSuccessfulPollReschedulesAndCompletesWithoutInitializingSync() async {
        await waitForScheduling()
        let completed = expectation(description: "Background poll completed")
        let rescheduled = expectation(description: "Next refresh scheduled")
        scheduler.onSubmit = { rescheduled.fulfill() }
        sync.pollAuditLogHandler = { true }
        let task = AuditBackgroundTask()
        task.onCompletion = { completed.fulfill() }
        scheduler.launch(task)
        await fulfillment(of: [completed, rescheduled], timeout: 1)
        XCTAssertEqual(task.results, [true])
        XCTAssertEqual(sync.pollAuditLogCallCount, 1)
        XCTAssertEqual(sync.initializeIfNeededCallCount, 0)
        XCTAssertEqual(sync.authState, .initializing)
    }

    func testStorageAndUnauthorizedErrorsCompleteUnsuccessfullyWithoutLoggingOut() async {
        await waitForScheduling()
        for error in [SyncError.failedToReadSecureStore(status: -25308), .unexpectedStatusCode(401)] {
            let completed = expectation(description: "Failed attempt completes")
            let rescheduled = expectation(description: "Failed attempt keeps a later refresh")
            scheduler.onSubmit = { rescheduled.fulfill() }
            sync.pollAuditLogHandler = { throw error }
            let task = AuditBackgroundTask()
            task.onCompletion = { completed.fulfill() }
            scheduler.launch(task)
            await fulfillment(of: [completed, rescheduled], timeout: 1)
            scheduler.onSubmit = nil
            XCTAssertEqual(task.results, [false])
            XCTAssertNotNil(sync.account)
            XCTAssertFalse(sync.disconnectCalled)
        }
        let recovered = expectation(description: "A later poll succeeds")
        sync.pollAuditLogHandler = { true }
        let retry = AuditBackgroundTask()
        retry.onCompletion = { recovered.fulfill() }
        scheduler.launch(retry)
        await fulfillment(of: [recovered], timeout: 1)
        XCTAssertEqual(retry.results, [true])
        XCTAssertEqual(sync.initializeIfNeededCallCount, 0)
    }

    func testExpirationCompletesImmediatelyAndLateResponseCannotCompleteAgain() async throws {
        await waitForScheduling()
        let started = expectation(description: "Poll waiting on an uncooperative request")
        let unwound = expectation(description: "Cancelled request eventually unwinds")
        var response: CheckedContinuation<Void, Never>?
        sync.pollAuditLogHandler = {
            await withCheckedContinuation {
                response = $0
                started.fulfill()
            }
            defer { unwound.fulfill() }
            try Task.checkCancellation()
            return true
        }
        let completed = expectation(description: "Expiration completes before the response")
        let task = AuditBackgroundTask()
        task.onCompletion = { completed.fulfill() }
        scheduler.launch(task)
        await fulfillment(of: [started], timeout: 1)
        let expire = try XCTUnwrap(task.expirationHandler)
        DispatchQueue.global().async { expire() }
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(task.results, [false])
        response?.resume()
        await fulfillment(of: [unwound], timeout: 1)
        XCTAssertEqual(task.results, [false])
    }

    func testExpirationBeforeMainActorStartsPreventsPollingButKeepsTheNextRefresh() async throws {
        await waitForScheduling()
        let rescheduled = expectation(description: "Expired launch retains a future refresh")
        scheduler.onSubmit = { rescheduled.fulfill() }
        let task = AuditBackgroundTask()
        scheduler.launch(task)
        try XCTUnwrap(task.expirationHandler)()
        let unexpectedPoll = expectation(description: "Expired task must not poll")
        unexpectedPoll.isInverted = true
        sync.pollAuditLogHandler = { unexpectedPoll.fulfill(); return true }
        await fulfillment(of: [rescheduled], timeout: 1)
        await fulfillment(of: [unexpectedPoll], timeout: 0.1)
        XCTAssertEqual(task.results, [false])
    }

    func testTurningBackgroundFlagOffCancelsPendingAndRunningWork() async {
        await assertDisablingRunningFlag(.syncAuditLogBackgroundPolling)
    }

    func testTurningNotificationFlagOffCancelsPendingAndRunningWork() async {
        await assertDisablingRunningFlag(.syncLoginNotification)
    }

    func testTurningAuditFlagOffCancelsPendingAndRunningWork() async {
        await assertDisablingRunningFlag(.syncLoginAuditLog)
    }

    private func assertDisablingRunningFlag(_ flag: FeatureFlag) async {
        await waitForScheduling()
        let started = expectation(description: "Poll started")
        let completed = expectation(description: "Flag disable completes system task")
        let unwound = expectation(description: "Poll unwinds after cancellation")
        var response: CheckedContinuation<Void, Never>?
        sync.pollAuditLogHandler = {
            await withCheckedContinuation { response = $0; started.fulfill() }
            defer { unwound.fulfill() }
            try Task.checkCancellation()
            return true
        }
        let task = AuditBackgroundTask()
        task.onCompletion = { completed.fulfill() }
        scheduler.launch(task)
        await fulfillment(of: [started], timeout: 1)
        flags.enabledFeatureFlags.removeAll { $0 == flag }
        flags.triggerUpdate()
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(task.results, [false])
        XCTAssertFalse(scheduler.pending.contains { $0.identifier == SyncAuditLogBackgroundTask.identifier })
        response?.resume()
        await fulfillment(of: [unwound], timeout: 1)
        XCTAssertEqual(task.results, [false])

        let disabledTask = AuditBackgroundTask()
        let disabledComplete = expectation(description: "Disabled feature skips a queued launch")
        disabledTask.onCompletion = { disabledComplete.fulfill() }
        scheduler.launch(disabledTask)
        await fulfillment(of: [disabledComplete], timeout: 1)
        XCTAssertEqual(disabledTask.results, [true])
        XCTAssertEqual(sync.pollAuditLogCallCount, 1)
    }

    func testProvisionalAndAuthorizedPermissionsAllowSchedulingWithoutPrompting() async {
        for status: UNAuthorizationStatus in [.provisional, .authorized] {
            notificationPermissions.authorizationStatus = status
            scheduler.pending = []
            let scheduled = expectation(description: "Allowed notifications schedule a refresh")
            scheduler.onSubmit = { scheduled.fulfill() }
            subject.start()
            notifications.post(name: UIApplication.didBecomeActiveNotification, object: nil)
            await fulfillment(of: [scheduled], timeout: 1)
            scheduler.onSubmit = nil
            XCTAssertFalse(notificationPermissions.didRequestAuthorization)
        }
    }

    func testDeniedNotificationsPreventSchedulingAndPolling() async {
        notificationPermissions.authorizationStatus = .denied
        let cancelled = expectation(description: "Denied notifications cancel refresh")
        scheduler.onCancel = { cancelled.fulfill() }
        subject.start()
        await fulfillment(of: [cancelled], timeout: 1)
        scheduler.onCancel = nil
        XCTAssertTrue(scheduler.submitted.isEmpty)
        let task = AuditBackgroundTask()
        let completed = expectation(description: "Stale launch completes")
        task.onCompletion = { completed.fulfill() }
        scheduler.launch(task)
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(sync.pollAuditLogCallCount, 0)
        XCTAssertFalse(notificationPermissions.didRequestAuthorization)
    }

    func testOptOutCancelsRunningPollAndReenablingSchedulesAgain() async {
        await assertPolicyChangeStopsRunningPoll { settings.isEnabled = false }
        let scheduled = expectation(description: "Opt in schedules refresh")
        scheduler.onSubmit = { scheduled.fulfill() }
        settings.isEnabled = true
        await fulfillment(of: [scheduled], timeout: 1)
    }

    func testPermissionDenialOnReturningToAppCancelsRunningPoll() async {
        await assertPolicyChangeStopsRunningPoll {
            notificationPermissions.authorizationStatus = .denied
            notifications.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        }
    }

    func testBackgroundRefreshBecomingUnavailableCancelsRunningPoll() async {
        await assertPolicyChangeStopsRunningPoll {
            application.backgroundRefreshStatus = .denied
            notifications.post(name: UIApplication.backgroundRefreshStatusDidChangeNotification, object: nil)
        }
    }

    private func assertPolicyChangeStopsRunningPoll(change: () -> Void) async {
        await waitForScheduling()
        let started = expectation(description: "Poll started")
        let completed = expectation(description: "Ineligible poll completes immediately")
        let unwound = expectation(description: "Cancelled poll unwinds")
        var response: CheckedContinuation<Void, Never>?
        sync.pollAuditLogHandler = {
            await withCheckedContinuation { response = $0; started.fulfill() }
            defer { unwound.fulfill() }
            try Task.checkCancellation()
            return true
        }
        let task = AuditBackgroundTask()
        task.onCompletion = { completed.fulfill() }
        scheduler.launch(task)
        await fulfillment(of: [started], timeout: 1)
        change()
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(task.results, [false])
        XCTAssertTrue(scheduler.pending.isEmpty)
        response?.resume()
        await fulfillment(of: [unwound], timeout: 1)
        XCTAssertEqual(task.results, [false])
    }

    func testDisabledAndRestrictedBackgroundRefreshDoNotSubmitOrPoll() async {
        subject.start()
        for status: UIBackgroundRefreshStatus in [.denied, .restricted] {
            application.backgroundRefreshStatus = status
            let cancelled = expectation(description: "Unavailable background refresh cancels request")
            scheduler.onCancel = { cancelled.fulfill() }
            notifications.post(name: UIApplication.backgroundRefreshStatusDidChangeNotification, object: nil)
            await fulfillment(of: [cancelled], timeout: 1)
            scheduler.onCancel = nil
            XCTAssertTrue(scheduler.pending.isEmpty)
            let task = AuditBackgroundTask()
            let completed = expectation(description: "Stale launch does no work")
            task.onCompletion = { completed.fulfill() }
            scheduler.launch(task)
            await fulfillment(of: [completed], timeout: 1)
        }
        XCTAssertTrue(scheduler.submitted.isEmpty)
        XCTAssertEqual(sync.pollAuditLogCallCount, 0)
        application.backgroundRefreshStatus = .available
        let scheduled = expectation(description: "Refresh available again")
        scheduler.onSubmit = { scheduled.fulfill() }
        notifications.post(name: UIApplication.backgroundRefreshStatusDidChangeNotification, object: nil)
        await fulfillment(of: [scheduled], timeout: 1)
    }

    func testExternallyScheduledShortRequestSurvivesBackgroundEntry() async throws {
        await waitForScheduling()
        let unrelated = BGAppRefreshTaskRequest(identifier: "another-feature")
        scheduler.pending.append(unrelated)
        let before = Date()
        let request = BGAppRefreshTaskRequest(identifier: SyncAuditLogBackgroundTask.identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30)
        try scheduler.submit(request)
        let earliest = try XCTUnwrap(request.earliestBeginDate)
        XCTAssertGreaterThanOrEqual(earliest.timeIntervalSince(before), 30)
        XCTAssertLessThanOrEqual(earliest.timeIntervalSinceNow, 30)
        XCTAssertEqual(scheduler.pending.count, 2)
        XCTAssertTrue(scheduler.pending.contains { $0 === unrelated })
        let noReplacement = expectation(description: "Background entry preserves debug delay")
        noReplacement.isInverted = true
        scheduler.onSubmit = { noReplacement.fulfill() }
        notifications.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        await fulfillment(of: [noReplacement], timeout: 0.1)
        XCTAssertTrue(scheduler.pending.contains { $0 === request })
    }

    func testDisablingDuringPendingRequestLookupCannotSubmitLateRequest() async {
        let lookup = expectation(description: "Pending request lookup started")
        var response: CheckedContinuation<[BGTaskRequest], Never>?
        scheduler.pendingHandler = {
            await withCheckedContinuation { response = $0; lookup.fulfill() }
        }
        subject.start()
        await fulfillment(of: [lookup], timeout: 1)
        let cancelled = expectation(description: "Feature disabled")
        scheduler.onCancel = { cancelled.fulfill() }
        flags.enabledFeatureFlags = [.syncAuditLogBackgroundPolling]
        flags.triggerUpdate()
        await fulfillment(of: [cancelled], timeout: 1)
        let noLateSubmit = expectation(description: "Cancelled lookup must not submit")
        noLateSubmit.isInverted = true
        scheduler.onSubmit = { noLateSubmit.fulfill() }
        response?.resume(returning: [])
        await fulfillment(of: [noLateSubmit], timeout: 0.1)
    }
}

private final class AuditBackgroundScheduler: BGTaskScheduling {
    var pending: [BGTaskRequest] = []
    var submitted: [BGTaskRequest] = []
    var registrationCount = 0
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?
    var pendingHandler: (() async -> [BGTaskRequest])?
    private var launchHandler: ((BGTaskInterface) -> Void)?

    func register(forTaskWithIdentifier identifier: String, launchHandler: @escaping (BGTaskInterface) -> Void) -> Bool {
        registrationCount += 1
        self.launchHandler = launchHandler
        return true
    }

    func submit(_ taskRequest: BGTaskRequest) throws {
        submitted.append(taskRequest)
        pending.removeAll { $0.identifier == taskRequest.identifier }
        pending.append(taskRequest)
        onSubmit?()
    }

    func cancel(taskRequestWithIdentifier identifier: String) {
        pending.removeAll { $0.identifier == identifier }
        onCancel?()
    }

    func getPendingTaskRequests(completionHandler: @escaping ([BGTaskRequest]) -> Void) {
        completionHandler(pending)
    }

    func pendingTaskRequests() async -> [BGTaskRequest] {
        await pendingHandler?() ?? pending
    }

    func launch(_ task: AuditBackgroundTask) {
        pending.removeAll { $0.identifier == SyncAuditLogBackgroundTask.identifier }
        launchHandler?(task)
    }
}

private final class AuditBackgroundTask: BGTaskInterface {
    let identifier = SyncAuditLogBackgroundTask.identifier
    var expirationHandler: (() -> Void)?
    var onCompletion: (() -> Void)?
    private let lock = NSLock()
    private var completions: [Bool] = []

    var results: [Bool] { lock.withLock { completions } }

    func setTaskCompleted(success: Bool) {
        lock.withLock { completions.append(success) }
        onCompletion?()
    }
}
