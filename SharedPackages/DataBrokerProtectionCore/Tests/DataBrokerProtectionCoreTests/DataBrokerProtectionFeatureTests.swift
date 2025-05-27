//
//  DataBrokerProtectionFeatureTests.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils
import UserScript
import WebKit

final class DataBrokerProtectionFeatureTests: XCTestCase {

    let mockCSSDelegate = MockCSSCommunicationDelegate()

    let mockWebView = WKWebView()
    let mockBroker = UserScriptMessageBroker(context: "mock context")

    let mockProfileQuery = ProfileQuery(firstName: "", lastName: "", city: "", state: "", birthYear: 1970)
    lazy var mockCCFRequestData = CCFRequestData.userData(mockProfileQuery, nil)

    override func setUp() {
        mockCSSDelegate.reset()
    }

    func testWhenParseActionCompletedFailsOnParsing_thenDelegateSendsBackTheCorrectError() async {
        let params = ["result": "something"]
        let sut = DataBrokerProtectionFeature(delegate: mockCSSDelegate)

        await sut.parseActionCompleted(params: params)

        XCTAssertEqual(mockCSSDelegate.lastError as? DataBrokerProtectionError, DataBrokerProtectionError.parsingErrorObjectFailed)
    }

    func testWhenErrorIsParsed_thenDelegateSendsBackActionFailedError() async {
        let params = ["result": ["error": ["actionID": "someActionID", "message": "some message"]]]
        let sut = DataBrokerProtectionFeature(delegate: mockCSSDelegate)

        await sut.parseActionCompleted(params: params)

        XCTAssertEqual(mockCSSDelegate.lastError as? DataBrokerProtectionError, DataBrokerProtectionError.actionFailed(actionID: "someActionID", message: "some message"))
    }

    func testWhenNavigateActionIsParsed_thenDelegateSendsBackURL() async {
        let params = ["result": ["success": ["actionID": "1", "actionType": "navigate", "response": ["url": "www.duckduckgo.com"]] as [String: Any]]]
        let sut = DataBrokerProtectionFeature(delegate: mockCSSDelegate)

        await sut.parseActionCompleted(params: params)

        XCTAssertNil(mockCSSDelegate.lastError)
        XCTAssertEqual(mockCSSDelegate.url?.absoluteString, "www.duckduckgo.com")
    }

    func testWhenExtractActionIsParsed_thenDelegateSendsExtractedProfiles() async {
        let profiles = NSArray(objects: ["name": "John"], ["name": "Ben"])
        let params = ["result": ["success": ["actionID": "1", "actionType": "extract", "response": profiles] as [String: Any]]]
        let sut = DataBrokerProtectionFeature(delegate: mockCSSDelegate)

        await sut.parseActionCompleted(params: params)

        XCTAssertNil(mockCSSDelegate.lastError)
        XCTAssertNotNil(mockCSSDelegate.profiles)
        XCTAssertEqual(mockCSSDelegate.profiles?.count, 2)
    }

    func testWhenUnknownActionIsParsed_thenDelegateSendsParsingError() async {
        let params = ["result": ["success": ["actionID": "1", "actionType": "unknown"] as [String: Any]]]
        let sut = DataBrokerProtectionFeature(delegate: mockCSSDelegate)

        await sut.parseActionCompleted(params: params)

        XCTAssertEqual(mockCSSDelegate.lastError as? DataBrokerProtectionError, DataBrokerProtectionError.parsingErrorObjectFailed)
    }

    func testWhenClickActionIsParsed_thenDelegateSendsSuccessWithCorrectActionId() async {
        let params = ["result": ["success": ["actionID": "click", "actionType": "click"] as [String: Any]]]
        let sut = DataBrokerProtectionFeature(delegate: mockCSSDelegate)

        await sut.parseActionCompleted(params: params)

        XCTAssertEqual(mockCSSDelegate.successActionId, "click")
    }

    func testWhenExpectationActionIsParsed_thenDelegateSendsSuccessWithCorrectActionId() async {
        let params = ["result": ["success": ["actionID": "expectation", "actionType": "expectation"] as [String: Any]]]
        let sut = DataBrokerProtectionFeature(delegate: mockCSSDelegate)

        await sut.parseActionCompleted(params: params)

        XCTAssertEqual(mockCSSDelegate.successActionId, "expectation")
    }

    func testWhenGetCaptchaInfoIsParsed_thenTheCorrectCaptchaInfoIsParsed() async {
        let params = ["result": ["success": ["actionID": "getCaptchaInfo", "actionType": "getCaptchaInfo", "response": ["siteKey": "1234", "url": "www.test.com", "type": "g-captcha"]] as [String: Any]]]
        let sut = DataBrokerProtectionFeature(delegate: mockCSSDelegate)

        await sut.parseActionCompleted(params: params)

        XCTAssertEqual(mockCSSDelegate.captchaInfo?.siteKey, "1234")
        XCTAssertEqual(mockCSSDelegate.captchaInfo?.url, "www.test.com")
        XCTAssertEqual(mockCSSDelegate.captchaInfo?.type, "g-captcha")
    }

    @MainActor
    func testWhenExpectationActionTimesOut_thenDelegateReceivesTimeoutError() async {
        let sut = DataBrokerProtectionFeature(delegate: mockCSSDelegate, actionResponseTimeout: 0.1)
        sut.with(broker: mockBroker)
        let action = ExpectationAction(id: "expectation-1", actionType: .expectation, expectations: [], dataSource: nil, actions: nil)
        let params = Params(state: ActionRequest(action: action, data: mockCCFRequestData))

        let timeoutExpectation = expectation(description: "Timeout error received")

        mockCSSDelegate.onErrorCallback = { error in
            if let error = error as? DataBrokerProtectionError,
               case .actionFailed(let actionID, let message) = error,
               actionID == "expectation-1" && message == "Request timed out" {
                timeoutExpectation.fulfill()
            }
        }

        sut.pushAction(method: .onActionReceived, webView: mockWebView, params: params, canTimeOut: true)

        await fulfillment(of: [timeoutExpectation], timeout: 0.3)

        XCTAssertEqual(mockCSSDelegate.lastError as? DataBrokerProtectionError, DataBrokerProtectionError.actionFailed(actionID: "expectation-1", message: "Request timed out"))
    }

