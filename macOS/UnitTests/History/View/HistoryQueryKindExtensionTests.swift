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
        XCTAssertEqual(DataModel.HistoryQueryKind.domainFilter(["domain"]).deleteMode, .sites(["domain"]))
        XCTAssertEqual(DataModel.HistoryQueryKind.rangeFilter(.all).deleteMode, .all)
        XCTAssertEqual(DataModel.HistoryQueryKind.rangeFilter(.today).deleteMode, .today)
        XCTAssertEqual(DataModel.HistoryQueryKind.rangeFilter(.yesterday).deleteMode, .yesterday)
        XCTAssertEqual(DataModel.HistoryQueryKind.rangeFilter(.older).deleteMode, .older)

        XCTAssertTrue(DataModel.HistoryQueryKind.rangeFilter(.sunday).deleteMode.isDate)
        XCTAssertTrue(DataModel.HistoryQueryKind.rangeFilter(.monday).deleteMode.isDate)
        XCTAssertTrue(DataModel.HistoryQueryKind.rangeFilter(.tuesday).deleteMode.isDate)
        XCTAssertTrue(DataModel.HistoryQueryKind.rangeFilter(.wednesday).deleteMode.isDate)
        XCTAssertTrue(DataModel.HistoryQueryKind.rangeFilter(.thursday).deleteMode.isDate)
        XCTAssertTrue(DataModel.HistoryQueryKind.rangeFilter(.friday).deleteMode.isDate)
        XCTAssertTrue(DataModel.HistoryQueryKind.rangeFilter(.saturday).deleteMode.isDate)
    }

    // MARK: - Date title format

    func testCompactDateFormatNamesTheWeekdayMonthAndDayWithoutTheYear() {
        // Scenario: A History view section that covers a single date, titled by the compact dialog.
        // Expectation: The format names the weekday, the month and the day, and leaves the year out.
        // These sections only reach back one week, so the year adds nothing and only made the title
        // long enough to wrap onto a second line.
        //
        // The format is asserted instead of a formatted string, because the wording and the order of
        // the parts depend on the locale of the machine running the test.

        let format = HistoryViewDeleteDialogModel.compactDateFormatter.dateFormat ?? ""

        XCTAssertFalse(format.contains("y"), "The compact date must not name the year, got format \(format)")
        XCTAssertFalse(format.contains("Y"), "The compact date must not name the year, got format \(format)")
        XCTAssertTrue(format.contains("EEEE"), "The compact date must name the weekday, got format \(format)")
        // Some locales resolve the month of a template to its standalone form.
        XCTAssertTrue(format.contains("MMMM") || format.contains("LLLL"),
                      "The compact date must name the month, got format \(format)")
        XCTAssertTrue(format.contains("d"), "The compact date must name the day, got format \(format)")
    }

    func testFullDateFormatStillNamesTheYear() {
        // Scenario: The legacy dialog titles a section that covers a single date.
        // Expectation: The date still names the year. Shortening the date belongs to the compact
        // dialog, and must not reach the legacy one.

        let format = HistoryViewDeleteDialogModel.dateFormatter.dateFormat ?? ""

        XCTAssertTrue(format.contains("y") || format.contains("Y"),
                      "The full date must name the year, got format \(format)")
    }

    func testDateTitlesEmbedTheFormattedDate() {
        // Scenario: Each dialog titles a section that covers a single date.
        // Expectation: Each title carries the date in its own format, so the user can see which day
        // is deleted, and the two titles differ.

        let date = Date(timeIntervalSince1970: 1715774400)
        let fullDate = HistoryViewDeleteDialogModel.dateFormatter.string(from: date)
        let compactDate = HistoryViewDeleteDialogModel.compactDateFormatter.string(from: date)

        XCTAssertTrue(HistoryViewDeleteDialogModel.DeleteMode.date(date).title.contains(fullDate),
                      "Expected the title to contain \(fullDate)")
        XCTAssertTrue(HistoryViewDeleteDialogModel.DeleteMode.date(date).compactTitle.contains(compactDate),
                      "Expected the compact title to contain \(compactDate)")
        XCTAssertNotEqual(fullDate, compactDate)
    }

    func testTitlesWithoutADateAreTheSameInBothFormats() {
        // Scenario: The delete modes that carry no date.
        // Expectation: The compact title matches the full one, because only the date is shortened.

        let modes: [HistoryViewDeleteDialogModel.DeleteMode] = [
            .all, .today, .yesterday, .older, .unspecified, .sites(["example.com"]), .sites(["a.com", "b.com"])
        ]

        for mode in modes {
            XCTAssertEqual(mode.compactTitle, mode.title, "\(mode)")
        }
    }

    func testShouldSkipDeleteDialog() {
        XCTAssertFalse(DataModel.HistoryQueryKind.rangeFilter(.all).shouldSkipDeleteDialog)
        XCTAssertFalse(DataModel.HistoryQueryKind.rangeFilter(.today).shouldSkipDeleteDialog)
        XCTAssertFalse(DataModel.HistoryQueryKind.rangeFilter(.yesterday).shouldSkipDeleteDialog)
        XCTAssertFalse(DataModel.HistoryQueryKind.rangeFilter(.older).shouldSkipDeleteDialog)
        XCTAssertFalse(DataModel.HistoryQueryKind.searchTerm("searchTerm").shouldSkipDeleteDialog)
        XCTAssertFalse(DataModel.HistoryQueryKind.domainFilter(["domain"]).shouldSkipDeleteDialog)
        XCTAssertTrue(DataModel.HistoryQueryKind.searchTerm("").shouldSkipDeleteDialog)
        XCTAssertTrue(DataModel.HistoryQueryKind.domainFilter([]).shouldSkipDeleteDialog)
    }
}
