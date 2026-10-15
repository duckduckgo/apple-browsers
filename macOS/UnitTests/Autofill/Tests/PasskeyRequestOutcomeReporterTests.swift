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

@MainActor
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
        PasskeyRequestOutcome(style: style, type: .get, result: result)
    }

    private let failedError = NSError(domain: ASAuthorizationError.errorDomain, code: ASAuthorizationError.failed.rawValue)

    private let requestInProgressError = NSError(domain: ASAuthorizationError.errorDomain,
                                                 code: ASAuthorizationError.failed.rawValue,
                                                 userInfo: [NSLocalizedFailureReasonErrorKey: "Request already in progress for specified application identifier."])

    private func waitPastDelay() {
        let expectation = expectation(description: "delay passed")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay * 3) { expectation.fulfill() }
        wait(for: [expectation], timeout: 1)
    }

    private let activeUserPixelName = "passkey_active_user_macos"
    private let stuckPixelName = "passkey_stuck_macos"

    /// Fired pixels other than the active user and stuck ones.
    private var outcomeFireCalls: [ExpectedFireCall] {
        pixelFiring.actualFireCalls.filter { ![activeUserPixelName, stuckPixelName].contains($0.pixel.name) }
    }

    private var stuckFireCalls: [ExpectedFireCall] {
        pixelFiring.actualFireCalls.filter { $0.pixel.name == stuckPixelName }
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
        reporter.report(outcome(.failure(failedError)))
        XCTAssertTrue(outcomeFireCalls.isEmpty)

        waitPastDelay()

        XCTAssertEqual(outcomeFireCalls, [
            ExpectedFireCall(pixel: PasskeyRequestOutcomePixel(outcome(.failure(failedError))), frequency: .dailyAndCount)
        ])
    }

    func test_failures_inQuickSuccession_fireOnlyTheLast() {
        reporter.report(outcome(.failure(failedError), style: .autofill))
        reporter.report(outcome(.failure(requestInProgressError)))

        waitPastDelay()

        XCTAssertEqual(outcomeFireCalls, [
            ExpectedFireCall(pixel: PasskeyRequestOutcomePixel(outcome(.failure(requestInProgressError))), frequency: .dailyAndCount)
        ])
    }

    func test_success_afterFailure_dropsTheFailure() {
        reporter.report(outcome(.failure(failedError)))
        reporter.report(outcome(.success))

        waitPastDelay()

        XCTAssertEqual(firedPixels, ["passkey_request_success_macos"])
    }

    func test_cancellation_afterFailure_dropsTheFailure() {
        reporter.report(outcome(.failure(failedError)))
        reporter.report(outcome(.canceled))

        waitPastDelay()

        XCTAssertEqual(firedPixels, ["passkey_request_cancel_macos"])
    }

    func test_failure_afterDelayPassed_firesAgain() {
        reporter.report(outcome(.failure(failedError)))
        waitPastDelay()
        reporter.report(outcome(.failure(failedError)))
        waitPastDelay()

        XCTAssertEqual(firedPixels, ["passkey_request_failure_macos", "passkey_request_failure_macos"])
    }

    // MARK: - Active users

    func test_activeUser_firesDaily_forSuccessesAndShownSheets() {
        let outcomes: [PasskeyRequestOutcome] = [
            outcome(.success),
            outcome(.success, style: .autofill),
            outcome(.canceled),
            outcome(.failure(failedError))
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
            outcome(.failure(failedError), style: .autofill),
            outcome(.failure(requestInProgressError)),
            outcome(.failure(requestInProgressError), style: .autofill),
            outcome(.canceled, style: .unknown)
        ]

        for outcome in outcomes {
            makeReporter()
            reporter.report(outcome)
            waitPastDelay()

            XCTAssertTrue(activeUserFireCalls.isEmpty, "\(outcome)")
        }
    }

    // MARK: - Stuck

    func test_stuck_firesRightAway_forRefusedSheet() {
        reporter.report(outcome(.failure(requestInProgressError)))

        XCTAssertEqual(stuckFireCalls, [ExpectedFireCall(pixel: PasskeyStuckPixel(), frequency: .dailyAndCount)])
    }

    func test_stuck_doesNotFire_forOtherOutcomes() {
        let outcomes: [PasskeyRequestOutcome] = [
            outcome(.failure(requestInProgressError), style: .autofill),
            outcome(.failure(failedError)),
            outcome(.canceled),
            outcome(.success)
        ]

        for outcome in outcomes {
            makeReporter()
            reporter.report(outcome)
            waitPastDelay()

            XCTAssertTrue(stuckFireCalls.isEmpty, "\(outcome)")
        }
    }

    // MARK: - Parameters

    func test_successAndCancellationParameters_haveNoError() {
        XCTAssertEqual(PasskeyRequestOutcomePixel(outcome(.success)).parameters, ["style": "modal", "type": "get", "petal": "randomize"])
        XCTAssertEqual(PasskeyRequestOutcomePixel(outcome(.canceled)).parameters, ["style": "modal", "type": "get", "petal": "randomize"])
    }

    func test_failure_carriesError() {
        XCTAssertEqual(PasskeyRequestOutcomePixel(outcome(.failure(failedError), style: .autofill)).parameters, ["style": "autofill", "type": "get", "petal": "randomize"])
        XCTAssertEqual(PasskeyRequestOutcomePixel(outcome(.failure(failedError))).error, failedError)
        XCTAssertNil(PasskeyRequestOutcomePixel(outcome(.success)).error)
    }

    // MARK: - Results

    func test_result_noError_isSuccess() {
        XCTAssertEqual(PasskeyRequestOutcome.Result(error: nil), .success)
    }

    func test_result_canceled_isCanceled() {
        let error = NSError(domain: ASAuthorizationError.errorDomain, code: ASAuthorizationError.canceled.rawValue)

        XCTAssertEqual(PasskeyRequestOutcome.Result(error: error), .canceled)
    }

    func test_result_otherError_isFailure() {
        let error = NSError(domain: "SomeDomain", code: ASAuthorizationError.canceled.rawValue)

        XCTAssertEqual(PasskeyRequestOutcome.Result(error: error), .failure(error))
    }

    func test_requestInProgress_isToldByFailureReason() {
        XCTAssertTrue(requestInProgressError.isPasskeyRequestInProgress)
        XCTAssertFalse(failedError.isPasskeyRequestInProgress)
    }
}
