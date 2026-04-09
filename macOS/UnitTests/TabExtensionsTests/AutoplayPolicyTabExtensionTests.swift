//
//  AutoplayPolicyTabExtensionTests.swift
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

import Combine
import FeatureFlags
import PrivacyConfig
import UserScript
import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser
@testable import Navigation

@MainActor
final class AutoplayPolicyTabExtensionTests: XCTestCase {

    private var mockPermissionManager: PermissionManagerMock!
    private var mockFeatureFlagger: MockFeatureFlagger!
    private var autoplayPreferences: AutoplayPreferences!
    private var persistor: AutoplayPreferencesPersistorMock!
    private var telemetryScriptSubject: PassthroughSubject<MockWebTelemetryScriptProvider, Never>!
    private var webView: WKWebView!

    override func setUp() {
        super.setUp()
        mockPermissionManager = PermissionManagerMock()
        mockFeatureFlagger = MockFeatureFlagger()
        persistor = AutoplayPreferencesPersistorMock(autoplayBlockingModeRawValue: AutoplayBlockingMode.blockAudio.rawValue)
        autoplayPreferences = AutoplayPreferences(persistor: persistor)
        telemetryScriptSubject = PassthroughSubject<MockWebTelemetryScriptProvider, Never>()
        telemetryScriptSubject.send(MockWebTelemetryScriptProvider())

        webView = WKWebView()
    }

