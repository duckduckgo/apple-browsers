//
//  GeolocationUserScriptTests.swift
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
import WebKit
import XCTest
@testable import SitePermissions

@MainActor
final class GeolocationUserScriptTests: XCTestCase {

    func testSubfeatureServesThePageWorldFeatureAndEveryBridgeOperation() {
        let script = GeolocationUserScript()

        XCTAssertEqual(script.featureName, "sitePermissionsGeolocation")
        XCTAssertEqual(GeolocationUserScript.policyFeatureName, "sitePermissionsGeolocationPolicy")
        guard case .all = script.messageOriginPolicy else {
            return XCTFail("Every origin must reach the native policy checks")
        }
        for method in ["getCurrentPosition", "queryPermission", "startWatch", "clearWatch"] {
            XCTAssertNotNil(script.handler(forMethodNamed: method), "Expected a handler for \(method)")
        }
        XCTAssertNil(script.handler(forMethodNamed: "registerFrame"), "Frames need no registration")
        XCTAssertNil(script.handler(forMethodNamed: "requestPermission"))
    }

    func testFeatureSettingsCarryOnlyTheCapability() {
        let settings = GeolocationUserScript().featureSettings

        XCTAssertEqual(Set(settings.keys), ["capability"])
        XCTAssertEqual(settings["capability"] as? String, GeolocationUserScript.capabilityToken)
    }

    func testPolicyFeatureSettingsEnableItWithoutTheCapability() {
        let settings = GeolocationUserScript.policyFeatureSettings

        XCTAssertEqual(Set(settings.keys), ["enabled"])
        XCTAssertEqual(settings["enabled"] as? Bool, true)
    }

    func testUnauthenticatedMessagesAreDeniedBeforeAnyOtherCheck() async throws {
        let delegate = TestGeolocationUserScriptDelegate()
        let script = GeolocationUserScript(delegate: delegate)
        script.activationHandler = { _ in true }
        let webView = PolicyTestWebView()
        let frame = WKFrameInfo.mock(isMainFrame: true, securityOriginHost: "example.com", webView: webView)
        var body = requestBody(kind: "getCurrentPosition")
        body["capability"] = "forged"
        let message = MockWKScriptMessageObject(webView: webView, frameInfo: frame, body: body).scriptMessage

        let reply = await script.userContentController(WKUserContentController(), didReceive: message)

        let payload = try XCTUnwrap(reply.0 as? [String: Any])
        XCTAssertEqual(payload["status"] as? String, "error")
        XCTAssertEqual(payload["code"] as? Int, GeolocationPositionError.Code.permissionDenied.rawValue)
    }

    func testOptionsAcceptFiniteNonnegativeValues() {
        let options = GeolocationUserScript.options(from: [
            "options": [
                "enableHighAccuracy": true,
                "timeout": 12.5,
                "maximumAge": 60
            ]
        ])

        XCTAssertEqual(options, GeolocationRequestOptions(enableHighAccuracy: true, timeout: 0.0125, maximumAge: 0.06))
    }

    func testOptionsRejectNegativeAndNonfiniteValues() {
        let options = GeolocationUserScript.options(from: [
            "options": [
                "timeout": -1,
                "maximumAge": Double.infinity
            ]
        ])

        XCTAssertEqual(options, GeolocationRequestOptions())
    }

    func testOptionsPreserveInfiniteMaximumAge() {
        let options = GeolocationUserScript.options(from: ["options": ["maximumAge": "infinity"]])

        XCTAssertEqual(options.maximumAge, .infinity)
    }

    func testConstraintsDefaultToDenyWhenThePageOmitsGatingValues() {
        XCTAssertFalse(GeolocationUserScript.constraints(from: [:]).allowsRequest)
        XCTAssertTrue(GeolocationUserScript.constraints(from: [
            "isSecureContext": true,
            "isSandboxed": false,
            "isPolicyAllowed": true
        ]).allowsRequest)
    }

    func testPositionPayloadUsesWebGeolocationShape() throws {
        let coordinates = GeolocationPosition.Coordinates(latitude: 37.3317,
                                                          longitude: -122.0301,
                                                          accuracy: 4,
                                                          altitude: nil,
                                                          altitudeAccuracy: nil,
                                                          heading: 90,
                                                          speed: 2)
        let date = Date(timeIntervalSince1970: 123)

        let payload = GeolocationUserScript.positionPayload(.success(.init(coordinates: coordinates, timestamp: date)))
        let payloadCoordinates = try XCTUnwrap(payload["coords"] as? [String: Any])

        XCTAssertEqual(payload["status"] as? String, "success")
        XCTAssertEqual(payload["timestamp"] as? Double, 123_000)
        XCTAssertEqual(payloadCoordinates["latitude"] as? Double, 37.3317)
        XCTAssertEqual(payloadCoordinates["longitude"] as? Double, -122.0301)
        XCTAssertTrue(payloadCoordinates["altitude"] is NSNull)
    }

