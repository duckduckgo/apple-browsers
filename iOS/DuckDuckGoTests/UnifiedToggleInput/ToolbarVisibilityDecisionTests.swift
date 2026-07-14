//
//  ToolbarVisibilityDecisionTests.swift
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

final class ToolbarVisibilityDecisionTests: XCTestCase {

    // MARK: - Toolbar hidden on AI chrome (non-omnibar)

    func test_aiChrome_notOmnibarSession_hidesToolbar() {
        XCTAssertEqual(decide(isCurrentTabUsingUnifiedInputAIChrome: true, isFocusedOmnibarSession: false).visibility, .hidden)
    }

    func test_aiChrome_omnibarSession_keepsToolbarTabLike() {
        // Focused omnibar opened from a Duck.ai tab keeps the toolbar (standard browser controls).
        XCTAssertEqual(decide(isCurrentTabUsingUnifiedInputAIChrome: true, isFocusedOmnibarSession: true).visibility, .visible)
    }

    // MARK: - Non-AI branch (iPad / minimal chrome)

    func test_nonAIChrome_largeWidth_hidesToolbar() {
        XCTAssertEqual(decide(isLargeWidth: true).visibility, .hidden)
    }

    func test_nonAIChrome_minimalChrome_hidesToolbar() {
        XCTAssertEqual(decide(isInMinimalChromeLayout: true).visibility, .hidden)
    }

    func test_nonAIChrome_phone_showsToolbar() {
        XCTAssertEqual(decide().visibility, .visible)
    }

    // MARK: - Bars recompute on hidden-flip

    func test_recomputesBars_whenHiddenFlips() {
        XCTAssertTrue(decide(isCurrentTabUsingUnifiedInputAIChrome: true, currentToolbarIsHidden: false).recomputesBars)
        XCTAssertFalse(decide(isCurrentTabUsingUnifiedInputAIChrome: true, currentToolbarIsHidden: true).recomputesBars)
    }

    // MARK: - Helper

    private func decide(
        isCurrentTabUsingUnifiedInputAIChrome: Bool = false,
        isFocusedOmnibarSession: Bool = false,
        isLargeWidth: Bool = false,
        isInMinimalChromeLayout: Bool = false,
        currentToolbarIsHidden: Bool = false
    ) -> ToolbarVisibilityDecision {
        ToolbarVisibilityDecision.resolve(.init(
            isCurrentTabUsingUnifiedInputAIChrome: isCurrentTabUsingUnifiedInputAIChrome,
            isFocusedOmnibarSession: isFocusedOmnibarSession,
            isLargeWidth: isLargeWidth,
            isInMinimalChromeLayout: isInMinimalChromeLayout,
            currentToolbarIsHidden: currentToolbarIsHidden
        ))
    }
}
