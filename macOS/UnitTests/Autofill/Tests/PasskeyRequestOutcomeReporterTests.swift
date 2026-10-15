//
//  PasskeyRequestOutcomeReporterTests.swift
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

import AuthenticationServices
@_spi(Testing) import PixelKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class PasskeyRequestOutcomeReporterTests: XCTestCase {

    private let delay: TimeInterval = 0.05
    private var pixelFiring: PixelKitMock!
    private var reporter: PasskeyRequestOutcomeReporter!

    override func setUp() {
        super.setUp()
        makeReporter()
    }

    private func makeReporter() {
        pixelFiring = PixelKitMock()
        reporter = PasskeyRequestOutcomeReporter(pixelFiring: pixelFiring, failureDelay: delay)
    }

    override func tearDown() {
        reporter = nil
        pixelFiring = nil
        super.tearDown()
    }

    private func outcome(_ result: PasskeyRequestOutcome.Result, style: PasskeyRequestOutcome.Style = .modal) -> PasskeyRequestOutcome {
        PasskeyRequestOutcome(style: style, type: .get, result: result, duration: .under1s)
    }

    private func waitPastDelay() {
        let expectation = expectation(description: "delay passed")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay * 3) { expectation.fulfill() }
        wait(for: [expectation], timeout: 1)
    }

    private let activeUserPixelName = "passkey_active_user_macos"

    /// Fired pixels other than the active user one.
    private var outcomeFireCalls: [ExpectedFireCall] {
        pixelFiring.actualFireCalls.filter { $0.pixel.name != activeUserPixelName }
    }

    private var firedPixels: [String] {
        outcomeFireCalls.map { $0.pixel.name }
    }

    private var activeUserFireCalls: [ExpectedFireCall] {
        pixelFiring.actualFireCalls.filter { $0.pixel.name == activeUserPixelName }
    }

    // MARK: - Firing

    func test_success_firesRightAway() {
        reporter.report(outcome(.success))

        XCTAssertEqual(outcomeFireCalls, [
            ExpectedFireCall(pixel: PasskeyRequestOutcomePixel(outcome(.success)), frequency: .dailyAndCount)
        ])
    }

    func test_cancellation_firesRightAway() {
        reporter.report(outcome(.canceled))

        XCTAssertEqual(outcomeFireCalls, [
            ExpectedFireCall(pixel: PasskeyRequestOutcomePixel(outcome(.canceled)), frequency: .dailyAndCount)
        ])
    }

    func test_failure_firesAfterDelay() {
        reporter.report(outcome(.failure(.failed)))
        XCTAssertTrue(outcomeFireCalls.isEmpty)

        waitPastDelay()

        XCTAssertEqual(outcomeFireCalls, [
            ExpectedFireCall(pixel: PasskeyRequestOutcomePixel(outcome(.failure(.failed))), frequency: .dailyAndCount)
        ])
    }

    func test_failures_inQuickSuccession_fireOnlyTheLast() {
        reporter.report(outcome(.failure(.failed), style: .autofill))
        reporter.report(outcome(.failure(.requestInProgress)))

        waitPastDelay()

        XCTAssertEqual(outcomeFireCalls, [
            ExpectedFireCall(pixel: PasskeyRequestOutcomePixel(outcome(.failure(.requestInProgress))), frequency: .dailyAndCount)
        ])
    }

    func test_success_afterFailure_dropsTheFailure() {
        reporter.report(outcome(.failure(.failed)))
        reporter.report(outcome(.success))

        waitPastDelay()

        XCTAssertEqual(firedPixels, ["passkey_request_success_macos"])
    }

    func test_cancellation_afterFailure_dropsTheFailure() {
        reporter.report(outcome(.failure(.failed)))
        reporter.report(outcome(.canceled))

        waitPastDelay()

        XCTAssertEqual(firedPixels, ["passkey_request_cancel_macos"])
    }

    func test_failure_afterDelayPassed_firesAgain() {
        reporter.report(outcome(.failure(.failed)))
        waitPastDelay()
        reporter.report(outcome(.failure(.failed)))
        waitPastDelay()

        XCTAssertEqual(firedPixels, ["passkey_request_failure_macos", "passkey_request_failure_macos"])
    }

    // MARK: - Active users

    func test_activeUser_firesDaily_forSuccessesAndShownSheets() {
        let outcomes: [PasskeyRequestOutcome] = [
            outcome(.success),
            outcome(.success, style: .autofill),
            outcome(.canceled),
            outcome(.failure(.failed))
        ]

        for activeUse in outcomes {
            makeReporter()
            reporter.report(activeUse)

            XCTAssertEqual(activeUserFireCalls, [ExpectedFireCall(pixel: PasskeyActiveUserPixel(), frequency: .daily)], "\(activeUse)")
        }
    }

    func test_activeUser_doesNotFire_withoutPasskeyUseOrSheet() {
        let outcomes: [PasskeyRequestOutcome] = [
            outcome(.canceled, style: .autofill),
            outcome(.failure(.failed), style: .autofill),
            outcome(.failure(.requestInProgress)),
            outcome(.failure(.requestInProgress), style: .autofill),
            outcome(.canceled, style: .unknown)
        ]

        for outcome in outcomes {
            makeReporter()
            reporter.report(outcome)
            waitPastDelay()

            XCTAssertTrue(activeUserFireCalls.isEmpty, "\(outcome)")
        }
    }

    // MARK: - Parameters

    func test_successAndCancellationParameters_haveNoError() {
        XCTAssertEqual(PasskeyRequestOutcomePixel(outcome(.success)).parameters, ["style": "modal", "type": "get", "duration": "under1s"])
        XCTAssertEqual(PasskeyRequestOutcomePixel(outcome(.canceled)).parameters, ["style": "modal", "type": "get", "duration": "under1s"])
    }

    func test_failureParameters_includeError() {
        let pixel = PasskeyRequestOutcomePixel(outcome(.failure(.other(code: 1006)), style: .autofill))

        XCTAssertEqual(pixel.parameters, ["style": "autofill", "type": "get", "duration": "under1s", "error": "other_1006"])
    }

    // MARK: - Results

    func test_result_noError_isSuccess() {
        XCTAssertEqual(PasskeyRequestOutcome.Result(error: nil), .success)
    }

    func test_result_canceled_isCanceled() {
        let error = NSError(domain: ASAuthorizationError.errorDomain, code: ASAuthorizationError.canceled.rawValue)

        XCTAssertEqual(PasskeyRequestOutcome.Result(error: error), .canceled)
    }

    func test_result_failedWithRequestInProgressReason_isRequestInProgress() {
        let error = NSError(domain: ASAuthorizationError.errorDomain,
                            code: ASAuthorizationError.failed.rawValue,
                            userInfo: [NSLocalizedFailureReasonErrorKey: "Request already in progress for specified application identifier."])

        XCTAssertEqual(PasskeyRequestOutcome.Result(error: error), .failure(.requestInProgress))
    }

    func test_result_failedWithOtherReason_isFailed() {
        let error = NSError(domain: ASAuthorizationError.errorDomain,
                            code: ASAuthorizationError.failed.rawValue,
                            userInfo: [NSLocalizedFailureReasonErrorKey: "Something else."])

        XCTAssertEqual(PasskeyRequestOutcome.Result(error: error), .failure(.failed))
    }

    func test_result_otherCodeOrDomain_isOtherFailure() {
        XCTAssertEqual(PasskeyRequestOutcome.Result(error: NSError(domain: ASAuthorizationError.errorDomain, code: 1006)), .failure(.other(code: 1006)))
        XCTAssertEqual(PasskeyRequestOutcome.Result(error: NSError(domain: "SomeDomain", code: 7)), .failure(.other(code: 7)))
    }

    func test_duration_buckets() {
        XCTAssertEqual(PasskeyRequestOutcome.Duration(0.003), .under100ms)
        XCTAssertEqual(PasskeyRequestOutcome.Duration(0.28), .under1s)
        XCTAssertEqual(PasskeyRequestOutcome.Duration(5), .under10s)
        XCTAssertEqual(PasskeyRequestOutcome.Duration(30), .under1m)
        XCTAssertEqual(PasskeyRequestOutcome.Duration(90), .over1m)
    }
}
