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

    // MARK: - Toolbar hidden on AI chrome

    func test_aiChrome_hidesToolbar() {
        XCTAssertTrue(decide(isCurrentTabUsingUnifiedInputAIChrome: true).isHidden)
    }

    // MARK: - Non-AI branch (iPad / minimal chrome)

    func test_nonAIChrome_largeWidth_hidesToolbar() {
        XCTAssertTrue(decide(isLargeWidth: true).isHidden)
    }

    func test_nonAIChrome_minimalChrome_hidesToolbar() {
        XCTAssertTrue(decide(isInMinimalChromeLayout: true).isHidden)
    }

    func test_nonAIChrome_phone_showsToolbar() {
        XCTAssertFalse(decide().isHidden)
    }

    func testWebInputEditingHidesToolbarAndRestoresItsLayoutVisibilityAfterEditing() {
        for isLargeWidth in [false, true] {
            for isInMinimalChromeLayout in [false, true] {
                var inputs = ToolbarVisibilityDecision.Inputs(
                    isCurrentTabUsingUnifiedInputAIChrome: false,
                    isLargeWidth: isLargeWidth,
                    isInMinimalChromeLayout: isInMinimalChromeLayout,
                    isFloatingWebInputEditing: true)
                XCTAssertTrue(ToolbarVisibilityDecision.resolve(inputs).isHidden)

                inputs.isFloatingWebInputEditing = false

                XCTAssertEqual(ToolbarVisibilityDecision.resolve(inputs).isHidden, isLargeWidth || isInMinimalChromeLayout)
            }
        }
    }

    // MARK: - Helper

    private func decide(
        isCurrentTabUsingUnifiedInputAIChrome: Bool = false,
        isLargeWidth: Bool = false,
        isInMinimalChromeLayout: Bool = false
    ) -> ToolbarVisibilityDecision {
        ToolbarVisibilityDecision.resolve(.init(
            isCurrentTabUsingUnifiedInputAIChrome: isCurrentTabUsingUnifiedInputAIChrome,
            isLargeWidth: isLargeWidth,
            isInMinimalChromeLayout: isInMinimalChromeLayout
        ))
    }
}
