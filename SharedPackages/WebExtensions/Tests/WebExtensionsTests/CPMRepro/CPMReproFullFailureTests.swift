//
//  CPMReproFullFailureTests.swift
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

/// Full failure: one fault must not leave every tab, including documents loaded earlier, without
/// CPM. These run the app's path (navigation gate, M4) and must pass.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMReproFullFailureTests: CPMReproTestCase {

    // MARK: Network process crash

    /// Four working tabs, Network process crash, then already loaded documents re-send `init`
    /// and tabs navigate again.
    func testNetworkProcessCrashKeepsEveryTabWorking() async throws {
        let report = try await runFullFailureScenario(fault: .networkProcessCrash)
        XCTAssertFalse(report.allOutcomes.contains(.timedOut), "\(report)")
    }

    func testNetworkProcessCrashKeepsEveryTabWorkingRepeatedly() async throws {
        try requireLocalRun()
        var failures = 0
        for iteration in 1...iterations {
            let harness = try await makeHarness(Options(isHangRecoveryEnabled: false))
            let tabs = (0..<3).map { _ in harness.openTab() }
            _ = await navigateAll(tabs, in: harness)
            try crashNetworkProcess(of: harness)
            await harness.sleep(2)
            let iterationFailures = await navigateAll(tabs, in: harness)
            harness.log.add("iteration \(iteration): \(iterationFailures) failed navigations after crash")
            failures += iterationFailures
        }
        print("NETWORK PROCESS CRASH: \(failures) failed navigations in \(iterations) iterations")
        XCTAssertEqual(failures, 0)
    }

    /// Without M4, an active user keeps navigating after a Network process crash.
    func testNetworkProcessCrashRecoversWithoutExtensionReload() async throws {
        try requireLocalRun()
        let harness = try await makeHarness(Options(isHangRecoveryEnabled: false))
        let tab = harness.openTab()
        _ = await harness.navigateAndMeasure(tab)
        try crashNetworkProcess(of: harness)
        await harness.sleep(2)

        var failures = 0
        for _ in 0..<5 {
            if await harness.navigateAndMeasure(tab) == .timedOut { failures += 1 }
            await harness.sleep(3)
        }
        XCTAssertEqual(failures, 0)
    }

    // MARK: Worker death with the Network process intact

    /// The worker dies while its Network process stays the same, which the app cannot observe
    /// directly. The first failed navigation restarts the background, so at most that navigation is
    /// lost, and every tab, including documents that loaded before the fault, works afterwards
    /// without an extension reload.
    func testServiceWorkerTerminationCostsAtMostOneNavigation() async throws {
        try requireLocalRun()
        try await assertWorkerDeathCostsAtMostOneNavigation { harness in
            harness.log.add("FAULT: terminate service workers")
            try CPMReproWebKitSPI.terminateServiceWorkers(of: XCTUnwrap(harness.backgroundWebView))
        }
    }

    /// Same, with the worker killed by removing service worker registrations from the data store,
    /// as data clearing does when it runs without unloading the extensions first.
    func testServiceWorkerRegistrationRemovalCostsAtMostOneNavigation() async throws {
        try requireLocalRun()
        try await assertWorkerDeathCostsAtMostOneNavigation { harness in
            harness.log.add("FAULT: remove service worker registrations")
            let dataStore = try XCTUnwrap(harness.backgroundWebView).configuration.websiteDataStore
            await dataStore.removeData(ofTypes: [WKWebsiteDataTypeServiceWorkerRegistrations], modifiedSince: .distantPast)
        }
    }

    private func assertWorkerDeathCostsAtMostOneNavigation(killWorker: (CPMReproHarness) async throws -> Void) async throws {
        var lostNavigations = 0
        for iteration in 1...iterations {
            let harness = try await makeHarness()
            let tabs = (0..<4).map { _ in harness.openTab() }
            let failedBeforeFault = await navigateAll(tabs, in: harness)
            XCTAssertEqual(failedBeforeFault, 0, "tabs failed before the fault")
            try await killWorker(harness)
            await harness.sleep(1)
            if await harness.navigateAndMeasure(tabs[0]) == .timedOut { lostNavigations += 1 }

            var afterRecovery: [CPMReproHarness.Outcome] = []
            for tab in tabs.dropFirst() {
                afterRecovery.append(await harness.reinitExistingDocument(in: tab))
            }
            let failedNavigations = await navigateAll(tabs, in: harness)
            harness.log.add("iteration \(iteration): existing documents \(afterRecovery), failed navigations \(failedNavigations)")
            XCTAssertFalse(afterRecovery.contains(.timedOut), "documents loaded before the fault: \(afterRecovery)")
            XCTAssertEqual(failedNavigations, 0)
            XCTAssertEqual(harness.monitor.extensionReloadGeneration, 0, "recovery must not reload the extension")
        }
        print("WORKER DEATH: \(lostNavigations)/\(iterations) first navigations lost")
    }

    // MARK: Faults that WebKit already recovers from

    func testMemoryPressureKeepsEveryTabWorking() async throws {
        try requireLocalRun()
        let report = try await runFullFailureScenario(fault: .memoryPressure)
        XCTAssertFalse(report.allOutcomes.contains(.timedOut), "\(report)")
    }

    func testBackgroundFreezeKeepsEveryTabWorking() async throws {
        try requireLocalRun()
        let report = try await runFullFailureScenario(fault: .backgroundFreeze)
        XCTAssertFalse(report.allOutcomes.contains(.timedOut), "\(report)")
    }

    /// The in-flight message itself is lost when WebKit unloads the frozen background; the tabs
    /// must work afterwards.
    func testBackgroundFreezeWithMessageInFlightKeepsEveryTabWorking() async throws {
        try requireLocalRun()
        let report = try await runFullFailureScenario(fault: .backgroundFreezeWithMessageInFlight)
        XCTAssertFalse(report.allOutcomes.contains(.timedOut), "\(report)")
    }
}
