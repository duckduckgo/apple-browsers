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
import BrowserServicesKitTestsUtils
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
        let sut = DataBrokerProtectionFeature(delegate: mockCSSDelegate, executionConfig: BrokerJobExecutionConfig(), shouldContinueActionHandler: { true })

        await sut.parseActionCompleted(params: params)

        XCTAssertEqual(mockCSSDelegate.lastError as? DataBrokerProtectionError, DataBrokerProtectionError.parsingErrorObjectFailed)
    }

    func testWhenErrorIsParsed_thenDelegateSendsBackActionFailedError() async {
        let params = ["result": ["error": ["actionID": "someActionID", "message": "some message"]]]
        let sut = DataBrokerProtectionFeature(delegate: mockCSSDelegate, executionConfig: BrokerJobExecutionConfig(), shouldContinueActionHandler: { true })

        await sut.parseActionCompleted(params: params)

        XCTAssertEqual(mockCSSDelegate.lastError as? DataBrokerProtectionError, DataBrokerProtectionError.actionFailed(actionID: "someActionID", message: "some message"))
    }

    func testWhenNavigateActionIsParsed_thenDelegateSendsBackURL() async {
        let params = ["result": ["success": ["actionID": "1", "actionType": "navigate", "response": ["url": "www.duckduckgo.com"]] as [String: Any]]]
        let sut = DataBrokerProtectionFeature(delegate: mockCSSDelegate, executionConfig: BrokerJobExecutionConfig(), shouldContinueActionHandler: { true })

        await sut.parseActionCompleted(params: params)

        XCTAssertNil(mockCSSDelegate.lastError)
        XCTAssertEqual(mockCSSDelegate.url?.absoluteString, "www.duckduckgo.com")
    }

    func testWhenExtractActionIsParsed_thenDelegateSendsExtractedProfiles() async {
        let profiles = NSArray(objects: ["name": "John"], ["name": "Ben"])
        let params = ["result": ["success": ["actionID": "1", "actionType": "extract", "response": profiles] as [String: Any]]]
        let sut = DataBrokerProtectionFeature(delegate: mockCSSDelegate, executionConfig: BrokerJobExecutionConfig(), shouldContinueActionHandler: { true })

        await sut.parseActionCompleted(params: params)

        XCTAssertNil(mockCSSDelegate.lastError)
        XCTAssertNotNil(mockCSSDelegate.profiles)
        XCTAssertEqual(mockCSSDelegate.profiles?.count, 2)
    }

    func testWhenUnknownActionIsParsed_thenDelegateSendsParsingError() async {
        let params = ["result": ["success": ["actionID": "1", "actionType": "unknown"] as [String: Any]]]
        let sut = DataBrokerProtectionFeature(delegate: mockCSSDelegate, executionConfig: BrokerJobExecutionConfig(), shouldContinueActionHandler: { true })

        await sut.parseActionCompleted(params: params)

        XCTAssertEqual(mockCSSDelegate.lastError as? DataBrokerProtectionError, DataBrokerProtectionError.parsingErrorObjectFailed)
    }

    func testWhenClickActionIsParsed_thenDelegateSendsSuccessWithCorrectActionId() async {
        let params = ["result": ["success": ["actionID": "click", "actionType": "click"] as [String: Any]]]
        let sut = DataBrokerProtectionFeature(delegate: mockCSSDelegate, executionConfig: BrokerJobExecutionConfig(), shouldContinueActionHandler: { true })

        await sut.parseActionCompleted(params: params)

        XCTAssertEqual(mockCSSDelegate.successActionId, "click")
    }

    func testWhenExpectationActionIsParsed_thenDelegateSendsSuccessWithCorrectActionId() async {
        let params = ["result": ["success": ["actionID": "expectation", "actionType": "expectation"] as [String: Any]]]
        let sut = DataBrokerProtectionFeature(delegate: mockCSSDelegate, executionConfig: BrokerJobExecutionConfig(), shouldContinueActionHandler: { true })

        await sut.parseActionCompleted(params: params)

        XCTAssertEqual(mockCSSDelegate.successActionId, "expectation")
    }

    func testWhenGetCaptchaInfoIsParsed_thenTheCorrectCaptchaInfoIsParsed() async {
        let params = ["result": ["success": ["actionID": "getCaptchaInfo", "actionType": "getCaptchaInfo", "response": ["siteKey": "1234", "url": "www.test.com", "type": "g-captcha"]] as [String: Any]]]
        let sut = DataBrokerProtectionFeature(delegate: mockCSSDelegate, executionConfig: BrokerJobExecutionConfig(), shouldContinueActionHandler: { true })

        await sut.parseActionCompleted(params: params)

        XCTAssertEqual(mockCSSDelegate.captchaInfo?.siteKey, "1234")
        XCTAssertEqual(mockCSSDelegate.captchaInfo?.url, "www.test.com")
        XCTAssertEqual(mockCSSDelegate.captchaInfo?.type, "g-captcha")
    }

    @MainActor
    private func verifyTimeoutBehavior(
        action: Action,
        actionID: String,
        stepType: StepType
    ) async {
        let executionConfig = BrokerJobExecutionConfig(cssActionTimeout: 0.01)
        let sut = DataBrokerProtectionFeature(delegate: mockCSSDelegate, executionConfig: executionConfig, shouldContinueActionHandler: { true })
        sut.with(broker: mockBroker)
        let params = Params(state: ActionRequest(action: action, data: mockCCFRequestData))

        let timeoutExpectation = XCTestExpectation(description: "Timeout should occur")
        mockCSSDelegate.onErrorCallback = { error in
            if let error = error as? DataBrokerProtectionError,
               case .actionFailed(let errorActionID, let message) = error,
               errorActionID == actionID && message == "Action timed out" {
                timeoutExpectation.fulfill()
            }
        }

        sut.pushAction(method: CCFSubscribeActionName.onActionReceived, webView: mockWebView, params: params)

        await fulfillment(of: [timeoutExpectation], timeout: 3.0)

        XCTAssertEqual(mockCSSDelegate.lastError as? DataBrokerProtectionError,
                       DataBrokerProtectionError.actionFailed(actionID: actionID, message: "Action timed out"))
    }

    @MainActor
    func testActionTimeoutBehavior() async {
        let testCases: [(Action, String, StepType)] = [
            (ExpectationAction(id: "expectation-1", actionType: .expectation), "expectation-1", .scan),
            (NavigateAction(id: "navigate-1", actionType: .navigate, url: ""), "navigate-1", .scan),
            (ClickAction(id: "click-1", actionType: .click), "click-1", .optOut),
            (FillFormAction(id: "form-1", actionType: .fillForm, elements: []), "form-1", .optOut),
            (ExtractAction(id: "extract-1", actionType: .extract), "extract-1", .scan),
            (GetCaptchaInfoAction(id: "captcha-1", actionType: .getCaptchaInfo), "captcha-1", .optOut),
            (SolveCaptchaAction(id: "solve-1", actionType: .solveCaptcha), "solve-1", .optOut)
        ]
        for (action, actionID, stepType) in testCases {
            mockCSSDelegate.reset()
            await verifyTimeoutBehavior(action: action, actionID: actionID, stepType: stepType)
        }
    }

    @MainActor
    func testWhenActionCompletesBeforeTimeout_thenNoTimeoutErrorIsSent() async {
        let sut = DataBrokerProtectionFeature(delegate: mockCSSDelegate, executionConfig: BrokerJobExecutionConfig(), shouldContinueActionHandler: { true })
        sut.with(broker: mockBroker)
        let action = ExpectationAction(id: "expectation-1", actionType: .expectation)
        let params = Params(state: ActionRequest(action: action, data: mockCCFRequestData))

        sut.pushAction(method: CCFSubscribeActionName.onActionReceived, webView: mockWebView, params: params)

        let completionParams = ["result": ["success": ["actionID": "expectation-1", "actionType": "expectation"] as [String: Any]]]
        _ = try? await sut.onActionCompleted(params: completionParams, original: WKScriptMessage.mock())

        XCTAssertNil(mockCSSDelegate.lastError)
        XCTAssertEqual(mockCSSDelegate.successActionId, "expectation-1")
    }

    @MainActor
    func testWhenActionFailsBeforeTimeout_thenNoTimeoutErrorIsSent() async {
        let sut = DataBrokerProtectionFeature(delegate: mockCSSDelegate, executionConfig: BrokerJobExecutionConfig(), shouldContinueActionHandler: { true })
        sut.with(broker: mockBroker)
        let action = ExpectationAction(id: "expectation-1", actionType: .expectation)
        let params = Params(state: ActionRequest(action: action, data: mockCCFRequestData))

        sut.pushAction(method: CCFSubscribeActionName.onActionReceived, webView: mockWebView, params: params)

        let errorParams = ["error": "No action found."]
        _ = try? await sut.onActionError(params: errorParams, original: WKScriptMessage.mock())

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
    var conditionSuccessActions: [Action]?
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

    func conditionSuccess(actions: [Action]) async {
        self.conditionSuccessActions = actions
    }

    func reset() {
        lastError = nil
        profiles = nil
        url = nil
        successActionId = nil
        captchaInfo = nil
        solveCaptchaResponse = nil
        onErrorCallback = nil
        conditionSuccessActions = nil
    }
}
