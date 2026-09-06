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
        XCTAssertEqual(Set(handler.receivedBodies[0].keys), ["capability", "requestID", "video", "audio", "isEligible"])
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

    func testInjectedJavaScriptMarksSyntheticFrameIneligibleWithoutCallingNativeFunction() async {
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
            // Expected: the bridge rejects the ineligible document without requesting permission.
        }

        let nativeCallCount = try? await webView.callAsyncJavaScript(
            "return globalThis.__nativeMediaCallCount;",
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? Int
        XCTAssertEqual(nativeCallCount, 0)
        XCTAssertFalse(handler.receivedBodies.isEmpty)
        XCTAssertTrue(handler.receivedBodies.allSatisfy { $0["isEligible"] as? Bool == false })
    }

    func testInjectedJavaScriptAllowsOrdinarySameOriginBlobFrame() async throws {
        let (webView, handler) = await makeWebView(reply: (["decision": "allow"], nil),
                                                   baseURL: URL(string: "https://duck.ai")!)

        let result = try await requestCameraFromBlobFrame(in: webView)

        XCTAssertEqual(result["result"] as? String, "native-result")
        XCTAssertEqual(result["nativeCallCount"] as? Int, 1)
        XCTAssertEqual(handler.receivedBodies.count, 1)
    }

    func testInjectedJavaScriptMarksOpaqueSandboxIneligibleAfterAttributeRemovalWithoutCallingNative() async throws {
        let (webView, handler) = await makeWebView(reply: (["decision": "allow"], nil),
                                                   baseURL: URL(string: "https://duck.ai")!)

        let result = try await requestCameraFromBlobFrame(in: webView, sandbox: "allow-scripts", removeSandboxAfterLoad: true)

        XCTAssertEqual(result["origin"] as? String, "null")
        XCTAssertEqual(result["rejected"] as? Bool, true)
        XCTAssertEqual(result["nativeCallCount"] as? Int, 0)
        XCTAssertFalse(handler.receivedBodies.isEmpty)
        XCTAssertTrue(handler.receivedBodies.allSatisfy { $0["isEligible"] as? Bool == false })
    }

    func testInjectedJavaScriptAllowsSameOriginFramesInOpenAndClosedShadowRoots() async throws {
        let (webView, handler) = await makeWebView(reply: (["decision": "allow"], nil),
                                                   baseURL: URL(string: "https://duck.ai")!)

        for mode in ["open", "closed"] {
            let result = try await requestCameraFromBlobFrame(in: webView, shadowRootMode: mode)

            XCTAssertEqual(result["result"] as? String, "native-result", mode)
            XCTAssertEqual(result["nativeCallCount"] as? Int, 1, mode)
        }
        XCTAssertEqual(handler.receivedBodies.count, 2)
    }

    func testInjectedJavaScriptAllowsSandboxWithSameOriginPermission() async throws {
        let (webView, handler) = await makeWebView(reply: (["decision": "allow"], nil),
                                                   baseURL: URL(string: "https://duck.ai")!)

        // A sandbox with allow-same-origin is eligible for media under the web platform rules.
        let result = try await requestCameraFromBlobFrame(in: webView, sandbox: "allow-same-origin allow-scripts")

        XCTAssertEqual(result["result"] as? String, "native-result")
        XCTAssertEqual(result["nativeCallCount"] as? Int, 1)
        XCTAssertEqual(handler.receivedBodies.count, 1)
    }

    func testInjectedJavaScriptAllowsNewDocumentAfterRemovingOpaqueSandboxAndNavigating() async throws {
        let (webView, handler) = await makeWebView(reply: (["decision": "allow"], nil),
                                                   baseURL: URL(string: "https://duck.ai")!)

        let result = try await requestCameraFromBlobFrame(in: webView,
                                                          sandbox: "allow-scripts",
                                                          navigateAfterRemovingSandbox: true)

        XCTAssertEqual(result["origin"] as? String, "https://duck.ai")
        XCTAssertEqual(result["result"] as? String, "native-result")
        XCTAssertEqual(result["nativeCallCount"] as? Int, 1)
        XCTAssertEqual(handler.receivedBodies.count, 1)
    }

    func testInjectedJavaScriptMarksPolicyBlockedFrameIneligibleWithoutCallingNative() async throws {
        let (webView, handler) = await makeWebView(reply: (["decision": "allow"], nil),
                                                   baseURL: URL(string: "https://duck.ai")!,
                                                   deniedPolicyFeatures: ["camera"])

        let result = try await requestCameraFromBlobFrame(in: webView)

        XCTAssertEqual(result["rejected"] as? Bool, true)
        XCTAssertEqual(result["nativeCallCount"] as? Int, 0)
        XCTAssertFalse(handler.receivedBodies.isEmpty)
        XCTAssertTrue(handler.receivedBodies.allSatisfy { $0["isEligible"] as? Bool == false })
    }

    func testPolicyFallbackRejectsBlockedSameOriginFramesIncludingShadowRootsAndNestedFrames() async throws {
        let (webView, handler) = await makeWebView(reply: (["decision": "allow"], nil),
                                                   baseURL: URL(string: "https://duck.ai")!)

        for shadowRootMode in [nil, "open", "closed"] as [String?] {
            for nestedFrame in [false, true] {
                let result = try await requestCameraFromBlobFrame(in: webView,
                                                                  shadowRootMode: shadowRootMode,
                                                                  allow: "camera 'none'; microphone *",
                                                                  removeAllowAfterLoad: true,
                                                                  nestedFrame: nestedFrame)

                XCTAssertEqual(result["rejected"] as? Bool, true)
                XCTAssertEqual(result["nativeCallCount"] as? Int, 0)
            }
        }
        XCTAssertFalse(handler.receivedBodies.isEmpty)
        XCTAssertTrue(handler.receivedBodies.allSatisfy { $0["isEligible"] as? Bool == false })
    }

    func testPolicyFallbackPreservesAllowedSameOriginAllowlistForms() async throws {
        let (webView, handler) = await makeWebView(reply: (["decision": "allow"], nil),
                                                   baseURL: URL(string: "https://duck.ai")!)
        let policies = ["camera", "camera *", "camera 'self'", "camera 'src'", "camera:'self'",
                        "camera https://other.example https://duck.ai", "microphone 'none'"]

        for policy in policies {
            let result = try await requestCameraFromBlobFrame(in: webView, allow: policy, nestedFrame: true)

            XCTAssertEqual(result["result"] as? String, "native-result", policy)
            XCTAssertEqual(result["nativeCallCount"] as? Int, 1, policy)
        }
        XCTAssertEqual(handler.receivedBodies.count, policies.count)
    }

    func testPolicyFallbackRejectsNonmatchingAllowlistAndUsesFirstDuplicateDirective() async throws {
        let (webView, handler) = await makeWebView(reply: (["decision": "allow"], nil),
                                                   baseURL: URL(string: "https://duck.ai")!)

        for policy in ["camera https://other.example", "camera 'none'; camera *", "camera:'none'", "camera 'self' 'NONE'"] {
            let result = try await requestCameraFromBlobFrame(in: webView, allow: policy)

            XCTAssertEqual(result["rejected"] as? Bool, true, policy)
            XCTAssertEqual(result["nativeCallCount"] as? Int, 0, policy)
        }
        XCTAssertFalse(handler.receivedBodies.isEmpty)
        XCTAssertTrue(handler.receivedBodies.allSatisfy { $0["isEligible"] as? Bool == false })
    }

    func testPolicyFallbackAppliesChangedAllowAttributeOnNextNavigation() async throws {
        let (webView, _) = await makeWebView(reply: (["decision": "allow"], nil),
                                             baseURL: URL(string: "https://duck.ai")!)

        for navigate in [false, true] {
            let result = try await requestCameraFromBlobFrame(in: webView,
                                                              allowAfterLoad: "camera 'none'",
                                                              navigateAfterChangingAllow: navigate)

            XCTAssertEqual(result["rejected"] as? Bool, navigate)
            XCTAssertEqual(result["nativeCallCount"] as? Int, navigate ? 0 : 1)
        }
    }

    func testNativeHandlerAppliesFlagChangesToAnAlreadyLoadedIneligibleDocument() async throws {
        let script = MediaCaptureUserScript()
        let delegate = MediaCapturePermissionDelegate()
        script.delegate = delegate
        let (webView, _) = await makeWebView(reply: (nil, nil),
                                              baseURL: URL(string: "about:blank")!,
                                              messageHandler: script)

        for enabled in [false, true, false] {
            delegate.isMediaCapturePermissionHandlingEnabled = enabled
            let result = try await webView.callAsyncJavaScript(
                """
                try {
                    await navigator.mediaDevices.getUserMedia({ video: true });
                    return true;
                } catch (_) {
                    return false;
                }
                """,
                arguments: [:],
                in: nil,
                contentWorld: .page
            ) as? Bool
            XCTAssertEqual(result, !enabled)
        }

        let nativeCallCount = try await webView.callAsyncJavaScript(
            "return globalThis.__nativeMediaCallCount;",
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? Int
        XCTAssertEqual(nativeCallCount, 2)
        XCTAssertEqual(delegate.requestCount, 0)
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

    func testInjectedJavaScriptMarksBorrowedReceiverIneligibleWithoutCallingNative() async {
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
            // Expected: borrowed receivers are marked ineligible before permission handling.
        }
        let nativeCallCount = try? await webView.callAsyncJavaScript(
            "return globalThis.__nativeMediaCallCount;",
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? Int

        XCTAssertFalse(handler.receivedBodies.isEmpty)
        XCTAssertTrue(handler.receivedBodies.allSatisfy { $0["isEligible"] as? Bool == false })
        XCTAssertEqual(nativeCallCount, 0)
    }

    private func makeWebView(reply: (Any?, String?),
                             baseURL: URL,
                             deniedPolicyFeatures: [String] = [],
                             messageHandler: (any WKScriptMessageHandlerWithReply)? = nil) async -> (WKWebView, MediaCaptureReplyHandler) {
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        configuration.userContentController = contentController

        let handler = MediaCaptureReplyHandler(reply: reply)
        let script = MediaCaptureUserScript()
        contentController.addScriptMessageHandler(messageHandler ?? handler,
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
                                            sandbox: String? = nil,
                                            removeSandboxAfterLoad: Bool = false,
                                            navigateAfterRemovingSandbox: Bool = false,
                                            shadowRootMode: String? = nil,
                                            allow: String? = nil,
                                            removeAllowAfterLoad: Bool = false,
                                            nestedFrame: Bool = false,
                                            allowAfterLoad: String? = nil,
                                            navigateAfterChangingAllow: Bool = false) async throws -> [String: Any] {
        try await webView.callAsyncJavaScript(
            """
            const iframe = document.createElement("iframe");
            if (sandbox !== null) {
                iframe.setAttribute("sandbox", sandbox);
            }
            if (allow !== null) {
                iframe.setAttribute("allow", allow);
            }
            let container = document.body;
            if (shadowRootMode !== null) {
                const host = document.createElement("div");
                document.body.appendChild(host);
                container = host.attachShadow({ mode: shadowRootMode });
            }
            const blob = new Blob([`
                <script>
                addEventListener("message", async () => {
                    let captureWindow = globalThis;
                    try {
                        if (${nestedFrame}) {
                            const child = document.createElement("iframe");
                            child.src = location.href;
                            const loaded = new Promise(resolve => child.addEventListener("load", resolve, { once: true }));
                            document.body.appendChild(child);
                            await loaded;
                            captureWindow = child.contentWindow;
                        }
                        const result = await captureWindow.navigator.mediaDevices.getUserMedia({ video: true });
                        parent.postMessage({ result, rejected: false, nativeCallCount: captureWindow.__nativeMediaCallCount }, "*");
                    } catch (error) {
                        parent.postMessage({ rejected: true, nativeCallCount: captureWindow.__nativeMediaCallCount }, "*");
                    }
                }, { once: true });
                </script>
                `], { type: "text/html" });
            const url = URL.createObjectURL(blob);
            iframe.src = url;
            const loaded = new Promise(resolve => iframe.addEventListener("load", resolve, { once: true }));
            container.appendChild(iframe);
            await loaded;
            if (removeSandboxAfterLoad) {
                iframe.removeAttribute("sandbox");
            }
            if (removeAllowAfterLoad) {
                iframe.removeAttribute("allow");
            }
            if (allowAfterLoad !== null) {
                iframe.setAttribute("allow", allowAfterLoad);
            }
            if (navigateAfterRemovingSandbox || navigateAfterChangingAllow) {
                iframe.removeAttribute("sandbox");
                const reloaded = new Promise(resolve => iframe.addEventListener("load", resolve, { once: true }));
                iframe.src = url;
                await reloaded;
            }
            // postMessage also works for an opaque child, whose DOM the parent cannot access.
            const result = await new Promise(resolve => {
                const receiveResult = event => {
                    if (event.source === iframe.contentWindow) {
                        removeEventListener("message", receiveResult);
                        resolve({ ...event.data, origin: event.origin });
                    }
                };
                addEventListener("message", receiveResult);
                iframe.contentWindow.postMessage("request-camera", "*");
            });
            iframe.remove();
            URL.revokeObjectURL(url);
            return result;
            """,
            arguments: ["sandbox": sandbox as Any? ?? NSNull(),
                        "removeSandboxAfterLoad": removeSandboxAfterLoad,
                        "navigateAfterRemovingSandbox": navigateAfterRemovingSandbox,
                        "shadowRootMode": shadowRootMode as Any? ?? NSNull(),
                        "allow": allow as Any? ?? NSNull(),
                        "removeAllowAfterLoad": removeAllowAfterLoad,
                        "nestedFrame": nestedFrame,
                        "allowAfterLoad": allowAfterLoad as Any? ?? NSNull(),
                        "navigateAfterChangingAllow": navigateAfterChangingAllow],
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
private final class MediaCapturePermissionDelegate: MediaCaptureUserScriptDelegate {
    var isMediaCapturePermissionHandlingEnabled = false
    private(set) var requestCount = 0

    func mediaCaptureUserScript(_ userScript: MediaCaptureUserScript,
                                requestPermissionFor permissionTypes: Set<SitePermissionType>,
                                requestID: String,
                                in frame: WKFrameInfo,
                                webView: WKWebView) async -> MediaCaptureBridgeDecision {
        requestCount += 1
        return .allow
    }
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
            if body["isEligible"] as? Bool == false,
               (reply.0 as? [String: String])?["decision"] != "bypass" {
                return (["decision": "deny"], nil)
            }
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
