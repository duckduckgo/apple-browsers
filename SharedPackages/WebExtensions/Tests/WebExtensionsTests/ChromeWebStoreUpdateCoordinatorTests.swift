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
import XCTest
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class ChromeWebStoreUpdateCoordinatorTests: XCTestCase {
    private func coordinator(interval: TimeInterval = ChromeWebStoreUpdateCoordinator.defaultCheckInterval,
                             identifiers: @escaping ChromeWebStoreUpdateCoordinator.IdentifiersProvider = { ["extension"] },
                             version: @escaping ChromeWebStoreUpdateCoordinator.VersionProvider = { _ in
                                 .init(installedVersion: "2.0", reportedVersion: "1.0")
                             },
                             check: @escaping ChromeWebStoreUpdateCoordinator.Check) -> ChromeWebStoreUpdateCoordinator {
        ChromeWebStoreUpdateCoordinator(interval: interval, installedIdentifiers: identifiers, version: version, check: check)
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

    func testSchedulerStaysIdleBetweenChecksAndStartIsIdempotent() async throws {
        let firstCheck = expectation(description: "Launch check")
        var providerCalls = 0
        let checks = CheckRecorder()
        let coordinator = coordinator(identifiers: {
            providerCalls += 1
            return ["extension"]
        }, check: { _, _ in
            let result = await checks.record()
            firstCheck.fulfill()
            return result
        })
        await coordinator.start()
        await coordinator.start()
        await fulfillment(of: [firstCheck], timeout: 1)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(providerCalls, 1, "No installation polling between scheduled cycles")
        let count = await checks.count
        XCTAssertEqual(count, 1, "No network checks between scheduled cycles")
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
        weak var weakCoordinator = coordinator
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
        weak var weakToken = token
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

    private final class CallbackToken {}

    private actor CheckRecorder {
        private(set) var count = 0

        func record() -> ChromeWebStoreUpdateChecker.CheckResult {
            count += 1
            return .init(outcome: .noUpdate, retryNotBefore: nil)
        }
    }
}
