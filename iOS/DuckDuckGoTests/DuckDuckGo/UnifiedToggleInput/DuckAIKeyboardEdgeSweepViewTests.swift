//
//  DuckAIKeyboardEdgeSweepViewTests.swift
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

final class DuckAIKeyboardEdgeSweepViewTests: XCTestCase {

    func test_isActive_whenFlagOnAndEditingDuckAIInput() {
        XCTAssertTrue(isActive())
    }

    func test_isActive_falseWhenFlagOff() {
        XCTAssertFalse(isActive(isFeatureOn: false))
    }

    func test_isActive_falseWhenNotEditing() {
        XCTAssertFalse(isActive(isInputEditing: false))
    }

    func test_isActive_falseInSearchMode() {
        XCTAssertFalse(isActive(inputMode: .search))
    }

    func test_isActive_falseWhenUnifiedToggleInputUnavailable() {
        XCTAssertFalse(isActive(isUnifiedToggleInputAvailable: false))
    }

    // MARK: - Helper

    private func isActive(
        isFeatureOn: Bool = true,
        isInputEditing: Bool = true,
        inputMode: TextEntryMode = .aiChat,
        isUnifiedToggleInputAvailable: Bool = true
    ) -> Bool {
        DuckAIKeyboardEdgeSweepView.isActive(
            isFeatureOn: isFeatureOn,
            isInputEditing: isInputEditing,
            inputMode: inputMode,
            isUnifiedToggleInputAvailable: isUnifiedToggleInputAvailable
        )
    }
}
