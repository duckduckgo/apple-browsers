//
//  ContentBlockingUpdatingTests.swift
//  DuckDuckGo
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import Combine
import Common
import Core
import TrackerRadarKit
import BrowserServicesKit
import BrowserServicesKitTestsUtils
import FeatureFlags_iOS
import PrivacyConfig
import PrivacyConfigTestsUtils
import UserScript
import AIChat
import AIChatTestingUtilities
@_spi(Testing) import PixelKit
@_spi(Testing) import Persistence
@testable import SitePermissions
@testable import DuckDuckGo

class FireproofingMock: Fireproofing {
    var loginDetectionEnabled: Bool = false

    var allowedDomains = [String]()

    func isAllowed(cookieDomain: String) -> Bool { return true }

    func isAllowed(fireproofDomain domain: String) -> Bool { return true }

    func addToAllowed(domain: String) {}
    
    func remove(domain: String) {}

    func clearAll() {}

    func displayDomain(for domain: String) -> String { domain }

    func migrateFireproofDomainsToETLDPlus1IfNeeded() -> Bool { false }
}

final class ContentBlockingUpdatingTests: XCTestCase {
    let appSettings = AppSettingsMock()
    let configManager = PrivacyConfigurationManagerMock()
    let rulesManager = ContentBlockerRulesManagerMock()
    var updating: ContentBlockingUpdating!
    let segmentSkipPreferences = SegmentSkipPreferences(store: InMemoryKeyValueStore())

    override func setUp() {
        super.setUp()
        updating = ContentBlockingUpdating(userScriptsDependencies: .init(appSettings: appSettings,
                                                                          sync: MockDDGSyncing(),
                                                                          privacyConfigurationManager: configManager,
                                                                          contentBlockingManager: rulesManager,
                                                                          fireproofing: FireproofingMock(),
                                                                          contentScopeExperimentsManager: MockContentScopeExperimentManager(),
                                                                          internalUserDecider: MockInternalUserDecider(),
                                                                          syncErrorHandler: CapturingAdapterErrorHandler(),
                                                                          webExtensionAvailability: nil,
                                                                          aiChatBonusOffer: AIChatBonusOfferDependencies(handler: MockAIChatBonusHandling(), messageLog: AIChatBonusMessageLog())),
                                           segmentSkipPreferences: segmentSkipPreferences)
    }

    override static func setUp() {
        // WKContentRuleList uses native c++ _contentRuleList api object and calls ~ContentRuleList on dealloc
        // let it just leak
        WKContentRuleList.swizzleDealloc()
    }
    override static func tearDown() {
        WKContentRuleList.restoreDealloc()
    }

    func testInitialUpdateIsBuffered() {
        rulesManager.updatesSubject.send(Self.testUpdate())

        let e = expectation(description: "should publish rules")
        let c = updating.userContentBlockingAssets.sink { assets in
            XCTAssertTrue(assets.isValid)
            e.fulfill()
        }

        withExtendedLifetime(c) {
            waitForExpectations(timeout: 5, handler: nil)
            updating.stopUpdates()
        }
    }

    func testNavigationWaitsForGeolocationOnlyWhenEnabledAndPreservesLegacyContentBlockingWaits() {
        for assetsInstalled in [false, true] {
            for contentBlockingEnabled in [false, true] {
                for isSERP in [false, true] {
                    for geolocationInstalled in [false, true] {
                        let legacyWait = !assetsInstalled && contentBlockingEnabled && !isSERP
                        XCTAssertEqual(TabViewController.shouldWaitForContentBlockingAssets(
                            assetsInstalled: assetsInstalled,
                            contentBlockingEnabled: contentBlockingEnabled,
                            sitePermissionsEnabled: false,
                            geolocationScriptInstalled: geolocationInstalled,
                            isDuckDuckGoSearch: isSERP
                        ), legacyWait)
                        XCTAssertEqual(TabViewController.shouldWaitForContentBlockingAssets(
                            assetsInstalled: assetsInstalled,
                            contentBlockingEnabled: contentBlockingEnabled,
                            sitePermissionsEnabled: true,
                            geolocationScriptInstalled: geolocationInstalled,
                            isDuckDuckGoSearch: isSERP
                        ), !geolocationInstalled || legacyWait)
                    }
                }
            }
        }
    }

    @MainActor
    func testWhenAssetsArriveWithoutGeolocationThenNavigationKeepsWaiting() async throws {
        let assets = PassthroughSubject<ContentBlockingUpdating.NewContent, Never>()
        let controller = UserContentController(assetsPublisher: assets, privacyConfigurationManager: configManager)
        defer { controller.cleanUpBeforeClosing() }
        let pixelFiring = PixelKitMock()
        let notifications = NotificationCenter()
        let tab = TabViewController.fake(customWebView: { configuration in
            (configuration.userContentController as? UserContentController)?.cleanUpBeforeClosing()
            configuration.userContentController = controller
            return MockWebView(frame: .zero, configuration: configuration)
        }, featureFlagger: MockFeatureFlagger(), sitePermissionsEnabled: true, pixelFiring: pixelFiring)
        tab.contentBlockingWaitNotificationCenter = notifications
        tab.contentBlockingWaitPixelTimeout = 0

        let cancelled = expectation(description: "Only teardown ends the wait")
        cancelled.assertForOverFulfill = true
        var decisions = [Bool]()
        XCTAssertTrue(tab.shouldWaitUntilContentBlockingIsLoaded({ ready in
            decisions.append(ready)
            cancelled.fulfill()
        }, for: URL(string: "https://example.com")!))
        notifications.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        let installed = expectation(description: "Assets without geolocation are installed")
        let subscription = controller.$contentBlockingAssets.compactMap { $0 }.first().sink { _ in installed.fulfill() }
        defer { subscription.cancel() }
        assets.send(.init(rulesUpdate: .init(rules: [], changes: [:], completionTokens: []),
                          sourceProvider: makeScriptSourceProvider(),
                          duckAiNativeStorageHandler: nil,
                          segmentSkipPreferences: segmentSkipPreferences))
        await fulfillment(of: [installed], timeout: 10)

        notifications.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        try await assertTimeoutPixelFires(pixelFiring)
        XCTAssertTrue(decisions.isEmpty, "Assets without geolocation must not resume the navigation")

        tab.closeSitePermissions()
        await fulfillment(of: [cancelled], timeout: 2)
        XCTAssertEqual(decisions, [false])
        XCTAssertFalse(tab.isError)
    }

