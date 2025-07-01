//
//  CheckDefaultBrowserManagerTests.swift
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

import Foundation
import Testing
import SetDefaultBrowserTestSupport
@testable import SetDefaultBrowserCore

@MainActor
@Suite("Set Default Browser - Check Default Browser Manager")
final class DefaultBrowserManagerTests {
    let defaultBrowserService: MockCheckDefaultBrowserService!
    let dataProviderMock: MockDateProvider!
    let store: MockDefaultBrowserInfoStore
    let eventMapperMock: MockDefaultBrowserPromptEventMapping<DefaultBrowserManagerDebugEvent>!
    var sut: DefaultBrowserManager!

    init() {
        defaultBrowserService = MockCheckDefaultBrowserService()
        store = MockDefaultBrowserInfoStore()
        dataProviderMock = MockDateProvider()
        eventMapperMock = MockDefaultBrowserPromptEventMapping()
        sut = DefaultBrowserManager(
            defaultBrowserInfoStore: store,
            defaultBrowserEventMapper: eventMapperMock,
            defaultBrowserChecker: defaultBrowserService,
            dateProvider: dataProviderMock.getDate
        )
    }

    @Test("Check Browser Succeeds store and returns expected info",
        arguments: [
            true,
            false
        ]
    )
    func checkDefaultBrowserReturnsSuccess(_ value: Bool) throws {
        // GIVEN
        let timestamp: TimeInterval = 1741586108000 // March 10, 2025
        let date = Date(timeIntervalSince1970: timestamp)
        let dateProviderMock = MockDateProvider(date: date)
        defaultBrowserService.resultToReturn = .success(value)
        sut = DefaultBrowserManager(
            defaultBrowserInfoStore: store,
            defaultBrowserEventMapper: eventMapperMock,
            defaultBrowserChecker: defaultBrowserService,
            dateProvider: dateProviderMock.getDate
        )

        // WHEN
        let result = sut.defaultBrowserInfo()

        // THEN
        result
            .onNewValue { info in
                #expect(info.isDefaultBrowser == value)
                #expect(info.lastSuccessfulCheckDate == timestamp)
                #expect(info.lastAttemptedCheckDate == timestamp)
                #expect(info.numberOfTimesChecked  == 1)
                #expect(info.nextRetryAvailableDate == nil)
            }
            .onFailure { _ in
                Issue.record("Success expected")
            }
        #expect(store.didSetDefaultBrowserInfo)
    }

    @Test("Check Successful attempts update Browser Info data")
    func checkSuccessfulAttemptsUpdateBrowserInfoData() {
        // GIVEN 1st Check
        let timestamp: TimeInterval = 1741586108000 // March 10, 2025
        let date = Date(timeIntervalSince1970: timestamp)
        let dateProviderMock = MockDateProvider(date: date)
        defaultBrowserService.resultToReturn = .success(false)
        sut = DefaultBrowserManager(
            defaultBrowserInfoStore: store,
            defaultBrowserEventMapper: eventMapperMock,
            defaultBrowserChecker: defaultBrowserService,
            dateProvider: dateProviderMock.getDate
        )

        // WHEN
        var result = sut.defaultBrowserInfo()

        // THEN
        result
            .onNewValue { info in
                #expect(!info.isDefaultBrowser)
                #expect(info.lastSuccessfulCheckDate == timestamp)
                #expect(info.lastAttemptedCheckDate == timestamp)
                #expect(info.numberOfTimesChecked  == 1)
                #expect(info.nextRetryAvailableDate == nil)
            }
            .onFailure { _ in
                Issue.record("Success expected")
            }

        // GIVEN 2nd Check
        defaultBrowserService.resultToReturn = .success(true)
        dateProviderMock.advanceBy(TimeInterval.days(5))
        let lastSuccessfulTimestamp: TimeInterval = dateProviderMock.getDate().timeIntervalSince1970

        // WHEN
        result = sut.defaultBrowserInfo()

        // THEN
        result
            .onNewValue { info in
                #expect(info.isDefaultBrowser)
                #expect(info.lastSuccessfulCheckDate == lastSuccessfulTimestamp)
                #expect(info.lastAttemptedCheckDate == lastSuccessfulTimestamp)
                #expect(info.numberOfTimesChecked == 2)
                #expect(info.nextRetryAvailableDate == nil)
            }
            .onFailure { _ in
                Issue.record("Success expected")
            }
    }

