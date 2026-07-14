//
//  UnifiedInputChromeResolverTests.swift
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

final class UnifiedInputChromeResolverTests: XCTestCase {

    // MARK: - Toolbar hidden on AI chrome (non-omnibar)

    func test_aiChrome_notOmnibarSession_hidesToolbar() {
        let state = resolve(isCurrentTabUsingUnifiedInputAIChrome: true, isFocusedOmnibarSession: false)
        XCTAssertEqual(state.toolbar, .hidden)
    }

    func test_aiChrome_omnibarSession_keepsToolbarTabLike() {
        // Focused omnibar opened from a Duck.ai tab keeps the toolbar (standard browser controls).
        let state = resolve(isCurrentTabUsingUnifiedInputAIChrome: true, isFocusedOmnibarSession: true)
        XCTAssertEqual(state.toolbar, .visible(healsClampConstant: false))
    }

    // MARK: - Non-AI branch (iPad / minimal chrome)

    func test_nonAIChrome_largeWidth_hidesToolbar() {
        let state = resolve(isLargeWidth: true)
        XCTAssertEqual(state.toolbar, .hidden)
    }

    func test_nonAIChrome_minimalChrome_hidesToolbar() {
        let state = resolve(isInMinimalChromeLayout: true)
        XCTAssertEqual(state.toolbar, .hidden)
    }

    func test_nonAIChrome_phone_showsToolbar() {
        let state = resolve()
        XCTAssertEqual(state.toolbar, .visible(healsClampConstant: false))
    }

    // MARK: - Self-heal clamp (kept in Phase 1; Phase 4 deletes it)

    func test_visibleToolbar_staleOffscreenConstant_healsClamp() {
        let state = resolve(toolbarAlpha: 1.0, toolbarBottomConstant: 49)
        XCTAssertEqual(state.toolbar, .visible(healsClampConstant: true))
    }

    func test_visibleToolbar_partialAlpha_doesNotHeal() {
        // alpha < 1 == mid-scroll partial hide; not a stale clamp.
        let state = resolve(toolbarAlpha: 0.5, toolbarBottomConstant: 49)
        XCTAssertEqual(state.toolbar, .visible(healsClampConstant: false))
    }

    func test_visibleToolbar_constantAlreadyZero_doesNotHeal() {
        let state = resolve(toolbarAlpha: 1.0, toolbarBottomConstant: 0)
        XCTAssertEqual(state.toolbar, .visible(healsClampConstant: false))
    }

    // MARK: - Bars recompute on hidden-flip

    func test_recomputesBars_whenHiddenFlips() {
        let flips = resolve(isCurrentTabUsingUnifiedInputAIChrome: true, currentToolbarIsHidden: false)
        XCTAssertTrue(flips.recomputesBars)
        let stable = resolve(isCurrentTabUsingUnifiedInputAIChrome: true, currentToolbarIsHidden: true)
        XCTAssertFalse(stable.recomputesBars)
    }

    // MARK: - Helper

    private func resolve(
        isCurrentTabUsingUnifiedInputAIChrome: Bool = false,
        isFocusedOmnibarSession: Bool = false,
        isLargeWidth: Bool = false,
        isInMinimalChromeLayout: Bool = false,
        currentToolbarIsHidden: Bool = false,
        toolbarAlpha: CGFloat = 1.0,
        toolbarBottomConstant: CGFloat = 0
    ) -> ChromeState {
        UnifiedInputChromeResolver.resolve(.init(
            isCurrentTabUsingUnifiedInputAIChrome: isCurrentTabUsingUnifiedInputAIChrome,
            isFocusedOmnibarSession: isFocusedOmnibarSession,
            isLargeWidth: isLargeWidth,
            isInMinimalChromeLayout: isInMinimalChromeLayout,
            currentToolbarIsHidden: currentToolbarIsHidden,
            toolbarAlpha: toolbarAlpha,
            toolbarBottomConstant: toolbarBottomConstant
        ))
    }
}
