//
//  CPMReproScenarios.swift
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
import notify
@testable import WebExtensions

/// Full-failure scenario shared by the app-path tests and the WebKit characterization tests.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
extension CPMReproTestCase {

    enum Fault: String {
        /// Terminates service workers through WebKit test SPI.
        case serviceWorkerTermination
        case backgroundFreeze
        case memoryPressure
        case backgroundFreezeWithMessageInFlight
        case networkProcessCrash
    }

    /// Outcomes of each phase of a full-failure scenario.
    struct FullFailureReport: CustomStringConvertible {
        var existingDocumentsAfterFault: [CPMReproHarness.Outcome] = []
        var navigationsAfterFault: [CPMReproHarness.Outcome] = []
        var didReloadExtension = false
        var untouchedDocumentsAfterRecovery: [CPMReproHarness.Outcome] = []
        var navigationsAfterRecovery: [CPMReproHarness.Outcome] = []

        var allOutcomes: [CPMReproHarness.Outcome] {
            existingDocumentsAfterFault + navigationsAfterFault + untouchedDocumentsAfterRecovery + navigationsAfterRecovery
        }

        var description: String {
            """
            existing documents after fault: \(existingDocumentsAfterFault)
            navigations after fault: \(navigationsAfterFault)
            M4 extension reload: \(didReloadExtension)
            untouched documents after recovery: \(untouchedDocumentsAfterRecovery)
            navigations after recovery: \(navigationsAfterRecovery)
            """
        }
    }

    /// Opens four tabs that all work, injects one fault, then:
    /// 1. asks every already loaded document to re-send `init` (no navigation),
    /// 2. navigates two tabs, which lets the production monitor confirm a hang and run M4,
    /// 3. after M4, re-probes the two documents that were never navigated, and navigates again.
    func runFullFailureScenario(fault: Fault, options: Options = Options()) async throws -> FullFailureReport {
        let harness = try await makeHarness(options)
        // Start from a fully loaded background so only the injected fault can break the tabs.
        await harness.manager.loadEmbeddedExtensionBackgroundContent()
        let tabs = (0..<4).map { _ in harness.openTab() }
        for tab in tabs {
            let outcome = await harness.navigateAndMeasure(tab)
            XCTAssertNotEqual(outcome, .timedOut, "\(tab.identifier) failed before the fault")
        }
        let navigated = Array(tabs.prefix(2))
        let untouched = Array(tabs.suffix(2))

        try await inject(fault, into: harness)

        var report = FullFailureReport()
        for tab in tabs {
            report.existingDocumentsAfterFault.append(await harness.reinitExistingDocument(in: tab))
        }
        for tab in navigated {
            report.navigationsAfterFault.append(await harness.navigateAndMeasure(tab))
        }
        report.didReloadExtension = await harness.waitUntil(timeout: 10) { harness.monitor.extensionReloadGeneration > 0 }
        await harness.sleep(1)
        for tab in untouched {
            report.untouchedDocumentsAfterRecovery.append(await harness.reinitExistingDocument(in: tab))
        }
        for tab in tabs {
            report.navigationsAfterRecovery.append(await harness.navigateAndMeasure(tab))
        }
        harness.log.add("REPORT \(fault.rawValue):\n\(report)")
        return report
    }

    func inject(_ fault: Fault, into harness: CPMReproHarness) async throws {
        let background = try XCTUnwrap(harness.backgroundWebView)
        switch fault {
        case .serviceWorkerTermination:
            harness.log.add("FAULT: terminate service workers")
            try CPMReproWebKitSPI.terminateServiceWorkers(of: background)
            await harness.sleep(1)
        case .backgroundFreeze:
            let seconds = TimeInterval(ProcessInfo.processInfo.environment["CPM_REPRO_FREEZE"] ?? "") ?? 10
            harness.log.add("FAULT: freeze background process for \(seconds)s")
            await harness.freezeBackground(for: seconds)
            await harness.sleep(1)
        case .backgroundFreezeWithMessageInFlight:
            let seconds = TimeInterval(ProcessInfo.processInfo.environment["CPM_REPRO_FREEZE"] ?? "") ?? 40
            harness.log.add("FAULT: freeze background for \(seconds)s while a tab's init is in flight")
            let freeze = Task { await harness.freezeBackground(for: seconds) }
            await harness.sleep(0.2)
            let tab = harness.openTab()
            let inFlight = harness.navigate(tab)
            await freeze.value
            let outcome = await harness.outcome(for: inFlight, in: tab, grace: 5)
            harness.log.add("in-flight navigation after thaw -> \(outcome) content=\(await harness.contentMarks(in: tab))")
            await harness.sleep(1)
        case .networkProcessCrash:
            try crashNetworkProcess(of: harness)
            await harness.sleep(2)
        case .memoryPressure:
            harness.log.add("FAULT: simulated memory pressure (org.WebKit.lowMemory)")
            notify_post("org.WebKit.lowMemory")
            await harness.sleep(2)
        }
    }
}
