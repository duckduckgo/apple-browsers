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

import WebKit
import XCTest

@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMMessagingHealthMonitorTests: XCTestCase {

    func testFirstFailureStaysLocalUntilEpisodeCompletion() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        let measurement = monitor.beginMeasurement(tabIdentifier: "tab-1", navigationKind: .sessionRestoration)
        let didBecomeStuck = monitor.reportFailure(measurement)

        XCTAssertFalse(didBecomeStuck)
        assertPendingEpisode(on: monitor, pixelFiring: pixelFiring, reason: .sessionRestoration,
                             wasStuck: false, reloadState: .none)
    }

    func testFirstHangAfterInitializationFailureInvokesConfirmedHangHandler() {
        let monitor = CPMMessagingHealthMonitor(pixelFiring: CapturingWebExtensionPixelFiring())
        var confirmedHangCount = 0
        monitor.onConfirmedHang = { confirmedHangCount += 1 }

        XCTAssertFalse(beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other))
        XCTAssertTrue(beginAndReportFailure(on: monitor, tabIdentifier: "tab-2", navigationKind: .other))

        XCTAssertEqual(confirmedHangCount, 1)
    }

    func testRepeatedSessionRestorationFailuresDoNotStartStuckEpisode() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        XCTAssertFalse(beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .sessionRestoration))
        XCTAssertFalse(beginAndReportFailure(on: monitor, tabIdentifier: "tab-2", navigationKind: .sessionRestoration))
        XCTAssertFalse(beginAndReportFailure(on: monitor, tabIdentifier: "tab-3", navigationKind: .sessionRestoration))

        assertPendingEpisode(on: monitor, pixelFiring: pixelFiring, reason: .sessionRestoration,
                             wasStuck: false, reloadState: .none)
    }

    func testRegularFailureAfterSessionRestorationFailureReportsStuckWithRestorationReason() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        XCTAssertFalse(beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .sessionRestoration))
        XCTAssertTrue(beginAndReportFailure(on: monitor, tabIdentifier: "tab-2", navigationKind: .other))

        assertPendingEpisode(on: monitor, pixelFiring: pixelFiring, reason: .sessionRestoration,
                             wasStuck: true, reloadState: .none)
    }

    func testRestorationSuccessClearsPendingRestorationFailure() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .sessionRestoration)
        let successfulRestoration = monitor.beginMeasurement(tabIdentifier: "tab-2", navigationKind: .sessionRestoration)
        monitor.reportSuccess(successfulRestoration)

        XCTAssertFalse(beginAndReportFailure(on: monitor, tabIdentifier: "tab-3", navigationKind: .other))
        assertReport(pixelFiring, reason: .sessionRestoration, wasStuck: false,
                     outcome: .otherTabResponse, reloadState: .none)
        monitor.reportSuccess(monitor.beginMeasurement(tabIdentifier: "tab-1", navigationKind: .other))
        XCTAssertEqual(pixelFiring.reports.count, 2)
        XCTAssertEqual(pixelFiring.reports.last?.reason, .other)
        XCTAssertFalse(pixelFiring.reports.last?.wasStuck ?? true)
    }

    func testSuccessOnFailedTabReportsRecoveryBeforeStuckState() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        let measurement = monitor.beginMeasurement(tabIdentifier: "tab-1", navigationKind: .other)
        monitor.reportFailure(measurement)
        monitor.reportSuccess(measurement)

        assertReport(pixelFiring, reason: .other, wasStuck: false,
                     outcome: .failedMeasurementResponse, reloadState: .none)
    }

    func testSuccessOnUnfailedTabReportsOtherTabEvidenceAndResetsFailureSequence() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        let failedMeasurement = monitor.beginMeasurement(tabIdentifier: "tab-1", navigationKind: .other)
        monitor.reportFailure(failedMeasurement)
        let healthyMeasurement = monitor.beginMeasurement(tabIdentifier: "tab-2", navigationKind: .other)
        monitor.reportSuccess(healthyMeasurement)
        let didBecomeStuck = beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other)

        XCTAssertFalse(didBecomeStuck)
        assertReport(pixelFiring, reason: .other, wasStuck: false,
                     outcome: .otherTabResponse, reloadState: .none)
        monitor.reportSuccess(monitor.beginMeasurement(tabIdentifier: "tab-1", navigationKind: .other))
        XCTAssertEqual(pixelFiring.reports.count, 2)
        XCTAssertEqual(pixelFiring.reports.last?.reason, .other)
        XCTAssertFalse(pixelFiring.reports.last?.wasStuck ?? true)
    }

    func testSuccessOnAnyTabClosesStuckEpisode() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .tabCrash)
        beginAndReportFailure(on: monitor, tabIdentifier: "tab-2", navigationKind: .other)
        let healthyMeasurement = monitor.beginMeasurement(tabIdentifier: "tab-3", navigationKind: .other)
        monitor.reportSuccess(healthyMeasurement)

        assertReport(pixelFiring, reason: .tabCrash, wasStuck: true,
                     outcome: .otherTabResponse, reloadState: .none)
    }

    func testSuccessAfterEmbeddedExtensionReloadReportsRecoveryForFailedTab() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other)
        monitor.handle(.reloaded(identifier: "embedded", type: .embedded, trigger: .dataClearing))
        let recoveredMeasurement = monitor.beginMeasurement(tabIdentifier: "tab-1", navigationKind: .other)
        monitor.reportSuccess(recoveredMeasurement)

        assertReport(pixelFiring, reason: .other, wasStuck: false,
                     outcome: .failedTabResponse, reloadState: .loaded)
    }

    func testSuccessAfterEmbeddedExtensionReloadClosesStuckEpisode() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other)
        beginAndReportFailure(on: monitor, tabIdentifier: "tab-2", navigationKind: .other)
        monitor.handle(.reloaded(identifier: "embedded", type: .embedded, trigger: .dataClearing))
        let recoveredMeasurement = monitor.beginMeasurement(tabIdentifier: "tab-3", navigationKind: .other)
        monitor.reportSuccess(recoveredMeasurement)

        assertReport(pixelFiring, reason: .other, wasStuck: true,
                     outcome: .otherTabResponse, reloadState: .loaded)
    }

    func testFailureAfterReloadIsReportedOncePerEpisode() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other)
        monitor.handle(.reloaded(identifier: "embedded", type: .embedded, trigger: .scriptletUpdate))
        beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other)
        beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other)

        // Every failure is in one tab, so the episode is not reported as stuck.
        assertPendingEpisode(on: monitor, pixelFiring: pixelFiring, reason: .other,
                             wasStuck: false, reloadState: .responseTimedOut)
    }

    func testLifecycleReloadFailureIsIncludedInEpisodeSummary() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other)
        monitor.handle(.reloadFailed(identifier: "embedded", type: .embedded, trigger: .explicit))

        assertPendingEpisode(on: monitor, pixelFiring: pixelFiring, reason: .other,
                             wasStuck: false, reloadState: .failed)
    }

    func testOtherExtensionLifecycleEventsDoNotAffectCPMEpisode() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        let measurement = monitor.beginMeasurement(tabIdentifier: "tab-1", navigationKind: .other)
        monitor.reportFailure(measurement)
        monitor.handle(.reloaded(identifier: "dark-reader", type: .darkReader, trigger: .explicit))
        monitor.reportSuccess(measurement)

        assertReport(pixelFiring, reason: .other, wasStuck: false,
                     outcome: .failedMeasurementResponse, reloadState: .none)
    }

    func testNavigationStartedBeforeReloadDoesNotConsumePostReloadMeasurement() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        let preReloadMeasurement = monitor.beginMeasurement(tabIdentifier: "tab-1", navigationKind: .other)
        monitor.handle(.reloaded(identifier: "embedded", type: .embedded, trigger: .dataClearing))
        monitor.reportFailure(preReloadMeasurement)
        beginAndReportFailure(on: monitor, tabIdentifier: "tab-2", navigationKind: .other)

        assertPendingEpisode(on: monitor, pixelFiring: pixelFiring, reason: .other,
                             wasStuck: true, reloadState: .responseTimedOut)
    }

    func testFirstFailureAfterReloadReportsReloadFailureAndRecoversAfterReload() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        monitor.handle(.reloaded(identifier: "embedded", type: .embedded, trigger: .dataClearing))
        let measurement = monitor.beginMeasurement(tabIdentifier: "tab-1", navigationKind: .other)
        monitor.reportFailure(measurement)
        monitor.reportSuccess(measurement)

        assertReport(pixelFiring, reason: .extensionReload, wasStuck: false,
                     outcome: .failedMeasurementResponse, reloadState: .responseTimedOut)
    }

    func testCancelledFirstPostReloadMeasurementHandsReloadAttributionToNextMeasurement() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        monitor.handle(.reloaded(identifier: "embedded", type: .embedded, trigger: .dataClearing))
        let cancelledMeasurement = monitor.beginMeasurement(tabIdentifier: "cancelled", navigationKind: .other)
        monitor.cancel(cancelledMeasurement)
        beginAndReportFailure(on: monitor, tabIdentifier: "next", navigationKind: .other)

        assertPendingEpisode(on: monitor, pixelFiring: pixelFiring, reason: .extensionReload,
                             wasStuck: false, reloadState: .responseTimedOut)
    }

    func testStuckEpisodeKeepsInitialExtensionReloadFailureReason() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        monitor.handle(.reloaded(identifier: "embedded", type: .embedded, trigger: .dataClearing))
        beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other)
        beginAndReportFailure(on: monitor, tabIdentifier: "tab-2", navigationKind: .other)

        assertPendingEpisode(on: monitor, pixelFiring: pixelFiring, reason: .extensionReload,
                             wasStuck: true, reloadState: .responseTimedOut)
    }

    func testConcurrentOrdinaryFailuresDoNotStartStuckEpisode() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)
        let first = monitor.beginMeasurement(tabIdentifier: "tab-1", navigationKind: .other)
        let second = monitor.beginMeasurement(tabIdentifier: "tab-2", navigationKind: .other)

        XCTAssertFalse(monitor.reportFailure(first))
        XCTAssertFalse(monitor.reportFailure(second))
        assertPendingEpisode(on: monitor, pixelFiring: pixelFiring, reason: .other,
                             wasStuck: false, reloadState: .none)
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
        assertNoEpisode(on: monitor, pixelFiring: pixelFiring)
    }

    func testExpiredEpisodeIsNotCombinedWithLaterFailure() {
        var currentDate = Date(timeIntervalSince1970: 0)
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring, episodeLifetime: 60, now: { currentDate })
        beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other)

        currentDate.addTimeInterval(61)

        XCTAssertFalse(beginAndReportFailure(on: monitor, tabIdentifier: "tab-2", navigationKind: .other))
        assertReport(pixelFiring, reason: .other, wasStuck: false,
                     outcome: .noResponseBeforeDeadline, reloadState: .none)
        XCTAssertNil(pixelFiring.metadata.last?.parameters["response_after"])
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
        await waitForEventTimeout(on: monitor)

        assertNoEpisode(on: monitor, pixelFiring: pixelFiring)
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
        await waitForEventTimeout(on: monitor)

        assertPendingEpisode(on: monitor, pixelFiring: pixelFiring, reason: .tabCrash,
                             wasStuck: false, reloadState: .none)
    }

    func testDashboardResponseBeforeNavigationFinishCompletesMeasurementWithoutFailure() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)
        let url = URL(string: "https://example.com/consent")!

        monitor.handle(.navigationStarted(tabIdentifier: "tab-1", navigationKind: .other))
        monitor.handle(.navigationCommitted(tabIdentifier: "tab-1", url: url))
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 17, url: url))
        monitor.handle(.navigationFinished(tabIdentifier: "tab-1", url: url, extensionIsLoaded: true))
        await waitForEventTimeout(on: monitor)

        assertNoEpisode(on: monitor, pixelFiring: pixelFiring)
    }

    func testConcurrentNavigationFailuresRequireLaterNavigationToReportStuck() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)

        finishNavigation(tabIdentifier: "tab-1", path: "one", on: monitor)
        finishNavigation(tabIdentifier: "tab-2", path: "two", on: monitor)
        await waitForEventTimeout(on: monitor)

        XCTAssertTrue(pixelFiring.reports.isEmpty)
        XCTAssertEqual(pixelFiring.confirmedHangCount, 0)

        finishNavigation(tabIdentifier: "tab-3", path: "three", on: monitor)
        await waitForEventTimeout(on: monitor)

        assertPendingEpisode(on: monitor, pixelFiring: pixelFiring, reason: .other,
                             wasStuck: true, reloadState: .none)
    }

    func testNavigationStartCancelsPreviousDocumentTimeout() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)

        finishNavigation(tabIdentifier: "tab-1", path: "old", on: monitor)
        monitor.handle(.navigationStarted(tabIdentifier: "tab-1", navigationKind: .other))
        await waitForEventTimeout(on: monitor)

        assertNoEpisode(on: monitor, pixelFiring: pixelFiring)
    }

    func testNavigationFailureCancelsCurrentMeasurement() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)

        finishNavigation(tabIdentifier: "tab-1", path: "failed", on: monitor)
        monitor.handle(.navigationFailed(tabIdentifier: "tab-1"))
        await waitForEventTimeout(on: monitor)

        assertNoEpisode(on: monitor, pixelFiring: pixelFiring)
    }

    func testTabCloseCancelsCurrentMeasurement() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)

        finishNavigation(tabIdentifier: "tab-1", path: "closed", on: monitor)
        monitor.handle(.tabClosed(tabIdentifier: "tab-1"))
        await waitForEventTimeout(on: monitor)

        assertNoEpisode(on: monitor, pixelFiring: pixelFiring)
    }

    func testFinishWithDifferentURLFromCommitIsIgnored() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)
        let committedURL = URL(string: "https://example.com/committed")!
        let finishedURL = URL(string: "https://example.com/replaced")!

        startAndCommitNavigation(tabIdentifier: "tab-1", url: committedURL, navigationKind: .other, on: monitor)
        monitor.handle(.navigationFinished(tabIdentifier: "tab-1", url: finishedURL, extensionIsLoaded: true))
        await waitForEventTimeout(on: monitor)

        assertNoEpisode(on: monitor, pixelFiring: pixelFiring)
    }

    func testCommitWithoutObservedNavigationStartCanStillBeMeasured() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)
        let url = URL(string: "https://example.com/late-observer")!

        monitor.handle(.navigationCommitted(tabIdentifier: "tab-1", url: url))
        monitor.handle(.navigationFinished(tabIdentifier: "tab-1", url: url, extensionIsLoaded: true))
        await waitForEventTimeout(on: monitor)

        assertPendingEpisode(on: monitor, pixelFiring: pixelFiring, reason: .other,
                             wasStuck: false, reloadState: .none)
    }

    func testFinishWithoutObservedStartOrCommitCanStillBeMeasured() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)
        let url = URL(string: "https://example.com/late-observer")!

        monitor.handle(.navigationFinished(tabIdentifier: "tab-1", url: url, extensionIsLoaded: true))
        await waitForEventTimeout(on: monitor)

        assertPendingEpisode(on: monitor, pixelFiring: pixelFiring, reason: .other,
                             wasStuck: false, reloadState: .none)
    }

    func testDashboardResponseAfterNavigationFinishCancelsFailure() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)
        let url = URL(string: "https://example.com/responded")!

        finishNavigation(tabIdentifier: "tab-1", url: url, on: monitor)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 1, url: url))
        await waitForEventTimeout(on: monitor)

        assertNoEpisode(on: monitor, pixelFiring: pixelFiring)
    }

    func testNavigationFinishedWhileExtensionIsUnloadedExpiresWithoutReportingFailure() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)

        finishNavigation(tabIdentifier: "tab-1", path: "waiting", extensionIsLoaded: false, on: monitor)
        await waitForEventTimeout(on: monitor)

        assertNoEpisode(on: monitor, pixelFiring: pixelFiring)
    }

    func testExtensionLoadedStartsGracePeriodForWaitingNavigation() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)

        finishNavigation(tabIdentifier: "tab-1", path: "waiting", extensionIsLoaded: false, on: monitor)
        monitor.handle(.extensionLifecycle(.loaded(identifier: "embedded", type: .embedded)))
        await waitForEventTimeout(on: monitor)

        assertPendingEpisode(on: monitor, pixelFiring: pixelFiring, reason: .other,
                             wasStuck: false, reloadState: .none)
    }

    func testResponseWhileWaitingForExtensionPreventsFailureAfterExtensionLoads() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)
        let url = URL(string: "https://example.com/waiting")!

        finishNavigation(tabIdentifier: "tab-1", url: url, extensionIsLoaded: false, on: monitor)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 1, url: url))
        monitor.handle(.extensionLifecycle(.loaded(identifier: "embedded", type: .embedded)))
        await waitForEventTimeout(on: monitor)

        assertNoEpisode(on: monitor, pixelFiring: pixelFiring)
    }

    func testExtensionWillReloadCancelsCurrentNavigationMeasurements() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)

        finishNavigation(tabIdentifier: "tab-1", path: "one", on: monitor)
        finishNavigation(tabIdentifier: "tab-2", path: "two", on: monitor)
        monitor.handle(.extensionLifecycle(.willReload(identifier: "embedded", type: .embedded, trigger: .explicit)))
        await waitForEventTimeout(on: monitor)

        assertNoEpisode(on: monitor, pixelFiring: pixelFiring)
    }

    func testPreReloadResponseCannotCompletePostReloadMeasurement() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)
        let preReloadURL = URL(string: "https://example.com/buffered-before-reload")!

        monitor.handle(.dashboardResponse(extensionTabIdentifier: 7, url: preReloadURL))
        beginAndReportFailure(on: monitor, tabIdentifier: "failed", navigationKind: .other)
        monitor.handle(.willReload(identifier: "embedded", type: .embedded, trigger: .explicit))
        monitor.handle(.reloaded(identifier: "embedded", type: .embedded, trigger: .explicit))
        finishNavigation(tabIdentifier: "post-reload", url: preReloadURL, on: monitor)
        await waitForEventTimeout(on: monitor)

        assertPendingEpisode(on: monitor, pixelFiring: pixelFiring, reason: .other,
                             wasStuck: true, reloadState: .responseTimedOut)
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
        await waitForEventTimeout(on: monitor)

        assertPendingEpisode(on: monitor, pixelFiring: pixelFiring, reason: .other,
                             wasStuck: true, reloadState: .responseTimedOut)
    }

    func testDelayedRestorationFailureAfterRegularFailureDoesNotReportStuck() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)

        finishNavigation(tabIdentifier: "regular-1", path: "regular-1", on: monitor)
        await waitForEventTimeout(on: monitor)
        finishNavigation(
            tabIdentifier: "restored-1",
            path: "restored-1",
            navigationKind: .sessionRestoration,
            on: monitor
        )
        await waitForEventTimeout(on: monitor)

        XCTAssertTrue(pixelFiring.reports.isEmpty)
        XCTAssertEqual(pixelFiring.confirmedHangCount, 0)

        finishNavigation(tabIdentifier: "regular-2", path: "regular-2", on: monitor)
        await waitForEventTimeout(on: monitor)

        assertPendingEpisode(on: monitor, pixelFiring: pixelFiring, reason: .other,
                             wasStuck: true, reloadState: .none)
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
        await waitForEventTimeout(on: monitor)
        monitor.handle(.navigationFinished(tabIdentifier: "restored", url: restorationURL, extensionIsLoaded: true))
        await waitForEventTimeout(on: monitor)

        assertPendingEpisode(on: monitor, pixelFiring: pixelFiring, reason: .other,
                             wasStuck: false, reloadState: .none)
    }

    func testRestorationAlreadyInFlightCannotConfirmLaterRegularFailure() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)
        let restoration = monitor.beginMeasurement(tabIdentifier: "restored", navigationKind: .sessionRestoration)
        let regular = monitor.beginMeasurement(tabIdentifier: "regular-1", navigationKind: .other)

        XCTAssertFalse(monitor.reportFailure(regular))
        XCTAssertFalse(monitor.reportFailure(restoration))
        XCTAssertTrue(beginAndReportFailure(on: monitor, tabIdentifier: "regular-2", navigationKind: .other))
        assertPendingEpisode(on: monitor, pixelFiring: pixelFiring, reason: .other,
                             wasStuck: true, reloadState: .none)
    }

    func testDelayedRestorationSuccessClosesRegularFailureWithOtherTabEvidence() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        beginAndReportFailure(on: monitor, tabIdentifier: "regular-1", navigationKind: .other)
        let restoration = monitor.beginMeasurement(tabIdentifier: "restored", navigationKind: .sessionRestoration)
        monitor.reportSuccess(restoration)

        XCTAssertFalse(beginAndReportFailure(on: monitor, tabIdentifier: "regular-2", navigationKind: .other))
        assertReport(pixelFiring, reason: .other, wasStuck: false,
                     outcome: .otherTabResponse, reloadState: .none)
        monitor.reportSuccess(monitor.beginMeasurement(tabIdentifier: "tab-1", navigationKind: .other))
        XCTAssertEqual(pixelFiring.reports.count, 2)
        XCTAssertEqual(pixelFiring.reports.last?.reason, .other)
        XCTAssertFalse(pixelFiring.reports.last?.wasStuck ?? true)
    }

    func testSessionRestorationAfterReloadDoesNotConsumeReloadMeasurement() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        monitor.handle(.reloaded(identifier: "embedded", type: .embedded, trigger: .dataClearing))
        beginAndReportFailure(on: monitor, tabIdentifier: "restored", navigationKind: .sessionRestoration)
        beginAndReportFailure(on: monitor, tabIdentifier: "regular", navigationKind: .other)

        assertPendingEpisode(on: monitor, pixelFiring: pixelFiring, reason: .sessionRestoration,
                             wasStuck: true, reloadState: .responseTimedOut)
    }

    func testPreReloadSuccessCannotRecoverEpisodeAcrossReloadBoundary() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)
        beginAndReportFailure(on: monitor, tabIdentifier: "failed", navigationKind: .other)
        let preReloadMeasurement = monitor.beginMeasurement(tabIdentifier: "pre-reload", navigationKind: .other)

        monitor.handle(.reloaded(identifier: "embedded", type: .embedded, trigger: .dataClearing))
        monitor.reportSuccess(preReloadMeasurement)

        XCTAssertTrue(pixelFiring.reports.isEmpty)

        let postReloadMeasurement = monitor.beginMeasurement(tabIdentifier: "failed", navigationKind: .other)
        monitor.reportSuccess(postReloadMeasurement)

        assertReport(pixelFiring, reason: .other, wasStuck: false,
                     outcome: .failedTabResponse, reloadState: .loaded)
    }

    /// Once a tab mapping is learned, a response arriving between `navigationStarted` and
    /// `navigationCommitted` must survive until the commit that can claim it.
    func testMappedResponseArrivingBeforeCommitDoesNotCauseFailure() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)
        let url = URL(string: "https://example.com/mapped")!

        finishNavigation(tabIdentifier: "tab-1", url: url, on: monitor)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 21, url: url))
        await waitForEventTimeout(on: monitor)
        XCTAssertTrue(pixelFiring.reports.isEmpty, "Expected the first navigation to establish the mapping cleanly")

        monitor.handle(.navigationStarted(tabIdentifier: "tab-1", navigationKind: .other))
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 21, url: url))
        monitor.handle(.navigationCommitted(tabIdentifier: "tab-1", url: url))
        monitor.handle(.navigationFinished(tabIdentifier: "tab-1", url: url, extensionIsLoaded: true))
        await waitForEventTimeout(on: monitor)

        assertNoEpisode(on: monitor, pixelFiring: pixelFiring)
    }

    /// A response matching several unanswered tabs cannot be pinned to one of them, but it still
    /// proves the extension is answering, which is all a browser-wide episode needs to close.
    func testAmbiguousResponseRecoversStuckEpisodeWithoutReload() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)
        let sharedURL = URL(string: "https://example.com/healthy")!

        beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other)
        beginAndReportFailure(on: monitor, tabIdentifier: "tab-2", navigationKind: .other)
        startAndCommitNavigation(tabIdentifier: "tab-3", url: sharedURL, navigationKind: .other, on: monitor)
        startAndCommitNavigation(tabIdentifier: "tab-4", url: sharedURL, navigationKind: .other, on: monitor)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: nil, url: sharedURL))

        assertReport(pixelFiring, reason: .other, wasStuck: true,
                     outcome: .unattributedResponse, reloadState: .none)
    }

    /// A response whose URL matches no committed document is not health evidence: crediting it would
    /// report a recovery while the tab that actually received it still times out into a failure.
    func testResponseMatchingNoCommittedDocumentDoesNotRecoverStuckEpisode() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other)
        beginAndReportFailure(on: monitor, tabIdentifier: "tab-2", navigationKind: .other)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: nil, url: URL(string: "https://example.com/unknown")!))
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 11, url: URL(string: "https://example.com/unknown")!))

        assertPendingEpisode(on: monitor, pixelFiring: pixelFiring, reason: .other,
                             wasStuck: true, reloadState: .none)
    }

    func testUnattributedResponseCannotRecoverEpisodeAcrossReloadBoundary() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other)
        monitor.handle(.reloaded(identifier: "embedded", type: .embedded, trigger: .dataClearing))
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 99, url: URL(string: "https://example.com/unknown")!))

        let recovery = monitor.beginMeasurement(tabIdentifier: "tab-1", navigationKind: .other)
        monitor.reportSuccess(recovery)

        assertReport(pixelFiring, reason: .other, wasStuck: false,
                     outcome: .failedTabResponse, reloadState: .loaded)
    }

    /// A matching response supersedes an earlier unattributable one, so the navigation is measured
    /// after all and its success closes the episode instead of leaving it open to re-confirm stuck.
    func testMatchingResponseAfterAbandonmentStillReportsRecovery() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)
        let url = URL(string: "https://example.com/resumed")!

        // Establish the mapping 3 -> tab-1 with a healthy navigation.
        finishNavigation(tabIdentifier: "tab-1", url: url, on: monitor)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 3, url: url))
        await waitForEventTimeout(on: monitor)
        XCTAssertTrue(pixelFiring.reports.isEmpty)

        // Drive an episode to stuck on unrelated tabs.
        finishNavigation(tabIdentifier: "tab-2", path: "one", on: monitor)
        await waitForEventTimeout(on: monitor)
        finishNavigation(tabIdentifier: "tab-3", path: "two", on: monitor)
        await waitForEventTimeout(on: monitor)
        XCTAssertTrue(pixelFiring.reports.isEmpty)
        XCTAssertEqual(pixelFiring.confirmedHangCount, 1)

        // The response beats the commit, so it is unattributable and the navigation is abandoned.
        monitor.handle(.navigationStarted(tabIdentifier: "tab-1", navigationKind: .other))
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 3, url: url))
        // A second response, now matching the committed document, is provable evidence.
        monitor.handle(.navigationCommitted(tabIdentifier: "tab-1", url: url))
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 3, url: url))
        monitor.handle(.navigationFinished(tabIdentifier: "tab-1", url: url, extensionIsLoaded: true))
        await waitForEventTimeout(on: monitor)

        assertReport(pixelFiring, reason: .other, wasStuck: true,
                     outcome: .otherTabResponse, reloadState: .none)
    }

    /// The end-to-end shape of the reported case: two tabs share a URL, the episode goes stuck, and
    /// the extension starts answering again. The response is unattributable, but recovery is still
    /// reported rather than the episode being left open to be re-confirmed as stuck.
    func testAmbiguousResponseAfterStuckReportsRecovery() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)
        let sharedURL = URL(string: "https://example.com/shared")!

        finishNavigation(tabIdentifier: "tab-1", url: sharedURL, on: monitor)
        await waitForEventTimeout(on: monitor)
        finishNavigation(tabIdentifier: "tab-2", url: sharedURL, on: monitor)
        await waitForEventTimeout(on: monitor)

        XCTAssertTrue(pixelFiring.reports.isEmpty)
        XCTAssertEqual(pixelFiring.confirmedHangCount, 1)

        monitor.handle(.dashboardResponse(extensionTabIdentifier: nil, url: sharedURL))

        assertReport(pixelFiring, reason: .other, wasStuck: true,
                     outcome: .unattributedResponse, reloadState: .none)
    }

    /// Both candidates of an ambiguous response are abandoned, so neither reports an outcome even
    /// once the ambiguity resolves.
    func testAmbiguousResponseAbandonsCandidateNavigations() async {
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
        await waitForEventTimeout(on: monitor)

        assertNoEpisode(on: monitor, pixelFiring: pixelFiring)
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
        await waitForEventTimeout(on: monitor)

        assertNoEpisode(on: monitor, pixelFiring: pixelFiring)
    }

    /// Tabs restored to the same URL cannot be told apart, so they never report an outcome.
    func testDuplicateURLRestoredTabsNeverReportOutcomes() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)
        let sharedURL = URL(string: "https://example.com/restored")!

        finishNavigation(tabIdentifier: "restored-1", url: sharedURL, navigationKind: .sessionRestoration, on: monitor)
        finishNavigation(tabIdentifier: "restored-2", url: sharedURL, navigationKind: .sessionRestoration, on: monitor)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 1, url: sharedURL))
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 2, url: sharedURL))

        finishNavigation(tabIdentifier: "restored-1", url: sharedURL, on: monitor)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 2, url: sharedURL))
        await waitForEventTimeout(on: monitor)

        assertNoEpisode(on: monitor, pixelFiring: pixelFiring)
    }

    func testMappedResponseAfterReloadCannotCompleteNavigationStartedBeforeReload() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)
        let url = URL(string: "https://example.com/spanning-reload")!

        startAndCommitNavigation(tabIdentifier: "tab-1", url: url, navigationKind: .other, on: monitor)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 8, url: url))
        beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other)
        monitor.handle(.willReload(identifier: "embedded", type: .embedded, trigger: .explicit))
        monitor.handle(.reloaded(identifier: "embedded", type: .embedded, trigger: .explicit))

        monitor.handle(.dashboardResponse(extensionTabIdentifier: 8, url: url))
        monitor.handle(.navigationFinished(tabIdentifier: "tab-1", url: url, extensionIsLoaded: true))
        await waitForEventTimeout(on: monitor)

        XCTAssertTrue(pixelFiring.reports.isEmpty)
        XCTAssertEqual(pixelFiring.confirmedHangCount, 1)

        startAndCommitNavigation(tabIdentifier: "tab-1", url: url, navigationKind: .other, on: monitor)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 8, url: url))
        monitor.handle(.navigationFinished(tabIdentifier: "tab-1", url: url, extensionIsLoaded: true))

        assertReport(pixelFiring, reason: .other, wasStuck: false,
                     outcome: .failedTabResponse, reloadState: .responseTimedOut)
    }

    func testEarlierUnattributedResponseDoesNotCompleteLaterNavigation() async {
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
        await waitForEventTimeout(on: monitor)

        assertPendingEpisode(on: monitor, pixelFiring: pixelFiring, reason: .other,
                             wasStuck: false, reloadState: .none)
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
        await waitForEventTimeout(on: monitor)

        assertNoEpisode(on: monitor, pixelFiring: pixelFiring)
    }

    /// Closing one of two identically-committed tabs does not revive the abandoned measurement of
    /// the tab that remains.
    func testTabCloseDoesNotReviveAbandonedMeasurement() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)
        let sharedURL = URL(string: "https://example.com/shared")!

        finishNavigation(tabIdentifier: "tab-1", url: sharedURL, on: monitor)
        finishNavigation(tabIdentifier: "tab-2", url: sharedURL, on: monitor)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 1, url: sharedURL))
        monitor.handle(.tabClosed(tabIdentifier: "tab-2"))
        await waitForEventTimeout(on: monitor)

        assertNoEpisode(on: monitor, pixelFiring: pixelFiring)
    }

    func testNavigationFailureAfterCrashPreservesCrashAttributionForRetry() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)
        let failedURL = URL(string: "https://example.com/provisional")!

        monitor.handle(.webContentProcessTerminated(tabIdentifier: "tab-1"))
        startAndCommitNavigation(tabIdentifier: "tab-1", url: failedURL, navigationKind: .other, on: monitor)
        monitor.handle(.navigationFailed(tabIdentifier: "tab-1"))
        finishNavigation(tabIdentifier: "tab-1", path: "retry", on: monitor)
        await waitForEventTimeout(on: monitor)

        assertPendingEpisode(on: monitor, pixelFiring: pixelFiring, reason: .tabCrash,
                             wasStuck: false, reloadState: .none)
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
        await waitForEventTimeout(on: monitor)

        assertNoEpisode(on: monitor, pixelFiring: pixelFiring)
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

        assertReport(pixelFiring, reason: .other, wasStuck: false,
                     outcome: .failedMeasurementResponse, reloadState: .none)
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
        await waitForEventTimeout(on: monitor)

        assertPendingEpisode(on: monitor, pixelFiring: pixelFiring, reason: .other,
                             wasStuck: false, reloadState: .none)
    }

    // MARK: - Stuck scope

    func testRepeatedFailureInFirstTabConfirmsHangButIsNotStuck() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)
        monitor.onConfirmedHang = { pixelFiring.confirmedHangCount += 1 }

        XCTAssertFalse(beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other))
        XCTAssertTrue(beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other))

        XCTAssertEqual(pixelFiring.confirmedHangCount, 1)
        assertPendingEpisode(on: monitor, pixelFiring: pixelFiring, reason: .other,
                             wasStuck: false, reloadState: .none)
    }

    func testFailureInAnotherTabConfirmsHangAndIsStuck() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)
        monitor.onConfirmedHang = { pixelFiring.confirmedHangCount += 1 }

        XCTAssertFalse(beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other))
        XCTAssertTrue(beginAndReportFailure(on: monitor, tabIdentifier: "tab-2", navigationKind: .other))

        XCTAssertEqual(pixelFiring.confirmedHangCount, 1)
        assertPendingEpisode(on: monitor, pixelFiring: pixelFiring, reason: .other,
                             wasStuck: true, reloadState: .none)
    }

    func testAnotherTabAfterRepeatBecomesStuckWithoutASecondRecovery() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)
        monitor.onConfirmedHang = { pixelFiring.confirmedHangCount += 1 }

        XCTAssertFalse(beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other))
        XCTAssertTrue(beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other))
        XCTAssertFalse(beginAndReportFailure(on: monitor, tabIdentifier: "tab-2", navigationKind: .other))

        XCTAssertEqual(pixelFiring.confirmedHangCount, 1)
        assertPendingEpisode(on: monitor, pixelFiring: pixelFiring, reason: .other,
                             wasStuck: true, reloadState: .none)
    }

    func testRestorationFailuresNeverMakeAnEpisodeStuck() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)
        monitor.onConfirmedHang = { pixelFiring.confirmedHangCount += 1 }

        beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .sessionRestoration)
        beginAndReportFailure(on: monitor, tabIdentifier: "tab-2", navigationKind: .sessionRestoration)
        XCTAssertEqual(pixelFiring.confirmedHangCount, 0)

        // A regular navigation in the tab that opened the episode confirms the hang, not the extension.
        XCTAssertTrue(beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other))
        XCTAssertEqual(pixelFiring.confirmedHangCount, 1)

        beginAndReportFailure(on: monitor, tabIdentifier: "tab-3", navigationKind: .other)
        assertPendingEpisode(on: monitor, pixelFiring: pixelFiring, reason: .sessionRestoration,
                             wasStuck: true, reloadState: .none)
    }

    // MARK: - Interruptions

    func testInterruptionStopsPendingResponseWaitAndRestartsItOnResume() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeInterruptibleMonitor(pixelFiring: pixelFiring)

        finishNavigation(tabIdentifier: "tab-1", path: "interrupted", on: monitor)
        monitor.handle(.interruptionBegan)
        try? await Task.sleep(nanoseconds: 60_000_000)
        assertNoEpisode(on: monitor, pixelFiring: pixelFiring)

        monitor.handle(.interruptionEnded)
        await waitForEventTimeout(on: monitor)

        assertPendingEpisode(on: monitor, pixelFiring: pixelFiring, reason: .other,
                             wasStuck: false, reloadState: .none)
    }

    func testInterruptedWaitRestartsWithTheLongerGraceNotTheNormalOne() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring, episodeLifetime: 60,
                                                responseGracePeriod: 0.01, resumedResponseGracePeriod: 30, now: Date.init)

        finishNavigation(tabIdentifier: "tab-1", path: "long-grace", on: monitor)
        monitor.handle(.interruptionBegan)
        monitor.handle(.interruptionEnded)

        // The normal 10 ms grace would have reported by now; the restarted wait is 30 s.
        try? await Task.sleep(nanoseconds: 100_000_000)
        assertNoEpisode(on: monitor, pixelFiring: pixelFiring)
    }

    func testInterruptedExtensionLoadWaitRestartsAndStillOnlyCancels() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeInterruptibleMonitor(pixelFiring: pixelFiring)

        finishNavigation(tabIdentifier: "tab-1", path: "waiting-for-extension", extensionIsLoaded: false, on: monitor)
        monitor.handle(.interruptionBegan)
        monitor.handle(.interruptionEnded)
        await waitForEventTimeout(on: monitor)

        // The wait expired and cancelled the measurement, so the extension loading later reports nothing.
        monitor.handle(.extensionLifecycle(.loaded(identifier: "embedded", type: .embedded)))
        await waitForEventTimeout(on: monitor)
        assertNoEpisode(on: monitor, pixelFiring: pixelFiring)
    }

    func testExtensionLoadedWhileInterruptedStartsItsGraceOnResume() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeInterruptibleMonitor(pixelFiring: pixelFiring)

        finishNavigation(tabIdentifier: "tab-1", path: "loaded-while-interrupted", extensionIsLoaded: false, on: monitor)
        monitor.handle(.interruptionBegan)
        monitor.handle(.extensionLifecycle(.loaded(identifier: "embedded", type: .embedded)))
        try? await Task.sleep(nanoseconds: 60_000_000)
        assertNoEpisode(on: monitor, pixelFiring: pixelFiring)

        monitor.handle(.interruptionEnded)
        await waitForEventTimeout(on: monitor)

        assertPendingEpisode(on: monitor, pixelFiring: pixelFiring, reason: .other,
                             wasStuck: false, reloadState: .none)
    }

    func testTabClosedWhileInterruptedLeavesNothingToRestart() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeInterruptibleMonitor(pixelFiring: pixelFiring)

        finishNavigation(tabIdentifier: "tab-1", path: "closed-while-interrupted", on: monitor)
        monitor.handle(.interruptionBegan)
        monitor.handle(.tabClosed(tabIdentifier: "tab-1"))
        monitor.handle(.interruptionEnded)
        await waitForEventTimeout(on: monitor)
        try? await Task.sleep(nanoseconds: 60_000_000)

        assertNoEpisode(on: monitor, pixelFiring: pixelFiring)
    }

    func testResponseDuringInterruptionClosesEpisodeOnFrozenTime() {
        var currentDate = Date(timeIntervalSince1970: 0)
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring, episodeLifetime: 300, now: { currentDate })
        beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other)

        currentDate.addTimeInterval(10)
        monitor.handle(.interruptionBegan)
        currentDate.addTimeInterval(3600)
        monitor.reportSuccess(monitor.beginMeasurement(tabIdentifier: "tab-2", navigationKind: .other))

        assertReport(pixelFiring, reason: .other, wasStuck: false, outcome: .otherTabResponse, reloadState: .none)
        XCTAssertEqual(pixelFiring.metadata.last?.parameters["response_after"], "under_30s",
                       "The hour spent suspended must not count towards the response time")
    }

    func testRepeatedInterruptionStartKeepsTheFirstMoment() {
        var currentDate = Date(timeIntervalSince1970: 0)
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring, episodeLifetime: 60,
                                                minimumEpisodeRemainder: 30, now: { currentDate })
        beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other)

        currentDate.addTimeInterval(10)
        monitor.handle(.interruptionBegan)
        currentDate.addTimeInterval(10)
        monitor.handle(.interruptionBegan)
        currentDate.addTimeInterval(3600)
        monitor.handle(.interruptionEnded)

        // 10 s were observed before the first start; a second start must not move that moment to 20 s.
        currentDate.addTimeInterval(49)
        monitor.handle(.tabClosed(tabIdentifier: "unknown"))
        XCTAssertTrue(pixelFiring.reports.isEmpty)
        currentDate.addTimeInterval(2)
        monitor.handle(.tabClosed(tabIdentifier: "unknown"))
        XCTAssertEqual(pixelFiring.reports.count, 1)
    }

    func testInterruptionEndWithoutStartDoesNotExtendTheEpisode() {
        var currentDate = Date(timeIntervalSince1970: 0)
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring, episodeLifetime: 60,
                                                minimumEpisodeRemainder: 30, now: { currentDate })
        beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other)

        currentDate.addTimeInterval(3600)
        monitor.handle(.interruptionEnded)
        XCTAssertTrue(pixelFiring.reports.isEmpty, "An unmatched end is ignored, not treated as a resume")

        monitor.handle(.tabClosed(tabIdentifier: "unknown"))
        assertReport(pixelFiring, reason: .other, wasStuck: false,
                     outcome: .noResponseBeforeDeadline, reloadState: .none)
    }

    func testNavigationFinishedWhileInterruptedWaitsUntilResume() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeInterruptibleMonitor(pixelFiring: pixelFiring)

        monitor.handle(.interruptionBegan)
        finishNavigation(tabIdentifier: "tab-1", path: "while-interrupted", on: monitor)
        try? await Task.sleep(nanoseconds: 60_000_000)
        assertNoEpisode(on: monitor, pixelFiring: pixelFiring)

        monitor.handle(.interruptionEnded)
        await waitForEventTimeout(on: monitor)

        assertPendingEpisode(on: monitor, pixelFiring: pixelFiring, reason: .other,
                             wasStuck: false, reloadState: .none)
    }

    func testSuspendedTimeDoesNotConsumeEpisodeTime() {
        var currentDate = Date(timeIntervalSince1970: 0)
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring, episodeLifetime: 60,
                                                minimumEpisodeRemainder: 30, now: { currentDate })
        beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other)

        currentDate.addTimeInterval(10)
        monitor.handle(.interruptionBegan)
        currentDate.addTimeInterval(3600)
        monitor.handle(.interruptionEnded)

        currentDate.addTimeInterval(49)
        monitor.handle(.tabClosed(tabIdentifier: "unknown"))
        XCTAssertTrue(pixelFiring.reports.isEmpty, "59 s of observed time is inside the 60 s episode")

        currentDate.addTimeInterval(2)
        monitor.handle(.tabClosed(tabIdentifier: "unknown"))
        assertReport(pixelFiring, reason: .other, wasStuck: false,
                     outcome: .noResponseBeforeDeadline, reloadState: .none)
    }

    func testLateInterruptionStartDoesNotExpireTheEpisode() {
        var currentDate = Date(timeIntervalSince1970: 0)
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring, episodeLifetime: 60,
                                                minimumEpisodeRemainder: 30, now: { currentDate })
        beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other)

        // The system slept before this handler ran, so the wall clock has already jumped.
        currentDate.addTimeInterval(3600)
        monitor.handle(.interruptionBegan)
        monitor.handle(.interruptionEnded)

        XCTAssertTrue(pixelFiring.reports.isEmpty)
        currentDate.addTimeInterval(25)
        monitor.handle(.tabClosed(tabIdentifier: "unknown"))
        XCTAssertTrue(pixelFiring.reports.isEmpty, "The minimum after resume keeps the episode open")
    }

    func testLateResponseOnFailedMeasurementStillClosesAnExtendedEpisode() async {
        var currentDate = Date(timeIntervalSince1970: 0)
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring, episodeLifetime: 60, extensionLoadWait: 1,
                                                responseGracePeriod: 0.01, minimumEpisodeRemainder: 30,
                                                now: { currentDate })
        let url = URL(string: "https://example.com/late")!
        finishNavigation(tabIdentifier: "tab-1", url: url, on: monitor)
        await waitForEventTimeout(on: monitor)

        // 50 s observed, then a suspension: the episode now runs to 80 s, the measurement's own 60 s is over at 75 s.
        currentDate.addTimeInterval(50)
        monitor.handle(.interruptionBegan)
        currentDate.addTimeInterval(3600)
        monitor.handle(.interruptionEnded)
        currentDate.addTimeInterval(25)

        monitor.handle(.dashboardResponse(extensionTabIdentifier: 8, url: url))

        assertReport(pixelFiring, reason: .other, wasStuck: false,
                     outcome: .failedMeasurementResponse, reloadState: .none)
    }

    func testEpisodeKeepsMinimumTimeAfterResume() {
        var currentDate = Date(timeIntervalSince1970: 0)
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring, episodeLifetime: 60,
                                                minimumEpisodeRemainder: 30, now: { currentDate })
        beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other)

        currentDate.addTimeInterval(50)
        monitor.handle(.interruptionBegan)
        currentDate.addTimeInterval(3600)
        monitor.handle(.interruptionEnded)

        currentDate.addTimeInterval(25)
        monitor.handle(.tabClosed(tabIdentifier: "unknown"))
        XCTAssertTrue(pixelFiring.reports.isEmpty, "10 s would have remained; the 30 s minimum applies")

        currentDate.addTimeInterval(6)
        monitor.handle(.tabClosed(tabIdentifier: "unknown"))
        assertReport(pixelFiring, reason: .other, wasStuck: false,
                     outcome: .noResponseBeforeDeadline, reloadState: .none)
    }

    func testInterruptionStopsEpisodeDeadlineTaskUntilResume() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring, episodeLifetime: 0.02,
                                                minimumEpisodeRemainder: 0.02, now: Date.init)
        beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other)
        monitor.handle(.interruptionBegan)

        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertTrue(pixelFiring.reports.isEmpty)

        let reported = expectation(description: "Deadline reports after the interruption ends")
        pixelFiring.onReport = { reported.fulfill() }
        monitor.handle(.interruptionEnded)
        await fulfillment(of: [reported], timeout: 1)

        assertReport(pixelFiring, reason: .other, wasStuck: false,
                     outcome: .noResponseBeforeDeadline, reloadState: .none)
    }

    func testDeadlineReportsQuietEpisodeWithoutAnotherEvent() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let reported = expectation(description: "Episode deadline reports without another health event")
        pixelFiring.onReport = { reported.fulfill() }
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring, episodeLifetime: 0.02, now: Date.init)
        beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other)

        await fulfillment(of: [reported], timeout: 1)

        assertReport(pixelFiring, reason: .other, wasStuck: false,
                     outcome: .noResponseBeforeDeadline, reloadState: .none)
        XCTAssertNil(pixelFiring.metadata.last?.parameters["response_after"])
    }

    func testResponseCancelsDeadlineAndDoesNotSendASecondReport() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        // A fixed clock keeps `reportSuccess` from expiring the 20 ms episode on a stalled runner;
        // only the deadline task, which the response must cancel, uses real time.
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring, episodeLifetime: 0.02, now: { Date(timeIntervalSince1970: 0) })
        let measurement = monitor.beginMeasurement(tabIdentifier: "tab-1", navigationKind: .other)
        monitor.reportFailure(measurement)
        monitor.reportSuccess(measurement)

        try? await Task.sleep(nanoseconds: 50_000_000)

        assertReport(pixelFiring, reason: .other, wasStuck: false,
                     outcome: .failedMeasurementResponse, reloadState: .none)
    }

    func testReleasingMonitorLosesUnfinishedReportWithoutRetainingMonitor() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        var monitor: CPMMessagingHealthMonitor? = CPMMessagingHealthMonitor(pixelFiring: pixelFiring, episodeLifetime: 0.02, now: Date.init)
        weak var weakMonitor: CPMMessagingHealthMonitor?
        weakMonitor = monitor
        if let monitor {
            monitor.reportFailure(monitor.beginMeasurement(tabIdentifier: "tab-1", navigationKind: .other))
        }
        monitor = nil

        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNil(weakMonitor)
        XCTAssertTrue(pixelFiring.reports.isEmpty)
    }

    func testReloadLifecycleStateIsReportedOnlyWithTheTerminalSummary() {
        let states: [(WebExtensionLifecycleEvent, CPMMessagingEpisodeReport.ReloadState)] = [
            (.willReload(identifier: "embedded", type: .embedded, trigger: .explicit), .pending),
            (.reloadFailed(identifier: "embedded", type: .embedded, trigger: .explicit), .failed),
            (.reloaded(identifier: "embedded", type: .embedded, trigger: .explicit), .loaded)
        ]
        for (event, state) in states {
            let pixelFiring = CapturingWebExtensionPixelFiring()
            let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)
            beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other)
            monitor.handle(event)
            assertPendingEpisode(on: monitor, pixelFiring: pixelFiring, reason: .other,
                                 wasStuck: false, reloadState: state)
        }
    }

    func testSummaryUploadsOnlyAllowlistedFirstFailureFacts() {
        var diagnostics = CPMMessagingDiagnostics(
            extensionContextLoaded: true, secondsSinceCriticalMemoryPressure: 17, networkProcessRestarted: true,
            extensionContextErrors: ["private-error:123"], backgroundWebViewCreateCount: 12, backgroundWebViewAlive: true,
            leakedBackgroundWebViewCount: 11, backgroundWebProcessAlive: false, tabKnownToWebKit: false,
            nativeMessageHandlerRegistered: true, tabControllerMatchesContext: false, tabHasExtensionUserScripts: true,
            backgroundWebProcessResponsive: false,
            backgroundEvents: [.init(token: "view", secondsBeforeSnapshot: 42)]
        )
        diagnostics.secondsSinceAppLaunch = 123
        diagnostics.appVersionChange = .updated
        diagnostics.backgroundReadiness = .failed
        diagnostics.secondsSinceBackgroundViewCreation = 32
        diagnostics.hasBackgroundLoadError = true
        diagnostics.secondsFromBackgroundViewToLoadError = 30.4
        diagnostics.backgroundLoadErrorAppState = .background
        let report = CPMMessagingEpisodeReport(reason: .other, wasStuck: false, outcome: .failedMeasurementResponse,
                                               reloadState: .none, secondsToResponse: 12.345, diagnostics: diagnostics)
        XCTAssertEqual(report.pixelParameters, [
            "reason": "other", "was_stuck": "false", "outcome": "failed_measurement_response",
            "reload_state": "none", "response_after": "under_30s", "context_loaded": "true", "bg_view_alive": "true",
            "bg_process_alive": "false", "bg_process_responsive": "false", "tab_in_context": "false",
            "handler_registered": "true", "tab_controller_match": "false", "tab_has_ext_scripts": "true",
            "bg_events": "view@1m", "bg_ready_after": "failed", "bg_view_age": "30s_to_2m",
            "bg_load_error_after": "25s_to_35s", "bg_load_error_app_state": "background"
        ])
    }

    func testResponseDelayUsesOnlyCoarseBucketsAndIsAbsentAtDeadline() {
        for (seconds, bucket) in [(0.0, "under_30s"), (29.9, "under_30s"), (30, "30s_to_1m"),
                                  (59.9, "30s_to_1m"), (60, "1m_to_deadline"), (299, "1m_to_deadline")] {
            let report = CPMMessagingEpisodeReport(reason: .other, wasStuck: false, outcome: .otherTabResponse,
                                                   reloadState: .none, secondsToResponse: seconds, diagnostics: nil)
            XCTAssertEqual(report.pixelParameters["response_after"], bucket)
        }
        let report = CPMMessagingEpisodeReport(reason: .other, wasStuck: false, outcome: .noResponseBeforeDeadline,
                                               reloadState: .none, secondsToResponse: 300, diagnostics: nil)
        XCTAssertNil(report.pixelParameters["response_after"])
    }

    func testCPMPixelMetadataUsesDailyAndCountForOneEpisodeReport() throws {
        let report = CPMMessagingEpisodeReport(reason: .tabCrash, wasStuck: true, outcome: .failedTabResponse,
                                               reloadState: .loaded, secondsToResponse: 45, diagnostics: nil)
        let metadata = try XCTUnwrap(CPMWebExtensionPixelMetadata(event: .cpmMessagingEpisode(report)))
        XCTAssertEqual(metadata.name, "web_extension_cpm_episode")
        XCTAssertEqual(metadata.frequency, .dailyAndCount)
        XCTAssertEqual(metadata.parameters, [
            "reason": "tab_crash", "was_stuck": "true", "outcome": "failed_tab_response",
            "reload_state": "loaded", "response_after": "30s_to_1m"
        ])
    }

    func testRecoveryParametersDistinguishEpisodeStateWithAndWithoutReload() throws {
        for wasStuck in [false, true] {
            for didReload in [false, true] {
                let pixelFiring = CapturingWebExtensionPixelFiring()
                let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)
                beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other)
                if wasStuck {
                    beginAndReportFailure(on: monitor, tabIdentifier: "tab-2", navigationKind: .other)
                }
                if didReload {
                    monitor.handle(.reloaded(identifier: "embedded", type: .embedded, trigger: .dataClearing))
                }
                XCTAssertTrue(pixelFiring.reports.isEmpty)
                let measurement = monitor.beginMeasurement(tabIdentifier: "tab-1", navigationKind: .other)
                monitor.reportSuccess(measurement)
                assertReport(pixelFiring, reason: .other, wasStuck: wasStuck,
                             outcome: .failedTabResponse, reloadState: didReload ? .loaded : .none)
                monitor.reportSuccess(measurement)
                XCTAssertEqual(pixelFiring.reports.count, 1)
            }
        }
    }

    func testReloadErrorPixelMetadataIncludesDomainAndCode() {
        let metadata = WebExtensionReloadErrorPixelMetadata(
            type: .embedded,
            trigger: .dataClearing,
            phase: .lightweightLoad,
            error: NSError(
                domain: WKWebExtensionContext.errorDomain,
                code: WKWebExtensionContext.Error.Code.baseURLAlreadyInUse.rawValue
            )
        )

        XCTAssertEqual(WebExtensionReloadErrorPixelMetadata.name, "debug_web_extension_reload_failed")
        XCTAssertEqual(metadata.parameters, [
            "extension_type": "embedded",
            "reload_trigger": "data_clearing",
            "reload_phase": "light_load",
            "d": WKWebExtensionContext.errorDomain,
            "e": String(WKWebExtensionContext.Error.Code.baseURLAlreadyInUse.rawValue)
        ])
    }

    func testReloadErrorPixelPreservesUnknownDomainAndUnderlyingCodeWithoutUserInfo() {
        let underlying = NSError(domain: NSURLErrorDomain, code: -1009,
                                 userInfo: [NSLocalizedDescriptionKey: "https://private.example/path"])
        let error = NSError(domain: "CustomReloadError", code: 42,
                            userInfo: [NSUnderlyingErrorKey: underlying, NSFilePathErrorKey: "/Users/private/file"])
        let metadata = WebExtensionReloadErrorPixelMetadata(type: nil, trigger: .explicit, phase: .load, error: error)

        XCTAssertEqual(metadata.parameters, [
            "extension_type": "unknown",
            "reload_trigger": "explicit",
            "reload_phase": "load",
            "d": "CustomReloadError",
            "e": "42",
            "ud": NSURLErrorDomain,
            "ue": "-1009"
        ])
    }

    func testCPMDocumentMatchingIncludesQueryAndIgnoresFragment() {
        let pageURL = URL(string: "https://example.com/path?test=1#first")!

        XCTAssertTrue(pageURL.matchesCPMDiagnosticsDocument(URL(string: "https://example.com/path?test=1#second")!))
        XCTAssertFalse(pageURL.matchesCPMDiagnosticsDocument(URL(string: "https://example.com/path?test=2#first")!))
        XCTAssertFalse(pageURL.matchesCPMDiagnosticsDocument(URL(string: "http://example.com/path?test=1#first")!))
    }

    func testNonHypertextNavigationDoesNotReportFailure() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)

        finishNavigation(tabIdentifier: "tab-1", url: URL(string: "file:///tmp/page.html")!, on: monitor)
        await waitForEventTimeout(on: monitor)

        assertNoEpisode(on: monitor, pixelFiring: pixelFiring)
    }

    func testNonHypertextCommitCancelsPendingMeasurement() async {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = makeEventMonitor(pixelFiring: pixelFiring)

        finishNavigation(tabIdentifier: "tab-1", path: "first", on: monitor)
        monitor.handle(.navigationCommitted(tabIdentifier: "tab-1", url: URL(string: "file:///tmp/page.html")!))
        await waitForEventTimeout(on: monitor)

        assertNoEpisode(on: monitor, pixelFiring: pixelFiring)
    }

    func testNonHypertextDashboardResponseDoesNotRecoverFailureEpisode() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        beginAndReportFailure(on: monitor, tabIdentifier: "tab-1", navigationKind: .other)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: nil, url: URL(string: "file:///tmp/page.html")!))
        beginAndReportFailure(on: monitor, tabIdentifier: "tab-2", navigationKind: .other)

        assertPendingEpisode(on: monitor, pixelFiring: pixelFiring, reason: .other,
                             wasStuck: true, reloadState: .none)
    }

    func testCPMDashboardMatchingUsesHostAndNormalizedPathOnly() {
        let pageURL = URL(string: "https://example.com:8443?test=1#first")!

        XCTAssertTrue(pageURL.matchesCPMDashboardStatePage(URL(string: "http://example.com/?test=2#second")!))
        XCTAssertFalse(pageURL.matchesCPMDashboardStatePage(URL(string: "https://other.example.com/")!))
        XCTAssertFalse(pageURL.matchesCPMDashboardStatePage(URL(string: "https://example.com/path")!))
    }

    /// An empty sink alone cannot distinguish healthy state from a silently pending failure episode.
    private func assertNoEpisode(on monitor: CPMMessagingHealthMonitor, pixelFiring: CapturingWebExtensionPixelFiring,
                                 file: StaticString = #filePath, line: UInt = #line) {
        monitor.reportSuccess(monitor.beginMeasurement(tabIdentifier: "summary-check", navigationKind: .other))
        XCTAssertTrue(pixelFiring.reports.isEmpty, file: file, line: line)
    }

    /// Complete an otherwise pending episode using new, attributed response evidence.
    /// This also verifies that no intermediate failure/stuck/reload pixel was emitted.
    private func assertPendingEpisode(
        on monitor: CPMMessagingHealthMonitor,
        pixelFiring: CapturingWebExtensionPixelFiring,
        reason: CPMMessagingFailureReason,
        wasStuck: Bool,
        reloadState: CPMMessagingEpisodeReport.ReloadState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(pixelFiring.reports.isEmpty, file: file, line: line)
        monitor.reportSuccess(monitor.beginMeasurement(tabIdentifier: "summary-check", navigationKind: .other))
        assertReport(pixelFiring, reason: reason, wasStuck: wasStuck,
                     outcome: .otherTabResponse, reloadState: reloadState, file: file, line: line)
    }

    private func assertReport(
        _ pixelFiring: CapturingWebExtensionPixelFiring,
        reason: CPMMessagingFailureReason,
        wasStuck: Bool,
        outcome: CPMMessagingEpisodeReport.Outcome,
        reloadState: CPMMessagingEpisodeReport.ReloadState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(pixelFiring.reports.count, 1, file: file, line: line)
        XCTAssertEqual(pixelFiring.reports.last?.reason, reason, file: file, line: line)
        XCTAssertEqual(pixelFiring.reports.last?.wasStuck, wasStuck, file: file, line: line)
        XCTAssertEqual(pixelFiring.reports.last?.outcome, outcome, file: file, line: line)
        XCTAssertEqual(pixelFiring.reports.last?.reloadState, reloadState, file: file, line: line)
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

    /// Short real-time waits, so tests can run an interrupted wait to completion deterministically.
    private func makeInterruptibleMonitor(pixelFiring: CapturingWebExtensionPixelFiring) -> CPMMessagingHealthMonitor {
        CPMMessagingHealthMonitor(
            pixelFiring: pixelFiring,
            episodeLifetime: 60,
            extensionLoadWait: 0.01,
            responseGracePeriod: 0.01,
            resumedResponseGracePeriod: 0.02,
            now: Date.init
        )
    }

    private func makeEventMonitor(pixelFiring: CapturingWebExtensionPixelFiring) -> CPMMessagingHealthMonitor {
        let monitor = CPMMessagingHealthMonitor(
            pixelFiring: pixelFiring,
            episodeLifetime: 60,
            extensionLoadWait: 0.01,
            responseGracePeriod: 0.01,
            now: Date.init
        )
        monitor.onConfirmedHang = { pixelFiring.confirmedHangCount += 1 }
        return monitor
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

    /// Waits for the monitor's own scheduled timeouts instead of a fixed sleep, which raced slow CI runners.
    private func waitForEventTimeout(on monitor: CPMMessagingHealthMonitor) async {
        await monitor.waitForScheduledTimeouts()
    }
}

// MARK: - Diagnostics

@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMMessagingHealthMonitorDiagnosticsTests: XCTestCase {

    func testWithoutProviderSummaryFiresOnlyAtEpisodeCompletion() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)

        let measurement = monitor.beginMeasurement(tabIdentifier: "tab-1", navigationKind: .other)
        monitor.reportFailure(measurement)

        XCTAssertTrue(pixelFiring.reports.isEmpty)
        monitor.reportSuccess(measurement)
        XCTAssertEqual(pixelFiring.reports.count, 1)
        XCTAssertEqual(pixelFiring.diagnostics, [nil])
    }

    func testProviderDiagnosticsAreCapturedOnlyAtFirstFailure() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let provider = StubDiagnosticsProvider()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)
        monitor.diagnosticsProvider = provider

        monitor.reportFailure(monitor.beginMeasurement(tabIdentifier: "tab-1", navigationKind: .other))
        let didBecomeStuck = monitor.reportFailure(monitor.beginMeasurement(tabIdentifier: "tab-2", navigationKind: .other))

        XCTAssertTrue(didBecomeStuck)
        XCTAssertTrue(pixelFiring.reports.isEmpty)
        monitor.reportSuccess(monitor.beginMeasurement(tabIdentifier: "tab-1", navigationKind: .other))
        XCTAssertEqual(pixelFiring.diagnostics.compactMap { $0 }.count, 1)
        XCTAssertEqual(provider.requests.map(\.tabIdentifier), ["tab-1"])
        XCTAssertNil(pixelFiring.metadata.first?.parameters["bg_events"])
    }

    func testWhenContextChangesAfterFailureThenPixelKeepsFailureTimeDiagnostics() {
        let pixelFiring = CapturingWebExtensionPixelFiring()
        let provider = StubDiagnosticsProvider()
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)
        monitor.diagnosticsProvider = provider
        var initialDiagnostics = CPMMessagingDiagnostics(
            extensionContextLoaded: false, tabKnownToWebKit: false,
            backgroundEvents: [.init(token: "load", secondsBeforeSnapshot: 42),
                               .init(token: "view", secondsBeforeSnapshot: 2)]
        )
        initialDiagnostics.backgroundReadiness = .pending
        initialDiagnostics.secondsSinceBackgroundViewCreation = 5
        provider.diagnostics = initialDiagnostics

        monitor.reportFailure(monitor.beginMeasurement(tabIdentifier: "tab-1", navigationKind: .other))
        provider.diagnostics = CPMMessagingDiagnostics(
            extensionContextLoaded: true, tabKnownToWebKit: true,
            backgroundEvents: [.init(token: "error_background_failed_to_load:E:6", secondsBeforeSnapshot: 1)]
        )
        provider.diagnostics.backgroundReadiness = .failed
        provider.diagnostics.hasBackgroundLoadError = true
        provider.diagnostics.secondsFromBackgroundViewToLoadError = 30
        provider.diagnostics.backgroundLoadErrorAppState = .background
        monitor.reportFailure(monitor.beginMeasurement(tabIdentifier: "tab-2", navigationKind: .other))

        XCTAssertTrue(pixelFiring.reports.isEmpty)
        monitor.reportSuccess(monitor.beginMeasurement(tabIdentifier: "tab-1", navigationKind: .other))
        XCTAssertEqual(pixelFiring.diagnostics, [initialDiagnostics])
        XCTAssertEqual(pixelFiring.metadata.first?.parameters["bg_events"], "load@1m,view@30s")
        XCTAssertEqual(pixelFiring.metadata.first?.parameters["bg_ready_after"], "pending")
        XCTAssertEqual(pixelFiring.metadata.first?.parameters["bg_view_age"], "4s_to_8s")
        XCTAssertNil(pixelFiring.metadata.first?.parameters["bg_load_error_after"])
        XCTAssertNil(pixelFiring.metadata.first?.parameters["bg_load_error_app_state"])
        XCTAssertEqual(provider.requests.map(\.tabIdentifier), ["tab-1"])
    }
}