    @Test("Check Max Attempts Exceeded Failure and no Browser Info stored does not update info and return nil object")
    func checkDefaultBrowserReturnsMaxNumberOfAttemptsExceededFailure() {
        // GIVEN
        let lastSuccessfulTimestamp: TimeInterval = 1741586108 // March 10, 2025
        let nextRetryTimestamp: TimeInterval = 1773122108000 // March 10, 2026
        let savedDefaultBrowserInfo = DefaultBrowserContext(
            isDefaultBrowser: true,
            lastSuccessfulCheckDate: lastSuccessfulTimestamp,
            lastAttemptedCheckDate: lastSuccessfulTimestamp,
            numberOfTimesChecked: 5,
            nextRetryAvailableDate: nextRetryTimestamp
        )
        defaultBrowserService.resultToReturn = .failure(.maxNumberOfAttemptsExceeded(nextRetryDate: Date(timeIntervalSince1970: nextRetryTimestamp)))
        store.defaultBrowserContext = savedDefaultBrowserInfo
        let dateProviderMock = MockDateProvider(date: Date(timeIntervalSince1970: lastSuccessfulTimestamp))
        dateProviderMock.advanceBy(TimeInterval.days(1))
        let lastAttemptedCheckTimestamp = dateProviderMock.getDate().timeIntervalSince1970
        let expectedDefaultBrowserInfo = DefaultBrowserContext(
            isDefaultBrowser: savedDefaultBrowserInfo.isDefaultBrowser,
            lastSuccessfulCheckDate: lastSuccessfulTimestamp,
            lastAttemptedCheckDate: lastAttemptedCheckTimestamp,
            numberOfTimesChecked: 6,
            nextRetryAvailableDate: nextRetryTimestamp
        )
        sut = DefaultBrowserManager(
            defaultBrowserInfoStore: store,
            defaultBrowserEventMapper: eventMapperMock,
            defaultBrowserChecker: defaultBrowserService,
            dateProvider: dateProviderMock.getDate
        )

        // WHEN
        let result = sut.defaultBrowserInfo()

        // THEN
        result
            .onNewValue { _ in
                Issue.record("Failure expected")
            }
            .onFailure { failure in
                #expect(failure == .rateLimitReached(updatedStoredInfo: expectedDefaultBrowserInfo))
            }

        #expect(store.didSetDefaultBrowserInfo)
    }

    @Test("Check When Max Attempts Exceeded Failure and no Browser Info stored do not update info and return nil object")
    func checkDefaultBrowserReturnsMaxNumberOfAttemptsExceededFailureAndNoInfoStored() {
        // GIVEN
        let timestamp: TimeInterval = 1773122108000 // March 8, 2026
        let date = Date(timeIntervalSince1970: timestamp)
        defaultBrowserService.resultToReturn = .failure(.maxNumberOfAttemptsExceeded(nextRetryDate: date))

        // WHEN
        let result = sut.defaultBrowserInfo()

        // THEN
        result
            .onNewValue { _ in
                Issue.record("Failure expected")
            }
            .onFailure { failure in
                #expect(failure == .rateLimitReached(updatedStoredInfo: nil))
            }

        #expect(!store.didSetDefaultBrowserInfo)
    }

    @Test("Check Default Browser Info is not stored when unknown error")
    func checkDefaultBrowserReturnsUnknownError() {
        // GIVEN
        let error = NSError(domain: #function, code: 0)
        defaultBrowserService.resultToReturn = .failure(.unknownError(error))

        // WHEN
        let result = sut.defaultBrowserInfo()

        // THEN
        result
            .onNewValue { _ in
                Issue.record("Failure expected")
            }
            .onFailure { failure in
                #expect(failure == .unknownError(error))
            }

        #expect(!store.didSetDefaultBrowserInfo)
    }

    @Test("Check Default Browser Info is not stored when notSupportedOnCurrentOSVersion error")
    func checkDefaultBrowserReturnsUnsupportedOS() {
        // GIVEN
        defaultBrowserService.resultToReturn = .failure(.notSupportedOnThisOSVersion)

        // WHEN
        let result = sut.defaultBrowserInfo()

        // THEN
        result
            .onNewValue { _ in
                Issue.record("Failure expected")
            }
            .onFailure { failure in
                #expect(failure == .notSupportedOnCurrentOSVersion)
            }

        #expect(!store.didSetDefaultBrowserInfo)
    }

}
