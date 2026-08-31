//
//  GeolocationUserScriptWebKitTests.swift
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

import Network
import WebKit
import XCTest
@testable import SitePermissions

@MainActor
final class GeolocationUserScriptWebKitTests: XCTestCase {

    func testDisabledRegistrationLeavesNativePageAPIUntouched() async throws {
        let script = GeolocationUserScript()
        let harness = makeHarness(script: script)

        try await harness.load(nativeAPICaptureHTML)
        try await waitUntil(in: harness.webView, expression: "window.pageStart !== undefined")

        let state = try await javaScriptDictionary(in: harness.webView, body: """
        return {
            markerInstalled: Boolean(window.__ddgSitePermissionsGeolocation),
            geolocationUnchanged: window.pageStart.geolocation === navigator.geolocation,
            getCurrentPositionUnchanged: window.pageStart.getCurrentPosition === navigator.geolocation.getCurrentPosition,
            permissionsQueryUnchanged: window.pageStart.permissionsQuery === navigator.permissions.query
        };
        """)

        XCTAssertEqual(state["markerInstalled"] as? Bool, false)
        XCTAssertEqual(state["geolocationUnchanged"] as? Bool, true)
        XCTAssertEqual(state["getCurrentPositionUnchanged"] as? Bool, true)
        XCTAssertEqual(state["permissionsQueryUnchanged"] as? Bool, true)
    }

    func testEnabledRegistrationInstallsShimInThePageWorld() async throws {
        let script = GeolocationUserScript(installImmediately: true)
        script.activationHandler = { _ in true }
        let harness = makeHarness(script: script)

        try await harness.load(nativeAPICaptureHTML)
        try await waitUntil(in: harness.webView, expression: "Boolean(window.__ddgSitePermissionsGeolocation)")

        let state = try await javaScriptDictionary(in: harness.webView, body: """
        return {
            markerInstalled: Boolean(window.__ddgSitePermissionsGeolocation),
            installedBeforePageScript: window.pageStart.geolocation === navigator.geolocation &&
                                       window.pageStart.getCurrentPosition === navigator.geolocation.getCurrentPosition &&
                                       window.pageStart.permissionsQuery === navigator.permissions.query
        };
        """)

        XCTAssertEqual(state["markerInstalled"] as? Bool, true)
        XCTAssertEqual(state["installedBeforePageScript"] as? Bool, true)
    }

