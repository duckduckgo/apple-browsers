//
//  CheckDefaultBrowserServiceTests.swift
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
import class UIKit.UIApplication
import Testing
import SetDefaultBrowserTestSupport
@testable import SetDefaultBrowserCore

@Suite("Set Default Browser - Check Default Browser Service")
struct CheckDefaultBrowserServiceTests {
    private static let isLowerThanPermittedVersion: Bool = {
        if #available(iOS 18.3, *) {
            false
        } else {
            true
        }
    }()

    @MainActor
    @Test(
        "Check Is Default Browser returns success when there are no errors",
        arguments: [
            true,
            false
        ]
    )
    @available(iOS 18.3, *)
    func checkDefaultBrowserReturnsSuccess(_ expectedDefaultBrowserValue: Bool) throws {
        // GIVEN
        let application = MockApplication()
        application.resultToReturn = .success(expectedDefaultBrowserValue)
        let sut = SystemCheckDefaultBrowserService(application: application)

        // WHEN
        let result = sut.isDefaultWebBrowser()

        // THEN
        #expect(try result.get() == expectedDefaultBrowserValue)
    }

    @MainActor
    @Test("Check is Default Browser returns maxNumberOfAttemptsExceeded when rateLimited error")
    @available(iOS 18.3, *)
    func checkDefaultBrowserReturnsMaxNumberOfAttemptsExceededFailure() throws {
        // GIVEN
        let timestamp: TimeInterval = 1773122108000 // 10th of March 2026
        let expectedRetryDate = Date(timeIntervalSince1970: timestamp)
        let systemError = NSError(
            domain: UIApplication.CategoryDefaultError.errorDomain,
            code: UIApplication.CategoryDefaultError.rateLimited.rawValue,
            userInfo: [
                UIApplication.CategoryDefaultError.retryAvailableDateErrorKey: expectedRetryDate,
            ]
        )
        let application = MockApplication()
        application.resultToReturn = .failure(systemError)
        let sut = SystemCheckDefaultBrowserService(application: application)

        // WHEN
        let result = sut.isDefaultWebBrowser()

        // THEN
        let error = try result.getError()
        guard case let CheckDefaultBrowserServiceError.maxNumberOfAttemptsExceeded(nextRetryDate) = error else {
            Issue.record("Should be maxNumberOfAttemptsExceeded error")
            return
        }
        #expect(nextRetryDate == expectedRetryDate)
    }

    @MainActor
    @Test("Check is Default Browser returns unknown failure when generic error")
    @available(iOS 18.3, *)
    func checkDefaultBrowserReturnsUnknownFailure() throws {
        // GIVEN
        let systemError = NSError(
            domain: UIApplication.CategoryDefaultError.errorDomain,
            code: 123456,
            userInfo: nil
        )
        let application = MockApplication()
        application.resultToReturn = .failure(systemError)
        let sut = SystemCheckDefaultBrowserService(application: application)

        // WHEN
        let result = sut.isDefaultWebBrowser()

        // THEN
        let error = try result.getError()
        guard case let CheckDefaultBrowserServiceError.unknownError(error) = error else {
            Issue.record("Should be maxNumberOfAttemptsExceeded error")
            return
        }
        #expect(error == systemError)
    }

    @MainActor
    @Test(.enabled(if: CheckDefaultBrowserServiceTests.isLowerThanPermittedVersion))
    func legacyCheckDefaultBrowserReturnsNotSupportedFailure() throws {
        // GIVEN
        let sut = SystemCheckDefaultBrowserService()

        // WHEN
        let result = sut.isDefaultWebBrowser()

        // THEN
        let error = try result.getError()
        #expect(error == .notSupportedOnThisOSVersion)
    }

}
