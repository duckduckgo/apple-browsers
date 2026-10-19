//
//  WebContentHealthPixelTests.swift
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
import UIKit
import WebKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class WebContentHealthPixelTests: XCTestCase {

    private var date = Date(timeIntervalSince1970: 1_000_000)

    func testWhenTerminationReloadEndsThenResultPixelFiresOnceWithOutcomeAndRecovery() throws {
        let pixelFiring = MockWebContentHealthPixelFiring()
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
        let pixelFiring = MockWebContentHealthPixelFiring()
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
        XCTAssertEqual(pixel.name, "web-content_unresponsive-2")
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
        let pixelFiring = MockWebContentHealthPixelFiring()
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

        XCTAssertEqual(pixelFiring.calls.map { $0.event.name }, ["web-content_unresponsive-2", "web-content_unresponsive-result"])
        XCTAssertEqual(pixelFiring.calls[1].event.parameters,
                       ["outcome": "recovered", "duration": "5-15", "attempts": "2", "app_state": "foreground", "left_tab": "false",
                        "surface": "other", "loading": "false", "desktop_mode": "false", "protections": "true", "web_extension": "false"])
        XCTAssertEqual(pixelFiring.calls.map { $0.frequency }, [.dailyAndCount, .dailyAndCount])
        XCTAssertFalse(monitor.isFrozen)
    }

    func testWhenWebKitReportsResponsiveButPageDoesNotAnswerThenFreezeStaysOpen() {
        let pixelFiring = MockWebContentHealthPixelFiring()
        let monitor = makeFreezeMonitor(pixelFiring: pixelFiring)
        var probeCompletion: ((Bool) -> Void)?

        monitor.didBecomeUnresponsive(makeContext())
        monitor.processDidBecomeResponsive { probeCompletion = $0 }
        probeCompletion?(false) // The script errored, so the page did not answer.

        XCTAssertTrue(monitor.isFrozen)
        XCTAssertEqual(pixelFiring.calls.map { $0.event.name }, ["web-content_unresponsive-2"])

        date += 3
        monitor.end(.closed)
        XCTAssertEqual(pixelFiring.calls.last?.event.parameters?["outcome"], "closed")
    }

    func testWhenPageAnswersProbeThenOutcomeIsRecovered() {
        let pixelFiring = MockWebContentHealthPixelFiring()
        let monitor = makeFreezeMonitor(pixelFiring: pixelFiring)

        monitor.didBecomeUnresponsive(makeContext())
        date += 4
        monitor.processDidBecomeResponsive { $0(true) }

        XCTAssertFalse(monitor.isFrozen)
        XCTAssertEqual(pixelFiring.calls.last?.event.parameters?["outcome"], "recovered")
        XCTAssertEqual(pixelFiring.calls.last?.event.parameters?["duration"], "2-5")
    }

    func testWhenProbeAnswersAfterFreezeEndedThenAnswerIsIgnored() {
        let pixelFiring = MockWebContentHealthPixelFiring()
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
                       ["web-content_unresponsive-2", "terminated", "web-content_unresponsive-2"])
    }

    func testWhenNotFrozenThenResponsiveReportIsIgnored() {
        let pixelFiring = MockWebContentHealthPixelFiring()
        let monitor = makeFreezeMonitor(pixelFiring: pixelFiring)
        var probed = false

        monitor.processDidBecomeResponsive { _ in probed = true }

        XCTAssertFalse(probed)
        XCTAssertTrue(pixelFiring.calls.isEmpty)
    }

    func testWhenAnAttemptPrecededTheReportThenDurationRunsFromTheAttempt() {
        let pixelFiring = MockWebContentHealthPixelFiring()
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
        let pixelFiring = MockWebContentHealthPixelFiring()
        let monitor = makeFreezeMonitor(pixelFiring: pixelFiring)

        monitor.didAttemptNavigation()
        date += 60
        monitor.didBecomeUnresponsive(makeContext())
        date += 1
        monitor.end(.recovered)

        XCTAssertEqual(pixelFiring.calls.last?.event.parameters?["duration"], "0-2")
    }

    func testWhenFireClearsAFrozenTabThenOutcomeIsFire() {
        let pixelFiring = MockWebContentHealthPixelFiring()
        let monitor = makeFreezeMonitor(pixelFiring: pixelFiring)

        monitor.didBecomeUnresponsive(makeContext())
        monitor.end(.fire)
        monitor.end(.closed) // The tab is torn down afterwards; nothing left to report.

        XCTAssertEqual(pixelFiring.calls.map { $0.event.parameters?["outcome"] ?? $0.event.name }, ["web-content_unresponsive-2", "fire"])
    }

    func testWhenPageRecoversRightAfterResponsiveReportThenUserDidNotLeave() {
        let pixelFiring = MockWebContentHealthPixelFiring()
        let monitor = makeFreezeMonitor(pixelFiring: pixelFiring)

        monitor.didBecomeUnresponsive(makeContext())
        date += 5
        monitor.processDidBecomeResponsive { $0(true) }

        XCTAssertEqual(pixelFiring.calls.last?.event.parameters?["left_tab"], "false")
    }

    func testWhenTabIsTornDownRightAfterResponsiveReportThenUserDidNotLeave() {
        let pixelFiring = MockWebContentHealthPixelFiring()
        let monitor = makeFreezeMonitor(pixelFiring: pixelFiring)

        monitor.didBecomeUnresponsive(makeContext())
        date += 5
        monitor.processDidBecomeResponsive { _ in } // Teardown: the page never answers.
        date += 0.5
        monitor.end(.closed)

        XCTAssertEqual(pixelFiring.calls.last?.event.parameters?["left_tab"], "false")
    }

    func testWhenUserLeavesAndComesBackToCloseTheTabThenLeftTabIsReported() {
        let pixelFiring = MockWebContentHealthPixelFiring()
        let monitor = makeFreezeMonitor(pixelFiring: pixelFiring)

        monitor.didBecomeUnresponsive(makeContext())
        date += 5
        monitor.processDidBecomeResponsive { _ in } // The app went to the background; the page never answers.
        date += 30
        monitor.end(.closed)

        XCTAssertEqual(pixelFiring.calls.last?.event.parameters?["left_tab"], "true")
    }

    func testWhenPageRecoversWhileUserIsAwayThenLeftTabIsReported() {
        let pixelFiring = MockWebContentHealthPixelFiring()
        let monitor = makeFreezeMonitor(pixelFiring: pixelFiring)
        var probeCompletion: ((Bool) -> Void)?

        monitor.didBecomeUnresponsive(makeContext())
        date += 5
        monitor.processDidBecomeResponsive { probeCompletion = $0 } // The app went to the background.
        date += 20
        probeCompletion?(true) // The loop ended while the user was away.

        XCTAssertEqual(pixelFiring.calls.last?.event.parameters?["outcome"], "recovered")
        XCTAssertEqual(pixelFiring.calls.last?.event.parameters?["left_tab"], "true")
    }

    func testWhenProcessTerminatesDuringFreezeThenOutcomeIsTerminated() {
        let pixelFiring = MockWebContentHealthPixelFiring()
        let monitor = makeFreezeMonitor(pixelFiring: pixelFiring, applicationState: .background)

        monitor.didBecomeUnresponsive(makeContext())
        monitor.end(.terminated)

        XCTAssertEqual(pixelFiring.calls.last?.event.parameters,
                       ["outcome": "terminated", "duration": "0-2", "attempts": "0", "app_state": "background", "left_tab": "false",
                        "surface": "other", "loading": "false", "desktop_mode": "false", "protections": "true", "web_extension": "false"])
    }

    func testWhenFrozenTabIsClosedThenOutcomeIsClosedAndRecordIsCleared() {
        let pixelFiring = MockWebContentHealthPixelFiring()
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
        let first = makeFreezeMonitor(pixelFiring: MockWebContentHealthPixelFiring(), store: store, notificationCenter: notificationCenter)
        let second = makeFreezeMonitor(pixelFiring: MockWebContentHealthPixelFiring(), store: store, notificationCenter: notificationCenter)

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
        let first = makeFreezeMonitor(pixelFiring: MockWebContentHealthPixelFiring(), store: store)
        let second = makeFreezeMonitor(pixelFiring: MockWebContentHealthPixelFiring(), store: store)

        first.didBecomeUnresponsive(makeContext())
        date += 1
        second.didBecomeUnresponsive(makeContext())
        first.end(.recovered)
        XCTAssertEqual(store.object(forKey: "web-content-freeze.start-date") as? Date, date)

        second.end(.recovered)
        XCTAssertNil(store.object(forKey: "web-content-freeze.start-date"))
    }

    func testWhenTelemetryIsDisabledThenFreezesAreNotReported() {
        let pixelFiring = MockWebContentHealthPixelFiring()
        let monitor = makeFreezeMonitor(featureEnabled: false, pixelFiring: pixelFiring)

        monitor.didBecomeUnresponsive(makeContext())
        monitor.didAttemptNavigation()
        monitor.end(.recovered)

        XCTAssertTrue(pixelFiring.calls.isEmpty)
        XCTAssertFalse(monitor.isFrozen)
    }

    func testWhenTelemetryIsDisabledDuringFreezeThenResultIsNotReportedAndStateIsCleared() {
        let pixelFiring = MockWebContentHealthPixelFiring()
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.webContentFreezeTelemetry])
        let store = MockKeyValueStore()
        let monitor = makeFreezeMonitor(featureFlagger: featureFlagger, pixelFiring: pixelFiring, store: store)

        monitor.didBecomeUnresponsive(makeContext())
        featureFlagger.enabledFeatureFlags = []
        monitor.end(.recovered)

        XCTAssertEqual(pixelFiring.calls.map { $0.event.name }, ["web-content_unresponsive-2"])
        XCTAssertFalse(monitor.isFrozen)
        XCTAssertNil(store.object(forKey: "web-content-freeze.start-date"))
    }

    func testWhenAppExitsInBackgroundDuringFreezeThenNextLaunchReportsItWithDurationUntilBackground() {
        let store = MockKeyValueStore()
        let notificationCenter = NotificationCenter()
        let monitor = makeFreezeMonitor(pixelFiring: MockWebContentHealthPixelFiring(), store: store, notificationCenter: notificationCenter)
        monitor.didBecomeUnresponsive(makeContext())
        monitor.didAttemptNavigation()
        date += 20
        notificationCenter.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        date += 100

        let launchPixelFiring = MockWebContentHealthPixelFiring()
        let report = { WebContentFreezeMonitor.reportFreezeEndedWithApp(record: .init(store: store),
                                                                        pixelFiring: launchPixelFiring,
                                                                        featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.webContentFreezeTelemetry])) }
        report()
        report() // Already reported.

        XCTAssertEqual(launchPixelFiring.calls.map { $0.event.name }, ["web-content_unresponsive-result"])
        XCTAssertEqual(launchPixelFiring.calls[0].event.parameters,
                       ["outcome": "app-ended", "duration": "15-30", "attempts": "1", "app_state": "background", "left_tab": "true",
                        "surface": "other", "loading": "false", "desktop_mode": "false", "protections": "true", "web_extension": "false"])
    }

    func testWhenAppExitsInForegroundDuringFreezeThenNextLaunchReportsUnknownDuration() {
        let store = MockKeyValueStore()
        let notificationCenter = NotificationCenter()
        let monitor = makeFreezeMonitor(pixelFiring: MockWebContentHealthPixelFiring(), store: store, notificationCenter: notificationCenter)
        monitor.didBecomeUnresponsive(makeContext())
        notificationCenter.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        notificationCenter.post(name: UIApplication.willEnterForegroundNotification, object: nil)

        let launchPixelFiring = MockWebContentHealthPixelFiring()
        WebContentFreezeMonitor.reportFreezeEndedWithApp(record: .init(store: store),
                                                         pixelFiring: launchPixelFiring,
                                                         featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.webContentFreezeTelemetry]))

        XCTAssertEqual(launchPixelFiring.calls.last?.event.parameters,
                       ["outcome": "app-ended", "duration": "unknown", "attempts": "0", "app_state": "foreground", "left_tab": "false",
                        "surface": "other", "loading": "false", "desktop_mode": "false", "protections": "true", "web_extension": "false"])
    }

    func testWhenHangIsReportedInBackgroundThenAppEndedDurationRunsFromTheReport() {
        let store = MockKeyValueStore()
        let monitor = makeFreezeMonitor(pixelFiring: MockWebContentHealthPixelFiring(), store: store, applicationState: .background)
        monitor.didBecomeUnresponsive(makeContext())
        date += 10

        let launchPixelFiring = MockWebContentHealthPixelFiring()
        WebContentFreezeMonitor.reportFreezeEndedWithApp(record: .init(store: store),
                                                         pixelFiring: launchPixelFiring,
                                                         featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.webContentFreezeTelemetry]))

        XCTAssertEqual(launchPixelFiring.calls.last?.event.parameters?["duration"], "0-2")
        XCTAssertEqual(launchPixelFiring.calls.last?.event.parameters?["app_state"], "background")
    }

    func testWhenNoFreezeWasInterruptedThenLaunchReportsNothing() {
        let pixelFiring = MockWebContentHealthPixelFiring()
        WebContentFreezeMonitor.reportFreezeEndedWithApp(record: .init(store: MockKeyValueStore()),
                                                         pixelFiring: pixelFiring,
                                                         featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.webContentFreezeTelemetry]))
        XCTAssertTrue(pixelFiring.calls.isEmpty)
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
                                   featureFlagger: MockFeatureFlagger? = nil,
                                   pixelFiring: MockWebContentHealthPixelFiring,
                                   store: KeyValueStoring = MockKeyValueStore(),
                                   applicationState: UIApplication.State = .active,
                                   notificationCenter: NotificationCenter = NotificationCenter()) -> WebContentFreezeMonitor {
        WebContentFreezeMonitor(pixelFiring: pixelFiring,
                                featureFlagger: featureFlagger ?? MockFeatureFlagger(enabledFeatureFlags: featureEnabled ? [.webContentFreezeTelemetry] : []),
                                record: .init(store: store),
                                applicationState: { applicationState },
                                notificationCenter: notificationCenter,
                                date: { self.date })
    }

    private func makeContext() -> WebContentHealthPixel.PageContext {
        .init(surface: .other, isLoading: false, isDesktopMode: false, isProtected: true, hasWebExtension: false)
    }

}

private final class MockWebContentHealthPixelFiring: PixelFiring {

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
