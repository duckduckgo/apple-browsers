//
//  SurveyLastSearchStateRefresherIntegrationTests.swift
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
import RemoteMessaging
import BrowserServicesKitTestsUtils
@testable import DuckDuckGo

@Suite("RMF - Survey Last Search State Refresher - Integration Tests")
struct SurveyLastSearchStateRefresherIntegrationTests {

    @Test("Check Refresher Correctly Uses Survey URL Builder")
    func refreshLastSearchStateUsesCorrectlySurveyURLBuilder() throws {
        // GIVEN
        let testDate = Date(timeIntervalSince1970: 1760054400) // 10 October 2025 12:00:00 AM GMT
        let mockProvider = MockAutofillUsageProvider(searchDauDate: testDate)

        let sut = RemoteMessagingSurveyLastSearchStateRefresher(
            searchDauDateProvider: mockProvider,
            refreshLastSearchStateFunction: DefaultRemoteMessagingSurveyURLBuilder.refreshLastSearchState
        )
        let testPath = "https://survey.example.com?last_search_state=1760054400"

        // WHEN
        let result = sut.refreshLastSearchState(forURLPath: testPath)

        // THEN
        let lastSearchStateQueryPath = try #require(result.components(separatedBy: "last_search_state=").last)
        #expect(result.contains("survey.example.com"))
        #expect(lastSearchStateQueryPath != "1760054400")
    }

}