    func testDeletionAndDirectPrototypeCallsCannotRecoverNativeAPI() async throws {
        let delegate = WebKitTestGeolocationDelegate()
        let script = GeolocationUserScript(delegate: delegate, installImmediately: true)
        script.activationHandler = { _ in true }
        let harness = makeHarness(script: script)
        let server = try await WebKitLoopbackHTTPServer.start(html: "<html><body></body></html>")
        defer { server.stop() }

        try await harness.load(try XCTUnwrap(server.url))
        try await waitUntil(in: harness.webView, expression: "Boolean(window.__ddgSitePermissionsGeolocation)")

        let state = try await javaScriptDictionary(in: harness.webView, body: """
        const geolocation = navigator.geolocation;
        const navigatorPrototypeGeolocation = Navigator.prototype.geolocation;
        const permissions = navigator.permissions;
        const permissionsPrototype = Object.getPrototypeOf(permissions);
        const getCurrentPosition = geolocation.getCurrentPosition;
        const permissionsQuery = permissions.query;

        const navigatorDeleted = Reflect.deleteProperty(navigator, "geolocation");
        const navigatorPrototypeDeleted = Reflect.deleteProperty(Navigator.prototype, "geolocation");
        const permissionsDeleted = Reflect.deleteProperty(permissions, "query");
        const permissionsPrototypeDeleted = Reflect.deleteProperty(permissionsPrototype, "query");

        const positionResult = await new Promise((resolve) => {
            navigatorPrototypeGeolocation.getCurrentPosition.call(
                geolocation,
                (position) => resolve({ status: "success", position }),
                (error) => resolve({ status: "error", error })
            );
        });
        const permission = await permissionsPrototype.query.call(permissions, { name: "geolocation" });

        return {
            navigatorDeleted,
            navigatorPrototypeDeleted,
            permissionsDeleted,
            permissionsPrototypeDeleted,
            geolocationStillShimmed: navigator.geolocation === geolocation && navigator.geolocation.getCurrentPosition === getCurrentPosition,
            navigatorPrototypeStillShimmed: Navigator.prototype.geolocation === geolocation,
            permissionsStillShimmed: navigator.permissions.query === permissionsQuery,
            positionStatus: positionResult.status,
            positionErrorCode: positionResult.error?.code ?? 0,
            isSecureContext: globalThis.isSecureContext,
            origin: globalThis.origin,
            latitude: positionResult.position?.coords.latitude ?? 0,
            longitude: positionResult.position?.coords.longitude ?? 0,
            permissionState: permission.state
        };
        """)

        XCTAssertEqual(state["navigatorDeleted"] as? Bool, false)
        XCTAssertEqual(state["navigatorPrototypeDeleted"] as? Bool, false)
        XCTAssertEqual(state["permissionsDeleted"] as? Bool, false)
        XCTAssertEqual(state["permissionsPrototypeDeleted"] as? Bool, false)
        XCTAssertEqual(state["geolocationStillShimmed"] as? Bool, true)
        XCTAssertEqual(state["navigatorPrototypeStillShimmed"] as? Bool, true)
        XCTAssertEqual(state["permissionsStillShimmed"] as? Bool, true)
        XCTAssertEqual(state["positionStatus"] as? String, "success", "Page state: \(state)")
        XCTAssertEqual(state["latitude"] as? Double, 37.3317)
        XCTAssertEqual(state["longitude"] as? Double, -122.0301)
        XCTAssertEqual(state["permissionState"] as? String, GeolocationPermissionState.granted.rawValue)
        XCTAssertEqual(delegate.positionRequestCount, 1)
        XCTAssertEqual(delegate.permissionQueryCount, 1)
    }

    func testTopLevelRequestAndQueryUseFallbackWhenPolicyAPIIsUnavailable() async throws {
        let delegate = WebKitTestGeolocationDelegate()
        let script = GeolocationUserScript(delegate: delegate, installImmediately: true)
        script.activationHandler = { _ in true }
        let harness = makeHarness(script: script)
        let server = try await WebKitLoopbackHTTPServer.start(html: "<html><body></body></html>")
        defer { server.stop() }

        try await harness.load(try XCTUnwrap(server.url))
        try await waitUntil(in: harness.webView, expression: "Boolean(window.__ddgSitePermissionsGeolocation)")

        let state = try await javaScriptDictionary(in: harness.webView, body: """
        const policy = document.permissionsPolicy ?? document.featurePolicy;
        const permission = await navigator.permissions.query({ name: "geolocation" });
        const result = await new Promise((resolve) => {
            navigator.geolocation.getCurrentPosition(
                (position) => resolve({ status: "success", position }),
                (error) => resolve({ status: "error", error })
            );
        });
        return {
            hasPolicyAPI: typeof policy?.allowsFeature === "function",
            status: result.status,
            errorCode: result.error?.code ?? 0,
            latitude: result.position?.coords.latitude ?? 0,
            longitude: result.position?.coords.longitude ?? 0,
            permissionState: permission.state
        };
        """)

        XCTAssertEqual(state["hasPolicyAPI"] as? Bool, false, "This regression specifically exercises the v1 fallback")
        XCTAssertEqual(state["status"] as? String, "success", "Page state: \(state)")
        XCTAssertEqual(state["latitude"] as? Double, 37.3317)
        XCTAssertEqual(state["longitude"] as? Double, -122.0301)
        XCTAssertEqual(state["permissionState"] as? String, GeolocationPermissionState.granted.rawValue)
        XCTAssertEqual(delegate.positionRequestCount, 1)
        XCTAssertEqual(delegate.permissionQueryCount, 1)
    }

