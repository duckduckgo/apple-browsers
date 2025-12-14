//
//  AutofillEmailUserScriptTests.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import WebKit
import UserScript
@testable import BrowserServicesKit

class AutofillEmailUserScriptTests: XCTestCase {

    let userScript: AutofillUserScript = {
        let embeddedConfig =
        """
        {
            "features": {
                "autofill": {
                    "status": "enabled",
                    "exceptions": []
                }
            },
            "unprotectedTemporary": []
        }
        """.data(using: .utf8)!
        let privacyConfig = AutofillTestHelper.preparePrivacyConfig(embeddedConfig: embeddedConfig)
        let properties = ContentScopeProperties(gpcEnabled: false, sessionKey: "1234", messageSecret: "1234", featureToggles: ContentScopeFeatureToggles.allTogglesOn)
        let sourceProvider = try! DefaultAutofillSourceProvider.Builder(privacyConfigurationManager: privacyConfig,
                                                                        properties: properties)
            .withJSLoading()
            .build()
        return AutofillUserScript(scriptSourceProvider: sourceProvider, encrypter: MockEncrypter(), hostProvider: SecurityOriginHostProvider())
    }()
    let userContentController = WKUserContentController()

    var mockBody: [String: Any] = [:]

    @available(iOS 14, macOS 11, *)
    func testWhenReceivesStoreTokenMessageThenCallsDelegateMethodWithCorrectTokenAndUsername() {
        let mock = MockAutofillEmailDelegate()
        userScript.emailDelegate = mock

        let token = "testToken"
        let username = "testUsername"
        let cohort = "testCohort"

        let expect = expectation(description: "testWhenReceivesStoreTokenMessageThenCallsDelegateMethod")
        mock.requestStoreTokenCallback = { callbackToken, callbackUsername, callbackCohort in
            XCTAssertEqual(token, callbackToken)
            XCTAssertEqual(username, callbackUsername)
            XCTAssertEqual(cohort, callbackCohort)
            expect.fulfill()
        }

        let body: [String: Any] = [
            "token": "testToken",
            "username": "testUsername",
            "cohort": "testCohort"
        ]
        let message = MockWKScriptMessage(name: "emailHandlerStoreToken", body: body)

        let replyExpect = expectation(description: "reply handler called")
        userScript.userContentController(userContentController, didReceive: message) { reply, error in
            XCTAssertNil(reply)
            XCTAssertNil(error)
            replyExpect.fulfill()
        }

        waitForExpectations(timeout: 1.0, handler: nil)
    }

    @available(iOS 14, macOS 11, *)
    func testWhenReceivesCheckSignedInMessageThenCallsDelegateMethod() {
        let mock = MockAutofillEmailDelegate()
        userScript.emailDelegate = mock

        let expect = expectation(description: "testWhenReceivesCheckSignedInMessageThenCallsDelegateMethod")
        mock.signedInCallback = {
            expect.fulfill()
        }

        let mockWebView = MockWebView()
        let message = MockWKScriptMessage(name: "emailHandlerCheckAppSignedInStatus", body: mockBody, webView: mockWebView)

        let replyExpect = expectation(description: "reply handler called")
        userScript.userContentController(userContentController, didReceive: message) { reply, error in
            XCTAssertNotNil(reply)
            XCTAssertNil(error)
            if let replyString = reply as? String {
                XCTAssertTrue(replyString.contains("\"isAppSignedIn\": false"))
            } else {
                XCTFail("Expected string reply")
            }
            replyExpect.fulfill()
        }

        waitForExpectations(timeout: 2.0, handler: nil)
    }

    @available(iOS 14, macOS 11, *)
    func testWhenReceivesGetAliasMessageThenCallsDelegateMethod() {
        let mock = MockAutofillEmailDelegate()
        userScript.emailDelegate = mock

        let expect = expectation(description: "testWhenReceivesGetAliasMessageThenCallsDelegateMethod")
        mock.requestAliasCallback = {
            expect.fulfill()
        }

        var body: [String: Any] = [:]
        body["requiresUserPermission"] = false
        body["shouldConsumeAliasIfProvided"] = false
        body["isIncontextSignupAvailable"] = false
        let mockWebView = MockWebView()
        let message = MockWKScriptMessage(name: "emailHandlerGetAlias", body: body, webView: mockWebView)

        let replyExpect = expectation(description: "reply handler called")
        userScript.userContentController(userContentController, didReceive: message) { reply, error in
            XCTAssertNotNil(reply)
            XCTAssertNil(error)
            if let replyString = reply as? String {
                XCTAssertTrue(replyString.contains("\"alias\": \"alias\""))
            } else {
                XCTFail("Expected string reply")
            }
            replyExpect.fulfill()
        }

        waitForExpectations(timeout: 2.0, handler: nil)
    }

