//
//  CPMReproSingleTabTests.swift
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

/// Single-tab failures: one document's `init` must reach the background service worker. These run
/// the app's path (lifecycle coordinator, navigation gate) and must pass.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMReproSingleTabTests: CPMReproTestCase {

    // MARK: First background load

    /// App launch with a first install: tabs navigate while the coordinator is still loading.
    func testColdStartInitIsDelivered() async throws {
        var lost = 0
        for iteration in 1...iterations {
            let harness = try await makeHarness(Options(waitForLoad: false))
            let outcome = await harness.navigateAndMeasure(harness.openTab())
            harness.log.add("iteration \(iteration): \(outcome)")
            if outcome == .timedOut { lost += 1 }
        }
        print("COLD START: \(lost)/\(iterations) first navigations got no CPM response")
        XCTAssertEqual(lost, 0, "\(lost)/\(iterations) cold-start inits were lost")
    }

    /// First launch after an app update: the installed embedded extension is older than the
    /// bundled one, so the launch sync installs the new version under a new identifier.
    func testUpgradeOnLaunchInitIsDelivered() async throws {
        var lost = 0
        for iteration in 1...iterations {
            let directory = temporaryInstallationDirectory()
            let installer = try await makeHarness(Options(installationDirectory: directory))
            try installer.markInstalledVersionAsOutdated()

            let harness = try await makeHarness(Options(installationDirectory: directory, waitForLoad: false))
            let outcome = await harness.navigateAndMeasure(harness.openTab())
            harness.log.add("upgrade \(iteration): \(outcome)")
            if outcome == .timedOut { lost += 1 }
        }
        print("UPGRADE ON LAUNCH: \(lost)/\(iterations) first navigations got no CPM response")
        XCTAssertEqual(lost, 0)
    }

    /// App relaunch with the extension already installed: WebKit loads the background lazily.
    func testRelaunchColdStartInitIsDelivered() async throws {
        let directory = temporaryInstallationDirectory()
        _ = try await makeHarness(Options(installationDirectory: directory))
        var lost = 0
        for iteration in 1...iterations {
            let harness = try await makeHarness(Options(installationDirectory: directory, waitForLoad: false))
            XCTAssertTrue(harness.isRelaunch)
            let outcome = await harness.navigateAndMeasure(harness.openTab())
            harness.log.add("relaunch \(iteration): \(outcome)")
            if outcome == .timedOut { lost += 1 }
        }
        print("RELAUNCH COLD START: \(lost)/\(iterations) first navigations got no CPM response")
        XCTAssertEqual(lost, 0)
    }

    /// Cross-process relaunch. The first run installs into `CPM_REPRO_INSTALL_DIR` and skips; every
    /// later run is a real process relaunch that navigates while the app is still loading.
    func testProcessRelaunchColdStartInitIsDelivered() async throws {
        guard let path = ProcessInfo.processInfo.environment["CPM_REPRO_INSTALL_DIR"] else {
            throw XCTSkip("Set CPM_REPRO_INSTALL_DIR to measure a real process relaunch")
        }
        let directory = URL(fileURLWithPath: path)
        let isRelaunch = FileManager.default.fileExists(atPath: directory.appendingPathComponent("installed.json").path)
        let harness = try await makeHarness(Options(installationDirectory: directory, waitForLoad: isRelaunch == false))
        guard isRelaunch else {
            throw XCTSkip("Installed the extension; run again to measure a relaunch")
        }
        let outcome = await harness.navigateAndMeasure(harness.openTab())
        print("PROCESS RELAUNCH: \(outcome)")
        XCTAssertNotEqual(outcome, .timedOut)
    }

    // MARK: Background reload and wake

    /// After an extension reload (what M4 does), tabs navigate at once, including a new tab.
    func testNavigationRightAfterExtensionReloadInitIsDelivered() async throws {
        try requireLocalRun()
        var lost = 0
        for iteration in 1...iterations {
            let harness = try await makeHarness()
            let tab = harness.openTab()
            _ = await harness.navigateAndMeasure(tab)
            let identifier = try XCTUnwrap(harness.embeddedContext?.uniqueIdentifier)

            harness.log.add("reloading extension")
            try await harness.manager.reloadExtension(identifier: identifier)
            lost += await navigateAll([tab, harness.openTab()], in: harness)
            harness.log.add("iteration \(iteration) done")
        }
        print("AFTER RELOAD: \(lost) navigations right after extension reload got no CPM response")
        XCTAssertEqual(lost, 0)
    }

    /// Slows the background script's evaluation (a busy device), reloads the extension as M4
    /// does, and navigates while the new background's script is still running.
    func testInitWhileReloadedBackgroundEvaluatesIsDelivered() async throws {
        try requireLocalRun()
        var options = Options()
        options.prelude.startupBusyWaitMs = 1000
        var lost = 0
        for iteration in 1...iterations {
            let harness = try await makeHarness(options)
            let tab = harness.openTab()
            _ = await harness.navigateAndMeasure(tab)
            let identifier = try XCTUnwrap(harness.embeddedContext?.uniqueIdentifier)

            try await harness.manager.reloadExtension(identifier: identifier)
            _ = await harness.waitUntil(timeout: 5) { harness.backgroundPID != nil }
            let outcome = await harness.navigateAndMeasure(tab)
            harness.log.add("iteration \(iteration): -> \(outcome)")
            if outcome == .timedOut { lost += 1 }
        }
        print("SLOW BACKGROUND AFTER RELOAD: \(lost)/\(iterations) navigations lost init")
        XCTAssertEqual(lost, 0)
    }

    /// Leaves the extension idle until WebKit unloads the background, then one tab wakes it and a
    /// second tab navigates while the woken background is still loading.
    func testWakeAfterIdleUnloadInitIsDelivered() async throws {
        try requireLocalRun()
        let harness = try await makeHarness()
        let first = harness.openTab()
        let second = harness.openTab()
        _ = await harness.navigateAndMeasure(first)
        let unloaded = await harness.waitUntil(timeout: 60) { harness.backgroundWebView == nil }
        XCTAssertTrue(unloaded, "WebKit did not unload the idle background")

        let waking = harness.navigate(first)
        _ = await harness.waitUntil(timeout: 5) { harness.backgroundWebView != nil }
        let racing = harness.navigate(second)
        let wakingOutcome = await harness.outcome(for: waking, in: first)
        let racingOutcome = await harness.outcome(for: racing, in: second)
        harness.log.add("waking tab -> \(wakingOutcome); second tab during load -> \(racingOutcome)")
        XCTAssertNotEqual(wakingOutcome, .timedOut)
        XCTAssertNotEqual(racingOutcome, .timedOut)
    }

    /// Kills the background WebContent process (as in the error-6 telemetry), then navigates.
    func testBackgroundCrashThenInitIsDelivered() async throws {
        let harness = try await makeHarness()
        let tab = harness.openTab()
        _ = await harness.navigateAndMeasure(tab)
        let background = try XCTUnwrap(harness.backgroundWebView)

        harness.log.add("killing background web content process")
        try CPMReproWebKitSPI.killWebContentProcess(of: background)
        await harness.sleep(1)
        let outcome = await harness.navigateAndMeasure(tab)
        XCTAssertNotEqual(outcome, .timedOut, "navigation after background crash got no CPM response")
    }
}
