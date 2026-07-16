//
//  NavigationPixelNavigationResponderTests.swift
//  DuckDuckGo
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
import PixelKit
import PrivacyDashboard
import WebKit
import XCTest
@testable import DuckDuckGo

/// Class double for `SiteLoadingNavigation`. Avoids `WKNavigation()`, whose direct-init deinit crashes.
private final class MockNavigation: SiteLoadingNavigation {
    var siteLoadingStartTime: Date?
    var siteLoadingNavigationType: String?
}

final class NavigationPixelNavigationResponderTests: XCTestCase {

    private var firedPixels: [(name: String, params: [String: String])] = []
    private var isErrorPageReload = false
    private var isLoadingErrorPage = false
    private var sut: NavigationPixelNavigationResponder!

    /// Use 100% sampling in tests to make pixel firing deterministic.
    private let testSamplePercentage = 100
    private var expectedSampleSuffix: String { "_sample\(testSamplePercentage)" }

    override func setUp() {
        super.setUp()
        firedPixels = []
        isErrorPageReload = false
        isLoadingErrorPage = false

        let defaults = UserDefaults(suiteName: "test_\(UUID().uuidString)")!
        PixelKit.setUp(
            dryRun: false,
            appVersion: "1.0.0",
            session: "test",
            defaultHeaders: [:],
            defaults: defaults
        ) { [weak self] firedPixelName, _, firedParameters, _, _, completion in
            self?.firedPixels.append((firedPixelName, firedParameters))
            completion(true, nil)
        }

        sut = NavigationPixelNavigationResponder(
            samplePercentage: testSamplePercentage,
            isErrorPageReload: { [weak self] _ in self?.isErrorPageReload ?? false },
            isLoadingErrorPage: { [weak self] _ in self?.isLoadingErrorPage ?? false }
        )
    }

    override func tearDown() {
        PixelKit.tearDown()
        sut = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func mainFrameAction(_ type: WKNavigationType = .linkActivated, urlString: String = "https://example.com") -> MockNavigationAction {
        let url = URL(string: urlString)!
        return MockNavigationAction(
            request: URLRequest(url: url),
            navigationType: type,
            targetFrame: WKFrameInfo.mock(isMainFrame: true, securityOriginHost: url.host ?? "example.com")
        )
    }

    private func subFrameAction(_ type: WKNavigationType = .linkActivated) -> MockNavigationAction {
        let url = URL(string: "https://example.com/sub")!
        return MockNavigationAction(
            request: URLRequest(url: url),
            navigationType: type,
            targetFrame: WKFrameInfo.mock(isMainFrame: false, securityOriginHost: "example.com")
        )
    }

    // MARK: - Happy paths

    func test_willStart_didStart_didFinish_firesSiteLoadingSuccess() {
        let nav = MockNavigation()

        sut.willStart(mainFrameAction(.linkActivated))
        sut.didStart(nav)
        sut.didFinish(nav)

        XCTAssertEqual(firedPixels.count, 1)
        XCTAssertEqual(firedPixels.first?.name, "m_site_loading_success" + expectedSampleSuffix)
        XCTAssertEqual(firedPixels.first?.params["navigation_type"], "linkActivated")
    }

    func test_willStart_didStart_didFail_firesSiteLoadingFailure() {
        let nav = MockNavigation()
        let error = NSError(domain: "TestDomain", code: 42, userInfo: nil)

        sut.willStart(mainFrameAction(.reload))
        sut.didStart(nav)
        sut.didFail(nav, error: error)

        XCTAssertEqual(firedPixels.count, 1)
        XCTAssertEqual(firedPixels.first?.name, "m_site_loading_failure" + expectedSampleSuffix)
        XCTAssertEqual(firedPixels.first?.params["navigation_type"], "reload")
        // PixelKit emits the error as the short query-string keys defined in `PixelKit.Parameters`.
        XCTAssertEqual(firedPixels.first?.params[PixelKit.Parameters.errorCode], "42")
        XCTAssertEqual(firedPixels.first?.params[PixelKit.Parameters.errorDomain], "TestDomain")
    }

    // MARK: - Sub-frame is ignored

    func test_subFrameWillStart_isIgnored() {
        let nav = MockNavigation()

        sut.willStart(subFrameAction(.linkActivated))
        sut.didStart(nav)
        sut.didFinish(nav)

        XCTAssertTrue(firedPixels.isEmpty)
    }

    // MARK: - Error-page short-circuits

    func test_willStart_whenLoadingErrorPage_doesNotFire() {
        isLoadingErrorPage = true
        let nav = MockNavigation()

        sut.willStart(mainFrameAction(.other))
        sut.didStart(nav)
        sut.didFinish(nav)

        XCTAssertTrue(firedPixels.isEmpty)
    }

    func test_willStart_whenOnErrorPage_otherNavigationDoesNotFire() {
        // Mirrors macOS's `case .other where targetFrame?.url == .error` — error-page reload buttons surface
        // as `.other`, not `.reload`, so the gate keys off the page state instead of the type alone.
        isErrorPageReload = true
        let nav = MockNavigation()

        sut.willStart(mainFrameAction(.other))
        sut.didStart(nav)
        sut.didFinish(nav)

        XCTAssertTrue(firedPixels.isEmpty)
    }

    func test_willStart_whenOnErrorPage_userInitiatedNavigationStillFires() {
        // `.linkActivated` is an explicit user action even from an error page — should fire.
        isErrorPageReload = true
        let nav = MockNavigation()

        sut.willStart(mainFrameAction(.linkActivated))
        sut.didStart(nav)
        sut.didFinish(nav)

        XCTAssertEqual(firedPixels.count, 1)
        XCTAssertEqual(firedPixels.first?.name, "m_site_loading_success" + expectedSampleSuffix)
        XCTAssertEqual(firedPixels.first?.params["navigation_type"], "linkActivated")
    }

    // MARK: - Missing-state behavior

    func test_didStart_withoutPriorWillStart_doesNotFire() {
        let nav = MockNavigation()

        sut.didStart(nav)
        sut.didFinish(nav)

        XCTAssertTrue(firedPixels.isEmpty)
    }

    func test_didFinish_clearsState_secondDidFinishDoesNotRefire() {
        let nav = MockNavigation()

        sut.willStart(mainFrameAction(.linkActivated))
        sut.didStart(nav)
        sut.didFinish(nav)
        sut.didFinish(nav) // re-entry; state should be cleared

        XCTAssertEqual(firedPixels.count, 1)
    }

    func test_didFail_clearsState_secondCallbackDoesNotRefire() {
        let nav = MockNavigation()
        let error = NSError(domain: "TestDomain", code: 1, userInfo: nil)

        sut.willStart(mainFrameAction(.linkActivated))
        sut.didStart(nav)
        sut.didFail(nav, error: error)
        sut.didFinish(nav) // both didFail and didFinish should never produce two pixels

        XCTAssertEqual(firedPixels.count, 1)
        XCTAssertEqual(firedPixels.first?.name, "m_site_loading_failure" + expectedSampleSuffix)
    }
}
