//
//  CPMReproWebKitTests.swift
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
import WebKit
@testable import WebExtensions

/// Characterizes the system WebKit defects behind CPM messaging failures, with the app's
/// mitigations turned off. Each test asserts the defect is still present, so it fails once WebKit
/// fixes it and the matching mitigation can be reconsidered. Run with `CPM_REPRO_WEBKIT=1`.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMReproWebKitTests: CPMReproTestCase {

    override func setUp() async throws {
        try await super.setUp()
        try requireLocalRun()
        let isEnabled = ProcessInfo.processInfo.environment["CPM_REPRO_WEBKIT"] == "1"
        try XCTSkipUnless(isEnabled, "Set CPM_REPRO_WEBKIT=1 to characterize system WebKit")
    }

    private var unprotected: Options {
        Options(isHangRecoveryEnabled: false, isNavigationGateEnabled: false)
    }

    // MARK: Defect 1: message dropped during the first background load

    /// Without the navigation gate, a tab that navigates while WebKit loads a newly installed
    /// extension's background for the first time loses its `init`. The background script is slowed
    /// down, as on a busy device at launch, so the navigation lands in that window every time.
    func testWebKitDropsInitDuringFirstBackgroundLoad() async throws {
        var options = unprotected
        options.prelude.startupBusyWaitMs = 1000
        var lost = 0
        for iteration in 1...iterations {
            let harness = try await makeHarness(options)
            let tab = harness.openTab()
            let url = harness.navigate(tab)
            let outcome = await harness.outcome(for: url, in: tab)
            let received = harness.backgroundReceivedInit(from: url)
            harness.log.add("iteration \(iteration): \(outcome) backgroundReceivedInit=\(received)")
            if outcome == .timedOut { lost += 1 }
        }
        print("WEBKIT FIRST LOAD: \(lost)/\(iterations) inits dropped")
        XCTAssertGreaterThan(lost, 0, "WebKit delivered every init; the navigation gate may no longer be needed")
    }

    /// Sweeps how long after the extension load the first navigation starts.
    func testWebKitFirstLoadLossWindowSweep() async throws {
        var results: [String] = []
        for delay in [0, 25, 50, 100, 200, 400] {
            let harness = try await makeHarness(unprotected)
            await harness.sleep(TimeInterval(delay) / 1000)
            let tab = harness.openTab()
            let url = harness.navigate(tab)
            let outcome = await harness.outcome(for: url, in: tab)
            results.append("\(delay)ms: \(outcome == .timedOut ? "LOST" : "ok")")
        }
        print("SWEEP:\n" + results.joined(separator: "\n"))
    }

    // MARK: Defect 2: dead worker behind a live background

    /// After a Network process crash, WebKit keeps the background and drops every message from
    /// every tab, including documents that loaded before the crash.
    func testWebKitLosesWorkerAfterNetworkProcessCrash() async throws {
        let report = try await runFullFailureScenario(fault: .networkProcessCrash, options: unprotected)
        XCTAssertFalse(report.existingDocumentsAfterFault.contains { $0 != .timedOut }, "\(report)")
        XCTAssertFalse(report.navigationsAfterFault.contains { $0 != .timedOut }, "\(report)")
    }

    /// Terminating service workers through WebKit SPI produces the same state.
    func testWebKitLosesWorkerAfterServiceWorkerTermination() async throws {
        let report = try await runFullFailureScenario(fault: .serviceWorkerTermination, options: unprotected)
        XCTAssertFalse(report.navigationsAfterFault.contains { $0 != .timedOut }, "\(report)")
    }

    // MARK: Recovery actions

    /// Reloading the extension (M4) restores new navigations but not documents loaded before it;
    /// restarting only the background restores both. This is why the watchdog restarts the
    /// background instead of reloading the extension.
    func testOnlyBackgroundRestartRecoversExistingDocuments() async throws {
        let reloadOutcomes = try await recoverFromNetworkProcessCrash(byReloadingExtension: true)
        let restartOutcomes = try await recoverFromNetworkProcessCrash(byReloadingExtension: false)
        XCTAssertTrue(reloadOutcomes.contains(.timedOut), "extension reload: \(reloadOutcomes)")
        XCTAssertFalse(restartOutcomes.contains(.timedOut), "background restart: \(restartOutcomes)")
    }

    /// Crashes the Network process, applies one recovery action, then re-probes the documents that
    /// loaded before the crash.
    private func recoverFromNetworkProcessCrash(byReloadingExtension: Bool) async throws -> [CPMReproHarness.Outcome] {
        let harness = try await makeHarness(unprotected)
        let tabs = (0..<3).map { _ in harness.openTab() }
        _ = await navigateAll(tabs, in: harness)
        let background = try XCTUnwrap(harness.backgroundWebView)
        try crashNetworkProcess(of: harness)
        await harness.sleep(1)

        if byReloadingExtension {
            let identifier = try XCTUnwrap(harness.embeddedContext?.uniqueIdentifier)
            try await harness.manager.reloadExtension(identifier: identifier)
        } else {
            try CPMReproWebKitSPI.killWebContentProcess(of: background)
        }
        await harness.sleep(1)
        var outcomes: [CPMReproHarness.Outcome] = []
        for tab in tabs {
            outcomes.append(await harness.reinitExistingDocument(in: tab))
        }
        harness.log.add("recovery by \(byReloadingExtension ? "extension reload" : "background restart"): \(outcomes)")
        return outcomes
    }

    // MARK: Why a dead worker cannot be detected from the app

    /// `runtime.sendMessage` from the background page resolves at once without reaching the
    /// worker, even while it is alive, so the app cannot ping the worker without the extension's help.
    func testWebKitDoesNotDeliverBackgroundPageMessagesToWorker() async throws {
        let harness = try await makeHarness(unprotected)
        await harness.manager.loadEmbeddedExtensionBackgroundContent()
        _ = await harness.navigateAndMeasure(harness.openTab())
        let background = try XCTUnwrap(harness.backgroundWebView)
        let script = """
        const reply = await browser.runtime.sendMessage({ messageType: "autoconsent", autoconsentPayload: { type: "init" } });
        return reply === undefined ? "undefined" : JSON.stringify(reply);
        """
        let reply = try await background.callAsyncJavaScript(script, contentWorld: .page) as? String
        await harness.sleep(0.5)

        XCTAssertEqual(reply, "undefined")
        XCTAssertFalse(harness.log.lines.contains { $0.contains("recv init") && $0.contains("tab=undefined") })
    }

    /// Removing service worker registrations (as data clearing does) kills the worker in the same
    /// way. The apps unload and reload extensions around Fire, so this documents why that matters.
    func testWebKitLosesWorkerAfterServiceWorkerRegistrationRemoval() async throws {
        let harness = try await makeHarness(unprotected)
        await harness.manager.loadEmbeddedExtensionBackgroundContent()
        let tab = harness.openTab()
        _ = await harness.navigateAndMeasure(tab)
        let dataStore = try XCTUnwrap(harness.backgroundWebView).configuration.websiteDataStore
        await dataStore.removeData(ofTypes: [WKWebsiteDataTypeServiceWorkerRegistrations], modifiedSince: .distantPast)
        await harness.sleep(1)

        let first = await harness.navigateAndMeasure(tab)
        let second = await harness.navigateAndMeasure(tab)
        XCTAssertEqual([first, second], [.timedOut, .timedOut])
    }
}
