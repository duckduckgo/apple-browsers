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
import Core
import TrackerRadarKit
import BrowserServicesKit
import BrowserServicesKitTestsUtils
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

    func testWhenGeolocationScriptsDoNotMatchFlagThenNavigationWaitsIncludingSERP() {
        for isSERP in [false, true] {
            for isEnabled in [false, true] {
                XCTAssertTrue(TabViewController.shouldWaitForContentBlockingAssets(
                    assetsInstalled: true,
                    contentBlockingEnabled: false,
                    sitePermissionsEnabled: isEnabled,
                    geolocationScriptInstalled: !isEnabled,
                    isDuckDuckGoSearch: isSERP
                ))
                XCTAssertFalse(TabViewController.shouldWaitForContentBlockingAssets(
                    assetsInstalled: true,
                    contentBlockingEnabled: true,
                    sitePermissionsEnabled: isEnabled,
                    geolocationScriptInstalled: isEnabled,
                    isDuckDuckGoSearch: isSERP
                ))
            }
        }
        XCTAssertFalse(TabViewController.shouldWaitForContentBlockingAssets(
            assetsInstalled: false,
            contentBlockingEnabled: true,
            sitePermissionsEnabled: false,
            geolocationScriptInstalled: false,
            isDuckDuckGoSearch: true
        ))
        XCTAssertTrue(TabViewController.shouldWaitForContentBlockingAssets(
            assetsInstalled: false,
            contentBlockingEnabled: false,
            sitePermissionsEnabled: true,
            geolocationScriptInstalled: false,
            isDuckDuckGoSearch: true
        ))
    }

    @MainActor
    func testWhenFlagChangesWithoutContentUpdateThenNextDocumentUsesMatchingGeolocationAPI() async throws {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.sitePermissions])
        let tab = TabViewController.fake(featureFlagger: flagger,
                                        contentBlockingAssetsPublisher: updating.userContentBlockingAssets)
        defer { tab.prepareForDataClearing() }
        let controller = try XCTUnwrap(tab.webView.configuration.userContentController as? UserContentController)
        let navigationDelegate = MockWKNavigationDelegate()
        tab.webView.navigationDelegate = navigationDelegate

        for isEnabled in [true, false, true] {
            let installed = expectation(description: "Scripts installed with flag \(isEnabled)")
            let subscription = controller.$contentBlockingAssets
                .compactMap { $0?.userScripts as? UserScripts }
                .filter { ($0.geolocationUserScript != nil) == isEnabled }
                .first()
                .sink { _ in installed.fulfill() }
            flagger.enabledFeatureFlags = isEnabled ? [.sitePermissions] : []
            flagger.triggerUpdate()
            if controller.contentBlockingAssets == nil {
                rulesManager.updatesSubject.send(Self.testUpdate())
            }
            await fulfillment(of: [installed], timeout: 10)
            subscription.cancel()

            let loaded = expectation(description: "New document loaded")
            navigationDelegate.didFinishNavigation = { _, _ in loaded.fulfill() }
            tab.webView.loadHTMLString("<html><body>Geolocation rollback</body></html>", baseURL: nil)
            await fulfillment(of: [loaded], timeout: 10)
            let hasShim: Bool? = try await tab.webView.evaluateJavaScript("typeof window.__ddgSitePermissionsGeolocation !== 'undefined'")
            XCTAssertEqual(hasShim, isEnabled)
        }
    }

    @MainActor
    func testWhenFlagChangesThenPreviousReloadNotificationIsNotReplayed() async {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.sitePermissions])
        let tab = TabViewController.fake(featureFlagger: flagger,
                                        contentBlockingAssetsPublisher: updating.userContentBlockingAssets)
        defer { tab.prepareForDataClearing() }
        let initial = expectation(description: "Content update includes reload notification")
        let refreshed = expectation(description: "Flag refresh omits old notification")
        var updates = [ContentBlockerRulesManager.UpdateEvent]()
        let subscription = tab.makeTabContentBlockingAssetsPublisher(mediaCaptureUserScript: MediaCaptureUserScript())
            .sink { content in
                updates.append(content.rulesUpdate)
                if updates.count == 1 { initial.fulfill() }
                if updates.count == 2 { refreshed.fulfill() }
            }
        let update = ContentBlockerRulesManager.UpdateEvent(rules: Self.testRules(),
                                                           changes: ["test": .unprotectedSites],
                                                           completionTokens: ["real-update"])
        rulesManager.updatesSubject.send(update)
        await fulfillment(of: [initial], timeout: 3)
        flagger.enabledFeatureFlags = []
        flagger.triggerUpdate()
        await fulfillment(of: [refreshed], timeout: 3)
        subscription.cancel()
        XCTAssertEqual(updates[0].changes["test"], .unprotectedSites)
        XCTAssertEqual(updates[0].completionTokens, ["real-update"])
        XCTAssertTrue(updates[1].changes.isEmpty)
        XCTAssertTrue(updates[1].completionTokens.isEmpty)
    }

    @MainActor
    func testGeolocationUserScriptRegistrationFollowsSitePermissionsFlag() {
        let sourceProvider = makeScriptSourceProvider()

        let disabledScripts = UserScripts(
            with: sourceProvider,
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [])
        )
        XCTAssertNil(disabledScripts.geolocationUserScript)
        XCTAssertFalse(disabledScripts.userScripts.contains { $0 is GeolocationUserScript })

        let geolocationUserScript = GeolocationUserScript()
        let enabledScripts = UserScripts(
            with: sourceProvider,
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.sitePermissions]),
            geolocationUserScript: geolocationUserScript
        )
        XCTAssertTrue(enabledScripts.geolocationUserScript === geolocationUserScript)
        XCTAssertTrue(enabledScripts.userScripts.contains { ($0 as? GeolocationUserScript) === geolocationUserScript })

        let tabEnabledWithDifferentGlobalFlag = UserScripts(
            with: sourceProvider,
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: []),
            sitePermissionsEnabled: true,
            geolocationUserScript: geolocationUserScript
        )
        XCTAssertTrue(tabEnabledWithDifferentGlobalFlag.geolocationUserScript === geolocationUserScript)

        let tabDisabledWithDifferentGlobalFlag = UserScripts(
            with: sourceProvider,
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.sitePermissions]),
            sitePermissionsEnabled: false,
            geolocationUserScript: geolocationUserScript
        )
        XCTAssertNil(tabDisabledWithDifferentGlobalFlag.geolocationUserScript)

        let nonTabScripts = UserScripts(
            with: sourceProvider,
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.sitePermissions])
        )
        XCTAssertNil(nonTabScripts.geolocationUserScript)
        XCTAssertFalse(nonTabScripts.userScripts.contains { $0 is GeolocationUserScript })
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