    func testDeallocatedDelegateProducesRepliesInsteadOfLeavingOneShotsPending() async throws {
        let script = GeolocationUserScript()
        script.activationHandler = { _ in true }
        let webView = PolicyTestWebView()
        let frame = WKFrameInfo.mock(isMainFrame: true, securityOriginHost: "example.com", webView: webView)
        let controller = WKUserContentController()
        var body = requestBody()

        var delegate: TestGeolocationUserScriptDelegate? = TestGeolocationUserScriptDelegate()
        weak let weakDelegate = delegate
        script.delegate = delegate
        delegate = nil

        XCTAssertNil(weakDelegate)

        body["kind"] = "getCurrentPosition"
        let positionMessage = MockWKScriptMessageObject(webView: webView, frameInfo: frame, body: body).scriptMessage
        let positionReply = await script.userContentController(controller, didReceive: positionMessage)
        let position = try XCTUnwrap(positionReply.0 as? [String: Any])

        body["kind"] = "queryPermission"
        body["statusID"] = String(repeating: "b", count: 32) + ":1"
        let permissionMessage = MockWKScriptMessageObject(webView: webView, frameInfo: frame, body: body).scriptMessage
        let permissionReply = await script.userContentController(controller, didReceive: permissionMessage)
        let permission = try XCTUnwrap(permissionReply.0 as? [String: Any])

        XCTAssertEqual(position["status"] as? String, "error")
        XCTAssertEqual(position["code"] as? Int, GeolocationPositionError.Code.positionUnavailable.rawValue)
        XCTAssertEqual(permission["status"] as? String, "permission")
        XCTAssertEqual(permission["state"] as? String, GeolocationPermissionState.denied.rawValue)
    }

    func testRequestsAreDeniedUntilTheAppActivatesTheFrame() async throws {
        let delegate = TestGeolocationUserScriptDelegate()
        let script = GeolocationUserScript(delegate: delegate)
        let webView = PolicyTestWebView()
        let frame = WKFrameInfo.mock(isMainFrame: true, securityOriginHost: "example.com", webView: webView)
        let message = MockWKScriptMessageObject(webView: webView, frameInfo: frame, body: requestBody()).scriptMessage

        let response = await script.userContentController(WKUserContentController(), didReceive: message)
        let payload = try XCTUnwrap(response.0 as? [String: Any])

        XCTAssertEqual(payload["code"] as? Int, GeolocationPositionError.Code.permissionDenied.rawValue)
        XCTAssertEqual(delegate.positionRequestCount, 0)
    }

    func testRequestRejectsInvalidDocumentIdentity() async throws {
        let delegate = TestGeolocationUserScriptDelegate()
        let script = GeolocationUserScript(delegate: delegate)
        script.activationHandler = { _ in true }
        let webView = PolicyTestWebView()
        let frame = WKFrameInfo.mock(isMainFrame: true, securityOriginHost: "example.com", webView: webView)
        var body = requestBody()
        body["documentID"] = String(repeating: "b", count: 129)
        let message = MockWKScriptMessageObject(webView: webView, frameInfo: frame, body: body).scriptMessage

        let response = await script.userContentController(WKUserContentController(), didReceive: message)
        let payload = try XCTUnwrap(response.0 as? [String: Any])

        XCTAssertEqual(payload["code"] as? Int, GeolocationPositionError.Code.permissionDenied.rawValue)
        XCTAssertEqual(delegate.positionRequestCount, 0)
    }

    func testWatchStartRejectsUnboundedRequestID() async throws {
        let delegate = TestGeolocationUserScriptDelegate()
        let script = GeolocationUserScript(delegate: delegate)
        script.activationHandler = { _ in true }
        let webView = PolicyTestWebView()
        let frame = WKFrameInfo.mock(isMainFrame: true, securityOriginHost: "example.com", webView: webView)

        var body = requestBody(kind: "startWatch")
        body["requestID"] = String(repeating: "b", count: 32) + ":" + String(repeating: "1", count: 96)
        let message = MockWKScriptMessageObject(webView: webView, frameInfo: frame, body: body).scriptMessage
        let response = await script.userContentController(WKUserContentController(), didReceive: message)
        let payload = try XCTUnwrap(response.0 as? [String: Any])

        XCTAssertEqual(payload["status"] as? String, "error")
        XCTAssertEqual(payload["code"] as? Int, GeolocationPositionError.Code.positionUnavailable.rawValue)
    }