    func testSameOriginIframeRequestAndQueryReachDelegate() async throws {
        let delegate = WebKitTestGeolocationDelegate()
        let script = GeolocationUserScript(delegate: delegate, installImmediately: true)
        script.activationHandler = { _ in true }
        let harness = makeHarness(script: script)
        let server = try await WebKitLoopbackHTTPServer.start(html: frameHostHTML(source: "/frame"),
                                                              frameHTML: frameExerciseHTML)
        defer { server.stop() }

        try await harness.load(try XCTUnwrap(server.url))
        try await waitUntil(in: harness.webView, expression: "window.frameResult !== undefined")
        let state = try await javaScriptDictionary(in: harness.webView, body: "return window.frameResult;")

        assertAllowed(state)
        XCTAssertEqual(delegate.positionRequestCount, 1)
        XCTAssertEqual(delegate.permissionQueryCount, 1)
    }

    func testSameSiteCrossOriginIframeRequestAndQueryFailClosed() async throws {
        let delegate = WebKitTestGeolocationDelegate()
        let script = GeolocationUserScript(delegate: delegate, installImmediately: true)
        script.activationHandler = { _ in true }
        let harness = makeHarness(script: script)
        let frameServer = try await WebKitLoopbackHTTPServer.start(html: frameExerciseHTML)
        defer { frameServer.stop() }
        let frameURL = try XCTUnwrap(frameServer.url)
        let topServer = try await WebKitLoopbackHTTPServer.start(html: frameHostHTML(source: frameURL.absoluteString))
        defer { topServer.stop() }

        try await harness.load(try XCTUnwrap(topServer.url))
        try await waitUntil(in: harness.webView, expression: "window.frameResult !== undefined")
        let state = try await javaScriptDictionary(in: harness.webView, body: "return window.frameResult;")

        assertDenied(state)
        XCTAssertEqual(delegate.positionRequestCount, 0)
        XCTAssertEqual(delegate.permissionQueryCount, 0)
    }

    func testCrossSiteIframeRequestAndQueryFailClosed() async throws {
        let delegate = WebKitTestGeolocationDelegate()
        let script = GeolocationUserScript(delegate: delegate, installImmediately: true)
        script.activationHandler = { _ in true }
        let harness = makeHarness(script: script)
        let frameServer = try await WebKitLoopbackHTTPServer.start(html: frameExerciseHTML)
        defer { frameServer.stop() }
        var frameURL = try XCTUnwrap(URLComponents(url: try XCTUnwrap(frameServer.url), resolvingAgainstBaseURL: false))
        frameURL.host = "127.0.0.1"
        let topServer = try await WebKitLoopbackHTTPServer.start(
            html: frameHostHTML(source: try XCTUnwrap(frameURL.url).absoluteString)
        )
        defer { topServer.stop() }

        try await harness.load(try XCTUnwrap(topServer.url))
        try await waitUntil(in: harness.webView, expression: "window.frameResult !== undefined")
        let state = try await javaScriptDictionary(in: harness.webView, body: "return window.frameResult;")

        assertDenied(state)
        XCTAssertEqual(delegate.positionRequestCount, 0)
        XCTAssertEqual(delegate.permissionQueryCount, 0)
    }

    func testInsecureTopLevelRequestAndQueryFailClosed() async throws {
        let delegate = WebKitTestGeolocationDelegate()
        let script = GeolocationUserScript(delegate: delegate, installImmediately: true)
        script.activationHandler = { _ in true }
        let harness = makeHarness(script: script)
        let insecureURL = try XCTUnwrap(URL(string: "http://example.com"))

        try await harness.load("<html><body></body></html>", baseURL: insecureURL)
        try await waitUntil(in: harness.webView, expression: "Boolean(window.__ddgSitePermissionsGeolocation)")
        let state = try await exerciseGeolocation(in: harness.webView)

        XCTAssertEqual(state["isSecureContext"] as? Bool, false, "Page state: \(state)")
        assertDenied(state)
        XCTAssertEqual(delegate.positionRequestCount, 0)
        XCTAssertEqual(delegate.permissionQueryCount, 0)
    }

