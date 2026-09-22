//
//  DebugPIRRecoveryTests.swift
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

#if DEBUG
import XCTest
import WebKit
import DataBrokerProtectionCoreTestsUtils
@testable import DataBrokerProtectionCore

@MainActor
final class DebugPIRRecoveryTests: XCTestCase {
    private let original = ClickAction(id: "broken", actionType: .click)
    private let replacement = ClickAction(id: "replacement", actionType: .click)

    private func makeRunner() -> (BrokerProfileScanSubJobWebRunner, WebViewHandlerMock) {
        let step = Step(type: .scan, actions: [original, ClickAction(id: "next", actionType: .click)])
        let runner = BrokerProfileScanSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(), prefs: .mock,
            context: BrokerProfileQueryData.mock(with: [step]),
            emailConfirmationDataService: MockEmailConfirmationDataServiceProvider(),
            captchaService: CaptchaServiceMock(), featureFlagger: MockDBPFeatureFlagger(),
            applicationNameForUserAgentProvider: { nil }, operationAwaitTime: 0,
            stageDurationCalculator: MockStageDurationCalculator(), pixelHandler: MockDataBrokerProtectionPixelsHandler(),
            executionConfig: BrokerJobExecutionConfig(), shouldRunNextStep: { true })
        let webView = WebViewHandlerMock()
        webView.webViewForInspection = WKWebView()
        runner.webViewHandler = webView
        runner.actionsHandler = ActionsHandler.forScan(step)
        _ = runner.actionsHandler?.nextAction()
        return (runner, webView)
    }

    func testReplacementExecutesAndResumesAtNextAuthoredAction() async throws {
        let (runner, webView) = makeRunner()
        runner.debugRecovery = DebugPIRRecoverySession { [replacement] request, _, _, _ in
            XCTAssertEqual(request.failedActionID, "broken")
            XCTAssertEqual(request.completedActionCount, 0)
            return replacement
        }
        await runner.onError(error: DataBrokerProtectionError.actionFailed(actionID: "broken", message: "missing target"))
        XCTAssertEqual(runner.actionsHandler?.currentAction()?.id, "replacement")
        XCTAssertEqual(webView.executeCallCount, 1)
        await runner.success(actionId: "replacement", actionType: .click)
        XCTAssertEqual(runner.actionsHandler?.currentAction()?.id, "next")
        XCTAssertEqual(webView.executeCallCount, 2)
        await runner.success(actionId: "replacement", actionType: .click)
        XCTAssertEqual(runner.actionsHandler?.currentAction()?.id, "next")
        XCTAssertEqual(webView.executeCallCount, 2)
    }

    func testRecoveryDisabledUsesNormalFailureHandling() async {
        let (runner, webView) = makeRunner()
        await runner.onError(error: DataBrokerProtectionError.actionFailed(actionID: "broken", message: "missing target"))
        XCTAssertEqual(webView.executeCallCount, 0)
        XCTAssertTrue(webView.wasFinishCalled)
        XCTAssertEqual(runner.actionsHandler?.currentAction()?.id, "broken")
    }

    func testReplacementFailureDoesNotGenerateOrExecuteAgain() async {
        let (runner, webView) = makeRunner()
        var generationCount = 0
        runner.debugRecovery = DebugPIRRecoverySession { [replacement] _, _, _, _ in
            generationCount += 1
            return replacement
        }
        await runner.onError(error: DataBrokerProtectionError.actionFailed(actionID: "broken", message: "missing target"))
        await runner.onError(error: DataBrokerProtectionError.actionFailed(actionID: "replacement", message: "still failed"))
        XCTAssertEqual(generationCount, 1)
        XCTAssertEqual(webView.executeCallCount, 1)
        XCTAssertTrue(webView.wasFinishCalled)
    }

    func testLateOriginalCallbacksDoNotAdvanceReplacement() async {
        let (runner, webView) = makeRunner()
        runner.debugRecovery = DebugPIRRecoverySession { [replacement] _, _, _, _ in
            return replacement
        }
        await runner.onError(error: DataBrokerProtectionError.actionFailed(actionID: "broken", message: "missing target"))
        await runner.success(actionId: "broken", actionType: .click)
        await runner.onError(error: DataBrokerProtectionError.actionFailed(actionID: "broken", message: "late failure"))
        XCTAssertEqual(runner.actionsHandler?.currentAction()?.id, "replacement")
        XCTAssertEqual(webView.executeCallCount, 1)
        XCTAssertFalse(webView.wasFinishCalled)
    }

    func testCancellationDuringGenerationDoesNotExecuteProposal() async {
        let (runner, webView) = makeRunner()
        runner.debugRecovery = DebugPIRRecoverySession { [weak runner, replacement] _, _, _, _ in
            _ = runner?.runnerCancellation.markCancelled()
            return replacement
        }
        await runner.onError(error: DataBrokerProtectionError.actionFailed(actionID: "broken", message: "missing target"))
        XCTAssertEqual(webView.executeCallCount, 0)
        XCTAssertTrue(webView.wasFinishCalled)
        XCTAssertEqual(runner.actionsHandler?.currentAction()?.id, "broken")
    }

    func testGenerationFailureUsesNormalFailureHandling() async {
        let (runner, webView) = makeRunner()
        runner.debugRecovery = DebugPIRRecoverySession { _, _, _, _ in
            throw DataBrokerProtectionError.webContentProcessTerminated
        }
        await runner.onError(error: DataBrokerProtectionError.actionFailed(actionID: "broken", message: "missing target"))
        XCTAssertEqual(webView.executeCallCount, 0)
        XCTAssertTrue(webView.wasFinishCalled)
    }

    func testNonActionFailureDuringGenerationTerminatesAndDiscardsProposal() async {
        let (runner, webView) = makeRunner()
        runner.debugRecovery = DebugPIRRecoverySession { [weak runner, replacement] _, _, _, _ in
            await runner?.onError(error: DataBrokerProtectionError.webContentProcessTerminated)
            return replacement
        }
        await runner.onError(error: DataBrokerProtectionError.actionFailed(actionID: "broken", message: "missing target"))
        XCTAssertEqual(webView.executeCallCount, 0)
        XCTAssertTrue(webView.wasFinishCalled)
    }

    func testWrongActionTypeRejected() async {
        let (runner, webView) = makeRunner()
        runner.debugRecovery = DebugPIRRecoverySession { _, _, _, _ in
            return FillFormAction(id: "wrong-type", actionType: .fillForm, elements: [])
        }
        await runner.onError(error: DataBrokerProtectionError.actionFailed(actionID: "broken", message: "missing target"))
        XCTAssertEqual(runner.actionsHandler?.currentAction()?.id, "broken")
        XCTAssertEqual(webView.executeCallCount, 0)
        XCTAssertTrue(webView.wasFinishCalled)
    }

    func testRecoveryContextUsesInsertedActionsAndCorrectOptOutPosition() throws {
        let handler = ActionsHandler.forOptOut(Step(type: .optOut, actions: [original, ClickAction(id: "next", actionType: .click)]))
        _ = handler.nextAction()
        handler.insert(actions: [ClickAction(id: "inserted", actionType: .click)])
        _ = handler.nextAction()
        let context = try XCTUnwrap(handler.debugRecoveryStep())
        let step = try JSONDecoder().decode(Step.self, from: Data(context.json.utf8))
        XCTAssertEqual(step.type, .optOut)
        XCTAssertEqual(context.index, 1)
        XCTAssertEqual(step.actions.map(\.id), ["broken", "inserted", "next"])
        XCTAssertTrue(handler.replaceCurrentActionForDebugRecovery(ClickAction(id: "repaired", actionType: .click), expectedID: "inserted"))
        XCTAssertFalse(handler.replaceCurrentActionForDebugRecovery(original, expectedID: "inserted"))
        XCTAssertEqual(handler.nextAction()?.id, "next")
    }
}
#endif
