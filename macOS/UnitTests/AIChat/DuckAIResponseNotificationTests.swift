//
//  DuckAIResponseNotificationTests.swift
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

import AIChat
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class DuckAIResponseCompletionDetectorTests: XCTestCase {

    private var detector: DuckAIResponseCompletionDetector!

    override func setUp() {
        super.setUp()
        detector = DuckAIResponseCompletionDetector()
    }

    override func tearDown() {
        detector = nil
        super.tearDown()
    }

    func testPromptThenAnswer_isFinishedResponse() {
        XCTAssertFalse(detector.isFinishedResponse(chatID: "c1", lastMessage: .user(count: 3)))
        XCTAssertTrue(detector.isFinishedResponse(chatID: "c1", lastMessage: .assistant(count: 4)))
    }

    func testAnswerWithoutPromptSeenInThisTab_isNotFinishedResponse() {
        XCTAssertFalse(detector.isFinishedResponse(chatID: "c1", lastMessage: .assistant(count: 4)))
    }

    func testSaveAfterNotifiedAnswer_isNotFinishedResponse() {
        _ = detector.isFinishedResponse(chatID: "c1", lastMessage: .user(count: 3))
        _ = detector.isFinishedResponse(chatID: "c1", lastMessage: .assistant(count: 4))

        XCTAssertFalse(detector.isFinishedResponse(chatID: "c1", lastMessage: .assistant(count: 4)))
    }

    func testAnswerForAnotherChat_isNotFinishedResponse() {
        _ = detector.isFinishedResponse(chatID: "c1", lastMessage: .user(count: 3))

        XCTAssertFalse(detector.isFinishedResponse(chatID: "c2", lastMessage: .assistant(count: 4)))
    }

    func testAssistantSaveWithoutNewMessage_isNotFinishedResponse() {
        _ = detector.isFinishedResponse(chatID: "c1", lastMessage: .user(count: 3))

        XCTAssertFalse(detector.isFinishedResponse(chatID: "c1", lastMessage: .assistant(count: 3)))
    }
}

@MainActor
final class DuckAIResponseNotificationPreviewTests: XCTestCase {

    func testPreview_dropsMarkdownAndFoldsLines() {
        let text = """
            ## Ducks

            Ducks are **waterfowl** with [webbed feet](https://example.com).

            - They swim
            1. They fly
            """

        XCTAssertEqual(DuckAIResponseNotificationPresenter.preview(of: text),
                       "Ducks Ducks are waterfowl with webbed feet. They swim They fly")
    }

    func testPreview_longText_isTruncated() throws {
        let preview = try XCTUnwrap(DuckAIResponseNotificationPresenter.preview(of: String(repeating: "a", count: 1000)))

        XCTAssertEqual(preview.count, 300)
        XCTAssertTrue(preview.hasSuffix("…"))
    }

    func testPreview_whitespaceOnly_isNil() {
        XCTAssertNil(DuckAIResponseNotificationPresenter.preview(of: " \n\n "))
    }
}

private extension DuckAiChatLastMessage {
    static func user(count: Int) -> DuckAiChatLastMessage {
        DuckAiChatLastMessage(chatTitle: "Chat", messageCount: count, role: "user", text: "question")
    }

    static func assistant(count: Int) -> DuckAiChatLastMessage {
        DuckAiChatLastMessage(chatTitle: "Chat", messageCount: count, role: "assistant", text: "answer")
    }
}
