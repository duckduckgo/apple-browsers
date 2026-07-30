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
                         hasActiveChat: Bool = false,
                         isContextualSurfacePresented: Bool = false) -> DuckAIAddressBarEntry {
        DuckAIAddressBarEntry.resolve(
            isContextualModeAvailable: isContextualModeAvailable,
            isFloatingInputAvailable: isFloatingInputAvailable,
            isHomeTab: isHomeTab,
            hasActiveChat: hasActiveChat,
            isContextualSurfacePresented: isContextualSurfacePresented
        )
    }

    // MARK: - Menu

    func testWebPageWithFloatingInputAndNoChatShowsTheMenu() {
        XCTAssertEqual(resolve(), .menu)
    }

    // MARK: - Sheet

    func testWebPageWithAnActiveChatGoesStraightToTheSheet() {
        XCTAssertEqual(resolve(hasActiveChat: true), .contextualSheet)
    }

    func testWebPageWithoutFloatingInputGoesStraightToTheSheet() {
        XCTAssertEqual(resolve(isFloatingInputAvailable: false), .contextualSheet)
    }

    // MARK: - Dismissal

    func testAPresentedSurfaceIsDismissedRatherThanReopened() {
        XCTAssertEqual(resolve(isContextualSurfacePresented: true), .dismissContextualSurface)
    }

    func testAPresentedSurfaceWinsOverAnActiveChat() {
        XCTAssertEqual(resolve(hasActiveChat: true, isContextualSurfacePresented: true), .dismissContextualSurface)
    }

    // MARK: - Legacy

    func testHomeTabOpensDuckAiDirectly() {
        XCTAssertEqual(resolve(isHomeTab: true), .legacyDuckAI)
    }

    func testWithoutContextualModeOpensDuckAiDirectly() {
        XCTAssertEqual(resolve(isContextualModeAvailable: false), .legacyDuckAI)
    }

    func testHomeTabWinsOverAnActiveChat() {
        XCTAssertEqual(resolve(isHomeTab: true, hasActiveChat: true), .legacyDuckAI)
    }

    func testHomeTabWinsOverAPresentedSurface() {
        XCTAssertEqual(resolve(isHomeTab: true, isContextualSurfacePresented: true), .legacyDuckAI)
    }
}
