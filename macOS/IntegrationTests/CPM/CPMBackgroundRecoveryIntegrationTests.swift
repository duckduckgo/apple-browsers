//
//  CPMBackgroundRecoveryIntegrationTests.swift
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
@_spi(Testing) import PixelKit

@testable import DuckDuckGo_Privacy_Browser

#if DEBUG
@available(macOS 15.4, *)
@MainActor
// Review-only app/WebKit suite; this branch is not intended for merging.
// Runs only through the opt-in CPM Integration Tests scheme; keep it out of CI.
final class CPMBackgroundRecoveryIntegrationTests: CPMAppIntegrationTestCase {
    // Exceed both the five-second navigation gate and four-second response deadline.
    // Newer WebKit can otherwise buffer the first message until an eight-second startup finishes.
    private let lateStartupDelayMilliseconds = 12_000

    private var installStartupDelayMilliseconds: Int {
        Int(ProcessInfo.processInfo.environment["CPM_APP_INTEGRATION_INSTALL_DELAY_MS"] ?? "") ?? 4500
    }

    /// Port of #7379's install regression, using the real app's flag/lifecycle/navigation path.
    func testInstallDuringSessionInitIsDelivered() async throws {
        let harness = try XCTUnwrap(harness)
        harness.startupDelayMilliseconds = installStartupDelayMilliseconds
        try await harness.start(embeddedEnabled: false)
        let tab = try harness.openWindow()[0]
        XCTAssertNil(harness.context)
        if ProcessInfo.processInfo.environment["CPM_APP_INTEGRATION_DISABLE_P1_P2_FIXES"] == "1" {
            harness.setFlag(.webExtensionStateRestorationGate, enabled: false)
        }
        harness.setFlag(.embeddedExtension, enabled: true)
        try await harness.wait("mid-session embedded install", timeout: 15) { harness.context != nil }
        let probe = try await harness.navigate(tab, label: "install-during-session")
        assertHealthy(probe)
        await harness.app.webExtensionLifecycleCoordinator?.sync().value
        await harness.manager.loadEmbeddedExtensionBackgroundContent()
        XCTAssertEqual(harness.pixels.recoveryOutcomes(.installReadiness), [.backgroundReady])
        harness.note(["regression": "7379-install", "workerDelayMilliseconds": installStartupDelayMilliseconds,
                      "requiredBehavior": "The first document after a mid-session install receives native dashboard and page initResp"])
    }

    /// Port of #7379's upgrade regression; old/new installations coexist during the real upgrade.
    func testUpgradeDuringSessionInitIsDelivered() async throws {
        let harness = try await start()
        let tab = try harness.openWindow()[0]
        assertHealthy(try await harness.navigate(tab, label: "upgrade-during-session-baseline"))
        let original = try XCTUnwrap(harness.context)
        let storage = try XCTUnwrap(harness.storages.last)
        storage.startupDelayMilliseconds = installStartupDelayMilliseconds
        try XCTUnwrap(harness.installationStore).markInstalledVersionAsOutdated()
        if ProcessInfo.processInfo.environment["CPM_APP_INTEGRATION_DISABLE_P1_P2_FIXES"] == "1" {
            harness.setFlag(.webExtensionStateRestorationGate, enabled: false)
        }
        let sync = try XCTUnwrap(harness.app.webExtensionLifecycleCoordinator).sync()
        try await harness.wait("replacement embedded context", timeout: 15) {
            harness.manager.contexts.contains { $0.uniqueIdentifier != original.uniqueIdentifier }
        }
        let probe = try await harness.navigate(tab, label: "upgrade-during-session")
        assertHealthy(probe)
        await sync.value
        await harness.manager.loadEmbeddedExtensionBackgroundContent()
        let replacement = try XCTUnwrap(harness.context)
        XCTAssertNotEqual(replacement.uniqueIdentifier, original.uniqueIdentifier)
        XCTAssertTrue(harness.observedContextSets.contains {
            $0.contains(original.uniqueIdentifier) && $0.contains(replacement.uniqueIdentifier)
        }, "The production upgrade must load the replacement before unloading the old context")
        XCTAssertEqual(harness.pixels.recoveryOutcomes(.upgradeReadiness), [.backgroundReady])
        harness.note(["regression": "7379-upgrade", "workerDelayMilliseconds": installStartupDelayMilliseconds,
                      "contextSetsDuringUpgrade": harness.observedContextSets,
                      "requiredBehavior": "Wait for the replacement's background and deliver the first document's initResp"])
    }

