//
//  UnifiedInputContentContainerViewControllerTests.swift
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

final class UnifiedInputContentContainerViewControllerTests: XCTestCase {

    // MARK: - computeEscapeHatchInsets
    //
    // The formula produces two CGFloat values used as `additionalTopInset` for the
    // suggestion tray (Search) and the chat history list (Duck.ai). Each constant is
    // gated by `hasEscapeHatch`, so the result naturally collapses to (0, 0) when no
    // hatch is present.
    //
    // Reference constants (from `Metrics` enum in the VC):
    //   escapeHatchBaseTopInset              = 44
    //   escapeHatchTopBarTrayPullUp          = -10
    //   chatHistoryBottomBarCompensation     = 1
    //   escapeHatchEmptyListBoost            = 165
    //   landscapeDuckAiAlignmentPullUp       = -1

    // MARK: - No hatch (natural collapse to zero)

    func test_computeEscapeHatchInsets_whenNoHatch_returnsZeroForBothRegardlessOfOtherFlags() {
        let insets = UnifiedInputContentContainerViewController.computeEscapeHatchInsets(
            hasEscapeHatch: false,
            isBottomBar: true,
            chatHasSuggestions: true,
            isLandscape: true
        )
        XCTAssertEqual(insets.tray, 0)
        XCTAssertEqual(insets.chat, 0)
    }

    // MARK: - Portrait top bar (isBottomBar: false, isLandscape: false)

    func test_computeEscapeHatchInsets_whenPortraitTopBarAndNoChats_returnsTrayPullUpAndEmptyListBoost() {
        let insets = UnifiedInputContentContainerViewController.computeEscapeHatchInsets(
            hasEscapeHatch: true,
            isBottomBar: false,
            chatHasSuggestions: false,
            isLandscape: false
        )
        // Tray: 0 (base, no bottom bar) + (-10) (top bar pull-up) = -10
        XCTAssertEqual(insets.tray, -10)
        // Chat: 0 (base) - 0 (compensation) + 165 (empty list boost) + 0 (no landscape) = 165
        XCTAssertEqual(insets.chat, 165)
    }

    func test_computeEscapeHatchInsets_whenPortraitTopBarAndWithChats_returnsTrayPullUpAndNoBoost() {
        let insets = UnifiedInputContentContainerViewController.computeEscapeHatchInsets(
            hasEscapeHatch: true,
            isBottomBar: false,
            chatHasSuggestions: true,
            isLandscape: false
        )
        XCTAssertEqual(insets.tray, -10)
        // Chat: 0 - 0 + 0 (chats present → no boost) + 0 = 0
        XCTAssertEqual(insets.chat, 0)
    }

    // MARK: - Portrait bottom bar (isBottomBar: true, isLandscape: false)

    func test_computeEscapeHatchInsets_whenPortraitBottomBarAndNoChats_returnsDismissButtonInsetMinusCompensation() {
        let insets = UnifiedInputContentContainerViewController.computeEscapeHatchInsets(
            hasEscapeHatch: true,
            isBottomBar: true,
            chatHasSuggestions: false,
            isLandscape: false
        )
        // Tray: 44 (dismiss button clearance) + 0 (no pull-up in bottom bar) = 44
        XCTAssertEqual(insets.tray, 44)
        // Chat: 44 - 1 (compensation) + 0 (no boost in bottom bar) + 0 = 43
        XCTAssertEqual(insets.chat, 43)
    }

    func test_computeEscapeHatchInsets_whenPortraitBottomBarAndWithChats_returnsSameAsNoChats() {
        let insets = UnifiedInputContentContainerViewController.computeEscapeHatchInsets(
            hasEscapeHatch: true,
            isBottomBar: true,
            chatHasSuggestions: true,
            isLandscape: false
        )
        // In bottom bar, chatHasSuggestions doesn't change anything (empty list boost is gated on !isBottomBar).
        XCTAssertEqual(insets.tray, 44)
        XCTAssertEqual(insets.chat, 43)
    }

    // MARK: - Landscape (isLandscape: true, auto-switches to top bar)

    func test_computeEscapeHatchInsets_whenLandscapeAndNoChats_returnsTrayPullUpAndLandscapeAlignment() {
        let insets = UnifiedInputContentContainerViewController.computeEscapeHatchInsets(
            hasEscapeHatch: true,
            isBottomBar: false,
            chatHasSuggestions: false,
            isLandscape: true
        )
        XCTAssertEqual(insets.tray, -10)
        // Empty list boost is suppressed in landscape (otherwise hatch ends up under UTI/keyboard).
        // Chat: 0 - 0 + 0 (landscape suppresses boost) + (-1) (landscape alignment) = -1
        XCTAssertEqual(insets.chat, -1)
    }

    func test_computeEscapeHatchInsets_whenLandscapeAndWithChats_returnsLandscapeAlignmentOnly() {
        let insets = UnifiedInputContentContainerViewController.computeEscapeHatchInsets(
            hasEscapeHatch: true,
            isBottomBar: false,
            chatHasSuggestions: true,
            isLandscape: true
        )
        XCTAssertEqual(insets.tray, -10)
        // Chat: 0 - 0 + 0 + (-1) = -1 (same as no chats, since empty list boost is already 0)
        XCTAssertEqual(insets.chat, -1)
    }
}
