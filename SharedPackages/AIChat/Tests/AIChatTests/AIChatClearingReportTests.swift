//
//  AIChatClearingReportTests.swift
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

final class AIChatClearingReportTests: XCTestCase {

    private func report(attempts: Int, firstAttemptError: Error?) -> AIChatClearingReport {
        AIChatClearingReport(attempts: attempts, firstAttemptError: firstAttemptError, firstAttemptTimings: AIChatClearingTimings())
    }

    func testWhenNotRetriedThenThereIsNoRetriedErrorCode() {
        let report = report(attempts: 1, firstAttemptError: AIChatDataClearingUserScript.ClearError.notReady)

        XCTAssertNil(report.retriedErrorCode)
    }

    func testWhenRetriedAfterAClearingErrorThenItsCodeIsReported() {
        let report = report(attempts: 2, firstAttemptError: AIChatDataClearingUserScript.ClearError.navigationTimeout)

        XCTAssertEqual(report.retriedErrorCode, 5)
    }

    func testWhenRetriedAfterAPageLoadErrorThenThePageLoadFailedCodeIsReported() {
        let report = report(attempts: 2, firstAttemptError: NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet))

        XCTAssertEqual(report.retriedErrorCode, AIChatClearingReport.pageLoadFailedCode)
    }
}
