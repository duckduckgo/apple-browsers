//
//  TabTerminationTelemetryTests.swift
//  DuckDuckGoTests
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

import FeatureFlags_iOS
@_spi(Testing) import Persistence
import PixelKit
import PrivacyConfigTestsUtils
import UIKit
import WebKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class TabTerminationTelemetryTests: XCTestCase {

    private var date = Date(timeIntervalSince1970: 1_000_000)

    func testInteractionStateRestorationPixelNamesRemainBackwardCompatible() {
        XCTAssertEqual(TabTerminationTelemetryPixel.interactionStateFailedToRestore.name,
                       "m_d_tab-interaction-state_failed-to-restore")
        XCTAssertEqual(TabTerminationTelemetryPixel.interactionStateFailedToRestoreDaily.name,
                       "m_d_tab-interaction-state_failed-to-restore_daily")
    }

    func testWhenFeatureIsDisabledThenNoPixelsFire() {
        let pixelFiring = MockTabTerminationPixelFiring()
        let telemetry = makeTelemetry(featureEnabled: false, pixelFiring: pixelFiring)

        telemetry.didReceiveMemoryWarning(activeTabCount: 1)
        telemetry.webContentProcessDidTerminate(activeTabCount: 1)

        XCTAssertTrue(pixelFiring.calls.isEmpty)
    }

    func testWhenTerminationOccursInForegroundThenExpectedPixelsFire() {
        let pixelFiring = MockTabTerminationPixelFiring()
        let telemetry = makeTelemetry(pixelFiring: pixelFiring,
                                      applicationState: .active,
                                      memoryFootprint: 600 * 1_048_576)

        telemetry.webContentProcessDidTerminate(activeTabCount: 7)

        XCTAssertEqual(pixelFiring.call(named: "debug_webkit_termination_foreground")?.frequency, .dailyAndCount)
        XCTAssertEqual(pixelFiring.call(named: "debug_webkit_termination_occurrence_1")?.frequency, .daily)
        XCTAssertEqual(pixelFiring.call(named: "debug_webkit_termination_memory_512-1023")?.frequency, .dailyAndCount)
        XCTAssertEqual(pixelFiring.call(named: "debug_webkit_termination_active-tabs_6-10")?.frequency, .dailyAndCount)
        XCTAssertEqual(pixelFiring.calls.count, 4)
    }

    func testWhenTerminationOccursInBackgroundThenBackgroundPixelFires() {
        let pixelFiring = MockTabTerminationPixelFiring()
        let telemetry = makeTelemetry(pixelFiring: pixelFiring, applicationState: .background)

        telemetry.webContentProcessDidTerminate(activeTabCount: 1)

        XCTAssertNotNil(pixelFiring.call(named: "debug_webkit_termination_background"))
        XCTAssertNil(pixelFiring.call(named: "debug_webkit_termination_foreground"))
    }

    func testWhenTerminationsRepeatThenOccurrenceIsBucketedAndResetsDaily() {
        let pixelFiring = MockTabTerminationPixelFiring()
        let telemetry = makeTelemetry(pixelFiring: pixelFiring)

        for _ in 0..<6 {
            telemetry.webContentProcessDidTerminate(activeTabCount: 1)
        }

        XCTAssertEqual(pixelFiring.calls.filter { $0.event.name.hasPrefix("debug_webkit_termination_occurrence_") }.map(\.event.name), [
            "debug_webkit_termination_occurrence_1",
            "debug_webkit_termination_occurrence_2",
            "debug_webkit_termination_occurrence_3",
            "debug_webkit_termination_occurrence_4",
            "debug_webkit_termination_occurrence_5-plus",
            "debug_webkit_termination_occurrence_5-plus"
        ])

        date.addTimeInterval(86_400)
        telemetry.webContentProcessDidTerminate(activeTabCount: 1)

        XCTAssertEqual(pixelFiring.calls.last { $0.event.name.hasPrefix("debug_webkit_termination_occurrence_") }?.event.name,
                       "debug_webkit_termination_occurrence_1")
    }

    func testMemoryBuckets() {
        let megabyte: UInt64 = 1_048_576
        let cases: [(UInt64, String)] = [
            (511 * megabyte, "less-512"),
            (512 * megabyte, "512-1023"),
            (1024 * megabyte, "1024-2047"),
            (2048 * megabyte, "2048-4095"),
            (4096 * megabyte, "4096-8191"),
            (8192 * megabyte, "8192-16383"),
            (16384 * megabyte, "16384-plus")
        ]

        for (bytes, expectedName) in cases {
            XCTAssertEqual(TabTerminationTelemetryPixel.memory(.init(bytes: bytes)).name,
                           "debug_webkit_termination_memory_\(expectedName)")
        }
    }

    func testActiveTabBuckets() {
        let cases = [
            (1, "1"),
            (2, "2-5"),
            (6, "6-10"),
            (11, "11-20"),
            (21, "21-40"),
            (41, "41-60"),
            (61, "61-80"),
            (81, "81-plus")
        ]

        for (count, expectedName) in cases {
            XCTAssertEqual(TabTerminationTelemetryPixel.activeTabs(.init(count)).name,
                           "debug_webkit_termination_active-tabs_\(expectedName)")
        }
    }

    func testWhenMemoryFootprintIsUnavailableAndNoWarningOccurredThenOptionalPixelsDoNotFire() {
        let pixelFiring = MockTabTerminationPixelFiring()
        let telemetry = makeTelemetry(pixelFiring: pixelFiring, memoryFootprint: nil)

        telemetry.webContentProcessDidTerminate(activeTabCount: 1)

        XCTAssertFalse(pixelFiring.calls.contains { $0.event.name.hasPrefix("debug_webkit_termination_memory_") })
        XCTAssertFalse(pixelFiring.calls.contains { $0.event.name.hasPrefix("debug_webkit_termination_time-since-memory-warning_") })
    }

    func testWhenMemoryWarningOccurredThenElapsedTimePixelFires() {
        let pixelFiring = MockTabTerminationPixelFiring()
        let telemetry = makeTelemetry(pixelFiring: pixelFiring)
        telemetry.didReceiveMemoryWarning(activeTabCount: 1)
        date.addTimeInterval(6)

        telemetry.webContentProcessDidTerminate(activeTabCount: 1)

        XCTAssertEqual(pixelFiring.call(named: "debug_webkit_termination_time-since-memory-warning_10")?.frequency, .standard)
    }

    func testWhenMemoryWarningOccursThenActiveTabsAndRollingOccurrencePixelsFire() {
        let pixelFiring = MockTabTerminationPixelFiring()
        let telemetry = makeTelemetry(pixelFiring: pixelFiring, memoryWarningTelemetryWindow: 60)

        telemetry.didReceiveMemoryWarning(activeTabCount: 7)
        date.addTimeInterval(30)
        telemetry.didReceiveMemoryWarning(activeTabCount: 7)
        date.addTimeInterval(31)
        telemetry.didReceiveMemoryWarning(activeTabCount: 7)

        XCTAssertEqual(pixelFiring.calls.filter { $0.event.name.hasPrefix("debug_memory_warning_active-tabs_") }.map(\.event.name), [
            "debug_memory_warning_active-tabs_6-10",
            "debug_memory_warning_active-tabs_6-10",
            "debug_memory_warning_active-tabs_6-10"
        ])
        XCTAssertEqual(pixelFiring.calls.filter { $0.event.name.hasPrefix("debug_memory_warning_occurrence-in-window_") }.map(\.event.name), [
            "debug_memory_warning_occurrence-in-window_1",
            "debug_memory_warning_occurrence-in-window_2",
            "debug_memory_warning_occurrence-in-window_2"
        ])
        XCTAssertEqual(pixelFiring.call(named: "debug_memory_warning_active-tabs_6-10")?.frequency, .dailyAndCount)
        XCTAssertEqual(pixelFiring.call(named: "debug_memory_warning_occurrence-in-window_1")?.frequency, .standard)
    }

    func testTabEvictionSettingsReadRemoteValues() {
        let settings = makeSettings(json: "{\"memoryWarningTelemetryWindowSeconds\": 30, \"maxCapacityPhone\": 12, \"maxCapacityPad\": 8}")

        XCTAssertEqual(settings.memoryWarningTelemetryWindow, 30)
        XCTAssertEqual(settings.maximumCapacity(isPad: false), 12)
        XCTAssertEqual(settings.maximumCapacity(isPad: true), 8)
    }

    func testTabEvictionSettingsFallBackForInvalidValues() {
        let invalidSettings = [
            nil,
            "not json",
            "{}",
            "{\"memoryWarningTelemetryWindowSeconds\": 0, \"maxCapacityPhone\": -1, \"maxCapacityPad\": 2.5}",
            "{\"memoryWarningTelemetryWindowSeconds\": \"60\", \"maxCapacityPhone\": true, \"maxCapacityPad\": \"10\"}"
        ]

        for json in invalidSettings {
            let settings = makeSettings(json: json)
            XCTAssertEqual(settings.memoryWarningTelemetryWindow, 60)
            XCTAssertEqual(settings.maximumCapacity(isPad: false), 20)
            XCTAssertEqual(settings.maximumCapacity(isPad: true), 10)
        }
    }

    func testWhenTerminationReloadEndsThenResultPixelFiresOnceWithOutcomeAndRecovery() throws {
        let pixelFiring = MockTabTerminationPixelFiring()
        var tracker = TerminationReloadMonitor(pixelFiring: pixelFiring)

        tracker.didFinish()
        XCTAssertTrue(pixelFiring.calls.isEmpty, "Navigations without a termination reload are not reported")

        tracker.begin(.deferred)
        tracker.didFail(with: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
        tracker.didFail(with: NSError(domain: WKError.WebKitErrorDomain, code: WKError.Code.frameLoadInterruptedByPolicyChange.rawValue))
        XCTAssertTrue(pixelFiring.calls.isEmpty, "Cancellations keep waiting for the real result")

        tracker.didFinish()
        tracker.didFinish()

        let call = try XCTUnwrap(pixelFiring.call(named: "web-content_termination-reload-result"))
        XCTAssertEqual(call.event.parameters, ["outcome": "finished", "recovery": "deferred"])
        XCTAssertEqual(call.frequency, .dailyAndCount)
        XCTAssertEqual(pixelFiring.calls.count, 1)
    }

    func testWhenTerminationReloadFailsOrTerminatesThenOutcomeIsReported() {
        let pixelFiring = MockTabTerminationPixelFiring()
        var tracker = TerminationReloadMonitor(pixelFiring: pixelFiring)

        tracker.begin(.immediate)
        tracker.didFail(with: NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet))
        tracker.begin(.immediate)
        tracker.didTerminate()

        XCTAssertEqual(pixelFiring.calls.map { $0.event.parameters?["outcome"] }, ["failed", "terminated"])
        XCTAssertNil(tracker.pendingRecovery)
    }

    func testUnresponsivePixelNameAndParameters() {
        let context = WebContentHealthPixel.PageContext(surface: .search, isLoading: true, isDesktopMode: false, isProtected: true, hasWebExtension: false)
        let pixel = WebContentHealthPixel.unresponsive(context: context, appState: "foreground")
        XCTAssertEqual(pixel.name, "web-content_unresponsive")
        XCTAssertEqual(pixel.parameters, ["app_state": "foreground",
                                          "surface": "search",
                                          "loading": "true",
                                          "desktop_mode": "false",
                                          "protections": "true",
                                          "web_extension": "false"])
    }

    // MARK: - Web content freezes

    func testTabViewControllerRespondsToWebKitResponsivenessCallbacks() {
        XCTAssertTrue(TabViewController.instancesRespond(to: Selector(("_webViewWebProcessDidBecomeUnresponsive:"))))
        XCTAssertTrue(TabViewController.instancesRespond(to: Selector(("_webViewWebProcessDidBecomeResponsive:"))))
    }

    func testWhenFrozenPageRecoversThenDurationAndAttemptsAreReported() {
        let pixelFiring = MockTabTerminationPixelFiring()
        let monitor = makeFreezeMonitor(pixelFiring: pixelFiring)

        monitor.didAttemptNavigation() // Not frozen yet, so not counted.
        monitor.didBecomeUnresponsive(makeContext())
        monitor.didBecomeUnresponsive(makeContext()) // Same freeze.
        date += 1
        monitor.didAttemptNavigation()
        date += 6
        monitor.didAttemptNavigation()
        monitor.end(.recovered)
        monitor.end(.recovered) // Nothing left to end.

        XCTAssertEqual(pixelFiring.calls.map { $0.event.name }, ["web-content_unresponsive", "web-content_unresponsive-result"])
        XCTAssertEqual(pixelFiring.calls[1].event.parameters,
                       ["outcome": "recovered", "duration": "5-15", "attempts": "2", "app_state": "foreground",
                        "surface": "other", "loading": "false", "desktop_mode": "false", "protections": "true", "web_extension": "false"])
        XCTAssertEqual(pixelFiring.calls.map { $0.frequency }, [.dailyAndCount, .dailyAndCount])
        XCTAssertFalse(monitor.isFrozen)
    }

    func testWhenWebKitReportsResponsiveButPageDoesNotAnswerThenFreezeStaysOpen() {
        let pixelFiring = MockTabTerminationPixelFiring()
        let monitor = makeFreezeMonitor(pixelFiring: pixelFiring)
        var probeCompletion: ((Bool) -> Void)?

        monitor.didBecomeUnresponsive(makeContext())
        monitor.processDidBecomeResponsive { probeCompletion = $0 }
        probeCompletion?(false) // The script errored, so the page did not answer.

        XCTAssertTrue(monitor.isFrozen)
        XCTAssertEqual(pixelFiring.calls.map { $0.event.name }, ["web-content_unresponsive"])

        date += 3
        monitor.end(.closed)
        XCTAssertEqual(pixelFiring.calls.last?.event.parameters?["outcome"], "closed")
    }

    func testWhenPageAnswersProbeThenOutcomeIsRecovered() {
        let pixelFiring = MockTabTerminationPixelFiring()
        let monitor = makeFreezeMonitor(pixelFiring: pixelFiring)

        monitor.didBecomeUnresponsive(makeContext())
        date += 4
        monitor.processDidBecomeResponsive { $0(true) }

        XCTAssertFalse(monitor.isFrozen)
        XCTAssertEqual(pixelFiring.calls.last?.event.parameters?["outcome"], "recovered")
        XCTAssertEqual(pixelFiring.calls.last?.event.parameters?["duration"], "2-5")
    }

    func testWhenProbeAnswersAfterFreezeEndedThenAnswerIsIgnored() {
        let pixelFiring = MockTabTerminationPixelFiring()
        let monitor = makeFreezeMonitor(pixelFiring: pixelFiring)
        var probeCompletion: ((Bool) -> Void)?

        monitor.didBecomeUnresponsive(makeContext())
        monitor.processDidBecomeResponsive { probeCompletion = $0 }
        monitor.end(.terminated)
        date += 1
        monitor.didBecomeUnresponsive(makeContext()) // A new freeze.
        probeCompletion?(true) // Late answer for the old one.

        XCTAssertTrue(monitor.isFrozen)
        XCTAssertEqual(pixelFiring.calls.map { $0.event.parameters?["outcome"] ?? $0.event.name },
                       ["web-content_unresponsive", "terminated", "web-content_unresponsive"])
    }

    func testWhenNotFrozenThenResponsiveReportIsIgnored() {
        let pixelFiring = MockTabTerminationPixelFiring()
        let monitor = makeFreezeMonitor(pixelFiring: pixelFiring)
        var probed = false

        monitor.processDidBecomeResponsive { _ in probed = true }

        XCTAssertFalse(probed)
        XCTAssertTrue(pixelFiring.calls.isEmpty)
    }

    func testWhenAnAttemptPrecededTheReportThenDurationRunsFromTheAttempt() {
        let pixelFiring = MockTabTerminationPixelFiring()
        let monitor = makeFreezeMonitor(pixelFiring: pixelFiring)

        monitor.didAttemptNavigation() // The reload WebKit is about to time out on.
        date += 3
        monitor.didBecomeUnresponsive(makeContext())
        date += 1
        monitor.end(.recovered)

        XCTAssertEqual(pixelFiring.calls.last?.event.parameters?["duration"], "2-5")
        XCTAssertEqual(pixelFiring.calls.last?.event.parameters?["attempts"], "0")
    }

    func testWhenNoRecentAttemptPrecededTheReportThenDurationRunsFromTheReport() {
        let pixelFiring = MockTabTerminationPixelFiring()
        let monitor = makeFreezeMonitor(pixelFiring: pixelFiring)

        monitor.didAttemptNavigation()
        date += 60
        monitor.didBecomeUnresponsive(makeContext())
        date += 1
        monitor.end(.recovered)

        XCTAssertEqual(pixelFiring.calls.last?.event.parameters?["duration"], "0-2")
    }

    func testWhenProcessTerminatesDuringFreezeThenOutcomeIsTerminated() {
        let pixelFiring = MockTabTerminationPixelFiring()
        let monitor = makeFreezeMonitor(pixelFiring: pixelFiring, applicationState: .background)

        monitor.didBecomeUnresponsive(makeContext())
        monitor.end(.terminated)

        XCTAssertEqual(pixelFiring.calls.last?.event.parameters,
                       ["outcome": "terminated", "duration": "0-2", "attempts": "0", "app_state": "background",
                        "surface": "other", "loading": "false", "desktop_mode": "false", "protections": "true", "web_extension": "false"])
    }

    func testWhenFrozenTabIsClosedThenOutcomeIsClosedAndRecordIsCleared() {
        let pixelFiring = MockTabTerminationPixelFiring()
        let store = MockKeyValueStore()
        let monitor = makeFreezeMonitor(pixelFiring: pixelFiring, store: store)

        monitor.didBecomeUnresponsive(makeContext())
        XCTAssertNotNil(store.object(forKey: "web-content-freeze.start-date"))
        date += 3
        monitor.end(.closed)

        XCTAssertEqual(pixelFiring.calls.last?.event.parameters?["outcome"], "closed")
        XCTAssertEqual(pixelFiring.calls.last?.event.parameters?["duration"], "2-5")
        XCTAssertNil(store.object(forKey: "web-content-freeze.start-date"))
    }

    func testWhenAnotherTabFreezesThenTheFirstNoLongerWritesTheRecord() {
        let store = MockKeyValueStore()
        let notificationCenter = NotificationCenter()
        let first = makeFreezeMonitor(pixelFiring: MockTabTerminationPixelFiring(), store: store, notificationCenter: notificationCenter)
        let second = makeFreezeMonitor(pixelFiring: MockTabTerminationPixelFiring(), store: store, notificationCenter: notificationCenter)

        first.didBecomeUnresponsive(makeContext())
        date += 1
        second.didBecomeUnresponsive(makeContext())
        first.didAttemptNavigation()
        XCTAssertEqual(store.object(forKey: "web-content-freeze.attempts") as? Int, 0)

        second.end(.recovered) // Clears the record; the first tab must not bring it back.
        notificationCenter.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertNil(store.object(forKey: "web-content-freeze.background-date"))
    }

    func testWhenAnotherTabFreezesThenEndingTheFirstKeepsItsRecord() {
        let store = MockKeyValueStore()
        let first = makeFreezeMonitor(pixelFiring: MockTabTerminationPixelFiring(), store: store)
        let second = makeFreezeMonitor(pixelFiring: MockTabTerminationPixelFiring(), store: store)

        first.didBecomeUnresponsive(makeContext())
        date += 1
        second.didBecomeUnresponsive(makeContext())
        first.end(.recovered)
        XCTAssertEqual(store.object(forKey: "web-content-freeze.start-date") as? Date, date)

        second.end(.recovered)
        XCTAssertNil(store.object(forKey: "web-content-freeze.start-date"))
    }

    func testWhenTelemetryIsDisabledThenFreezesAreNotReported() {
        let pixelFiring = MockTabTerminationPixelFiring()
        let monitor = makeFreezeMonitor(featureEnabled: false, pixelFiring: pixelFiring)

        monitor.didBecomeUnresponsive(makeContext())
        monitor.didAttemptNavigation()
        monitor.previewSnapshotTimedOut(result: .retryTimeout)
        monitor.end(.recovered)

        XCTAssertTrue(pixelFiring.calls.isEmpty)
        XCTAssertFalse(monitor.isFrozen)
    }

    func testWhenAppExitsInBackgroundDuringFreezeThenNextLaunchReportsItWithDurationUntilBackground() {
        let store = MockKeyValueStore()
        let notificationCenter = NotificationCenter()
        let monitor = makeFreezeMonitor(pixelFiring: MockTabTerminationPixelFiring(), store: store, notificationCenter: notificationCenter)
        monitor.didBecomeUnresponsive(makeContext())
        monitor.didAttemptNavigation()
        date += 20
        notificationCenter.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        date += 100

        let launchPixelFiring = MockTabTerminationPixelFiring()
        let report = { WebContentFreezeMonitor.reportFreezeEndedWithApp(record: .init(store: store),
                                                                        pixelFiring: launchPixelFiring,
                                                                        featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.tabTerminationTelemetry])) }
        report()
        report() // Already reported.

        XCTAssertEqual(launchPixelFiring.calls.map { $0.event.name }, ["web-content_unresponsive-result"])
        XCTAssertEqual(launchPixelFiring.calls[0].event.parameters,
                       ["outcome": "app-ended", "duration": "15-30", "attempts": "1", "app_state": "background",
                        "surface": "other", "loading": "false", "desktop_mode": "false", "protections": "true", "web_extension": "false"])
    }

    func testWhenAppExitsInForegroundDuringFreezeThenNextLaunchReportsUnknownDuration() {
        let store = MockKeyValueStore()
        let notificationCenter = NotificationCenter()
        let monitor = makeFreezeMonitor(pixelFiring: MockTabTerminationPixelFiring(), store: store, notificationCenter: notificationCenter)
        monitor.didBecomeUnresponsive(makeContext())
        notificationCenter.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        notificationCenter.post(name: UIApplication.willEnterForegroundNotification, object: nil)

        let launchPixelFiring = MockTabTerminationPixelFiring()
        WebContentFreezeMonitor.reportFreezeEndedWithApp(record: .init(store: store),
                                                         pixelFiring: launchPixelFiring,
                                                         featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.tabTerminationTelemetry]))

        XCTAssertEqual(launchPixelFiring.calls.last?.event.parameters,
                       ["outcome": "app-ended", "duration": "unknown", "attempts": "0", "app_state": "foreground",
                        "surface": "other", "loading": "false", "desktop_mode": "false", "protections": "true", "web_extension": "false"])
    }

    func testWhenHangIsReportedInBackgroundThenAppEndedDurationRunsFromTheReport() {
        let store = MockKeyValueStore()
        let monitor = makeFreezeMonitor(pixelFiring: MockTabTerminationPixelFiring(), store: store, applicationState: .background)
        monitor.didBecomeUnresponsive(makeContext())
        date += 10

        let launchPixelFiring = MockTabTerminationPixelFiring()
        WebContentFreezeMonitor.reportFreezeEndedWithApp(record: .init(store: store),
                                                         pixelFiring: launchPixelFiring,
                                                         featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.tabTerminationTelemetry]))

        XCTAssertEqual(launchPixelFiring.calls.last?.event.parameters?["duration"], "0-2")
        XCTAssertEqual(launchPixelFiring.calls.last?.event.parameters?["app_state"], "background")
    }

    func testWhenNoFreezeWasInterruptedThenLaunchReportsNothing() {
        let pixelFiring = MockTabTerminationPixelFiring()
        WebContentFreezeMonitor.reportFreezeEndedWithApp(record: .init(store: MockKeyValueStore()),
                                                         pixelFiring: pixelFiring,
                                                         featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.tabTerminationTelemetry]))
        XCTAssertTrue(pixelFiring.calls.isEmpty)
    }

    func testWhenPreviewSnapshotTimesOutThenRetryResultAndFreezeStateAreReported() {
        let pixelFiring = MockTabTerminationPixelFiring()
        let monitor = makeFreezeMonitor(pixelFiring: pixelFiring)

        monitor.previewSnapshotTimedOut(result: .retryTimeout)
        monitor.didBecomeUnresponsive(makeContext())
        monitor.previewSnapshotTimedOut(result: .retryImage)

        let calls = pixelFiring.calls.filter { $0.event.name == "web-content_preview-snapshot-timeout" }
        XCTAssertEqual(calls.map { $0.event.parameters },
                       [["result": "retry-timeout", "unresponsive": "false", "app_state": "foreground"],
                        ["result": "retry-image", "unresponsive": "true", "app_state": "foreground"]])
        XCTAssertEqual(calls.map { $0.frequency }, [.dailyAndCount, .dailyAndCount])
    }

    func testWhenAppIsNotActiveThenSnapshotTimeoutIsNotReported() {
        let pixelFiring = MockTabTerminationPixelFiring()
        let monitor = makeFreezeMonitor(pixelFiring: pixelFiring, applicationState: .background)

        monitor.previewSnapshotTimedOut(result: .retryImage)

        XCTAssertTrue(pixelFiring.calls.isEmpty)
    }

    func testOnlyRetryResultsCountAsSnapshotTimeouts() {
        XCTAssertEqual([WebContentHealthPixel.SnapshotResult.skipped, .success, .retryImage, .retryNoImage, .retryTimeout].map(\.isTimeout),
                       [false, false, true, true, true])
    }

    func testFreezeDurationBuckets() {
        let buckets = [0, 1.9, 2, 4.9, 5, 14.9, 15, 29.9, 30, 59.9, 60, 3600].map { WebContentFreezeMonitor.DurationBucket(seconds: $0).rawValue }
        XCTAssertEqual(buckets, ["0-2", "0-2", "2-5", "2-5", "5-15", "5-15", "15-30", "15-30", "30-60", "30-60", "60-plus", "60-plus"])
    }

    func testFreezeAttemptsBuckets() {
        let buckets = [0, 1, 2, 3, 5, 6, 40].map { WebContentFreezeMonitor.AttemptsBucket($0).rawValue }
        XCTAssertEqual(buckets, ["0", "1", "2", "3-5", "3-5", "6-plus", "6-plus"])
    }

    func testSurfaceIsDerivedFromURL() {
        XCTAssertEqual(WebContentHealthPixel.Surface(url: URL(string: "https://duckduckgo.com/?q=test")), .search)
        XCTAssertEqual(WebContentHealthPixel.Surface(url: URL(string: "https://duckduckgo.com/?q=test&ia=chat&duckai=1")), .duckai)
        XCTAssertEqual(WebContentHealthPixel.Surface(url: URL(string: "https://duck.ai/")), .duckai)
        XCTAssertEqual(WebContentHealthPixel.Surface(url: URL(string: "https://example.com/")), .other)
        XCTAssertEqual(WebContentHealthPixel.Surface(url: nil), .other)
    }

    private func makeFreezeMonitor(featureEnabled: Bool = true,
                                   pixelFiring: MockTabTerminationPixelFiring,
                                   store: KeyValueStoring = MockKeyValueStore(),
                                   applicationState: UIApplication.State = .active,
                                   notificationCenter: NotificationCenter = NotificationCenter()) -> WebContentFreezeMonitor {
        WebContentFreezeMonitor(pixelFiring: pixelFiring,
                                featureFlagger: MockFeatureFlagger(enabledFeatureFlags: featureEnabled ? [.tabTerminationTelemetry] : []),
                                record: .init(store: store),
                                applicationState: { applicationState },
                                notificationCenter: notificationCenter,
                                date: { self.date })
    }

    private func makeContext() -> WebContentHealthPixel.PageContext {
        .init(surface: .other, isLoading: false, isDesktopMode: false, isProtected: true, hasWebExtension: false)
    }

    private func makeTelemetry(featureEnabled: Bool = true,
                               pixelFiring: MockTabTerminationPixelFiring,
                               applicationState: UIApplication.State = .active,
                               memoryFootprint: UInt64? = 100 * 1_048_576,
                               memoryWarningTelemetryWindow: TimeInterval = 60) -> DefaultTabTerminationTelemetry {
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: featureEnabled ? [.tabTerminationTelemetry] : [])
        return DefaultTabTerminationTelemetry(
            featureFlagger: featureFlagger,
            keyValueStore: MockKeyValueStore(),
            pixelFiring: pixelFiring,
            applicationState: { applicationState },
            memoryFootprint: { memoryFootprint },
            memoryWarningTelemetryWindow: { memoryWarningTelemetryWindow },
            date: { self.date })
    }

    private func makeSettings(json: String?) -> TabEvictionSettings {
        let config = MockPrivacyConfiguration()
        config.subfeatureSettings = json
        let manager = MockPrivacyConfigurationManager()
        manager.privacyConfig = config
        return TabEvictionSettings(privacyConfigurationManager: manager)
    }
}

private final class MockTabTerminationPixelFiring: PixelFiring {

    struct Call {
        let event: PixelKit.Event
        let frequency: PixelKit.Frequency
    }

    private(set) var calls: [Call] = []

    func fire(event: PixelKit.Event,
              frequency: PixelKit.Frequency,
              options: PixelKit.Options,
              onComplete: @escaping PixelKit.CompletionBlock) {
        calls.append(.init(event: event, frequency: frequency))
        onComplete(true, nil)
    }

    func call(named name: String) -> Call? {
        calls.first { $0.event.name == name }
    }
}
