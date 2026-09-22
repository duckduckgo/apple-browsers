//
//  AIChatElicitationCoordinatorTests.swift
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

/// Correlation between a pushed prompt and the answer that resolves it.
@MainActor
final class AIChatElicitationCoordinatorTests: XCTestCase {

    private var coordinator: AIChatElicitationCoordinator!
    private var pusher: RecordingPusher!

    override func setUp() {
        super.setUp()
        coordinator = AIChatElicitationCoordinator(timeout: 5, makeID: Self.sequentialID())
        pusher = RecordingPusher()
    }

    override func tearDown() {
        coordinator = nil
        pusher = nil
        super.tearDown()
    }

    func testWhenElicitingThenThePushedParamsCarryTheIdModeMessageAndSchema() async throws {
        let task = elicit(toolName: "alpha", message: "Duck.ai wants alpha.")
        try await waitForPending(count: 1)

        let params = try XCTUnwrap(pusher.pushed.first)
        XCTAssertEqual(params.id, "id-1")
        XCTAssertEqual(params.mode, "form")
        XCTAssertEqual(params.message, "Duck.ai wants alpha.")
        XCTAssertEqual(params.requestedSchema, BrowserToolPermissionElicitation.choiceSchema)

        coordinator.complete(id: "id-1", result: .cancel)
        _ = await task.value
    }

    func testWhenAnswerArrivesThenElicitResolvesWithIt() async throws {
        let task = elicit()
        try await waitForPending(count: 1)
        let answer = MCPElicitationResult(action: .accept, content: ["choice": "allowOnce"])

        XCTAssertTrue(coordinator.complete(id: "id-1", result: answer))

        let result = await task.value
        XCTAssertEqual(result, answer)
    }

    func testWhenPromptIsAnsweredThenItIsNoLongerPending() async throws {
        let task = elicit()
        try await waitForPending(count: 1)

        coordinator.complete(id: "id-1", result: .cancel)
        _ = await task.value

        XCTAssertTrue(coordinator.pendingPrompts.isEmpty)
        XCTAssertFalse(coordinator.complete(id: "id-1", result: .cancel))
    }

    func testWhenIdIsUnknownThenCompleteReturnsFalse() {
        XCTAssertFalse(coordinator.complete(id: "never-issued", result: .cancel))
    }

    func testWhenPendingThenThePromptIsListedWithItsToolAndOwner() async throws {
        let task = elicit(toolName: "alpha", message: "Duck.ai wants alpha.", ownerTabID: "tab-9")
        try await waitForPending(count: 1)

        XCTAssertEqual(coordinator.pendingPrompts,
                       [PendingElicitation(id: "id-1", ownerTabID: "tab-9", toolName: "alpha", message: "Duck.ai wants alpha.")])

        coordinator.complete(id: "id-1", result: .cancel)
        _ = await task.value
    }

    func testWhenPushFailsThenElicitResolvesAsCancelAndNothingStaysPending() async {
        pusher.deliver = false

        let result = await coordinator.elicit(toolName: "alpha",
                                              message: "m",
                                              requestedSchema: [:],
                                              ownerTabID: "tab",
                                              pusher: pusher)

        XCTAssertEqual(result, .cancel)
        XCTAssertEqual(pusher.pushed.count, 1)
        XCTAssertTrue(coordinator.pendingPrompts.isEmpty)
    }

    func testWhenThereIsNoPusherThenElicitResolvesAsCancelWithoutPushing() async {
        let result = await coordinator.elicit(toolName: "alpha",
                                              message: "m",
                                              requestedSchema: [:],
                                              ownerTabID: "tab",
                                              pusher: nil)

        XCTAssertEqual(result, .cancel)
        XCTAssertTrue(coordinator.pendingPrompts.isEmpty)
    }

    func testWhenNoAnswerArrivesBeforeTheTimeoutThenElicitResolvesAsCancel() async {
        coordinator = AIChatElicitationCoordinator(timeout: 0.05, makeID: Self.sequentialID())

        let result = await elicit().value

        XCTAssertEqual(result, .cancel)
        XCTAssertTrue(coordinator.pendingPrompts.isEmpty)
    }

    func testWhenTwoPromptsArePendingThenEachResolvesWithItsOwnAnswer() async throws {
        let first = elicit(toolName: "alpha")
        let second = elicit(toolName: "beta")
        try await waitForPending(count: 2)

        coordinator.complete(id: "id-2", result: .decline)
        coordinator.complete(id: "id-1", result: MCPElicitationResult(action: .accept, content: ["choice": "neverAllow"]))

        let firstResult = await first.value
        let secondResult = await second.value
        XCTAssertEqual(firstResult, MCPElicitationResult(action: .accept, content: ["choice": "neverAllow"]))
        XCTAssertEqual(secondResult, .decline)
    }

    // MARK: -

    private func elicit(toolName: String = "alpha",
                        message: String = "m",
                        ownerTabID: String = "tab") -> Task<MCPElicitationResult, Never> {
        let coordinator = coordinator!
        let pusher = pusher!
        return Task {
            await coordinator.elicit(toolName: toolName,
                                     message: message,
                                     requestedSchema: BrowserToolPermissionElicitation.choiceSchema,
                                     ownerTabID: ownerTabID,
                                     pusher: pusher)
        }
    }

    private func waitForPending(count: Int) async throws {
        for _ in 0..<200 where coordinator.pendingPrompts.count < count {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(coordinator.pendingPrompts.count, count)
    }

    private static func sequentialID() -> () -> String {
        var next = 0
        return {
            next += 1
            return "id-\(next)"
        }
    }
}

private final class RecordingPusher: AIChatElicitationPushing {
    var deliver = true
    private(set) var pushed: [MCPElicitationCreateParams] = []

    func pushElicitationCreate(_ params: MCPElicitationCreateParams) -> Bool {
        pushed.append(params)
        return deliver
    }
}

private extension MCPElicitationResult {
    static let decline = MCPElicitationResult(action: .decline)
}
