//
//  DaxPetCoordinatorTests.swift
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

@MainActor
final class DaxPetCoordinatorTests: XCTestCase {

    private let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
    private let secondScreen = NSRect(x: 1440, y: 0, width: 1920, height: 1080)

    private func characterFrame(at origin: NSPoint) -> NSRect {
        DaxPetView.Metrics.characterFrame().offsetBy(dx: origin.x, dy: origin.y)
    }

    func testWhenDaxIsWhollyOnScreenThenHeStaysPut() {
        let origin = NSPoint(x: 500, y: 100)

        XCTAssertEqual(DaxPetCoordinator.origin(keepingCharacterOnScreenFor: origin, visibleFrames: [screen]), origin)
    }

    func testWhenDaxHangsOffTheLeftEdgeThenHeSlidesBackOn() {
        let origin = NSPoint(x: -characterFrame(at: .zero).midX, y: 100)

        let corrected = DaxPetCoordinator.origin(keepingCharacterOnScreenFor: origin, visibleFrames: [screen])

        XCTAssertEqual(characterFrame(at: corrected).minX, screen.minX, accuracy: 0.001)
        XCTAssertEqual(corrected.y, origin.y)
    }

    func testWhenDaxHangsBelowTheBottomThenHeIsLiftedBackUp() {
        let origin = NSPoint(x: 500, y: -characterFrame(at: .zero).maxY + 10)

        let corrected = DaxPetCoordinator.origin(keepingCharacterOnScreenFor: origin, visibleFrames: [screen])

        XCTAssertEqual(characterFrame(at: corrected).minY, screen.minY, accuracy: 0.001)
    }

    func testWhenDaxStraddlesTwoScreensThenHeLandsOnTheOneHeIsMostlyOn() {
        let character = characterFrame(at: .zero)
        let origin = NSPoint(x: secondScreen.minX - character.minX - character.width * 0.3, y: 100)

        let corrected = DaxPetCoordinator.origin(keepingCharacterOnScreenFor: origin, visibleFrames: [screen, secondScreen])

        XCTAssertEqual(characterFrame(at: corrected).minX, secondScreen.minX, accuracy: 0.001)
    }

    // MARK: - Duck.ai answers

    func testWhenAPageAnswersThenTheAnswerStartsAndFinishes() {
        var tracker = DaxAnswerTracker()
        let page = NSObject()

        XCTAssertEqual(tracker.update(.loading, on: page), .started)
        XCTAssertNil(tracker.update(.streaming, on: page))
        XCTAssertEqual(tracker.update(.ready, on: page), .finished(succeeded: true))
    }

    func testWhenAPageIsReadyWithoutHavingAnsweredThenNothingHappens() {
        var tracker = DaxAnswerTracker()

        XCTAssertNil(tracker.update(.ready, on: NSObject()))
    }

    func testWhenTwoPagesAnswerThenTheAnswerFinishesWithTheLastOne() {
        var tracker = DaxAnswerTracker()
        let first = NSObject(), second = NSObject()

        XCTAssertEqual(tracker.update(.streaming, on: first), .started)
        XCTAssertNil(tracker.update(.streaming, on: second))
        XCTAssertNil(tracker.update(.ready, on: first))
        XCTAssertEqual(tracker.update(.ready, on: second), .finished(succeeded: true))
    }

    func testWhenAPageFailsThenTheAnswerFinishesUnsuccessfully() {
        var tracker = DaxAnswerTracker()
        let page = NSObject()
        _ = tracker.update(.startStreamNewPrompt, on: page)

        XCTAssertEqual(tracker.update(.error, on: page), .finished(succeeded: false))
    }

    // MARK: - Last chat

    private func chat(_ id: String, pinned: Bool = false, at timestamp: Date?) -> AIChatSuggestion {
        AIChatSuggestion(id: id, title: id, isPinned: pinned, chatId: id, timestamp: timestamp)
    }

    func testTheLastChatIsTheOneTouchedMostRecentlyPinnedOrNot() {
        let now = Date()
        let chats = [chat("pinned-old", pinned: true, at: now.addingTimeInterval(-3600)),
                     chat("recent", at: now.addingTimeInterval(-60)),
                     chat("pinned-new", pinned: true, at: now)]

        XCTAssertEqual(DaxPetPromptSubmitter.mostRecent(chats)?.chatId, "pinned-new")
    }

    func testChatsWithoutADateCountAsOldest() {
        let chats = [chat("undated", at: nil), chat("dated", at: Date(timeIntervalSince1970: 0))]

        XCTAssertEqual(DaxPetPromptSubmitter.mostRecent(chats)?.chatId, "dated")
    }

    func testWhenThereAreNoChatsThenThereIsNoLastChat() {
        XCTAssertNil(DaxPetPromptSubmitter.mostRecent([]))
    }
}