    @MainActor
    func testWhenMainFrameNavigationReplacesAWaitThenOnlyTheNewDecisionCanResume() async throws {
        let tab = TabViewController.fake(customWebView: { MockWebView(frame: .zero, configuration: $0) },
                                        featureFlagger: MockFeatureFlagger(), sitePermissionsEnabled: true,
                                        contentBlockingAssetsPublisher: updating.userContentBlockingAssets)
        tab.specialErrorPageNavigationHandler.delegate = nil
        defer { tab.prepareForDataClearing() }
        tab.contentBlockingWaitPixelTimeout = 3600
        let compilationPixels = PixelKitMock()
        tab.rulesCompilationMonitor = RulesCompilationMonitor { compilationPixels }
        let webView = try XCTUnwrap(tab.webView as? MockWebView)
        let cancelled = expectation(description: "Superseded main-frame decision cancelled")
        cancelled.assertForOverFulfill = true
        let continued = expectation(description: "Replacement decision resumes with required assets")
        continued.assertForOverFulfill = true
        var oldDecisions = [WKNavigationActionPolicy]()
        var newDecisions = [WKNavigationActionPolicy]()
        func action(path: String) -> WKNavigationAction {
            let request = URLRequest(url: URL(string: "https://example.com/\(path)")!)
            return MockNavigationAction(request: request, navigationType: .other,
                                        targetFrame: .mock(isMainFrame: true, securityOriginHost: "example.com", request: request))
        }
        tab.webView(webView, decidePolicyFor: action(path: "old")) { policy in
            oldDecisions.append(policy)
            cancelled.fulfill()
        }
        await Task.yield()
        tab.webView(webView, decidePolicyFor: action(path: "new")) { policy in
            newDecisions.append(policy)
            continued.fulfill()
        }
        await fulfillment(of: [cancelled], timeout: 1)
        XCTAssertEqual(oldDecisions, [.cancel])
        XCTAssertTrue(newDecisions.isEmpty)
        XCTAssertTrue(compilationPixels.actualFireCalls.isEmpty, "A superseded wait must not report the rules as compiled")
        rulesManager.updatesSubject.send(Self.testUpdate())
        await fulfillment(of: [continued], timeout: 10)
        XCTAssertEqual(oldDecisions, [.cancel])
        XCTAssertEqual(newDecisions.count, 1)
        XCTAssertNotEqual(newDecisions.first, .cancel)
        XCTAssertEqual(compilationPixels.actualFireCalls.count, 1)
        XCTAssertTrue(compilationPixels.actualFireCalls.first?.pixel.name.hasPrefix("m_compilation_result_success_") == true)
        XCTAssertFalse(tab.isError, "The superseded wait must not replace the new page with an error")
        XCTAssertEqual(webView.loadCallCount, 0)
    }

    @MainActor
    func testWhenExplicitLoadReplacesAWaitThenItCancelsBeforeTheNextPolicyDecision() async throws {
        let tab = TabViewController.fake(customWebView: { MockWebView(frame: .zero, configuration: $0) },
                                        featureFlagger: MockFeatureFlagger(), sitePermissionsEnabled: true)
        tab.specialErrorPageNavigationHandler.delegate = nil
        defer { tab.prepareForDataClearing() }
        tab.contentBlockingWaitPixelTimeout = 3600
        let webView = try XCTUnwrap(tab.webView as? MockWebView)
        let oldRequest = URLRequest(url: URL(string: "https://example.com/old")!)
        let action = MockNavigationAction(request: oldRequest, navigationType: .other,
                                          targetFrame: .mock(isMainFrame: true, securityOriginHost: "example.com", request: oldRequest))
        let cancelled = expectation(description: "Explicit load cancels the old decision before WebKit asks about its replacement")
        cancelled.assertForOverFulfill = true
        var decisions = [WKNavigationActionPolicy]()
        tab.webView(webView, decidePolicyFor: action) { policy in
            decisions.append(policy)
            cancelled.fulfill()
        }
        await Task.yield()
        let replacementURL = URL(string: "https://example.com/new")!
        let loaded = expectation(description: "Replacement URL reaches WebKit")
        webView.loadCompletionHandler = { loaded.fulfill() }
        tab.load(url: replacementURL)
        XCTAssertTrue(tab.sitePermissionsState.contentBlockingWaitTasks.isEmpty)
        // MockWebView.load does not invoke a navigation delegate: replacement itself must cancel the wait.
        await fulfillment(of: [cancelled, loaded], timeout: 1)
        XCTAssertEqual(decisions, [.cancel])
        XCTAssertEqual(webView.lastLoadedRequest?.url, replacementURL)
        XCTAssertEqual(tab.url, replacementURL)
        XCTAssertFalse(tab.isError, "The replaced wait must not show an error page")
    }

