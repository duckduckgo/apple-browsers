//
//  UnifiedInputTextChangeGateTests.swift
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

final class UnifiedInputTextChangeGateTests: XCTestCase {

    /// The dismiss cleanup blanks the field to empty — that change is the cleanup, ignore it.
    func test_cleanupBlank_isIgnored() {
        XCTAssertTrue(UnifiedInputTextChangeGate.shouldIgnore(text: "", duringDismissCleanup: true))
    }

    /// A non-empty change during the cleanup window is genuine user input — must be kept.
    func test_genuineInputDuringCleanup_isKept() {
        XCTAssertFalse(UnifiedInputTextChangeGate.shouldIgnore(text: "h", duringDismissCleanup: true))
    }

    /// Outside the cleanup window nothing is ignored, empty or not.
    func test_normalInput_isKept() {
        XCTAssertFalse(UnifiedInputTextChangeGate.shouldIgnore(text: "h", duringDismissCleanup: false))
        XCTAssertFalse(UnifiedInputTextChangeGate.shouldIgnore(text: "", duringDismissCleanup: false))
    }
}