    override func tearDown() {
        mockPermissionManager = nil
        mockFeatureFlagger = nil
        autoplayPreferences = nil
        persistor = nil
        telemetryScriptSubject = nil
        webView = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeExtension() -> AutoplayPolicyTabExtension {
        AutoplayPolicyTabExtension(
            autoplayPreferences: autoplayPreferences,
            featureFlagger: mockFeatureFlagger,
            permissionManager: mockPermissionManager,
            telemetryScriptPublisher: telemetryScriptSubject
        )
    }

    private func makeNavigationAction(url: URL) -> NavigationAction {
        let frame = FrameInfo(
            webView: webView,
            handle: FrameHandle(rawValue: 1),
            isMainFrame: true,
            url: url,
            securityOrigin: url.securityOrigin
        )
        return NavigationAction(
            request: URLRequest(url: url),
            navigationType: .other,
            currentHistoryItemIdentity: nil,
            redirectHistory: nil,
            isUserInitiated: false,
            sourceFrame: frame,
            targetFrame: frame,
            shouldDownload: false,
            mainFrameNavigation: nil
        )
    }

    // MARK: - Feature flag off

    func testWhenFeatureFlagOffThenDecidePolicyReturnsNextWithoutModifyingPreferences() async {
        mockFeatureFlagger.featuresStub[FeatureFlag.autoplayPolicy.rawValue] = false
        let ext = makeExtension()
        var prefs = NavigationPreferences.default

        let policy = await ext.decidePolicy(for: makeNavigationAction(url: URL(string: "https://example.com")!), preferences: &prefs)

        XCTAssertNil(policy, "Policy should be .next (nil) to pass to the next responder")
        XCTAssertNil(prefs.autoplayPolicy, "Preferences should not be modified when feature flag is off")
        XCTAssertFalse(prefs.mustApplyAutoplayPolicy, "mustApplyAutoplayPolicy should be false when feature flag is off")
    }

    // MARK: - No per-site override (falls back to global preferences)

    func testWhenNoPerSiteOverrideAndGlobalAllowAllThenPolicyIsAllow() async {
        mockFeatureFlagger.featuresStub[FeatureFlag.autoplayPolicy.rawValue] = true
        persistor.autoplayBlockingModeRawValue = AutoplayBlockingMode.allowAll.rawValue
        autoplayPreferences = AutoplayPreferences(persistor: persistor)
        let ext = makeExtension()
        var prefs = NavigationPreferences.default

        _ = await ext.decidePolicy(for: makeNavigationAction(url: URL(string: "https://example.com")!), preferences: &prefs)

        XCTAssertEqual(prefs.autoplayPolicy, .allow)
    }

    func testWhenNoPerSiteOverrideAndGlobalBlockAudioThenPolicyIsAllowWithoutSound() async {
        mockFeatureFlagger.featuresStub[FeatureFlag.autoplayPolicy.rawValue] = true
        persistor.autoplayBlockingModeRawValue = AutoplayBlockingMode.blockAudio.rawValue
        autoplayPreferences = AutoplayPreferences(persistor: persistor)
        let ext = makeExtension()
        var prefs = NavigationPreferences.default

        _ = await ext.decidePolicy(for: makeNavigationAction(url: URL(string: "https://example.com")!), preferences: &prefs)

        XCTAssertEqual(prefs.autoplayPolicy, .allowWithoutSound)
    }

    func testWhenNoPerSiteOverrideAndGlobalBlockAllThenPolicyIsDeny() async {
        mockFeatureFlagger.featuresStub[FeatureFlag.autoplayPolicy.rawValue] = true
        persistor.autoplayBlockingModeRawValue = AutoplayBlockingMode.blockAll.rawValue
        autoplayPreferences = AutoplayPreferences(persistor: persistor)
        let ext = makeExtension()
        var prefs = NavigationPreferences.default

        _ = await ext.decidePolicy(for: makeNavigationAction(url: URL(string: "https://example.com")!), preferences: &prefs)

        XCTAssertEqual(prefs.autoplayPolicy, .deny)
    }

    // MARK: - Per-site override stored

    func testWhenPerSiteAllowStoredThenPolicyIsAllow() async {
        mockFeatureFlagger.featuresStub[FeatureFlag.autoplayPolicy.rawValue] = true
        mockPermissionManager.setPermission(.allow, forDomain: "example.com", permissionType: .autoplayPolicy)
        let ext = makeExtension()
        var prefs = NavigationPreferences.default

        _ = await ext.decidePolicy(for: makeNavigationAction(url: URL(string: "https://example.com")!), preferences: &prefs)

        XCTAssertEqual(prefs.autoplayPolicy, .allow)
    }

    func testWhenPerSiteAskStoredThenPolicyIsAllowWithoutSound() async {
        mockFeatureFlagger.featuresStub[FeatureFlag.autoplayPolicy.rawValue] = true
        mockPermissionManager.setPermission(.ask, forDomain: "example.com", permissionType: .autoplayPolicy)
        let ext = makeExtension()
        var prefs = NavigationPreferences.default

        _ = await ext.decidePolicy(for: makeNavigationAction(url: URL(string: "https://example.com")!), preferences: &prefs)

        XCTAssertEqual(prefs.autoplayPolicy, .allowWithoutSound)
    }

    func testWhenPerSiteDenyStoredThenPolicyIsDeny() async {
        mockFeatureFlagger.featuresStub[FeatureFlag.autoplayPolicy.rawValue] = true
        mockPermissionManager.setPermission(.deny, forDomain: "example.com", permissionType: .autoplayPolicy)
        let ext = makeExtension()
        var prefs = NavigationPreferences.default

        _ = await ext.decidePolicy(for: makeNavigationAction(url: URL(string: "https://example.com")!), preferences: &prefs)

        XCTAssertEqual(prefs.autoplayPolicy, .deny)
    }

    // MARK: - Per-site override takes precedence over global

    func testWhenPerSiteDenyStoredAndGlobalAllowAllThenPolicyIsDeny() async {
        mockFeatureFlagger.featuresStub[FeatureFlag.autoplayPolicy.rawValue] = true
        persistor.autoplayBlockingModeRawValue = AutoplayBlockingMode.allowAll.rawValue
        autoplayPreferences = AutoplayPreferences(persistor: persistor)
        mockPermissionManager.setPermission(.deny, forDomain: "example.com", permissionType: .autoplayPolicy)
        let ext = makeExtension()
        var prefs = NavigationPreferences.default

        _ = await ext.decidePolicy(for: makeNavigationAction(url: URL(string: "https://example.com")!), preferences: &prefs)

        XCTAssertEqual(prefs.autoplayPolicy, .deny, "Per-site override should take precedence over global default")
    }

    // MARK: - mustApplyAutoplayPolicy

    func testWhenFeatureFlagOnThenMustApplyAutoplayPolicyIsTrue() async {
        mockFeatureFlagger.featuresStub[FeatureFlag.autoplayPolicy.rawValue] = true
        let ext = makeExtension()
        var prefs = NavigationPreferences.default

        _ = await ext.decidePolicy(for: makeNavigationAction(url: URL(string: "https://example.com")!), preferences: &prefs)

        XCTAssertTrue(prefs.mustApplyAutoplayPolicy)
    }

    // MARK: - Non-HTTP URLs fall back to global default

    func testWhenURLIsFileThenAutoplayPolicyIsNotApplied() async {
        mockFeatureFlagger.featuresStub[FeatureFlag.autoplayPolicy.rawValue] = true
        mockPermissionManager.setPermission(.allow, forDomain: "example.com", permissionType: .autoplayPolicy)
        let ext = makeExtension()
        var prefs = NavigationPreferences.default

        _ = await ext.decidePolicy(for: makeNavigationAction(url: URL(string: "file:///tmp/page.html")!), preferences: &prefs)

        XCTAssertNil(prefs.autoplayPolicy, "file:// URLs should not have an autoplay policy set")
        XCTAssertFalse(prefs.mustApplyAutoplayPolicy, "file:// URLs should not apply autoplay policy")
    }

    func testWhenURLIsAboutBlankThenAutoplayPolicyIsNotApplied() async {
        mockFeatureFlagger.featuresStub[FeatureFlag.autoplayPolicy.rawValue] = true
        let ext = makeExtension()
        var prefs = NavigationPreferences.default

        _ = await ext.decidePolicy(for: makeNavigationAction(url: URL(string: "about:blank")!), preferences: &prefs)

        XCTAssertNil(prefs.autoplayPolicy, "about:blank should not have an autoplay policy set")
        XCTAssertFalse(prefs.mustApplyAutoplayPolicy, "about:blank should not apply autoplay policy")
    }

    // MARK: - Per-site isolation (override for domain A does not leak to domain B)

    func testWhenPerSiteOverrideExistsForDifferentDomainThenFallsBackToGlobalDefault() async {
        mockFeatureFlagger.featuresStub[FeatureFlag.autoplayPolicy.rawValue] = true
        persistor.autoplayBlockingModeRawValue = AutoplayBlockingMode.blockAudio.rawValue
        autoplayPreferences = AutoplayPreferences(persistor: persistor)
        mockPermissionManager.setPermission(.allow, forDomain: "other.com", permissionType: .autoplayPolicy)
        let ext = makeExtension()
        var prefs = NavigationPreferences.default

        _ = await ext.decidePolicy(for: makeNavigationAction(url: URL(string: "https://example.com")!), preferences: &prefs)

        XCTAssertEqual(prefs.autoplayPolicy, .allowWithoutSound, "Per-site override for other.com should not affect example.com")
    }

    // MARK: - Return value

    func testDecidePolicyAlwaysReturnsNext() async {
        mockFeatureFlagger.featuresStub[FeatureFlag.autoplayPolicy.rawValue] = true
        let ext = makeExtension()
        var prefs = NavigationPreferences.default

        let policy = await ext.decidePolicy(for: makeNavigationAction(url: URL(string: "https://example.com")!), preferences: &prefs)

        XCTAssertNil(policy, "Policy should be .next (nil) to pass to the next responder")
    }

    // MARK: - Video playback detection

    func testWhenVideoPlaybackDetectedThenPublishedPropertyIsTrue() async {
        mockFeatureFlagger.featuresStub[FeatureFlag.autoplayPolicy.rawValue] = true
        let ext = makeExtension()
        let script = WebTelemetryUserScript()
        let payload = WebTelemetryUserScript.VideoPlaybackPayload(userInteraction: false)

        ext.webTelemetryUserScript(script, didDetectVideoPlayback: payload, in: webView)

        XCTAssertTrue(ext.videoPlaybackDetected)
    }

    func testWhenNavigationOccursThenVideoPlaybackDetectedResets() async {
        mockFeatureFlagger.featuresStub[FeatureFlag.autoplayPolicy.rawValue] = true
        let ext = makeExtension()
        let script = WebTelemetryUserScript()
        let payload = WebTelemetryUserScript.VideoPlaybackPayload(userInteraction: false)

        ext.webTelemetryUserScript(script, didDetectVideoPlayback: payload, in: webView)
        XCTAssertTrue(ext.videoPlaybackDetected)

        var prefs = NavigationPreferences.default
        _ = await ext.decidePolicy(for: makeNavigationAction(url: URL(string: "https://example.com")!), preferences: &prefs)

        XCTAssertFalse(ext.videoPlaybackDetected)
    }
}

private struct MockWebTelemetryScriptProvider: WebTelemetryUserScriptProvider {
    var webTelemetryScript = WebTelemetryUserScript()
}