    @MainActor
    func testWhenLegacyWaitsStallThenPixelCountsForegroundTimeAndClearingPreservesPendingDecisions() async throws {
        let pixelFiring = PixelKitMock()
        let notifications = NotificationCenter()
        var tab: TabViewController? = TabViewController.fake(sitePermissionsEnabled: false,
                                                            contentBlockingAssetsPublisher: updating.userContentBlockingAssets, pixelFiring: pixelFiring)
        tab?.specialErrorPageNavigationHandler.delegate = nil
        let config = try XCTUnwrap(tab?.privacyConfigurationManager.privacyConfig as? PrivacyConfigurationMock)
        config.enabledFeaturesForVersions = [.contentBlocking: [AppVersionProvider().appVersion() ?? ""]]
        tab?.contentBlockingWaitNotificationCenter = notifications
        tab?.contentBlockingWaitPixelTimeout = 0
        let released = expectation(description: "Tab releases after all pending decisions resume")
        tab?.onDeinit { released.fulfill() }
        let resumed = expectation(description: "All legacy waits resume when assets arrive")
        resumed.expectedFulfillmentCount = 5
        let state = try XCTUnwrap(tab?.sitePermissionsState)
        var decisions = [Bool]()
        let decide: @Sendable @MainActor (Bool) -> Void = {
            XCTAssertNil(state.contentBlockingWaitTimeoutPixel, "Assets must cancel measurement before decisions resume")
            decisions.append($0)
            resumed.fulfill()
        }
        let url = URL(string: "https://example.com")!
        XCTAssertEqual(tab?.shouldWaitUntilContentBlockingIsLoaded(decide, for: url), true)
        let firstTimer = ObjectIdentifier(try XCTUnwrap(tab?.sitePermissionsState.contentBlockingWaitTimeoutPixel))
        XCTAssertEqual(tab?.shouldWaitUntilContentBlockingIsLoaded(decide, for: url, isMainFrame: false), true)
        XCTAssertEqual(tab?.sitePermissionsState.contentBlockingWaitTimeoutPixel.map(ObjectIdentifier.init), firstTimer)
        XCTAssertEqual(tab?.shouldWaitUntilContentBlockingIsLoaded(decide, for: url), true)
        XCTAssertNotEqual(tab?.sitePermissionsState.contentBlockingWaitTimeoutPixel.map(ObjectIdentifier.init), firstTimer)

        notifications.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty)
        notifications.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        try await assertTimeoutPixelFires(pixelFiring)
        XCTAssertTrue(decisions.isEmpty, "Emitting the pixel must not resolve navigation")

