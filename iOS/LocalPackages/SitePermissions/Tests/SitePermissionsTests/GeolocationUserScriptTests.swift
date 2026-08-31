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

    func testScriptUsesPageWorldAtDocumentStartInEveryFrame() {
        let script = GeolocationUserScript()

        XCTAssertEqual(script.injectionTime, .atDocumentStart)
        XCTAssertFalse(script.forMainFrameOnly)
        XCTAssertTrue(script.requiresRunInPageContentWorld)
        XCTAssertEqual(script.messageNames, ["sitePermissionsGeolocation", "sitePermissionsGeolocationWatch"])
    }

    func testScriptSourceLoadsFromPackageAndContainsAllBridgeOperations() {
        let source = GeolocationUserScript().source

        for operation in ["registerFrame", "getCurrentPosition", "watchPosition", "clearWatch", "queryPermission",
                          "receiveWatchResult", "receiveTerminalWatchResult", "receivePermissionState"] {
            XCTAssertTrue(source.contains(operation), "Expected shim source to contain \(operation)")
        }
        XCTAssertTrue(source.contains("!activeWatches.has(requestID)"), "A cleared watch must compensate if native start wins the race")
        XCTAssertTrue(source.contains("postMessage.bind"), "Page code must not replace the captured native bridge functions")
        XCTAssertTrue(source.contains("const isSecureContext = globalThis.isSecureContext === true"),
                      "The secure-context constraint must be captured before page scripts run")
        XCTAssertTrue(source.contains("globalThis.top.location.origin === globalThis.location.origin"),
                      "Only frames with the top-level origin may use the v1 fallback")
        XCTAssertTrue(source.contains("globalThis.location.hostname.length > 0"),
                      "Opaque and synthetic documents must fail closed")
        XCTAssertTrue(source.contains("globalThis.origin !== \"null\""))
        XCTAssertTrue(source.contains("globalThis.location.protocol === \"https:\" || globalThis.location.protocol === \"http:\""),
                      "Only network documents may use the shim")
        XCTAssertTrue(source.contains("return true;\n        } catch (_)"),
                      "A missing policy API must use the v1 self-only fallback rather than denying first-party pages")
        XCTAssertTrue(source.contains("isPolicyAllowed: isFramePolicyEligible && policyAllowsGeolocation()"),
                      "Every request and permission query must share the same policy constraint")
        XCTAssertTrue(source.contains("const nativePermissionsPolicy = document.permissionsPolicy ?? document.featurePolicy"))
        XCTAssertTrue(source.contains("apply(nativePolicyAllowsFeature, nativePermissionsPolicy, [\"geolocation\"])"),
                      "Page code must not replace the captured policy API before a later resample")
        XCTAssertTrue(source.contains("embeddingFrameForSource(source)"),
                      "The parent must map each authenticated child to its direct embedding element")
        XCTAssertTrue(source.contains("attributeOldValue: true"),
                      "Sandbox removal must retain the prior attribute value")
        XCTAssertTrue(source.contains("sandboxedEmbeddingFrames"),
                      "An embedding frame that was ever sandboxed must stay fail-closed for its surviving document")
        XCTAssertTrue(source.contains("apply(weakSetHas, sandboxedEmbeddingFrames, [embeddingFrame])"))
        XCTAssertTrue(source.contains("const ancestorSandboxed = await sandboxVerdict"),
                      "A child must inherit the sandbox verdict from every ancestor")
        XCTAssertTrue(source.contains("signHMAC(\"HMAC\""),
                      "The page-visible probe must authenticate without exposing the native capability")
        XCTAssertTrue(source.contains("sandboxProbeTimeout = scheduleTask(() => finishSandboxProbe(true)"),
                      "An unanswered parent probe must fail closed")
        XCTAssertTrue(source.contains("const registration = registerFrame()"),
                      "Native registration must wait for the authenticated sandbox verdict")
        XCTAssertTrue(source.contains("message(\"registerFrame\")"), "Each frame must authenticate before sending requests")
        XCTAssertTrue(source.contains("const capability ="), "Every message must carry the native bridge capability")
        XCTAssertTrue(source.contains("configurable: false"), "The installed API must not reveal native methods after deletion")
        XCTAssertTrue(source.contains("Object.getPrototypeOf(nativeGeolocation)"), "Direct native-prototype calls must route through the shim")
        XCTAssertTrue(source.contains("Object.getPrototypeOf(nativePermissions)"), "Direct Permissions prototype calls must route through the shim")
        XCTAssertTrue(source.contains("scheduleTask(() => { throw exception; }, 0)"),
                      "Callback exceptions must be reported in a later task without terminating native watch routing")
        XCTAssertFalse(source.contains("${CAPABILITY_TOKEN}"), "The package must replace the native bridge capability")
        XCTAssertFalse(source.contains("${INSTALL_IMMEDIATELY}"), "The package must replace the installation mode")
        XCTAssertTrue(source.contains("const installImmediately = false"), "The default script must leave non-tab WebViews untouched")

        let terminalStart = try? XCTUnwrap(source.range(of: "const receiveTerminalWatchResult"))
        let delete = terminalStart.flatMap { source.range(of: "activeWatches.delete(requestID)", range: $0.lowerBound..<source.endIndex) }
        let callback = terminalStart.flatMap { source.range(of: "settlePosition(result", range: $0.lowerBound..<source.endIndex) }
        XCTAssertNotNil(delete)
        XCTAssertNotNil(callback)
        if let delete, let callback {
            XCTAssertLessThan(delete.lowerBound, callback.lowerBound, "Terminal delivery must remove page state before invoking callbacks")
        }
    }

    func testImmediateInstallationHardensBeforeRegistrationAndBypassesOnlyDuckAIHosts() {
        let source = GeolocationUserScript(installImmediately: true).source

        XCTAssertTrue(source.contains("const installImmediately = true"))
        XCTAssertTrue(source.contains("initialHostname === \"duck.ai\""))
        XCTAssertTrue(source.contains("initialHostname.endsWith(\".duck.ai\")"))
        XCTAssertFalse(source.contains("initialHostname === \"duckduckgo.com\""))
        let install = source.range(of: "if (installImmediately) {\n        installShim();")
        let registrationReply = source.range(of: "registration.then((enabled) => {\n        if (enabled && !installImmediately)")
        XCTAssertNotNil(install)
        XCTAssertNotNil(registrationReply)
        if let install, let registrationReply {
            XCTAssertLessThan(install.lowerBound, registrationReply.lowerBound)
        }
    }

    func testEachOperationRefreshesNativeFrameRegistration() {
        let source = GeolocationUserScript().source

        XCTAssertTrue(source.contains("const registerFrame = () => sandboxVerdict"))
        XCTAssertEqual(source.components(separatedBy: "registerFrame().then((enabled)").count - 1, 4,
                       "Position requests, permission queries, watch starts, and watch cancellation must recover after native registration resets")
    }

    func testPolicyIsResampledForRegistrationAndImmediatelyBeforeOperations() {
        let source = GeolocationUserScript().source

        XCTAssertTrue(source.contains("constraints = currentConstraints(isSandboxed);\n            return postOneShot(message(\"registerFrame\"))"))
        XCTAssertTrue(source.contains("const isAllowedByPlatform = () => {\n        constraints = currentConstraints(constraints.isSandboxed);"))
        XCTAssertTrue(source.contains("const receiveWatchResult = (requestID, result) => {"))
        XCTAssertTrue(source.contains("if (!isAllowedByPlatform()) {\n                activeWatches.delete(requestID);"),
                      "A restrictive policy change must stop later watch deliveries")
        XCTAssertTrue(source.contains("settlePosition(isAllowedByPlatform() ? result : deniedResult(), success, error)"),
                      "A newly restrictive policy must suppress an in-flight one-shot result")
        XCTAssertTrue(source.contains("record.initialize(isAllowedByPlatform() ? normalizedPermissionState(result?.state) : \"denied\")"),
                      "A newly restrictive policy must suppress an in-flight query result")
        XCTAssertTrue(source.contains("record.update(isAllowedByPlatform() ? state : \"denied\")"),
                      "A policy change must fail closed when native refreshes an existing status")
        XCTAssertTrue(source.contains("result?.status === \"started\" && !isAllowedByPlatform()"),
                      "A newly restrictive policy must cancel an in-flight watch start")
        XCTAssertFalse(source.contains("staticConstraints"))
    }

    func testScriptPayloadsDoNotDefineHostOriginOrURLFields() {
        let source = GeolocationUserScript().source.lowercased()

        XCTAssertFalse(source.contains("host:"))
        XCTAssertFalse(source.contains("origin:"))
        XCTAssertFalse(source.contains("url:"))
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

    func testDeallocatedDelegateProducesRepliesInsteadOfLeavingOneShotsPending() async {
        let script = GeolocationUserScript()
        var delegate: TestGeolocationUserScriptDelegate? = TestGeolocationUserScriptDelegate()
        weak let weakDelegate = delegate
        script.delegate = delegate
        delegate = nil

        XCTAssertNil(weakDelegate)

        let constraints = GeolocationRequestConstraints(isSecureContext: true, isSandboxed: false, isPolicyAllowed: true)
        let position = await script.handleOneShot(.getCurrentPosition, body: [:], frame: nil, constraints: constraints)
        let permission = await script.handleOneShot(.queryPermission, body: [:], frame: nil, constraints: constraints)

        XCTAssertEqual(position["status"] as? String, "error")
        XCTAssertEqual(position["code"] as? Int, GeolocationPositionError.Code.positionUnavailable.rawValue)
        XCTAssertEqual(permission["status"] as? String, "permission")
        XCTAssertEqual(permission["state"] as? String, GeolocationPermissionState.denied.rawValue)
    }

    func testFrameRegistrationIsDisabledUntilTheAppExplicitlyActivatesIt() async throws {
        let script = GeolocationUserScript()
        let webView = WKWebView()
        let frame = WKFrameInfo.mock(isMainFrame: true, securityOriginHost: "example.com", webView: webView)
        let message = MockWKScriptMessageObject(webView: webView,
                                                frameInfo: frame,
                                                body: registrationBody()).scriptMessage

        let response = await script.userContentController(WKUserContentController(), didReceive: message)
        let payload = try XCTUnwrap(response.0 as? [String: Any])

        XCTAssertEqual(payload["status"] as? String, "registered")
        XCTAssertEqual(payload["enabled"] as? Bool, false)
    }

    func testFrameRegistrationRejectsInvalidNonce() async throws {
        let script = GeolocationUserScript()
        script.activationHandler = { _ in true }
        let webView = WKWebView()
        let frame = WKFrameInfo.mock(isMainFrame: true, securityOriginHost: "example.com", webView: webView)
        var body = registrationBody()
        body["nonce"] = String(repeating: "a", count: 129)
        let message = MockWKScriptMessageObject(webView: webView, frameInfo: frame, body: body).scriptMessage

        let response = await script.userContentController(WKUserContentController(), didReceive: message)
        let payload = try XCTUnwrap(response.0 as? [String: Any])

        XCTAssertEqual(payload["status"] as? String, "error")
        XCTAssertEqual(payload["code"] as? Int, GeolocationPositionError.Code.permissionDenied.rawValue)
    }

    func testWatchStartRejectsUnboundedRequestID() async throws {
        let delegate = TestGeolocationUserScriptDelegate()
        let script = GeolocationUserScript(delegate: delegate)
        script.activationHandler = { _ in true }
        let webView = WKWebView()
        let frame = WKFrameInfo.mock(isMainFrame: true, securityOriginHost: "example.com", webView: webView)
        let registrationMessage = MockWKScriptMessageObject(webView: webView,
                                                            frameInfo: frame,
                                                            body: registrationBody()).scriptMessage
        _ = await script.userContentController(WKUserContentController(), didReceive: registrationMessage)

        var body = registrationBody()
        body["kind"] = "startWatch"
        body["requestID"] = String(repeating: "a", count: 32) + ":" + String(repeating: "1", count: 96)
        let message = MockWKScriptMessageObject(webView: webView, frameInfo: frame, body: body).scriptMessage
        let response = await script.userContentController(WKUserContentController(), didReceive: message)
        let payload = try XCTUnwrap(response.0 as? [String: Any])

        XCTAssertEqual(payload["status"] as? String, "error")
        XCTAssertEqual(payload["code"] as? Int, GeolocationPositionError.Code.positionUnavailable.rawValue)
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
    }

    func testEnabledRegistrationAuthenticatesLaterMessagesAcrossFrameInfoWrappers() async throws {
        let script = GeolocationUserScript()
        script.activationHandler = { _ in true }
        let webView = WKWebView()
        let firstFrame = WKFrameInfo.mock(isMainFrame: true, securityOriginHost: "example.com", webView: webView)
        let registrationMessage = MockWKScriptMessageObject(webView: webView,
                                                            frameInfo: firstFrame,
                                                            body: registrationBody()).scriptMessage
        let registrationResponse = await script.userContentController(WKUserContentController(), didReceive: registrationMessage)

        XCTAssertEqual((registrationResponse.0 as? [String: Any])?["enabled"] as? Bool, true)

        let laterFrameWrapper = WKFrameInfo.mock(isMainFrame: true, securityOriginHost: "example.com", webView: webView)
        var queryBody = registrationBody()
        queryBody["kind"] = "queryPermission"
        queryBody["statusID"] = String(repeating: "b", count: 32) + ":1"
        let queryMessage = MockWKScriptMessageObject(webView: webView,
                                                     frameInfo: laterFrameWrapper,
                                                     body: queryBody).scriptMessage
        let queryResponse = await script.userContentController(WKUserContentController(), didReceive: queryMessage)
        let queryPayload = try XCTUnwrap(queryResponse.0 as? [String: Any])

        XCTAssertEqual(queryPayload["status"] as? String, "permission")
        XCTAssertEqual(queryPayload["state"] as? String, "denied")
    }

    func testPermissionStatusRegistryClearsOnPageReset() async throws {
        let delegate = TestGeolocationUserScriptDelegate()
        let script = GeolocationUserScript(delegate: delegate)
        script.activationHandler = { _ in true }
        let webView = WKWebView()
        let frame = WKFrameInfo.mock(isMainFrame: true, securityOriginHost: "example.com", webView: webView)
        let registrationMessage = MockWKScriptMessageObject(webView: webView,
                                                            frameInfo: frame,
                                                            body: registrationBody()).scriptMessage
        _ = await script.userContentController(WKUserContentController(), didReceive: registrationMessage)
        let statusID = String(repeating: "b", count: 32) + ":1"
        var queryBody = registrationBody()
        queryBody["kind"] = "queryPermission"
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

        XCTAssertTrue(registry.register("frame-a:1", nonce: "a") { script, completion in firstScripts.append(script); completion(true) })
        XCTAssertTrue(registry.register("frame-b:1", nonce: "b") { script, completion in secondScripts.append(script); completion(true) })
        XCTAssertFalse(registry.register("frame-a:1", nonce: "a") { _, completion in completion(true) })

        XCTAssertTrue(registry.send("first", to: "frame-a:1"))
        XCTAssertTrue(registry.send("second", to: "frame-a:1"))
        XCTAssertTrue(registry.send("other-frame", to: "frame-b:1"))
        XCTAssertEqual(firstScripts, ["first", "second"])
        XCTAssertEqual(secondScripts, ["other-frame"])

        XCTAssertFalse(registry.remove("frame-a:1", nonce: "forged"))
        XCTAssertTrue(registry.remove("frame-a:1", nonce: "a"))
        XCTAssertFalse(registry.send("late", to: "frame-a:1"))
        XCTAssertEqual(firstScripts, ["first", "second"])
    }

    func testWatchRegistryReportsWhenAFrameCannotEvaluate() {
        let registry = GeolocationWatchRegistry()
        XCTAssertTrue(registry.register("frame:1", nonce: "nonce") { _, completion in completion(false) })

        var succeeded = true
        XCTAssertTrue(registry.send("result", to: "frame:1") { succeeded = $0 })
        XCTAssertFalse(succeeded)
    }

    func testRemovingAllWatchesPreventsLateCallbacks() {
        let registry = GeolocationWatchRegistry()
        var callbackCount = 0
        XCTAssertTrue(registry.register("frame:1", nonce: "a") { _, completion in callbackCount += 1; completion(true) })
        XCTAssertTrue(registry.register("frame:2", nonce: "b") { _, completion in callbackCount += 1; completion(true) })

        XCTAssertEqual(Set(registry.removeAll()), Set(["frame:1", "frame:2"]))
        XCTAssertEqual(registry.count, 0)
        XCTAssertFalse(registry.send("late", to: "frame:1"))
        XCTAssertEqual(callbackCount, 0)
    }

    func testTakingTerminalWatchRemovesItBeforeDelivery() throws {
        let registry = GeolocationWatchRegistry()
        XCTAssertTrue(registry.register("frame:1", nonce: "nonce") { _, completion in completion(true) })

        let callback = try XCTUnwrap(registry.take("frame:1"))

        XCTAssertEqual(registry.count, 0)
        XCTAssertFalse(registry.send("late", to: "frame:1"))
        callback("terminal") { _ in }
    }

    func testFrameRegistrationRejectsForgedNonceAndOverwrite() throws {
        let store = GeolocationFrameRegistrationStore()
        let constraints = GeolocationRequestConstraints(isSecureContext: true, isSandboxed: false, isPolicyAllowed: true)
        let webView = WKWebView()
        let frame = GeolocationNativeFrameIdentity(webViewID: ObjectIdentifier(webView),
                                                   scheme: "https",
                                                   host: "example.com",
                                                   port: 0,
                                                   isMainFrame: true)
        let otherFrame = GeolocationNativeFrameIdentity(webViewID: ObjectIdentifier(webView),
                                                        scheme: "https",
                                                        host: "frame.example.com",
                                                        port: 0,
                                                        isMainFrame: false)
        XCTAssertTrue(store.register(nonce: "native-nonce", frame: frame, constraints: constraints))

        XCTAssertNil(store.registration(for: "forged-nonce", frame: frame))
        XCTAssertNil(store.registration(for: "native-nonce", frame: otherFrame))
        XCTAssertEqual(try XCTUnwrap(store.registration(for: "native-nonce", frame: frame)).constraints, constraints)

        store.removeAll()
        XCTAssertEqual(store.count, 0)
        XCTAssertNil(store.registration(for: "native-nonce", frame: frame))
    }

    private func registrationBody() -> [String: Any] {
        [
            "kind": "registerFrame",
            "capability": GeolocationUserScript.capabilityToken,
            "nonce": String(repeating: "a", count: 32),
            "isSecureContext": true,
            "isSandboxed": false,
            "isPolicyAllowed": true
        ]
    }
}

