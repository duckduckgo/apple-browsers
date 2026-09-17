//
//  AIChatTabExtensionTests.swift
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
import WebKit
import XCTest
@testable import Navigation
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class AIChatTabExtensionTests: XCTestCase {

    private var scriptsPublisher: PassthroughSubject<UserScripts, Never>!
    private var webViewPublisher: PassthroughSubject<WKWebView, Never>!
    private var openedURLs: [URL]!
    private var navigationPreferences: NavigationPreferences!

    override func setUpWithError() throws {
        try super.setUpWithError()
        scriptsPublisher = PassthroughSubject<UserScripts, Never>()
        webViewPublisher = PassthroughSubject<WKWebView, Never>()
        openedURLs = []
        navigationPreferences = NavigationPreferences(userAgent: "test", preferences: WKWebpagePreferences())
    }

    override func tearDown() {
        scriptsPublisher = nil
        webViewPublisher = nil
        openedURLs = nil
        navigationPreferences = nil
        super.tearDown()
    }

    private func makeExtension(aboutSchemeFixEnabled: Bool) -> AIChatTabExtension {
        let featureFlagger = MockFeatureFlagger(
            featuresStub: [FeatureFlag.aiChatSidebarAboutSchemeNavigationFix.rawValue: aboutSchemeFixEnabled]
        )
        return AIChatTabExtension(
            scriptsPublisher: scriptsPublisher.eraseToAnyPublisher(),
            webViewPublisher: webViewPublisher.eraseToAnyPublisher(),
            isLoadedInSidebar: true,
            isTabBurner: false,
            featureFlagger: featureFlagger,
            duckAiNativeStorageHandler: nil,
            burnerDuckAiStorageRegistry: nil,
            openNewTab: { [weak self] url in
                self?.openedURLs.append(url)
                return true
            }
        )
    }

    private func userInitiatedNavigation(to urlString: String) -> NavigationAction {
        let url = URL(string: urlString)!
        return NavigationAction(
            webView: WKWebView(),
            navigationAction: MockWKNavigationAction(
                request: URLRequest(url: url),
                targetFrame: WKFrameInfo.mock(url: url),
                sourceFrame: WKFrameInfo.mock(url: URL(string: "https://duck.ai/")!),
                isUserInitiated: true),
            currentHistoryItemIdentity: nil,
            redirectHistory: [],
            mainFrameNavigation: nil
        )
    }

    func testAboutSchemeNavigationIsAllowedInSidebarAndDoesNotOpenNewTab() async {
        // Regression test for #4358: about:srcdoc (an internal iframe navigation created by duck.ai
        // JS) must be allowed to proceed inside the sidebar, not opened in a new tab. Reverting the
        // about-scheme allow branch sends it to the new-tab fallback (.cancel + openNewTab).
        let sut = makeExtension(aboutSchemeFixEnabled: true)
        var prefs = navigationPreferences!

        let result = await sut.decidePolicy(for: userInitiatedNavigation(to: "about:srcdoc"), preferences: &prefs)

        XCTAssertNil(result, "about:srcdoc should be allowed to proceed in the sidebar (.next)")
        XCTAssertTrue(openedURLs.isEmpty, "about:srcdoc must not open a new tab")
    }

    func testNonAllowlistedHostOpensNewTabAndCancels() async {
        // Control: a normal cross-site navigation in the sidebar opens a new tab and cancels. This
        // proves the new-tab fallback actually fires in the test environment, so the `.next`
        // assertion above is meaningful (i.e. not passing merely because the fallback is a no-op).
        let sut = makeExtension(aboutSchemeFixEnabled: true)
        var prefs = navigationPreferences!

        let result = await sut.decidePolicy(for: userInitiatedNavigation(to: "https://example.com/"), preferences: &prefs)

        guard case .cancel? = result else {
            return XCTFail("Expected .cancel, got \(String(describing: result))")
        }
        XCTAssertEqual(openedURLs, [URL(string: "https://example.com/")!])
    }
}
