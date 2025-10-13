//
//  SurveyLastSearchStateRefresherTests.swift
//  DuckDuckGo
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

import Testing
import Foundation
import BrowserServicesKitTestsUtils
@testable import DuckDuckGo

@Suite("RMF - Survey Last Search State Refresher - Unit Tests")
struct SurveyLastSearchStateRefresherTests {

    @Test("Check Refresher Calls Internal Refresh Function With Correct Arguments")
    func refresherCallsInternalRefreshFunctionWithSearchDauDate() throws {
        // GIVEN
        let testDate = Date(timeIntervalSince1970: 1760054400) // 10 October 2025 12:00:00 AM GMT
        let mockProvider = MockAutofillUsageProvider(searchDauDate: testDate)
        var capturedPath: String?
        var capturedDate: Date?

        let mockRefreshFunction: (String, Date?) -> String = { path, date in
            capturedPath = path
            capturedDate = date
            return "refreshed_\(path)"
        }

        let sut = RemoteMessagingSurveyLastSearchStateRefresher(
            searchDauDateProvider: mockProvider,
            refreshLastSearchStateFunction: mockRefreshFunction
        )
        let testPath = "https://survey.example.com?param=value"

        // WHEN
        let result = sut.refreshLastSearchState(forURLPath: testPath)

        // THEN
        #expect(capturedPath == testPath)
        #expect(capturedDate == testDate)
        #expect(result == "refreshed_\(testPath)")
    }

    @Test("Check Refresher Calls Use Correct Date From Provider Each Time")
    func multipleRefreshCallsUpdateDateEachTime() throws {
        // GIVEN
        let date1 = Date(timeIntervalSince1970: 1760054400) // 10 October 2025 12:00:00 AM GMT
        let date2 = Date(timeIntervalSince1970: 1762732800) // 11 October 2025 12:00:00 AM GMT
        let mockProvider = MockAutofillUsageProvider()

        var capturedDates: [Date?] = []
        let mockRefreshFunction: (String, Date?) -> String = { _, date in
            capturedDates.append(date)
            return "result"
        }

        let sut = RemoteMessagingSurveyLastSearchStateRefresher(
            searchDauDateProvider: mockProvider,
            refreshLastSearchStateFunction: mockRefreshFunction
        )

        // WHEN
        mockProvider.searchDauDate = date1
        _ = sut.refreshLastSearchState(forURLPath: "path1")

        mockProvider.searchDauDate = date2
        _ = sut.refreshLastSearchState(forURLPath: "path2")

        mockProvider.searchDauDate = nil
        _ = sut.refreshLastSearchState(forURLPath: "path3")

        // THEN
        #expect(capturedDates.count == 3)
        #expect(try #require(capturedDates[safe: 0]) == date1)
        #expect(try #require(capturedDates[safe: 1]) == date2)
        #expect(try #require(capturedDates[safe: 2]) == nil)
    }

}
