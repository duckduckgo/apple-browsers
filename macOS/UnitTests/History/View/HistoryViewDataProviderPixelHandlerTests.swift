//
//  HistoryViewDataProviderPixelHandlerTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

final class HistoryViewDataProviderPixelHandlerTests: XCTestCase {
    var handler: HistoryViewDataProviderPixelHandler!
    var firePixelCalls: [HistoryViewPixel] = []

    override func setUp() {
        firePixelCalls = []
        handler = HistoryViewDataProviderPixelHandler(
            firePixel: { self.firePixelCalls.append($0) },
            debounce: .milliseconds(100)
        )
    }

    override func tearDown() {
        firePixelCalls = []
    }

    func testThatAllRangeFilterFiresFilterClearedPixel() {
        handler.fireFilterUpdatedPixel(.rangeFilter(.all))
        XCTAssertEqual(firePixelCalls.map(\.name), [HistoryViewPixel.filterCleared.name])
    }

    func testThatEmptySearchTermFilterFiresFilterClearedPixel() {
        handler.fireFilterUpdatedPixel(.searchTerm(""))
        XCTAssertEqual(firePixelCalls.map(\.name), [HistoryViewPixel.filterCleared.name])
    }

    func testThatDateRangeFilterFiresFilterSetPixel() {
        handler.fireFilterUpdatedPixel(.rangeFilter(.monday))
        XCTAssertEqual(firePixelCalls.map(\.name), [HistoryViewPixel.filterSet(.range).name])
    }

    func testThatDomainFilterFiresFilterSetPixel() {
        handler.fireFilterUpdatedPixel(.domainFilter("example.com"))
        XCTAssertEqual(firePixelCalls.map(\.name), [HistoryViewPixel.filterSet(.domain).name])
    }

    func testThatSearchTermFilterIsDebounced() async throws {
        handler.fireFilterUpdatedPixel(.searchTerm("e"))
        handler.fireFilterUpdatedPixel(.searchTerm("ex"))
        handler.fireFilterUpdatedPixel(.searchTerm("exa"))
        handler.fireFilterUpdatedPixel(.searchTerm("exam"))
        handler.fireFilterUpdatedPixel(.searchTerm("examp"))
        handler.fireFilterUpdatedPixel(.searchTerm("exampl"))
        handler.fireFilterUpdatedPixel(.searchTerm("example"))

        try await Task.sleep(nanoseconds: 200_000_000)

        handler.fireFilterUpdatedPixel(.searchTerm("example."))
        handler.fireFilterUpdatedPixel(.searchTerm("example.c"))
        handler.fireFilterUpdatedPixel(.searchTerm("example.co"))
        handler.fireFilterUpdatedPixel(.searchTerm("example.com"))

        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(firePixelCalls.map(\.name), [
            HistoryViewPixel.filterSet(.searchTerm).name,
            HistoryViewPixel.filterSet(.searchTerm).name
        ])
    }
}
