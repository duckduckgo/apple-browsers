//
//  AIChatConversationSourceHandlerTests.swift
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

final class AIChatConversationSourceHandlerTests: XCTestCase {

    func testTheEntryIsTakenOnce() {
        let handler = AIChatConversationSourceHandler()
        handler.setData(.tabBarButton)

        XCTAssertEqual(handler.takeUnreportedEntry(), .tabBarButton)
        XCTAssertNil(handler.takeUnreportedEntry())
    }

    func testTakingTheEntryLeavesTheChatsSource() {
        let handler = AIChatConversationSourceHandler()
        handler.setData(.omnibar)

        _ = handler.takeUnreportedEntry()

        XCTAssertEqual(handler.consumeData(), .omnibar)
    }

    func testTheChatConsumingItsSourceLeavesTheEntry() {
        let handler = AIChatConversationSourceHandler()
        handler.setData(.omnibar)

        _ = handler.consumeData()

        XCTAssertEqual(handler.takeUnreportedEntry(), .omnibar)
    }

    func testANewStampReplacesAnUnreportedEntry() {
        let handler = AIChatConversationSourceHandler()
        handler.setData(.mainMenuVoice)
        handler.setData(.promptBar)

        XCTAssertEqual(handler.takeUnreportedEntry(), .promptBar)
    }

    func testDiscardingAPendingOpenClearsBoth() {
        let handler = AIChatConversationSourceHandler()
        handler.setData(.mainMenuVoice)

        handler.discardPendingOpen()

        XCTAssertNil(handler.takeUnreportedEntry())
        XCTAssertNil(handler.consumeData())
    }

    func testMainMenuAskAboutPageCountsAsTheAskDuckAIButton() {
        XCTAssertTrue(AIChatConversationSource.mainMenuAskAboutPage.isAskDuckAiButton)
        XCTAssertEqual(AIChatConversationSource.mainMenuAskAboutPage.rawValue, "main-menu-ask-about-page")
    }
}
