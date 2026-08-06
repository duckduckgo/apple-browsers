//
//  SubJobWebRunnerTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Foundation
@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils

final class DataBrokerJobTests: XCTestCase {

    func testWhenScanJobEncounters404_thenNextActionIsExecuted() async throws {
        // Given
        let sut = scanJob
        let mockActionsHandler = MockActionsHandler()
        sut.actionsHandler = mockActionsHandler
        let mockWebHandler = WebViewHandlerMock()
        mockWebHandler.errorStatusCodeToThrow = 404
        try await sut.initialize(handler: mockWebHandler, showWebView: false)

        // When
        await sut.loadURL(url: URL(string: "www.duckduckgo.com")!)

        // Then
        XCTAssertTrue(mockActionsHandler.didCallNextAction)
    }

    func testWhenScanJobEncounters403_thenNextActionIsNotExecuted() async throws {
        // Given
        let sut = scanJob
        let mockActionsHandler = MockActionsHandler()
        sut.actionsHandler = mockActionsHandler
        let mockWebHandler = WebViewHandlerMock()
        mockWebHandler.errorStatusCodeToThrow = 403
        try await sut.initialize(handler: mockWebHandler, showWebView: false)

        // When
        await sut.loadURL(url: URL(string: "www.duckduckgo.com")!)

        // Then
        XCTAssertFalse(mockActionsHandler.didCallNextAction)
    }

    func testWhenOptOutEncounters404_thenNextActionIsNotExecuted() async throws {
        // Given
        let sut = optOutJob
        let mockActionsHandler = MockActionsHandler()
        sut.actionsHandler = mockActionsHandler
        let mockWebHandler = WebViewHandlerMock()
        mockWebHandler.errorStatusCodeToThrow = 404
        try await sut.initialize(handler: mockWebHandler, showWebView: false)

        // When
        await sut.loadURL(url: URL(string: "www.duckduckgo.com")!)

        // Then
        XCTAssertFalse(mockActionsHandler.didCallNextAction)
    }

    func testWhenScan_thenWillRetryOnce() async throws {
        // Given
        let sut = optOutJob
        let mockActionsHandler = MockActionsHandler(stepType: .scan)
        sut.actionsHandler = mockActionsHandler

        let action = NavigateAction(id: "navigate", actionType: .navigate, url: "url")

        // When
        _ = await sut.evaluateActionAndHaltIfNeeded(action)

        // Then
        XCTAssertEqual(sut.retriesCountOnError, 1)
    }

    func testWhenOptOut_thenWillRetryOnce() async throws {
        // Given
        let sut = optOutJob
        let mockActionsHandler = MockActionsHandler(stepType: .optOut)
        sut.actionsHandler = mockActionsHandler
        let action = NavigateAction(id: "navigate", actionType: .navigate, url: "url")

        // When
        _ = await sut.evaluateActionAndHaltIfNeeded(action)

        // Then
        XCTAssertEqual(sut.retriesCountOnError, 1)
    }