    func testCallbacksMustBelongToTheRequestingDocument() async throws {
        let delegate = TestGeolocationUserScriptDelegate()
        let script = GeolocationUserScript(delegate: delegate)
        script.activationHandler = { _ in true }
        let webView = PolicyTestWebView()
        let frame = WKFrameInfo.mock(isMainFrame: true, securityOriginHost: "example.com", webView: webView)
        let otherDocumentCallback = String(repeating: "c", count: 32) + ":1"

        for kind in ["startWatch", "queryPermission"] {
            var body = requestBody(kind: kind)
            body["requestID"] = otherDocumentCallback
            body["statusID"] = otherDocumentCallback
            let message = MockWKScriptMessageObject(webView: webView, frameInfo: frame, body: body).scriptMessage
            _ = await script.userContentController(WKUserContentController(), didReceive: message)
        }

        XCTAssertEqual(delegate.watchCount, 0)
        XCTAssertEqual(delegate.permissionQueryCount, 0)
        XCTAssertFalse(script.send(.granted, toPermissionStatusWithID: otherDocumentCallback))
    }

    func testNonceAndRequestIDValidationUsesExactBoundedFormats() {
        let nonce = String(repeating: "a", count: 32)

        XCTAssertTrue(GeolocationUserScript.isValidNonce(nonce))
        XCTAssertFalse(GeolocationUserScript.isValidNonce(String(repeating: "a", count: 31)))
        XCTAssertFalse(GeolocationUserScript.isValidNonce(String(repeating: "A", count: 32)))
        XCTAssertTrue(GeolocationUserScript.isValidRequestID(nonce + ":1"))
        XCTAssertFalse(GeolocationUserScript.isValidRequestID(nonce + ":0"))
        XCTAssertFalse(GeolocationUserScript.isValidRequestID(nonce + ":1:2"))
        XCTAssertFalse(GeolocationUserScript.isValidRequestID(nonce + ":" + String(repeating: "1", count: 96)))
        XCTAssertTrue(GeolocationUserScript.isCallbackID(nonce + ":1", ownedBy: nonce))
        XCTAssertFalse(GeolocationUserScript.isCallbackID(nonce + ":1", ownedBy: String(repeating: "b", count: 32)))
    }

    func testRequestsAuthenticateAcrossFrameInfoWrappers() async throws {
        let script = GeolocationUserScript()
        script.activationHandler = { _ in true }
        let webView = PolicyTestWebView()

        for _ in 0..<2 {
            let frameWrapper = WKFrameInfo.mock(isMainFrame: true, securityOriginHost: "example.com", webView: webView)
            var queryBody = requestBody(kind: "queryPermission")
            queryBody["statusID"] = String(repeating: "b", count: 32) + ":\(Int.random(in: 1...1_000_000))"
            let queryMessage = MockWKScriptMessageObject(webView: webView, frameInfo: frameWrapper, body: queryBody).scriptMessage
            let queryResponse = await script.userContentController(WKUserContentController(), didReceive: queryMessage)
            let queryPayload = try XCTUnwrap(queryResponse.0 as? [String: Any])

            XCTAssertEqual(queryPayload["status"] as? String, "permission")
            XCTAssertEqual(queryPayload["state"] as? String, "denied")
        }
    }

