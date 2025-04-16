//
//  HistoryQueryKindExtensionTests.swift
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

import HistoryView
import XCTest
@testable import DuckDuckGo_Privacy_Browser

fileprivate extension HistoryViewDeleteDialogModel.DeleteMode {
    var isDate: Bool {
        switch self {
        case .date:
            return true
        default:
            return false
        }
    }
}

final class HistoryQueryKindExtensionTests: XCTestCase {

    func testDeleteMode() throws {
        XCTAssertEqual(DataModel.HistoryQueryKind.searchTerm("searchTerm").deleteMode, .unspecified)
        XCTAssertEqual(DataModel.HistoryQueryKind.domainFilter("domain").deleteMode, .unspecified)
        XCTAssertEqual(DataModel.HistoryQueryKind.rangeFilter(.all).deleteMode, .all)
        XCTAssertEqual(DataModel.HistoryQueryKind.rangeFilter(.today).deleteMode, .today)
        XCTAssertEqual(DataModel.HistoryQueryKind.rangeFilter(.yesterday).deleteMode, .yesterday)
        XCTAssertEqual(DataModel.HistoryQueryKind.rangeFilter(.older).deleteMode, .unspecified)

        XCTAssertTrue(DataModel.HistoryQueryKind.rangeFilter(.sunday).deleteMode.isDate)
        XCTAssertTrue(DataModel.HistoryQueryKind.rangeFilter(.monday).deleteMode.isDate)
        XCTAssertTrue(DataModel.HistoryQueryKind.rangeFilter(.tuesday).deleteMode.isDate)
        XCTAssertTrue(DataModel.HistoryQueryKind.rangeFilter(.wednesday).deleteMode.isDate)
        XCTAssertTrue(DataModel.HistoryQueryKind.rangeFilter(.thursday).deleteMode.isDate)
        XCTAssertTrue(DataModel.HistoryQueryKind.rangeFilter(.friday).deleteMode.isDate)
        XCTAssertTrue(DataModel.HistoryQueryKind.rangeFilter(.saturday).deleteMode.isDate)
    }

    func testShouldSkipDeleteDialog() {
        XCTAssertFalse(DataModel.HistoryQueryKind.rangeFilter(.all).shouldSkipDeleteDialog)
        XCTAssertFalse(DataModel.HistoryQueryKind.rangeFilter(.today).shouldSkipDeleteDialog)
        XCTAssertFalse(DataModel.HistoryQueryKind.rangeFilter(.yesterday).shouldSkipDeleteDialog)
        XCTAssertFalse(DataModel.HistoryQueryKind.rangeFilter(.older).shouldSkipDeleteDialog)
        XCTAssertFalse(DataModel.HistoryQueryKind.searchTerm("searchTerm").shouldSkipDeleteDialog)
        XCTAssertFalse(DataModel.HistoryQueryKind.domainFilter("domain").shouldSkipDeleteDialog)
        XCTAssertTrue(DataModel.HistoryQueryKind.searchTerm("").shouldSkipDeleteDialog)
        XCTAssertTrue(DataModel.HistoryQueryKind.domainFilter("").shouldSkipDeleteDialog)
    }
}
