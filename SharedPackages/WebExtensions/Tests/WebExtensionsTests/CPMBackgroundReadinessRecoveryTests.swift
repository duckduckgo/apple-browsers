//
//  CPMBackgroundReadinessRecoveryTests.swift
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

import XCTest
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMBackgroundReadinessRecoveryTests: XCTestCase {
    private let url = URL(string: "https://example.com/page?q=one")!
    private var enabled = true
    private var backgrounded = false
    private var date = Date()
    private var reloads = 0
    private var outcomes: [CPMRecoveryOutcome] = []

    private func makeRecovery() -> CPMBackgroundReadinessRecovery {
        CPMBackgroundReadinessRecovery(isEnabled: { [unowned self] in enabled },
                                       isApplicationInBackground: { [unowned self] in backgrounded },
                                       instrumentation: Instrumentation { [unowned self] in outcomes.append($0) },
                                       now: { [unowned self] in date })
    }

    private func pendingDocument(_ recovery: CPMBackgroundReadinessRecovery) -> UUID {
        let id = UUID()
        recovery.backgroundStarted(id)
        recovery.navigationStarted(in: "tab")
        recovery.navigationCommitted(in: "tab", url: url)
        recovery.registerDocument(in: "tab") { [unowned self] in reloads += 1; return true }
        return id
    }

    private func drain() async { for _ in 0..<10 { await Task.yield() } }

    func testRequiresFailureAndSuccessfulBackgroundThenReloadsOnlyOnce() async {
        let recovery = makeRecovery()
        let id = pendingDocument(recovery)
        recovery.initializationFailed(in: "tab")
        await drain()
        XCTAssertEqual(reloads, 0)
        recovery.backgroundCompleted(id, succeeded: true)
        await drain()
        recovery.initializationFailed(in: "tab")
        recovery.backgroundCompleted(id, succeeded: true)
        await drain()
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(outcomes, [.reloadStarted])
        recovery.navigationStarted(in: "tab")
        recovery.navigationCommitted(in: "tab", url: url)
        recovery.responseReceived(in: "tab")
        recovery.responseReceived(in: "tab")
        XCTAssertEqual(outcomes, [.reloadStarted, .responseReceived])
    }

    func testHealthyLateResponseAvoidsReload() async {
        let recovery = makeRecovery()
        let id = pendingDocument(recovery)
        recovery.responseReceived(in: "tab")
        recovery.initializationFailed(in: "tab")
        recovery.backgroundCompleted(id, succeeded: true)
        await drain()
        XCTAssertEqual(reloads, 0)
        XCTAssertTrue(outcomes.isEmpty)
    }

    func testChangedClosedFailedAndReplacedDocumentsAreNotReloaded() async {
        for cancellation in 0..<4 {
            let recovery = makeRecovery()
            let id = pendingDocument(recovery)
            recovery.initializationFailed(in: "tab")
            switch cancellation {
            case 0: recovery.navigationStarted(in: "tab")
            case 1: recovery.navigationCancelled(in: "tab")
            case 2: recovery.invalidate()
            default: recovery.backgroundCompleted(id, succeeded: false)
            }
            recovery.backgroundCompleted(id, succeeded: true)
            await drain()
        }
        XCTAssertEqual(reloads, 0)
    }

    func testKillSwitchAndBackgroundStateAreRecheckedAtExecution() async {
        for suspendApplication in [false, true] {
            enabled = true
            backgrounded = false
            let recovery = makeRecovery()
            let id = pendingDocument(recovery)
            recovery.initializationFailed(in: "tab")
            recovery.backgroundCompleted(id, succeeded: true)
            if suspendApplication { backgrounded = true } else { enabled = false }
            await drain()
            XCTAssertEqual(reloads, 0)
        }
    }

    func testDisabledFlagDoesNotArmDocumentAndCanBeEnabledAtRuntime() async {
        let recovery = makeRecovery()
        enabled = false
        let id = pendingDocument(recovery)
        enabled = true
        recovery.initializationFailed(in: "tab")
        recovery.backgroundCompleted(id, succeeded: true)
        await drain()
        XCTAssertEqual(reloads, 0)
        let next = pendingDocument(recovery)
        recovery.initializationFailed(in: "tab")
        recovery.backgroundCompleted(next, succeeded: true)
        await drain()
        XCTAssertEqual(reloads, 1)
    }

    func testExpiredStartupAndUnsafeDocumentDoNotReloadOrClaimSuccess() async {
        let recovery = makeRecovery()
        let expired = pendingDocument(recovery)
        date.addTimeInterval(31)
        recovery.initializationFailed(in: "tab")
        recovery.backgroundCompleted(expired, succeeded: true)
        await drain()
        let unsafe = pendingDocument(recovery)
        recovery.registerDocument(in: "tab") { false }
        recovery.initializationFailed(in: "tab")
        recovery.backgroundCompleted(unsafe, succeeded: true)
        await drain()
        recovery.responseReceived(in: "tab")
        XCTAssertEqual(reloads, 0)
        XCTAssertTrue(outcomes.isEmpty)
    }

    func testOriginalResponseDuringReloadSafetyCheckCannotClaimRecovery() async {
        let recovery = makeRecovery()
        let id = pendingDocument(recovery)
        recovery.registerDocument(in: "tab") {
            recovery.responseReceived(in: "tab")
            return false
        }
        recovery.initializationFailed(in: "tab")
        recovery.backgroundCompleted(id, succeeded: true)
        await drain()
        XCTAssertTrue(outcomes.isEmpty)
    }

    func testReplacementNavigationCannotClaimReloadResponse() async {
        let recovery = makeRecovery()
        let id = pendingDocument(recovery)
        recovery.initializationFailed(in: "tab")
        recovery.backgroundCompleted(id, succeeded: true)
        await drain()
        recovery.navigationStarted(in: "tab")
        recovery.navigationCommitted(in: "tab", url: URL(string: "https://example.com/other")!)
        recovery.responseReceived(in: "tab")
        XCTAssertEqual(outcomes, [.reloadStarted])
    }

    func testEveryFixHasSeparatePIIFreeMetadata() {
        for fix in CPMRecoveryFix.allCases {
            let outcome: CPMRecoveryOutcome = fix == .lateDocumentReload ? .reloadStarted : .backgroundReady
            let metadata = CPMWebExtensionPixelMetadata(event: .cpmRecovery(fix, outcome: outcome))
            XCTAssertEqual(metadata?.name, "web_extension_cpm_\(fix.rawValue)")
            XCTAssertEqual(metadata?.frequency, .dailyAndCount)
            XCTAssertEqual(metadata?.parameters, ["outcome": outcome.rawValue])
        }
    }
}

@available(macOS 15.4, iOS 18.4, *)
private struct Instrumentation: CPMRecoveryInstrumentation {
    let callback: (CPMRecoveryOutcome) -> Void
    func record(_ fix: CPMRecoveryFix, outcome: CPMRecoveryOutcome) {
        XCTAssertEqual(fix, .lateDocumentReload)
        callback(outcome)
    }
}