    @MainActor
    func testWhenScanIsCancelledAfterDispatchingAction_thenFinishesAndIgnoresLateCallbacks() async {
        let action = NavigateAction(id: "navigate", actionType: .navigate, url: "https://example.com")
        let stageCalculator = MockStageDurationCalculator()
        stageCalculator.isImmediateOperation = true
        let pixelHandler = MockDataBrokerProtectionPixelsHandler()
        let sut = makeScanJob(actions: [action],
                              operationAwaitTime: 0,
                              stageDurationCalculator: stageCalculator,
                              pixelHandler: pixelHandler)
        sut.postLoadingSiteStartTime = Date()
        let webViewHandler = WebViewHandlerMock()
        let actionDispatched = expectation(description: "Action dispatched")
        let runFinished = expectation(description: "Scan run finished")
        let webViewFinished = expectation(description: "Web view finished")
        webViewHandler.executeHandler = {
            actionDispatched.fulfill()
        }
        webViewHandler.finishHandler = { [weak webViewHandler] in
            if webViewHandler?.finishCallCount == 1 {
                webViewFinished.fulfill()
            }
        }

        let runTask = Task { @MainActor in
            defer { runFinished.fulfill() }

            do {
                _ = try await sut.run(inputValue: (),
                                      webViewHandler: webViewHandler,
                                      actionsHandler: nil,
                                      showWebView: false)
                XCTFail("Expected cancellation error")
            } catch {
                XCTAssertEqual(error as? DataBrokerProtectionError, .cancelled)
            }
        }

        await fulfillment(of: [actionDispatched], timeout: 5)
        runTask.cancel()
        await fulfillment(of: [runFinished, webViewFinished], timeout: 5)
        webViewHandler.finishHandler = nil

        XCTAssertTrue(webViewHandler.wasFinishCalled)
        XCTAssertEqual(webViewHandler.finishCallCount, 1)
        XCTAssertEqual(webViewHandler.executeCallCount, 1)

        await sut.success(actionId: action.id, actionType: action.actionType)

        XCTAssertEqual(webViewHandler.finishCallCount, 2)

        sut.retriesCountOnError = 1
        await sut.onError(error: DataBrokerProtectionError.actionFailed(actionID: action.id, message: "Late error"))
        await sut.extractedProfiles(profiles: [], meta: nil)

        XCTAssertEqual(webViewHandler.executeCallCount, 1)

        let postLoadingDurationEvents = pixelHandler.firedEvents.filter {
            if case .initialScanPostLoadingDuration = $0 {
                return true
            }
            return false
        }
        XCTAssertEqual(postLoadingDurationEvents.count, 1)
    }

    @MainActor
    func testWhenScanIsCancelledDuringWebViewInitialization_thenDoesNotDispatchAction() async {
        let action = NavigateAction(id: "navigate", actionType: .navigate, url: "https://example.com")
        let sut = makeScanJob(actions: [action], operationAwaitTime: 0)
        let webViewHandler = WebViewHandlerMock()
        let initializationStarted = expectation(description: "Web view initialization started")
        let runFinished = expectation(description: "Scan run finished")
        let webViewFinished = expectation(description: "Web view finished")
        let initializationGate = WebViewInitializationTestGate()
        webViewHandler.initializeWebViewHandler = {
            initializationStarted.fulfill()
            await initializationGate.wait()
        }
        webViewHandler.finishHandler = { [weak webViewHandler] in
            if webViewHandler?.finishCallCount == 1 {
                webViewFinished.fulfill()
            }
        }

        let runTask = Task { @MainActor in
            defer { runFinished.fulfill() }

            do {
                _ = try await sut.run(inputValue: (),
                                      webViewHandler: webViewHandler,
                                      actionsHandler: nil,
                                      showWebView: false)
                XCTFail("Expected cancellation error")
            } catch {
                XCTAssertEqual(error as? DataBrokerProtectionError, .cancelled)
            }
        }

        await fulfillment(of: [initializationStarted], timeout: 5)
        runTask.cancel()
        await fulfillment(of: [webViewFinished], timeout: 5)
        await initializationGate.open()
        await fulfillment(of: [runFinished], timeout: 5)

        XCTAssertTrue(webViewHandler.wasFinishCalled)
        XCTAssertEqual(webViewHandler.executeCallCount, 0)
    }

    @MainActor
    func testWhenShouldRunNextStepIsFalse_thenOnErrorReportsCancelledAndReleasesTheWebView() async {
        let action = NavigateAction(id: "navigate", actionType: .navigate, url: "https://example.com")
        let sut = makeScanJob(actions: [action], operationAwaitTime: 0, shouldRunNextStep: { false })
        let webViewHandler = WebViewHandlerMock()
        sut.webViewHandler = webViewHandler
        sut.retriesCountOnError = 1

        await sut.onError(error: DataBrokerProtectionError.actionFailed(actionID: action.id, message: "Failed"))

        XCTAssertTrue(webViewHandler.wasFinishCalled)
        XCTAssertEqual(webViewHandler.executeCallCount, 0)
    }

