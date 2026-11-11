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

import Combine
import WebKit
import XCTest
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMNetworkProcessRecoveryTests: XCTestCase {
    private let readinessTimeout: TimeInterval = 30
    private let flagUpdates = PassthroughSubject<Void, Never>()
    private var nextContextCheck: XCTestExpectation?
    private var nextRestart: XCTestExpectation?
    private var flagReads = 0
    private var processReads = 0
    private var contextChecks = 0
    private var process: Int32? = 100
    private var enabled = true
    private var current = true
    private var canRestart = true
    private var restarted: [WKWebView] = []
    private let pixels = RecoveryPixelFiringSpy()

    private func makeRecovery(interval: TimeInterval = 60) -> CPMNetworkProcessRecovery {
        CPMNetworkProcessRecovery(isEnabled: { [unowned self] in
            self.flagReads += 1
            return self.enabled
        }, featureFlagUpdates: flagUpdates.eraseToAnyPublisher(), pixelFiring: pixels, checkInterval: interval,
                                  processIdentifier: { [unowned self] _ in
            self.processReads += 1
            return self.process
        },
                                  restart: { [unowned self] webView in
            guard self.canRestart else { return false }
            self.restarted.append(webView)
            self.nextRestart?.fulfill()
            self.nextRestart = nil
            return true
        })
    }

    private func expectNextContextCheck() -> XCTestExpectation {
        let checked = expectation(description: "The watched background is checked")
        nextContextCheck = checked
        return checked
    }

    private func expectNextRestart() -> XCTestExpectation {
        let restarted = expectation(description: "The watched background restarts")
        nextRestart = restarted
        return restarted
    }

    private func watch(_ view: WKWebView, in recovery: CPMNetworkProcessRecovery, identifier: String = "embedded") {
        recovery.watch(view, identifier: identifier, isCurrent: { [unowned self] in
            self.contextChecks += 1
            self.nextContextCheck?.fulfill()
            self.nextContextCheck = nil
            return self.current
        })
    }

    func testUnchangedNetworkProcessDoesNotRestartHealthyBackground() {
        let recovery = makeRecovery()
        let view = WKWebView()
        watch(view, in: recovery)
        XCTAssertFalse(recovery.recoverIfNeeded())
        XCTAssertTrue(restarted.isEmpty)
        XCTAssertEqual(pixels.recoveryCount, 0)
    }

    func testRecoveryReadsTheWatchedDataStoreWithoutCopyingConfigurationAgain() {
        let dataStore = WKWebsiteDataStore.nonPersistent()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        let view = ConfigurationCountingWebView(frame: .zero, configuration: configuration)
        var observedStores: [WKWebsiteDataStore] = []
        let recovery = CPMNetworkProcessRecovery(isEnabled: { true },
                                                 processIdentifier: { [unowned self] store in
            observedStores.append(store)
            return self.process
        }, restart: { [unowned self] view in
            self.restarted.append(view)
            return true
        })
        watch(view, in: recovery)
        let configurationReads = view.configurationReads

        XCTAssertFalse(recovery.recoverIfNeeded())
        process = 200
        XCTAssertTrue(recovery.recoverIfNeeded())

        XCTAssertEqual(observedStores.count, 3)
        XCTAssertTrue(observedStores.allSatisfy { $0 === dataStore }, "Read the background's isolated store, not the default store")
        XCTAssertEqual(view.configurationReads, configurationReads, "Checks must reuse the store captured by the watch")
        XCTAssertEqual(restarted, [view])
    }

    func testReplacedNetworkProcessRestartsOnlyOnce() {
        let recovery = makeRecovery()
        let view = WKWebView()
        watch(view, in: recovery)
        process = 200
        XCTAssertTrue(recovery.recoverIfNeeded())
        XCTAssertFalse(recovery.recoverIfNeeded())
        XCTAssertEqual(restarted, [view])
        XCTAssertEqual(pixels.recoveryCount, 1)
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
        XCTAssertEqual(pixels.recoveryCount, 0)
    }

    func testInitiallyDisabledFlagDoesNotStartPolling() async throws {
        enabled = false
        let recovery = makeRecovery(interval: 0.01)
        let view = WKWebView()
        watch(view, in: recovery)
        let initialFlagReads = flagReads
        let initialProcessReads = processReads
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(flagReads, initialFlagReads, "Disabled recovery must not wake to poll the flag")
        XCTAssertEqual(processReads, initialProcessReads)
        XCTAssertEqual(contextChecks, 0)
        withExtendedLifetime(recovery) {}
    }

    func testRuntimeDisableStopsPollingAndEnableRecoversWithoutNavigation() async throws {
        let recovery = makeRecovery(interval: 0.01)
        let view = WKWebView()
        let polled = expectNextContextCheck()
        watch(view, in: recovery)
        await fulfillment(of: [polled], timeout: readinessTimeout)
        XCTAssertGreaterThan(contextChecks, 0, "The enabled watch must poll before testing disable")
        enabled = false
        flagUpdates.send(())
        // The flag subscriber runs on the main queue. Wait until it has handled this update.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
        let disabledFlagReads = flagReads
        let disabledProcessReads = processReads
        let disabledContextChecks = contextChecks
        process = 200
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(flagReads, disabledFlagReads, "Flag disable must cancel the periodic task")
        XCTAssertEqual(processReads, disabledProcessReads)
        XCTAssertEqual(contextChecks, disabledContextChecks)
        XCTAssertTrue(restarted.isEmpty)
        let didRestart = expectNextRestart()
        enabled = true
        flagUpdates.send(())
        await fulfillment(of: [didRestart], timeout: readinessTimeout)
        XCTAssertEqual(restarted, [view], "Re-enable must recover using the retained baseline without navigation")
        withExtendedLifetime(recovery) {}
    }

    func testRuntimeEnableStartsPollingForInitiallyDisabledHealthyBackground() async throws {
        enabled = false
        let recovery = makeRecovery(interval: 0.01)
        let view = WKWebView()
        watch(view, in: recovery)
        let polled = expectNextContextCheck()
        enabled = true
        flagUpdates.send(())
        await fulfillment(of: [polled], timeout: readinessTimeout)
        XCTAssertGreaterThan(contextChecks, 0)
        XCTAssertTrue(restarted.isEmpty)
        let didRestart = expectNextRestart()
        process = 200
        await fulfillment(of: [didRestart], timeout: readinessTimeout)
        XCTAssertEqual(restarted, [view])
        withExtendedLifetime(recovery) {}
    }

    func testActivePollingAndFlagSubscriptionDoNotRetainOwner() async throws {
        var recovery: CPMNetworkProcessRecovery? = makeRecovery(interval: 0.01)
        weak var released = recovery
        let view = WKWebView()
        let polled = expectNextContextCheck()
        watch(view, in: try XCTUnwrap(recovery))
        await fulfillment(of: [polled], timeout: readinessTimeout)
        XCTAssertGreaterThan(contextChecks, 0)
        recovery = nil
        XCTAssertNil(released)
        flagUpdates.send(())
        try await Task.sleep(for: .milliseconds(50))
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
        XCTAssertEqual(pixels.recoveryCount, 0)
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

    func testLateOldBackgroundDuringUpgradeDoesNotDiscardReplacementWatch() {
        let recovery = makeRecovery()
        let old = WKWebView()
        let replacement = WKWebView()
        let lateOld = WKWebView()
        watch(old, in: recovery, identifier: "old")
        watch(replacement, in: recovery, identifier: "new")
        watch(lateOld, in: recovery, identifier: "old")
        recovery.stopWatching(identifier: "old")

        process = 200
        XCTAssertTrue(recovery.recoverIfNeeded())
        XCTAssertEqual(restarted, [replacement])
        XCTAssertFalse(recovery.recoverIfNeeded(), "The surviving background must only restart once")
    }

    func testOverlappingContextsKeepIndependentNetworkProcessBaselines() {
        let recovery = makeRecovery()
        let old = WKWebView()
        let replacement = WKWebView()
        watch(old, in: recovery, identifier: "old")
        process = 200
        watch(replacement, in: recovery, identifier: "new")

        XCTAssertTrue(recovery.recoverIfNeeded())
        XCTAssertEqual(restarted, [old], "Only the background with a replaced Network process should restart")
        process = 300
        XCTAssertTrue(recovery.recoverIfNeeded())
        XCTAssertEqual(restarted, [old, replacement])
        XCTAssertFalse(recovery.recoverIfNeeded())
        XCTAssertEqual(pixels.recoveryCount, 2)
    }

    func testDiscardingStaleContextDoesNotDiscardAnotherContextWatch() {
        let recovery = makeRecovery()
        let old = WKWebView()
        let replacement = WKWebView()
        recovery.watch(old, identifier: "old", isCurrent: { false })
        watch(replacement, in: recovery, identifier: "new")

        XCTAssertFalse(recovery.recoverIfNeeded())
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
        XCTAssertEqual(pixels.recoveryCount, 0)
        canRestart = true
        XCTAssertTrue(recovery.recoverIfNeeded())
        XCTAssertEqual(restarted, [view])
        XCTAssertEqual(pixels.recoveryCount, 1)
    }

    func testRecoveryPixelHasNoCustomParametersAndUsesDailyAndCount() throws {
        let metadata = try XCTUnwrap(CPMWebExtensionPixelMetadata(event: .cpmNetworkProcessRecoveryApplied))
        XCTAssertEqual(metadata.name, "web_extension_cpm_network_process_recovery_applied")
        XCTAssertEqual(metadata.frequency, .dailyAndCount)
        XCTAssertTrue(metadata.parameters.isEmpty)
    }

    func testSynchronousReplacementDuringRestartKeepsItsNewWatch() throws {
        let old = WKWebView()
        let replacement = WKWebView()
        var recovery: CPMNetworkProcessRecovery?
        recovery = CPMNetworkProcessRecovery(isEnabled: { true }, checkInterval: 60,
                                             processIdentifier: { [unowned self] _ in self.process },
                                             restart: { [unowned self] view in
            self.restarted.append(view)
            if view === old { recovery?.watch(replacement, identifier: "embedded", isCurrent: { true }) }
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

    func testBackgroundIsNotRetainedByWatch() async throws {
        let recovery = makeRecovery()
        weak var released: WKWebView?
        autoreleasepool {
            let view = WKWebView()
            released = view
            watch(view, in: recovery)
        }
        // UIKit/WebKit can release initialization references on a later main-run-loop turn.
        let deadline = Date().addingTimeInterval(5)
        while released != nil, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNil(released, "The live recovery owner must not retain the background")
        process = 200
        XCTAssertFalse(recovery.recoverIfNeeded())
        withExtendedLifetime(recovery) {}
    }

    func testPeriodicCheckRecoversWithoutNavigationAndDoesNotRetainOwner() async throws {
        var recovery: CPMNetworkProcessRecovery? = makeRecovery(interval: 0.01)
        weak var released = recovery
        let view = WKWebView()
        watch(view, in: try XCTUnwrap(recovery))
        let didRestart = expectNextRestart()
        process = 200
        await fulfillment(of: [didRestart], timeout: readinessTimeout)
        XCTAssertEqual(restarted, [view])
        recovery = nil
        XCTAssertNil(released)
    }
}

@available(macOS 15.4, iOS 18.4, *)
@MainActor
private final class ConfigurationCountingWebView: WKWebView {
    private(set) var configurationReads = 0

    override var configuration: WKWebViewConfiguration {
        configurationReads += 1
        return super.configuration
    }
}

@available(macOS 15.4, iOS 18.4, *)
private final class RecoveryPixelFiringSpy: WebExtensionPixelFiring {
    private(set) var recoveryCount = 0

    func fire(_ event: WebExtensionPixelEvent) {
        guard case .cpmNetworkProcessRecoveryApplied = event else {
            XCTFail("Network process recovery must only emit its application event")
            return
        }
        recoveryCount += 1
    }
}
