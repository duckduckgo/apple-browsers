//
//  MediaCaptureUserScriptTests.swift
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

@testable import SitePermissions
import WebKit
import XCTest

@MainActor
final class MediaCaptureUserScriptTests: XCTestCase {

    func testInjectionConfigurationInterceptsEveryFrameAtDocumentStartInPageWorld() {
        let sut = MediaCaptureUserScript()

        XCTAssertEqual(sut.injectionTime, .atDocumentStart)
        XCTAssertFalse(sut.forMainFrameOnly)
        XCTAssertTrue(sut.requiresRunInPageContentWorld)
    }

    func testRequestIDValidationAcceptsGeneratedFormatOnly() {
        XCTAssertTrue(MediaCaptureUserScript.isValidRequestID("0123456789abcdef0123456789abcdef:1"))
        XCTAssertTrue(MediaCaptureUserScript.isValidRequestID("ABCDEF0123456789ABCDEF0123456789:18446744073709551615"))

        XCTAssertFalse(MediaCaptureUserScript.isValidRequestID(""))
        XCTAssertFalse(MediaCaptureUserScript.isValidRequestID("0123456789abcdef0123456789abcdef:0"))
        XCTAssertFalse(MediaCaptureUserScript.isValidRequestID("0123456789abcdef0123456789abcdef:"))
        XCTAssertFalse(MediaCaptureUserScript.isValidRequestID("0123456789abcdef0123456789abcdeg:1"))
        XCTAssertFalse(MediaCaptureUserScript.isValidRequestID("0123456789abcdef:1"))
    }

