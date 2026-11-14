//
//  RulesCompilationMonitorTests.swift
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

import Foundation
import Core
import BrowserServicesKit
import Combine
import FeatureFlags_iOS
import WebExtensions
import WebKit
@_spi(Testing) import PixelKit
import UIKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class RulesCompilationMonitorTests: XCTestCase {

    private var time: TimeInterval = 0
    private let pixelFiring = PixelKitMock()
    private let notifications = NotificationCenter()

    private func makeMonitor(isOnboarding: Bool = true) -> RulesCompilationMonitor {
        RulesCompilationMonitor(pixelFiring: pixelFiring, isOnboarding: isOnboarding,
                                now: { [unowned self] in self.time }, notificationCenter: notifications, isInBackground: { false })
    }

    func testFullIntervalIncludesExtensionWaitEvenWhenRulesAreAlreadyInstalled() throws {
        let monitor = makeMonitor()
        let id = try XCTUnwrap(monitor.begin())
        monitor.beginStage(.webExtensions, for: id)
        time = 0.8
        monitor.endStage(for: id)
        // Rules prepared concurrently during extension startup, so there is no second wait.
        monitor.finish(id, outcome: .success)

        assertPixel(outcome: "success", total: "1", extensions: "1", rules: "0")
    }

    func testBothSequentialWaitsAreIncludedWithoutAddingParallelPreparation() throws {
        let monitor = makeMonitor(isOnboarding: false)
        let id = try XCTUnwrap(monitor.begin())
        monitor.beginStage(.webExtensions, for: id)
        time = 0.4
        monitor.endStage(for: id)
        monitor.beginStage(.contentBlocking, for: id)
        time = 0.8
        monitor.endStage(for: id)
        monitor.finish(id, outcome: .success)

        assertPixel(outcome: "success", total: "1", extensions: "0.5", rules: "0.5", appState: "regular")
    }

    func testStageTimesAreBucketedWithoutSendingExactDurations() throws {
        let cases: [(seconds: Double, bucket: String)] = [(0.05, "0.1"), (0.5, "0.5"), (1, "1"), (4.9, "5"),
                                                          (9, "10"), (19, "20"), (39, "40"), (41, "more")]
        for testCase in cases {
            let firing = PixelKitMock()
            time = 0
            let monitor = RulesCompilationMonitor(pixelFiring: firing, isOnboarding: false,
                                                   now: { [unowned self] in self.time }, notificationCenter: notifications, isInBackground: { false })
            let id = try XCTUnwrap(monitor.begin())
            monitor.beginStage(.webExtensions, for: id)
            time = testCase.seconds
            monitor.endStage(for: id)
            monitor.finish(id, outcome: .success)

            assertSetupPixel(firing, outcome: "success", state: "regular",
                             total: testCase.bucket, extensions: testCase.bucket, rules: "0")
        }
    }

    func testRulesOnlyWaitAndRetriesUseTheSameSample() throws {
        let monitor = makeMonitor()
        let id = try XCTUnwrap(monitor.begin())
        monitor.beginStage(.contentBlocking, for: id)
        time = 0.3
        monitor.endStage(for: id)
        monitor.beginStage(.contentBlocking, for: id)
        time = 0.6
        monitor.endStage(for: id)
        monitor.finish(id, outcome: .success)

        assertPixel(outcome: "success", total: "1", extensions: "0", rules: "1")
    }

    func testAlreadyReadyChecksReportZeroAndOnlyFirstNavigationIsReported() throws {
        let monitor = makeMonitor()
        let id = try XCTUnwrap(monitor.begin())
        time = 0.01
        monitor.finish(id, outcome: .success)
        monitor.finish(id, outcome: .success)
        XCTAssertNil(monitor.begin())

        assertPixel(outcome: "success", total: "0", extensions: "0", rules: "0")
    }

    func testOtherTabsAndStaleCallbacksCannotFinishOrOverwriteSample() throws {
        let monitor = makeMonitor()
        let id = try XCTUnwrap(monitor.begin())
        monitor.beginStage(.webExtensions, for: id)
        XCTAssertNil(monitor.begin())
        time = 0.2
        monitor.beginStage(.contentBlocking, for: UUID())
        monitor.endStage(for: nil)
        monitor.finish(UUID(), outcome: .cancelled)
        monitor.finish(nil, outcome: .success)
        XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty)
        monitor.finish(id, outcome: .success)

        assertPixel(outcome: "success", total: "0.5", extensions: "0.5", rules: "0")
    }

    func testExtensionDeadlineIsCountedAsWaitWithoutClaimingSuccessfulPageLoad() throws {
        let monitor = makeMonitor()
        let id = try XCTUnwrap(monitor.begin())
        monitor.beginStage(.webExtensions, for: id)
        time = 5
        monitor.endStage(for: id)
        monitor.finish(id, outcome: .success)

        assertPixel(outcome: "success", total: "5", extensions: "5", rules: "0")
    }

    func testContentBlockingTimeoutReportsPartialWaitInsteadOfRelease() throws {
        let monitor = makeMonitor()
        let id = try XCTUnwrap(monitor.begin())
        monitor.beginStage(.contentBlocking, for: id)
        time = 15
        monitor.finish(id, outcome: .timeout)
        monitor.finish(id, outcome: .cancelled)

        assertPixel(outcome: "timeout", total: "20", extensions: "0", rules: "20")
    }

    func testCancellationAndTabCloseEndPendingStageExactlyOnce() throws {
        for outcome in [RulesCompilationMonitor.Outcome.cancelled, .tabClosed] {
            let firing = PixelKitMock()
            let monitor = RulesCompilationMonitor(pixelFiring: firing, isOnboarding: false,
                                                  now: { [unowned self] in self.time }, notificationCenter: notifications, isInBackground: { false })
            time = 0
            let id = try XCTUnwrap(monitor.begin())
            monitor.beginStage(.webExtensions, for: id)
            time = 0.2
            monitor.finish(id, outcome: outcome)
            time = 30
            monitor.endStage(for: id)
            monitor.finish(id, outcome: .success)

            assertSetupPixel(firing, outcome: outcome.rawValue, state: "regular", total: "0.5", extensions: "0.5", rules: "0")
        }
    }

    func testBackgroundStopsSampleBeforeSuspensionAndLateCompletionCannotIncludeBackgroundTime() throws {
        let monitor = makeMonitor()
        let id = try XCTUnwrap(monitor.begin())
        monitor.beginStage(.contentBlocking, for: id)
        time = 0.4
        notifications.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        assertPixel(outcome: "app_backgrounded", total: "0.5", extensions: "0", rules: "0.5")
        time = 100
        notifications.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        monitor.endStage(for: id)
        monitor.finish(id, outcome: .success)
        XCTAssertNil(monitor.begin())
        XCTAssertEqual(pixelFiring.actualFireCalls.count, 1)
        XCTAssertEqual(pixelFiring.actualFireCalls.first?.pixel.parameters?["wait_time"], "0.5")
    }

    func testBackgroundNavigationDoesNotConsumeFirstForegroundSample() throws {
        var backgrounded = true
        let monitor = RulesCompilationMonitor(pixelFiring: pixelFiring, isOnboarding: true,
                                               now: { [unowned self] in self.time }, notificationCenter: notifications,
                                               isInBackground: { backgrounded })
        XCTAssertNil(monitor.begin())
        backgrounded = false
        let id = try XCTUnwrap(monitor.begin())
        monitor.finish(id, outcome: .success)

        assertPixel(outcome: "success", total: "0", extensions: "0", rules: "0")
    }

    func testTerminationReportsUnfinishedWaitAndDoesNotReportWithoutNavigation() throws {
        let monitor = makeMonitor()
        notifications.post(name: UIApplication.willTerminateNotification, object: nil)
        XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty)
        let id = try XCTUnwrap(monitor.begin())
        monitor.beginStage(.webExtensions, for: id)
        time = 2
        notifications.post(name: UIApplication.willTerminateNotification, object: nil)
        monitor.finish(id, outcome: .success)

        assertPixel(outcome: "app_quit", total: "5", extensions: "5", rules: "0")
    }

    private func assertPixel(outcome: String, total: String, extensions: String, rules: String, appState: String = "onboarding",
                             file: StaticString = #filePath, line: UInt = #line) {
        assertSetupPixel(pixelFiring, outcome: outcome, state: appState, total: total, extensions: extensions, rules: rules,
                         file: file, line: line)
    }
}