    @MainActor
    func testWhenNonExpectationActionTimeOut_thenDelegateDoesNotReceiveTimeoutError() async {
        let sut = DataBrokerProtectionFeature(delegate: mockCSSDelegate, actionResponseTimeout: 0.1)
        sut.with(broker: mockBroker)
        let action = NavigateAction(id: "navigate-1", actionType: .navigate, url: "", ageRange: nil, dataSource: nil)
        let params = Params(state: ActionRequest(action: action, data: mockCCFRequestData))

        let noErrorExpectation = expectation(description: "No error received")
        noErrorExpectation.isInverted = true

        mockCSSDelegate.onErrorCallback = { _ in
            noErrorExpectation.fulfill()
        }

        sut.pushAction(method: .onActionReceived, webView: mockWebView, params: params, canTimeOut: false)

        // Wait for a reasonable time to ensure no error is received
        await fulfillment(of: [noErrorExpectation], timeout: 0.3)
        XCTAssertNil(mockCSSDelegate.lastError)
    }

    @MainActor
    func testWhenExpectationActionCompletesBeforeTimeout_thenNoTimeoutErrorIsSent() async {
        let sut = DataBrokerProtectionFeature(delegate: mockCSSDelegate, actionResponseTimeout: 0.1)
        sut.with(broker: mockBroker)
        let action = ExpectationAction(id: "expectation-1", actionType: .expectation, expectations: [], dataSource: nil, actions: nil)
        let params = Params(state: ActionRequest(action: action, data: mockCCFRequestData))

        let noErrorExpectation = expectation(description: "No error received")
        noErrorExpectation.isInverted = true

        mockCSSDelegate.onErrorCallback = { _ in
            noErrorExpectation.fulfill()
        }

        sut.pushAction(method: .onActionReceived, webView: mockWebView, params: params, canTimeOut: true)

        // Complete the action before timeout
        let completionParams = ["result": ["success": ["actionID": "expectation-1", "actionType": "expectation"] as [String: Any]]]
        _ = try? await sut.onActionCompleted(params: completionParams, original: MockWKScriptMessage())

        await fulfillment(of: [noErrorExpectation], timeout: 0.3)

        XCTAssertNil(mockCSSDelegate.lastError)
        XCTAssertEqual(mockCSSDelegate.successActionId, "expectation-1")
    }

    @MainActor
    func testWhenExpectationActionFailsBeforeTimeout_thenNoTimeoutErrorIsSent() async {
        let sut = DataBrokerProtectionFeature(delegate: mockCSSDelegate, actionResponseTimeout: 0.1)
        sut.with(broker: mockBroker)
        let action = ExpectationAction(id: "expectation-1", actionType: .expectation, expectations: [], dataSource: nil, actions: nil)
        let params = Params(state: ActionRequest(action: action, data: mockCCFRequestData))

        let noTimeoutErrorExpectation = expectation(description: "No timeout error received")
        noTimeoutErrorExpectation.isInverted = true

        mockCSSDelegate.onErrorCallback = { error in
            if let error = error as? DataBrokerProtectionError,
               case .actionFailed(let actionID, let message) = error,
               actionID == "expectation-1" && message == "Request timed out" {
                noTimeoutErrorExpectation.fulfill()
            }
        }

        sut.pushAction(method: .onActionReceived, webView: mockWebView, params: params, canTimeOut: true)

        // Fail the action before timeout
        let errorParams = ["error": "No action found."]
        _ = try? await sut.onActionError(params: errorParams, original: MockWKScriptMessage())

        await fulfillment(of: [noTimeoutErrorExpectation], timeout: 0.3)

        XCTAssertEqual(mockCSSDelegate.lastError as? DataBrokerProtectionError, .noActionFound)
    }
}

final class MockCSSCommunicationDelegate: CCFCommunicationDelegate {
    var lastError: Error?
    var profiles: [ExtractedProfile]?
    var url: URL?
    var captchaInfo: GetCaptchaInfoResponse?
    var solveCaptchaResponse: SolveCaptchaResponse?
    var successActionId: String?
    var onErrorCallback: ((Error) -> Void)?

    func loadURL(url: URL) {
        self.url = url
    }

    func extractedProfiles(profiles: [ExtractedProfile], meta: [String: Any]?) async {
        self.profiles = profiles
    }

    func success(actionId: String, actionType: ActionType) {
        self.successActionId = actionId
    }

    func captchaInformation(captchaInfo: GetCaptchaInfoResponse) {
        self.captchaInfo = captchaInfo
    }

    func onError(error: Error) {
        self.lastError = error
        onErrorCallback?(error)
    }

    func solveCaptcha(with response: SolveCaptchaResponse) async {
        self.solveCaptchaResponse = response
    }

    func reset() {
        lastError = nil
        profiles = nil
        url = nil
        successActionId = nil
        captchaInfo = nil
        solveCaptchaResponse = nil
        onErrorCallback = nil
    }
}

private class MockWKScriptMessage: WKScriptMessage {

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

    init(name: String = "", body: Any = "", webView: WKWebView? = nil) {
        self.mockedName = name
        self.mockedBody = body
        self.mockedWebView = webView
        super.init()
    }
}
