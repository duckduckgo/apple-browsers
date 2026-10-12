//
//  AIChatDataClearingUserScriptTests.swift
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
@testable import AIChat

@MainActor
final class AIChatDataClearingUserScriptTests: XCTestCase {

    private typealias ClearError = AIChatDataClearingUserScript.ClearError
    private typealias ScriptFailure = AIChatDataClearingUserScript.ScriptFailure

    private var script: AIChatDataClearingUserScript!

    override func setUp() {
        super.setUp()
        script = AIChatDataClearingUserScript()
    }

    override func tearDown() {
        script = nil
        super.tearDown()
    }

    private func receiveReady() async {
        _ = try? await script.handler(forMethodNamed: AIChatDataClearingUserScript.MessageName.duckAiClearDataReady.rawValue)?([:], WKScriptMessage.mock())
    }

    // MARK: - Readiness

    func testWhenScriptWasReadyBeforeWaitingThenWaitSucceeds() async {
        await receiveReady()

        let result = await script.waitUntilReady(timeout: 5)

        XCTAssertNoThrow(try result.get())
    }

    func testWhenScriptBecomesReadyWhileWaitingThenWaitSucceeds() async {
        Task { @MainActor in await receiveReady() }

        let result = await script.waitUntilReady(timeout: 5)

        XCTAssertNoThrow(try result.get())
    }

    func testWhenScriptNeverBecomesReadyThenWaitFailsWithScriptNeverReady() async {
        let result = await script.waitUntilReady(timeout: 0.05)

        XCTAssertThrowsError(try result.get()) { XCTAssertEqual($0 as? ClearError, .scriptNeverReady) }
    }

    func testWhenANewPageLoadStartsThenEarlierReadinessIsForgotten() async {
        await receiveReady()
        script.prepareForPageLoad()

        let result = await script.waitUntilReady(timeout: 0.05)

        XCTAssertThrowsError(try result.get()) { XCTAssertEqual($0 as? ClearError, .scriptNeverReady) }
    }

    func testWhenPageIsGoneWhileWaitingForReadyThenWaitFailsImmediately() async {
        Task { @MainActor in script.failPendingWaits(with: .webContentProcessTerminated) }

        let result = await script.waitUntilReady(timeout: 5)

        XCTAssertThrowsError(try result.get()) { XCTAssertEqual($0 as? ClearError, .webContentProcessTerminated) }
    }

    // MARK: - Script failure payload

    func testWhenPayloadHasStageAndErrorNameThenFailureCodeCombinesThem() {
        XCTAssertEqual(ScriptFailure(payload: ["stage": "indexedDB", "errorName": "UnknownError", "error": "Internal"]).errorCode, 201)
        XCTAssertEqual(ScriptFailure(payload: ["stage": "localStorage", "errorName": "SecurityError"]).errorCode, 109)
        XCTAssertEqual(ScriptFailure(payload: ["stage": "unexpected", "errorName": "TypeError"]).errorCode, 310)
    }

    func testWhenErrorNameIsUnrecognizedThenOnlyStageIsKept() {
        XCTAssertEqual(ScriptFailure(payload: ["stage": "indexedDB", "errorName": "SomethingNew"]).errorCode, 200)
    }

    func testWhenPayloadIsFromAScriptWithoutStageOrNameThenCodeIsZero() {
        XCTAssertEqual(ScriptFailure(payload: ["error": "[object Event]"]).errorCode, 0)
        XCTAssertEqual(ScriptFailure(payload: "unexpected").errorCode, 0)
    }

    func testWhenScriptFailsThenErrorKeepsItsCodeAndCarriesTheScriptFailure() {
        let failure = ScriptFailure(payload: ["stage": "indexedDB", "errorName": "QuotaExceededError"])
        let error = ClearError.failedFromScript(failure)

        XCTAssertEqual(error.errorCode, 3)
        XCTAssertEqual(error.underlyingError as? ScriptFailure, failure)
    }
}