/// Asserts the single setup-wait pixel was fired once with these bucketed values and no extra parameters.
private func assertSetupPixel(_ firing: PixelKitMock, outcome: String, state: String, total: String, extensions: String, rules: String,
                              file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(firing.actualFireCalls.count, 1, file: file, line: line)
    let call = firing.actualFireCalls.first
    XCTAssertEqual(call?.pixel.name, "navigation_setup_wait", file: file, line: line)
    XCTAssertEqual(call?.frequency, .standard, file: file, line: line)
    XCTAssertEqual(call?.pixel.parameters,
                   ["outcome": outcome, "state": state, "wait_time": total,
                    "web_extensions_wait_time": extensions, "content_blocking_wait_time": rules], file: file, line: line)
    XCTAssertNil(call?.additionalParameters, file: file, line: line)
    XCTAssertEqual(call?.includeAppVersionParameter, true, file: file, line: line)
}

@available(iOS 18.4, *)
@MainActor
final class RulesCompilationPolicyTests: XCTestCase {

    func testNavigationIncludesExtensionWaitWhetherRulesFinishBeforeOrAfterIt() async throws {
        for rulesPreparedDuringExtensions in [false, true] {
            let firing = PixelKitMock()
            var time: TimeInterval = 0
            let monitor = RulesCompilationMonitor(pixelFiring: firing, isOnboarding: true, now: { time })
            let assets = PassthroughSubject<ContentBlockingUpdating.NewContent, Never>()
            var releaseExtension: CheckedContinuation<Void, Never>?
            let extensionStarted = expectation(description: "Navigation waiting for extensions")
            let tab = TabViewController.fake(customWebView: { MockWebView(frame: .zero, configuration: $0) },
                                             sitePermissionsEnabled: true,
                                             webExtensionInitialLoadWaiterProvider: {
                {
                    await withCheckedContinuation { continuation in
                        releaseExtension = continuation
                        extensionStarted.fulfill()
                    }
                }
            }, contentBlockingAssetsPublisher: assets.eraseToAnyPublisher())
            tab.rulesCompilationMonitor = monitor
            tab.specialErrorPageNavigationHandler.delegate = nil
            defer { tab.prepareForDataClearing() }
            let decided = expectation(description: "Readiness checks released navigation")
            tab.webView(tab.webView, decidePolicyFor: makeAction()) { _ in decided.fulfill() }
            await fulfillment(of: [extensionStarted], timeout: 2)
            XCTAssertTrue(firing.actualFireCalls.isEmpty)
            let readyAssets = ContentBlockingUpdating.NewContent(
                rulesUpdate: .init(rules: [], changes: [:], completionTokens: []),
                sourceProvider: DefaultScriptSourceProvider(dependencies: .makeMock()), duckAiNativeStorageHandler: nil)
            if rulesPreparedDuringExtensions {
                let controller = try XCTUnwrap(tab.webView.configuration.userContentController as? UserContentController)
                let installed = expectation(description: "Rules installed while extension still pending")
                let subscription = controller.$contentBlockingAssets.compactMap { $0 }.first().sink { _ in installed.fulfill() }
                defer { subscription.cancel() }
                assets.send(readyAssets)
                await fulfillment(of: [installed], timeout: 5)
                time = 0.8
                try XCTUnwrap(releaseExtension).resume()
            } else {
                time = 0.4
                try XCTUnwrap(releaseExtension).resume()
                let deadline = Date().addingTimeInterval(2)
                while tab.sitePermissionsState.contentBlockingWaitTasks.isEmpty, Date() < deadline {
                    try await Task.sleep(nanoseconds: 1_000_000)
                }
                XCTAssertFalse(tab.sitePermissionsState.contentBlockingWaitTasks.isEmpty)
                XCTAssertTrue(firing.actualFireCalls.isEmpty, "Extension completion alone must not finish the sample")
                time = 0.8
                assets.send(readyAssets)
            }
            await fulfillment(of: [decided], timeout: 5)

            assertSetupPixel(firing, outcome: "success", state: "onboarding", total: "1",
                             extensions: rulesPreparedDuringExtensions ? "1" : "0.5",
                             rules: rulesPreparedDuringExtensions ? "0" : "0.5")
        }
    }

