//
//  PIRAssistTests.swift
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
import WebKit
import XCTest
@testable import DataBrokerProtectionCore

@MainActor
final class PIRAssistSessionDetailTests: XCTestCase {

    private func session(currentIndex: Int, turn: PIRAssistUserTurnKind?) -> PIRAssistSession {
        let session = PIRAssistSession(id: PIRAssistItemID(brokerId: 1, profileQueryId: 1, extractedProfileId: 1),
                                       brokerName: "Glad I Know", brokerURL: "gladiknow.com", webView: WKWebView())
        session.update(checklist: PIRAssistChecklist(items: ["Open the form", "Entering your name", "Submit request"],
                                                     currentIndex: currentIndex))
        session.setUserTurn(turn)
        return session
    }

    func testWhileRunning_thenTheDetailIsTheCurrentStep() {
        XCTAssertEqual(session(currentIndex: 1, turn: nil).needsYouDetail, "Step 2 of 3 \u{00B7} Entering your name")
    }

    func testDuringTheUsersTurn_thenTheDetailSaysWhatToDo() {
        XCTAssertEqual(session(currentIndex: 1, turn: .recaptcha).needsYouDetail, "Check \u{201C}I\u{2019}m not a robot\u{201D} to continue")
        XCTAssertEqual(session(currentIndex: 1, turn: .turnstile).needsYouDetail, "Complete the security check to continue")
    }
}

final class PIRAssistChecklistTests: XCTestCase {

    private let checklist = PIRAssistChecklist(items: ["Open the form", "Entering your name",
                                                                       PIRAssistChecklist.proveHumanLabel, "Submit request"],
                                               currentIndex: 1)

    func testWhileAutomationRuns_thenTheCurrentStepRunsAndTheChallengeIsFlaggedAhead() {
        XCTAssertEqual(checklist.steps(userTurn: nil).map(\.state), [.done, .running, .needsUserLater, .upcoming])
    }

    func testDuringTheUsersTurn_thenTheCurrentStepIsTheirs() {
        XCTAssertEqual(checklist.steps(userTurn: .turnstile).map(\.state), [.done, .userTurn, .needsUserLater, .upcoming])
    }
}
#endif
