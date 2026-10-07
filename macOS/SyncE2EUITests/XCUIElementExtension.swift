//
//  XCUIElementExtension.swift
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

extension XCUIElement {
    /// Timeout constants for different test requirements
    enum Timeouts {
        /// Mostly, we use timeouts to wait for element existence. This is about 3x longer than needed, for CI resilience
        static let elementExistence: Double = 5.0
    }

    @discardableResult
    func assertExists(with timeout: TimeInterval = Timeouts.elementExistence, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(waitForExistence(timeout: timeout), "\(self) didn't become available in a reasonable timeframe.", file: file, line: line)
        return self
    }
}
