//
//  ChromeWebStoreUpdateCoordinatorTests.swift
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

import Foundation
import os
@_spi(Testing) import Persistence
import XCTest
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class ChromeWebStoreUpdateCoordinatorTests: XCTestCase {
    private func coordinator(interval: TimeInterval = ChromeWebStoreUpdateCoordinator.defaultCheckInterval,
                             scheduler: ChromeWebStorePeriodicSchedulerMock = ChromeWebStorePeriodicSchedulerMock(),
                             initialState: ChromeWebStoreUpdateState = .init(),
                             isEnabled: Bool = true,
                             now: @escaping @Sendable () -> Date = Date.init,
                             persistState: ChromeWebStoreUpdateCoordinator.PersistState? = nil,
                             resultHandler: ChromeWebStoreUpdateCoordinator.ResultHandler? = nil,
                             identifiers: @escaping ChromeWebStoreUpdateCoordinator.IdentifiersProvider = { ["extension"] },
                             version: @escaping ChromeWebStoreUpdateCoordinator.VersionProvider = { _ in
                                 .init(installedVersion: "2.0", reportedVersion: "1.0")
                             },
                             check: @escaping ChromeWebStoreUpdateCoordinator.Check) -> ChromeWebStoreUpdateCoordinator {
        ChromeWebStoreUpdateCoordinator(interval: interval, schedulerFactory: { _ in scheduler },
                                       initialState: initialState, isEnabled: isEnabled, now: now, persistState: persistState, resultHandler: resultHandler,
                                       installedIdentifiers: identifiers, version: version, check: check)
    }

    func testDisabledCoordinatorHasNoScheduledActivityOrChecksUntilEnabled() async {
        let checks = CheckRecorder()
        let scheduler = ChromeWebStorePeriodicSchedulerMock()
        let coordinator = coordinator(scheduler: scheduler, isEnabled: false) { _, _ in await checks.record() }
        await coordinator.start()
        await coordinator.checkForUpdatesNow()
        XCTAssertEqual(scheduler.scheduleCount, 0)
        let disabledCount = await checks.count
        XCTAssertEqual(disabledCount, 0)

        await coordinator.setEnabled(true, revision: 1)
        await coordinator.start()
        await coordinator.setEnabled(true, revision: 2)
        await coordinator.start()
        XCTAssertEqual(scheduler.scheduleCount, 1)
        let enabledCount = await checks.count
        XCTAssertEqual(enabledCount, 1)
        await coordinator.stop()
    }

    func testDisableInvalidatesActivityAndBlocksManualAndDeliveredPeriodicChecks() async {
        let now = Date(timeIntervalSince1970: 100000)
        let checks = CheckRecorder()
        let scheduler = ChromeWebStorePeriodicSchedulerMock()
        let coordinator = coordinator(scheduler: scheduler, initialState: .init(lastCompletedBatch: now, retryNotBefore: nil), now: { now }) { _, _ in
            await checks.record()
        }
        await coordinator.start()
        XCTAssertEqual(scheduler.scheduleCount, 1)
        await coordinator.setEnabled(false, revision: 1)
        XCTAssertEqual(scheduler.invalidationCount, 1)
        await coordinator.checkForUpdatesNow()
        await scheduler.fire()
        let count = await checks.count
        XCTAssertEqual(count, 0)
        await coordinator.stop()
        XCTAssertEqual(scheduler.invalidationCount, 1)
    }

    func testReenableRetainsRecentCompletionAndRegistersOnlyOneNewActivity() async {
        let now = Date(timeIntervalSince1970: 100000)
        let checks = CheckRecorder()
        let scheduler = ChromeWebStorePeriodicSchedulerMock()
        let coordinator = coordinator(scheduler: scheduler, now: { now }) { _, _ in await checks.record() }
        await coordinator.start()
        await coordinator.setEnabled(false, revision: 1)
        await coordinator.setEnabled(true, revision: 2)
        await coordinator.start()
        await coordinator.setEnabled(true, revision: 3)
        await coordinator.start()
        let count = await checks.count
        XCTAssertEqual(count, 1, "Re-enabling must honor the recent completed batch")
        XCTAssertEqual(scheduler.scheduleCount, 2)
        XCTAssertEqual(scheduler.invalidationCount, 1)
        await scheduler.fire()
        let periodicCount = await checks.count
        XCTAssertEqual(periodicCount, 2)
        await coordinator.stop()
    }

    func testDisableCancelsActiveCheckWithoutReportingLateOutcomesOrCheckingNextCandidate() async {
        let entered = expectation(description: "Check started")
        let cancelled = expectation(description: "Check cancelled")
        var outcomes = 0
        var savedStates: [ChromeWebStoreUpdateState] = []
        let coordinator = coordinator(persistState: { savedStates.append($0) }, resultHandler: { _, _ in outcomes += 1 },
                                      identifiers: { ["a", "b"] }) { identifier, _ in
            XCTAssertEqual(identifier, "a", "Disabling must prevent the next request")
            entered.fulfill()
            do { try await Task.sleep(for: .seconds(5)) } catch { cancelled.fulfill() }
            return .init(outcome: .failure(.networkFailure), retryNotBefore: nil)
        }
        let manual = Task { await coordinator.checkForUpdatesNow() }
        await fulfillment(of: [entered], timeout: 1)
        await coordinator.setEnabled(false, revision: 1)
        await manual.value
        await fulfillment(of: [cancelled], timeout: 1)
        XCTAssertEqual(outcomes, 0)
        XCTAssertTrue(savedStates.isEmpty)
        await coordinator.stop()
    }

    func testRapidReenableWaitsForCancelledStartupBeforeRegisteringActivity() async {
        let entered = expectation(description: "Startup provider suspended")
        var resume: CheckedContinuation<[String]?, Never>?
        var providerCalls = 0
        let checks = CheckRecorder()
        let scheduler = ChromeWebStorePeriodicSchedulerMock()
        let coordinator = coordinator(scheduler: scheduler, identifiers: {
            providerCalls += 1
            if providerCalls == 1 {
                return await withCheckedContinuation { continuation in
                    resume = continuation
                    entered.fulfill()
                }
            }
            return ["extension"]
        }) { _, _ in await checks.record() }
        let firstStart = Task { await coordinator.start() }
        await fulfillment(of: [entered], timeout: 1)
        await coordinator.setEnabled(false, revision: 1)
        await coordinator.setEnabled(true, revision: 2)
        let resumedStart = Task { await coordinator.start() }
        XCTAssertEqual(scheduler.scheduleCount, 0)
        resume?.resume(returning: ["extension"])
        await firstStart.value
        await resumedStart.value
        let count = await checks.count
        XCTAssertEqual(count, 1, "The cancelled startup must not check or overlap its replacement")
        XCTAssertEqual(providerCalls, 2)
        XCTAssertEqual(scheduler.scheduleCount, 1)
        await coordinator.stop()
    }

    func testImmediateManualCheckAfterReenableDrainsCancelledBatchDespiteRecentCompletion() async {
        let now = Date(timeIntervalSince1970: 100000)
        let entered = expectation(description: "Manual provider suspended")
        var resume: CheckedContinuation<[String]?, Never>?
        var providerCalls = 0
        let checks = CheckRecorder()
        let scheduler = ChromeWebStorePeriodicSchedulerMock()
        let coordinator = coordinator(scheduler: scheduler, initialState: .init(lastCompletedBatch: now, retryNotBefore: nil), now: { now }, identifiers: {
            providerCalls += 1
            if providerCalls == 1 {
                return await withCheckedContinuation { continuation in
                    resume = continuation
                    entered.fulfill()
                }
            }
            return ["extension"]
        }) { _, _ in await checks.record() }
        await coordinator.start()
        let oldManual = Task { await coordinator.checkForUpdatesNow() }
        await fulfillment(of: [entered], timeout: 1)
        await coordinator.setEnabled(false, revision: 1)
        await coordinator.setEnabled(true, revision: 2)
        let currentManual = Task { await coordinator.checkForUpdatesNow() }
        resume?.resume(returning: ["extension"])
        await oldManual.value
        await currentManual.value
        await coordinator.start()
        let count = await checks.count
        XCTAssertEqual(count, 1, "A new manual action must not only join the cancelled old batch")
        XCTAssertEqual(providerCalls, 2)
        XCTAssertEqual(scheduler.scheduleCount, 2)
        await coordinator.stop()
    }

    func testStaleFlagRevisionsCannotOverrideNewerState() async {
        let checks = CheckRecorder()
        let scheduler = ChromeWebStorePeriodicSchedulerMock()
        let coordinator = coordinator(scheduler: scheduler, isEnabled: false) { _, _ in await checks.record() }
        await coordinator.setEnabled(true, revision: 2)
        await coordinator.setEnabled(false, revision: 1)
        await coordinator.start()
        await coordinator.setEnabled(false, revision: 4)
        await coordinator.setEnabled(true, revision: 3)
        await coordinator.checkForUpdatesNow()
        let count = await checks.count
        XCTAssertEqual(count, 1)
        XCTAssertEqual(scheduler.scheduleCount, 1)
        XCTAssertEqual(scheduler.invalidationCount, 1)
        await coordinator.stop()
    }

    func testPauseRetainsServerBackoffAndStopCannotBeReenabled() async {
        let now = Date(timeIntervalSince1970: 100000)
        let checks = CheckRecorder()
        let scheduler = ChromeWebStorePeriodicSchedulerMock()
        let coordinator = coordinator(scheduler: scheduler, initialState: .init(lastCompletedBatch: nil, retryNotBefore: now.addingTimeInterval(60)), now: { now }) { _, _ in
            await checks.record()
        }
        await coordinator.start()
        await coordinator.setEnabled(false, revision: 1)
        await coordinator.setEnabled(true, revision: 2)
        await coordinator.start()
        await coordinator.checkForUpdatesNow()
        let count = await checks.count
        XCTAssertEqual(count, 0)
        XCTAssertEqual(scheduler.scheduleCount, 2)
        await coordinator.stop()
        await coordinator.setEnabled(true, revision: 3)
        await coordinator.start()
        await coordinator.checkForUpdatesNow()
        XCTAssertEqual(scheduler.scheduleCount, 2)
        let stoppedCount = await checks.count
        XCTAssertEqual(stoppedCount, 0)
    }

    func testChecksRunOffMainAndProvidersRunOnMainActor() async {
        let coordinator = coordinator(identifiers: {
            XCTAssertTrue(Thread.isMainThread)
            return ["extension"]
        }, version: { identifier in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(identifier, "extension")
            return .init(installedVersion: "2.0", reportedVersion: "1.0")
        }, check: { identifier, version in
            XCTAssertFalse(Thread.isMainThread)
            XCTAssertEqual(identifier, "extension")
            XCTAssertEqual(version, "1.0")
            return .init(outcome: .noUpdate, retryNotBefore: nil)
        })
        await coordinator.checkForUpdatesNow()
        await coordinator.stop()
    }

    func testConcurrentChecksJoinBatchWhileIdentifiersProviderIsSuspended() async throws {
        let entered = expectation(description: "Identifiers provider suspended")
        var resume: CheckedContinuation<[String]?, Never>?
        var providerCalls = 0
        let checks = CheckRecorder()
        let coordinator = coordinator(identifiers: {
            providerCalls += 1
            guard providerCalls == 1 else {
                XCTFail("Reentrant callers must join the registered batch")
                return ["extension"]
            }
            return await withCheckedContinuation { continuation in
                resume = continuation
                entered.fulfill()
            }
        }, check: { _, _ in await checks.record() })
        let callers = (0..<5).map { _ in Task { await coordinator.checkForUpdatesNow() } }
        await fulfillment(of: [entered], timeout: 1)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(providerCalls, 1)
        resume?.resume(returning: ["extension"])
        for caller in callers { await caller.value }
        let count = await checks.count
        XCTAssertEqual(count, 1)
        await coordinator.stop()
    }

    func testStoppingDuringIdentifiersProviderPreventsChecks() async {
        let entered = expectation(description: "Identifiers provider suspended")
        var resume: CheckedContinuation<[String]?, Never>?
        let coordinator = coordinator(identifiers: {
            await withCheckedContinuation { continuation in
                resume = continuation
                entered.fulfill()
            }
        }, check: { _, _ in
            XCTFail("A stopped coordinator must not query the server")
            return .init(outcome: .noUpdate, retryNotBefore: nil)
        })
        let caller = Task { await coordinator.checkForUpdatesNow() }
        await fulfillment(of: [entered], timeout: 1)
        await coordinator.stop()
        resume?.resume(returning: ["extension"])
        await caller.value
    }

    func testStoppingDuringVersionProviderPreventsChecks() async {
        let entered = expectation(description: "Version provider suspended")
        var resume: CheckedContinuation<ChromeWebStoreUpdateCoordinator.Version?, Never>?
        let coordinator = coordinator(version: { _ in
            await withCheckedContinuation { continuation in
                resume = continuation
                entered.fulfill()
            }
        }, check: { _, _ in
            XCTFail("A stopped coordinator must not query the server")
            return .init(outcome: .noUpdate, retryNotBefore: nil)
        })
        let caller = Task { await coordinator.checkForUpdatesNow() }
        await fulfillment(of: [entered], timeout: 1)
        await coordinator.stop()
        resume?.resume(returning: .init(installedVersion: "2.0", reportedVersion: "1.0"))
        await caller.value
    }

    func testStopPreventsDelayedStartupAndManualChecks() async {
        let coordinator = coordinator(identifiers: {
            XCTFail("Stopping before startup must prevent even installation reads")
            return ["extension"]
        }, check: { _, _ in
            XCTFail("A stopped coordinator must not query the server")
            return .init(outcome: .noUpdate, retryNotBefore: nil)
        })
        await coordinator.stop()
        await coordinator.start()
        await coordinator.checkForUpdatesNow()
        await coordinator.stop()
    }

    func testSchedulerStaysIdleUntilPeriodicActivityAndStartIsIdempotent() async {
        var providerCalls = 0
        let checks = CheckRecorder()
        let scheduler = ChromeWebStorePeriodicSchedulerMock()
        let coordinator = coordinator(scheduler: scheduler, identifiers: {
            providerCalls += 1
            return ["extension"]
        }, check: { _, _ in
            await checks.record()
        })
        await coordinator.start()
        await coordinator.start()
        XCTAssertEqual(scheduler.scheduleCount, 1)
        XCTAssertEqual(providerCalls, 1, "No installation polling between scheduled cycles")
        let count = await checks.count
        XCTAssertEqual(count, 1, "No network checks between scheduled cycles")
        await scheduler.fire()
        XCTAssertEqual(providerCalls, 2)
        let periodicCount = await checks.count
        XCTAssertEqual(periodicCount, 2)
        await coordinator.stop()
        XCTAssertEqual(scheduler.invalidationCount, 1)
        await scheduler.fire()
        XCTAssertEqual(providerCalls, 2, "An already-delivered callback must not read installations after stop")
        let stoppedCount = await checks.count
        XCTAssertEqual(stoppedCount, 2)
    }

    func testStopDuringInitialBatchPreventsPeriodicRegistration() async {
        let entered = expectation(description: "Initial provider suspended")
        var resume: CheckedContinuation<[String]?, Never>?
        let scheduler = ChromeWebStorePeriodicSchedulerMock()
        let coordinator = coordinator(scheduler: scheduler, identifiers: {
            await withCheckedContinuation { continuation in
                resume = continuation
                entered.fulfill()
            }
        }, check: { _, _ in
            XCTFail("Stopping the initial batch must prevent network checks")
            return .init(outcome: .noUpdate, retryNotBefore: nil)
        })
        let start = Task { await coordinator.start() }
        await fulfillment(of: [entered], timeout: 1)
        XCTAssertEqual(scheduler.scheduleCount, 0)
        await coordinator.stop()
        resume?.resume(returning: ["extension"])
        await start.value
        XCTAssertEqual(scheduler.scheduleCount, 0, "The stopped startup must not register periodic activity")
    }

    func testPeriodicCallbacksJoinManualBatch() async throws {
        let entered = expectation(description: "Manual batch suspended")
        let checks = CheckRecorder()
        var resume: CheckedContinuation<ChromeWebStoreUpdateCoordinator.Version?, Never>?
        var suspend = false
        var suspendedCalls = 0
        let scheduler = ChromeWebStorePeriodicSchedulerMock()
        let coordinator = coordinator(scheduler: scheduler, version: { _ in
            if suspend {
                suspendedCalls += 1
                guard suspendedCalls == 1 else {
                    XCTFail("Periodic callbacks must join the suspended manual batch")
                    return .init(installedVersion: "2.0", reportedVersion: "1.0")
                }
                return await withCheckedContinuation { continuation in
                    resume = continuation
                    entered.fulfill()
                }
            }
            return .init(installedVersion: "2.0", reportedVersion: "1.0")
        }, check: { _, _ in await checks.record() })
        await coordinator.start()
        suspend = true
        let manual = Task { await coordinator.checkForUpdatesNow() }
        await fulfillment(of: [entered], timeout: 1)
        let callbacks = (0..<3).map { _ in Task { await scheduler.fire() } }
        try await Task.sleep(for: .milliseconds(50))
        resume?.resume(returning: .init(installedVersion: "2.0", reportedVersion: "1.0"))
        await manual.value
        for callback in callbacks { await callback.value }
        let count = await checks.count
        XCTAssertEqual(count, 2, "Launch and the shared manual/periodic batch must be the only checks")
        await coordinator.stop()
    }

    func testStopCancelsActiveCheckAndReleasesCoordinator() async {
        let entered = expectation(description: "Check started")
        let cancelled = expectation(description: "Check cancelled")
        var coordinator: ChromeWebStoreUpdateCoordinator? = coordinator(check: { _, _ in
            entered.fulfill()
            do {
                try await Task.sleep(for: .seconds(5))
                XCTFail("Stopping must cancel an active check")
            } catch {
                cancelled.fulfill()
            }
            return .init(outcome: .failure(.cancelled), retryNotBefore: nil)
        })
        weak let weakCoordinator = coordinator
        let caller = Task { [weak coordinator] in await coordinator?.checkForUpdatesNow() }
        await fulfillment(of: [entered], timeout: 1)
        await coordinator?.stop()
        await caller.value
        await fulfillment(of: [cancelled], timeout: 1)
        coordinator = nil
        XCTAssertNil(weakCoordinator)
    }

    func testStopReleasesStoredProviderCaptures() async {
        var token: CallbackToken? = CallbackToken()
        weak let weakToken = token
        let coordinator = coordinator(identifiers: { [token] in
            _ = token
            return []
        }, check: { _, _ in .init(outcome: .noUpdate, retryNotBefore: nil) })
        token = nil
        XCTAssertNotNil(weakToken)
        await coordinator.stop()
        XCTAssertNil(weakToken)
    }

    func testEmptyInstallationSetDoesNotMakeRequests() async {
        let coordinator = coordinator(identifiers: { [] }, check: { _, _ in
            XCTFail("No installed extension means no network request")
            return .init(outcome: .noUpdate, retryNotBefore: nil)
        })
        await coordinator.checkForUpdatesNow()
        await coordinator.stop()
    }

    func testUnavailableInstallationSourceStopsDiscovery() async {
        var providerCalls = 0
        let coordinator = coordinator(identifiers: {
            providerCalls += 1
            return nil
        }, check: { _, _ in
            XCTFail("An unavailable installation source must stop discovery")
            return .init(outcome: .noUpdate, retryNotBefore: nil)
        })
        await coordinator.checkForUpdatesNow()
        await coordinator.start()
        await coordinator.checkForUpdatesNow()
        XCTAssertEqual(providerCalls, 1)
    }

    func testLaunchSuppressionExpiresAtExactlyFourHoursAndIgnoresFutureDates() async {
        let now = Date(timeIntervalSince1970: 100000)
        for (age, expectedChecks) in [(0.0, 0), (14399, 0), (14400, 1), (14401, 1), (-1, 1)] {
            let checks = CheckRecorder()
            let scheduler = ChromeWebStorePeriodicSchedulerMock()
            let state = ChromeWebStoreUpdateState(lastCompletedBatch: now.addingTimeInterval(-age), retryNotBefore: nil)
            let coordinator = coordinator(scheduler: scheduler, initialState: state, now: { now }) { _, _ in await checks.record() }
            await coordinator.start()
            let count = await checks.count
            XCTAssertEqual(count, expectedChecks, "Last completed batch age: \(age)")
            XCTAssertEqual(scheduler.scheduleCount, 1, "Skipping the launch check must still register periodic activity")
            await coordinator.stop()
        }
    }

    func testManualAndPeriodicChecksBypassRecentLaunchSuppression() async {
        let now = Date(timeIntervalSince1970: 100000)
        let checks = CheckRecorder()
        let scheduler = ChromeWebStorePeriodicSchedulerMock()
        let coordinator = coordinator(scheduler: scheduler,
                                      initialState: .init(lastCompletedBatch: now, retryNotBefore: nil), now: { now }) { _, _ in
            await checks.record()
        }
        await coordinator.start()
        await coordinator.checkForUpdatesNow()
        await scheduler.fire()
        let count = await checks.count
        XCTAssertEqual(count, 2)
        await coordinator.stop()
    }

    func testCompletedBatchSuppressesLaunchAfterCoordinatorAndStoreRecreation() async {
        let storage = InMemoryThrowingKeyValueStore()
        let store = ChromeWebStoreUpdateStateStore(keyValueStore: storage)
        let now = Date(timeIntervalSince1970: 100000)
        let checks = CheckRecorder()
        let first = coordinator(now: { now }, persistState: { store.save($0) }) { _, _ in await checks.record() }
        await first.start()
        await first.stop()
        let restored = ChromeWebStoreUpdateStateStore(keyValueStore: storage).load()
        XCTAssertEqual(restored.lastCompletedBatch, now)
        let second = coordinator(initialState: restored, now: { now.addingTimeInterval(3600) }) { _, _ in await checks.record() }
        await second.start()
        let count = await checks.count
        XCTAssertEqual(count, 1)
        await second.stop()
    }

    func testRestoredServerBackoffBlocksEveryTriggerUntilExactDeadline() async {
        let storage = InMemoryThrowingKeyValueStore()
        let store = ChromeWebStoreUpdateStateStore(keyValueStore: storage)
        let start = Date(timeIntervalSince1970: 100000)
        let deadline = start.addingTimeInterval(60)
        store.save(.init(lastCompletedBatch: nil, retryNotBefore: deadline))
        let clock = OSAllocatedUnfairLock(initialState: start)
        let checks = CheckRecorder()
        let scheduler = ChromeWebStorePeriodicSchedulerMock()
        let coordinator = coordinator(scheduler: scheduler, initialState: store.load(), now: { clock.withLock { $0 } },
                                      persistState: { store.save($0) }) { _, _ in await checks.record() }
        await coordinator.start()
        await coordinator.checkForUpdatesNow()
        await scheduler.fire()
        let blockedCount = await checks.count
        XCTAssertEqual(blockedCount, 0)
        clock.withLock { $0 = deadline }
        await coordinator.checkForUpdatesNow()
        let resumedCount = await checks.count
        XCTAssertEqual(resumedCount, 1)
        XCTAssertEqual(store.load().lastCompletedBatch, deadline)
        XCTAssertNil(store.load().retryNotBefore)
        await coordinator.stop()
    }

    func testBackoffOnOnlyOrFinalCandidateRecordsCompletionAndSuppressesRecentRelaunch() async throws {
        let identifier = ChromeWebStoreID.bitwarden.rawValue
        let update = ChromeWebStoreUpdateChecker.Update(extensionID: identifier, version: "3.0",
                                                        downloadURL: try XCTUnwrap(URL(string: "https://clients2.googleusercontent.com/extension.crx")),
                                                        size: 100, sha256: String(repeating: "a", count: 64))
        let now = Date(timeIntervalSince1970: 100000)
        let deadline = now.addingTimeInterval(30)
        for identifiers in [[identifier], [String(repeating: "a", count: 32), identifier]] {
            let storage = InMemoryThrowingKeyValueStore()
            let store = ChromeWebStoreUpdateStateStore(keyValueStore: storage)
            let checks = CheckRecorder()
            let first = coordinator(now: { now }, persistState: { store.save($0) }, identifiers: { identifiers }) { current, _ in
                _ = await checks.record()
                if current == identifier { return .init(outcome: .update(update), retryNotBefore: deadline) }
                return .init(outcome: .noUpdate, retryNotBefore: nil)
            }
            await first.start()
            await first.stop()
            let restored = ChromeWebStoreUpdateStateStore(keyValueStore: storage).load()
            XCTAssertEqual(restored.lastCompletedBatch, now, "Backoff on the final candidate still completes the batch")
            XCTAssertEqual(restored.retryNotBefore, deadline, "Completion must preserve the future server deadline")
            let second = coordinator(initialState: restored, now: { now.addingTimeInterval(60) }) { _, _ in
                XCTFail("An expired short backoff must not bypass suppression after a recent completed batch")
                return .init(outcome: .noUpdate, retryNotBefore: nil)
            }
            await second.start()
            let count = await checks.count
            XCTAssertEqual(count, identifiers.count)
            await second.stop()
        }
    }

    func testBackoffIsSavedBeforeTelemetryAndPartialBatchDoesNotRecordCompletion() async {
        let store = ChromeWebStoreUpdateStateStore(keyValueStore: InMemoryThrowingKeyValueStore())
        let now = Date(timeIntervalSince1970: 100000)
        let deadline = now.addingTimeInterval(60)
        let reported = expectation(description: "Outcome reported after persistence")
        let coordinator = coordinator(now: { now }, persistState: { store.save($0) }, resultHandler: { _, outcome in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(outcome, .failure(.httpStatus(503)))
            XCTAssertEqual(store.load().retryNotBefore, deadline)
            XCTAssertNil(store.load().lastCompletedBatch)
            reported.fulfill()
        }, identifiers: { ["a", "b"] }) { identifier, _ in
            XCTAssertEqual(identifier, "a", "Backoff must prevent the second request")
            return .init(outcome: .failure(.httpStatus(503)), retryNotBefore: deadline)
        }
        await coordinator.checkForUpdatesNow()
        await fulfillment(of: [reported], timeout: 1)
        XCTAssertNil(store.load().lastCompletedBatch)
        await coordinator.stop()
    }

    func testEmptyOrDisappearedCandidatesDoNotRecordCompletion() async {
        for identifiers in [[], ["extension"]] {
            var savedStates: [ChromeWebStoreUpdateState] = []
            let coordinator = coordinator(persistState: { savedStates.append($0) }, identifiers: { identifiers }, version: { _ in nil }) { _, _ in
                XCTFail("No current version means no network check")
                return .init(outcome: .noUpdate, retryNotBefore: nil)
            }
            await coordinator.checkForUpdatesNow()
            XCTAssertTrue(savedStates.isEmpty)
            await coordinator.stop()
        }
    }

    func testFailedRequestsRecordCompletionButCancelledChecksDoNot() async {
        let now = Date(timeIntervalSince1970: 100000)
        for failure in [ChromeWebStoreUpdateChecker.Failure.networkFailure, .cancelled] {
            var savedStates: [ChromeWebStoreUpdateState] = []
            let coordinator = coordinator(now: { now }, persistState: { savedStates.append($0) }) { _, _ in
                .init(outcome: .failure(failure), retryNotBefore: nil)
            }
            await coordinator.checkForUpdatesNow()
            XCTAssertEqual(savedStates.last?.lastCompletedBatch, failure == .cancelled ? nil : now)
            await coordinator.stop()
        }
    }

    private final class CallbackToken {}

    private actor CheckRecorder {
        private(set) var count = 0

        func record() -> ChromeWebStoreUpdateChecker.CheckResult {
            count += 1
            return .init(outcome: .noUpdate, retryNotBefore: nil)
        }
    }
}
