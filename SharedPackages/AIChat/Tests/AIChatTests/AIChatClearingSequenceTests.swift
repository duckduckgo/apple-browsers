//
//  AIChatClearingSequenceTests.swift
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
final class AIChatClearingSequenceTests: XCTestCase {

    private enum TestError: Error, Equatable {
        case loadFailed(String)
        case clearFailed(String)
    }

    private let first = URL(string: "https://first.example")!
    private let second = URL(string: "https://second.example")!

    /// Records every step in order, e.g. `load first.example`, `clear first.example all`, `clear first.example chat1`.
    private var steps: [String] = []
    private var currentOrigin: String?
    private var failingLoads: Set<String> = []
    private var failingClears: Set<String> = []
    private var failuresRequireReload = true

    override func setUp() {
        super.setUp()
        steps = []
        currentOrigin = nil
        failingLoads = []
        failingClears = []
        failuresRequireReload = true
    }

    private func makeSequence() -> AIChatClearingSequence {
        AIChatClearingSequence(
            origins: [first, second],
            loadOrigin: { [unowned self] origin in
                let host = origin.host ?? ""
                steps.append("load \(host)")
                currentOrigin = host
                return failingLoads.contains(host) ? .failure(TestError.loadFailed(host)) : .success(())
            },
            clear: { [unowned self] chatID in
                let step = "\(currentOrigin ?? "") \(chatID ?? "all")"
                steps.append("clear \(step)")
                return failingClears.contains(step) ? .failure(TestError.clearFailed(step)) : .success(())
            },
            requiresReload: { [unowned self] _ in failuresRequireReload }
        )
    }

    func testWhenEverythingSucceedsThenEveryOriginIsClearedAndResultIsSuccess() async {
        let result = await makeSequence().run(chatIDs: nil)

        XCTAssertNoThrow(try result.get())
        XCTAssertEqual(steps, ["load first.example", "clear first.example all",
                               "load second.example", "clear second.example all"])
    }

    func testWhenFirstOriginFailsToLoadThenSecondOriginIsStillCleared() async {
        failingLoads = ["first.example"]

        let result = await makeSequence().run(chatIDs: nil)

        XCTAssertEqual(steps, ["load first.example",
                               "load second.example", "clear second.example all"])
        XCTAssertThrowsError(try result.get()) { XCTAssertEqual($0 as? TestError, .loadFailed("first.example")) }
    }

    func testWhenClearingEveryOriginFailsThenEachIsAttemptedAndTheFirstErrorIsReturned() async {
        failingClears = ["first.example all", "second.example all"]

        let result = await makeSequence().run(chatIDs: nil)

        XCTAssertEqual(steps, ["load first.example", "clear first.example all",
                               "load second.example", "clear second.example all"])
        XCTAssertThrowsError(try result.get()) { XCTAssertEqual($0 as? TestError, .clearFailed("first.example all")) }
    }

    func testWhenChatFailureRequiresReloadThenOriginIsReloadedAndRemainingChatsAreStillCleared() async {
        failingClears = ["first.example chat1"]

        let result = await makeSequence().run(chatIDs: ["chat1", "chat2"])

        XCTAssertEqual(steps, ["load first.example", "clear first.example chat1",
                               "load first.example", "clear first.example chat2",
                               "load second.example", "clear second.example chat1", "clear second.example chat2"])
        XCTAssertThrowsError(try result.get()) { XCTAssertEqual($0 as? TestError, .clearFailed("first.example chat1")) }
    }

    func testWhenChatFailureDoesNotRequireReloadThenRemainingChatsAreClearedWithoutReload() async {
        failingClears = ["first.example chat1"]
        failuresRequireReload = false

        _ = await makeSequence().run(chatIDs: ["chat1", "chat2"])

        XCTAssertEqual(steps, ["load first.example", "clear first.example chat1", "clear first.example chat2",
                               "load second.example", "clear second.example chat1", "clear second.example chat2"])
    }

    func testWhenLastChatFailsThenOriginIsNotReloaded() async {
        failingClears = ["second.example chat2"]

        _ = await makeSequence().run(chatIDs: ["chat1", "chat2"])

        XCTAssertEqual(steps.last, "clear second.example chat2")
    }

    func testWhenTwoChatsInARowGetNoAnswerThenTheRestOfThatOriginIsSkipped() async {
        failingClears = ["first.example chat1", "first.example chat2", "first.example chat3"]

        _ = await makeSequence().run(chatIDs: ["chat1", "chat2", "chat3"])

        XCTAssertEqual(steps, ["load first.example", "clear first.example chat1",
                               "load first.example", "clear first.example chat2",
                               "load second.example", "clear second.example chat1", "clear second.example chat2", "clear second.example chat3"])
    }

    func testWhenAnsweredChatSitsBetweenUnansweredOnesThenTheOriginIsNotSkipped() async {
        failingClears = ["first.example chat1", "first.example chat3"]

        _ = await makeSequence().run(chatIDs: ["chat1", "chat2", "chat3"])

        XCTAssertEqual(steps.filter { $0.hasPrefix("clear first.example") },
                       ["clear first.example chat1", "clear first.example chat2", "clear first.example chat3"])
    }
}