    func testSlowBackgroundWakeKeepsFirstNavigationHealthy() async throws {
        let harness = try XCTUnwrap(harness)
        harness.startupDelayMilliseconds = 8000
        try await harness.start()
        let tab = try harness.openWindow()[0]
        assertHealthy(try await harness.navigate(tab, label: "slow-wake-fixed-baseline"))
        if ProcessInfo.processInfo.environment["CPM_APP_INTEGRATION_DISABLE_P1_P2_FIXES"] == "1" {
            harness.setFlag(.webExtensionStateRestorationGate, enabled: false)
        }
        try await harness.waitForIdle()
        let probe = try await harness.navigate(tab, label: "slow-wake-first-navigation-fixed", timeout: 20)
        assertHealthy(probe)
        // Also drain a late answer in the disabled-fix control before checking window deallocation.
        try await harness.wait("slow wake answer drained", timeout: 15) {
            harness.native.forwardedDashboardURLs.contains(probe.url.absoluteString)
        }
        XCTAssertEqual(harness.pixels.recoveryOutcomes(.backgroundWake), [.backgroundReady])
        XCTAssertTrue(harness.pixels.episodes.isEmpty)
        XCTAssertEqual(probe.diagnostics["bg_view_creations"], "2")
        XCTAssertEqual(harness.pixels.startupResponseMissingCount, 0, "An idle wake must not count as a first-startup failure")
        harness.note(["regression": "P1", "workerDelayMilliseconds": 8000,
                      "requiredBehavior": "First document receives initResp and native dashboard without a CPM timeout"])
    }

    func testBackgroundLoadFailureRecoversOriginalDocument() async throws {
        let harness = try XCTUnwrap(harness)
        harness.startupDelayMilliseconds = 5000
        try await harness.start()
        let tabs = try harness.openWindow()
        for tab in tabs { assertHealthy(try await harness.navigate(tab, label: "frozen-recovery-baseline")) }
        // P2 recovery is independent of P1's navigation gate; keep the original WebKit timing.
        harness.setFlag(.webExtensionStateRestorationGate, enabled: false)
        harness.setFlag(.cpmMessagingHangRecovery,
                        enabled: ProcessInfo.processInfo.environment["CPM_APP_INTEGRATION_DISABLE_P1_P2_FIXES"] != "1")
        let originalContext = try XCTUnwrap(harness.context)
        harness.observeBackgroundLoadErrors(in: originalContext)
        try await harness.waitForIdle()
        async let navigation = harness.navigate(tabs[0], label: "frozen-recovery-failure", timeout: 20)
        try await harness.wait("new background process", timeout: 10) {
            CPMAppWebKit.process(CPMAppWebKit.background(originalContext)) != nil
        }
        let process = try harness.freezeBackground()
        defer { harness.resume(process) }
        // Some WebKit builds report the expired load only after the stopped process can reply again.
        // Keep the actual 30-second deadline, then resume before waiting for the error notification.
        try await harness.pause(45)
        harness.resume(process)
        let failed = try await navigation
        assertFailed(failed)
        try await harness.wait("real WebKit error 6", timeout: 15) {
            harness.backgroundLoadErrorContexts.contains(ObjectIdentifier(originalContext))
        }
        harness.note(["regression": "P2", "errorCodes": originalContext.errors.map { ($0 as NSError).code },
                      "requiredBehavior": "Automatic same-document recovery after one failed wake, without a context reload or another navigation"])
        try await harness.wait("same-document recovery after WebKit load failure", timeout: 20) {
            harness.native.forwardedDashboardURLs.contains(failed.url.absoluteString)
        }
        let pageReceived = try await harness.waitForPageInitResponse(in: tabs[0])
        XCTAssertTrue(pageReceived, "The original failed document must receive initResp without navigating again")
        XCTAssertEqual(harness.pixels.recoveryOutcomes(.backgroundLoadRetry), [.backgroundReady])
        XCTAssertEqual(harness.pixels.startupResponseMissingCount, 0)
        XCTAssertTrue(harness.context === originalContext, "A one-wake load failure must not replace the live extension context")
        XCTAssertEqual(harness.pixels.episodes.last?.outcome, .failedMeasurementResponse)
        XCTAssertEqual(harness.pixels.episodes.last?.reloadState, .none as CPMMessagingEpisodeReport.ReloadState)
        harness.setFlag(.webExtensionStateRestorationGate, enabled: true)
        for tab in tabs { assertHealthy(try await harness.navigate(tab, label: "frozen-recovery-existing-tab", timeout: 20)) }
        assertHealthy(try await harness.navigate(try harness.openWindow()[0], label: "frozen-recovery-new-window"))
        assertHealthy(try await harness.navigate(try harness.appendTab(to: 0), label: "frozen-recovery-new-tab"))
        XCTAssertEqual(harness.context?.uniqueIdentifier, originalContext.uniqueIdentifier)
    }

