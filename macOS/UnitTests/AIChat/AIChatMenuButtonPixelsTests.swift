//
//  AIChatMenuButtonPixelsTests.swift
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

@_spi(Testing) import PixelKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

/// The names and `sidebarEntry` values are a contract with the pixel definitions.
final class AIChatMenuButtonPixelsTests: XCTestCase {

    private typealias NewChatGesture = AIChatMenuButtonPixelFirer.NewChatGesture

    private var pixelFiring: PixelKitMock!
    private var firer: AIChatMenuButtonPixelFirer!

    override func setUp() {
        super.setUp()
        pixelFiring = PixelKitMock()
        firer = AIChatMenuButtonPixelFirer(pixelFiring: pixelFiring)
    }

    override func tearDown() {
        firer = nil
        pixelFiring = nil
        super.tearDown()
    }

    // MARK: - Sidebar entry

    func testAPresentedChatIsOfferedCloseSidebarOnAnyPage() {
        XCTAssertEqual(AIChatMenuButtonSidebarEntry(isChatPresented: true, isPageAttachable: true), .closeSidebar)
        XCTAssertEqual(AIChatMenuButtonSidebarEntry(isChatPresented: true, isPageAttachable: false), .closeSidebar)
    }

    func testWithNoChatTheOfferDependsOnWhetherThePageCanBeAttached() {
        XCTAssertEqual(AIChatMenuButtonSidebarEntry(isChatPresented: false, isPageAttachable: true), .askAboutPage)
        XCTAssertEqual(AIChatMenuButtonSidebarEntry(isChatPresented: false, isPageAttachable: false), .openSidebar)
    }

    func testEachOpeningEntryReportsItsOwnSidebarSourceAndCloseSidebarCloses() {
        XCTAssertEqual(AIChatMenuButtonSidebarEntry.askAboutPage.action, .open(.askAboutPage))
        XCTAssertEqual(AIChatMenuButtonSidebarEntry.openSidebar.action, .open(.openSidebar))
        XCTAssertEqual(AIChatMenuButtonSidebarEntry.closeSidebar.action, .close)
    }

    func testOpenSidebarIsReportedApartFromAskAboutPage() {
        let sources = [AIChatSidebarOpenSource.askAboutPage, .openSidebar].map {
            AIChatPixel.aiChatSidebarOpened(source: $0, shouldAutomaticallySendPageContext: nil, minutesSinceSidebarHidden: nil)
                .parameters?["source"]
        }

        XCTAssertEqual(sources, ["ask-about-page", "open-sidebar"])
    }

    // MARK: - Menu shown

    func testMenuShownFiresOncePerOpenWithTheOfferedEntry() {
        for entry in AIChatMenuButtonSidebarEntry.allCases {
            firer.fireMenuShown(sidebarEntry: entry)
        }

        XCTAssertEqual(pixelFiring.actualFireCalls.map(\.pixel.name), Array(repeating: "aichat_title_bar_menu_shown_macos", count: 3))
        XCTAssertEqual(pixelFiring.actualFireCalls.map(\.pixel.parameters), [
            ["sidebarEntry": "ask-about-page"],
            ["sidebarEntry": "open-sidebar"],
            ["sidebarEntry": "close-sidebar"]
        ])
        XCTAssertEqual(pixelFiring.actualFireCalls.map(\.frequency), Array(repeating: .dailyAndCount, count: 3))
        XCTAssertTrue(pixelFiring.actualFireCalls.allSatisfy { $0.pixel.namePrefix == PixelKitNamePrefix.none })
    }

    // MARK: - New chat

    func testAPlainClickOpensTheMenu() {
        XCTAssertNil(NewChatGesture(clickEventType: .leftMouseUp, isCommandPressed: false))
    }

    func testMiddleClickAndCommandClickSkipTheMenu() {
        XCTAssertEqual(NewChatGesture(clickEventType: .otherMouseUp, isCommandPressed: false), .middleClick)
        XCTAssertEqual(NewChatGesture(clickEventType: .leftMouseUp, isCommandPressed: true), .middleClick)
    }

    func testMiddleClickFiresOnlyTheMiddleClickPixel() {
        firer.fireNewChat(via: .middleClick)

        XCTAssertEqual(pixelFiring.actualFireCalls, [
            ExpectedFireCall(pixel: AIChatPixel.aiChatTitleBarMiddleClickNewChat, frequency: .dailyAndCount)
        ])
        XCTAssertEqual(pixelFiring.actualFireCalls.first?.pixel.name, "aichat_title_bar_middle_click_new_chat_macos")
        XCTAssertEqual(pixelFiring.actualFireCalls.first?.pixel.namePrefix, PixelKitNamePrefix.none)
    }

    func testTheMenusNewChatFiresOnlyTheMenuPixel() {
        firer.fireNewChat(via: .menuItem)

        XCTAssertEqual(pixelFiring.actualFireCalls, [
            ExpectedFireCall(pixel: AIChatPixel.aiChatNewChatTitleBarMenu, frequency: .dailyAndStandard)
        ])
        XCTAssertEqual(pixelFiring.actualFireCalls.first?.pixel.namePrefix, PixelKitNamePrefix.platformDefault)
    }
}
