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

    @MainActor
    func testWhenRegisteringAndSendingReply_ThenHandlerReceivesResponse() async {
        var captured: String?
        await actor.register({ captured = $0 }, for: "msg")
        await actor.send(response: "hello", for: "msg")
        // Because both register/send schedule their callbacks via `await MainActor.run`,
        // and our test is already on MainActor, by this point `captured` is set.
        XCTAssertEqual(captured, "hello")
    }

    /// Sending to a key with no handlers should do nothing.
    @MainActor
    func testWhenSendingWithoutRegistering_ThenNothingHappens() async {
        // nothing should throw or change state
        await actor.send(response: "ignored", for: "no-msg")
        // no assertion needed—if it crashes, the test fails
    }

    /// If you send twice after a single register, only the first should fire.
    @MainActor
    func testWhenRegisteringMultipleTimes_ThenOnlyFirstHandlerIsCalledOnce() async {
        var count = 0
        await actor.register({ _ in count += 1 }, for: "once")
        await actor.send(response: "first", for: "once")
        await actor.send(response: "second", for: "once")
        XCTAssertEqual(count, 1)
    }

    @MainActor
    func testWhenRegisteringSecondHandlerForSameType_ThenFirstIsCancelled() async {
        var cancelledAction: AutofillUserScript.NoActionResponse.NoActionType?
        // first handler
        await actor.register({ response in
            let data = response!.data(using: .utf8)!
            let noAction = try! JSONDecoder().decode(AutofillUserScript.NoActionResponse.self, from: data)
            cancelledAction = noAction.success.action
        }, for: "dup")

        // register second handler (cancels the first now)
        await actor.register({ _ in
            XCTFail("Second handler shouldn’t run here")
        }, for: "dup")

        XCTAssertEqual(cancelledAction, AutofillUserScript.NoActionResponse.NoActionType.none)
    }

    @MainActor
    func testWhenRegisteringTwoHandlersForSameType_ThenSecondReceivesRealResponse() async {
        var cancelledAction: AutofillUserScript.NoActionResponse.NoActionType?
        var realResponse: String?

        // first handler (canceled)
        await actor.register({ response in
            let data = response!.data(using: .utf8)!
            let noAction = try! JSONDecoder()
                    .decode(AutofillUserScript.NoActionResponse.self, from: data)
            cancelledAction = noAction.success.action
        }, for: "dupType")

        // second handler (should get “real”)
        await actor.register({ realResponse = $0 }, for: "dupType")

        // now send real
        await actor.send(response: "real", for: "dupType")

        XCTAssertEqual(cancelledAction, AutofillUserScript.NoActionResponse.NoActionType.none)
        XCTAssertEqual(realResponse, "real")
    }

    @MainActor
    func testWhenCancelAll_ThenAllHandlersAreCancelled() async {
        var aCancelled = false
        var bCancelled = false

        await actor.register({ _ in aCancelled = true }, for: "a")
        await actor.register({ _ in bCancelled = true }, for: "b")

        await actor.cancelAll()

        XCTAssertTrue(aCancelled)
        XCTAssertTrue(bCancelled)
    }

    @MainActor
    func testWhenReusingActor_ThenSupportsMultipleCycles() async {
        var first: String?
        var second: String?

        // first cycle
        await actor.register({ first = $0 }, for: "cycle")
        await actor.send(response: "one", for: "cycle")
        XCTAssertEqual(first, "one")

        // second cycle
        await actor.register({ second = $0 }, for: "cycle")
        await actor.send(response: "two", for: "cycle")
        XCTAssertEqual(second, "two")
    }

    @MainActor
    func testWhenUsingDifferentTypes_ThenTheyDoNotInterfere() async {
        var foo: String?
        var bar: String?

        await actor.register({ foo = $0 }, for: "foo")
        await actor.register({ bar = $0 }, for: "bar")
        await actor.send(response: "F", for: "foo")
        await actor.send(response: "B", for: "bar")

        XCTAssertEqual(foo, "F")
        XCTAssertEqual(bar, "B")
    }
}