        XCTAssertEqual(tab?.shouldWaitUntilContentBlockingIsLoaded(decide, for: url), true)
        XCTAssertNotNil(tab?.sitePermissionsState.contentBlockingWaitTimeoutPixel)
        tab?.prepareForDataClearing()
        XCTAssertNil(tab?.sitePermissionsState.contentBlockingWaitTimeoutPixel)
        tab?.contentBlockingWaitPixelTimeout = 3600
        XCTAssertEqual(tab?.shouldWaitUntilContentBlockingIsLoaded(decide, for: url), true)
        XCTAssertNotNil(state.contentBlockingWaitTimeoutPixel)
        tab = nil
        XCTAssertTrue(decisions.isEmpty, "Clearing must not resolve legacy decisions")
        // The fixture's rule list is a stub WebKit cannot install; only the wait decision sees blocking enabled.
        config.enabledFeaturesForVersions = [:]
        rulesManager.updatesSubject.send(Self.testUpdate())
        await fulfillment(of: [resumed, released], timeout: 10, enforceOrder: true)
        XCTAssertEqual(decisions, [true, true, true, true, true])
        XCTAssertEqual(pixelFiring.actualFireCalls.count, 1, "Cleared waits must not emit another pixel")
    }

    @MainActor
    func testWhenGeolocationWaitStallsThenPixelCountsOnlyForegroundTimeAndDoesNotEndTheWait() async throws {
        let cases = [(true, "https://example.com"), (true, "https://duckduckgo.com/?q=maps"),
                     (false, "https://example.com"), (false, "https://duckduckgo.com/?q=maps")]
        for (contentBlockingEnabled, url) in cases {
            let pixelFiring = PixelKitMock()
            let notifications = NotificationCenter()
            let tab = TabViewController.fake(featureFlagger: MockFeatureFlagger(), sitePermissionsEnabled: true,
                                            pixelFiring: pixelFiring)
            tab.specialErrorPageNavigationHandler.delegate = nil
            defer { tab.prepareForDataClearing() }
            let config = try XCTUnwrap(tab.privacyConfigurationManager.privacyConfig as? PrivacyConfigurationMock)
            config.enabledFeaturesForVersions = contentBlockingEnabled ? [.contentBlocking: [AppVersionProvider().appVersion() ?? ""]] : [:]
            tab.contentBlockingWaitNotificationCenter = notifications
            tab.contentBlockingWaitPixelTimeout = 0
            let cancelled = expectation(description: "Teardown ends the stalled wait")
            var decisions = [Bool]()
            XCTAssertTrue(tab.shouldWaitUntilContentBlockingIsLoaded({ ready in
                decisions.append(ready)
                cancelled.fulfill()
            }, for: URL(string: url)!))

            notifications.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
            try await Task.sleep(nanoseconds: 100_000_000)
            XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty, "Time in the background must not count")
            notifications.post(name: UIApplication.willEnterForegroundNotification, object: nil)
            try await assertTimeoutPixelFires(pixelFiring)
            XCTAssertTrue(decisions.isEmpty, "Emitting the pixel must not resolve navigation")
            XCTAssertFalse(tab.isError)

            tab.closeSitePermissions()
            await fulfillment(of: [cancelled], timeout: 2)
            XCTAssertEqual(decisions, [false])
            XCTAssertNil(tab.sitePermissionsState.contentBlockingWaitTimeoutPixel, "Finished navigations must no longer be measured")
        }
    }

    @MainActor
    private func assertTimeoutPixelFires(_ pixelFiring: PixelKitMock, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(5)
        while pixelFiring.actualFireCalls.isEmpty, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(pixelFiring.actualFireCalls, [ExpectedFireCall(pixel: ContentBlockingPixel.rulesCompilationTimeout, frequency: .dailyAndCount)],
                       file: file, line: line)
    }

    @MainActor
    func testWhenTabClosesDuringAssetWaitThenCancellationDoesNotPresentAnErrorPage() async throws {
        let tab = TabViewController.fake(featureFlagger: MockFeatureFlagger(), sitePermissionsEnabled: true)
        tab.specialErrorPageNavigationHandler.delegate = nil
        defer { tab.prepareForDataClearing() }
        tab.contentBlockingWaitPixelTimeout = 3600
        try XCTUnwrap(tab.privacyConfigurationManager.privacyConfig as? PrivacyConfigurationMock).enabledFeaturesForVersions = [:]
        let cancelled = expectation(description: "Teardown cancels the pending decision")
        cancelled.assertForOverFulfill = true
        XCTAssertTrue(tab.shouldWaitUntilContentBlockingIsLoaded({ ready in
            XCTAssertFalse(ready)
            cancelled.fulfill()
        }, for: URL(string: "https://example.com")!))
        await Task.yield()
        XCTAssertNotNil(tab.sitePermissionsState.contentBlockingWaitTimeoutPixel)
        tab.closeSitePermissions()
        XCTAssertNil(tab.sitePermissionsState.contentBlockingWaitTimeoutPixel)
        await fulfillment(of: [cancelled], timeout: 1)
        XCTAssertFalse(tab.isError)
        XCTAssertTrue(tab.sitePermissionsState.contentBlockingWaitTasks.isEmpty)
    }

    @MainActor
    func testWhenFireClearsPendingGeolocationPolicyThenWebViewIsReleased() async throws {
        try await assertPendingGeolocationEvaluationIsReleased(stage: .policy) { $0.prepareForDataClearing() }
    }

    @MainActor
    func testWhenTabClosesWithPendingGeolocationPolicyThenWebViewIsReleased() async throws {
        try await assertPendingGeolocationEvaluationIsReleased(stage: .policy) { $0.closeSitePermissions() }
    }

    @MainActor
    func testWhenFireClearsPendingGeolocationDocumentValidationThenWebViewIsReleased() async throws {
        try await assertPendingGeolocationEvaluationIsReleased(stage: .currentDocument) { $0.prepareForDataClearing() }
    }

    @MainActor
    func testWhenTabClosesBeforeGeolocationPolicyResumesThenDocumentValidationDoesNotStart() async throws {
        try await assertPendingGeolocationEvaluationIsReleased(stage: .completedPolicy) { $0.closeSitePermissions() }
    }

    @MainActor
    private func assertPendingGeolocationEvaluationIsReleased(stage: SuspendedGeolocationEvaluation.Stage,
                                                              teardown: (TabViewController) -> Void) async throws {
        let evaluationStarted = expectation(description: "Geolocation JavaScript evaluation started")
        let replied = expectation(description: "Pending geolocation request denied")
        replied.assertForOverFulfill = true
        let navigationCancelled = expectation(description: "Pending navigation cancelled")
        navigationCancelled.assertForOverFulfill = true
        let released = expectation(description: "WebView released before JavaScript completes")
        let evaluation = SuspendedGeolocationEvaluation(stage: stage, started: evaluationStarted)
        defer { evaluation.complete() }
        weak var weakWebView: WKWebView?
        var replies = 0
        var decisions = [WKNavigationActionPolicy]()

        func exercise() async throws -> Task<Void, Never> {
            let tab = TabViewController.fake(customWebView: { configuration in
                let webView = SuspendedGeolocationWebView(frame: .zero, configuration: configuration)
                webView.evaluation = evaluation
                return webView
            }, featureFlagger: MockFeatureFlagger(), sitePermissionsEnabled: true)
            tab.specialErrorPageNavigationHandler.delegate = nil
            let webView = try XCTUnwrap(tab.webView)
            weakWebView = webView
            webView.onDeinit { released.fulfill() }
            let script = GeolocationUserScript()
            tab.configureSitePermissionsGeolocation(with: script)
            let controller = webView.configuration.userContentController
            let frame = WKFrameInfo.mock(isMainFrame: true, securityOriginHost: "example.com", webView: webView)
            let message = MockWKScriptMessageObject(webView: webView, frameInfo: frame, body: [
                "kind": "registerFrame",
                "capability": GeolocationUserScript.capabilityToken,
                "nonce": String(repeating: "a", count: 32),
                "documentID": String(repeating: "b", count: 32)
            ]).scriptMessage
            // The message and frame mocks hold the WebView weakly; the request must not capture the tab.
            let request = Task { @MainActor in
                let response = await script.userContentController(controller, didReceive: message)
                XCTAssertEqual((response.0 as? [String: Any])?["code"] as? Int,
                               GeolocationPositionError.Code.permissionDenied.rawValue)
                replies += 1
                replied.fulfill()
            }
            await fulfillment(of: [evaluationStarted], timeout: 1)

            let urlRequest = URLRequest(url: URL(string: "https://example.com/pending")!)
            let action = MockNavigationAction(request: urlRequest, navigationType: .other,
                                              targetFrame: .mock(isMainFrame: true, securityOriginHost: "example.com", request: urlRequest))
            tab.webView(webView, decidePolicyFor: action) { policy in
                decisions.append(policy)
                navigationCancelled.fulfill()
            }
            XCTAssertFalse(tab.sitePermissionsState.contentBlockingWaitTasks.isEmpty)
            if stage == .completedPolicy {
                // Resume JavaScript and close in the same actor turn, before the request task can run again.
                evaluation.complete()
            }
            teardown(tab)
            // Resolve while the tab is alive so deinit cannot provide the cancellation under test.
            await fulfillment(of: [replied, navigationCancelled], timeout: 1)
            XCTAssertEqual(decisions, [.cancel])
            XCTAssertTrue(tab.sitePermissionsState.contentBlockingWaitTasks.isEmpty)
            if stage == .completedPolicy {
                XCTAssertEqual(evaluation.currentDocumentEvaluationCount, 0)
            }
            return request
        }

        let request = try await exercise()
        await fulfillment(of: [released], timeout: 1)
        XCTAssertNil(weakWebView)
        // A late callback must be harmless. Completing also cleans up the deliberately suspended pre-fix fixture.
        evaluation.complete()
        await request.value
        XCTAssertEqual(replies, 1)
        XCTAssertEqual(decisions, [.cancel])
    }

    @MainActor
    func testWhenUserStopsDuringAssetWaitThenLateAssetsCannotResumeNavigationOrShowAnError() async throws {
        let controllerReleased = expectation(description: "Stopped navigation releases its content controller")
        func exerciseStop() async throws {
            let tab = TabViewController.fake(featureFlagger: MockFeatureFlagger(), sitePermissionsEnabled: true,
                                            contentBlockingAssetsPublisher: updating.userContentBlockingAssets)
            let controller = try XCTUnwrap(tab.webView.configuration.userContentController as? UserContentController)
            controller.onDeinit { controllerReleased.fulfill() }
            tab.specialErrorPageNavigationHandler.delegate = nil
            defer { tab.prepareForDataClearing() }
            tab.contentBlockingWaitPixelTimeout = 3600
            let compilationPixels = PixelKitMock()
            tab.rulesCompilationMonitor = RulesCompilationMonitor { compilationPixels }
            try XCTUnwrap(tab.privacyConfigurationManager.privacyConfig as? PrivacyConfigurationMock).enabledFeaturesForVersions = [:]
            let request = URLRequest(url: URL(string: "https://example.com/stopped")!)
            let action = MockNavigationAction(request: request, navigationType: .other,
                                              targetFrame: .mock(isMainFrame: true, securityOriginHost: "example.com", request: request))
            let cancelled = expectation(description: "Stop cancels the pending WebKit decision")
            cancelled.assertForOverFulfill = true
            var decisions = [WKNavigationActionPolicy]()
            tab.webView(tab.webView, decidePolicyFor: action) { policy in
                decisions.append(policy)
                cancelled.fulfill()
            }
            await Task.yield()
            XCTAssertNotNil(tab.sitePermissionsState.contentBlockingWaitTimeoutPixel)
            tab.stopLoading()
            XCTAssertNil(tab.sitePermissionsState.contentBlockingWaitTimeoutPixel)
            await fulfillment(of: [cancelled], timeout: 1)
            XCTAssertEqual(decisions, [.cancel])

            let installed = expectation(description: "Assets arrive after Stop")
            let subscription = controller.$contentBlockingAssets.compactMap { $0 }.first().sink { _ in installed.fulfill() }
            rulesManager.updatesSubject.send(Self.testUpdate())
            await fulfillment(of: [installed], timeout: 10)
            subscription.cancel()
            XCTAssertEqual(decisions, [.cancel])
            XCTAssertTrue(compilationPixels.actualFireCalls.isEmpty, "A stopped wait must not report the rules as compiled")
            XCTAssertFalse(tab.isError)
            XCTAssertTrue(tab.sitePermissionsState.contentBlockingWaitTasks.isEmpty)
        }
        try await exerciseStop()
        await fulfillment(of: [controllerReleased], timeout: 2)
    }

    @MainActor
    func testWhenSERPNavigationWaitsBeforeFirstAssetsThenItResumesOnceScriptsAreInstalled() async throws {
        let tab = TabViewController.fake(featureFlagger: MockFeatureFlagger(), sitePermissionsEnabled: true,
                                        contentBlockingAssetsPublisher: updating.userContentBlockingAssets)
        tab.specialErrorPageNavigationHandler.delegate = nil
        defer { tab.prepareForDataClearing() }
        let config = try XCTUnwrap(tab.privacyConfigurationManager.privacyConfig as? PrivacyConfigurationMock)
        config.enabledFeaturesForVersions = [:]
        tab.contentBlockingWaitPixelTimeout = 3600
        let controller = try XCTUnwrap(tab.webView.configuration.userContentController as? UserContentController)
        XCTAssertNil(controller.contentBlockingAssets)

        let resumed = expectation(description: "Navigation resumes after launch-time scripts are installed")
        resumed.assertForOverFulfill = true
        var decisions = [Bool]()
        XCTAssertTrue(tab.shouldWaitUntilContentBlockingIsLoaded({ shouldContinue in
            decisions.append(shouldContinue)
            resumed.fulfill()
        }, for: URL(string: "https://duckduckgo.com/?q=maps")!))
        let pendingTask = try XCTUnwrap(tab.sitePermissionsState.contentBlockingWaitTasks.values.first)
        defer { pendingTask.cancel() }
        await Task.yield()
        XCTAssertTrue(decisions.isEmpty)

        let mainTimer = ObjectIdentifier(try XCTUnwrap(tab.sitePermissionsState.contentBlockingWaitTimeoutPixel))
        let subframe = expectation(description: "Subframe wait resumes with the same assets")
        XCTAssertTrue(tab.shouldWaitUntilContentBlockingIsLoaded({ ready in
            XCTAssertTrue(ready)
            subframe.fulfill()
        }, for: URL(string: "https://example.com")!, isMainFrame: false))
        XCTAssertEqual(tab.sitePermissionsState.contentBlockingWaitTimeoutPixel.map(ObjectIdentifier.init), mainTimer,
                       "A subframe wait must not restart the main-frame measurement")
        rulesManager.updatesSubject.send(Self.testUpdate())
        await fulfillment(of: [resumed, subframe], timeout: 10)
        await pendingTask.value
        XCTAssertNil(tab.sitePermissionsState.contentBlockingWaitTimeoutPixel)
        XCTAssertEqual(decisions, [true])
        XCTAssertNotNil((controller.contentBlockingAssets?.userScripts as? UserScripts)?.geolocationUserScript)
        XCTAssertTrue(tab.sitePermissionsState.contentBlockingWaitTasks.isEmpty)
    }

    @MainActor
    func testGeolocationUserScriptIsRegisteredOnlyWhenSitePermissionsIsSupported() async throws {
        let sourceProvider = makeScriptSourceProvider()
        let geolocationUserScript = GeolocationUserScript()

        let disabledScripts = UserScripts(
            with: sourceProvider,
            featureFlagger: MockFeatureFlagger(),
            sitePermissionsEnabled: false,
            geolocationUserScript: geolocationUserScript,
            segmentSkipPreferences: segmentSkipPreferences
        )
        XCTAssertNil(disabledScripts.geolocationUserScript)
        XCTAssertFalse(disabledScripts.userScripts.contains { $0 is GeolocationUserScript })
        XCTAssertFalse(disabledScripts.userScripts.contains { $0 is GeolocationPolicyUserScript })

        let enabledScripts = UserScripts(
            with: sourceProvider,
            featureFlagger: MockFeatureFlagger(),
            sitePermissionsEnabled: true,
            geolocationUserScript: geolocationUserScript,
            segmentSkipPreferences: segmentSkipPreferences
        )
        XCTAssertTrue(enabledScripts.geolocationUserScript === geolocationUserScript)
        XCTAssertTrue(enabledScripts.userScripts.contains { ($0 as? GeolocationUserScript) === geolocationUserScript })
        let pageIndex = try XCTUnwrap(enabledScripts.userScripts.firstIndex { $0 === geolocationUserScript })
        let policyIndex = try XCTUnwrap(enabledScripts.userScripts.firstIndex { $0 === geolocationUserScript.policyScript })
        XCTAssertEqual(policyIndex + 1, pageIndex)
        let wkScripts = await enabledScripts.loadWKUserScripts()
        XCTAssertEqual(wkScripts.count, enabledScripts.userScripts.count)
        XCTAssertEqual(wkScripts[policyIndex].source, geolocationUserScript.policyScript.makeWKUserScriptSync().source)
        XCTAssertEqual(wkScripts[pageIndex].source, geolocationUserScript.makeWKUserScriptSync().source)
        XCTAssertEqual(geolocationUserScript.policyScript.getContentWorld(), .defaultClient)
        XCTAssertEqual(geolocationUserScript.getContentWorld(), .page)

        let nonTabScripts = UserScripts(
            with: sourceProvider,
            featureFlagger: MockFeatureFlagger(),
            segmentSkipPreferences: segmentSkipPreferences
        )
        XCTAssertNil(nonTabScripts.geolocationUserScript)
        XCTAssertFalse(nonTabScripts.userScripts.contains { $0 is GeolocationUserScript })
        XCTAssertFalse(nonTabScripts.userScripts.contains { $0 is GeolocationPolicyUserScript })
    }

    /// The site permissions navigation wait has no deadline, so every bundle must carry the geolocation script
    /// it waits for; otherwise a navigation could wait forever once assets have arrived.
    @MainActor
    func testWhenContentUpdatesThenEveryBundleCarriesTheLaunchTimeScripts() {
        for enabledAtLaunch in [false, true] {
            let mediaCaptureUserScript = MediaCaptureUserScript()
            let geolocationUserScript = GeolocationUserScript()
            let contentSubject = PassthroughSubject<ContentBlockingUpdating.NewContent, Never>()
            var receivedScripts = [(MediaCaptureUserScript?, GeolocationUserScript?)]()
            let cancellable = TabViewController.sitePermissionsContentBlockingAssetsPublisher(
                contentSubject.eraseToAnyPublisher(),
                sitePermissionsEnabled: enabledAtLaunch,
                mediaCaptureUserScript: mediaCaptureUserScript,
                geolocationUserScript: geolocationUserScript
            ).sink { content in
                let scripts = content.makeUserScripts(content.sourceProvider)
                receivedScripts.append((scripts.mediaCaptureUserScript, scripts.geolocationUserScript))
            }

            for _ in 0..<2 {
                contentSubject.send(.init(rulesUpdate: Self.testUpdate(),
                                          sourceProvider: makeScriptSourceProvider(),
                                          duckAiNativeStorageHandler: nil,
                                          segmentSkipPreferences: segmentSkipPreferences))
            }
            XCTAssertEqual(receivedScripts.count, 2)
            for (media, geolocation) in receivedScripts {
                XCTAssertTrue(media === mediaCaptureUserScript)
                XCTAssertTrue(geolocation === (enabledAtLaunch ? geolocationUserScript : nil))
            }
            withExtendedLifetime(cancellable) {}
        }
    }

    func testWhenRuleListIsRecompiledThenUpdatesAreReceived() {
        rulesManager.updatesSubject.send(Self.testUpdate())

        let e1 = expectation(description: "should publish rules 1")
        var e2: XCTestExpectation!
        var e3: XCTestExpectation!
        var ruleList1: WKContentRuleList?
        var ruleList2: WKContentRuleList?
        let c = updating.userContentBlockingAssets.sink { assets in
            switch (ruleList1, ruleList2) {
            case (.none, _):
                ruleList1 = assets.rules(withName: "test")
                e1.fulfill()
            case (.some, .none):
                ruleList2 = assets.rules(withName: "test")
                e2.fulfill()
            case (.some(let list1), .some(let list2)):
                XCTAssertFalse(list1 == list2)
                XCTAssertFalse(assets.rules(withName: "test") === list2)
                e3.fulfill()
            }
        }

        withExtendedLifetime(c) {
            waitForExpectations(timeout: 5, handler: nil)
            e2 = expectation(description: "should publish rules 2")
            rulesManager.updatesSubject.send(Self.testUpdate())
            waitForExpectations(timeout: 5, handler: nil)
            e3 = expectation(description: "should publish rules 3")
            rulesManager.updatesSubject.send(Self.testUpdate())
            waitForExpectations(timeout: 5, handler: nil)
            updating.stopUpdates()
        }
    }

    func testWhenDoNotSellStatusChangesThenUserScriptsAreRebuild() {
        let e1 = expectation(description: "should post initial update")
        var e2: XCTestExpectation!
        var ruleList: WKContentRuleList!
        let c = updating.userContentBlockingAssets.sink { assets in
            if ruleList == nil {
                ruleList = assets.rules(withName: "test")
                e1.fulfill()
            } else {
                // ruleList should not be recompiled
                XCTAssertTrue(assets.rules(withName: "test") === ruleList)
                XCTAssertTrue(assets.isValid)
                e2.fulfill()
            }
        }

        rulesManager.updatesSubject.send(Self.testUpdate())
        withExtendedLifetime(c) {
            waitForExpectations(timeout: 5, handler: nil)
            e2 = expectation(description: "should rebuild user scripts")
            appSettings.sendDoNotSell = !appSettings.sendDoNotSell
            NotificationCenter.default.post(name: AppUserDefaults.Notifications.doNotSellStatusChange, object: nil)
            waitForExpectations(timeout: 5, handler: nil)
            updating.stopUpdates()
        }
    }

    func testWhenFireproffingNotificationSentThenUserScriptsAreRebuild() {
        let e1 = expectation(description: "should post initial update")
        var e2: XCTestExpectation!

        var ruleList: WKContentRuleList!
        let c = updating.userContentBlockingAssets.sink { assets in
            if ruleList == nil {
                ruleList = assets.rules(withName: "test")
                e1.fulfill()
            } else {
                // ruleList should not be recompiled
                XCTAssertTrue(assets.rules(withName: "test") === ruleList)
                XCTAssertTrue(assets.isValid)
                e2.fulfill()
            }
        }

        rulesManager.updatesSubject.send(Self.testUpdate())
        withExtendedLifetime(c) {
            waitForExpectations(timeout: 5, handler: nil)
            e2 = expectation(description: "should rebuild user scripts")
            NotificationCenter.default.post(name: UserDefaultsFireproofing.Notifications.loginDetectionStateChanged, object: nil)
            waitForExpectations(timeout: 5, handler: nil)
            updating.stopUpdates()
        }
    }

    func testWhenAutofillEnabledChangeNotificationSentThenUserScriptsAreRebuild() {
        let e1 = expectation(description: "should post initial update")
        var e2: XCTestExpectation!
        var ruleList: WKContentRuleList!
        let c = updating.userContentBlockingAssets.sink { assets in
            if ruleList == nil {
                ruleList = assets.rules(withName: "test")
                e1.fulfill()
            } else {
                // ruleList should not be recompiled
                XCTAssertTrue(assets.rules(withName: "test") === ruleList)
                XCTAssertTrue(assets.isValid)
                e2.fulfill()
            }
        }

        rulesManager.updatesSubject.send(Self.testUpdate())
        withExtendedLifetime(c) {
            waitForExpectations(timeout: 5, handler: nil)
            e2 = expectation(description: "should rebuild user scripts")
            NotificationCenter.default.post(name: AppUserDefaults.Notifications.autofillEnabledChange, object: nil)
            waitForExpectations(timeout: 5, handler: nil)
            updating.stopUpdates()
        }
    }

    func testWhenDidVerifyInternalUserNotificationSentThenUserScriptsAreRebuild() {
        let e1 = expectation(description: "should post initial update")
        var e2: XCTestExpectation!
        var ruleList: WKContentRuleList!
        let c = updating.userContentBlockingAssets.sink { assets in
            if ruleList == nil {
                ruleList = assets.rules(withName: "test")
                e1.fulfill()
            } else {
                // ruleList should not be recompiled
                XCTAssertTrue(assets.rules(withName: "test") === ruleList)
                XCTAssertTrue(assets.isValid)
                e2.fulfill()
            }
        }

        rulesManager.updatesSubject.send(Self.testUpdate())
        withExtendedLifetime(c) {
            waitForExpectations(timeout: 5, handler: nil)
            e2 = expectation(description: "should rebuild user scripts")
            NotificationCenter.default.post(name: AppUserDefaults.Notifications.didVerifyInternalUser, object: nil)
            waitForExpectations(timeout: 5, handler: nil)
            updating.stopUpdates()
        }
    }

    func testWhenDidUpdateStorageCacheNotificationNotificationSentThenUserScriptsAreRebuild() {
        let e1 = expectation(description: "should post initial update")
        var e2: XCTestExpectation?
        var ruleList: WKContentRuleList!
        let c = updating.userContentBlockingAssets.sink { assets in
            if ruleList == nil {
                ruleList = assets.rules(withName: "test")
                e1.fulfill()
            } else {
                // ruleList should not be recompiled
                XCTAssertTrue(assets.rules(withName: "test") === ruleList)
                XCTAssertTrue(assets.isValid)
                e2?.fulfill()
                e2 = nil
            }
        }

        rulesManager.updatesSubject.send(Self.testUpdate())
        withExtendedLifetime(c) {
            waitForExpectations(timeout: 5, handler: nil)
            e2 = expectation(description: "should rebuild user scripts")
            NotificationCenter.default.post(name: ConfigurationManager.didUpdateTrackerDependencies, object: nil)
            waitForExpectations(timeout: 5, handler: nil)
            updating.stopUpdates()
        }
    }

    func testWhenRuleListIsRecompiledThenCompletionTokensArePublished() {
        let update1 = Self.testUpdate()
        let update2 = Self.testUpdate()
        var update1received = false
        let e1 = expectation(description: "should post initial update")
        var e2: XCTestExpectation!
        let c = updating.userContentBlockingAssets.map { $0.rulesUpdate.completionTokens }.sink { tokens in
            if !update1received {
                XCTAssertEqual(tokens, update1.completionTokens)
                update1received = true
                e1.fulfill()
            } else {
                XCTAssertEqual(tokens, update2.completionTokens)
                e2.fulfill()
            }
        }

        withExtendedLifetime(c) {
            rulesManager.updatesSubject.send(update1)
            waitForExpectations(timeout: 5, handler: nil)

            e2 = expectation(description: "2 updates received")
            rulesManager.updatesSubject.send(update2)

            waitForExpectations(timeout: 5, handler: nil)
            updating.stopUpdates()
        }
    }

    // MARK: - Test data

    private func makeScriptSourceProvider() -> DefaultScriptSourceProvider {
        DefaultScriptSourceProvider(dependencies: .init(appSettings: appSettings,
                                                         sync: MockDDGSyncing(),
                                                         privacyConfigurationManager: configManager,
                                                         contentBlockingManager: rulesManager,
                                                         fireproofing: FireproofingMock(),
                                                         contentScopeExperimentsManager: MockContentScopeExperimentManager(),
                                                         internalUserDecider: MockInternalUserDecider(),
                                                         syncErrorHandler: CapturingAdapterErrorHandler(),
                                                         webExtensionAvailability: nil,
                                                         aiChatBonusOffer: AIChatBonusOfferDependencies(handler: MockAIChatBonusHandling(), messageLog: AIChatBonusMessageLog())))
    }

    static let tracker = KnownTracker(domain: "tracker.com",
                               defaultAction: .block,
                               owner: KnownTracker.Owner(name: "Tracker Inc", displayName: "Tracker Inc company", ownedBy: nil),
                               prevalence: 0.1,
                               subdomains: nil,
                               categories: nil,
                               rules: nil)

    static let tds = TrackerData(trackers: ["tracker.com": tracker],
                                 entities: ["Tracker Inc": Entity(displayName: "Trackr Inc company",
                                                                  domains: ["tracker.com"],
                                                                  prevalence: 0.1)],
                                 domains: ["tracker.com": "Tracker Inc"],
                                 cnames: [:])
    static let encodedTrackerData = String(data: (try? JSONEncoder().encode(tds))!, encoding: .utf8)!

    static func testRules() -> [ContentBlockerRulesManager.Rules] {
        [.init(name: "test",
               rulesList: WKContentRuleList(),
               trackerData: tds,
               encodedTrackerData: encodedTrackerData,
               etag: "asd",
               identifier: ContentBlockerRulesIdentifier(name: "test",
                                                         tdsEtag: "asd",
                                                         tempListId: nil,
                                                         allowListId: nil,
                                                         unprotectedSitesHash: nil))]
    }

    static func testUpdate() -> ContentBlockerRulesManager.UpdateEvent {
        .init(rules: testRules(), changes: [:], completionTokens: [UUID().uuidString, UUID().uuidString])
    }

}

