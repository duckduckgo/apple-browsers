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
import Network
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
                                                                          webExtensionAvailability: nil))
    }

    override static func setUp() {
        // WKContentRuleList uses native c++ _contentRuleList api object and calls ~ContentRuleList on dealloc
        // let it just leak
        WKContentRuleList.swizzleDealloc()
    }
    override static func tearDown() {
        WKContentRuleList.restoreDealloc()
    }

    func testWhenSitePermissionsConfigChangesThenSessionKeepsItsLaunchStateUntilRecreated() throws {
        let initialStates: [String?] = [nil, "disabled", "enabled"]
        for initialState in initialStates {
            let (base, manager, _) = try makeSessionFeatureFlaggerBase(sitePermissionsState: initialState)
            let session = SessionFeatureFlagger(base: base)
            let initiallyEnabled = initialState == "enabled"
            XCTAssertEqual(session.isFeatureOn(for: FeatureFlag.sitePermissions), initiallyEnabled)

            let nextStates: [String?] = ["enabled", nil, "disabled"]
            for nextState in nextStates {
                manager.privacyConfig = try makeSessionPrivacyConfiguration(sitePermissionsState: nextState)
                manager.updatesSubject.send()

                XCTAssertEqual(base.isFeatureOn(for: FeatureFlag.sitePermissions), nextState == "enabled")
                XCTAssertEqual(session.isFeatureOn(for: FeatureFlag.sitePermissions), initiallyEnabled)
                XCTAssertEqual(SessionFeatureFlagger(base: base).isFeatureOn(for: FeatureFlag.sitePermissions),
                               nextState == "enabled")
            }
        }
    }

    func testWhenSitePermissionsOverrideChangesThenBothOverrideModesKeepTheirSeparateLaunchValues() throws {
        for remoteEnabled in [false, true] {
            let (base, manager, overrides) = try makeSessionFeatureFlaggerBase(
                sitePermissionsState: remoteEnabled ? "enabled" : "disabled")
            overrides.toggleOverride(for: FeatureFlag.sitePermissions)
            let session = SessionFeatureFlagger(base: base)

            XCTAssertEqual(session.isFeatureOn(for: FeatureFlag.sitePermissions, allowOverride: true), !remoteEnabled)
            XCTAssertEqual(session.isFeatureOn(for: FeatureFlag.sitePermissions, allowOverride: false), remoteEnabled)

            overrides.clearOverride(for: FeatureFlag.sitePermissions)
            XCTAssertEqual(base.isFeatureOn(for: FeatureFlag.sitePermissions), remoteEnabled)
            XCTAssertEqual(session.isFeatureOn(for: FeatureFlag.sitePermissions, allowOverride: true), !remoteEnabled)

            manager.privacyConfig = try makeSessionPrivacyConfiguration(sitePermissionsState: remoteEnabled ? "disabled" : "enabled")
            manager.updatesSubject.send()
            XCTAssertEqual(base.isFeatureOn(for: FeatureFlag.sitePermissions, allowOverride: false), !remoteEnabled)
            XCTAssertEqual(session.isFeatureOn(for: FeatureFlag.sitePermissions, allowOverride: true), !remoteEnabled)
            XCTAssertEqual(session.isFeatureOn(for: FeatureFlag.sitePermissions, allowOverride: false), remoteEnabled)
        }
    }

    func testWhenOtherFlagsChangeThenSessionForwardsLiveValuesAndConfigAndOverrideUpdates() throws {
        let (base, manager, overrides) = try makeSessionFeatureFlaggerBase(sitePermissionsState: "enabled")
        let session = SessionFeatureFlagger(base: base)
        var updateCount = 0
        let subscription = session.updatesPublisher.sink { updateCount += 1 }
        defer { subscription.cancel() }
        XCTAssertFalse(session.isFeatureOn(for: FeatureFlag.promoPresentationCoordination))

        manager.privacyConfig = try makeSessionPrivacyConfiguration(sitePermissionsState: "disabled", promoEnabled: true)
        manager.updatesSubject.send()
        XCTAssertEqual(updateCount, 1)
        XCTAssertTrue(session.isFeatureOn(for: FeatureFlag.promoPresentationCoordination))
        XCTAssertTrue(session.isFeatureOn(for: FeatureFlag.sitePermissions))

        overrides.toggleOverride(for: FeatureFlag.promoPresentationCoordination)
        XCTAssertEqual(updateCount, 2)
        XCTAssertFalse(session.isFeatureOn(for: FeatureFlag.promoPresentationCoordination))
        XCTAssertTrue(session.isFeatureOn(for: FeatureFlag.promoPresentationCoordination, allowOverride: false))
        XCTAssertTrue(session.isFeatureOn(for: FeatureFlag.sitePermissions))
    }

    private func makeSessionFeatureFlaggerBase(sitePermissionsState: String?) throws
        -> (DefaultFeatureFlagger, PrivacyConfigurationManagerMock, FeatureFlagLocalOverrides) {
        let manager = PrivacyConfigurationManagerMock()
        manager.privacyConfig = try makeSessionPrivacyConfiguration(sitePermissionsState: sitePermissionsState)
        let internalUserDecider = PrivacyConfig.MockInternalUserDecider(isInternalUser: true)
        let overrides = FeatureFlagLocalOverrides(
            keyValueStore: InMemoryKeyValueStore(),
            actionHandler: FeatureFlagOverridesPublishingHandler<FeatureFlag>())

        // DefaultFeatureFlagger explicitly permits tests through this switch; restore the caller's environment after initialization.
        let previousMode = ProcessInfo.processInfo.environment["TESTS_FEATUREFLAGGER_MODE"]
        setenv("TESTS_FEATUREFLAGGER_MODE", "1", 1)
        defer {
            if let previousMode {
                setenv("TESTS_FEATUREFLAGGER_MODE", previousMode, 1)
            } else {
                unsetenv("TESTS_FEATUREFLAGGER_MODE")
            }
        }
        let base = DefaultFeatureFlagger(internalUserDecider: internalUserDecider,
                                        privacyConfigManager: manager,
                                        localOverrides: overrides,
                                        experimentManager: nil,
                                        for: FeatureFlag.self)
        return (base, manager, overrides)
    }

    private func makeSessionPrivacyConfiguration(sitePermissionsState: String?, promoEnabled: Bool = false) throws -> AppPrivacyConfiguration {
        var subfeatures: [String: Any] = ["promoPresentationCoordination": ["state": promoEnabled ? "enabled" : "disabled"]]
        if let sitePermissionsState {
            subfeatures["sitePermissions"] = ["state": sitePermissionsState]
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "features": [PrivacyFeature.iOSBrowserConfig.rawValue: ["state": "enabled", "features": subfeatures]]
        ])
        return AppPrivacyConfiguration(data: try PrivacyConfigurationData(data: data),
                                       identifier: "site-permissions-session-tests",
                                       localProtection: PrivacyConfigTestsUtils.MockDomainsProtectionStore(),
                                       internalUserDecider: PrivacyConfig.MockInternalUserDecider())
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
    func testWhenRequiredAssetsTimeOutThenNavigationCancelsOnceAndRefreshRetriesItsURL() async throws {
        let tab = TabViewController.fake(customWebView: { MockWebView(frame: .zero, configuration: $0) },
                                        featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.sitePermissions]),
                                        contentBlockingAssetsPublisher: updating.userContentBlockingAssets)
        tab.specialErrorPageNavigationHandler.delegate = nil
        defer { tab.prepareForDataClearing() }
        tab.sitePermissionsNavigationTimeout = 0.03
        let webView = try XCTUnwrap(tab.webView as? MockWebView)
        let failedURL = try XCTUnwrap(URL(string: "https://example.com/failed"))
        let frame = WKFrameInfo.mock(isMainFrame: true, securityOriginHost: "example.com", request: URLRequest(url: failedURL))
        let action = MockNavigationAction(request: URLRequest(url: failedURL), navigationType: .other, targetFrame: frame)
        let cancelled = expectation(description: "Timed-out navigation cancelled")
        cancelled.assertForOverFulfill = true
        var decisions = [WKNavigationActionPolicy]()
        tab.webView(webView, decidePolicyFor: action) { policy in
            decisions.append(policy)
            cancelled.fulfill()
        }
        await fulfillment(of: [cancelled], timeout: 1)
        XCTAssertEqual(decisions, [.cancel])
        XCTAssertTrue(tab.isError)
        XCTAssertEqual(tab.errorText, URLError(.timedOut).localizedDescription)
        XCTAssertEqual(tab.url, failedURL)
        XCTAssertTrue(tab.sitePermissionsState.contentBlockingWaitTasks.isEmpty)
        XCTAssertEqual(webView.loadCallCount, 0, "Timeout must not automatically retry")

        let controller = try XCTUnwrap(webView.configuration.userContentController as? UserContentController)
        let installed = expectation(description: "Late assets installed")
        let subscription = controller.$contentBlockingAssets.compactMap { $0 }.first().sink { _ in installed.fulfill() }
        rulesManager.updatesSubject.send(Self.testUpdate())
        await fulfillment(of: [installed], timeout: 10)
        subscription.cancel()
        XCTAssertEqual(decisions, [.cancel], "Late readiness must not resume a timed-out decision")
        XCTAssertTrue(tab.isError)
        XCTAssertEqual(webView.loadCallCount, 0)

        let retried = expectation(description: "Refresh retries attempted URL")
        webView.loadCompletionHandler = { retried.fulfill() }
        tab.refresh()
        await fulfillment(of: [retried], timeout: 1)
        XCTAssertEqual(webView.lastLoadedRequest?.url, failedURL)
        XCTAssertEqual(webView.loadCallCount, 1)
    }

    @MainActor
    func testWhenUnrelatedAssetsKeepArrivingThenTheyDoNotExtendTheGeolocationDeadline() async throws {
        let originalReleased = expectation(description: "Displaced content controller released")
        let replacementReleased = expectation(description: "Fixture content controller released after timeout")
        func exerciseTimeout() async throws {
            let assets = PassthroughSubject<NonGeolocationContent, Never>()
            let controller = UserContentController(assetsPublisher: assets, privacyConfigurationManager: configManager)
            controller.onDeinit { replacementReleased.fulfill() }
            let tab = TabViewController.fake(customWebView: { configuration in
                if let originalController = configuration.userContentController as? UserContentController {
                    originalController.onDeinit { originalReleased.fulfill() }
                    // Replacing the controller transfers its teardown responsibility to this fixture.
                    originalController.cleanUpBeforeClosing()
                } else {
                    XCTFail("Tab must install its content controller before creating the web view")
                }
                configuration.userContentController = controller
                return WKWebView(frame: .zero, configuration: configuration)
            }, featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.sitePermissions]))
            tab.specialErrorPageNavigationHandler.delegate = nil
            defer { tab.prepareForDataClearing() }
            tab.sitePermissionsNavigationTimeout = 0.3
            var installedCount = 0
            let installedSubscription = controller.$contentBlockingAssets.compactMap { $0 }.sink { _ in installedCount += 1 }
            let updates = Timer.publish(every: 0.02, on: .main, in: .common).autoconnect().sink { _ in
                assets.send(NonGeolocationContent())
            }
            defer {
                updates.cancel()
                installedSubscription.cancel()
            }
            let cancelled = expectation(description: "Nonready updates cannot postpone deadline")
            cancelled.assertForOverFulfill = true
            XCTAssertTrue(tab.shouldWaitUntilContentBlockingIsLoaded({ ready in
                XCTAssertFalse(ready)
                cancelled.fulfill()
            }, for: URL(string: "https://example.com")!))
            await fulfillment(of: [cancelled], timeout: 2)
            XCTAssertGreaterThan(installedCount, 1)
            XCTAssertTrue(tab.isError)
            XCTAssertTrue(tab.sitePermissionsState.contentBlockingWaitTasks.isEmpty)
        }
        try await exerciseTimeout()
        await fulfillment(of: [originalReleased, replacementReleased], timeout: 2)
    }

    @MainActor
    func testWhenMainFrameNavigationReplacesAWaitThenOnlyTheNewDecisionCanResume() async throws {
        let tab = TabViewController.fake(featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.sitePermissions]),
                                        contentBlockingAssetsPublisher: updating.userContentBlockingAssets)
        tab.specialErrorPageNavigationHandler.delegate = nil
        defer { tab.prepareForDataClearing() }
        tab.sitePermissionsNavigationTimeout = 0.25
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
        tab.webView(tab.webView, decidePolicyFor: action(path: "old")) { policy in
            oldDecisions.append(policy)
            cancelled.fulfill()
        }
        await Task.yield()
        tab.sitePermissionsNavigationTimeout = 10
        tab.webView(tab.webView, decidePolicyFor: action(path: "new")) { policy in
            newDecisions.append(policy)
            continued.fulfill()
        }
        await fulfillment(of: [cancelled], timeout: 1)
        XCTAssertEqual(oldDecisions, [.cancel])
        XCTAssertTrue(newDecisions.isEmpty)
        rulesManager.updatesSubject.send(Self.testUpdate())
        await fulfillment(of: [continued], timeout: 10)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(oldDecisions, [.cancel])
        XCTAssertEqual(newDecisions.count, 1)
        XCTAssertNotEqual(newDecisions.first, .cancel)
        XCTAssertFalse(tab.isError, "The cancelled deadline must not replace the new page with an error")
        XCTAssertTrue(tab.sitePermissionsState.contentBlockingWaitTasks.isEmpty)
    }

    @MainActor
    func testWhenExplicitLoadReplacesAWaitThenItCancelsBeforeTheNextPolicyDecision() async throws {
        let tab = TabViewController.fake(customWebView: { MockWebView(frame: .zero, configuration: $0) },
                                        featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.sitePermissions]))
        tab.specialErrorPageNavigationHandler.delegate = nil
        defer { tab.prepareForDataClearing() }
        tab.sitePermissionsNavigationTimeout = 0.25
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
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(decisions, [.cancel])
        XCTAssertEqual(webView.lastLoadedRequest?.url, replacementURL)
        XCTAssertEqual(tab.url, replacementURL)
        XCTAssertFalse(tab.isError, "The old deadline must not replace the new URL with a timeout page")
    }

    @MainActor
    func testWhenTabClosesDuringAssetWaitThenCancellationDoesNotPresentTimeoutError() async throws {
        let tab = TabViewController.fake(featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.sitePermissions]))
        tab.specialErrorPageNavigationHandler.delegate = nil
        defer { tab.prepareForDataClearing() }
        tab.sitePermissionsNavigationTimeout = 0.25
        let cancelled = expectation(description: "Teardown cancels the pending decision")
        cancelled.assertForOverFulfill = true
        XCTAssertTrue(tab.shouldWaitUntilContentBlockingIsLoaded({ ready in
            XCTAssertFalse(ready)
            cancelled.fulfill()
        }, for: URL(string: "https://example.com")!))
        await Task.yield()
        tab.closeSitePermissions()
        await fulfillment(of: [cancelled], timeout: 1)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(tab.isError)
        XCTAssertTrue(tab.sitePermissionsState.contentBlockingWaitTasks.isEmpty)
    }

    @MainActor
    func testWhenUserStopsDuringAssetWaitThenLateAssetsCannotResumeNavigationOrShowAnError() async throws {
        let controllerReleased = expectation(description: "Stopped navigation releases its content controller")
        func exerciseStop() async throws {
            let tab = TabViewController.fake(featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.sitePermissions]),
                                            contentBlockingAssetsPublisher: updating.userContentBlockingAssets)
            let controller = try XCTUnwrap(tab.webView.configuration.userContentController as? UserContentController)
            controller.onDeinit { controllerReleased.fulfill() }
            tab.specialErrorPageNavigationHandler.delegate = nil
            defer { tab.prepareForDataClearing() }
            tab.sitePermissionsNavigationTimeout = 0.25
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
            tab.stopLoading()
            await fulfillment(of: [cancelled], timeout: 1)
            XCTAssertEqual(decisions, [.cancel])

            let installed = expectation(description: "Assets arrive after Stop")
            let subscription = controller.$contentBlockingAssets.compactMap { $0 }.first().sink { _ in installed.fulfill() }
            rulesManager.updatesSubject.send(Self.testUpdate())
            await fulfillment(of: [installed], timeout: 10)
            subscription.cancel()
            try await Task.sleep(nanoseconds: 300_000_000)
            XCTAssertEqual(decisions, [.cancel])
            XCTAssertFalse(tab.isError)
            XCTAssertTrue(tab.sitePermissionsState.contentBlockingWaitTasks.isEmpty)
        }
        try await exerciseStop()
        await fulfillment(of: [controllerReleased], timeout: 2)
    }

    @MainActor
    func testWhenRemoteFlagChangesBeforeFirstAssetsThenNavigationStillWaitsForLaunchTimeScripts() async throws {
        let remoteFlagger = MockFeatureFlagger(enabledFeatureFlags: [.sitePermissions])
        let flagger = SessionFeatureFlagger(base: remoteFlagger)
        let tab = TabViewController.fake(featureFlagger: flagger,
                                        contentBlockingAssetsPublisher: updating.userContentBlockingAssets)
        tab.specialErrorPageNavigationHandler.delegate = nil
        defer { tab.prepareForDataClearing() }
        let config = try XCTUnwrap(tab.privacyConfigurationManager.privacyConfig as? PrivacyConfigurationMock)
        config.enabledFeaturesForVersions = [:]
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
        remoteFlagger.enabledFeatureFlags = []
        remoteFlagger.triggerUpdate()
        await Task.yield()
        XCTAssertTrue(decisions.isEmpty)
        XCTAssertTrue(flagger.isFeatureOn(.sitePermissions))

        rulesManager.updatesSubject.send(Self.testUpdate())
        await fulfillment(of: [resumed], timeout: 10)
        await pendingTask.value
        XCTAssertEqual(decisions, [true])
        XCTAssertNotNil((controller.contentBlockingAssets?.userScripts as? UserScripts)?.geolocationUserScript)
        XCTAssertTrue(tab.sitePermissionsState.contentBlockingWaitTasks.isEmpty)
    }

    @MainActor
    func testRemoteFlagChangesApplyToDocumentsOnlyAfterRelaunch() async throws {
        for initiallyEnabled in [false, true] {
            let remoteFlagger = MockFeatureFlagger(enabledFeatureFlags: initiallyEnabled ? [.sitePermissions] : [])
            let launchFlagger = SessionFeatureFlagger(base: remoteFlagger)
            remoteFlagger.enabledFeatureFlags = initiallyEnabled ? [] : [.sitePermissions]
            remoteFlagger.triggerUpdate()

            // New tabs in the current process keep the launch decision. A fresh app flagger adopts the update.
            for isRelaunch in [false, true] {
                let flagger = isRelaunch ? SessionFeatureFlagger(base: remoteFlagger) : launchFlagger
                let expectedEnabled = isRelaunch ? !initiallyEnabled : initiallyEnabled
                let tab = TabViewController.fake(featureFlagger: flagger,
                                                contentBlockingAssetsPublisher: updating.userContentBlockingAssets)
                tab.specialErrorPageNavigationHandler.delegate = nil
                defer { tab.prepareForDataClearing() }
                let controller = try XCTUnwrap(tab.webView.configuration.userContentController as? UserContentController)
                let navigationDelegate = MockWKNavigationDelegate()
                tab.webView.navigationDelegate = navigationDelegate

                let installed = expectation(description: "Scripts installed for launch state \(expectedEnabled)")
                let subscription = controller.$contentBlockingAssets.compactMap { $0 }.first()
                    .sink { _ in installed.fulfill() }
                rulesManager.updatesSubject.send(Self.testUpdate())
                await fulfillment(of: [installed], timeout: 10)
                subscription.cancel()
                let scripts = try XCTUnwrap(controller.contentBlockingAssets?.userScripts as? UserScripts)
                XCTAssertEqual(scripts.geolocationUserScript != nil, expectedEnabled)

                let loaded = expectation(description: "New document loaded")
                navigationDelegate.didFinishNavigation = { _, _ in loaded.fulfill() }
                tab.webView.loadHTMLString("<html><body>Launch-time geolocation</body></html>", baseURL: nil)
                await fulfillment(of: [loaded], timeout: 10)
                let hasShim: Bool? = try await tab.webView.evaluateJavaScript("typeof window.__ddgSitePermissionsGeolocation !== 'undefined'")
                XCTAssertEqual(hasShim, expectedEnabled)
                let hasPolicy = try await tab.webView.callAsyncJavaScript(
                    "return typeof globalThis.__ddgSitePermissionsGeolocationPolicy !== 'undefined';",
                    arguments: [:], in: nil, contentWorld: .defaultClient)
                XCTAssertEqual(hasPolicy as? Bool, expectedEnabled)
                let hasPagePolicy: Bool? = try await tab.webView.evaluateJavaScript(
                    "typeof globalThis.__ddgSitePermissionsGeolocationPolicy !== 'undefined'")
                XCTAssertEqual(hasPagePolicy, false)
            }
        }
    }

    @MainActor
    func testWhenRemoteFlagIsDisabledThenRestoredCachedDocumentStillRoutesGeolocationUntilRelaunch() async throws {
        // Use the same loopback HTTP fixture pattern as the package's WebKit tests so WebKit
        // can restore a real document from its back-forward cache instead of reloading HTML.
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        defer { listener.cancel() }
        let serverReady = expectation(description: "Loopback server listening")
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                serverReady.fulfill()
            case .failed(let error):
                XCTFail("Loopback server failed: \(error)")
                serverReady.fulfill()
            default:
                break
            }
        }
        let body = Data("""
        <html><body><script>
        window.testDocumentID = Math.random().toString(36);
        window.testRestoredFromCache = false;
        addEventListener('pageshow', event => { window.testRestoredFromCache = event.persisted; });
        </script></body></html>
        """.utf8)
        let headers = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        let response = Data(headers.utf8) + body
        let serverQueue = DispatchQueue(label: "ContentBlockingUpdatingTests.HTTPServer")
        listener.newConnectionHandler = { connection in
            connection.start(queue: serverQueue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { _, _, _, _ in
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: serverQueue)
        await fulfillment(of: [serverReady], timeout: 3)
        let port = try XCTUnwrap(listener.port)
        let pageA = try XCTUnwrap(URL(string: "http://localhost:\(port.rawValue)/a"))
        let pageB = try XCTUnwrap(URL(string: "http://localhost:\(port.rawValue)/b"))

        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.sitePermissions])
        let tab = TabViewController.fake(featureFlagger: SessionFeatureFlagger(base: flagger),
                                        contentBlockingAssetsPublisher: updating.userContentBlockingAssets)
        defer { tab.prepareForDataClearing() }
        let errorHandler = try XCTUnwrap(tab.specialErrorPageNavigationHandler as? DummySpecialErrorPageNavigationHandler)
        errorHandler.handlesNavigationResponse = false
        defer {
            errorHandler.delegate = nil
            tab.closeSitePermissions()
        }
        let store = SitePermissionsStore(storage: InMemoryKeyValueStore().keyedStoring())
        let dependencies = SitePermissionsDependencies(store: store, systemPermissionClient: SystemPermissionClient())
        tab.sitePermissionsDependenciesProvider = { dependencies }
        var promptCount = 0
        tab.sitePermissionsPromptHandlerOverride = { _, completion in
            promptCount += 1
            completion(.denyOnce)
        }

        let originalWindow = UIApplication.shared.firstKeyWindow
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = tab
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            originalWindow?.makeKey()
        }

        let controller = try XCTUnwrap(tab.webView.configuration.userContentController as? UserContentController)
        func waitForScripts(enabled: Bool, update: () -> Void) async {
            let installed = expectation(description: "Geolocation script enabled: \(enabled)")
            let subscription = controller.$contentBlockingAssets
                .compactMap { $0?.userScripts as? UserScripts }
                .filter { ($0.geolocationUserScript != nil) == enabled }
                .first()
                .sink { _ in installed.fulfill() }
            update()
            await fulfillment(of: [installed], timeout: 10)
            subscription.cancel()
        }
        func navigate(to url: URL, action: () -> WKNavigation?) async throws {
            let loaded = expectation(description: "Loaded \(url.path) through production navigation delegate")
            let observation = tab.webView.observe(\.isLoading, options: [.new]) { webView, _ in
                if !webView.isLoading, webView.url == url {
                    loaded.fulfill()
                }
            }
            defer { observation.invalidate() }
            XCTAssertTrue(tab.webView.navigationDelegate === tab)
            XCTAssertNotNil(action())
            await fulfillment(of: [loaded], timeout: 10)
            let readyState: String? = try await tab.webView.evaluateJavaScript("document.readyState")
            XCTAssertEqual(readyState, "complete")
        }

        await waitForScripts(enabled: true) { rulesManager.updatesSubject.send(Self.testUpdate()) }
        try await navigate(to: pageA) { tab.webView.load(URLRequest(url: pageA)) }
        let originalDocument: String? = try await tab.webView.evaluateJavaScript("window.testDocumentID")
        let originalShim: String? = try await tab.webView.evaluateJavaScript("window.__ddgSitePermissionsGeolocation?.documentID")
        XCTAssertNotNil(originalDocument)
        XCTAssertNotNil(originalShim)

        flagger.enabledFeatureFlags = []
        flagger.triggerUpdate()
        try await navigate(to: pageB) { tab.webView.load(URLRequest(url: pageB)) }
        let hasShim: Bool? = try await tab.webView.evaluateJavaScript("typeof window.__ddgSitePermissionsGeolocation !== 'undefined'")
        XCTAssertEqual(hasShim, true)

        try await navigate(to: pageA) { tab.webView.goBack() }
        let restoredDocument: String? = try await tab.webView.evaluateJavaScript("window.testDocumentID")
        let restoredShim: String? = try await tab.webView.evaluateJavaScript("window.__ddgSitePermissionsGeolocation?.documentID")
        let restoredFromCache: Bool? = try await tab.webView.evaluateJavaScript("window.testRestoredFromCache")
        XCTAssertEqual(restoredDocument, originalDocument)
        XCTAssertEqual(restoredShim, originalShim)
        XCTAssertEqual(restoredFromCache, true, "A fresh load would not exercise the cached document bridge")

        let state = try await tab.webView.callAsyncJavaScript("""
        return await Promise.race([
            navigator.permissions.query({ name: 'geolocation' }).then(status => status.state),
            new Promise(resolve => setTimeout(() => resolve('timeout'), 3000))
        ]);
        """, arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(state as? String, "prompt")
        let errorCode = try await tab.webView.callAsyncJavaScript("""
        return await new Promise(resolve => {
            const timer = setTimeout(() => resolve(-1), 3000);
            navigator.geolocation.getCurrentPosition(
                () => { clearTimeout(timer); resolve(0); },
                error => { clearTimeout(timer); resolve(error.code); }
            );
        });
        """, arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(errorCode as? Int, 1)
        XCTAssertEqual(promptCount, 1, "The restored document must reach the coordinator; denial prevents an OS prompt")
    }

    @MainActor
    func testWhenRemoteFlagChangesThenAssetsAndReloadNotificationsAreNotReplayed() async {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.sitePermissions])
        let tab = TabViewController.fake(featureFlagger: SessionFeatureFlagger(base: flagger),
                                        contentBlockingAssetsPublisher: updating.userContentBlockingAssets)
        tab.specialErrorPageNavigationHandler.delegate = nil
        defer { tab.prepareForDataClearing() }
        let initial = expectation(description: "Content update includes reload notification")
        let replayed = expectation(description: "Flag update must not replay assets")
        replayed.isInverted = true
        var updates = [ContentBlockerRulesManager.UpdateEvent]()
        let subscription = tab.makeTabContentBlockingAssetsPublisher(mediaCaptureUserScript: MediaCaptureUserScript())
            .sink { content in
                updates.append(content.rulesUpdate)
                if updates.count == 1 { initial.fulfill() } else { replayed.fulfill() }
            }
        let update = ContentBlockerRulesManager.UpdateEvent(rules: Self.testRules(),
                                                           changes: ["test": .unprotectedSites],
                                                           completionTokens: ["real-update"])
        rulesManager.updatesSubject.send(update)
        await fulfillment(of: [initial], timeout: 3)
        flagger.enabledFeatureFlags = []
        flagger.triggerUpdate()
        await fulfillment(of: [replayed], timeout: 0.1)
        subscription.cancel()
        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates[0].changes["test"], .unprotectedSites)
        XCTAssertEqual(updates[0].completionTokens, ["real-update"])
    }

    @MainActor
    func testGeolocationUserScriptRegistrationFollowsSitePermissionsFlag() async throws {
        let sourceProvider = makeScriptSourceProvider()
        let geolocationUserScript = GeolocationUserScript()

        let disabledScripts = UserScripts(
            with: sourceProvider,
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: []),
            geolocationUserScript: geolocationUserScript
        )
        XCTAssertNil(disabledScripts.geolocationUserScript)
        XCTAssertFalse(disabledScripts.userScripts.contains { $0 is GeolocationUserScript })
        XCTAssertFalse(disabledScripts.userScripts.contains { $0 is GeolocationPolicyUserScript })

        let enabledScripts = UserScripts(
            with: sourceProvider,
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.sitePermissions]),
            geolocationUserScript: geolocationUserScript
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

        let tabEnabledWithDifferentGlobalFlag = UserScripts(
            with: sourceProvider,
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: []),
            sitePermissionsEnabled: true,
            geolocationUserScript: geolocationUserScript
        )
        XCTAssertTrue(tabEnabledWithDifferentGlobalFlag.geolocationUserScript === geolocationUserScript)
        XCTAssertTrue(tabEnabledWithDifferentGlobalFlag.userScripts.contains { $0 === geolocationUserScript.policyScript })

        let tabDisabledWithDifferentGlobalFlag = UserScripts(
            with: sourceProvider,
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.sitePermissions]),
            sitePermissionsEnabled: false,
            geolocationUserScript: geolocationUserScript
        )
        XCTAssertNil(tabDisabledWithDifferentGlobalFlag.geolocationUserScript)
        XCTAssertFalse(tabDisabledWithDifferentGlobalFlag.userScripts.contains { $0 is GeolocationPolicyUserScript })

        let nonTabScripts = UserScripts(
            with: sourceProvider,
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.sitePermissions])
        )
        XCTAssertNil(nonTabScripts.geolocationUserScript)
        XCTAssertFalse(nonTabScripts.userScripts.contains { $0 is GeolocationUserScript })
        XCTAssertFalse(nonTabScripts.userScripts.contains { $0 is GeolocationPolicyUserScript })
    }

    @MainActor
    func testContentUpdatesRetainTheLaunchTimeScriptsAfterRemoteFlagChanges() {
        for initiallyEnabled in [false, true] {
            let remoteFlagger = MockFeatureFlagger(enabledFeatureFlags: initiallyEnabled ? [.sitePermissions] : [])
            let featureFlagger = SessionFeatureFlagger(base: remoteFlagger)
            let mediaCaptureUserScript = MediaCaptureUserScript()
            let geolocationUserScript = GeolocationUserScript()
            let contentSubject = PassthroughSubject<ContentBlockingUpdating.NewContent, Never>()
            var receivedScripts = [(MediaCaptureUserScript?, GeolocationUserScript?)]()
            let cancellable = TabViewController.sitePermissionsContentBlockingAssetsPublisher(
                contentSubject.eraseToAnyPublisher(),
                featureFlagger: featureFlagger,
                mediaCaptureUserScript: mediaCaptureUserScript,
                geolocationUserScript: geolocationUserScript
            ).sink { content in
                let scripts = content.makeUserScripts(content.sourceProvider)
                receivedScripts.append((scripts.mediaCaptureUserScript, scripts.geolocationUserScript))
            }

            for isFlagUpdate in [false, true] {
                if isFlagUpdate {
                    remoteFlagger.enabledFeatureFlags = initiallyEnabled ? [] : [.sitePermissions]
                    remoteFlagger.triggerUpdate()
                    XCTAssertEqual(receivedScripts.count, 1, "Flag updates do not rebuild assets")
                }
                contentSubject.send(.init(rulesUpdate: Self.testUpdate(),
                                          sourceProvider: makeScriptSourceProvider(),
                                          duckAiNativeStorageHandler: nil))
            }
            XCTAssertEqual(receivedScripts.count, 2)
            for (media, geolocation) in receivedScripts {
                XCTAssertTrue(media === mediaCaptureUserScript)
                XCTAssertTrue(geolocation === (initiallyEnabled ? geolocationUserScript : nil))
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
                                                         webExtensionAvailability: nil))
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

private struct NonGeolocationContent: UserContentControllerNewContent {
    let rulesUpdate = ContentBlockerRulesManager.UpdateEvent(rules: [], changes: [:], completionTokens: [])
    let sourceProvider: Void = ()
    var makeUserScripts: @MainActor (()) -> NonGeolocationScripts { { _ in NonGeolocationScripts() } }
}

@MainActor
private final class NonGeolocationScripts: UserScriptsProvider {
    var userScripts: [UserScript] { [] }
    func loadWKUserScripts() async -> [WKUserScript] { [] }
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
