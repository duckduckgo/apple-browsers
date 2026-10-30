//
//  SponsorBlockSubfeatureTests.swift
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

import BrowserServicesKitTestsUtils
@_spi(Testing) import Persistence
import WebKit
import XCTest
@testable import BrowserServicesKit
@testable import UserScript

final class SponsorBlockSubfeatureTests: XCTestCase {

    private typealias Subfeature = SponsorBlockSubfeature

    private var preferences: SponsorBlockPreferences!
    private var isFeatureFlagOn = true

    override func setUp() {
        super.setUp()
        preferences = SponsorBlockPreferences(store: InMemoryKeyValueStore(), notificationCenter: NotificationCenter())
    }

    private func makeSubfeature(provider: SponsorBlockSegmentsProvider = SponsorBlockSegmentsProvider(load: { _ in
        XCTFail("Unexpected lookup")
        throw URLError(.badURL)
    })) -> Subfeature {
        Subfeature(segmentsProvider: provider, preferences: preferences, isFeatureFlagOn: { self.isFeatureFlagOn })
    }

    private func getSegments(_ subfeature: Subfeature, params: Any) async throws -> [SponsorBlockSegmentsProvider.Segment] {
        let handler = try XCTUnwrap(subfeature.handler(forMethodNamed: "getSegments"))
        let response = try await handler(params, WKScriptMessage.mock(name: "getSegments", body: [:]))
        return try XCTUnwrap(response as? Subfeature.GetSegmentsResponse).segments
    }

    private func getConfig(_ subfeature: Subfeature, webView: WKWebView? = nil) async throws -> Subfeature.ConfigResponse {
        let handler = try XCTUnwrap(subfeature.handler(forMethodNamed: "getConfig"))
        let response = try await handler([:], WKScriptMessage.mock(name: "getConfig", body: [:], webView: webView))
        return try XCTUnwrap(response as? Subfeature.ConfigResponse)
    }

    func testFeatureNameMatchesContentScopeScriptsFeature() {
        XCTAssertEqual(makeSubfeature().featureName, "sponsorBlock")
    }

    func testMessageOriginPolicyAllowsOnlyYouTubeAndDuckPlayerEmbed() {
        let policy = makeSubfeature().messageOriginPolicy
        XCTAssertTrue(policy.isAllowed("youtube.com"))
        XCTAssertTrue(policy.isAllowed("www.youtube.com"))
        XCTAssertTrue(policy.isAllowed("m.youtube.com"))
        XCTAssertTrue(policy.isAllowed("youtube-nocookie.com"))
        XCTAssertTrue(policy.isAllowed("www.youtube-nocookie.com"))
        XCTAssertFalse(policy.isAllowed("music.youtube.com"))
        XCTAssertFalse(policy.isAllowed("notyoutube.com"))
        XCTAssertFalse(policy.isAllowed("example.com"))
    }

    func testHandlerRouting() {
        let subfeature = makeSubfeature()
        XCTAssertNotNil(subfeature.handler(forMethodNamed: "getSegments"))
        XCTAssertNotNil(subfeature.handler(forMethodNamed: "getConfig"))
        XCTAssertNil(subfeature.handler(forMethodNamed: "log"))
        XCTAssertNil(subfeature.handler(forMethodNamed: "unknownMethod"))
    }

    // MARK: - getSegments

    @MainActor
    func testGetSegmentsResolvesToEmptyWhenLookupFails() async throws {
        let provider = SponsorBlockSegmentsProvider(load: { _ in throw URLError(.notConnectedToInternet) })
        let segments = try await getSegments(makeSubfeature(provider: provider), params: ["videoID": "dQw4w9WgXcQ"])
        XCTAssertEqual(segments, [])
    }

    @MainActor
    func testGetSegmentsAnswersEmptyWithoutLookupWhenFlagIsOff() async throws {
        isFeatureFlagOn = false
        let segments = try await getSegments(makeSubfeature(), params: ["videoID": "dQw4w9WgXcQ"])
        XCTAssertEqual(segments, [])
    }

    @MainActor
    func testGetSegmentsAnswersEmptyWithoutLookupWhenSettingIsOff() async throws {
        preferences.isEnabled = false
        let segments = try await getSegments(makeSubfeature(), params: ["videoID": "dQw4w9WgXcQ"])
        XCTAssertEqual(segments, [])
    }