@MainActor
private final class SuspendedGeolocationEvaluation {
    enum Stage {
        case policy
        case currentDocument
        case completedPolicy
    }

    let stage: Stage
    let started: XCTestExpectation
    var currentDocumentEvaluationCount = 0
    var completion: (@MainActor @Sendable (Any?, Error?) -> Void)?

    init(stage: Stage, started: XCTestExpectation) {
        self.stage = stage
        self.started = started
    }

    var policy: [String: Any] {
        ["documentID": String(repeating: "c", count: 32),
         "isSecureContext": true, "isSandboxed": false, "isPolicyAllowed": true]
    }

    func complete() {
        let callback = completion
        completion = nil
        callback?(stage == .currentDocument ? String(repeating: "b", count: 32) : policy, nil)
    }
}

@MainActor
private final class SuspendedGeolocationWebView: WKWebView {
    var evaluation: SuspendedGeolocationEvaluation!

    override func loadHTMLString(_ string: String, baseURL: URL?) -> WKNavigation? { nil }

    override func __callAsyncJavaScript(_ functionBody: String,
                                        arguments: [String: Any]?,
                                        inFrame frame: WKFrameInfo?,
                                        in contentWorld: WKContentWorld,
                                        completionHandler: (@MainActor @Sendable (Any?, Error?) -> Void)?) {
        if evaluation.stage == .currentDocument {
            completionHandler?(evaluation.policy, nil)
        } else {
            evaluation.completion = completionHandler
            evaluation.started.fulfill()
        }
    }

