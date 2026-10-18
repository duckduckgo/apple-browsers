//
//  CPMNetworkProcessRecoveryTests.swift
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

import WebKit
import XCTest
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMNetworkProcessRecoveryTests: XCTestCase {
    private var process: Int32? = 100
    private var enabled = true
    private var current = true
    private var canRestart = true
    private var restarted: [WKWebView] = []

    private func makeRecovery(interval: TimeInterval = 60) -> CPMNetworkProcessRecovery {
        CPMNetworkProcessRecovery(isEnabled: { [unowned self] in self.enabled }, checkInterval: interval,
                                  processIdentifier: { [unowned self] _ in self.process },
                                  restart: { [unowned self] webView in
            guard self.canRestart else { return false }
            self.restarted.append(webView)
            return true
        })
    }

    private func watch(_ view: WKWebView, in recovery: CPMNetworkProcessRecovery, identifier: String = "embedded") {
        recovery.watch(view, identifier: identifier, isCurrent: { [unowned self] in self.current })
    }

    func testUnchangedNetworkProcessDoesNotRestartHealthyBackground() {
        let recovery = makeRecovery()
        let view = WKWebView()
        watch(view, in: recovery)
        XCTAssertFalse(recovery.recoverIfNeeded())
        XCTAssertTrue(restarted.isEmpty)
    }

    func testReplacedNetworkProcessRestartsOnlyOnce() {
        let recovery = makeRecovery()
        let view = WKWebView()
        watch(view, in: recovery)
        process = 200
        XCTAssertTrue(recovery.recoverIfNeeded())
        XCTAssertFalse(recovery.recoverIfNeeded())
        XCTAssertEqual(restarted, [view])
    }

    func testUnknownOriginalProcessIsRecordedBeforeDetectingReplacement() {
        process = nil
        let recovery = makeRecovery()
        let view = WKWebView()
        watch(view, in: recovery)
        process = 100
        XCTAssertFalse(recovery.recoverIfNeeded())
        process = 200
        XCTAssertTrue(recovery.recoverIfNeeded())
        XCTAssertEqual(restarted, [view])
    }

    func testUnavailableCurrentProcessDoesNotTriggerSpeculativeRestart() {
        let recovery = makeRecovery()
        let view = WKWebView()
        watch(view, in: recovery)
        for value: Int32? in [nil, 0, -1] {
            process = value
            XCTAssertFalse(recovery.recoverIfNeeded())
        }
        process = 200
        XCTAssertTrue(recovery.recoverIfNeeded())
        XCTAssertEqual(restarted, [view])
    }

    func testDisabledFlagPreservesBaselineForRuntimeEnable() {
        enabled = false
        let recovery = makeRecovery()
        let view = WKWebView()
        watch(view, in: recovery)
        process = 200
        XCTAssertFalse(recovery.recoverIfNeeded())
        enabled = true
        XCTAssertTrue(recovery.recoverIfNeeded())
        XCTAssertEqual(restarted, [view])
    }

    func testRuntimeDisableVetoesRestart() {
        let recovery = makeRecovery()
        let view = WKWebView()
        watch(view, in: recovery)
        process = 200
        enabled = false
        XCTAssertFalse(recovery.recoverIfNeeded())
        XCTAssertTrue(restarted.isEmpty)
    }

    func testSupersededOrUnloadedContextIsNeverRestarted() {
        let recovery = makeRecovery()
        let view = WKWebView()
        watch(view, in: recovery)
        process = 200
        current = false
        XCTAssertFalse(recovery.recoverIfNeeded())
        current = true
        XCTAssertFalse(recovery.recoverIfNeeded(), "A discarded watch must stay discarded")
        XCTAssertTrue(restarted.isEmpty)
    }

    func testUnloadingOldIdentifierDoesNotStopReplacementWatch() {
        let recovery = makeRecovery()
        let old = WKWebView()
        let replacement = WKWebView()
        watch(old, in: recovery, identifier: "old")
        watch(replacement, in: recovery, identifier: "new")
        recovery.stopWatching(identifier: "old")
        process = 200
        XCTAssertTrue(recovery.recoverIfNeeded())
        XCTAssertEqual(restarted, [replacement])
    }

    func testUnloadingWatchedIdentifierStopsRecovery() {
        let recovery = makeRecovery()
        let view = WKWebView()
        watch(view, in: recovery)
        recovery.stopWatching(identifier: "embedded")
        process = 200
        XCTAssertFalse(recovery.recoverIfNeeded())
        XCTAssertTrue(restarted.isEmpty)
    }

    func testFreshBackgroundUsesItsOwnNetworkBaseline() {
        let recovery = makeRecovery()
        let old = WKWebView()
        watch(old, in: recovery)
        process = 200
        let replacement = WKWebView()
        watch(replacement, in: recovery)
        XCTAssertFalse(recovery.recoverIfNeeded())
        process = 300
        XCTAssertTrue(recovery.recoverIfNeeded())
        XCTAssertEqual(restarted, [replacement])
    }

    func testUnavailableRestartSPIKeepsWatchForLaterAttempt() {
        let recovery = makeRecovery()
        let view = WKWebView()
        watch(view, in: recovery)
        process = 200
        canRestart = false
        XCTAssertFalse(recovery.recoverIfNeeded())
        canRestart = true
        XCTAssertTrue(recovery.recoverIfNeeded())
        XCTAssertEqual(restarted, [view])
    }

    func testSynchronousReplacementDuringRestartKeepsItsNewWatch() throws {
        let old = WKWebView()
        let replacement = WKWebView()
        var recovery: CPMNetworkProcessRecovery?
        recovery = CPMNetworkProcessRecovery(isEnabled: { true }, checkInterval: 60,
                                             processIdentifier: { [unowned self] _ in self.process },
                                             restart: { [unowned self] view in
            self.restarted.append(view)
            if view === old { recovery?.watch(replacement, identifier: "new", isCurrent: { true }) }
            return true
        })
        let sut = try XCTUnwrap(recovery)
        watch(old, in: sut)
        process = 200
        XCTAssertTrue(sut.recoverIfNeeded())
        process = 300
        XCTAssertTrue(sut.recoverIfNeeded())
        XCTAssertEqual(restarted, [old, replacement])
        recovery = nil
    }

    func testBackgroundIsNotRetainedByWatch() {
        let recovery = makeRecovery()
        weak var released: WKWebView?
        autoreleasepool {
            let view = WKWebView()
            released = view
            watch(view, in: recovery)
        }
        XCTAssertNil(released)
        process = 200
        XCTAssertFalse(recovery.recoverIfNeeded())
    }

    func testPeriodicCheckRecoversWithoutNavigationAndDoesNotRetainOwner() async throws {
        var recovery: CPMNetworkProcessRecovery? = makeRecovery(interval: 0.01)
        weak var released = recovery
        let view = WKWebView()
        watch(view, in: try XCTUnwrap(recovery))
        process = 200
        let deadline = Date().addingTimeInterval(2)
        while restarted.isEmpty, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(restarted, [view])
        recovery = nil
        XCTAssertNil(released)
    }
}