    @available(iOS 14, macOS 11, *)
    func testWhenReceivesRefreshAliasMessageThenCallsDelegateMethod() {
        let mock = MockAutofillEmailDelegate()
        userScript.emailDelegate = mock

        let expect = expectation(description: "testWhenReceivesRefreshAliasMessageThenCallsDelegateMethod")
        mock.refreshAliasCallback = {
            expect.fulfill()
        }

        let message = MockWKScriptMessage(name: "emailHandlerRefreshAlias", body: mockBody)

        userScript.userContentController(userContentController, didReceive: message) { reply, error in
            XCTAssertNil(error)
        }

        waitForExpectations(timeout: 1.0, handler: nil)
    }

    @available(iOS 14, macOS 11, *)
    func testWhenReceivesEmailGetAddressesMessageThenCallsDelegateMethod() {
        let mock = MockAutofillEmailDelegate()
        userScript.emailDelegate = mock

        let expect = expectation(description: "testWhenReceivesRequestUsernameAndAliasMessageThenCallsDelegateMethod")
        mock.requestUsernameAndAliasCallback = {
            expect.fulfill()
        }

        let mockWebView = MockWebView()
        let message = MockWKScriptMessage(name: "emailHandlerGetAddresses", body: mockBody, webView: mockWebView)

        let replyExpect = expectation(description: "reply handler called")

        userScript.userContentController(userContentController, didReceive: message) { reply, error in
            XCTAssertNil(error)
            replyExpect.fulfill()
        }
        waitForExpectations(timeout: 1.0, handler: nil)
    }

    @available(iOS 14, macOS 11, *)
    func testWhenReceivesEmailGetUserDataMessageThenCallsDelegateMethod() {
        let mock = MockAutofillEmailDelegate()
        userScript.emailDelegate = mock

        let expect = expectation(description: "testWhenReceivesRequestUserDataMessageThenCallsDelegateMethod")
        mock.requestUserDataCallback = {
            expect.fulfill()
        }

        let mockWebView = MockWebView()
        let message = MockWKScriptMessage(name: "emailHandlerGetUserData", body: mockBody, webView: mockWebView)

        let replyExpect = expectation(description: "reply handler called")
        userScript.userContentController(userContentController, didReceive: message) { reply, error in
            XCTAssertNil(error)
            replyExpect.fulfill()
        }

        waitForExpectations(timeout: 1.0, handler: nil)
    }

    @available(iOS 14, macOS 11, *)
    func testWhenUnknownMessageReceivedThenNoProblem() {
        let message = MockWKScriptMessage(name: "unknownmessage", body: "")

        let replyExpect = expectation(description: "Unsupported message")
        let result = userScript.userContentController(userContentController, didReceive: message) { reply, error in
            // For unknown messages, we expect an error indicating the message is unsupported
            XCTAssertNotNil(error)
            replyExpect.fulfill()
        }

        waitForExpectations(timeout: 1.0, handler: nil)
    }

}

class MockWKScriptMessage: WKScriptMessage {

    let mockedName: String
    let mockedBody: Any
    let mockedWebView: WKWebView?

    override var name: String {
        return mockedName
    }

    override var body: Any {
        return mockedBody
    }

    override var webView: WKWebView? {
        return mockedWebView
    }

    init(name: String, body: Any, webView: WKWebView? = nil) {
        self.mockedName = name
        self.mockedBody = body
        self.mockedWebView = webView
        super.init()
    }
}

class MockUserScriptMessage: UserScriptMessage {

    let mockedName: String
    let mockedBody: Any
    let mockedHost: String
    let mockedWebView: WKWebView?
    let mockedMainFrame: Bool

    var isMainFrame: Bool {
        return mockedMainFrame
    }

    var messageName: String {
        return mockedName
    }

    var messageBody: Any {
        return mockedBody
    }

    var messageWebView: WKWebView? {
        return mockedWebView
    }

    var messageHost: String {
        return mockedHost
    }