    func testWhenRequestNamesAnotherTabsOrAPreviousDocumentThenItNeverReachesDelegate() async throws {
        let delegate = TestGeolocationUserScriptDelegate()
        let script = GeolocationUserScript(delegate: delegate)
        script.activationHandler = { _ in true }
        let webView = PolicyTestWebView()
        let frame = WKFrameInfo.mock(isMainFrame: true, securityOriginHost: "example.com", webView: webView)
        let controller = WKUserContentController()

        let validRequest = MockWKScriptMessageObject(webView: webView, frameInfo: frame, body: requestBody()).scriptMessage
        _ = await script.userContentController(controller, didReceive: validRequest)
        XCTAssertEqual(delegate.positionRequestCount, 1)

        // Another tab's isolated world reports its own page document.
        let otherWebView = PolicyTestWebView()
        otherWebView.pageDocumentID = String(repeating: "d", count: 32)
        let otherFrame = WKFrameInfo.mock(isMainFrame: true, securityOriginHost: "example.com", webView: otherWebView)
        let otherTabRequest = MockWKScriptMessageObject(webView: otherWebView, frameInfo: otherFrame, body: requestBody()).scriptMessage
        let otherTabResponse = await script.userContentController(controller, didReceive: otherTabRequest)
        XCTAssertEqual((otherTabResponse.0 as? [String: Any])?["code"] as? Int,
                       GeolocationPositionError.Code.permissionDenied.rawValue)
        XCTAssertEqual(delegate.positionRequestCount, 1)

        webView.pageDocumentID = String(repeating: "d", count: 32)
        let staleResponse = await script.userContentController(controller, didReceive: validRequest)
        XCTAssertEqual((staleResponse.0 as? [String: Any])?["code"] as? Int,
                       GeolocationPositionError.Code.permissionDenied.rawValue)
        XCTAssertEqual(delegate.positionRequestCount, 1, "A request from a replaced document must not reach the delegate")
    }

    func testPermissionStatusRegistryClearsOnPageReset() async throws {
        let delegate = TestGeolocationUserScriptDelegate()
        let script = GeolocationUserScript(delegate: delegate)
        script.activationHandler = { _ in true }
        let webView = PolicyTestWebView()
        let frame = WKFrameInfo.mock(isMainFrame: true, securityOriginHost: "example.com", webView: webView)
        let statusID = String(repeating: "b", count: 32) + ":1"
        var queryBody = requestBody(kind: "queryPermission")
        queryBody["statusID"] = statusID
        let queryMessage = MockWKScriptMessageObject(webView: webView, frameInfo: frame, body: queryBody).scriptMessage

        _ = await script.userContentController(WKUserContentController(), didReceive: queryMessage)
        XCTAssertTrue(script.send(.granted, toPermissionStatusWithID: statusID))

        script.cancelAllWatches()

        XCTAssertFalse(script.send(.denied, toPermissionStatusWithID: statusID))
        XCTAssertEqual(delegate.cancelledPermissionStatusIDs, [statusID])
    }

    func testWatchRegistryRoutesRepeatedResultsUntilCancellation() {
        let registry = GeolocationWatchRegistry()
        var firstScripts = [String]()
        var secondScripts = [String]()

        XCTAssertTrue(registry.register("frame-a:1", owner: "a", documentID: "isolated-document") { script, completion in firstScripts.append(script); completion(true) })
        XCTAssertTrue(registry.register("frame-b:1", owner: "b", documentID: "isolated-document") { script, completion in secondScripts.append(script); completion(true) })
        XCTAssertFalse(registry.register("frame-a:1", owner: "a", documentID: "isolated-document") { _, completion in completion(true) })

        XCTAssertTrue(registry.send("first", to: "frame-a:1"))
        XCTAssertTrue(registry.send("second", to: "frame-a:1"))
        XCTAssertTrue(registry.send("other-frame", to: "frame-b:1"))
        XCTAssertEqual(firstScripts, ["first", "second"])
        XCTAssertEqual(secondScripts, ["other-frame"])

        XCTAssertFalse(registry.remove("frame-a:1", owner: "forged"))
        XCTAssertTrue(registry.remove("frame-a:1", owner: "a"))
        XCTAssertFalse(registry.send("late", to: "frame-a:1"))
        XCTAssertEqual(firstScripts, ["first", "second"])
    }

    func testWatchRegistryReportsWhenAFrameCannotEvaluate() {
        let registry = GeolocationWatchRegistry()
        XCTAssertTrue(registry.register("frame:1", owner: "owner", documentID: "isolated-document") { _, completion in completion(false) })

        var succeeded = true
        XCTAssertTrue(registry.send("result", to: "frame:1") { succeeded = $0 })
        XCTAssertFalse(succeeded)
    }

    func testRemovingAllWatchesPreventsLateCallbacks() {
        let registry = GeolocationWatchRegistry()
        var callbackCount = 0
        XCTAssertTrue(registry.register("frame:1", owner: "a", documentID: "isolated-document") { _, completion in callbackCount += 1; completion(true) })
        XCTAssertTrue(registry.register("frame:2", owner: "b", documentID: "isolated-document") { _, completion in callbackCount += 1; completion(true) })

        XCTAssertEqual(Set(registry.removeAll()), Set(["frame:1", "frame:2"]))
        XCTAssertEqual(registry.count, 0)
        XCTAssertFalse(registry.send("late", to: "frame:1"))
        XCTAssertEqual(callbackCount, 0)
    }

