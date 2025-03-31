//
//  BrokenSiteReportHistoryEntryTests.swift
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
@testable import PrivacyDashboard

final class BrokenSiteReportHistoryEntryTests: XCTestCase {

    private let daysToExpiry: Int = 30

    func testDates() throws {
        let testDate = Date(timeIntervalSince1970: 1704795829)
        let entry = BrokenSiteReportEntry(report: BrokenSiteReportMocks.report, currentDate: testDate, daysToExpiry: daysToExpiry)

        XCTAssertNotNil(entry)
        XCTAssertEqual("2024-01-09", entry?.lastSentDayString)
        XCTAssertEqual(1704795829 + (86400*30), entry?.expiryDate?.timeIntervalSince1970)
    }

    func testUniqueIdentifier() throws {
        let testDate = Date(timeIntervalSince1970: 1704795829)
        let entry = BrokenSiteReportEntry(report: BrokenSiteReportMocks.report, currentDate: testDate, daysToExpiry: daysToExpiry)
        let entry2 = BrokenSiteReportEntry(report: BrokenSiteReportMocks.report2, currentDate: testDate, daysToExpiry: daysToExpiry)
        XCTAssertNotEqual(entry?.identifier, entry2?.identifier)

        let entry3 = BrokenSiteReportEntry(report: BrokenSiteReportMocks.report, currentDate: testDate, daysToExpiry: daysToExpiry)
        XCTAssertEqual(entry?.identifier, entry3?.identifier)
    }

    func testURLSanitation() {
        let report = BrokenSiteReportMocks.report3

        let trimmedURL = report.siteUrl.trimmingQueryItemsAndFragment()
        XCTAssertEqual(trimmedURL.absoluteString, "https://www.subdomain.example.com/some/pathname")

        let privacySanitisedURL = report.siteUrl.privacySanitised()
        XCTAssertEqual(privacySanitisedURL.absoluteString, "https://www.subdomain.example.com")
    }
}