    func testStoppingNavigationReportsCancellationAndLateExtensionCompletionCannotReportSuccess() async throws {
        let firing = PixelKitMock()
        var time: TimeInterval = 0
        let monitor = RulesCompilationMonitor(pixelFiring: firing, isOnboarding: false, now: { time })
        var releaseExtension: CheckedContinuation<Void, Never>?
        let extensionStarted = expectation(description: "Navigation waiting for extensions")
        let tab = TabViewController.fake(customWebView: { MockWebView(frame: .zero, configuration: $0) },
                                         webExtensionInitialLoadWaiterProvider: {
            {
                await withCheckedContinuation { continuation in
                    releaseExtension = continuation
                    extensionStarted.fulfill()
                }
            }
        })
        tab.rulesCompilationMonitor = monitor
        tab.specialErrorPageNavigationHandler.delegate = nil
        defer { tab.prepareForDataClearing() }
        let decided = expectation(description: "Stopped navigation cancelled")
        tab.webView(tab.webView, decidePolicyFor: makeAction()) { policy in
            XCTAssertEqual(policy, .cancel)
            decided.fulfill()
        }
        await fulfillment(of: [extensionStarted], timeout: 2)
        time = 0.2
        tab.stopLoading()
        time = 100
        try XCTUnwrap(releaseExtension).resume()
        await fulfillment(of: [decided], timeout: 2)

        assertSetupPixel(firing, outcome: "cancelled", state: "regular", total: "0.5", extensions: "0.5", rules: "0")
    }

