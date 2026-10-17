//
//  CPMReproTestCase.swift
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

/// Reproduction experiments for CPM Web Extension messaging failures on system WebKit.
///
/// These run the production extension, `WebExtensionManager` and `CPMMessagingHealthMonitor` in
/// real web views. Each test asserts the behavior users need; a failure means the problem
/// reproduced.
///
/// Tests run once per CI run. Tests that take long, or measure system WebKit rather than the
/// app, call `requireLocalRun()` and only run when `CPM_REPRO=1` is set. Repeat a test to measure
/// how often a problem reproduces:
///
///     CPM_REPRO=1 CPM_REPRO_ITERATIONS=20 swift test --filter CPMRepro
///
/// Optional knobs: `CPM_REPRO_ITERATIONS`, `CPM_REPRO_IDLE`, `CPM_REPRO_FREEZE`,
/// `CPM_REPRO_OBSERVE`, `CPM_REPRO_GAP`, `CPM_REPRO_INSTALL_DIR`.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
internal class CPMReproTestCase: XCTestCase {

    private var harness: CPMReproHarness?

    var iterations: Int {
        Int(ProcessInfo.processInfo.environment["CPM_REPRO_ITERATIONS"] ?? "") ?? 1
    }

    override func setUp() async throws {
        try await super.setUp()
        #if os(iOS)
        // The harness loads the bundled extension through `Bundle.module`, which the app-hosted iOS test
        // run cannot find; the missing bundle crashes the whole test process.
        throw XCTSkip("The CPM repro harness runs on macOS only")
        #endif
    }

    /// Skips the test unless `CPM_REPRO=1` is set. For tests too slow for CI.
    func requireLocalRun() throws {
        let isEnabled = ProcessInfo.processInfo.environment["CPM_REPRO"] == "1"
        try XCTSkipUnless(isEnabled, "Set CPM_REPRO=1 to run this CPM reproduction experiment")
    }

    override func tearDown() async throws {
        await harness?.tearDown()
        harness = nil
        try await super.tearDown()
    }

    /// Harness options. Defaults match the app: navigation gate and M4 on.
    struct Options {
        var prelude = CPMReproPrelude()
        var isHangRecoveryEnabled = true
        var isNavigationGateEnabled = true
        var installationDirectory: URL?
        /// Whether to wait for the coordinator's launch load and sync before returning.
        var waitForLoad = true
    }

    func makeHarness(_ options: Options = Options()) async throws -> CPMReproHarness {
        await harness?.tearDown()
        let harness = try CPMReproHarness(prelude: options.prelude,
                                          isHangRecoveryEnabled: options.isHangRecoveryEnabled,
                                          installationDirectory: options.installationDirectory)
        harness.isNavigationGateEnabled = options.isNavigationGateEnabled
        self.harness = harness
        await harness.start(waitForLoad: options.waitForLoad)
        return harness
    }

    func temporaryInstallationDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cpm-repro-install-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    /// Crashes WebKit's Network process, as a crash or jetsam on iOS would.
    func crashNetworkProcess(of harness: CPMReproHarness) throws {
        let background = try XCTUnwrap(harness.backgroundWebView)
        let pid = try XCTUnwrap(CPMReproWebKitSPI.networkProcessIdentifier(of: background))
        harness.log.add("FAULT: SIGKILL network process pid=\(pid)")
        kill(pid, SIGKILL)
    }

    /// Navigates every tab and returns how many navigations got no CPM response.
    func navigateAll(_ tabs: [CPMReproTab], in harness: CPMReproHarness) async -> Int {
        var failures = 0
        for tab in tabs {
            let outcome = await harness.navigateAndMeasure(tab)
            if outcome == .timedOut { failures += 1 }
        }
        return failures
    }
}
