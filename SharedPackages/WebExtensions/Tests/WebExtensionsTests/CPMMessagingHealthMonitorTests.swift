//
//  CPMMessagingHealthMonitorTests.swift
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
final class CPMMessagingHealthMonitorTests: XCTestCase {

    func testFirstFailureReportsInitializationReasonWithoutStartingStuckEpisode() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        let measurement = monitor.beginMeasurement(tabIdentifier: "tab-1", navigationKind: .sessionRestoration)
        let didBecomeStuck = monitor.reportFailure(measurement)

        XCTAssertFalse(didBecomeStuck)
        XCTAssertEqual(pixelFiring.events, ["initialization_failed_session_restoration"])
    }

    func testRepeatedSessionRestorationFailuresDoNotStartStuckEpisode() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        XCTAssertFalse(beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .sessionRestoration))
        XCTAssertFalse(beginAndReportFailure(on: monitor, tabIdentifier: "tab-2", navigationKind: .sessionRestoration))
        XCTAssertFalse(beginAndReportFailure(on: monitor, tabIdentifier: "tab-3", navigationKind: .sessionRestoration))

        XCTAssertEqual(pixelFiring.events, [
            "initialization_failed_session_restoration",
            "initialization_failed_session_restoration",
            "initialization_failed_session_restoration"
        ])
    }

    func testRegularFailureAfterSessionRestorationFailureReportsStuckWithRestorationReason() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        XCTAssertFalse(beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .sessionRestoration))
        XCTAssertTrue(beginAndReportFailure(on: monitor, tabIdentifier: "tab-2", navigationKind: .other))

        XCTAssertEqual(pixelFiring.events, [
            "initialization_failed_session_restoration",
            "initialization_failed_other",
            "stuck_session_restoration"
        ])
    }

    func testRestorationSuccessClearsPendingRestorationFailure() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .sessionRestoration)
        let successfulRestoration = monitor.beginMeasurement(tabIdentifier: "tab-2", navigationKind: .sessionRestoration)
        monitor.reportSuccess(successfulRestoration)

        XCTAssertFalse(beginAndReportFailure(on: monitor, tabIdentifier: "tab-3", navigationKind: .other))
        XCTAssertEqual(pixelFiring.events, [
            "initialization_failed_session_restoration",
            "initialization_failed_other"
        ])
    }

    func testSuccessOnFailedTabReportsRecoveryBeforeStuckState() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        let measurement = monitor.beginMeasurement(tabIdentifier: "tab-1", navigationKind: .other)
        monitor.reportFailure(measurement)
        monitor.reportSuccess(measurement)

        XCTAssertEqual(pixelFiring.events, ["initialization_failed_other", "recovered_without_reload"])
    }

    func testSuccessOnUnfailedTabResetsFailureSequenceWithoutReportingRecovery() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        let failedMeasurement = monitor.beginMeasurement(tabIdentifier: "tab-1", navigationKind: .other)
        monitor.reportFailure(failedMeasurement)
        let healthyMeasurement = monitor.beginMeasurement(tabIdentifier: "tab-2", navigationKind: .other)
        monitor.reportSuccess(healthyMeasurement)
        let didBecomeStuck = beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other)

        XCTAssertFalse(didBecomeStuck)
        XCTAssertEqual(pixelFiring.events, ["initialization_failed_other", "initialization_failed_other"])
    }

    func testSuccessOnAnyTabClosesStuckEpisode() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .tabCrash)
        beginAndReportFailure(on: monitor, tabIdentifier: "tab-2", navigationKind: .other)
        let healthyMeasurement = monitor.beginMeasurement(tabIdentifier: "tab-3", navigationKind: .other)
        monitor.reportSuccess(healthyMeasurement)

        XCTAssertEqual(pixelFiring.events, [
            "initialization_failed_tab_crash",
            "initialization_failed_other",
            "stuck_tab_crash",
            "recovered_without_reload"
        ])
    }

    func testSuccessAfterEmbeddedExtensionReloadReportsRecoveryForFailedTab() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other)
        monitor.handle(.reloaded(identifier: "embedded", type: .embedded, trigger: .dataClearing))
        let recoveredMeasurement = monitor.beginMeasurement(tabIdentifier: "tab-1", navigationKind: .other)
        monitor.reportSuccess(recoveredMeasurement)

        XCTAssertEqual(pixelFiring.events, ["initialization_failed_other", "recovered_after_reload"])
    }

    func testSuccessAfterEmbeddedExtensionReloadClosesStuckEpisode() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other)
        beginAndReportFailure(on: monitor, tabIdentifier: "tab-2", navigationKind: .other)
        monitor.handle(.reloaded(identifier: "embedded", type: .embedded, trigger: .dataClearing))
        let recoveredMeasurement = monitor.beginMeasurement(tabIdentifier: "tab-3", navigationKind: .other)
        monitor.reportSuccess(recoveredMeasurement)

        XCTAssertEqual(pixelFiring.events, [
            "initialization_failed_other",
            "initialization_failed_other",
            "stuck_other",
            "recovered_after_reload"
        ])
    }

    func testFailureAfterReloadIsReportedOncePerEpisode() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other)
        monitor.handle(.reloaded(identifier: "embedded", type: .embedded, trigger: .scriptletUpdate))
        beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other)
        beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other)

        XCTAssertEqual(pixelFiring.events, [
            "initialization_failed_other",
            "initialization_failed_extension_reload",
            "stuck_other",
            "reload_failed",
            "initialization_failed_other"
        ])
    }

    func testLifecycleReloadFailureDoesNotReportCPMReloadFailure() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other)
        monitor.handle(.reloadFailed(identifier: "embedded", type: .embedded, trigger: .explicit))

        XCTAssertEqual(pixelFiring.events, ["initialization_failed_other"])
    }

    func testOtherExtensionLifecycleEventsDoNotAffectCPMEpisode() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        let measurement = monitor.beginMeasurement(tabIdentifier: "tab-1", navigationKind: .other)
        monitor.reportFailure(measurement)
        monitor.handle(.reloaded(identifier: "dark-reader", type: .darkReader, trigger: .explicit))
        monitor.reportSuccess(measurement)

        XCTAssertEqual(pixelFiring.events, ["initialization_failed_other", "recovered_without_reload"])
    }

    func testNavigationStartedBeforeReloadDoesNotConsumePostReloadMeasurement() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        let preReloadMeasurement = monitor.beginMeasurement(tabIdentifier: "tab-1", navigationKind: .other)
        monitor.handle(.reloaded(identifier: "embedded", type: .embedded, trigger: .dataClearing))
        monitor.reportFailure(preReloadMeasurement)
        beginAndReportFailure(on: monitor, tabIdentifier: "tab-2", navigationKind: .other)

        XCTAssertEqual(pixelFiring.events, [
            "initialization_failed_other",
            "initialization_failed_extension_reload",
            "stuck_other",
            "reload_failed"
        ])
    }

    func testFirstFailureAfterReloadReportsReloadFailureAndRecoversAfterReload() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        monitor.handle(.reloaded(identifier: "embedded", type: .embedded, trigger: .dataClearing))
        let measurement = monitor.beginMeasurement(tabIdentifier: "tab-1", navigationKind: .other)
        monitor.reportFailure(measurement)
        monitor.reportSuccess(measurement)

        XCTAssertEqual(pixelFiring.events, [
            "initialization_failed_extension_reload",
            "reload_failed",
            "recovered_after_reload"
        ])
    }

    func testCancelledFirstPostReloadMeasurementHandsReloadAttributionToNextMeasurement() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        monitor.handle(.reloaded(identifier: "embedded", type: .embedded, trigger: .dataClearing))
        let cancelledMeasurement = monitor.beginMeasurement(tabIdentifier: "cancelled", navigationKind: .other)
        monitor.cancel(cancelledMeasurement)
        beginAndReportFailure(on: monitor, tabIdentifier: "next", navigationKind: .other)

        XCTAssertEqual(pixelFiring.events, [
            "initialization_failed_extension_reload",
            "reload_failed"
        ])
    }

    func testStuckEpisodeKeepsInitialExtensionReloadFailureReason() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        monitor.handle(.reloaded(identifier: "embedded", type: .embedded, trigger: .dataClearing))
        beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other)
        beginAndReportFailure(on: monitor, tabIdentifier: "tab-2", navigationKind: .other)

        XCTAssertEqual(pixelFiring.events, [
            "initialization_failed_extension_reload",
            "reload_failed",
            "initialization_failed_other",
            "stuck_extension_reload"
        ])
    }

    func testConcurrentOrdinaryFailuresDoNotStartStuckEpisode() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)
        let first = monitor.beginMeasurement(tabIdentifier: "tab-1", navigationKind: .other)
        let second = monitor.beginMeasurement(tabIdentifier: "tab-2", navigationKind: .other)

        XCTAssertFalse(monitor.reportFailure(first))
        XCTAssertFalse(monitor.reportFailure(second))
        XCTAssertFalse(pixelFiring.events.contains("stuck_other"))
    }

    func testConcurrentSuccessClearsEpisodeBeforeLaterFailure() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)
        let failed = monitor.beginMeasurement(tabIdentifier: "tab-1", navigationKind: .other)
        let concurrent = monitor.beginMeasurement(tabIdentifier: "tab-2", navigationKind: .other)
        monitor.reportFailure(failed)
        monitor.reportSuccess(concurrent)

        XCTAssertFalse(beginAndReportFailure(on: monitor, tabIdentifier: "tab-3", navigationKind: .other))
    }

    func testCancelledMeasurementCannotReportFailure() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)
        let measurement = monitor.beginMeasurement(tabIdentifier: "tab-1", navigationKind: .other)

        monitor.cancel(measurement)

        XCTAssertFalse(monitor.reportFailure(measurement))
        XCTAssertTrue(pixelFiring.events.isEmpty)
    }

    func testExpiredEpisodeIsNotCombinedWithLaterFailure() {
        var currentDate = Date(timeIntervalSince1970: 0)
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring, episodeLifetime: 60, now: { currentDate })
        beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other)

        currentDate.addTimeInterval(61)

        XCTAssertFalse(beginAndReportFailure(on: monitor, tabIdentifier: "tab-2", navigationKind: .other))
        XCTAssertFalse(pixelFiring.events.contains("stuck_other"))
    }

    func testBackForwardNavigationIsNotMeasured() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)
        let url = URL(string: "https://example.com/history")!

        monitor.handle(.navigationStarted(tabIdentifier: "tab-1", navigationKind: .backForward))
        monitor.handle(.navigationCommitted(tabIdentifier: "tab-1", url: url))
        monitor.handle(.navigationFinished(
            tabIdentifier: "tab-1",
            url: url,
            extensionIsLoaded: true
        ))
        await waitForEventTimeout()

        XCTAssertTrue(pixelFiring.events.isEmpty)
    }

    func testPendingTabCrashTakesPrecedenceOverBackForwardNavigation() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)
        let url = URL(string: "https://example.com/history")!

        monitor.handle(.webContentProcessTerminated(tabIdentifier: "tab-1"))
        monitor.handle(.navigationStarted(tabIdentifier: "tab-1", navigationKind: .backForward))
        monitor.handle(.navigationCommitted(tabIdentifier: "tab-1", url: url))
        monitor.handle(.navigationFinished(
            tabIdentifier: "tab-1",
            url: url,
            extensionIsLoaded: true
        ))
        await waitForEventTimeout()

        XCTAssertEqual(pixelFiring.events, ["initialization_failed_tab_crash"])
    }

    func testDashboardResponseBeforeNavigationFinishCompletesMeasurementWithoutFailure() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)
        let url = URL(string: "https://example.com/consent")!

        monitor.handle(.navigationStarted(tabIdentifier: "tab-1", navigationKind: .other))
        monitor.handle(.navigationCommitted(tabIdentifier: "tab-1", url: url))
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 17, url: url))
        monitor.handle(.navigationFinished(tabIdentifier: "tab-1", url: url, extensionIsLoaded: true))
        await waitForEventTimeout()

        XCTAssertTrue(pixelFiring.events.isEmpty)
    }

    func testConcurrentNavigationFailuresRequireLaterNavigationToReportStuck() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)

        finishNavigation(tabIdentifier: "tab-1", path: "one", on: monitor)
        finishNavigation(tabIdentifier: "tab-2", path: "two", on: monitor)
        await waitForEventTimeout()

        XCTAssertEqual(pixelFiring.events, ["initialization_failed_other", "initialization_failed_other"])

        finishNavigation(tabIdentifier: "tab-3", path: "three", on: monitor)
        await waitForEventTimeout()

        XCTAssertEqual(pixelFiring.events.suffix(2), ["initialization_failed_other", "stuck_other"])
    }

    func testNavigationStartCancelsPreviousDocumentTimeout() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)

        finishNavigation(tabIdentifier: "tab-1", path: "old", on: monitor)
        monitor.handle(.navigationStarted(tabIdentifier: "tab-1", navigationKind: .other))
        await waitForEventTimeout()

        XCTAssertTrue(pixelFiring.events.isEmpty)
    }

    func testNavigationFailureCancelsCurrentMeasurement() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)

        finishNavigation(tabIdentifier: "tab-1", path: "failed", on: monitor)
        monitor.handle(.navigationFailed(tabIdentifier: "tab-1"))
        await waitForEventTimeout()

        XCTAssertTrue(pixelFiring.events.isEmpty)
    }

    func testTabCloseCancelsCurrentMeasurement() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)

        finishNavigation(tabIdentifier: "tab-1", path: "closed", on: monitor)
        monitor.handle(.tabClosed(tabIdentifier: "tab-1"))
        await waitForEventTimeout()

        XCTAssertTrue(pixelFiring.events.isEmpty)
    }

    func testFinishWithDifferentURLFromCommitIsIgnored() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)
        let committedURL = URL(string: "https://example.com/committed")!
        let finishedURL = URL(string: "https://example.com/replaced")!

        startAndCommitNavigation(tabIdentifier: "tab-1", url: committedURL, navigationKind: .other, on: monitor)
        monitor.handle(.navigationFinished(tabIdentifier: "tab-1", url: finishedURL, extensionIsLoaded: true))
        await waitForEventTimeout()

        XCTAssertTrue(pixelFiring.events.isEmpty)
    }

    func testCommitWithoutObservedNavigationStartCanStillBeMeasured() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)
        let url = URL(string: "https://example.com/late-observer")!

        monitor.handle(.navigationCommitted(tabIdentifier: "tab-1", url: url))
        monitor.handle(.navigationFinished(tabIdentifier: "tab-1", url: url, extensionIsLoaded: true))
        await waitForEventTimeout()

        XCTAssertEqual(pixelFiring.events, ["initialization_failed_other"])
    }

    func testFinishWithoutObservedStartOrCommitCanStillBeMeasured() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)
        let url = URL(string: "https://example.com/late-observer")!

        monitor.handle(.navigationFinished(tabIdentifier: "tab-1", url: url, extensionIsLoaded: true))
        await waitForEventTimeout()

        XCTAssertEqual(pixelFiring.events, ["initialization_failed_other"])
    }

    func testDashboardResponseAfterNavigationFinishCancelsFailure() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)
        let url = URL(string: "https://example.com/responded")!

        finishNavigation(tabIdentifier: "tab-1", url: url, on: monitor)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 1, url: url))
        await waitForEventTimeout()

        XCTAssertTrue(pixelFiring.events.isEmpty)
    }

    func testNavigationFinishedWhileExtensionIsUnloadedExpiresWithoutReportingFailure() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)

        finishNavigation(tabIdentifier: "tab-1", path: "waiting", extensionIsLoaded: false, on: monitor)
        await waitForEventTimeout()

        XCTAssertTrue(pixelFiring.events.isEmpty)
    }

    func testExtensionLoadedStartsGracePeriodForWaitingNavigation() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)

        finishNavigation(tabIdentifier: "tab-1", path: "waiting", extensionIsLoaded: false, on: monitor)
        monitor.handle(.extensionLifecycle(.loaded(identifier: "embedded", type: .embedded)))
        await waitForEventTimeout()

        XCTAssertEqual(pixelFiring.events, ["initialization_failed_other"])
    }

    func testResponseWhileWaitingForExtensionPreventsFailureAfterExtensionLoads() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)
        let url = URL(string: "https://example.com/waiting")!

        finishNavigation(tabIdentifier: "tab-1", url: url, extensionIsLoaded: false, on: monitor)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 1, url: url))
        monitor.handle(.extensionLifecycle(.loaded(identifier: "embedded", type: .embedded)))
        await waitForEventTimeout()

        XCTAssertTrue(pixelFiring.events.isEmpty)
    }

    func testExtensionWillReloadCancelsCurrentNavigationMeasurements() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)

        finishNavigation(tabIdentifier: "tab-1", path: "one", on: monitor)
        finishNavigation(tabIdentifier: "tab-2", path: "two", on: monitor)
        monitor.handle(.extensionLifecycle(.willReload(identifier: "embedded", type: .embedded, trigger: .explicit)))
        await waitForEventTimeout()

        XCTAssertTrue(pixelFiring.events.isEmpty)
    }

    func testBufferedResponseBeforeReloadCannotCompletePostReloadMeasurement() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)
        let bufferedURL = URL(string: "https://example.com/buffered-before-reload")!

        monitor.handle(.dashboardResponse(extensionTabIdentifier: 7, url: bufferedURL))
        beginAndReportFailure(on: monitor, tabIdentifier: "failed", navigationKind: .other)
        monitor.handle(.willReload(identifier: "embedded", type: .embedded, trigger: .explicit))
        monitor.handle(.reloaded(identifier: "embedded", type: .embedded, trigger: .explicit))
        finishNavigation(tabIdentifier: "post-reload", url: bufferedURL, on: monitor)
        await waitForEventTimeout()

        XCTAssertEqual(pixelFiring.events, [
            "initialization_failed_other",
            "initialization_failed_extension_reload",
            "stuck_other",
            "reload_failed"
        ])
    }

    func testAttributedResponseBeforeReloadCannotCompleteNavigationFinishingAfterReload() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)
        let spanningURL = URL(string: "https://example.com/spanning-reload")!

        startAndCommitNavigation(tabIdentifier: "spanning", url: spanningURL, navigationKind: .other, on: monitor)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 8, url: spanningURL))
        beginAndReportFailure(on: monitor, tabIdentifier: "failed", navigationKind: .other)
        monitor.handle(.willReload(identifier: "embedded", type: .embedded, trigger: .explicit))
        monitor.handle(.reloaded(identifier: "embedded", type: .embedded, trigger: .explicit))
        monitor.handle(.navigationFinished(tabIdentifier: "spanning", url: spanningURL, extensionIsLoaded: true))
        await waitForEventTimeout()

        XCTAssertEqual(pixelFiring.events, [
            "initialization_failed_other",
            "initialization_failed_extension_reload",
            "stuck_other",
            "reload_failed"
        ])
    }

    func testDelayedRestorationFailureAfterRegularFailureDoesNotReportStuck() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)

        finishNavigation(tabIdentifier: "regular-1", path: "regular-1", on: monitor)
        await waitForEventTimeout()
        finishNavigation(
            tabIdentifier: "restored-1",
            path: "restored-1",
            navigationKind: .sessionRestoration,
            on: monitor
        )
        await waitForEventTimeout()

        XCTAssertEqual(pixelFiring.events, [
            "initialization_failed_other",
            "initialization_failed_session_restoration"
        ])

        finishNavigation(tabIdentifier: "regular-2", path: "regular-2", on: monitor)
        await waitForEventTimeout()

        XCTAssertEqual(pixelFiring.events.suffix(2), ["initialization_failed_other", "stuck_other"])
    }

    func testDelayedRestorationFinishAfterRegularFailureDoesNotReportStuck() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)
        let restorationURL = URL(string: "https://example.com/restored")!

        startAndCommitNavigation(
            tabIdentifier: "restored",
            url: restorationURL,
            navigationKind: .sessionRestoration,
            on: monitor
        )
        finishNavigation(tabIdentifier: "regular", path: "regular", on: monitor)
        await waitForEventTimeout()
        monitor.handle(.navigationFinished(tabIdentifier: "restored", url: restorationURL, extensionIsLoaded: true))
        await waitForEventTimeout()

        XCTAssertEqual(pixelFiring.events, [
            "initialization_failed_other",
            "initialization_failed_session_restoration"
        ])
    }

    func testRestorationAlreadyInFlightCannotConfirmLaterRegularFailure() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)
        let restoration = monitor.beginMeasurement(tabIdentifier: "restored", navigationKind: .sessionRestoration)
        let regular = monitor.beginMeasurement(tabIdentifier: "regular-1", navigationKind: .other)

        XCTAssertFalse(monitor.reportFailure(regular))
        XCTAssertFalse(monitor.reportFailure(restoration))
        XCTAssertTrue(beginAndReportFailure(on: monitor, tabIdentifier: "regular-2", navigationKind: .other))
        XCTAssertEqual(pixelFiring.events, [
            "initialization_failed_other",
            "initialization_failed_session_restoration",
            "initialization_failed_other",
            "stuck_other"
        ])
    }

    func testDelayedRestorationSuccessClosesRegularFailureWithoutRecoveryPixel() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        beginAndReportFailure(on: monitor, tabIdentifier: "regular-1", navigationKind: .other)
        let restoration = monitor.beginMeasurement(tabIdentifier: "restored", navigationKind: .sessionRestoration)
        monitor.reportSuccess(restoration)

        XCTAssertFalse(beginAndReportFailure(on: monitor, tabIdentifier: "regular-2", navigationKind: .other))
        XCTAssertEqual(pixelFiring.events, ["initialization_failed_other", "initialization_failed_other"])
    }

    func testSessionRestorationAfterReloadDoesNotConsumeReloadMeasurement() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        monitor.handle(.reloaded(identifier: "embedded", type: .embedded, trigger: .dataClearing))
        beginAndReportFailure(on: monitor, tabIdentifier: "restored", navigationKind: .sessionRestoration)
        beginAndReportFailure(on: monitor, tabIdentifier: "regular", navigationKind: .other)

        XCTAssertEqual(pixelFiring.events, [
            "initialization_failed_session_restoration",
            "initialization_failed_extension_reload",
            "stuck_session_restoration",
            "reload_failed"
        ])
    }

    func testPreReloadSuccessCannotRecoverEpisodeAcrossReloadBoundary() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)
        beginAndReportFailure(on: monitor, tabIdentifier: "failed", navigationKind: .other)
        let preReloadMeasurement = monitor.beginMeasurement(tabIdentifier: "pre-reload", navigationKind: .other)

        monitor.handle(.reloaded(identifier: "embedded", type: .embedded, trigger: .dataClearing))
        monitor.reportSuccess(preReloadMeasurement)

        XCTAssertEqual(pixelFiring.events, ["initialization_failed_other"])

        let postReloadMeasurement = monitor.beginMeasurement(tabIdentifier: "failed", navigationKind: .other)
        monitor.reportSuccess(postReloadMeasurement)

        XCTAssertEqual(pixelFiring.events, ["initialization_failed_other", "recovered_after_reload"])
    }

    func testUnattributedResponseRecoversStuckEpisodeWithoutReload() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other)
        beginAndReportFailure(on: monitor, tabIdentifier: "tab-2", navigationKind: .other)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: nil, url: URL(string: "https://example.com/healthy")!))

        XCTAssertEqual(pixelFiring.events, [
            "initialization_failed_other",
            "initialization_failed_other",
            "stuck_other",
            "recovered_without_reload"
        ])
    }

    func testUnattributedResponseCannotRecoverEpisodeAcrossReloadBoundary() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other)
        monitor.handle(.reloaded(identifier: "embedded", type: .embedded, trigger: .dataClearing))
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 99, url: URL(string: "https://example.com/unknown")!))

        let recovery = monitor.beginMeasurement(tabIdentifier: "tab-1", navigationKind: .other)
        monitor.reportSuccess(recovery)

        XCTAssertEqual(pixelFiring.events, ["initialization_failed_other", "recovered_after_reload"])
    }

    func testAmbiguousBufferedResponseIsAssociatedAfterOneTabNavigatesAway() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)
        let sharedURL = URL(string: "https://example.com/shared")!
        let replacementURL = URL(string: "https://example.com/replacement")!

        startAndCommitNavigation(tabIdentifier: "tab-1", url: sharedURL, navigationKind: .other, on: monitor)
        startAndCommitNavigation(tabIdentifier: "tab-2", url: sharedURL, navigationKind: .other, on: monitor)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 7, url: sharedURL))
        monitor.handle(.navigationCommitted(tabIdentifier: "tab-2", url: sharedURL))
        startAndCommitNavigation(tabIdentifier: "tab-2", url: replacementURL, navigationKind: .other, on: monitor)
        monitor.handle(.navigationFinished(tabIdentifier: "tab-1", url: sharedURL, extensionIsLoaded: true))
        await waitForEventTimeout()

        XCTAssertTrue(pixelFiring.events.isEmpty)
    }

    func testDistinctResponsesForRestoredTabsSharingURLBeforeFinishDoNotReportFailure() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)
        let sharedURL = URL(string: "https://example.com/restored")!

        startAndCommitNavigation(tabIdentifier: "restored-1", url: sharedURL, navigationKind: .sessionRestoration, on: monitor)
        startAndCommitNavigation(tabIdentifier: "restored-2", url: sharedURL, navigationKind: .sessionRestoration, on: monitor)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 385, url: sharedURL))
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 340, url: sharedURL))
        monitor.handle(.navigationFinished(tabIdentifier: "restored-1", url: sharedURL, extensionIsLoaded: true))
        monitor.handle(.navigationFinished(tabIdentifier: "restored-2", url: sharedURL, extensionIsLoaded: true))
        await waitForEventTimeout()

        XCTAssertTrue(pixelFiring.events.isEmpty)
    }

    func testExpiredBufferedResponseDoesNotCompleteLaterNavigation() async {
        var currentDate = Date(timeIntervalSince1970: 0)
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(
            pixelFiring: pixelFiring,
            episodeLifetime: 60,
            extensionLoadWait: 0.01,
            responseGracePeriod: 0.01,
            now: { currentDate }
        )
        let url = URL(string: "https://example.com/delayed")!

        monitor.handle(.dashboardResponse(extensionTabIdentifier: 8, url: url))
        currentDate.addTimeInterval(1)
        finishNavigation(tabIdentifier: "tab-1", url: url, on: monitor)
        await waitForEventTimeout()

        XCTAssertEqual(pixelFiring.events, ["initialization_failed_other"])
    }

    func testTabCloseRemovesExtensionTabMapping() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)
        let firstURL = URL(string: "https://example.com/first")!
        let secondURL = URL(string: "https://example.com/second")!

        startAndCommitNavigation(tabIdentifier: "tab-1", url: firstURL, navigationKind: .other, on: monitor)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 4, url: firstURL))
        monitor.handle(.tabClosed(tabIdentifier: "tab-1"))
        finishNavigation(tabIdentifier: "tab-2", url: secondURL, on: monitor)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 4, url: secondURL))
        await waitForEventTimeout()

        XCTAssertTrue(pixelFiring.events.isEmpty)
    }

    func testTabCloseAssociatesBufferedResponseWithRemainingMatchingTab() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)
        let sharedURL = URL(string: "https://example.com/shared")!

        finishNavigation(tabIdentifier: "tab-1", url: sharedURL, on: monitor)
        finishNavigation(tabIdentifier: "tab-2", url: sharedURL, on: monitor)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 1, url: sharedURL))
        monitor.handle(.tabClosed(tabIdentifier: "tab-2"))
        await waitForEventTimeout()

        XCTAssertTrue(pixelFiring.events.isEmpty)
    }

    func testNavigationFailureAfterCrashPreservesCrashAttributionForRetry() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)
        let failedURL = URL(string: "https://example.com/provisional")!

        monitor.handle(.webContentProcessTerminated(tabIdentifier: "tab-1"))
        startAndCommitNavigation(tabIdentifier: "tab-1", url: failedURL, navigationKind: .other, on: monitor)
        monitor.handle(.navigationFailed(tabIdentifier: "tab-1"))
        finishNavigation(tabIdentifier: "tab-1", path: "retry", on: monitor)
        await waitForEventTimeout()

        XCTAssertEqual(pixelFiring.events, ["initialization_failed_tab_crash"])
    }

    func testExpiredMeasurementCannotReportAndDoesNotLeaveTabTimeout() async {
        var currentDate = Date(timeIntervalSince1970: 0)
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(
            pixelFiring: pixelFiring,
            episodeLifetime: 0.01,
            extensionLoadWait: 1,
            responseGracePeriod: 1,
            now: { currentDate }
        )

        finishNavigation(tabIdentifier: "tab-1", path: "expired", on: monitor)
        currentDate.addTimeInterval(1)
        monitor.handle(.tabClosed(tabIdentifier: "unknown"))
        await waitForEventTimeout()

        XCTAssertTrue(pixelFiring.events.isEmpty)
    }

    func testDuplicateMeasurementResultsAreIgnored() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)
        let measurement = monitor.beginMeasurement(tabIdentifier: "tab-1", navigationKind: .other)

        monitor.reportFailure(measurement)
        XCTAssertFalse(monitor.reportFailure(measurement))
        monitor.reportSuccess(measurement)
        monitor.reportSuccess(measurement)
        monitor.cancel(measurement)

        XCTAssertEqual(pixelFiring.events, ["initialization_failed_other", "recovered_without_reload"])
    }

    func testNoOpMonitorAcceptsAllEventKinds() {
        let monitor = NoOpCPMMessagingHealthMonitor()

        monitor.handle(.navigationStarted(tabIdentifier: "tab-1", navigationKind: .other))
        monitor.handle(.navigationFailed(tabIdentifier: "tab-1"))
        monitor.handle(.tabClosed(tabIdentifier: "tab-1"))
    }

    func testExtensionTabMappingTargetsResponseWhenTabsLaterShareURL() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)
        let firstURL = URL(string: "https://example.com/first")!
        let secondURL = URL(string: "https://example.com/second")!
        let sharedURL = URL(string: "https://example.com/shared")!

        finishNavigation(tabIdentifier: "tab-1", url: firstURL, on: monitor)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 1, url: firstURL))
        finishNavigation(tabIdentifier: "tab-2", url: secondURL, on: monitor)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 2, url: secondURL))

        finishNavigation(tabIdentifier: "tab-1", url: sharedURL, on: monitor)
        finishNavigation(tabIdentifier: "tab-2", url: sharedURL, on: monitor)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 1, url: sharedURL))
        await waitForEventTimeout()

        XCTAssertEqual(pixelFiring.events, ["initialization_failed_other"])
    }

    func testCPMPixelMetadataDefinesCanonicalNamesFrequenciesAndParameters() throws {
        let initializationFailure = try XCTUnwrap(CPMWebExtensionPixelMetadata(event: .cpmInitializationFailed(reason: .tabCrash)))
        XCTAssertEqual(initializationFailure.name, "debug_web_extension_cpm_initialization_failed_after_tab_crash")
        XCTAssertEqual(initializationFailure.frequency, .daily)

        let stuck = try XCTUnwrap(CPMWebExtensionPixelMetadata(event: .cpmMessagingStuck(reason: .other)))
        XCTAssertEqual(stuck.name, "debug_web_extension_cpm_messaging_stuck_other")
        XCTAssertEqual(stuck.frequency, .dailyAndCount)

        let restorationStuck = try XCTUnwrap(CPMWebExtensionPixelMetadata(event: .cpmMessagingStuck(reason: .sessionRestoration)))
        XCTAssertEqual(restorationStuck.name, "debug_web_extension_cpm_messaging_stuck_session_restoration")

        let reloadStuck = try XCTUnwrap(CPMWebExtensionPixelMetadata(event: .cpmMessagingStuck(reason: .extensionReload)))
        XCTAssertEqual(reloadStuck.name, "debug_web_extension_cpm_messaging_stuck_extension_reload")

        let recovered = try XCTUnwrap(CPMWebExtensionPixelMetadata(event: .cpmMessagingRecoveredAfterExtensionReload))
        XCTAssertEqual(recovered.name, "debug_web_extension_cpm_messaging_recovered_after_extension_reload")
        XCTAssertEqual(recovered.frequency, .dailyAndCount)
    }

    func testCPMDocumentMatchingIncludesQueryAndIgnoresFragment() {
        let pageURL = URL(string: "https://example.com/path?test=1#first")!

        XCTAssertTrue(pageURL.matchesCPMDiagnosticsDocument(URL(string: "https://example.com/path?test=1#second")!))
        XCTAssertFalse(pageURL.matchesCPMDiagnosticsDocument(URL(string: "https://example.com/path?test=2#first")!))
        XCTAssertFalse(pageURL.matchesCPMDiagnosticsDocument(URL(string: "http://example.com/path?test=1#first")!))
    }

    func testCPMDashboardMatchingUsesHostAndNormalizedPathOnly() {
        let pageURL = URL(string: "https://example.com:8443?test=1#first")!

        XCTAssertTrue(pageURL.matchesCPMDashboardStatePage(URL(string: "http://example.com/?test=2#second")!))
        XCTAssertFalse(pageURL.matchesCPMDashboardStatePage(URL(string: "https://other.example.com/")!))
        XCTAssertFalse(pageURL.matchesCPMDashboardStatePage(URL(string: "https://example.com/path")!))
    }

    @discardableResult
    private func beginAndReportFailure(
        on monitor: CPMMessagingHealthMonitor,
        tabIdentifier: String,
        navigationKind: CPMNavigationKind
    ) -> Bool {
        let measurement = monitor.beginMeasurement(tabIdentifier: tabIdentifier, navigationKind: navigationKind)
        return monitor.reportFailure(measurement)
    }

    private func makeEventMonitor(pixelFiring: CapturingWebExtensionPixelFiring) -> CPMMessagingHealthMonitor {
        CPMMessagingHealthMonitor(
            pixelFiring: pixelFiring,
            episodeLifetime: 60,
            extensionLoadWait: 0.01,
            responseGracePeriod: 0.01,
            now: Date.init
        )
    }

    private func finishNavigation(
        tabIdentifier: String,
        path: String,
        navigationKind: CPMNavigationKind = .other,
        extensionIsLoaded: Bool = true,
        on monitor: CPMMessagingHealthMonitor
    ) {
        finishNavigation(
            tabIdentifier: tabIdentifier,
            url: URL(string: "https://example.com/\(path)")!,
            navigationKind: navigationKind,
            extensionIsLoaded: extensionIsLoaded,
            on: monitor
        )
    }

    private func finishNavigation(
        tabIdentifier: String,
        url: URL,
        navigationKind: CPMNavigationKind = .other,
        extensionIsLoaded: Bool = true,
        on monitor: CPMMessagingHealthMonitor
    ) {
        startAndCommitNavigation(tabIdentifier: tabIdentifier, url: url, navigationKind: navigationKind, on: monitor)
        monitor.handle(.navigationFinished(tabIdentifier: tabIdentifier, url: url, extensionIsLoaded: extensionIsLoaded))
    }

    private func startAndCommitNavigation(
        tabIdentifier: String,
        url: URL,
        navigationKind: CPMNavigationKind,
        on monitor: CPMMessagingHealthMonitor
    ) {
        monitor.handle(.navigationStarted(tabIdentifier: tabIdentifier, navigationKind: navigationKind))
        monitor.handle(.navigationCommitted(tabIdentifier: tabIdentifier, url: url))
    }

    private func waitForEventTimeout() async {
        try? await Task.sleep(nanoseconds: 30_000_000)
    }
}

@available(macOS 15.4, iOS 18.4, *)
private final class CapturingWebExtensionPixelFiring: WebExtensionPixelFiring {
    private(set) var events: [String] = []

    func fire(_ event: WebExtensionPixelEvent) {
        switch event {
        case .cpmInitializationFailed(let reason):
            events.append("initialization_failed_\(reason.rawValue)")
        case .cpmMessagingStuck(let reason):
            events.append("stuck_\(reason.rawValue)")
        case .cpmMessagingRecoveredWithoutExtensionReload:
            events.append("recovered_without_reload")
        case .cpmMessagingRecoveredAfterExtensionReload:
            events.append("recovered_after_reload")
        case .cpmMessagingExtensionReloadFailed:
            events.append("reload_failed")
        default:
            break
        }
    }
}