    func testSameOriginSandboxedFrameFailsClosedWithoutCallingDelegate() async throws {
        let delegate = WebKitTestGeolocationDelegate()
        let script = GeolocationUserScript(delegate: delegate, installImmediately: true)
        script.activationHandler = { _ in true }
        let harness = makeHarness(script: script)
        let server = try await WebKitLoopbackHTTPServer.start(
            html: frameHostHTML(source: "/frame", sandboxed: true),
            frameHTML: frameExerciseHTML
        )
        defer { server.stop() }

        try await harness.load(try XCTUnwrap(server.url))
        try await waitUntil(in: harness.webView, expression: "window.frameResult !== undefined")
        let state = try await javaScriptDictionary(in: harness.webView, body: "return window.frameResult;")

        assertDenied(state)
        XCTAssertEqual(delegate.positionRequestCount, 0)
        XCTAssertEqual(delegate.permissionQueryCount, 0)
    }

    func testRemovingSandboxAttributeImmediatelyDoesNotUnsandboxSurvivingDocument() async throws {
        let delegate = WebKitTestGeolocationDelegate()
        let script = GeolocationUserScript(delegate: delegate, installImmediately: true)
        script.activationHandler = { _ in true }
        let harness = makeHarness(script: script)
        let server = try await WebKitLoopbackHTTPServer.start(
            html: frameHostHTML(source: "/frame?removeSandbox", sandboxed: true),
            frameHTML: frameExerciseHTML
        )
        defer { server.stop() }

        try await harness.load(try XCTUnwrap(server.url))
        try await waitUntil(in: harness.webView,
                            expression: "window.sandboxRemoved === true && window.frameResult !== undefined")
        let state = try await javaScriptDictionary(in: harness.webView, body: """
        return {
            ...window.frameResult,
            sandboxAttributePresent: document.getElementById("test-frame").hasAttribute("sandbox")
        };
        """)

        XCTAssertEqual(state["sandboxAttributePresent"] as? Bool, false)
        assertDenied(state)
        XCTAssertEqual(delegate.positionRequestCount, 0)
        XCTAssertEqual(delegate.permissionQueryCount, 0)
    }

    func testPolicyIntrospectionDenialIsHonoredWhenAvailableAndUsesFallbackOtherwise() async throws {
        let delegate = WebKitTestGeolocationDelegate()
        let script = GeolocationUserScript(delegate: delegate, installImmediately: true)
        script.activationHandler = { _ in true }
        let harness = makeHarness(script: script)
        let server = try await WebKitLoopbackHTTPServer.start(html: "<html><body></body></html>",
                                                              permissionsPolicy: "geolocation=()")
        defer { server.stop() }

        try await harness.load(try XCTUnwrap(server.url))
        try await waitUntil(in: harness.webView, expression: "Boolean(window.__ddgSitePermissionsGeolocation)")
        let state = try await exerciseGeolocation(in: harness.webView)

        if state["hasPolicyAPI"] as? Bool == true {
            assertDenied(state)
            XCTAssertEqual(delegate.positionRequestCount, 0)
            XCTAssertEqual(delegate.permissionQueryCount, 0)
        } else {
            assertAllowed(state)
            XCTAssertEqual(delegate.positionRequestCount, 1)
            XCTAssertEqual(delegate.permissionQueryCount, 1)
        }
    }