    func testRecoveryPixelsUseSeparateNamesAndDailyCountFrequency() {
        let pixels = PixelKitMock()
        let adapter = MacOSWebExtensionPixelFiring(pixelFiring: pixels)
        for fix in CPMRecoveryFix.allCases {
            adapter.fire(.cpmRecovery(fix, outcome: fix == .lateDocumentReload ? .reloadStarted : .backgroundReady))
        }
        XCTAssertEqual(pixels.actualFireCalls.count, CPMRecoveryFix.allCases.count)
        for (call, fix) in zip(pixels.actualFireCalls, CPMRecoveryFix.allCases) {
            XCTAssertEqual(call.pixel.name, "web_extension_cpm_\(fix.rawValue)")
            XCTAssertEqual(call.pixel.namePrefix, .none)
            XCTAssertEqual(call.frequency, .dailyAndCount)
            XCTAssertEqual(call.pixel.parameters, ["outcome": fix == .lateDocumentReload ? "reload_started" : "background_ready"])
        }
        adapter.fire(WebExtensionPixelEvent.cpmStartupResponseMissing)
        XCTAssertEqual(pixels.actualFireCalls.count, CPMRecoveryFix.allCases.count + 1)
        let detection = pixels.actualFireCalls.last
        XCTAssertEqual(detection?.pixel.name, "web_extension_cpm_startup_response_missing")
        XCTAssertEqual(detection?.pixel.namePrefix, PixelKitNamePrefix.none)
        XCTAssertEqual(detection?.frequency, .dailyAndCount)
        XCTAssertEqual(detection?.pixel.parameters, [:])
    }

    func testLateStartupIsDetectedWithRecoveryDisabledWithoutReload() async throws {
        let harness = try XCTUnwrap(harness)
        harness.startupDelayMilliseconds = lateStartupDelayMilliseconds
        try await harness.start(embeddedEnabled: false)
        harness.setFlag(.cpmLateBackgroundDocumentRecovery, enabled: false)
        let tab = try harness.openWindow()[0]
        try await harness.warmUpWindow(for: tab)
        harness.setFlag(.embeddedExtension, enabled: true)
        try await harness.wait("detection-only install", timeout: 10) { harness.context != nil }
        let context = try XCTUnwrap(harness.context)
        let probe = try await harness.navigate(tab, label: "late-startup-detection-only", timeout: 15)
        assertFailed(probe)
        try await harness.wait("P4 detection with recovery disabled", timeout: 10) {
            harness.pixels.startupResponseMissingCount == 1
        }
        try await harness.pause(1)
        XCTAssertEqual(harness.finishedURLDates[probe.url]?.count, 1)
        XCTAssertFalse(harness.native.forwardedDashboardURLs.contains(probe.url.absoluteString))
        XCTAssertTrue(harness.pixels.recoveryOutcomes(.lateDocumentReload).isEmpty)
        XCTAssertTrue(harness.context === context)
        harness.note(["regression": "P4-detection-only", "recoveryEnabled": false,
                      "detections": harness.pixels.startupResponseMissingCount,
                      "finishCount": harness.finishedURLDates[probe.url]?.count ?? 0,
                      "requiredBehavior": "Count the first-startup missing response without reloading or claiming recovery"])
        assertHealthy(try await harness.navigate(tab, label: "manual-navigation-after-detection-only"))
        XCTAssertEqual(harness.pixels.startupResponseMissingCount, 1)
    }

    func testOverBudgetInstallRecoversFirstDocumentWithoutExtendingNavigationWait() async throws {
        try await exerciseLateStartup(upgrade: false)
    }

    func testOverBudgetUpgradeRecoversFirstDocumentWithoutExtendingNavigationWait() async throws {
        try await exerciseLateStartup(upgrade: true)
    }

    func testLateStartupDoesNotReloadEditedDocument() async throws {
        let harness = try XCTUnwrap(harness)
        harness.startupDelayMilliseconds = lateStartupDelayMilliseconds
        try await harness.start(embeddedEnabled: false)
        let tab = try harness.openWindow()[0]
        try await harness.warmUpWindow(for: tab)
        harness.setFlag(.embeddedExtension, enabled: true)
        try await harness.wait("late install context", timeout: 10) { harness.context != nil }
        let began = Date()
        async let navigation = harness.navigate(tab, label: "late-edited-document", timeout: 15)
        try await harness.wait("editable first document", timeout: 15) {
            harness.finishedURLDates.values.contains { $0.contains { $0 >= began } }
        }
        _ = try XCTUnwrap(harness.manager.pendingEmbeddedBackgroundStartup,
                          "Edit the first document while the background startup is still pending")
        _ = try await tab.webView.evaluateJavaScript("const input = document.createElement('input'); document.body.append(input); input.value = 'local edit';", in: nil, contentWorld: .defaultClient)
        let probe = try await navigation
        await harness.manager.loadEmbeddedExtensionBackgroundContent()
        try await harness.pause(1)
        XCTAssertEqual(harness.finishedURLDates[probe.url]?.count, 1)
        XCTAssertTrue(harness.pixels.recoveryOutcomes(.lateDocumentReload).isEmpty)
        assertHealthy(try await harness.navigate(tab, label: "manual-navigation-after-protected-edit"))
    }