@MainActor
private final class TestGeolocationUserScriptDelegate: GeolocationUserScriptDelegate {

    private(set) var cancelledPermissionStatusIDs = [String]()

    func geolocationUserScript(_ userScript: GeolocationUserScript,
                               getCurrentPositionWith options: GeolocationRequestOptions,
                               constraints: GeolocationRequestConstraints,
                               in frame: GeolocationFrame) async -> GeolocationPositionResult {
        .failure(.init(code: .positionUnavailable, message: "Unavailable"))
    }

    func geolocationUserScript(_ userScript: GeolocationUserScript,
                               permissionStatusID: String,
                               constraints: GeolocationRequestConstraints,
                               permissionStateIn frame: GeolocationFrame) -> GeolocationPermissionState {
        .denied
    }

    func geolocationUserScript(_ userScript: GeolocationUserScript,
                               didStartWatchWithID requestID: String,
                               options: GeolocationRequestOptions,
                               constraints: GeolocationRequestConstraints,
                               in frame: GeolocationFrame) {}

    func geolocationUserScript(_ userScript: GeolocationUserScript,
                               didCancelWatchWithID requestID: String) {}

    func geolocationUserScript(_ userScript: GeolocationUserScript,
                               didCancelPermissionStatusWithID statusID: String) {
        cancelledPermissionStatusIDs.append(statusID)
    }
}
