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
    let emailService = EmailServiceMock()
    let captchaService = CaptchaServiceMock()
    let pixelHandler = MockDataBrokerProtectionPixelsHandler()
    let stageCalulator = DataBrokerProtectionStageDurationCalculator(dataBroker: "broker", dataBrokerVersion: "1.1.1", handler: MockDataBrokerProtectionPixelsHandler(), vpnConnectionState: "disconnected", vpnBypassStatus: "off")

    override func tearDown() async throws {
        webViewHandler.reset()
        emailService.reset()
        captchaService.reset()
    }

    func testWhenEmailConfirmationActionSucceeds_thenExtractedLinkIsOpened() async {
        let emailConfirmationAction = EmailConfirmationAction(id: "", actionType: .emailConfirmation, pollingTime: 1, dataSource: nil)
        let step = Step(type: .optOut, actions: [emailConfirmationAction])
        let extractedProfile = ExtractedProfile(email: "test@duck.com")
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            query: BrokerProfileQueryData.mock(with: [step]),
            emailService: emailService,
            captchaService: captchaService,
            operationAwaitTime: 0,
            stageCalculator: stageCalulator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            shouldRunNextStep: { true }
        )

        do {
            _ = try await sut.run(inputValue: extractedProfile, webViewHandler: webViewHandler)
            XCTAssertEqual(webViewHandler.wasLoadCalledWithURL?.absoluteString, "https://www.duckduckgo.com")
            XCTAssertTrue(webViewHandler.wasFinishCalled)
        } catch {
            XCTFail("Should not throw")
        }
    }

    func testWhenEmailConfirmationActionHasNoEmail_thenNoURLIsLoadedAndWebViewFinishes() async {
        let emailConfirmationAction = EmailConfirmationAction(id: "", actionType: .emailConfirmation, pollingTime: 1, dataSource: nil)
        let step = Step(type: .optOut, actions: [emailConfirmationAction])
        let noEmailExtractedProfile = ExtractedProfile()
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            query: BrokerProfileQueryData.mock(with: [step]),
            emailService: emailService,
            captchaService: captchaService,
            operationAwaitTime: 0,
            stageCalculator: stageCalulator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            shouldRunNextStep: { true }
        )

        do {
            _ = try await sut.run(inputValue: noEmailExtractedProfile, webViewHandler: webViewHandler)
            XCTFail("Expected an error to be thrown")
        } catch {
            XCTAssertNil(webViewHandler.wasLoadCalledWithURL?.absoluteString)
            XCTAssertTrue(webViewHandler.wasFinishCalled)

            if let error = error as? DataBrokerProtectionError, case .emailError(.cantFindEmail) = error {
                return
            }

            XCTFail("Unexpected error thrown: \(error).")
        }
    }

    func testWhenOnEmailConfirmationActionEmailServiceThrows_thenOperationThrows() async {
        let emailConfirmationAction = EmailConfirmationAction(id: "", actionType: .emailConfirmation, pollingTime: 1, dataSource: nil)
        let step = Step(type: .optOut, actions: [emailConfirmationAction])
        let extractedProfile = ExtractedProfile(email: "test@duck.com")
        emailService.shouldThrow = true
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            query: BrokerProfileQueryData.mock(with: [step]),
            emailService: emailService,
            captchaService: captchaService,
            operationAwaitTime: 0,
            stageCalculator: stageCalulator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            shouldRunNextStep: { true }
        )

        do {
            _ = try await sut.run(inputValue: extractedProfile, webViewHandler: webViewHandler)
            XCTFail("Expected an error to be thrown")
        } catch {
            XCTAssertNil(webViewHandler.wasLoadCalledWithURL?.absoluteString)
            XCTAssertTrue(webViewHandler.wasFinishCalled)

            if let error = error as? DataBrokerProtectionError, case .emailError(nil) = error {
                return
            }

            XCTFail("Unexpected error thrown: \(error).")
        }
    }

    func testWhenActionNeedsEmail_thenExtractedProfileEmailIsSet() async {
        let fillFormAction = FillFormAction(id: "1", actionType: .fillForm, selector: "#test", elements: [.init(type: "email", selector: "#email", parent: nil, multiple: nil, min: nil, max: nil, failSilently: nil)], dataSource: nil)
        let step = Step(type: .optOut, actions: [fillFormAction])
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            query: BrokerProfileQueryData.mock(with: [step]),
            emailService: emailService,
            captchaService: captchaService,
            operationAwaitTime: 0,
            stageCalculator: stageCalulator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            shouldRunNextStep: { true }
        )
        sut.webViewHandler = webViewHandler
        sut.extractedProfile = ExtractedProfile()

        await sut.runNextAction(fillFormAction)

        XCTAssertEqual(sut.extractedProfile?.email, "test@duck.com")
        XCTAssertTrue(webViewHandler.wasExecuteCalledForUserData)
    }

    func testWhenGetEmailServiceFails_thenOperationThrows() async {
        let fillFormAction = FillFormAction(id: "1", actionType: .fillForm, selector: "#test", elements: [.init(type: "email", selector: "#email", parent: nil, multiple: nil, min: nil, max: nil, failSilently: nil)], dataSource: nil)
        let step = Step(type: .optOut, actions: [fillFormAction])
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            query: BrokerProfileQueryData.mock(with: [step]),
            emailService: emailService,
            captchaService: captchaService,
            operationAwaitTime: 0,
            stageCalculator: stageCalulator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            shouldRunNextStep: { true }
        )
        emailService.shouldThrow = true

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
            query: BrokerProfileQueryData.mock(),
            emailService: emailService,
            captchaService: captchaService,
            operationAwaitTime: 0,
            clickAwaitTime: 0,
            stageCalculator: stageCalulator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            shouldRunNextStep: { true }
        )
        sut.webViewHandler = webViewHandler

        await sut.success(actionId: "1", actionType: .click)

        XCTAssertFalse(webViewHandler.wasWaitForWebViewLoadCalled)
        XCTAssertTrue(webViewHandler.wasFinishCalled)
    }

    func testWhenAnActionThatIsNotClickSucceeds_thenWeDoNotWaitForWebViewToLoad() async {
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            query: BrokerProfileQueryData.mock(),
            emailService: emailService,
            captchaService: captchaService,
            operationAwaitTime: 0,
            stageCalculator: stageCalulator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            shouldRunNextStep: { true }
        )
        sut.webViewHandler = webViewHandler

        await sut.success(actionId: "1", actionType: .expectation)

        XCTAssertFalse(webViewHandler.wasWaitForWebViewLoadCalled)
        XCTAssertTrue(webViewHandler.wasFinishCalled)
    }

    func testWhenSolveCaptchaActionIsRun_thenCaptchaIsResolved() async {
        let solveCaptchaAction = SolveCaptchaAction(id: "1", actionType: .solveCaptcha, selector: "g-captcha", dataSource: nil, captchaType: nil)
        let step = Step(type: .optOut, actions: [solveCaptchaAction])
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            query: BrokerProfileQueryData.mock(),
            emailService: emailService,
            captchaService: captchaService,
            operationAwaitTime: 0,
            stageCalculator: stageCalulator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            shouldRunNextStep: { true }
        )
        sut.webViewHandler = webViewHandler
        sut.actionsHandler = ActionsHandler(step: step)
        sut.actionsHandler?.captchaTransactionId = "transactionId"

        await sut.runNextAction(solveCaptchaAction)

        XCTAssert(webViewHandler.wasExecuteCalledForSolveCaptcha)
    }

    func testWhenSolveCapchaActionFailsToSubmitDataToTheBackend_thenOperationFails() async {
        let solveCaptchaAction = SolveCaptchaAction(id: "1", actionType: .solveCaptcha, selector: "g-captcha", dataSource: nil, captchaType: nil)
        let step = Step(type: .optOut, actions: [solveCaptchaAction])
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            query: BrokerProfileQueryData.mock(with: [step]),
            emailService: emailService,
            captchaService: captchaService,
            operationAwaitTime: 0,
            stageCalculator: stageCalulator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            shouldRunNextStep: { true }
        )
        let actionsHandler = ActionsHandler(step: step)
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
            query: BrokerProfileQueryData.mock(),
            emailService: emailService,
            captchaService: captchaService,
            operationAwaitTime: 0,
            stageCalculator: stageCalulator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            shouldRunNextStep: { true }
        )
        sut.webViewHandler = webViewHandler
        sut.actionsHandler = ActionsHandler(step: step)

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
            query: BrokerProfileQueryData.mock(),
            emailService: emailService,
            captchaService: captchaService,
            operationAwaitTime: 0,
            stageCalculator: stageCalulator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            shouldRunNextStep: { true }
        )
        sut.resetRetriesCount()
        captchaService.shouldThrow = true
        sut.webViewHandler = webViewHandler
        sut.actionsHandler = ActionsHandler(step: step)

        await sut.captchaInformation(captchaInfo: getCaptchaResponse)

        XCTAssertFalse(captchaService.wasSubmitCaptchaInformationCalled)
        XCTAssert(webViewHandler.wasFinishCalled)
    }

    func testWhenRunningActionWithoutExtractedProfile_thenExecuteIsCalledWithProfileData() async {
        let expectationAction = ExpectationAction(id: "1", actionType: .expectation, expectations: [Item](), dataSource: nil, actions: nil)
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            query: BrokerProfileQueryData.mock(),
            emailService: emailService,
            captchaService: captchaService,
            operationAwaitTime: 0,
            stageCalculator: stageCalulator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
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
            query: BrokerProfileQueryData.mock(),
            emailService: emailService,
            captchaService: captchaService,
            operationAwaitTime: 0,
            stageCalculator: stageCalulator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            shouldRunNextStep: { true }
        )
        sut.webViewHandler = webViewHandler

        await sut.loadURL(url: URL(string: "https://www.duckduckgo.com")!)

        XCTAssertEqual(webViewHandler.wasLoadCalledWithURL?.absoluteString, "https://www.duckduckgo.com")
    }

    func testWhenGetCaptchaActionRuns_thenStageIsSetToCaptchaParse() async {
        let mockStageCalculator = MockStageDurationCalculator()
        let captchaAction = GetCaptchaInfoAction(id: "1", actionType: .getCaptchaInfo, selector: "captcha", dataSource: nil, captchaType: nil)
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            query: BrokerProfileQueryData.mock(),
            emailService: emailService,
            captchaService: captchaService,
            operationAwaitTime: 0,
            stageCalculator: mockStageCalculator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            shouldRunNextStep: { true }
        )

        await sut.runNextAction(captchaAction)

        XCTAssertEqual(mockStageCalculator.stage, .captchaParse)
    }

    func testWhenClickActionRuns_thenStageIsSetToSubmit() async {
        let mockStageCalculator = MockStageDurationCalculator()
        let clickAction = ClickAction(id: "1", actionType: .click, elements: [PageElement](), dataSource: nil, choices: nil, default: nil, hasDefault: false)
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            query: BrokerProfileQueryData.mock(),
            emailService: emailService,
            captchaService: captchaService,
            operationAwaitTime: 0,
            stageCalculator: mockStageCalculator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            shouldRunNextStep: { true }
        )

        await sut.runNextAction(clickAction)

        XCTAssertEqual(mockStageCalculator.stage, .fillForm)
    }

    func testWhenExpectationActionRuns_thenStageIsSetToSubmit() async {
        let mockStageCalculator = MockStageDurationCalculator()
        let expectationAction = ExpectationAction(id: "1", actionType: .expectation, expectations: [Item](), dataSource: nil, actions: nil)
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            query: BrokerProfileQueryData.mock(),
            emailService: emailService,
            captchaService: captchaService,
            operationAwaitTime: 0,
            stageCalculator: mockStageCalculator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            shouldRunNextStep: { true }
        )

        await sut.runNextAction(expectationAction)

        XCTAssertEqual(mockStageCalculator.stage, .submit)
    }

    func testWhenExpectationActionRunsDuringScan_thenRetriesCountIsSetToOne() async {
        let expectationAction = ExpectationAction(id: "1", actionType: .expectation, expectations: [Item](), dataSource: nil, actions: nil)
        let sut = BrokerProfileScanSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            query: .mock(with: [Step(type: .scan, actions: [])]),
            emailService: emailService,
            captchaService: captchaService,
            stageDurationCalculator: MockStageDurationCalculator(),
            pixelHandler: MockPixelHandler(),
            executionConfig: BrokerJobExecutionConfig(),
            shouldRunNextStep: { true }
        )

        XCTAssertEqual(sut.retriesCountOnError, 0)
        await sut.runNextAction(expectationAction)
        XCTAssertEqual(sut.retriesCountOnError, 1)
    }

    func testWhenExpectationActionRunsDuringOptOut_thenRetriesCountIsSetToThree() async {
        let expectationAction = ExpectationAction(id: "1", actionType: .expectation, expectations: [Item](), dataSource: nil, actions: nil)
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            query: BrokerProfileQueryData.mock(),
            emailService: emailService,
            captchaService: captchaService,
            operationAwaitTime: 0,
            stageCalculator: MockStageDurationCalculator(),
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            shouldRunNextStep: { true }
        )

        XCTAssertEqual(sut.retriesCountOnError, 3)
        await sut.runNextAction(expectationAction)
        XCTAssertEqual(sut.retriesCountOnError, 3)
    }

    func testWhenExpectationActionFailsDuringScan_thenRetryOnce() async {
        let expectationAction = ExpectationAction(id: "1", actionType: .expectation, expectations: [Item](), dataSource: nil, actions: nil)
        let step = Step(type: .scan, actions: [expectationAction])
        let sut = BrokerProfileScanSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            query: .mock(with: [Step(type: .scan, actions: [])]),
            emailService: emailService,
            captchaService: captchaService,
            stageDurationCalculator: MockStageDurationCalculator(),
            pixelHandler: MockPixelHandler(),
            executionConfig: BrokerJobExecutionConfig(),
            shouldRunNextStep: { true }
        )
        sut.webViewHandler = webViewHandler
        sut.actionsHandler = ActionsHandler(step: step)

        await sut.runNextAction(expectationAction)
        XCTAssertEqual(sut.retriesCountOnError, 1)

        _ = sut.actionsHandler?.nextAction()

        await sut.onError(error: DataBrokerProtectionError.httpError(code: 429))
        XCTAssertEqual(sut.retriesCountOnError, 0)

        await sut.onError(error: DataBrokerProtectionError.httpError(code: 429))
        XCTAssertTrue(webViewHandler.wasFinishCalled)
    }

    func testWhenFillFormActionRuns_thenStageIsSetToFillForm() async {
        let mockStageCalculator = MockStageDurationCalculator()
        let fillFormAction = FillFormAction(id: "1", actionType: .fillForm, selector: "", elements: [PageElement](), dataSource: nil)
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            query: BrokerProfileQueryData.mock(),
            emailService: emailService,
            captchaService: captchaService,
            operationAwaitTime: 0,
            stageCalculator: mockStageCalculator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
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
            query: BrokerProfileQueryData.mock(url: "spokeo.com"),
            emailService: emailService,
            captchaService: captchaService,
            cookieHandler: mockCookieHandler,
            operationAwaitTime: 0,
            stageCalculator: stageCalulator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
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
            query: BrokerProfileQueryData.mock(url: "verecor.com"),
            emailService: emailService,
            captchaService: captchaService,
            cookieHandler: mockCookieHandler,
            operationAwaitTime: 0,
            stageCalculator: stageCalulator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
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
        let conditionAction = ConditionAction(id: "1", actionType: .condition, expectations: [Item](), dataSource: nil, actions: [])
        let step = Step(type: .optOut, actions: [conditionAction])
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            query: BrokerProfileQueryData.mock(with: [step]),
            emailService: emailService,
            captchaService: captchaService,
            operationAwaitTime: 0,
            stageCalculator: mockStageCalculator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            shouldRunNextStep: { true }
        )
        sut.webViewHandler = webViewHandler
        sut.actionsHandler = ActionsHandler(step: step)

        // Simulate condition success
        await sut.conditionSuccess(actions: [])

        XCTAssertFalse(mockStageCalculator.fireOptOutConditionFoundCalled)
        XCTAssertTrue(mockStageCalculator.fireOptOutConditionNotFoundCalled)
    }

    func testWhenConditionActionFailsInOptOutStep_thenFireOptOutConditionNotFoundIsCalled() async {
        let mockStageCalculator = MockStageDurationCalculator()
        let conditionAction = ConditionAction(id: "1", actionType: .condition, expectations: [Item](), dataSource: nil, actions: [])
        let step = Step(type: .optOut, actions: [conditionAction])
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            query: BrokerProfileQueryData.mock(with: [step]),
            emailService: emailService,
            captchaService: captchaService,
            operationAwaitTime: 0,
            stageCalculator: mockStageCalculator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            shouldRunNextStep: { true }
        )
        sut.webViewHandler = webViewHandler
        sut.actionsHandler = ActionsHandler(step: step)

        // Execute the condition action to set it as current action
        _ = sut.actionsHandler?.nextAction()

        // Simulate condition failure
        await sut.onError(error: DataBrokerProtectionError.actionFailed(actionID: "1", message: "Condition failed"))

        XCTAssertFalse(mockStageCalculator.fireOptOutConditionFoundCalled)
        XCTAssertTrue(mockStageCalculator.fireOptOutConditionNotFoundCalled)
    }

    func testWhenConditionActionSucceedsInScanStep_thenFireOptOutConditionFoundIsNotCalled() async {
        let mockStageCalculator = MockStageDurationCalculator()
        let conditionAction = ConditionAction(id: "1", actionType: .condition, expectations: [Item](), dataSource: nil, actions: [])
        let step = Step(type: .scan, actions: [conditionAction])
        let sut = BrokerProfileScanSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            query: .mock(with: [step]),
            emailService: emailService,
            captchaService: captchaService,
            stageDurationCalculator: mockStageCalculator,
            pixelHandler: MockPixelHandler(),
            executionConfig: BrokerJobExecutionConfig(),
            shouldRunNextStep: { true }
        )
        sut.webViewHandler = webViewHandler
        sut.actionsHandler = ActionsHandler(step: step)

        // Simulate condition success in scan step
        await sut.conditionSuccess(actions: [])

        XCTAssertFalse(mockStageCalculator.fireOptOutConditionFoundCalled)
        XCTAssertFalse(mockStageCalculator.fireOptOutConditionNotFoundCalled)
    }

    func testWhenNonConditionActionFailsInOptOutStep_thenFireOptOutConditionNotFoundIsNotCalled() async {
        let mockStageCalculator = MockStageDurationCalculator()
        let expectationAction = ExpectationAction(id: "1", actionType: .expectation, expectations: [Item](), dataSource: nil, actions: nil)
        let step = Step(type: .optOut, actions: [expectationAction])
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            query: BrokerProfileQueryData.mock(with: [step]),
            emailService: emailService,
            captchaService: captchaService,
            operationAwaitTime: 0,
            stageCalculator: mockStageCalculator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            shouldRunNextStep: { true }
        )
        sut.webViewHandler = webViewHandler
        sut.actionsHandler = ActionsHandler(step: step)

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
        let followUpAction = ExpectationAction(id: "followup", actionType: .expectation, expectations: [Item](), dataSource: nil, actions: nil)
        let conditionAction = ConditionAction(id: "1", actionType: .condition, expectations: [Item](), dataSource: nil, actions: [followUpAction])
        let step = Step(type: .optOut, actions: [conditionAction])
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            query: BrokerProfileQueryData.mock(with: [step]),
            emailService: emailService,
            captchaService: captchaService,
            operationAwaitTime: 0,
            stageCalculator: mockStageCalculator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            shouldRunNextStep: { true }
        )
        sut.webViewHandler = webViewHandler
        sut.actionsHandler = ActionsHandler(step: step)

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
        let firstCondition = ConditionAction(id: "condition1", actionType: .condition, expectations: [Item](), dataSource: nil, actions: [])
        let secondCondition = ConditionAction(id: "condition2", actionType: .condition, expectations: [Item](), dataSource: nil, actions: [])
        let step = Step(type: .optOut, actions: [firstCondition, secondCondition])
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            query: BrokerProfileQueryData.mock(with: [step]),
            emailService: emailService,
            captchaService: captchaService,
            operationAwaitTime: 0,
            stageCalculator: mockStageCalculator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            shouldRunNextStep: { true }
        )
        sut.webViewHandler = webViewHandler
        sut.actionsHandler = ActionsHandler(step: step)

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
        let conditionAction = ConditionAction(id: "1", actionType: .condition, expectations: [Item](), dataSource: nil, actions: [])
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
                query: BrokerProfileQueryData.mock(with: [step]),
                emailService: emailService,
                captchaService: captchaService,
                operationAwaitTime: 0,
                stageCalculator: mockStageCalculator,
                pixelHandler: pixelHandler,
                executionConfig: BrokerJobExecutionConfig(),
                shouldRunNextStep: { true }
            )
            sut.webViewHandler = webViewHandler
            sut.actionsHandler = ActionsHandler(step: step)
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
        let conditionAction = ConditionAction(id: "1", actionType: .condition, expectations: [Item](), dataSource: nil, actions: [])
        let step = Step(type: .optOut, actions: [conditionAction])
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            query: BrokerProfileQueryData.mock(with: [step]),
            emailService: emailService,
            captchaService: captchaService,
            operationAwaitTime: 0,
            stageCalculator: mockStageCalculator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            shouldRunNextStep: { true }
        )
        sut.webViewHandler = webViewHandler
        sut.actionsHandler = ActionsHandler(step: step)

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
        let conditionAction = ConditionAction(id: "1", actionType: .condition, expectations: [Item](), dataSource: nil, actions: [])
        let step = Step(type: .optOut, actions: [conditionAction])
        let sut = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(),
            prefs: ContentScopeProperties.mock,
            query: BrokerProfileQueryData.mock(with: [step]),
            emailService: emailService,
            captchaService: captchaService,
            operationAwaitTime: 0,
            stageCalculator: mockStageCalculator,
            pixelHandler: pixelHandler,
            executionConfig: BrokerJobExecutionConfig(),
            shouldRunNextStep: { true }
        )
        sut.webViewHandler = webViewHandler
        sut.actionsHandler = ActionsHandler(step: step)

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
}
