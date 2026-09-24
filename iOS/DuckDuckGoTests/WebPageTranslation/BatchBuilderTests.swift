//
//  BatchBuilderTests.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

final class BatchBuilderTests: XCTestCase {

    func test_viewportOnly_stopsAfterViewport() {
        XCTAssertEqual(buildIndexBatches(uniqueCount: 12, viewportCount: 3, scope: .viewportOnly, restBatchSize: 5), [[0, 1, 2]])
    }

    func test_batches_viewportThenChunkedRest() {
        XCTAssertEqual(buildIndexBatches(uniqueCount: 12, viewportCount: 3, scope: .batches, restBatchSize: 5), [[0, 1, 2], [3, 4, 5, 6, 7], [8, 9, 10, 11]])
    }

    func test_batches_noViewport() {
        XCTAssertEqual(buildIndexBatches(uniqueCount: 4, viewportCount: 0, scope: .batches, restBatchSize: 5), [[0, 1, 2, 3]])
    }

    func test_fullPageExtracted_singleBatchOfEverything() {
        XCTAssertEqual(buildIndexBatches(uniqueCount: 12, viewportCount: 3, scope: .fullPageExtracted, restBatchSize: 5), [[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]])
    }

    func test_fullPageHTML_singleBatch() {
        XCTAssertEqual(buildIndexBatches(uniqueCount: 1, viewportCount: 1, scope: .fullPageHTML, restBatchSize: 5), [[0]])
    }

    func test_emptyInput_returnsNoBatches() {
        XCTAssertEqual(buildIndexBatches(uniqueCount: 0, viewportCount: 0, scope: .batches, restBatchSize: 5), [])
    }
}
