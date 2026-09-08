//
//  DuckAIAddressBarEntryTests.swift
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

final class DuckAIAddressBarEntryTests: XCTestCase {

    private func resolve(isContextualModeAvailable: Bool = true,
                         isMenuAvailable: Bool = true,
                         isHomeTab: Bool = false,
                         isChatHistoryAvailable: Bool = true,
                         hasChatToReopen: Bool = false,
                         isContextualSurfacePresented: Bool = false) -> DuckAIAddressBarEntry {
        DuckAIAddressBarEntry.resolve(
            isContextualModeAvailable: isContextualModeAvailable,
            isMenuAvailable: isMenuAvailable,
            isHomeTab: isHomeTab,
            isChatHistoryAvailable: isChatHistoryAvailable,
            hasChatToReopen: hasChatToReopen,
            isContextualSurfacePresented: isContextualSurfacePresented
        )
    }

    // MARK: - Menu

    func testWebPageWithMenuAvailableAndNoChatShowsTheMenu() {
        XCTAssertEqual(resolve(), .menu)
    }

    // MARK: - Sheet

    /// Live and restored conversations retain the direct route back to this tab's chat.
    func testAChatToReopenGoesStraightToTheSheet() {
        XCTAssertEqual(resolve(hasChatToReopen: true), .contextualSheet)
    }

    /// iPhone without the floating input, or iPad without the chrome menu button.
    func testWebPageWithoutMenuGoesStraightToTheSheet() {
        XCTAssertEqual(resolve(isMenuAvailable: false), .contextualSheet)
    }

    // MARK: - Dismissal

    func testAPresentedSurfaceIsDismissedRatherThanReopened() {
        XCTAssertEqual(resolve(isContextualSurfacePresented: true), .dismissContextualSurface)
    }

    func testAPresentedSurfaceWinsOverAnActiveChat() {
        XCTAssertEqual(resolve(hasChatToReopen: true, isContextualSurfacePresented: true), .dismissContextualSurface)
    }

    // MARK: - Legacy

    func testHomeTabOffersMenuWithAndWithoutContextualOrFloatingInput() {
        for contextualMode in [false, true] {
            for floatingInput in [false, true] {
                XCTAssertEqual(resolve(isContextualModeAvailable: contextualMode,
                                       isFloatingInputAvailable: floatingInput,
                                       isHomeTab: true), .menu)
            }
        }
    }

    func testHomeTabWithoutHistoryOpensDuckAiDirectly() {
        XCTAssertEqual(resolve(isHomeTab: true, isChatHistoryAvailable: false), .legacyDuckAI)
    }

    func testWebPageMenuDoesNotRequireHistory() {
        XCTAssertEqual(resolve(isChatHistoryAvailable: false), .menu)
    }

    func testWithoutContextualModeOpensDuckAiDirectly() {
        XCTAssertEqual(resolve(isContextualModeAvailable: false), .legacyDuckAI)
    }

    func testHomeTabWinsOverAnActiveChat() {
        XCTAssertEqual(resolve(isHomeTab: true, hasChatToReopen: true), .menu)
    }

    func testHomeTabWinsOverAPresentedSurface() {
        XCTAssertEqual(resolve(isHomeTab: true, isContextualSurfacePresented: true), .menu)
    }

    // MARK: - Contextual glyph

    private func showsGlyph(isContextualModeAvailable: Bool = true,
                            isHomeTab: Bool = false,
                            hasChatToReopen: Bool = false,
                            isContextualSurfacePresented: Bool = false) -> Bool {
        DuckAIAddressBarEntry.showsContextualGlyph(
            isContextualModeAvailable: isContextualModeAvailable,
            isHomeTab: isHomeTab,
            hasChatToReopen: hasChatToReopen,
            isContextualSurfacePresented: isContextualSurfacePresented
        )
    }

    func testNoGlyphOnAWebPageWithNothingGoingOn() {
        XCTAssertFalse(showsGlyph())
    }

    func testAChatToReopenShowsTheGlyph() {
        XCTAssertTrue(showsGlyph(hasChatToReopen: true))
    }

    /// An open surface counts even before a prompt, so the glyph appears as soon as it does.
    func testAPresentedSurfaceShowsTheGlyphWithoutAChat() {
        XCTAssertTrue(showsGlyph(isContextualSurfacePresented: true))
    }

    /// Dismissing without prompting leaves neither, which is what takes the glyph away again.
    func testDismissingWithoutAChatDropsTheGlyph() {
        XCTAssertFalse(showsGlyph(hasChatToReopen: false, isContextualSurfacePresented: false))
    }

    func testContextualModeOffNeverShowsTheGlyph() {
        XCTAssertFalse(showsGlyph(isContextualModeAvailable: false, hasChatToReopen: true))
    }

    /// Home-tab actions never restore a contextual session.
    func testHomeTabNeverShowsTheGlyph() {
        XCTAssertFalse(showsGlyph(isHomeTab: true, hasChatToReopen: true))
        XCTAssertFalse(showsGlyph(isHomeTab: true, isContextualSurfacePresented: true))
    }
}