    func testSynchronousExtensionPreparationIsIncludedInItsWaitTime() async throws {
        let firing = PixelKitMock()
        var time: TimeInterval = 0
        let monitor = RulesCompilationMonitor(pixelFiring: firing, isOnboarding: false, now: { time }, isInBackground: { false })
        let tab = try await makeReadyTab(monitor: monitor, sitePermissionsEnabled: true, waiterProvider: {
            time = 0.4 // Preparing WebKit background content can do synchronous work before returning the waiter.
            return { time = 0.8 }
        })
        defer { tab.prepareForDataClearing() }
        let decided = expectation(description: "Navigation released")
        tab.webView(tab.webView, decidePolicyFor: makeAction()) { _ in decided.fulfill() }
        await fulfillment(of: [decided], timeout: 2)

        assertSetupPixel(firing, outcome: "success", state: "regular", total: "1", extensions: "1", rules: "0")
    }

    func testReadyRulesWithoutExtensionWaitReportZeroWithSitePermissionsOnAndOff() async throws {
        for permissionsEnabled in [false, true] {
            let firing = PixelKitMock()
            let monitor = RulesCompilationMonitor(pixelFiring: firing, isOnboarding: false, now: { 0 }, isInBackground: { false })
            let tab = try await makeReadyTab(monitor: monitor, sitePermissionsEnabled: permissionsEnabled)
            defer { tab.prepareForDataClearing() }
            let decided = expectation(description: "Already-ready navigation released")
            tab.webView(tab.webView, decidePolicyFor: makeAction()) { _ in decided.fulfill() }
            await fulfillment(of: [decided], timeout: 2)

            assertSetupPixel(firing, outcome: "success", state: "regular", total: "0", extensions: "0", rules: "0")
        }
    }

