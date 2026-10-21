//
//  JSFileCacheTests.swift
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

import Foundation
import XCTest
@testable import UserScript

class JSFileCacheTests: XCTestCase {

    // MARK: - content(forFile:in:)

    func testContentReturnsFileFromBundle() throws {
        let content = try JSFileCache.content(forFile: "testUserScript", in: .module)
        XCTAssertTrue(content.contains("var val"))
    }

    func testContentThrowsForMissingFile() {
        XCTAssertThrowsError(try JSFileCache.content(forFile: "nonExistentFile", in: .module)) { error in
            guard case let UserScriptError.failedToLoadJS(jsFile, _) = error else {
                return XCTFail("Expected failedToLoadJS error but got: \(error)")
            }
            XCTAssertEqual(jsFile, "nonExistentFile")
        }
    }

    func testContentReturnsSameResultOnSecondCall() throws {
        let first = try JSFileCache.content(forFile: "testUserScript", in: .module)
        let second = try JSFileCache.content(forFile: "testUserScript", in: .module)
        XCTAssertEqual(first, second)
    }
}