    @MainActor
    func testGetSegmentsIgnoresCategoriesSentByThePage() async throws {
        let provider = SponsorBlockSegmentsProvider(load: { request in
            let url = request.url!.absoluteString
            XCTAssertTrue(url.contains("%22sponsor%22"), url)
            XCTAssertFalse(url.contains("selfpromo"), url)
            return (Data("[]".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        _ = try await getSegments(makeSubfeature(provider: provider), params: ["videoID": "dQw4w9WgXcQ", "categories": ["selfpromo"]])
    }

    @MainActor
    func testGetSegmentsWithBadParamsThrowsSoBrokerRepliesWithError() async throws {
        do {
            _ = try await getSegments(makeSubfeature(), params: ["videoID": "too-short"])
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Invalid getSegments param: videoID")
        }
    }

    // MARK: - getConfig

    @MainActor
    func testGetConfigReflectsFlagSettingAndSkipMode() async throws {
        let subfeature = makeSubfeature()
        let enabled = try await getConfig(subfeature)
        XCTAssertEqual(enabled, .init(enabled: true, skipMode: "manual", version: 1))

        preferences.skipMode = .auto
        let auto = try await getConfig(subfeature)
        XCTAssertEqual(auto, .init(enabled: true, skipMode: "auto", version: 1))

        preferences.isEnabled = false
        let settingOff = try await getConfig(subfeature)
        XCTAssertFalse(settingOff.enabled)

        preferences.isEnabled = true
        isFeatureFlagOn = false
        let flagOff = try await getConfig(subfeature)
        XCTAssertFalse(flagOff.enabled)
    }

    // MARK: - onConfigChanged

    @MainActor
    func testPreferenceChangePushesOneConfigUpdateToThePageThatAskedForConfig() async throws {
        let webView = PushCapturingWebView()
        let broker = UserScriptMessageBroker(context: "test")
        let subfeature = makeSubfeature()
        subfeature.with(broker: broker)
        _ = try await getConfig(subfeature, webView: webView)

        let pushed = expectation(description: "onConfigChanged pushed")
        webView.onEvaluate = { js in
            XCTAssertTrue(js.contains("onConfigChanged"), js)
            XCTAssertTrue(js.contains(#""skipMode":"auto""#), js)
            pushed.fulfill()
        }
        preferences.skipMode = .auto

        await fulfillment(of: [pushed], timeout: 1)
    }

    @MainActor
    func testPreferenceChangeBeforeGetConfigPushesNothing() async throws {
        let webView = PushCapturingWebView()
        webView.onEvaluate = { js in XCTFail("Unexpected push: \(js)") }
        let subfeature = makeSubfeature()
        subfeature.with(broker: UserScriptMessageBroker(context: "test"))

        preferences.skipMode = .auto
        await Task.yield()
        withExtendedLifetime((subfeature, webView)) {}
    }
}

private final class PushCapturingWebView: WKWebView {
    var onEvaluate: ((String) -> Void)?

    convenience init() {
        _ = WKWebView.swizzleEvaluateJavaScriptInContentWorldOnce
        self.init(frame: .zero, configuration: WKWebViewConfiguration())
    }
}

// `evaluateJavaScript:inFrame:inContentWorld:completionHandler:` is refined for Swift, so it cannot be overridden; swizzle it instead.
private extension WKWebView {

    static let swizzleEvaluateJavaScriptInContentWorldOnce: () = {
        let originalSelector = NSSelectorFromString("evaluateJavaScript:inFrame:inContentWorld:completionHandler:")
        guard let originalMethod = class_getInstanceMethod(WKWebView.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(WKWebView.self, #selector(swizzled_evaluateJavaScript(_:inFrame:inContentWorld:completionHandler:))) else {
            assertionFailure("Methods not available")
            return
        }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()

    @objc(swizzled_evaluateJavaScript:inFrame:inContentWorld:completionHandler:)
    dynamic func swizzled_evaluateJavaScript(_ javaScript: String,
                                             inFrame frame: WKFrameInfo?,
                                             inContentWorld contentWorld: WKContentWorld,
                                             completionHandler: ((Any?, Error?) -> Void)?) {
        if let capturing = self as? PushCapturingWebView {
            capturing.onEvaluate?(javaScript)
            return
        }
        swizzled_evaluateJavaScript(javaScript, inFrame: frame, inContentWorld: contentWorld, completionHandler: completionHandler) // original
    }
}