    func testSubframesAndNonWebNavigationsCannotConsumeOrFinishTheMainFrameSample() async throws {
        let firing = PixelKitMock()
        var time: TimeInterval = 0
        let monitor = RulesCompilationMonitor(pixelFiring: firing, isOnboarding: false, now: { time }, isInBackground: { false })
        var releaseExtension: CheckedContinuation<Void, Never>?
        let started = expectation(description: "Main-frame extension wait")
        let tab = try await makeReadyTab(monitor: monitor, sitePermissionsEnabled: true, waiterProvider: {
            {
                await withCheckedContinuation { continuation in
                    releaseExtension = continuation
                    started.fulfill()
                }
            }
        })
        defer { tab.prepareForDataClearing() }
        let nonWebDecided = expectation(description: "Non-web navigation released")
        tab.webView(tab.webView, decidePolicyFor: makeAction(url: URL(string: "about:blank")!)) { _ in nonWebDecided.fulfill() }
        await fulfillment(of: [nonWebDecided], timeout: 2)
        XCTAssertTrue(firing.actualFireCalls.isEmpty)

        let mainFrameDecided = expectation(description: "Main frame released")
        tab.webView(tab.webView, decidePolicyFor: makeAction()) { _ in mainFrameDecided.fulfill() }
        await fulfillment(of: [started], timeout: 2)
        time = 0.2
        let subframeDecided = expectation(description: "Subframe released")
        tab.webView(tab.webView, decidePolicyFor: makeAction(isMainFrame: false)) { _ in subframeDecided.fulfill() }
        await fulfillment(of: [subframeDecided], timeout: 2)
        XCTAssertTrue(firing.actualFireCalls.isEmpty, "Subframe readiness must not emit a zero-wait main-frame sample")
        time = 0.8
        try XCTUnwrap(releaseExtension).resume()
        await fulfillment(of: [mainFrameDecided], timeout: 2)

        assertSetupPixel(firing, outcome: "success", state: "regular", total: "1", extensions: "1", rules: "0")
    }

    func testRulesDeadlineReportsTimeoutBeforeErrorPageCancellation() async throws {
        let firing = PixelKitMock()
        var time: TimeInterval = 0
        let monitor = RulesCompilationMonitor(pixelFiring: firing, isOnboarding: false, now: { time }, isInBackground: { false })
        let tab = TabViewController.fake(customWebView: { MockWebView(frame: .zero, configuration: $0) },
                                         featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.sitePermissions]), sitePermissionsEnabled: true)
        tab.rulesCompilationMonitor = monitor
        tab.specialErrorPageNavigationHandler.delegate = nil
        tab.sitePermissionsNavigationTimeout = 0.02
        defer { tab.prepareForDataClearing() }
        let decided = expectation(description: "Rules deadline cancels navigation")
        tab.webView(tab.webView, decidePolicyFor: makeAction()) { policy in
            XCTAssertEqual(policy, .cancel)
            decided.fulfill()
        }
        time = 0.2
        await fulfillment(of: [decided], timeout: 2)

        assertSetupPixel(firing, outcome: "timeout", state: "regular", total: "0.5", extensions: "0", rules: "0.5")
    }

    private func makeReadyTab(monitor: RulesCompilationMonitor, sitePermissionsEnabled: Bool,
                              waiterProvider: @escaping @MainActor () -> WebExtensionInitialLoadWaiter? = { nil }) async throws -> TabViewController {
        let assets = PassthroughSubject<ContentBlockingUpdating.NewContent, Never>()
        let tab = TabViewController.fake(customWebView: { MockWebView(frame: .zero, configuration: $0) },
                                         featureFlagger: MockFeatureFlagger(enabledFeatureFlags: sitePermissionsEnabled ? [.sitePermissions] : []),
                                         sitePermissionsEnabled: sitePermissionsEnabled,
                                         webExtensionInitialLoadWaiterProvider: waiterProvider,
                                         contentBlockingAssetsPublisher: assets.eraseToAnyPublisher())
        tab.rulesCompilationMonitor = monitor
        tab.specialErrorPageNavigationHandler.delegate = nil
        let controller = try XCTUnwrap(tab.webView.configuration.userContentController as? UserContentController)
        let installed = expectation(description: "Fixture rules installed")
        let subscription = controller.$contentBlockingAssets.compactMap { $0 }.first().sink { _ in installed.fulfill() }
        defer { subscription.cancel() }
        assets.send(.init(rulesUpdate: .init(rules: [], changes: [:], completionTokens: []),
                          sourceProvider: DefaultScriptSourceProvider(dependencies: .makeMock()), duckAiNativeStorageHandler: nil))
        await fulfillment(of: [installed], timeout: 5)
        return tab
    }

    private func makeAction(url: URL = URL(string: "https://example.com/")!, isMainFrame: Bool = true) -> WKNavigationAction {
        let request = URLRequest(url: url)
        return MockNavigationAction(request: request, navigationType: .other,
                                    targetFrame: .mock(isMainFrame: isMainFrame, securityOriginHost: "example.com", request: request))
    }
}
