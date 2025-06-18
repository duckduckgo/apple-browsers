//
//  PendingRepliesActorTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
@testable import BrowserServicesKit

final class PendingRepliesActorTests: XCTestCase {
    var actor: PendingRepliesActor!

    override func setUp() {
        super.setUp()
        actor = PendingRepliesActor()
    }

    override func tearDown() {
        actor = nil
        super.tearDown()
    }

    func testWhenRegisteringAndSendingReply_ThenHandlerReceivesResponse() {
        let expected = "hello"
        let exp = expectation(description: #function)

        Task {
            await actor.register({ response in
                XCTAssertEqual(response, expected)
                exp.fulfill()
            }, for: "msg")
            await actor.send(response: expected, for: "msg")
        }

        waitForExpectations(timeout: 1.0)
    }

    func testWhenRegisteringMultipleTimes_ThenOnlyFirstHandlerIsCalledOnce() {
        let exp = expectation(description: #function)
        exp.expectedFulfillmentCount = 1

        Task {
            await actor.register({ _ in exp.fulfill() }, for: "once")
            await actor.send(response: "first", for: "once")
            // second send should not fire again
            await actor.send(response: "second", for: "once")
        }

        waitForExpectations(timeout: 1.0)
    }

    func testWhenRegisteringSecondHandlerForSameType_ThenFirstIsCancelled() {
        let cancelExp = expectation(description: #function)

        Task {
            // first handler should be cancelled when registering again
            await actor.register({ response in
                // decode NoActionResponse to verify .none action
                let data = response?.data(using: .utf8)
                let result = try? JSONDecoder().decode(AutofillUserScript.NoActionResponse.self,
                                                       from: data!)
                XCTAssertEqual(result?.success.action, AutofillUserScript.NoActionResponse.NoActionType.none)
                cancelExp.fulfill()
            }, for: "dup")

            await actor.register({ _ in
                XCTFail("Second handler should not run in this test")
            }, for: "dup")
        }

        waitForExpectations(timeout: 1.0)
    }

    func testWhenRegisteringTwoHandlersForSameType_ThenFirstIsCancelledAndSecondReceivesResponse() {
        let cancelExp = expectation(description: #function + "_cancel")
        let realExp   = expectation(description: #function + "_real")

        Task {
            // 1) First handler: should be cancelled by the next register call.
            await actor.register({ response in
                // decode NoActionResponse to verify .none action
                let data = response?.data(using: .utf8)
                let result = try? JSONDecoder().decode(AutofillUserScript.NoActionResponse.self, from: data!)
                XCTAssertEqual(result?.success.action, AutofillUserScript.NoActionResponse.NoActionType.none)
                cancelExp.fulfill()
            }, for: "dupType")

            // 2) Second handler: the one that should receive the real payload
            await actor.register({ response in
                XCTAssertEqual(response, "real")
                realExp.fulfill()
            }, for: "dupType")

            // 3) Send: only the second handler fires with “real”
            await actor.send(response: "real", for: "dupType")
        }

        wait(for: [cancelExp, realExp], timeout: 1.0)
    }

    func testWhenCancelAll_ThenAllHandlersAreCancelled() {
        let exp1 = expectation(description: #function + "_1")
        let exp2 = expectation(description: #function + "_2")

        Task {
            await actor.register({ _ in exp1.fulfill() }, for: "a")
            await actor.register({ _ in exp2.fulfill() }, for: "b")
            await actor.cancelAll()
        }

        waitForExpectations(timeout: 1.0)
    }
}
