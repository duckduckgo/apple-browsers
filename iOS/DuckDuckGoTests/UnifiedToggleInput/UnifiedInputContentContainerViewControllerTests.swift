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

    // MARK: - computeSuggestionTrayEscapeHatchInset
    //
    // Returns the additionalTopInset for the suggestion tray (Search-side).
    // Reference constants (from `Metrics` enum in the VC):
    //   escapeHatchBaseTopInset      = 44   (bottom-bar dismiss-button clearance)
    //   escapeHatchTopBarTrayPullUp  = -10  (top-bar tightening)

    func test_inset_whenNoHatch_returnsZero() {
        XCTAssertEqual(
            UnifiedInputContentContainerViewController.computeSuggestionTrayEscapeHatchInset(
                hasEscapeHatch: false, isBottomBar: true
            ),
            0
        )
        XCTAssertEqual(
            UnifiedInputContentContainerViewController.computeSuggestionTrayEscapeHatchInset(
                hasEscapeHatch: false, isBottomBar: false
            ),
            0
        )
    }

    func test_inset_whenBottomBarAndHatch_returnsDismissButtonClearance() {
        // 44 (base) + 0 (no top-bar pull-up) = 44
        XCTAssertEqual(
            UnifiedInputContentContainerViewController.computeSuggestionTrayEscapeHatchInset(
                hasEscapeHatch: true, isBottomBar: true
            ),
            44
        )
    }

    func test_inset_whenTopBarAndHatch_returnsPullUp() {
        // 0 (base) + (-10) (top-bar pull-up) = -10
        XCTAssertEqual(
            UnifiedInputContentContainerViewController.computeSuggestionTrayEscapeHatchInset(
                hasEscapeHatch: true, isBottomBar: false
            ),
            -10
        )
    }
}
