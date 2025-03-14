//
//  DefaultBrowserManagerTesting.swift
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
@testable import DuckDuckGo

@MainActor
final class DefaultBrowserManagerTesting {
    let defaultBrowserService: MockCheckDefaultBrowserService!
    let timeTraveller: TimeTraveller!
    let store: MockDefaultBrowserInfoStore
    var sut: DefaultBrowserManager!

    init() {
        defaultBrowserService = MockCheckDefaultBrowserService()
        store = MockDefaultBrowserInfoStore()
        timeTraveller = TimeTraveller()
        sut = DefaultBrowserManager(
            defaultBrowserChecker: defaultBrowserService,
            defaultBrowserInfoStore: store,
            dateProvider: timeTraveller.getDate
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
        let timeTraveller = TimeTraveller(date: date)
        defaultBrowserService.resultToReturn = .success(value)
        sut = DefaultBrowserManager(
            defaultBrowserChecker: defaultBrowserService,
            defaultBrowserInfoStore: store,
            dateProvider: timeTraveller.getDate
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
        let timeTraveller = TimeTraveller(date: date)
        defaultBrowserService.resultToReturn = .success(false)
        sut = DefaultBrowserManager(
            defaultBrowserChecker: defaultBrowserService,
            defaultBrowserInfoStore: store,
            dateProvider: timeTraveller.getDate
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
        timeTraveller.advanceBy(TimeInterval.days(5))
        let lastSuccessfulTimestamp: TimeInterval = timeTraveller.getDate().timeIntervalSince1970

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
        let savedDefaultBrowserInfo = DefaultBrowserInfo(
            isDefaultBrowser: true,
            lastSuccessfulCheckDate: lastSuccessfulTimestamp,
            lastAttemptedCheckDate: lastSuccessfulTimestamp,
            numberOfTimesChecked: 5,
            nextRetryAvailableDate: nextRetryTimestamp
        )
        defaultBrowserService.resultToReturn = .failure(.maxNumberOfAttemptsExceeded(nextRetryDate: Date(timeIntervalSince1970: nextRetryTimestamp)))
        store.defaultBrowserInfo = savedDefaultBrowserInfo
        let timeTraveller = TimeTraveller(date: Date(timeIntervalSince1970: lastSuccessfulTimestamp))
        timeTraveller.advanceBy(TimeInterval.day)
        let lastAttemptedCheckTimestamp = timeTraveller.getDate().timeIntervalSince1970
        let expectedDefaultBrowserInfo = DefaultBrowserInfo(
            isDefaultBrowser: savedDefaultBrowserInfo.isDefaultBrowser,
            lastSuccessfulCheckDate: lastSuccessfulTimestamp,
            lastAttemptedCheckDate: lastAttemptedCheckTimestamp,
            numberOfTimesChecked: 6,
            nextRetryAvailableDate: nextRetryTimestamp
        )
        sut = DefaultBrowserManager(
            defaultBrowserChecker: defaultBrowserService,
            defaultBrowserInfoStore: store,
            dateProvider: timeTraveller.getDate
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

final class MockCheckDefaultBrowserService: CheckDefaultBrowserService {
    var resultToReturn: Result<Bool, CheckDefaultBrowserServiceError> = .success(true)

    func isDefaultWebBrowser() -> Result<Bool, DuckDuckGo.CheckDefaultBrowserServiceError> {
        resultToReturn
    }

}

final class MockDefaultBrowserInfoStore: DefaultBrowserInfoStorage {
    private(set) var didSetDefaultBrowserInfo = false

    var defaultBrowserInfo: DuckDuckGo.DefaultBrowserInfo? {
        didSet {
            didSetDefaultBrowserInfo = true
        }
    }
}