    private func exerciseLateStartup(upgrade: Bool) async throws {
        let harness = try XCTUnwrap(harness)
        harness.startupDelayMilliseconds = upgrade ? 0 : lateStartupDelayMilliseconds
        try await harness.start(embeddedEnabled: upgrade)
        let tab = try harness.openWindow()[0]
        try await harness.warmUpWindow(for: tab)
        var sync: Task<Void, Never>?
        var expectedContext: WKWebExtensionContext?
        if upgrade {
            assertHealthy(try await harness.navigate(tab, label: "late-upgrade-baseline"))
            let original = try XCTUnwrap(harness.context)
            try XCTUnwrap(harness.storages.last).startupDelayMilliseconds = lateStartupDelayMilliseconds
            try XCTUnwrap(harness.installationStore).markInstalledVersionAsOutdated()
            sync = try XCTUnwrap(harness.app.webExtensionLifecycleCoordinator).sync()
            try await harness.wait("over-budget replacement context", timeout: 10) {
                harness.manager.contexts.contains { $0.uniqueIdentifier != original.uniqueIdentifier }
            }
            expectedContext = harness.manager.contexts.first { $0.uniqueIdentifier != original.uniqueIdentifier }
        } else {
            harness.setFlag(.embeddedExtension, enabled: true)
            try await harness.wait("over-budget install", timeout: 10) { harness.context != nil }
            expectedContext = harness.context
        }
        let context = try XCTUnwrap(expectedContext)
        let began = Date()
        async let navigation = harness.navigate(tab, label: "late-\(upgrade ? "upgrade" : "install")", timeout: 15)
        try await harness.wait("first document after the bounded navigation gate", timeout: 15) {
            harness.finishedURLDates.values.contains { $0.contains { $0 >= began } }
        }
        let firstFinish = try XCTUnwrap(harness.finishedURLDates.values.flatMap { $0 }.filter { $0 >= began }.min())
        let gate = try XCTUnwrap(harness.navigationGateWaits.last { $0.beganAt >= began })
        XCTAssertLessThan(gate.elapsed, 6.5, "The production five-second gate, with scheduler tolerance; exclude cold UI/page loading")
        XCTAssertTrue(gate.startupWasPendingAtRelease, "Navigation must resume while background startup remains pending")
        let firstURL = try XCTUnwrap(tab.webView.url)
        XCTAssertFalse(harness.native.forwardedDashboardURLs.contains(firstURL.absoluteString))
        let probe = try await navigation
        assertFailed(probe)
        try await harness.wait("P4 detection after late background readiness", timeout: 10) {
            harness.pixels.startupResponseMissingCount > 0
        }
        XCTAssertEqual(harness.pixels.startupResponseMissingCount, 1)
        try await harness.wait("automatic first-document recovery after late background readiness", timeout: 15) {
            harness.native.forwardedDashboardURLs.contains(firstURL.absoluteString)
        }
        let pageReceived = try await harness.waitForPageInitResponse(in: tab)
        XCTAssertTrue(pageReceived)
        try await harness.wait("one automatic reload finishes", timeout: 5) {
            harness.finishedURLDates[firstURL]?.count == 2
        }
        XCTAssertEqual(tab.webView.url, firstURL)
        XCTAssertTrue(harness.context === context)
        XCTAssertEqual(harness.pixels.recoveryOutcomes(.lateDocumentReload), [.reloadStarted, .responseReceived])
        await sync?.value
        harness.note(["regression": upgrade ? "late-upgrade" : "late-install", "workerDelayMilliseconds": lateStartupDelayMilliseconds,
                      "firstFinishSeconds": firstFinish.timeIntervalSince(began),
                      "navigationGateSeconds": gate.elapsed,
                      "startupWasPendingAtGateRelease": gate.startupWasPendingAtRelease,
                      "finishCount": harness.finishedURLDates[firstURL]?.count ?? 0,
                      "initialProbe": probe.report,
                      "requiredBehavior": "Navigation gate remains five seconds; exactly one automatic GET reload delivers real page initResp"])
    }

}
#endif
