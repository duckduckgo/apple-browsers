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
                         isFloatingInputAvailable: Bool = true,
                         isHomeTab: Bool = false,
                         hasChatToReopen: Bool = false,
                         isContextualSurfacePresented: Bool = false) -> DuckAIAddressBarEntry {
        DuckAIAddressBarEntry.resolve(
            isContextualModeAvailable: isContextualModeAvailable,
            isFloatingInputAvailable: isFloatingInputAvailable,
            isHomeTab: isHomeTab,
            hasChatToReopen: hasChatToReopen,
            isContextualSurfacePresented: isContextualSurfacePresented
        )
    }

    // MARK: - Menu

    func testWebPageWithFloatingInputAndNoChatShowsTheMenu() {
        XCTAssertEqual(resolve(), .menu)
    }

    // MARK: - Sheet

    /// Live or restored from a previous launch — both menu actions start something new, so offering the
    /// menu here would leave the conversation unreachable.
    func testAChatToReopenGoesStraightToTheSheet() {
        XCTAssertEqual(resolve(hasChatToReopen: true), .contextualSheet)
    }

    func testWebPageWithoutFloatingInputGoesStraightToTheSheet() {
        XCTAssertEqual(resolve(isFloatingInputAvailable: false), .contextualSheet)
    }

    // MARK: - Dismissal

    func testAPresentedSurfaceIsDismissedRatherThanReopened() {
        XCTAssertEqual(resolve(isContextualSurfacePresented: true), .dismissContextualSurface)
    }

    func testAPresentedSurfaceWinsOverAnActiveChat() {
        XCTAssertEqual(resolve(hasChatToReopen: true, isContextualSurfacePresented: true), .dismissContextualSurface)
    }

    // MARK: - Legacy

    func testHomeTabOpensDuckAiDirectly() {
        XCTAssertEqual(resolve(isHomeTab: true), .legacyDuckAI)
    }

    func testWithoutContextualModeOpensDuckAiDirectly() {
        XCTAssertEqual(resolve(isContextualModeAvailable: false), .legacyDuckAI)
    }

    func testHomeTabWinsOverAnActiveChat() {
        XCTAssertEqual(resolve(isHomeTab: true, hasChatToReopen: true), .legacyDuckAI)
    }

    func testHomeTabWinsOverAPresentedSurface() {
        XCTAssertEqual(resolve(isHomeTab: true, isContextualSurfacePresented: true), .legacyDuckAI)
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

    /// Matches `resolve`, which sends the home tab to `.legacyDuckAI`: the glyph must not promise a
    /// contextual session the tap will not open.
    func testHomeTabNeverShowsTheGlyph() {
        XCTAssertFalse(showsGlyph(isHomeTab: true, hasChatToReopen: true))
        XCTAssertFalse(showsGlyph(isHomeTab: true, isContextualSurfacePresented: true))
    }
}
