//
//  AttributedMetricOriginFileProviderTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
@testable import DuckDuckGo_Privacy_Browser
@testable import AttributedMetric

final class AttributedMetricOriginFileProviderTests: XCTestCase {
    private var sut: AttributedMetricOriginProvider!
    private let testBundle = Bundle(for: AttributedMetricOriginFileProviderTests.self)
    private let xattrName = "com.duckduckgo.origin.test"

    override func tearDown() {
        // Clean up any xattr we set during tests
        removexattr(testBundle.bundlePath, xattrName, 0)
        sut = nil
    }

    func testWhenXattrExistsThenReturnOriginValue() {
        // GIVEN
        let expected = "app_search"
        expected.withCString { value in
            setxattr(testBundle.bundlePath, xattrName, value, strlen(value), 0, 0)
        }
        sut = AttributedMetricOriginFileProvider(xattrName: xattrName, bundle: testBundle)

        // WHEN
        let result = sut.origin

        // THEN
        XCTAssertEqual(result, expected)
    }

    func testWhenXattrDoesNotExistThenReturnNil() {
        // GIVEN
        sut = AttributedMetricOriginFileProvider(xattrName: xattrName, bundle: testBundle)

        // WHEN
        let result = sut.origin

        // THEN
        XCTAssertNil(result)
    }
}