    func testPolicyIsReevaluatedAfterIframeAllowAttributeBecomesRestrictive() async throws {
        let delegate = WebKitTestGeolocationDelegate()
        let script = GeolocationUserScript(delegate: delegate, installImmediately: true)
        script.activationHandler = { _ in true }
        let harness = makeHarness(script: script)
        let server = try await WebKitLoopbackHTTPServer.start(html: frameHostHTML(source: "/frame"),
                                                              frameHTML: frameExerciseHTML)
        defer { server.stop() }

        try await harness.load(try XCTUnwrap(server.url))
        try await waitUntil(in: harness.webView, expression: "window.frameResult !== undefined")
        let firstState = try await javaScriptDictionary(in: harness.webView, body: "return window.frameResult;")
        assertAllowed(firstState)

        _ = try await harness.webView.callAsyncJavaScript("""
        window.frameResult = undefined;
        const frame = document.getElementById("test-frame");
        frame.setAttribute("allow", "geolocation 'none'");
        await new Promise((resolve) => setTimeout(resolve, 0));
        frame.contentWindow.postMessage({ test: "rerun-geolocation" }, "*");
        """, arguments: [:], in: nil, contentWorld: .page)
        try await waitUntil(in: harness.webView, expression: "window.frameResult !== undefined")
        let secondState = try await javaScriptDictionary(in: harness.webView, body: "return window.frameResult;")

        if secondState["hasPolicyAPI"] as? Bool == true {
            assertDenied(secondState)
            XCTAssertEqual(delegate.positionRequestCount, 1)
            XCTAssertEqual(delegate.permissionQueryCount, 1)
        } else {
            assertAllowed(secondState)
            XCTAssertEqual(delegate.positionRequestCount, 2)
            XCTAssertEqual(delegate.permissionQueryCount, 2)
        }
    }

