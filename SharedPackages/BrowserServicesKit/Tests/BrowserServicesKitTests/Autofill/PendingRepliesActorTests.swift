//
//  PendingRepliesActorTests.swift
//  BrowserServicesKit
//
//  Created by Anya Mallon on 18/06/2025.
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

    func testWhenRegisteringTwoHandlersForSameType_ThenSecondReceivesResponse() {
        let realExp = expectation(description: #function)

        Task {
            // 1) register handler1 (it will be cancelled by the next registration)
            await actor.register({ _ in
                XCTFail("First handler should have been cancelled")
            }, for: "dupType")

            // 2) register handler2
            await actor.register({ response in
                XCTAssertEqual(response, "real")
                realExp.fulfill()
            }, for: "dupType")

            // 3) send: only handler2 should fire
            await actor.send(response: "real", for: "dupType")
        }

        waitForExpectations(timeout: 1.0)
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