    init(name: String, body: Any, host: String, webView: WKWebView? = nil) {
        self.mockedName = name
        self.mockedBody = body
        self.mockedWebView = webView
        self.mockedHost = host
        self.mockedMainFrame = true
    }
}

class MockAutofillEmailDelegate: AutofillEmailDelegate {
    func autofillUserScript(_: BrowserServicesKit.AutofillUserScript, didRequestSetInContextPromptValue value: Double) {

    }

    func autofillUserScriptDidRequestInContextPromptValue(_: BrowserServicesKit.AutofillUserScript) -> Double? {
        return nil
    }

    func autofillUserScriptDidRequestInContextSignup(_: BrowserServicesKit.AutofillUserScript, completionHandler: @escaping BrowserServicesKit.SignUpCompletion) {

    }

    func autofillUserScriptDidCompleteInContextSignup(_: BrowserServicesKit.AutofillUserScript) {

    }

    var signedInCallback: (() -> Void)?
    var signedOutCallback: (() -> Void)?
    var requestAliasCallback: (() -> Void)?
    var requestStoreTokenCallback: ((String, String, String?) -> Void)?
    var refreshAliasCallback: (() -> Void)?
    var requestUsernameAndAliasCallback: (() -> Void)?
    var requestUserDataCallback: (() -> Void)?

    func autofillUserScriptDidRequestSignedInStatus(_: AutofillUserScript) -> Bool {
        signedInCallback?()
        return false
    }

    func autofillUserScript(_: AutofillUserScript,
                            didRequestAliasAndRequiresUserPermission requiresUserPermission: Bool,
                            shouldConsumeAliasIfProvided: Bool,
                            completionHandler: @escaping AliasAutosaveCompletion) {
        requestAliasCallback?()
        completionHandler("alias", true, nil)
    }

    func autofillUserScriptDidRequestRefreshAlias(_: AutofillUserScript) {
        refreshAliasCallback?()
    }

    func autofillUserScript(_: AutofillUserScript, didRequestStoreToken token: String, username: String, cohort: String?) {
        requestStoreTokenCallback!(token, username, cohort)
    }

    func autofillUserScriptDidRequestUsernameAndAlias(_: AutofillUserScript, completionHandler: @escaping UsernameAndAliasCompletion) {
        requestUsernameAndAliasCallback?()
        completionHandler("username", "alias", nil)
    }

    func autofillUserScriptDidRequestUserData(_: AutofillUserScript, completionHandler: @escaping UserDataCompletion) {
        requestUserDataCallback?()
        completionHandler("username", "alias", "token", nil)
    }

    func autofillUserScriptDidRequestSignOut(_: AutofillUserScript) {
        signedOutCallback?()
    }
}

class MockWebView: WKWebView {

    var javaScriptString: String?
    var evaluateJavaScriptResult: Any?

    convenience init() {
        self.init(frame: .zero, configuration: WKWebViewConfiguration())
    }

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        _=Self.swizzleEvaluateJavaScriptOnce
        super.init(frame: frame, configuration: configuration)
    }

    required init?(coder: NSCoder) {
        _=Self.swizzleEvaluateJavaScriptOnce
        super.init(coder: coder)
    }

}
private extension WKWebView {

    static let swizzleEvaluateJavaScriptOnce: () = {
        guard let originalMethod = class_getInstanceMethod(WKWebView.self, #selector(evaluateJavaScript(_:completionHandler:))),
              let swizzledMethod = class_getInstanceMethod(WKWebView.self, #selector(swizzled_evaluateJavaScript(_:completionHandler:))) else {
            assertionFailure("Methods not available")
            return
        }

        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()

    // place popover inside bounds of its owner Main Window
    @objc(swizzled_evaluateJavaScript:completionHandler:)
    private dynamic func swizzled_evaluateJavaScript(_ javaScriptString: String, completionHandler: ((Any?, (any Error)?) -> Void)? = nil) {
        if let mockWebView = self as? MockWebView {
            mockWebView.javaScriptString = javaScriptString
            completionHandler?(mockWebView.evaluateJavaScriptResult, nil)
            return
        }
        self.swizzled_evaluateJavaScript(javaScriptString, completionHandler: completionHandler) // call the original
    }

}

struct MockEncrypter: UserScriptEncrypter {

    var authenticationData: Data = Data()

    func encryptReply(_ reply: String, key: [UInt8], iv: [UInt8]) throws -> (ciphertext: Data, tag: Data) {
        return ("reply".data(using: .utf8)!, Data())
    }

}
