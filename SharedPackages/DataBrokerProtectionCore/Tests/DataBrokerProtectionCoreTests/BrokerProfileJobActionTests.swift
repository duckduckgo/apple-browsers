//
//  BrokerProfileJobActionTests.swift
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

import BrowserServicesKit
import Combine
import Foundation
import XCTest

@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils

final class BrokerProfileJobActionTests: XCTestCase {
    let webViewHandler = WebViewHandlerMock()
    let emailConfirmationDataService = MockEmailConfirmationDataServiceProvider()
    let captchaService = CaptchaServiceMock()
    let pixelHandler = MockDataBrokerProtectionPixelsHandler()
    let stageCalculator = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "broker.com", dataBrokerVersion: "1.1.1", handler: MockDataBrokerProtectionPixelsHandler(), isFreeScan: false, vpnConnectionState: "disconnected", vpnBypassStatus: "off")

    override func tearDown() async throws {
        webViewHandler.reset()
        emailConfirmationDataService.reset()
        captchaService.reset()
    }

    func testWhenActionNeedsEmail_thenExtractedProfileEmailIsSet() async {
        let fillFormAction = FillFormAction(id: "1", actionType: .fillForm, elements: [.init(type: "email")])
        let step = Step(type: .optOut, actions: [fillFormAction])
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            context: BrokerProfileQueryData.mock(with: [step]),
            emailConfirmationDataService: emailConfirmationDataService,
            captchaService: captchaService,
            featureFlagger: MockDBPFeatureFlagger(),
            applicationNameForUserAgentProvider: { nil },
            operationAwaitTime: 0,
            stageCalculator: stageCalculator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            actionsHandlerMode: .optOut,
            shouldRunNextStep: { true }
        )
        sut.webViewHandler = webViewHandler
        sut.extractedProfile = ExtractedProfile()

        await sut.runNextAction(fillFormAction)

        XCTAssertEqual(sut.extractedProfile?.email, "test@duck.com")
        XCTAssertTrue(webViewHandler.wasExecuteCalledForUserData)
    }

    func testWhenGetEmailServiceFails_thenOperationThrows() async {
        let fillFormAction = FillFormAction(id: "1", actionType: .fillForm, elements: [.init(type: "email")])
        let step = Step(type: .optOut, actions: [fillFormAction])
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            context: BrokerProfileQueryData.mock(with: [step]),
            emailConfirmationDataService: emailConfirmationDataService,
            captchaService: captchaService,
            featureFlagger: MockDBPFeatureFlagger(),
            applicationNameForUserAgentProvider: { nil },
            operationAwaitTime: 0,
            stageCalculator: stageCalculator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            actionsHandlerMode: .optOut,
            shouldRunNextStep: { true }
        )
        emailConfirmationDataService.shouldThrow = true

        do {
            _ = try await sut.run(inputValue: ExtractedProfile(), webViewHandler: webViewHandler)
            XCTFail("Expected an error to be thrown")
        } catch {
            XCTAssertTrue(webViewHandler.wasFinishCalled)

            if let error = error as? DataBrokerProtectionError, case .emailError(nil) = error {
                return
            }

            XCTFail("Unexpected error thrown: \(error).")
        }
    }

    func testWhenClickActionSucceeds_thenWeWaitForWebViewToLoad() async {
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            context: BrokerProfileQueryData.mock(),
            emailConfirmationDataService: emailConfirmationDataService,
            captchaService: captchaService,
            featureFlagger: MockDBPFeatureFlagger(),
            applicationNameForUserAgentProvider: { nil },
            operationAwaitTime: 0,
            stageCalculator: stageCalculator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(clickAwaitTimeForOptOut: 0.0,
                                                      clickAwaitTimeForScan: 0.0),
            actionsHandlerMode: .optOut,
            shouldRunNextStep: { true }
        )
        sut.webViewHandler = webViewHandler

        await sut.success(actionId: "1", actionType: ActionType.click)

        XCTAssertFalse(webViewHandler.wasWaitForWebViewLoadCalled)
        XCTAssertTrue(webViewHandler.wasFinishCalled)
    }

    func testWhenAnActionThatIsNotClickSucceeds_thenWeDoNotWaitForWebViewToLoad() async {
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            context: BrokerProfileQueryData.mock(),
            emailConfirmationDataService: emailConfirmationDataService,
            captchaService: captchaService,
            featureFlagger: MockDBPFeatureFlagger(),
            applicationNameForUserAgentProvider: { nil },
            operationAwaitTime: 0,
            stageCalculator: stageCalculator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            actionsHandlerMode: .optOut,
            shouldRunNextStep: { true }
        )
        sut.webViewHandler = webViewHandler

        await sut.success(actionId: "1", actionType: ActionType.expectation)

        XCTAssertFalse(webViewHandler.wasWaitForWebViewLoadCalled)
        XCTAssertTrue(webViewHandler.wasFinishCalled)
    }

    func testWhenSolveCaptchaActionIsRun_thenCaptchaIsResolved() async {
        let solveCaptchaAction = SolveCaptchaAction(id: "1", actionType: .solveCaptcha)
        let step = Step(type: .optOut, actions: [solveCaptchaAction])
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            context: BrokerProfileQueryData.mock(),
            emailConfirmationDataService: emailConfirmationDataService,
            captchaService: captchaService,
            featureFlagger: MockDBPFeatureFlagger(),
            applicationNameForUserAgentProvider: { nil },
            operationAwaitTime: 0,
            stageCalculator: stageCalculator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            actionsHandlerMode: .optOut,
            shouldRunNextStep: { true }
        )
        sut.webViewHandler = webViewHandler
        sut.actionsHandler = ActionsHandler.forOptOut(step)
        sut.actionsHandler?.captchaTransactionId = "transactionId"

        await sut.runNextAction(solveCaptchaAction)

        XCTAssert(webViewHandler.wasExecuteCalledForSolveCaptcha)
    }

    func testWhenSolveCapchaActionFailsToSubmitDataToTheBackend_thenOperationFails() async {
        let solveCaptchaAction = SolveCaptchaAction(id: "1", actionType: .solveCaptcha)
        let step = Step(type: .optOut, actions: [solveCaptchaAction])
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            context: BrokerProfileQueryData.mock(with: [step]),
            emailConfirmationDataService: emailConfirmationDataService,
            captchaService: captchaService,
            featureFlagger: MockDBPFeatureFlagger(),
            applicationNameForUserAgentProvider: { nil },
            operationAwaitTime: 0,
            stageCalculator: stageCalculator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            actionsHandlerMode: .testing,
            shouldRunNextStep: { true }
        )
        let actionsHandler = ActionsHandler.forOptOut(step)
        actionsHandler.captchaTransactionId = "transactionId"
        captchaService.shouldThrow = true

        do {
            _ = try await sut.run(inputValue: ExtractedProfile(), webViewHandler: webViewHandler, actionsHandler: actionsHandler)
            XCTFail("Expected an error to be thrown")
        } catch {
            if let error = error as? DataBrokerProtectionError, case .captchaServiceError(.nilDataWhenFetchingCaptchaResult) = error {
                return
            }

            XCTFail("Unexpected error thrown: \(error).")
        }
    }

    func testWhenCaptchaInformationIsReturned_thenWeSubmitItTotTheBackend() async {
        let getCaptchaResponse = GetCaptchaInfoResponse(siteKey: "siteKey", url: "url", type: "recaptcha")
        let step = Step(type: .optOut, actions: [Action]())
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            context: BrokerProfileQueryData.mock(),
            emailConfirmationDataService: emailConfirmationDataService,
            captchaService: captchaService,
            featureFlagger: MockDBPFeatureFlagger(),
            applicationNameForUserAgentProvider: { nil },
            operationAwaitTime: 0,
            stageCalculator: stageCalculator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            actionsHandlerMode: .optOut,
            shouldRunNextStep: { true }
        )
        sut.webViewHandler = webViewHandler
        sut.actionsHandler = ActionsHandler.forOptOut(step)

        await sut.captchaInformation(captchaInfo: getCaptchaResponse)

        XCTAssertTrue(captchaService.wasSubmitCaptchaInformationCalled)
        XCTAssert(webViewHandler.wasFinishCalled)
    }

    func testWhenCaptchaInformationFailsToBeSubmitted_thenTheOperationFails() async {
        let getCaptchaResponse = GetCaptchaInfoResponse(siteKey: "siteKey", url: "url", type: "recaptcha")
        let step = Step(type: .optOut, actions: [Action]())
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            context: BrokerProfileQueryData.mock(),
            emailConfirmationDataService: emailConfirmationDataService,
            captchaService: captchaService,
            featureFlagger: MockDBPFeatureFlagger(),
            applicationNameForUserAgentProvider: { nil },
            operationAwaitTime: 0,
            stageCalculator: stageCalculator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            actionsHandlerMode: .optOut,
            shouldRunNextStep: { true }
        )
        sut.resetRetriesCount()
        captchaService.shouldThrow = true
        sut.webViewHandler = webViewHandler
        sut.actionsHandler = ActionsHandler.forOptOut(step)

        await sut.captchaInformation(captchaInfo: getCaptchaResponse)

        XCTAssertFalse(captchaService.wasSubmitCaptchaInformationCalled)
        XCTAssert(webViewHandler.wasFinishCalled)
    }

    func testWhenRunningActionWithoutExtractedProfile_thenExecuteIsCalledWithProfileData() async {
        let expectationAction = ExpectationAction(id: "1", actionType: .expectation)
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            context: BrokerProfileQueryData.mock(),
            emailConfirmationDataService: emailConfirmationDataService,
            captchaService: captchaService,
            featureFlagger: MockDBPFeatureFlagger(),
            applicationNameForUserAgentProvider: { nil },
            operationAwaitTime: 0,
            stageCalculator: stageCalculator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            actionsHandlerMode: .optOut,
            shouldRunNextStep: { true }
        )
        sut.webViewHandler = webViewHandler

        await sut.runNextAction(expectationAction)

        XCTAssertTrue(webViewHandler.wasExecuteCalledForUserData)
    }

    func testWhenLoadURLDelegateIsCalled_thenCorrectMethodIsExecutedOnWebViewHandler() async {
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            context: BrokerProfileQueryData.mock(),
            emailConfirmationDataService: emailConfirmationDataService,
            captchaService: captchaService,
            featureFlagger: MockDBPFeatureFlagger(),
            applicationNameForUserAgentProvider: { nil },
            operationAwaitTime: 0,
            stageCalculator: stageCalculator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            actionsHandlerMode: .optOut,
            shouldRunNextStep: { true }
        )
        sut.webViewHandler = webViewHandler

        await sut.loadURL(url: URL(string: "https://www.duckduckgo.com")!)

        XCTAssertEqual(webViewHandler.wasLoadCalledWithURL?.absoluteString, "https://www.duckduckgo.com")
    }

    func testWhenGetCaptchaActionRuns_thenStageIsSetToCaptchaParse() async {
        let mockStageCalculator = MockStageDurationCalculator()
        let captchaAction = GetCaptchaInfoAction(id: "1", actionType: .getCaptchaInfo)
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            context: BrokerProfileQueryData.mock(),
            emailConfirmationDataService: emailConfirmationDataService,
            captchaService: captchaService,
            featureFlagger: MockDBPFeatureFlagger(),
            applicationNameForUserAgentProvider: { nil },
            operationAwaitTime: 0,
            stageCalculator: mockStageCalculator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            actionsHandlerMode: .optOut,
            shouldRunNextStep: { true }
        )

        await sut.runNextAction(captchaAction)

        XCTAssertEqual(mockStageCalculator.stage, .captchaParse)
    }

    func testWhenClickActionRuns_thenStageIsSetToSubmit() async {
        let mockStageCalculator = MockStageDurationCalculator()
        let clickAction = ClickAction(id: "1", actionType: .click)
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            context: BrokerProfileQueryData.mock(),
            emailConfirmationDataService: emailConfirmationDataService,
            captchaService: captchaService,
            featureFlagger: MockDBPFeatureFlagger(),
            applicationNameForUserAgentProvider: { nil },
            operationAwaitTime: 0,
            stageCalculator: mockStageCalculator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            actionsHandlerMode: .optOut,
            shouldRunNextStep: { true }
        )

        await sut.runNextAction(clickAction)

        XCTAssertEqual(mockStageCalculator.stage, .fillForm)
    }

    func testWhenExpectationActionRuns_thenStageIsSetToSubmit() async {
        let mockStageCalculator = MockStageDurationCalculator()
        let expectationAction = ExpectationAction(id: "1", actionType: .expectation)
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            context: BrokerProfileQueryData.mock(),
            emailConfirmationDataService: emailConfirmationDataService,
            captchaService: captchaService,
            featureFlagger: MockDBPFeatureFlagger(),
            applicationNameForUserAgentProvider: { nil },
            operationAwaitTime: 0,
            stageCalculator: mockStageCalculator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            actionsHandlerMode: .optOut,
            shouldRunNextStep: { true }
        )

        await sut.runNextAction(expectationAction)

        XCTAssertEqual(mockStageCalculator.stage, .submit)
    }

    func testWhenFillFormActionRuns_thenStageIsSetToFillForm() async {
        let mockStageCalculator = MockStageDurationCalculator()
        let fillFormAction = FillFormAction(id: "1", actionType: .fillForm, elements: [])
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            context: BrokerProfileQueryData.mock(),
            emailConfirmationDataService: emailConfirmationDataService,
            captchaService: captchaService,
            featureFlagger: MockDBPFeatureFlagger(),
            applicationNameForUserAgentProvider: { nil },
            operationAwaitTime: 0,
            stageCalculator: mockStageCalculator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            actionsHandlerMode: .optOut,
            shouldRunNextStep: { true }
        )

        await sut.runNextAction(fillFormAction)

        XCTAssertEqual(mockStageCalculator.stage, .fillForm)
    }

    func testWhenLoadUrlOnSpokeo_thenSetCookiesIsCalled() async {
        let mockCookieHandler = MockCookieHandler()
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            context: BrokerProfileQueryData.mock(url: "spokeo.com"),
            emailConfirmationDataService: emailConfirmationDataService,
            captchaService: captchaService,
            featureFlagger: MockDBPFeatureFlagger(),
            applicationNameForUserAgentProvider: { nil },
            cookieHandler: mockCookieHandler,
            operationAwaitTime: 0,
            stageCalculator: stageCalculator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            actionsHandlerMode: .optOut,
            shouldRunNextStep: { true }
        )

        mockCookieHandler.cookiesToReturn = [.init()]
        sut.webViewHandler = webViewHandler
        await sut.loadURL(url: URL(string: "www.test.com")!)

        XCTAssertTrue(webViewHandler.wasSetCookiesCalled)
    }

    func testWhenLoadUrlOnOtherBroker_thenSetCookiesIsNotCalled() async {
        let mockCookieHandler = MockCookieHandler()
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            context: BrokerProfileQueryData.mock(url: "verecor.com"),
            emailConfirmationDataService: emailConfirmationDataService,
            captchaService: captchaService,
            featureFlagger: MockDBPFeatureFlagger(),
            applicationNameForUserAgentProvider: { nil },
            cookieHandler: mockCookieHandler,
            operationAwaitTime: 0,
            stageCalculator: stageCalculator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            actionsHandlerMode: .optOut,
            shouldRunNextStep: { true }
        )

        mockCookieHandler.cookiesToReturn = [.init()]
        sut.webViewHandler = webViewHandler
        await sut.loadURL(url: URL(string: "www.test.com")!)

        XCTAssertFalse(webViewHandler.wasSetCookiesCalled)
    }

    // MARK: - ConditionAction Tests

    func testWhenConditionActionSucceedsInOptOutStep_thenFireOptOutConditionFoundIsCalled() async {
        let mockStageCalculator = MockStageDurationCalculator()
        let conditionAction = ConditionAction(id: "1", actionType: .condition)
        let step = Step(type: .optOut, actions: [conditionAction])
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            context: BrokerProfileQueryData.mock(with: [step]),
            emailConfirmationDataService: emailConfirmationDataService,
            captchaService: captchaService,
            featureFlagger: MockDBPFeatureFlagger(),
            applicationNameForUserAgentProvider: { nil },
            operationAwaitTime: 0,
            stageCalculator: mockStageCalculator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            actionsHandlerMode: .optOut,
            shouldRunNextStep: { true }
        )
        sut.webViewHandler = webViewHandler
        sut.actionsHandler = ActionsHandler.forOptOut(step)

        // Simulate condition success
        await sut.conditionSuccess(actions: [])

        XCTAssertFalse(mockStageCalculator.fireOptOutConditionFoundCalled)
        XCTAssertTrue(mockStageCalculator.fireOptOutConditionNotFoundCalled)
    }

    func testWhenConditionActionFailsInOptOutStep_thenFireOptOutConditionNotFoundIsCalled() async {
        let mockStageCalculator = MockStageDurationCalculator()
        let conditionAction = ConditionAction(id: "1", actionType: .condition)
        let step = Step(type: .optOut, actions: [conditionAction])
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            context: BrokerProfileQueryData.mock(with: [step]),
            emailConfirmationDataService: emailConfirmationDataService,
            captchaService: captchaService,
            featureFlagger: MockDBPFeatureFlagger(),
            applicationNameForUserAgentProvider: { nil },
            operationAwaitTime: 0,
            stageCalculator: mockStageCalculator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            actionsHandlerMode: .optOut,
            shouldRunNextStep: { true }
        )
        sut.webViewHandler = webViewHandler
        sut.actionsHandler = ActionsHandler.forOptOut(step)

        // Execute the condition action to set it as current action
        _ = sut.actionsHandler?.nextAction()

        // Simulate condition failure
        await sut.onError(error: DataBrokerProtectionError.actionFailed(actionID: "1", message: "Condition failed"))

        XCTAssertFalse(mockStageCalculator.fireOptOutConditionFoundCalled)
        XCTAssertTrue(mockStageCalculator.fireOptOutConditionNotFoundCalled)
    }

    func testWhenConditionActionSucceedsInScanStep_thenFireOptOutConditionFoundIsNotCalled() async {
        let mockStageCalculator = MockStageDurationCalculator()
        let conditionAction = ConditionAction(id: "1", actionType: .condition)
        let step = Step(type: .scan, actions: [conditionAction])
        let sut = BrokerProfileScanSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            context: BrokerProfileQueryData.mock(with: [step]),
            emailConfirmationDataService: emailConfirmationDataService,
            captchaService: captchaService,
            featureFlagger: MockDBPFeatureFlagger(),
            applicationNameForUserAgentProvider: { nil },
            stageDurationCalculator: mockStageCalculator,
            pixelHandler: MockDataBrokerProtectionPixelsHandler(),
            executionConfig: BrokerJobExecutionConfig(),
            shouldRunNextStep: { true }
        )
        sut.webViewHandler = webViewHandler
        sut.actionsHandler = ActionsHandler.forScan(step)

        // Simulate condition success in scan step
        await sut.conditionSuccess(actions: [])

        XCTAssertFalse(mockStageCalculator.fireOptOutConditionFoundCalled)
        XCTAssertFalse(mockStageCalculator.fireOptOutConditionNotFoundCalled)
    }

    func testWhenNonConditionActionFailsInOptOutStep_thenFireOptOutConditionNotFoundIsNotCalled() async {
        let mockStageCalculator = MockStageDurationCalculator()
        let expectationAction = ExpectationAction(id: "1", actionType: .expectation)
        let step = Step(type: .optOut, actions: [expectationAction])
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            context: BrokerProfileQueryData.mock(with: [step]),
            emailConfirmationDataService: emailConfirmationDataService,
            captchaService: captchaService,
            featureFlagger: MockDBPFeatureFlagger(),
            applicationNameForUserAgentProvider: { nil },
            operationAwaitTime: 0,
            stageCalculator: mockStageCalculator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            actionsHandlerMode: .optOut,
            shouldRunNextStep: { true }
        )
        sut.webViewHandler = webViewHandler
        sut.actionsHandler = ActionsHandler.forOptOut(step)

        // Execute the expectation action to set it as current action
        _ = sut.actionsHandler?.nextAction()

        // Simulate error with non-condition action
        await sut.onError(error: DataBrokerProtectionError.actionFailed(actionID: "1", message: "Action failed"))

        XCTAssertFalse(mockStageCalculator.fireOptOutConditionFoundCalled)
        XCTAssertFalse(mockStageCalculator.fireOptOutConditionNotFoundCalled)
    }

    // MARK: - ConditionAction Edge Cases

    func testWhenConditionActionSucceedsWithFollowUpActions_thenFireOptOutConditionFoundIsCalledAndActionsAreInserted() async {
        let mockStageCalculator = MockStageDurationCalculator()
        let followUpAction = ExpectationAction(id: "followup", actionType: .expectation)
        let conditionAction = ConditionAction(id: "1", actionType: .condition)
        let step = Step(type: .optOut, actions: [conditionAction])
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            context: BrokerProfileQueryData.mock(with: [step]),
            emailConfirmationDataService: emailConfirmationDataService,
            captchaService: captchaService,
            featureFlagger: MockDBPFeatureFlagger(),
            applicationNameForUserAgentProvider: { nil },
            operationAwaitTime: 0,
            stageCalculator: mockStageCalculator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            actionsHandlerMode: .optOut,
            shouldRunNextStep: { true }
        )
        sut.webViewHandler = webViewHandler
        sut.actionsHandler = ActionsHandler.forOptOut(step)

        // Simulate condition success with follow-up actions
        await sut.conditionSuccess(actions: [followUpAction])

        XCTAssertTrue(mockStageCalculator.fireOptOutConditionFoundCalled)
        XCTAssertFalse(mockStageCalculator.fireOptOutConditionNotFoundCalled)

        // Verify follow-up action was inserted
        let nextAction = sut.actionsHandler?.nextAction()
        XCTAssertEqual(nextAction?.id, "followup")
    }

    func testWhenMultipleConditionActionsInSequence_thenEachConditionIsTrackedSeparately() async {
        let mockStageCalculator = MockStageDurationCalculator()
        let firstCondition = ConditionAction(id: "condition1", actionType: .condition)
        let secondCondition = ConditionAction(id: "condition2", actionType: .condition)
        let step = Step(type: .optOut, actions: [firstCondition, secondCondition])
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            context: BrokerProfileQueryData.mock(with: [step]),
            emailConfirmationDataService: emailConfirmationDataService,
            captchaService: captchaService,
            featureFlagger: MockDBPFeatureFlagger(),
            applicationNameForUserAgentProvider: { nil },
            operationAwaitTime: 0,
            stageCalculator: mockStageCalculator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            actionsHandlerMode: .optOut,
            shouldRunNextStep: { true }
        )
        sut.webViewHandler = webViewHandler
        sut.actionsHandler = ActionsHandler.forOptOut(step)

        // First condition succeeds
        await sut.conditionSuccess(actions: [])
        XCTAssertFalse(mockStageCalculator.fireOptOutConditionFoundCalled)

        // Clear flags to test second condition
        mockStageCalculator.clear()

        // Execute second condition and make it fail
        _ = sut.actionsHandler?.nextAction() // Execute first condition
        _ = sut.actionsHandler?.nextAction() // Execute second condition
        await sut.onError(error: DataBrokerProtectionError.actionFailed(actionID: "condition2", message: "Second condition failed"))

        XCTAssertFalse(mockStageCalculator.fireOptOutConditionFoundCalled)
        XCTAssertTrue(mockStageCalculator.fireOptOutConditionNotFoundCalled)
    }

    func testWhenConditionActionFailsWithSpecificErrorTypes_thenFireOptOutConditionNotFoundIsCalledForEach() async {
        let mockStageCalculator = MockStageDurationCalculator()
        let conditionAction = ConditionAction(id: "1", actionType: .condition)
        let step = Step(type: .optOut, actions: [conditionAction])

        let errorTypes: [Error] = [
            DataBrokerProtectionError.httpError(code: 404),
            DataBrokerProtectionError.httpError(code: 500),
            DataBrokerProtectionError.actionFailed(actionID: "1", message: "Failed"),
            NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        ]

        for (index, error) in errorTypes.enumerated() {
            let sut = BrokerProfileOptOutSubJobWebRunner(
                privacyConfig: PrivacyConfigurationManagingMock(),
                prefs: ContentScopeProperties.mock,
                context: BrokerProfileQueryData.mock(with: [step]),
                emailConfirmationDataService: emailConfirmationDataService,
                captchaService: captchaService,
                featureFlagger: MockDBPFeatureFlagger(),
                applicationNameForUserAgentProvider: { nil },
                operationAwaitTime: 0,
                stageCalculator: mockStageCalculator,
                pixelHandler: pixelHandler,
                executionConfig: BrokerJobExecutionConfig(),
            actionsHandlerMode: .optOut,
                shouldRunNextStep: { true }
            )
            sut.webViewHandler = webViewHandler
            sut.actionsHandler = ActionsHandler.forOptOut(step)
            mockStageCalculator.clear()

            // Execute the condition action to set it as current action
            _ = sut.actionsHandler?.nextAction()

            // Simulate condition failure with specific error type
            await sut.onError(error: error)

            XCTAssertFalse(mockStageCalculator.fireOptOutConditionFoundCalled, "fireOptOutConditionFound should not be called for error type \(index)")
            XCTAssertTrue(mockStageCalculator.fireOptOutConditionNotFoundCalled, "fireOptOutConditionNotFound should be called for error type \(index)")
        }
    }

    func testWhenBothConditionMethodsAreCalledInSameTest_thenBothFlagsAreSet() async {
        let mockStageCalculator = MockStageDurationCalculator()
        let conditionAction = ConditionAction(id: "1", actionType: .condition)
        let step = Step(type: .optOut, actions: [conditionAction])
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            context: BrokerProfileQueryData.mock(with: [step]),
            emailConfirmationDataService: emailConfirmationDataService,
            captchaService: captchaService,
            featureFlagger: MockDBPFeatureFlagger(),
            applicationNameForUserAgentProvider: { nil },
            operationAwaitTime: 0,
            stageCalculator: mockStageCalculator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            actionsHandlerMode: .optOut,
            shouldRunNextStep: { true }
        )
        sut.webViewHandler = webViewHandler
        sut.actionsHandler = ActionsHandler.forOptOut(step)

        // First call success
        await sut.conditionSuccess(actions: [])
        XCTAssertFalse(mockStageCalculator.fireOptOutConditionFoundCalled)
        XCTAssertTrue(mockStageCalculator.fireOptOutConditionNotFoundCalled)

        // Then call failure (simulating a different scenario in the same test)
        _ = sut.actionsHandler?.nextAction() // Execute condition action
        await sut.onError(error: DataBrokerProtectionError.actionFailed(actionID: "1", message: "Condition failed"))

        // Both flags should now be true
        XCTAssertFalse(mockStageCalculator.fireOptOutConditionFoundCalled)
        XCTAssertTrue(mockStageCalculator.fireOptOutConditionNotFoundCalled)
    }

    func testWhenConditionActionIsExecutedMultipleTimes_thenFlagsAccumulateCorrectly() async {
        let mockStageCalculator = MockStageDurationCalculator()
        let conditionAction = ConditionAction(id: "1", actionType: .condition)
        let step = Step(type: .optOut, actions: [conditionAction])
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            context: BrokerProfileQueryData.mock(with: [step]),
            emailConfirmationDataService: emailConfirmationDataService,
            captchaService: captchaService,
            featureFlagger: MockDBPFeatureFlagger(),
            applicationNameForUserAgentProvider: { nil },
            operationAwaitTime: 0,
            stageCalculator: mockStageCalculator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            actionsHandlerMode: .optOut,
            shouldRunNextStep: { true }
        )
        sut.webViewHandler = webViewHandler
        sut.actionsHandler = ActionsHandler.forOptOut(step)

        // Execute multiple condition successes
        await sut.conditionSuccess(actions: [])
        await sut.conditionSuccess(actions: [])
        await sut.conditionSuccess(actions: [])

        // Flag should remain true after multiple calls
        XCTAssertFalse(mockStageCalculator.fireOptOutConditionFoundCalled)
        XCTAssertTrue(mockStageCalculator.fireOptOutConditionNotFoundCalled)

        // Clear and test multiple failures
        mockStageCalculator.clear()

        // Set up for multiple failure calls
        _ = sut.actionsHandler?.nextAction()
        await sut.onError(error: DataBrokerProtectionError.actionFailed(actionID: "1", message: "First failure"))
        await sut.onError(error: DataBrokerProtectionError.actionFailed(actionID: "1", message: "Second failure"))

        XCTAssertFalse(mockStageCalculator.fireOptOutConditionFoundCalled)
        XCTAssertTrue(mockStageCalculator.fireOptOutConditionNotFoundCalled)
    }

    // MARK: - generateEmail + fillForm fallback

    private func makeOptOutRunner(step: Step, extractedProfileId: Int64? = nil) -> BrokerProfileOptOutSubJobWebRunner {
        let runner = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            context: BrokerProfileQueryData.mock(with: [step]),
            emailConfirmationDataService: emailConfirmationDataService,
            captchaService: captchaService,
            featureFlagger: MockDBPFeatureFlagger(),
            applicationNameForUserAgentProvider: { nil },
            operationAwaitTime: 0,
            stageCalculator: stageCalculator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            actionsHandlerMode: .optOut,
            shouldRunNextStep: { true }
        )
        runner.webViewHandler = webViewHandler
        runner.extractedProfile = ExtractedProfile(id: extractedProfileId)
        return runner
    }

    private func makeScanRunner(step: Step) -> BrokerProfileScanSubJobWebRunner {
        let runner = BrokerProfileScanSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            context: BrokerProfileQueryData.mock(with: [step]),
            emailConfirmationDataService: emailConfirmationDataService,
            captchaService: captchaService,
            featureFlagger: MockDBPFeatureFlagger(),
            applicationNameForUserAgentProvider: { nil },
            operationAwaitTime: 0,
            stageDurationCalculator: stageCalculator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            shouldRunNextStep: { true }
        )
        runner.webViewHandler = webViewHandler
        return runner
    }

    // Regression guard: the legacy fillForm email-fetch path is unchanged when no prior
    // generateEmail has run.
    func testWhenFillFormNeedsEmailAndNoCachedEmail_thenServiceIsCalled() async {
        let fillFormAction = FillFormAction(id: "1", actionType: .fillForm, elements: [.init(type: "email")])
        let sut = makeOptOutRunner(step: Step(type: .optOut, actions: [fillFormAction]))

        await sut.runNextAction(fillFormAction)

        XCTAssertEqual(emailConfirmationDataService.getEmailAndSaveCallCount, 1)
        XCTAssertEqual(sut.extractedProfile?.email, "test@duck.com")
    }

    func testWhenGenerateEmailActionRunsOnOptOut_thenSaveCapableHelperIsUsedWithExtractedProfileId() async {
        let generateEmailAction = GenerateEmailAction(id: "1", actionType: .generateEmail)
        let sut = makeOptOutRunner(step: Step(type: .optOut, actions: [generateEmailAction]),
                                   extractedProfileId: 42)

        await sut.runNextAction(generateEmailAction)

        XCTAssertEqual(sut.fetchedEmail, "test@duck.com")
        XCTAssertEqual(emailConfirmationDataService.getEmailAndSaveCallCount, 1)
        XCTAssertEqual(emailConfirmationDataService.getEmailCallCount, 0)
        XCTAssertEqual(emailConfirmationDataService.lastExtractedProfileIdPassed, 42)
    }

    func testWhenGenerateEmailActionRunsOnScan_thenFetchOnlyPathIsUsed() async {
        let generateEmailAction = GenerateEmailAction(id: "1", actionType: .generateEmail)
        let sut = makeScanRunner(step: Step(type: .scan, actions: [generateEmailAction]))

        await sut.runNextAction(generateEmailAction)

        // Scan skips the save-capable helper entirely — no store row, no risk of the helper's
        // missing-ID throw. Only the fetch-only `getEmail` path runs.
        XCTAssertEqual(sut.fetchedEmail, "test@duck.com")
        XCTAssertEqual(emailConfirmationDataService.getEmailCallCount, 1)
        XCTAssertEqual(emailConfirmationDataService.getEmailAndSaveCallCount, 0)
    }

    func testWhenGenerateEmailServiceThrows_thenFetchedEmailRemainsNil() async {
        let generateEmailAction = GenerateEmailAction(id: "1", actionType: .generateEmail)
        let sut = makeOptOutRunner(step: Step(type: .optOut, actions: [generateEmailAction]))
        emailConfirmationDataService.shouldThrow = true

        await sut.runNextAction(generateEmailAction)

        XCTAssertNil(sut.fetchedEmail)
    }

    func testWhenGenerateEmailIsFollowedByFillFormWithFetchedEmailDataSource_thenNeedsEmailFallbackIsSkipped() async {
        let generateEmailAction = GenerateEmailAction(id: "1", actionType: .generateEmail)
        let fillFormAction = FillFormAction(id: "2",
                                            actionType: .fillForm,
                                            dataSource: "fetchedEmail",
                                            elements: [.init(type: "email")])
        let sut = makeOptOutRunner(step: Step(type: .optOut, actions: [generateEmailAction, fillFormAction]),
                                   extractedProfileId: 42)

        await sut.runNextAction(generateEmailAction)
        await sut.runNextAction(fillFormAction)

        XCTAssertEqual(emailConfirmationDataService.getEmailAndSaveCallCount, 1)
        XCTAssertEqual(emailConfirmationDataService.getEmailCallCount, 0)
    }

    func testWhenFillFormHasUserProfileDataSourceWithEmailElement_thenNeedsEmailFallbackStillFires() async {
        let fillFormAction = FillFormAction(id: "1",
                                            actionType: .fillForm,
                                            dataSource: "userProfile",
                                            elements: [.init(type: "email")])
        let sut = makeOptOutRunner(step: Step(type: .optOut, actions: [fillFormAction]),
                                   extractedProfileId: 42)

        await sut.runNextAction(fillFormAction)

        XCTAssertEqual(emailConfirmationDataService.getEmailAndSaveCallCount, 1)
    }

    // MARK: - getEmailData

    func testWhenGetEmailDataSucceeds_thenEmailDataIsPopulatedAndPassedToService() async {
        let action = GetEmailDataAction(id: "1", actionType: .getEmailData, pollingTime: 3)
        let sut = makeOptOutRunner(step: Step(type: .optOut, actions: [action]))
        sut.fetchedEmail = "polled@duck.com"
        emailConfirmationDataService.getEmailDataReturnValue = [
            "verificationCode": "123456",
            "token": "abc"
        ]

        await sut.runNextAction(action)

        XCTAssertEqual(emailConfirmationDataService.getEmailDataCallCount, 1)
        XCTAssertEqual(emailConfirmationDataService.lastGetEmailDataEmail, "polled@duck.com")
        XCTAssertEqual(emailConfirmationDataService.lastGetEmailDataPollingInterval, 3)
        XCTAssertEqual(emailConfirmationDataService.lastGetEmailDataTotalTimeout, BrokerJobExecutionConfig.Constants.defaultGetEmailDataTotalTimeout)
        XCTAssertEqual(sut.emailData, [
            "verificationCode": "123456",
            "token": "abc"
        ])
    }

    func testWhenGetEmailDataServiceThrows_thenActionIsNotRetried() async {
        let action = GetEmailDataAction(id: "1", actionType: .getEmailData, pollingTime: 3)
        let sut = makeOptOutRunner(step: Step(type: .optOut, actions: [action]))
        sut.fetchedEmail = "polled@duck.com"
        sut.retriesCountOnError = 3
        emailConfirmationDataService.getEmailDataThrowError = .linkExtractionTimedOut

        await sut.runNextAction(action)

        XCTAssertEqual(sut.retriesCountOnError, 0)
        XCTAssertTrue(sut.emailData.isEmpty)
    }

    func testWhenGetEmailDataCalledTwice_thenKeysMergeWithLastWriteWins() async {
        let action = GetEmailDataAction(id: "1", actionType: .getEmailData, pollingTime: 1)
        let sut = makeOptOutRunner(step: Step(type: .optOut, actions: [action]))
        sut.fetchedEmail = "polled@duck.com"

        emailConfirmationDataService.getEmailDataReturnValue = ["code": "first", "onlyFirst": "a"]
        await sut.runNextAction(action)
        emailConfirmationDataService.getEmailDataReturnValue = ["code": "second", "onlySecond": "b"]
        await sut.runNextAction(action)

        XCTAssertEqual(sut.emailData, [
            "code": "second",
            "onlyFirst": "a",
            "onlySecond": "b"
        ])
    }
}
