//
//  CPMNetworkProcessIntegrationTests.swift
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

import AppKit
import FeatureFlags_macOS
import WebExtensions
import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

#if DEBUG
@available(macOS 15.4, *)
@MainActor
final class CPMNetworkProcessIntegrationTests: CPMAppIntegrationTestCase {
    func testNetworkProcessCrashKeepsNavigationsWorkingAcrossTabsAndWindows() async throws {
        let harness = try await start()
        let tabs = try harness.openWindow(tabs: 2) + harness.openWindow(tabs: 2)
        for tab in tabs { assertHealthy(try await harness.navigate(tab, label: "before-crash")) }
        let context = try XCTUnwrap(harness.context)
        for iteration in 1...2 {
            let oldNetwork = try harness.crashNetworkProcess()
            for tab in tabs { assertHealthy(try await harness.navigate(tab, label: "after-crash-\(iteration)")) }
            XCTAssertNotEqual(CPMAppWebKit.network(CPMAppWebKit.background(harness.context)), oldNetwork)
        }
        XCTAssertTrue(harness.context === context, "Recovery must preserve the extension context")
    }

    func testNetworkProcessCrashRecoversExistingDocumentsWithoutExtensionReload() async throws {
        let harness = try await start()
        let tabs = try harness.openWindow(tabs: 2) + harness.openWindow()
        for tab in tabs { assertHealthy(try await harness.navigate(tab, label: "existing-document")) }
        let context = try XCTUnwrap(harness.context)
        let urls = tabs.map { $0.webView.url }
        let oldNetwork = try harness.crashNetworkProcess()
        // Give the idle watchdog a chance to detect replacement without a navigation.
        try await harness.pause(2)
        for tab in tabs {
            let recovered = try await harness.reinitialize(tab)
            XCTAssertTrue(recovered, "Previously loaded document must receive real initResp and dashboard")
        }
        XCTAssertEqual(tabs.map { $0.webView.url }, urls)
        XCTAssertNotEqual(CPMAppWebKit.network(CPMAppWebKit.background(harness.context)), oldNetwork)
        XCTAssertTrue(harness.context === context)
    }
    func testNetworkRecoveryWorksWithDiagnosticsAndStartupGateDisabled() async throws {
        let harness = try XCTUnwrap(harness)
        harness.diagnosticsEnabled = false
        try await harness.start()
        harness.setFlag(.webExtensionStateRestorationGate, enabled: false)
        let tab = try harness.openWindow()[0]
        assertHealthy(try await harness.navigate(tab, label: "no-diagnostics-baseline"))
        XCTAssertNil(harness.manager.cpmDiagnosticsRecorder)
        let context = try XCTUnwrap(harness.context)
        _ = try harness.crashNetworkProcess()
        assertHealthy(try await harness.navigate(tab, label: "no-diagnostics-after-crash"))
        XCTAssertTrue(harness.context === context)
    }

    func testRuntimeKillSwitchPreservesContextAndAllowsRecoveryWhenEnabled() async throws {
        let harness = try await start()
        let tab = try harness.openWindow()[0]
        assertHealthy(try await harness.navigate(tab, label: "runtime-flag-baseline"))
        let context = try XCTUnwrap(harness.context)
        let originalProcess = try XCTUnwrap(CPMAppWebKit.process(CPMAppWebKit.background(context)))
        harness.setFlag(.cpmNetworkProcessRecovery, enabled: false)
        _ = try harness.crashNetworkProcess()
        try await harness.pause(2)
        let disabledResponse = try await harness.reinitialize(tab)
        XCTAssertFalse(disabledResponse, "Disabled flag must retain the actual crash failure")
        XCTAssertEqual(CPMAppWebKit.process(CPMAppWebKit.background(context)), originalProcess)
        harness.setFlag(.cpmNetworkProcessRecovery, enabled: true)
        try await harness.wait("background restart after runtime flag enable", timeout: 5) {
            CPMAppWebKit.process(CPMAppWebKit.background(context)) != originalProcess
        }
        let recovered = try await harness.reinitialize(tab)
        XCTAssertTrue(recovered)
        XCTAssertTrue(harness.context === context)
        assertHealthy(try await harness.navigate(tab, label: "runtime-flag-recovered"))
    }

}
#endif
