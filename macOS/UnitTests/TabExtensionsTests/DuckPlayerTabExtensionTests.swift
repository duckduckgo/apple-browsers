//
//  DuckPlayerTabExtensionTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Combine
import WebKit
import BrowserServicesKit
@testable import Navigation

@testable import DuckDuckGo_Privacy_Browser

// Helper extension for creating test frames
extension WKFrameInfo {
    static func mock(url: URL) -> WKFrameInfo {
        return WKFrameInfoMock(
            webView: WKWebView(),
            securityOrigin: WKSecurityOriginMock.new(url: url),
            request: URLRequest(url: url),
            isMainFrame: true
        )
    }
}

final class MockWKNavigationAction: WKNavigationAction {
    private let mockRequest: URLRequest
    private let mockTargetFrame: WKFrameInfo?
    private let mockSourceFrame: WKFrameInfo

    init(request: URLRequest, targetFrame: WKFrameInfo?, sourceFrame: WKFrameInfo) {
        self.mockRequest = request
        self.mockTargetFrame = targetFrame
        self.mockSourceFrame = sourceFrame
        super.init()
    }

    override var request: URLRequest {
        return mockRequest
    }

    override var targetFrame: WKFrameInfo? {
        return mockTargetFrame
    }

    override var sourceFrame: WKFrameInfo {
        return mockSourceFrame
    }
}

@MainActor
final class DuckPlayerTabExtensionTests: XCTestCase {

    private var duckPlayer: DuckPlayer!
    private var preferences: DuckPlayerPreferences!
    private var webView: WKWebView!
    private var navigationAction: NavigationAction!
    private var tabExtension: DuckPlayerTabExtension!
    private var navigationPreferences: NavigationPreferences!

    override func setUpWithError() throws {
        try super.setUpWithError()

        // Setup DuckPlayer with enabled mode
        duckPlayer = DuckPlayer.mock(withMode: .enabled)

        // Setup preferences
        let preferencesPersistor = DuckPlayerPreferencesPersistorMock(
            duckPlayerMode: .enabled,
            duckPlayerOpenInNewTab: false
        )
        preferences = DuckPlayerPreferences(persistor: preferencesPersistor)

        // Setup webView
        webView = WKWebView()

        // Setup tab extension
        let scriptsPublisher = PassthroughSubject<UserScripts, Never>()
        let webViewPublisher = PassthroughSubject<WKWebView, Never>()
        let onboardingDecider = DefaultDuckPlayerOnboardingDecider()

        tabExtension = DuckPlayerTabExtension(
            duckPlayer: duckPlayer,
            isBurner: false,
            scriptsPublisher: scriptsPublisher.eraseToAnyPublisher(),
            webViewPublisher: webViewPublisher.eraseToAnyPublisher(),
            preferences: preferences,
            onboardingDecider: onboardingDecider
        )

        navigationPreferences = NavigationPreferences(
            userAgent: "test",
            preferences: WKWebpagePreferences()
        )

    }

    override func tearDown() {
        duckPlayer = nil
        preferences = nil
        tabExtension = nil
        webView = nil
    }

    func testNavigatingWhenNavigatingFromDuckPlayerToSameVideo_DisablesDuckPlayerForNextVideo() async {
        // Setup
        preferences.duckPlayerMode = .enabled

        // Simulate navigating to DuckPlayer
        navigationAction = NavigationAction(
            webView: webView,
            navigationAction: MockWKNavigationAction(request: URLRequest(url: URL(string: "duck://player/test123")!),
                                                     targetFrame: nil,
                                                     sourceFrame: WKFrameInfo.mock(url: URL(string: "duck://player/test123")!)),
            currentHistoryItemIdentity: nil,
            redirectHistory: [],
            mainFrameNavigation: nil
        )

        var prefs = navigationPreferences!
        let result = await tabExtension.decidePolicy(for: navigationAction, preferences: &prefs)

        XCTAssertNotNil(result)
        if case .allow = result { } else {
            XCTFail("Expected .allow but got \(String(describing: result))")
        }

        // When

        // Now navigate to the same video in youtube, to simulate "Watch in Youtube"
        navigationAction = NavigationAction(
            webView: webView,
            navigationAction: MockWKNavigationAction(request: URLRequest(url: URL(string: "https://www.youtube.com/watch?v=HdTCDxX-UnQ")!),
                                                     targetFrame: WKFrameInfo.mock(url: URL(string: "duck://player/HdTCDxX-UnQ")!),
                                                     sourceFrame: WKFrameInfo.mock(url: URL(string: "https://www.youtube.com/watch?v=HdTCDxX-UnQ")!)),
            currentHistoryItemIdentity: nil,
            redirectHistory: [],
            mainFrameNavigation: nil
        )

        _ = await tabExtension.decidePolicy(for: navigationAction, preferences: &prefs)

        // Then
        XCTAssertTrue(duckPlayer.shouldOpenNextVideoOnYoutube)

    }

}
