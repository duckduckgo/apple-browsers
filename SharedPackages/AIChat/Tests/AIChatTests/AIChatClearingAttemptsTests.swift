//
//  AIChatClearingAttemptsTests.swift
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

import XCTest
@testable import AIChat

@MainActor
final class AIChatClearingAttemptsTests: XCTestCase {

    private enum TestError: Error, Equatable {
        case transient
        case permanent
    }

    private let attempts = AIChatClearingAttempts(retryDelay: 0, isTransient: { ($0 as? TestError) == .transient })

    private func run(_ results: [Result<Void, Error>]) async -> (AIChatClearingAttempts.Outcome, calls: Int) {
        var remaining = results
        var calls = 0
        let outcome = await attempts.run {
            calls += 1
            return remaining.removeFirst()
        }
        return (outcome, calls)
    }

    func testWhenFirstAttemptSucceedsThenItIsNotRetried() async {
        let (outcome, calls) = await run([.success(())])

        XCTAssertEqual(calls, 1)
        XCTAssertEqual(outcome.attempts, 1)
        XCTAssertNil(outcome.firstAttemptError)
        XCTAssertNoThrow(try outcome.result.get())
    }

    func testWhenFirstAttemptFailsTransientlyThenRetryResultIsReturned() async {
        let (outcome, calls) = await run([.failure(TestError.transient), .success(())])

        XCTAssertEqual(calls, 2)
        XCTAssertEqual(outcome.attempts, 2)
        XCTAssertEqual(outcome.firstAttemptError as? TestError, .transient)
        XCTAssertNoThrow(try outcome.result.get())
    }

    func testWhenFirstAttemptFailsPermanentlyThenItIsNotRetried() async {
        let (outcome, calls) = await run([.failure(TestError.permanent)])

        XCTAssertEqual(calls, 1)
        XCTAssertEqual(outcome.firstAttemptError as? TestError, .permanent)
        XCTAssertThrowsError(try outcome.result.get()) { XCTAssertEqual($0 as? TestError, .permanent) }
    }

    func testWhenRetryAlsoFailsThenItsErrorIsReturnedAndNoThirdAttemptIsMade() async {
        let (outcome, calls) = await run([.failure(TestError.transient), .failure(TestError.permanent)])

        XCTAssertEqual(calls, 2)
        XCTAssertEqual(outcome.firstAttemptError as? TestError, .transient)
        XCTAssertThrowsError(try outcome.result.get()) { XCTAssertEqual($0 as? TestError, .permanent) }
    }

    func testTransientErrorsAreTheOnesARetryCanFix() {
        typealias ClearError = AIChatDataClearingUserScript.ClearError
        let isTransient = WebViewAIChatJSDataCleaner.isTransient

        XCTAssertTrue(isTransient(ClearError.timeout))
        XCTAssertTrue(isTransient(ClearError.failedFromScript(.init(payload: [:]))))
        XCTAssertTrue(isTransient(ClearError.scriptNeverReady))
        XCTAssertTrue(isTransient(ClearError.navigationTimeout))
        XCTAssertTrue(isTransient(ClearError.webContentProcessTerminated))
        XCTAssertTrue(isTransient(NSError(domain: "WebKitErrorDomain", code: 102)))
        XCTAssertFalse(isTransient(ClearError.notReady))
        XCTAssertFalse(isTransient(WebViewAIChatJSDataCleaner.CleanerError.operationInProgress))
    }
}
