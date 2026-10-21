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
import BrowserServicesKit
import BrowserServicesKitTestsUtils
@testable import DuckDuckGo

@Suite("RMF - Survey Usage State Refresher - Unit Tests")
struct SurveyUsageStateRefresherTests {

    @available(iOS 16, *)
    @Test("Check Refresher Calls Internal Refresh Function With Correct Arguments", .timeLimit(.minutes(1)))
    func refresherCallsInternalRefreshFunctionWithUsageData() throws {
        // GIVEN
        let testDate = Date(timeIntervalSince1970: 1760054400) // 10 October 2025 12:00:00 AM GMT
        let mockProvider = MockAutofillUsageProvider(searchDauDate: testDate)
        let mockFeatureDiscovery = MockFeatureDiscovery()
        mockFeatureDiscovery.setDaysSinceLastUsedValue(3, for: .aiChat)
        var capturedPath: String?
        var capturedDate: Date?
        var capturedDaysSinceDuckAIUsed: Int?

        let mockRefreshFunction: (String, Date?, Int?) -> String = { path, date, daysSinceDuckAIUsed in
            capturedPath = path
            capturedDate = date
            capturedDaysSinceDuckAIUsed = daysSinceDuckAIUsed
            return "refreshed_\(path)"
        }

        let sut = RemoteMessagingSurveyUsageStateRefresher(
            searchDauDateProvider: mockProvider,
            featureDiscovery: mockFeatureDiscovery,
            refreshSurveyUsageStatesFunction: mockRefreshFunction
        )
        let testPath = "https://survey.example.com?last_search_state=none&last_duck_ai_usage=none"

        // WHEN
        let result = sut.refreshSurveyUsageStates(forURLPath: testPath)

        // THEN
        #expect(capturedPath == testPath)
        #expect(capturedDate == testDate)
        #expect(capturedDaysSinceDuckAIUsed == 3)
        #expect(result == "refreshed_\(testPath)")
    }

    @available(iOS 16, *)
    @Test("Check Refresher Calls Use Current Usage Data From Providers", .timeLimit(.minutes(1)))
    func multipleRefreshCallsUpdateUsageDataEachTime() throws {
        // GIVEN
        let date1 = Date(timeIntervalSince1970: 1760054400) // 10 October 2025 12:00:00 AM GMT
        let date2 = Date(timeIntervalSince1970: 1762732800) // 11 October 2025 12:00:00 AM GMT
        let mockProvider = MockAutofillUsageProvider()
        let mockFeatureDiscovery = MockFeatureDiscovery()

        var capturedDates: [Date?] = []
        var capturedDaysSinceDuckAIUsed: [Int?] = []
        let mockRefreshFunction: (String, Date?, Int?) -> String = { _, date, daysSinceDuckAIUsed in
            capturedDates.append(date)
            capturedDaysSinceDuckAIUsed.append(daysSinceDuckAIUsed)
            return "result"
        }

        let sut = RemoteMessagingSurveyUsageStateRefresher(
            searchDauDateProvider: mockProvider,
            featureDiscovery: mockFeatureDiscovery,
            refreshSurveyUsageStatesFunction: mockRefreshFunction
        )

        // WHEN
        mockProvider.searchDauDate = date1
        mockFeatureDiscovery.setDaysSinceLastUsedValue(1, for: .aiChat)
        _ = sut.refreshSurveyUsageStates(forURLPath: "https://survey.example.com?last_search_state=none&last_duck_ai_usage=none")

        mockProvider.searchDauDate = date2
        mockFeatureDiscovery.setDaysSinceLastUsedValue(3, for: .aiChat)
        _ = sut.refreshSurveyUsageStates(forURLPath: "https://survey.example.com?last_search_state=none&last_duck_ai_usage=none")

        mockProvider.searchDauDate = nil
        mockFeatureDiscovery.setDaysSinceLastUsedValue(7, for: .aiChat)
        _ = sut.refreshSurveyUsageStates(forURLPath: "https://survey.example.com?last_search_state=none&last_duck_ai_usage=none")

        // THEN
        #expect(capturedDates.count == 3)
        #expect(try #require(capturedDates[safe: 0]) == date1)
        #expect(try #require(capturedDates[safe: 1]) == date2)
        #expect(try #require(capturedDates[safe: 2]) == nil)
        #expect(capturedDaysSinceDuckAIUsed == [1, 3, 7])
    }

    @available(iOS 16, *)
    @Test("Check Refresher Only Reads Usage Data Requested By Survey URL", .timeLimit(.minutes(1)))
    func refresherOnlyReadsRequestedUsageData() {
        let expectations = [
            (url: "https://survey.example.com?param=value", searchReadCount: 0, duckAIReadCount: 0),
            (url: "https://survey.example.com?last_duck_ai_usage=none", searchReadCount: 0, duckAIReadCount: 1),
            (url: "https://survey.example.com?last_search_state=none", searchReadCount: 1, duckAIReadCount: 0),
            (url: "https://survey.example.com?last_search_state=none&last_duck_ai_usage=none", searchReadCount: 1, duckAIReadCount: 1)
        ]

        for expectation in expectations {
            let searchDauDateProvider = AutofillUsageProviderSpy(searchDauDate: Date())
            let featureDiscovery = FeatureDiscoverySpy(daysSinceDuckAIUsed: 1)
            let sut = RemoteMessagingSurveyUsageStateRefresher(
                searchDauDateProvider: searchDauDateProvider,
                featureDiscovery: featureDiscovery
            )

            _ = sut.refreshSurveyUsageStates(forURLPath: expectation.url)

            #expect(searchDauDateProvider.searchDauDateReadCount == expectation.searchReadCount)
            #expect(featureDiscovery.daysSinceDuckAIUsedReadCount == expectation.duckAIReadCount)
        }
    }

}

private final class AutofillUsageProviderSpy: AutofillUsageProvider {
    private let searchDauDateValue: Date?
    private(set) var searchDauDateReadCount = 0

    var formattedFillDate: String? { nil }
    var fillDate: Date? { nil }
    var lastActiveDate: Date? { nil }
    var formattedLastActiveDate: String? { nil }
    var isOnboarded: Bool { false }
    var searchDauDate: Date? {
        searchDauDateReadCount += 1
        return searchDauDateValue
    }

    init(searchDauDate: Date?) {
        self.searchDauDateValue = searchDauDate
    }
}

private final class FeatureDiscoverySpy: FeatureDiscovery {
    private let daysSinceDuckAIUsed: Int?
    private(set) var daysSinceDuckAIUsedReadCount = 0

    init(daysSinceDuckAIUsed: Int?) {
        self.daysSinceDuckAIUsed = daysSinceDuckAIUsed
    }

    func setWasUsedBefore(_ feature: WasUsedBeforeFeature) {}
    func wasUsedBefore(_ feature: WasUsedBeforeFeature) -> Bool { false }

    func daysSinceLastUsed(_ feature: WasUsedBeforeFeature) -> Int? {
        daysSinceDuckAIUsedReadCount += 1
        return daysSinceDuckAIUsed
    }

    func addToParams(_ params: [String: String], forFeature feature: WasUsedBeforeFeature) -> [String: String] {
        params
    }
}