    func testTakingTerminalWatchRemovesItBeforeDelivery() throws {
        let registry = GeolocationWatchRegistry()
        XCTAssertTrue(registry.register("frame:1", owner: "owner", documentID: "isolated-document") { _, completion in completion(true) })

        let callback = try XCTUnwrap(registry.take("frame:1"))

        XCTAssertEqual(registry.count, 0)
        XCTAssertFalse(registry.send("late", to: "frame:1"))
        callback("terminal") { _ in }
    }

    func testNativePolicyIsRequiredAndRecheckedForEveryOperation() async throws {
        let delegate = TestGeolocationUserScriptDelegate()
        let script = GeolocationUserScript(delegate: delegate)
        script.activationHandler = { _ in true }
        let webView = PolicyTestWebView()
        let frame = WKFrameInfo.mock(isMainFrame: true, securityOriginHost: "example.com", webView: webView)
        let controller = WKUserContentController()

        for kind in ["getCurrentPosition", "queryPermission", "startWatch"] {
            var body = requestBody(kind: kind)
            body["requestID"] = String(repeating: "b", count: 32) + ":1"
            body["statusID"] = String(repeating: "b", count: 32) + ":2"
            let message = MockWKScriptMessageObject(webView: webView, frameInfo: frame, body: body).scriptMessage
            _ = await script.userContentController(controller, didReceive: message)
        }
        XCTAssertEqual(delegate.positionRequestCount, 1)
        XCTAssertEqual(delegate.permissionQueryCount, 1)
        XCTAssertEqual(delegate.watchCount, 1)

        let allowedPolicy = webView.policy
        for policy in [nil,
                       allowedPolicy?.merging(["isSandboxed": true]) { _, new in new },
                       allowedPolicy?.merging(["pageDocumentID": String(repeating: "d", count: 32)]) { _, new in new }] {
            webView.policy = policy
            for kind in ["getCurrentPosition", "queryPermission", "startWatch"] {
                var body = requestBody(kind: kind)
                body["requestID"] = String(repeating: "b", count: 32) + ":3"
                body["statusID"] = String(repeating: "b", count: 32) + ":4"
                let message = MockWKScriptMessageObject(webView: webView, frameInfo: frame, body: body).scriptMessage
                let reply = await script.userContentController(controller, didReceive: message)
                let payload = try XCTUnwrap(reply.0 as? [String: Any])
                if kind == "queryPermission", policy?["isSandboxed"] as? Bool == true {
                    XCTAssertEqual(payload["status"] as? String, "permission")
                    XCTAssertEqual(payload["state"] as? String, "denied")
                } else {
                    XCTAssertEqual(payload["code"] as? Int, GeolocationPositionError.Code.permissionDenied.rawValue)
                }
            }
        }
        webView.policy = allowedPolicy
        webView.pageDocumentID = String(repeating: "d", count: 32)
        let body = requestBody()
        let staleDocumentRequest = MockWKScriptMessageObject(webView: webView, frameInfo: frame, body: body).scriptMessage
        let staleDocumentReply = await script.userContentController(controller, didReceive: staleDocumentRequest)
        XCTAssertEqual((staleDocumentReply.0 as? [String: Any])?["code"] as? Int,
                       GeolocationPositionError.Code.permissionDenied.rawValue)
        XCTAssertEqual(delegate.positionRequestCount, 1)
        XCTAssertEqual(delegate.permissionQueryCount, 1)
        XCTAssertEqual(delegate.watchCount, 1)
    }

    func testRequestCannotCompleteAfterLifecycleResetOrDocumentReplacement() async throws {
        for documentReplaced in [false, true] {
            let delegate = TestGeolocationUserScriptDelegate()
            let script = GeolocationUserScript(delegate: delegate)
            script.activationHandler = { _ in true }
            let webView = PolicyTestWebView()
            let evaluationStarted = expectation(description: "Isolated policy evaluation started")
            webView.policyEvaluationStarted = evaluationStarted
            webView.suspendsPolicyEvaluation = true
            let frame = WKFrameInfo.mock(isMainFrame: true, securityOriginHost: "example.com", webView: webView)
            let controller = WKUserContentController()
            let request = MockWKScriptMessageObject(webView: webView, frameInfo: frame, body: requestBody()).scriptMessage
            let task = Task { await script.userContentController(controller, didReceive: request) }
            await fulfillment(of: [evaluationStarted], timeout: 2)

            if documentReplaced {
                webView.pageDocumentID = String(repeating: "d", count: 32)
            } else {
                script.cancelAllWatches()
            }
            webView.completePolicyEvaluation()
            let response = await task.value
            XCTAssertEqual((response.0 as? [String: Any])?["code"] as? Int,
                           GeolocationPositionError.Code.permissionDenied.rawValue)
            XCTAssertEqual(delegate.positionRequestCount, 0)

            // After a reset, the same document may ask again; a replaced document's requests stay denied.
            _ = await script.userContentController(controller, didReceive: request)
            XCTAssertEqual(delegate.positionRequestCount, documentReplaced ? 0 : 1)
        }
    }

