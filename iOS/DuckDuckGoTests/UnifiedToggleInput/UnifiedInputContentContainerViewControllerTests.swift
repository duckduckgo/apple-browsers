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
    // Returns the additionalTopInset applied to both the search and duck.ai
    // suggestion trays so the UTI escape hatch lines up with the NTP hatch.

    func test_inset_whenNoHatch_returnsZero() {
        XCTAssertEqual(
            UnifiedInputContentContainerViewController.computeSuggestionTrayEscapeHatchInset(
                hasEscapeHatch: false
            ),
            0
        )
    }

    func test_inset_whenHatchPresent_returnsPullUp() {
        XCTAssertEqual(
            UnifiedInputContentContainerViewController.computeSuggestionTrayEscapeHatchInset(
                hasEscapeHatch: true
            ),
            -10
        )
    }
}