    func testOperationReregistersAfterNativeLifecycleReset() async throws {
        let delegate = WebKitTestGeolocationDelegate()
        let script = GeolocationUserScript(delegate: delegate, installImmediately: true)
        script.activationHandler = { _ in true }
        let harness = makeHarness(script: script)
        let server = try await WebKitLoopbackHTTPServer.start(html: "<html><body></body></html>")
        defer { server.stop() }

        try await harness.load(try XCTUnwrap(server.url))
        try await waitUntil(in: harness.webView, expression: "Boolean(window.__ddgSitePermissionsGeolocation)")
        _ = try await harness.webView.callAsyncJavaScript(
            "return (await navigator.permissions.query({ name: 'geolocation' })).state;",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        script.cancelAllWatches()

        let state = try await exerciseGeolocation(in: harness.webView)

        assertAllowed(state)
        XCTAssertEqual(delegate.positionRequestCount, 1)
        XCTAssertEqual(delegate.permissionQueryCount, 2)
    }

    private func exerciseGeolocation(in webView: WKWebView) async throws -> [String: Any] {
        try await javaScriptDictionary(in: webView, body: """
        const policy = document.permissionsPolicy ?? document.featurePolicy;
        const permission = await navigator.permissions.query({ name: "geolocation" });
        const result = await new Promise((resolve) => {
            navigator.geolocation.getCurrentPosition(
                (position) => resolve({ status: "success", position }),
                (error) => resolve({ status: "error", error })
            );
        });
        return {
            hasPolicyAPI: typeof policy?.allowsFeature === "function",
            isSecureContext: globalThis.isSecureContext,
            permissionState: permission.state,
            requestStatus: result.status,
            errorCode: result.error?.code ?? 0,
            latitude: result.position?.coords.latitude ?? 0
        };
        """)
    }

    private func assertAllowed(_ state: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(state["permissionState"] as? String, GeolocationPermissionState.granted.rawValue,
                       "Page state: \(state)", file: file, line: line)
        XCTAssertEqual(state["requestStatus"] as? String, "success", "Page state: \(state)", file: file, line: line)
        XCTAssertEqual(state["latitude"] as? Double, 37.3317, file: file, line: line)
    }

    private func assertDenied(_ state: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(state["permissionState"] as? String, GeolocationPermissionState.denied.rawValue,
                       "Page state: \(state)", file: file, line: line)
        XCTAssertEqual(state["requestStatus"] as? String, "error", "Page state: \(state)", file: file, line: line)
        XCTAssertEqual(state["errorCode"] as? Int, GeolocationPositionError.Code.permissionDenied.rawValue,
                       "Page state: \(state)", file: file, line: line)
    }

    private func frameHostHTML(source: String, sandboxed: Bool = false) -> String {
        let sandbox = sandboxed ? " sandbox=\"allow-same-origin allow-scripts\"" : ""
        return """
        <html><head><script>
            window.addEventListener("message", (event) => {
                if (event.data?.test === "remove-sandbox") {
                    document.getElementById("test-frame").removeAttribute("sandbox");
                    window.sandboxRemoved = true;
                    event.source.postMessage({ test: "sandbox-removed" }, "*");
                } else if (event.data?.test === "geolocation-frame-result") {
                    window.frameResult = event.data;
                }
            });
        </script></head><body>
            <iframe id="test-frame" allow="geolocation"\(sandbox) src="\(source)"></iframe>
        </body></html>
        """
    }

    private var frameExerciseHTML: String {
        """
        <html><head><script>
            const exerciseGeolocation = async () => {
                const policy = document.permissionsPolicy ?? document.featurePolicy;
                const permission = await navigator.permissions.query({ name: "geolocation" });
                const result = await new Promise((resolve) => {
                    navigator.geolocation.getCurrentPosition(
                        (position) => resolve({ status: "success", position }),
                        (error) => resolve({ status: "error", error })
                    );
                });
                parent.postMessage({
                    test: "geolocation-frame-result",
                    hasPolicyAPI: typeof policy?.allowsFeature === "function",
                    isSecureContext: globalThis.isSecureContext,
                    permissionState: permission.state,
                    requestStatus: result.status,
                    errorCode: result.error?.code ?? 0,
                    latitude: result.position?.coords.latitude ?? 0,
                    origin: globalThis.origin
                }, "*");
            };
            window.addEventListener("message", (event) => {
                if (event.data?.test === "rerun-geolocation" || event.data?.test === "sandbox-removed") {
                    void exerciseGeolocation();
                }
            });
            if (globalThis.location.search === "?removeSandbox") {
                parent.postMessage({ test: "remove-sandbox" }, "*");
            } else {
                window.addEventListener("load", exerciseGeolocation);
            }
        </script></head><body></body></html>
        """
    }

    private var nativeAPICaptureHTML: String {
        """
        <html><head><script>
            window.pageStart = {
                geolocation: navigator.geolocation,
                getCurrentPosition: navigator.geolocation.getCurrentPosition,
                permissionsQuery: navigator.permissions.query
            };
        </script></head><body></body></html>
        """
    }

    private func makeHarness(script: GeolocationUserScript) -> WebKitTestHarness {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(WKUserScript(source: script.source,
                                                                        injectionTime: script.injectionTime,
                                                                        forMainFrameOnly: script.forMainFrameOnly,
                                                                        in: .page))
        for messageName in script.messageNames {
            configuration.userContentController.addScriptMessageHandler(script, contentWorld: .page, name: messageName)
        }
        return WebKitTestHarness(configuration: configuration)
    }

    private func waitUntil(in webView: WKWebView,
                           expression: String,
                           attempts: Int = 100) async throws {
        for _ in 0..<attempts {
            let result = try await webView.callAsyncJavaScript("return Boolean(\(expression));",
                                                               arguments: [:],
                                                               in: nil,
                                                               contentWorld: .page)
            if result as? Bool == true {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for JavaScript expression: \(expression)")
    }

    private func javaScriptDictionary(in webView: WKWebView, body: String) async throws -> [String: Any] {
        let result = try await webView.callAsyncJavaScript(body,
                                                           arguments: [:],
                                                           in: nil,
                                                           contentWorld: .page)
        return try XCTUnwrap(result as? [String: Any])
    }
}

@MainActor
private final class WebKitTestHarness: NSObject, WKNavigationDelegate {

    let webView: WKWebView
    private var navigationContinuation: CheckedContinuation<Void, Error>?

    init(configuration: WKWebViewConfiguration) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    func load(_ html: String) async throws {
        try await load(html, baseURL: XCTUnwrap(URL(string: "https://example.com")))
    }

    func load(_ html: String, baseURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
            navigationContinuation = continuation
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    func load(_ url: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            navigationContinuation = continuation
            webView.load(URLRequest(url: url))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationContinuation?.resume()
        navigationContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }
}

private final class WebKitLoopbackHTTPServer: @unchecked Sendable {

    enum Error: Swift.Error {
        case missingPort
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "GeolocationUserScriptWebKitTests.HTTPServer")
    private let response: Data
    private let frameResponse: Data?
    private(set) var url: URL?
    private var startContinuation: CheckedContinuation<Void, Swift.Error>?

    private init(html: String, frameHTML: String?, permissionsPolicy: String) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)

        response = Self.response(html: html, permissionsPolicy: permissionsPolicy)
        frameResponse = frameHTML.map { Self.response(html: $0, permissionsPolicy: permissionsPolicy) }
    }

    private static func response(html: String, permissionsPolicy: String) -> Data {
        let body = Data(html.utf8)
        let header = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Permissions-Policy: \(permissionsPolicy)\r
        Content-Length: \(body.count)\r
        Connection: close\r
        \r

        """
        return Data(header.utf8) + body
    }

    static func start(html: String,
                      frameHTML: String? = nil,
                      permissionsPolicy: String = "geolocation=*") async throws -> WebKitLoopbackHTTPServer {
        let server = try WebKitLoopbackHTTPServer(html: html,
                                                  frameHTML: frameHTML,
                                                  permissionsPolicy: permissionsPolicy)
        try await server.start()
        return server
    }

    private func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
            startContinuation = continuation
            listener.stateUpdateHandler = { [weak self] state in
                self?.handleListenerState(state)
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.serve(connection)
            }
            listener.start(queue: queue)
        }
    }

    private func handleListenerState(_ state: NWListener.State) {
        guard let startContinuation else { return }
        switch state {
        case .ready:
            guard let port = listener.port else {
                self.startContinuation = nil
                startContinuation.resume(throwing: Error.missingPort)
                return
            }
            self.startContinuation = nil
            url = URL(string: "http://localhost:\(port.rawValue)")
            startContinuation.resume()
        case .failed(let error):
            self.startContinuation = nil
            startContinuation.resume(throwing: error)
        default:
            break
        }
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [response, frameResponse] request, _, _, _ in
            let isFrameRequest = request.flatMap { String(data: $0, encoding: .utf8) }?.hasPrefix("GET /frame") == true
            let selectedResponse = isFrameRequest ? frameResponse ?? response : response
            connection.send(content: selectedResponse, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    func stop() {
        listener.cancel()
    }
}

@MainActor
private final class WebKitTestGeolocationDelegate: GeolocationUserScriptDelegate {

    private(set) var positionRequestCount = 0
    private(set) var permissionQueryCount = 0

    func geolocationUserScript(_ userScript: GeolocationUserScript,
                               getCurrentPositionWith options: GeolocationRequestOptions,
                               constraints: GeolocationRequestConstraints,
                               in frame: GeolocationFrame) async -> GeolocationPositionResult {
        positionRequestCount += 1
        let coordinates = GeolocationPosition.Coordinates(latitude: 37.3317,
                                                          longitude: -122.0301,
                                                          accuracy: 4,
                                                          altitude: nil,
                                                          altitudeAccuracy: nil,
                                                          heading: nil,
                                                          speed: nil)
        return .success(.init(coordinates: coordinates, timestamp: Date(timeIntervalSince1970: 123)))
    }

    func geolocationUserScript(_ userScript: GeolocationUserScript,
                               constraints: GeolocationRequestConstraints,
                               permissionStateIn frame: GeolocationFrame) -> GeolocationPermissionState {
        permissionQueryCount += 1
        return .granted
    }

    func geolocationUserScript(_ userScript: GeolocationUserScript,
                               didStartWatchWithID requestID: String,
                               options: GeolocationRequestOptions,
                               constraints: GeolocationRequestConstraints,
                               in frame: GeolocationFrame) {}

    func geolocationUserScript(_ userScript: GeolocationUserScript,
                               didCancelWatchWithID requestID: String) {}
}
