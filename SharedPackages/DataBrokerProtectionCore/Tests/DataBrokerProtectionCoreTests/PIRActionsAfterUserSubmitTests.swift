//
//  PIRActionsAfterUserSubmitTests.swift
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

#if os(macOS) && DEBUG
import XCTest
@testable import DataBrokerProtectionCore

final class PIRActionsAfterUserSubmitTests: XCTestCase {

    private func optOut(_ actions: [Action]) -> ActionsHandler {
        ActionsHandler.forOptOut(Step(type: .optOut, actions: actions))
    }

    func testWhenTheUserSubmitsDuringTheCaptcha_thenOnlyTheRemainingChecksRun() {
        let sut = optOut([FillFormAction(id: "fill", actionType: .fillForm, elements: []),
                          GetCaptchaInfoAction(id: "captcha", actionType: .getCaptchaInfo),
                          SolveCaptchaAction(id: "solve", actionType: .solveCaptcha),
                          ClickAction(id: "submit", actionType: .click),
                          ExpectationAction(id: "success", actionType: .expectation)])
        _ = sut.nextAction()
        _ = sut.nextAction()

        XCTAssertTrue(sut.keepOnlyRemainingExpectations())
        XCTAssertEqual(sut.nextAction()?.id, "success")
        XCTAssertNil(sut.nextAction())
    }

    func testWhenNoChecksRemain_thenThereIsNothingToConfirmTheSubmission() {
        let sut = optOut([GetCaptchaInfoAction(id: "captcha", actionType: .getCaptchaInfo),
                          ClickAction(id: "submit", actionType: .click)])
        _ = sut.nextAction()

        XCTAssertFalse(sut.keepOnlyRemainingExpectations())
        XCTAssertNil(sut.nextAction())
    }

    func testChecksAlreadyRunAreNotRunAgain() {
        let sut = optOut([ExpectationAction(id: "form-loaded", actionType: .expectation),
                          GetCaptchaInfoAction(id: "captcha", actionType: .getCaptchaInfo),
                          ExpectationAction(id: "success", actionType: .expectation)])
        _ = sut.nextAction()
        _ = sut.nextAction()

        XCTAssertTrue(sut.keepOnlyRemainingExpectations())
        XCTAssertEqual(sut.nextAction()?.id, "success")
    }

    func testBeforeTheSubmitClick_thenTheFinalCheckRunsFirst() throws {
        let sut = optOut([GetCaptchaInfoAction(id: "captcha", actionType: .getCaptchaInfo),
                          ClickAction(id: "submit", actionType: .click),
                          ExpectationAction(id: "sent", actionType: .expectation),
                          ExpectationAction(id: "success", actionType: .expectation)])
        _ = sut.nextAction()
        let submit = try XCTUnwrap(sut.nextAction())

        XCTAssertEqual(sut.submissionCheck(before: submit)?.id, "success")
    }

    func testTheCheckLooksAtThePageOnce() throws {
        let success = ExpectationAction(id: "success", actionType: .expectation,
                                        json: Data(#"{"id":"success","actionType":"expectation","expectations":[]}"#.utf8))
        let sut = optOut([GetCaptchaInfoAction(id: "captcha", actionType: .getCaptchaInfo),
                          ClickAction(id: "submit", actionType: .click), success])
        _ = sut.nextAction()
        let submit = try XCTUnwrap(sut.nextAction())

        let check = try XCTUnwrap(sut.submissionCheck(before: submit)?.json)
        let retry = try XCTUnwrap((JSONSerialization.jsonObject(with: check) as? [String: Any])?["retry"] as? [String: Any])
        XCTAssertEqual(retry["environment"] as? String, "web")
        XCTAssertEqual(retry["maxAttempts"] as? Int, 1)
    }

    func testOnlyClicksAndFillsWaitForTheCheck() throws {
        let sut = optOut([ExpectationAction(id: "loaded", actionType: .expectation),
                          ExpectationAction(id: "success", actionType: .expectation)])
        let loaded = try XCTUnwrap(sut.nextAction())

        XCTAssertNil(sut.submissionCheck(before: loaded))
    }

    func testScansAreNeverChecked() throws {
        let sut = ActionsHandler.forScan(Step(type: .scan, actions: [ClickAction(id: "search", actionType: .click),
                                                                     ExpectationAction(id: "results", actionType: .expectation)]))
        let search = try XCTUnwrap(sut.nextAction())

        XCTAssertNil(sut.submissionCheck(before: search))
    }
}
#endif