    private func requestBody(kind: String = "getCurrentPosition") -> [String: Any] {
        [
            "kind": kind,
            "capability": GeolocationUserScript.capabilityToken,
            "documentID": String(repeating: "b", count: 32)
        ]
    }
}

@MainActor
private final class TestGeolocationUserScriptDelegate: GeolocationUserScriptDelegate {

    private(set) var cancelledPermissionStatusIDs = [String]()
    private(set) var positionRequestCount = 0
    private(set) var permissionQueryCount = 0
    private(set) var watchCount = 0

    func geolocationUserScript(_ userScript: GeolocationUserScript,
                               getCurrentPositionWith options: GeolocationRequestOptions,
                               constraints: GeolocationRequestConstraints,
                               in frame: GeolocationFrame) async -> GeolocationPositionResult {
        positionRequestCount += 1
        return .failure(.init(code: .positionUnavailable, message: "Unavailable"))
    }

    func geolocationUserScript(_ userScript: GeolocationUserScript,
                               permissionStatusID: String,
                               constraints: GeolocationRequestConstraints,
                               permissionStateIn frame: GeolocationFrame) -> GeolocationPermissionState {
        permissionQueryCount += 1
        return .denied
    }

    func geolocationUserScript(_ userScript: GeolocationUserScript,
                               didStartWatchWithID requestID: String,
                               options: GeolocationRequestOptions,
                               constraints: GeolocationRequestConstraints,
                               in frame: GeolocationFrame) {
        watchCount += 1
    }

    func geolocationUserScript(_ userScript: GeolocationUserScript,
                               didCancelWatchWithID requestID: String) {}

    func geolocationUserScript(_ userScript: GeolocationUserScript,
                               didCancelPermissionStatusWithID statusID: String) {
        cancelledPermissionStatusIDs.append(statusID)
    }
}

@MainActor
private final class PolicyTestWebView: WKWebView {

    var policy: [String: Any]? = [
        "documentID": String(repeating: "c", count: 32),
        "isSecureContext": true,
        "isSandboxed": false,
        "isPolicyAllowed": true
    ]
    /// The page feature's identity, which the isolated world reports alongside `policy`.
    var pageDocumentID = String(repeating: "b", count: 32)
    var suspendsPolicyEvaluation = false
    var policyEvaluationStarted: XCTestExpectation?
    private var policyCompletion: (@MainActor @Sendable (Any?, Error?) -> Void)?

    override func __callAsyncJavaScript(_ functionBody: String,
                                        arguments: [String: Any]?,
                                        inFrame frame: WKFrameInfo?,
                                        in contentWorld: WKContentWorld,
                                        completionHandler: (@MainActor @Sendable (Any?, Error?) -> Void)?) {
        XCTAssertEqual(contentWorld, .defaultClient)
        XCTAssertNotNil(frame)
        if suspendsPolicyEvaluation {
            policyCompletion = completionHandler
            policyEvaluationStarted?.fulfill()
        } else {
            completionHandler?(policyReply, nil)
        }
    }

    private var policyReply: [String: Any]? {
        policy?.merging(["pageDocumentID": pageDocumentID]) { reported, _ in reported }
    }

    func completePolicyEvaluation() {
        let completion = policyCompletion
        policyCompletion = nil
        suspendsPolicyEvaluation = false
        completion?(policyReply, nil)
    }

    override func __evaluateJavaScript(_ javaScriptString: String,
                                       inFrame frame: WKFrameInfo?,
                                       in contentWorld: WKContentWorld,
                                       completionHandler: (@MainActor @Sendable (Any?, Error?) -> Void)?) {
        XCTAssertEqual(contentWorld, .defaultClient)
        XCTAssertNotNil(frame)
        completionHandler?(true, nil)
    }
}
