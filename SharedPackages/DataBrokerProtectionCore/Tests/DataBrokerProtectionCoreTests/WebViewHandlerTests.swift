//
//  WebViewHandlerTests.swift
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

import BrowserServicesKit
import Common
import ConcurrencyExtensions
import DataBrokerProtectionCoreTestsUtils
import ImageIO
import PixelKit
import WebKit
import XCTest
@testable import DataBrokerProtectionCore

final class WebViewHandlerTests: XCTestCase {

#if DEBUG
    @MainActor
    func testActionSnapshotContainsTheRenderedPageAndPreservesTheViewport() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshots = DebugActionSnapshots(directory: directory)
        let bounds = CGRect(x: 0, y: 0, width: 128, height: 96)
        let webView = WKWebView(frame: bounds)
        let loaded = expectation(description: "Local page loaded")
        let delegate = SnapshotPageDelegate(loaded: loaded)
        webView.navigationDelegate = delegate
        defer { withExtendedLifetime(delegate) {} }
        webView.loadHTMLString("<html style='background:lime'><body style='height:3000px'></body></html>", baseURL: nil)
        await fulfillment(of: [loaded], timeout: 10)

        let name = await snapshots.capture(webView: webView, step: .scan, action: .extract, moment: .before)
        let url = try directory.appendingPathComponent(XCTUnwrap(name))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width * 3, image.height * 4)
        let pixel = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        pixel.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let rgba = try XCTUnwrap(pixel.data).assumingMemoryBound(to: UInt8.self)
        XCTAssertGreaterThan(rgba[1], 200)
        XCTAssertLessThan(rgba[0], 40)
        XCTAssertLessThan(rgba[2], 40)
    }
#endif

    @MainActor
    func testWhenWaitingForWebViewLoadAndTaskIsCancelled_thenThrowsCancelled() async throws {
        // Given
        let sut = try makeWebViewHandler()
        let loadTask = Task { @MainActor in
            try await sut.waitForWebViewLoad()
        }

        // When
        try await Task.sleep(interval: 0.01)
        loadTask.cancel()

        let result = await loadTask.result

        // Then
        switch result {
        case .success:
            XCTFail("Expected cancellation error")
        case .failure(let error):
            XCTAssertEqual(error as? DataBrokerProtectionError, .cancelled)
        }
    }

    @MainActor
    func testWhenWebContentProcessTerminatesWhileWaitingForWebViewLoad_thenThrowsExplicitError() async throws {
        // Given
        let sut = try makeWebViewHandler()
        let loadTask = Task { @MainActor in
            try await sut.waitForWebViewLoad()
        }

        // When
        try await Task.sleep(interval: 0.01)
        sut.webViewWebContentProcessDidTerminate(WKWebView())

        let result = await loadTask.result

        // Then
        switch result {
        case .success:
            XCTFail("Expected web content termination error")
        case .failure(let error):
            XCTAssertEqual(error as? DataBrokerProtectionError, .webContentProcessTerminated)
        }
    }

    @MainActor
    func testWhenWebContentProcessTerminatesDuringUserAssist_thenActionFails() async throws {
        let delegate = MockWebViewCommunicationDelegate()
        let sut = try makeWebViewHandler(delegate: delegate)
        await sut.initializeWebView(showWebView: false)
        let failed = expectation(description: "userAssist failed")
        delegate.onErrorHandler = { _ in failed.fulfill() }
        let profile = ProfileQuery(firstName: "", lastName: "", city: "", state: "", birthYear: 1970)
        sut.execute(action: UserAssistAction(id: "assist"), ofType: .optOut, data: .userData(profile, nil, nil, [:]))

        sut.webViewWebContentProcessDidTerminate(WKWebView())

        await fulfillment(of: [failed], timeout: 5)
        XCTAssertEqual(delegate.errors as? [DataBrokerProtectionError], [.webContentProcessTerminated])
    }

    @MainActor
    func testWhenCustomUserAgentIsProvided_thenWebViewUsesIt() async throws {
        let customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:142.0) Gecko/20100101 Firefox/142.0"
        let sut = try makeWebViewHandler(customUserAgent: customUserAgent)

        await sut.initializeWebView(showWebView: false)

        XCTAssertEqual(sut.webViewForTesting?.customUserAgent, customUserAgent)
    }

    @MainActor
    func testWhenCustomUserAgentIsNil_thenWebViewKeepsDefaultUserAgent() async throws {
        let sut = try makeWebViewHandler()

        await sut.initializeWebView(showWebView: false)

        let webView = try XCTUnwrap(sut.webViewForTesting)
        XCTAssertTrue(webView.customUserAgent?.isEmpty ?? true)
    }

    @MainActor
    private func makeWebViewHandler(
        delegate: CCFCommunicationDelegate = MockWebViewCommunicationDelegate(),
        customUserAgent: String? = nil,
        pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>? = nil
    ) throws -> DataBrokerProtectionWebViewHandler {
        try DataBrokerProtectionWebViewHandler(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: .mock,
            delegate: delegate,
            executionConfig: BrokerJobExecutionConfig(),
            shouldContinueActionHandler: { true },
            customUserAgent: customUserAgent,
            pixelHandler: pixelHandler
        )
    }
}

private final class MockWebViewCommunicationDelegate: CCFCommunicationDelegate {

    func loadURL(url: URL) {
    }

    func extractedProfiles(profiles: [ExtractedProfile], meta: [String: Any]?) async {
    }

    func captchaInformation(captchaInfo: GetCaptchaInfoResponse) {
    }

    func solveCaptcha(with response: SolveCaptchaResponse) async {
    }

    func success(actionId: String, actionType: ActionType) {
    }

    func conditionSuccess(actions: [Action]) async {
    }

    var errors: [Error] = []
    var onErrorHandler: ((Error) -> Void)?

    func onError(error: Error) {
        errors.append(error)
        onErrorHandler?(error)
    }
}

#if DEBUG
private final class SnapshotPageDelegate: NSObject, WKNavigationDelegate {
    let loaded: XCTestExpectation

    init(loaded: XCTestExpectation) {
        self.loaded = loaded
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded.fulfill()
    }
}
#endif