    func testInjectedJavaScriptWaitsForAllowReplyThenInvokesSavedNativeFunctionOnce() async throws {
        let (webView, handler) = await makeWebView(reply: (["decision": "allow"], nil),
                                                   baseURL: URL(string: "https://duck.ai")!)

        let result = try await webView.callAsyncJavaScript(
            "return await navigator.mediaDevices.getUserMedia({ video: true });",
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? String
        let nativeCallCount = try await webView.callAsyncJavaScript(
            "return globalThis.__nativeMediaCallCount;",
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? Int

        XCTAssertEqual(result, "native-result")
        XCTAssertEqual(nativeCallCount, 1)
        XCTAssertEqual(handler.receivedBodies.count, 1)
        XCTAssertEqual(Set(handler.receivedBodies[0].keys), ["capability", "requestID", "video", "audio"])
        XCTAssertEqual(handler.receivedBodies[0]["capability"] as? String, MediaCaptureUserScript.capabilityToken)
        XCTAssertEqual(handler.receivedBodies[0]["video"] as? Bool, true)
        XCTAssertEqual(handler.receivedBodies[0]["audio"] as? Bool, false)
    }

    func testInjectedJavaScriptRejectsWithoutInvokingNativeFunctionWhenBridgeDenies() async {
        let (webView, handler) = await makeWebView(reply: (["decision": "deny"], nil),
                                                   baseURL: URL(string: "https://duck.ai")!)

        do {
            _ = try await webView.callAsyncJavaScript(
                "return await navigator.mediaDevices.getUserMedia({ audio: true });",
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
            XCTFail("Expected getUserMedia to reject")
        } catch {
            // Expected: the bridge translates denial into a rejected getUserMedia promise.
        }

        let nativeCallCount = try? await webView.callAsyncJavaScript(
            "return globalThis.__nativeMediaCallCount;",
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? Int
        XCTAssertEqual(nativeCallCount, 0)
        XCTAssertEqual(handler.receivedBodies.count, 1)
    }

    func testInjectedJavaScriptRejectsSyntheticFrameBeforeCallingBridgeOrNativeFunction() async {
        let (webView, handler) = await makeWebView(reply: (["decision": "allow"], nil),
                                                   baseURL: URL(string: "about:blank")!)

        do {
            _ = try await webView.callAsyncJavaScript(
                "return await navigator.mediaDevices.getUserMedia({ video: true });",
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
            XCTFail("Expected getUserMedia to reject")
        } catch {
            // Expected: synthetic documents are rejected in JavaScript before native routing.
        }

        let nativeCallCount = try? await webView.callAsyncJavaScript(
            "return globalThis.__nativeMediaCallCount;",
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? Int
        XCTAssertEqual(nativeCallCount, 0)
        XCTAssertTrue(handler.receivedBodies.isEmpty)
    }

    func testInjectedJavaScriptAllowsOrdinarySameOriginBlobFrame() async throws {
        let (webView, handler) = await makeWebView(reply: (["decision": "allow"], nil),
                                                   baseURL: URL(string: "https://duck.ai")!)

        let result = try await requestCameraFromBlobFrame(in: webView, sandboxedThenRemoved: false)

        XCTAssertEqual(result["result"] as? String, "native-result")
        XCTAssertEqual(result["nativeCallCount"] as? Int, 1)
        XCTAssertEqual(handler.receivedBodies.count, 1)
    }

    func testInjectedJavaScriptRejectsSandboxedBlobFrameAfterAttributeRemovalWithoutCallingBridgeOrNative() async throws {
        let (webView, handler) = await makeWebView(reply: (["decision": "allow"], nil),
                                                   baseURL: URL(string: "https://duck.ai")!)

        let result = try await requestCameraFromBlobFrame(in: webView, sandboxedThenRemoved: true)

        XCTAssertEqual(result["rejected"] as? Bool, true)
        XCTAssertEqual(result["nativeCallCount"] as? Int, 0)
        XCTAssertTrue(handler.receivedBodies.isEmpty)
    }

    func testInjectedJavaScriptHonorsPermissionsPolicyBeforeCallingBridgeOrNative() async throws {
        let (webView, handler) = await makeWebView(reply: (["decision": "allow"], nil),
                                                   baseURL: URL(string: "https://duck.ai")!,
                                                   deniedPolicyFeatures: ["camera"])

        let result = try await requestCameraFromBlobFrame(in: webView, sandboxedThenRemoved: false)

        XCTAssertEqual(result["rejected"] as? Bool, true)
        XCTAssertEqual(result["nativeCallCount"] as? Int, 0)
        XCTAssertTrue(handler.receivedBodies.isEmpty)
    }

    func testNativeCapabilityIsNotExposedAsAGlobalPropertyName() async throws {
        let (webView, _) = await makeWebView(reply: (["decision": "allow"], nil),
                                             baseURL: URL(string: "https://duck.ai")!)

        let isExposed = try await webView.callAsyncJavaScript(
            "return Object.getOwnPropertyNames(globalThis).some(name => name.includes(capability));",
            arguments: ["capability": MediaCaptureUserScript.capabilityToken],
            in: nil,
            contentWorld: .page
        ) as? Bool

        XCTAssertEqual(isExposed, false)
    }

    func testLegacyNavigatorGetUserMediaEntryPointsAreUnavailable() async throws {
        let (webView, _) = await makeWebView(reply: (["decision": "allow"], nil),
                                             baseURL: URL(string: "https://duck.ai")!)

        let legacyEntryPointCount = try await webView.callAsyncJavaScript(
            "return [navigator.getUserMedia, navigator.webkitGetUserMedia].filter(value => typeof value === 'function').length;",
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? Int

        XCTAssertEqual(legacyEntryPointCount, 0)
    }

    func testInjectedJavaScriptSnapshotsChangingConstraintGettersBeforeCallingBridgeAndNative() async throws {
        let (webView, handler) = await makeWebView(reply: (["decision": "allow"], nil),
                                                   baseURL: URL(string: "https://duck.ai")!)

        let reads = try await webView.callAsyncJavaScript(
            """
            let videoReads = 0;
            let audioReads = 0;
            const constraints = {
                get video() { videoReads += 1; return videoReads === 1; },
                get audio() { audioReads += 1; return audioReads !== 1; }
            };
            await navigator.mediaDevices.getUserMedia(constraints);
            return { videoReads, audioReads };
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? [String: Any]
        let nativeConstraints = try await capturedNativeConstraints(in: webView)

        XCTAssertEqual(reads?["videoReads"] as? Int, 1)
        XCTAssertEqual(reads?["audioReads"] as? Int, 1)
        XCTAssertEqual(handler.receivedBodies[0]["video"] as? Bool, true)
        XCTAssertEqual(handler.receivedBodies[0]["audio"] as? Bool, false)
        XCTAssertEqual(nativeConstraints["video"] as? Bool, true)
        XCTAssertEqual(nativeConstraints["audio"] as? Bool, false)
    }

    func testInjectedJavaScriptRejectsBorrowedReceiverWithoutCallingBridgeOrNative() async {
        let (webView, handler) = await makeWebView(reply: (["decision": "allow"], nil),
                                                   baseURL: URL(string: "https://duck.ai")!)

        do {
            _ = try await webView.callAsyncJavaScript(
                "return await navigator.mediaDevices.getUserMedia.call(globalThis.__otherMediaDevices, { video: true });",
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
            XCTFail("Expected a borrowed receiver to be rejected")
        } catch {
            // Expected: borrowed receivers are conservatively unsupported without entering native code.
        }
        let nativeCallCount = try? await webView.callAsyncJavaScript(
            "return globalThis.__nativeMediaCallCount;",
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? Int

        XCTAssertTrue(handler.receivedBodies.isEmpty)
        XCTAssertEqual(nativeCallCount, 0)
    }

    func testInjectedJavaScriptSnapshotsProxyConstraintsOnce() async throws {
        let (webView, handler) = await makeWebView(reply: (["decision": "allow"], nil),
                                                   baseURL: URL(string: "https://duck.ai")!)

        let reads = try await webView.callAsyncJavaScript(
            """
            const reads = { video: 0, audio: 0 };
            const constraints = new Proxy({}, {
                get(_, key) {
                    reads[key] += 1;
                    return key === "video" ? reads[key] === 1 : reads[key] !== 1;
                }
            });
            await navigator.mediaDevices.getUserMedia(constraints);
            return reads;
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? [String: Any]
        let nativeConstraints = try await capturedNativeConstraints(in: webView)

        XCTAssertEqual(reads?["video"] as? Int, 1)
        XCTAssertEqual(reads?["audio"] as? Int, 1)
        XCTAssertEqual(handler.receivedBodies[0]["video"] as? Bool, true)
        XCTAssertEqual(handler.receivedBodies[0]["audio"] as? Bool, false)
        XCTAssertEqual(nativeConstraints["video"] as? Bool, true)
        XCTAssertEqual(nativeConstraints["audio"] as? Bool, false)
    }

    private func makeWebView(reply: (Any?, String?),
                             baseURL: URL,
                             deniedPolicyFeatures: [String] = []) async -> (WKWebView, MediaCaptureReplyHandler) {
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        configuration.userContentController = contentController

        let handler = MediaCaptureReplyHandler(reply: reply)
        let script = MediaCaptureUserScript()
        contentController.addScriptMessageHandler(handler,
                                                  contentWorld: .page,
                                                  name: script.messageNames[0])
        contentController.addUserScript(WKUserScript(
            source: Self.fakeMediaDevicesSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: .page
        ))
        if !deniedPolicyFeatures.isEmpty {
            let featureList = deniedPolicyFeatures.map { "\"\($0)\"" }.joined(separator: ",")
            contentController.addUserScript(WKUserScript(
                source: """
                Object.defineProperty(document, "permissionsPolicy", {
                    configurable: true,
                    value: { allowsFeature: feature => ![\(featureList)].includes(feature) }
                });
                """,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                in: .page
            ))
        }
        contentController.addUserScript(script.makeWKUserScriptSync())

        let webView = WKWebView(frame: .zero, configuration: configuration)
        let loadExpectation = expectation(description: "Web view loaded")
        let navigationDelegate = MediaCaptureNavigationDelegate {
            loadExpectation.fulfill()
        }
        webView.navigationDelegate = navigationDelegate
        webView.loadHTMLString("<html><body></body></html>", baseURL: baseURL)
        await fulfillment(of: [loadExpectation], timeout: 1)
        withExtendedLifetime(navigationDelegate) {}
        return (webView, handler)
    }

    private func capturedNativeConstraints(in webView: WKWebView) async throws -> [String: Any] {
        try await webView.callAsyncJavaScript(
            "return globalThis.__nativeMediaConstraints;",
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? [String: Any] ?? [:]
    }

    private func requestCameraFromBlobFrame(in webView: WKWebView,
                                            sandboxedThenRemoved: Bool) async throws -> [String: Any] {
        try await webView.callAsyncJavaScript(
            """
            const iframe = document.createElement("iframe");
            if (sandboxedThenRemoved) {
                iframe.setAttribute("sandbox", "allow-same-origin allow-scripts");
            }
            const blob = new Blob(["<html><body></body></html>"], { type: "text/html" });
            iframe.src = URL.createObjectURL(blob);
            const loaded = new Promise(resolve => iframe.addEventListener("load", resolve, { once: true }));
            document.body.appendChild(iframe);
            if (sandboxedThenRemoved) {
                iframe.removeAttribute("sandbox");
            }
            await loaded;
            try {
                const result = await iframe.contentWindow.navigator.mediaDevices.getUserMedia({ video: true });
                return {
                    result,
                    rejected: false,
                    nativeCallCount: iframe.contentWindow.__nativeMediaCallCount
                };
            } catch (_) {
                return {
                    rejected: true,
                    nativeCallCount: iframe.contentWindow.__nativeMediaCallCount
                };
            }
            """,
            arguments: ["sandboxedThenRemoved": sandboxedThenRemoved],
            in: nil,
            contentWorld: .page
        ) as? [String: Any] ?? [:]
    }

    private static let fakeMediaDevicesSource = """
    class FakeMediaDevices {
        getUserMedia(constraints) {
            globalThis.__nativeMediaCallCount += 1;
            globalThis.__nativeMediaConstraints = {
                video: Boolean(constraints?.video),
                audio: Boolean(constraints?.audio)
            };
            return Promise.resolve("native-result");
        }
    }
    globalThis.__nativeMediaCallCount = 0;
    globalThis.__nativeMediaConstraints = null;
    globalThis.__otherMediaDevices = new FakeMediaDevices();
    Object.defineProperty(navigator, "mediaDevices", {
        configurable: true,
        value: new FakeMediaDevices()
    });
    """
}

@MainActor
private final class MediaCaptureReplyHandler: NSObject, WKScriptMessageHandlerWithReply {
    private let reply: (Any?, String?)
    private(set) var receivedBodies = [[String: Any]]()

    init(reply: (Any?, String?)) {
        self.reply = reply
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) async -> (Any?, String?) {
        if let body = message.body as? [String: Any] {
            receivedBodies.append(body)
        }
        return reply
    }
}

@MainActor
private final class MediaCaptureNavigationDelegate: NSObject, WKNavigationDelegate {
    private let didFinish: () -> Void

    init(didFinish: @escaping () -> Void) {
        self.didFinish = didFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        didFinish()
    }
}