@available(macOS 15.4, iOS 18.4, *)
@MainActor
private final class StubDiagnosticsProvider: CPMMessagingDiagnosticsProviding {
    struct Request: Equatable {
        let tabIdentifier: String
    }

    private(set) var requests: [Request] = []
    var diagnostics = CPMMessagingDiagnostics(extensionContextLoaded: true, tabKnownToWebKit: true)

    func collectDiagnostics(tabIdentifier: String) -> CPMMessagingDiagnostics {
        requests.append(Request(tabIdentifier: tabIdentifier))
        return diagnostics
    }
}

@available(macOS 15.4, iOS 18.4, *)
private final class CapturingWebExtensionPixelFiring: WebExtensionPixelFiring {
    private(set) var metadata: [CPMWebExtensionPixelMetadata] = []
    private(set) var reports: [CPMMessagingEpisodeReport] = []
    var confirmedHangCount = 0
    var onReport: (() -> Void)?
    var diagnostics: [CPMMessagingDiagnostics?] { reports.map(\.diagnostics) }

    func fire(_ event: WebExtensionPixelEvent) {
        if let metadata = CPMWebExtensionPixelMetadata(event: event) {
            self.metadata.append(metadata)
        }
        if case .cpmMessagingEpisode(let report) = event {
            reports.append(report)
            onReport?()
        }
    }
}
