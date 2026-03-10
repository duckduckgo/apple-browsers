//
//  AIChatContextualWebViewControllerTests.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import AIChat
import BrowserServicesKit
import BrowserServicesKitTestsUtils
import Combine
import WebKit
@testable import Core
@testable import DuckDuckGo

final class AIChatContextualWebViewControllerTests: XCTestCase {

    // MARK: - Tests

    @MainActor
    func testWebViewUsesCustomUserAgent() {
        let expectedURL = URL(string: "https://duck.ai/chat")!
        let stubUserAgent = StubUserAgentManager(stubbedUserAgent: "ddg_ios/7.100.0 (com.duckduckgo; iOS 17.0)")

        let sut = AIChatContextualWebViewController(
            aiChatSettings: MockAIChatSettingsProvider(aiChatURL: expectedURL),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            contentBlockingAssetsPublisher: Empty().eraseToAnyPublisher(),
            featureDiscovery: MockFeatureDiscovery(),
            featureFlagger: MockFeatureFlagger(),
            downloadHandler: StubDownloadHandler(),
            getPageContext: nil,
            pixelHandler: StubContextualModePixelHandler(),
            userAgentManager: stubUserAgent
        )

        sut.loadViewIfNeeded()

        let webView = sut.view.firstSubview(ofType: WKWebView.self)
        XCTAssertNotNil(webView)
        XCTAssertEqual(webView?.customUserAgent, "ddg_ios/7.100.0 (com.duckduckgo; iOS 17.0)")
        XCTAssertEqual(stubUserAgent.capturedURL, expectedURL)
        XCTAssertEqual(stubUserAgent.capturedIsDesktop, false)
    }

    @MainActor
    func testWebViewUsesDefaultUserAgentManagerWhenNoneProvided() {
        let sut = AIChatContextualWebViewController(
            aiChatSettings: MockAIChatSettingsProvider(),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            contentBlockingAssetsPublisher: Empty().eraseToAnyPublisher(),
            featureDiscovery: MockFeatureDiscovery(),
            featureFlagger: MockFeatureFlagger(),
            downloadHandler: StubDownloadHandler(),
            getPageContext: nil,
            pixelHandler: StubContextualModePixelHandler()
        )

        sut.loadViewIfNeeded()

        let webView = sut.view.firstSubview(ofType: WKWebView.self)
        XCTAssertNotNil(webView)
        XCTAssertNotNil(webView?.customUserAgent)
        XCTAssertFalse(webView?.customUserAgent?.isEmpty ?? true)
    }
}

// MARK: - Helpers

private extension UIView {
    func firstSubview<T: UIView>(ofType type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T {
                return match
            }
            if let match = subview.firstSubview(ofType: type) {
                return match
            }
        }
        return nil
    }
}

// MARK: - Stubs

private final class StubUserAgentManager: UserAgentManaging {
    let stubbedUserAgent: String
    var capturedURL: URL?
    var capturedIsDesktop: Bool?

    init(stubbedUserAgent: String) {
        self.stubbedUserAgent = stubbedUserAgent
    }

    func extractAndSetDefaultUserAgent() async throws -> String { stubbedUserAgent }
    func setDefaultUserAgent(_ userAgent: String) {}
    func userAgent(isDesktop: Bool) -> String { stubbedUserAgent }

    func userAgent(isDesktop: Bool, url: URL?) -> String {
        capturedIsDesktop = isDesktop
        capturedURL = url
        return stubbedUserAgent
    }

    func update(request: inout URLRequest, isDesktop: Bool) {}
    func update(webView: WKWebView, isDesktop: Bool, url: URL?) {}
}

private final class StubDownloadHandler: NSObject, DownloadHandling {
    var onDownloadComplete: DownloadCompletionHandler?

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        return nil
    }
}

private final class StubContextualModePixelHandler: AIChatContextualModePixelFiring {
    func fireSheetOpened() {}
    func fireSheetDismissed() {}
    func fireSessionRestored() {}
    func fireExpandButtonTapped() {}
    func fireNewChatButtonTapped() {}
    func fireQuickActionSummarizeSelected() {}
    func firePageContextPlaceholderShown() {}
    func firePageContextPlaceholderTapped() {}
    func firePageContextAutoAttached() {}
    func firePageContextUpdatedOnNavigation(url: String) {}
    func firePageContextManuallyAttachedNative() {}
    func firePageContextManuallyAttachedFrontend() {}
    func firePageContextRemovedNative() {}
    func firePageContextRemovedFrontend() {}
    func firePageContextCollectionEmpty() {}
    func firePageContextCollectionUnavailable() {}
    func firePromptSubmittedWithContext() {}
    func firePromptSubmittedWithoutContext() {}
    func beginManualAttach() {}
    func endManualAttach() {}
    var isManualAttachInProgress: Bool { false }
    func reset() {}
}
