//
//  AIChatHistorySidebarInstrumentationTests.swift
//  DuckDuckGo
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
@testable import DuckDuckGo
@_spi(Testing) import PixelKit

final class AIChatHistorySidebarInstrumentationTests: XCTestCase {

    private var pixelKit: PixelKitMock!
    private var instrumentation: DefaultAIChatHistorySidebarInstrumentation!

    override func setUp() {
        super.setUp()
        pixelKit = PixelKitMock()
        instrumentation = DefaultAIChatHistorySidebarInstrumentation(pixelFiring: pixelKit)
    }

    override func tearDown() {
        instrumentation = nil
        pixelKit = nil
        super.tearDown()
    }

    func testWhenSidebarOpenedThenFiresOpenedWithSourceAndLayout() {
        instrumentation.sidebarOpened(source: .chatsEntryPoint, layout: .overlay)

        assertSingleFire(name: "aichat_history_sidebar_opened",
                         parameters: ["source": "chats_entry_point", "layout": "overlay"])
    }

    func testWhenSidebarClosedThenFiresClosedWithSourceAndLayout() {
        instrumentation.sidebarClosed(source: .inputChatsButton, layout: .column)

        assertSingleFire(name: "aichat_history_sidebar_closed",
                         parameters: ["source": "input_chats_button", "layout": "column"])
    }

    func testWhenFloatingNewChatTappedThenFiresNewChatTapped() {
        instrumentation.floatingNewChatTapped()

        assertSingleFire(name: "aichat_history_sidebar_new_chat_tapped", parameters: nil)
    }

    func testWhenMenuActionSelectedThenFiresMenuActionWithAction() {
        instrumentation.menuActionSelected(.duckAISettings)

        assertSingleFire(name: "aichat_history_sidebar_menu_action", parameters: ["action": "duckai_settings"])
    }

    func testWhenOpenChatDeletedThenFiresOpenChatDeleted() {
        instrumentation.openChatDeleted()

        assertSingleFire(name: "aichat_history_sidebar_open_chat_deleted", parameters: nil)
    }

    func testWhenPageDoesNotAnswerThenFallbackReasonIsNoAnswer() {
        instrumentation.chatOpenFellBack(outcome: nil)

        assertSingleFire(name: "aichat_history_sidebar_chat_open_fallback", parameters: ["reason": "no_answer"])
    }

    func testWhenPageReportsFailuresThenFallbackReasonMatchesOutcome() {
        instrumentation.chatOpenFellBack(outcome: .notFound)
        instrumentation.chatOpenFellBack(outcome: .failed)

        XCTAssertEqual(pixelKit.actualFireCalls.map { $0.pixel.parameters?["reason"] }, ["not_found", "failed"])
    }

    func testWhenChatOpenedInPlaceThenNoFallbackFires() {
        instrumentation.chatOpenFellBack(outcome: .opened)

        XCTAssertTrue(pixelKit.actualFireCalls.isEmpty)
    }

    private func assertSingleFire(name: String, parameters: [String: String]?, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(pixelKit.actualFireCalls.count, 1, file: file, line: line)
        let call = pixelKit.actualFireCalls.first
        XCTAssertEqual(call?.pixel.name, name, file: file, line: line)
        XCTAssertEqual(call?.pixel.parameters, parameters, file: file, line: line)
        XCTAssertEqual(call?.frequency, .dailyAndCount, file: file, line: line)
    }
}