    @MainActor
    func testWhenOptOutIsCancelledAfterDispatchingAction_thenFinishes() async {
        let action = NavigateAction(id: "navigate", actionType: .navigate, url: "https://example.com")
        let sut = makeOptOutJob(actions: [action], operationAwaitTime: 0)
        let webViewHandler = WebViewHandlerMock()
        let actionDispatched = expectation(description: "Action dispatched")
        let runFinished = expectation(description: "Opt-out run finished")
        let webViewFinished = expectation(description: "Web view finished")
        webViewHandler.executeHandler = {
            actionDispatched.fulfill()
        }
        webViewHandler.finishHandler = { [weak webViewHandler] in
            if webViewHandler?.finishCallCount == 1 {
                webViewFinished.fulfill()
            }
        }

        let runTask = Task { @MainActor in
            defer { runFinished.fulfill() }

            do {
                try await sut.run(inputValue: .mockWithoutRemovedDate,
                                  webViewHandler: webViewHandler,
                                  actionsHandler: nil,
                                  showWebView: false)
                XCTFail("Expected cancellation error")
            } catch {
                XCTAssertEqual(error as? DataBrokerProtectionError, .cancelled)
            }
        }

        await fulfillment(of: [actionDispatched], timeout: 5)
        runTask.cancel()
        await fulfillment(of: [runFinished, webViewFinished], timeout: 5)
        webViewHandler.finishHandler = nil

        XCTAssertTrue(webViewHandler.wasFinishCalled)
        XCTAssertEqual(webViewHandler.finishCallCount, 1)
        XCTAssertEqual(webViewHandler.executeCallCount, 1)

        await sut.success(actionId: action.id, actionType: action.actionType)

        XCTAssertEqual(webViewHandler.finishCallCount, 2)
        XCTAssertEqual(webViewHandler.executeCallCount, 1)
    }
}

private extension DataBrokerJobTests {

    var scanJob: BrokerProfileScanSubJobWebRunner {
        makeScanJob()
    }

    var optOutJob: BrokerProfileOptOutSubJobWebRunner {
        makeOptOutJob()
    }

    func makeScanJob(actions: [Action] = [],
                     operationAwaitTime: TimeInterval = 3,
                     shouldRunNextStep: @escaping () -> Bool = { true },
                     stageDurationCalculator: StageDurationCalculator = MockStageDurationCalculator(),
                     pixelHandler: MockDataBrokerProtectionPixelsHandler = .init()) -> BrokerProfileScanSubJobWebRunner {
        BrokerProfileScanSubJobWebRunner(privacyConfig: PrivacyConfigurationManagingMock(),
                                         prefs: .mock,
                                         context: BrokerProfileQueryData.mock(with: [Step(type: .scan, actions: actions)]),
                                         emailConfirmationDataService: MockEmailConfirmationDataServiceProvider(),
                                         captchaService: CaptchaServiceMock(),
                                         featureFlagger: MockDBPFeatureFlagger(),
                                         applicationNameForUserAgentProvider: { nil },
                                         operationAwaitTime: operationAwaitTime,
                                         stageDurationCalculator: stageDurationCalculator,
                                         pixelHandler: pixelHandler,
                                         executionConfig: BrokerJobExecutionConfig(),
                                         shouldRunNextStep: shouldRunNextStep)
    }

    func makeOptOutJob(actions: [Action] = [], operationAwaitTime: TimeInterval = 3) -> BrokerProfileOptOutSubJobWebRunner {
        BrokerProfileOptOutSubJobWebRunner(privacyConfig: PrivacyConfigurationManagingMock(),
                                           prefs: .mock,
                                           context: BrokerProfileQueryData.mock(with: [Step(type: .optOut, actions: actions)]),
                                           emailConfirmationDataService: MockEmailConfirmationDataServiceProvider(),
                                           captchaService: CaptchaServiceMock(),
                                           featureFlagger: MockDBPFeatureFlagger(),
                                           applicationNameForUserAgentProvider: { nil },
                                           operationAwaitTime: operationAwaitTime,
                                           stageCalculator: MockStageDurationCalculator(),
                                           pixelHandler: MockDataBrokerProtectionPixelsHandler(),
                                           executionConfig: BrokerJobExecutionConfig(),
                                           actionsHandlerMode: .optOut,
                                           shouldRunNextStep: { true })
    }

}

private actor WebViewInitializationTestGate {

    private var isOpen = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !isOpen else { return }

        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}