    override func __evaluateJavaScript(_ javaScriptString: String,
                                       inFrame frame: WKFrameInfo?,
                                       in contentWorld: WKContentWorld,
                                       completionHandler: (@MainActor @Sendable (Any?, Error?) -> Void)?) {
        evaluation.currentDocumentEvaluationCount += 1
        if evaluation.stage == .currentDocument {
            evaluation.completion = completionHandler
            evaluation.started.fulfill()
        } else {
            completionHandler?(String(repeating: "b", count: 32), nil)
        }
    }
}

extension UserContentControllerNewContent {
    func rules(withName name: String) -> WKContentRuleList? { rulesUpdate.rules.first(where: { $0.name == name })?.rulesList }

    var isValid: Bool { rules(withName: "test") != nil }
}

extension WKContentRuleList {

    private static var isSwizzled = false
    private static let originalDealloc = { class_getInstanceMethod(WKContentRuleList.self, NSSelectorFromString("dealloc"))! }()
    private static let swizzledDealloc = { class_getInstanceMethod(WKContentRuleList.self, #selector(swizzled_dealloc))! }()

    static func swizzleDealloc() {
        guard !self.isSwizzled else { return }
        self.isSwizzled = true
        method_exchangeImplementations(originalDealloc, swizzledDealloc)
    }

    static func restoreDealloc() {
        guard self.isSwizzled else { return }
        self.isSwizzled = false
        method_exchangeImplementations(originalDealloc, swizzledDealloc)
    }

    @objc
    func swizzled_dealloc() { }

}
