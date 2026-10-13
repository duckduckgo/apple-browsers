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

import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class AIChatMenuButtonPixelsTests: XCTestCase {

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
}
