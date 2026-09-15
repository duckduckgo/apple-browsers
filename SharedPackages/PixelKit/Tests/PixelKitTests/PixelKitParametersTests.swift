//
//  PixelKitParametersTests.swift
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
@_spi(Testing) @testable import PixelKit

final class PixelKitParametersTests: XCTestCase {

    /// Test events for convenience
    ///
    private enum TestEvent: PixelKit.Event {
        case errorEvent(error: Error)

        var name: String {
            switch self {
            case .errorEvent:
                return "error_event"
            }
        }

        var parameters: [String: String]? {
            nil
        }

        var standardParameters: [PixelKitStandardParameter]? {
            switch self {
            case .errorEvent:
                return [.pixelSource]
            }
        }

    }

    /// Test that when firing pixels that include multiple levels of underlying error information, all levels
    /// are properly included in the pixel.
    ///
    func testUnderlyingErrorInformationParameters() {
        let underlyingError3 = NSError(domain: "test",
                                       code: 3,
                                       userInfo: [
                                           NSLocalizedDescriptionKey: "underlyingError3"
                                       ])
        let underlyingError2 = NSError(
            domain: "test",
            code: 2,
            userInfo: [
                NSUnderlyingErrorKey: underlyingError3 as NSError,
                NSLocalizedDescriptionKey: "underlyingError2"
            ])
        let topLevelError = NSError(
            domain: "test",
            code: 1,
            userInfo: [
                NSUnderlyingErrorKey: underlyingError2 as NSError,
                NSLocalizedDescriptionKey: "topLevelError"
            ])

        fire(TestEvent.errorEvent(error: topLevelError),
             frequency: .standard,
             and: .expect(pixelName: "m_mac_error_event",
                          error: topLevelError,
                          underlyingErrors: [underlyingError2, underlyingError3]),
             file: #filePath,
             line: #line)
    }

    // MARK: - SQLite result codes

    /// Core Data attaches its own result code under `NSSQLiteErrorDomain`, and legacy iOS pixels
    /// reported it by overwriting the chain's `ue`/`ud`. That behaviour is deliberately not carried
    /// over, so the key must be ignored entirely rather than mapped to `sqlrc`.
    /// Tech design: https://app.asana.com/1/137249556945/project/414235014887631/task/1218234709844266
    func testCoreDataSQLiteErrorDomainIsNotReported() {
        let error = NSError(domain: NSCocoaErrorDomain, code: 256, userInfo: ["NSSQLiteErrorDomain": NSNumber(value: 13)])

        var parameters = [String: String]()
        parameters.appendErrorPixelParams(error: error)

        XCTAssertNil(parameters[PixelKit.Parameters.underlyingErrorSQLiteCode])
        XCTAssertNil(parameters[PixelKit.Parameters.underlyingErrorSQLiteExtendedCode])
        XCTAssertNil(parameters[PixelKit.Parameters.underlyingErrorCode],
                     "and it must not be reported as an underlying error either")
        XCTAssertNil(parameters[PixelKit.Parameters.underlyingErrorDomain])
    }

    func testSecureStorageSQLiteResultCodesAreReported() {
        let error = NSError(domain: "secure.storage", code: 1, userInfo: [
            "SQLiteResultCode": NSNumber(value: 11),
            "SQLiteExtendedResultCode": NSNumber(value: 267)
        ])

        var parameters = [String: String]()
        parameters.appendErrorPixelParams(error: error)

        XCTAssertEqual(parameters[PixelKit.Parameters.underlyingErrorSQLiteCode], "11")
        XCTAssertEqual(parameters[PixelKit.Parameters.underlyingErrorSQLiteExtendedCode], "267")
    }

    /// A SQLite result code is not an error, so it must never appear as a link in the chain: an
    /// error carrying one reports its real chain, at its real depth, plus the code alongside it.
    func testSQLiteResultCodeDoesNotAddALinkToTheUnderlyingErrorChain() {
        let deepestError = NSError(domain: "deepest", code: 3)
        let middleError = NSError(domain: "middle", code: 2, userInfo: [NSUnderlyingErrorKey: deepestError])
        let topLevelError = NSError(domain: "top", code: 1, userInfo: [
            NSUnderlyingErrorKey: middleError,
            "SQLiteResultCode": NSNumber(value: 11)
        ])

        var parameters = [String: String]()
        parameters.appendErrorPixelParams(error: topLevelError)

        XCTAssertEqual(parameters[PixelKit.Parameters.errorCode], "1")
        XCTAssertEqual(parameters[PixelKit.Parameters.errorDomain], "top")
        XCTAssertEqual(parameters[PixelKit.Parameters.underlyingErrorCode], "2")
        XCTAssertEqual(parameters[PixelKit.Parameters.underlyingErrorDomain], "middle")
        XCTAssertEqual(parameters[PixelKit.Parameters.underlyingErrorCode + "2"], "3")
        XCTAssertEqual(parameters[PixelKit.Parameters.underlyingErrorDomain + "2"], "deepest",
                       "the deepest link must stay the real deepest error")
        XCTAssertNil(parameters[PixelKit.Parameters.underlyingErrorCode + "3"],
                     "the result code must not be reported as a further link in the chain")
        XCTAssertNil(parameters[PixelKit.Parameters.underlyingErrorDomain + "3"])
        XCTAssertEqual(parameters[PixelKit.Parameters.underlyingErrorSQLiteCode], "11",
                       "and it is reported alongside the chain")
    }

    /// The code is surfaced from anywhere in the chain, not just from the error the pixel is fired
    /// with, and the error carrying it is still reported as the chain link it actually is.
    func testSQLiteResultCodeCarriedByADeeperErrorIsReported() {
        let deepestError = NSError(domain: "deepest", code: 3, userInfo: ["SQLiteResultCode": NSNumber(value: 11)])
        let middleError = NSError(domain: "middle", code: 2, userInfo: [NSUnderlyingErrorKey: deepestError])
        let topLevelError = NSError(domain: "top", code: 1, userInfo: [NSUnderlyingErrorKey: middleError])

        var parameters = [String: String]()
        parameters.appendErrorPixelParams(error: topLevelError)

        XCTAssertEqual(parameters[PixelKit.Parameters.underlyingErrorSQLiteCode], "11")
        XCTAssertEqual(parameters[PixelKit.Parameters.underlyingErrorCode + "2"], "3",
                       "the error carrying the code is still a chain link")
        XCTAssertEqual(parameters[PixelKit.Parameters.underlyingErrorDomain + "2"], "deepest")
        XCTAssertNil(parameters[PixelKit.Parameters.underlyingErrorCode + "3"],
                     "and the code adds no link of its own")
    }

    /// Both codes have to come from the same error, so a plain code and an extended code carried by
    /// different errors in one chain can never be reported as if they were a pair.
    func testSQLiteResultCodesAreTakenFromTheOutermostErrorThatCarriesEither() {
        let deepestError = NSError(domain: "deepest", code: 3, userInfo: [
            "SQLiteResultCode": NSNumber(value: 5),
            "SQLiteExtendedResultCode": NSNumber(value: 267)
        ])
        let topLevelError = NSError(domain: "top", code: 1, userInfo: [
            NSUnderlyingErrorKey: deepestError,
            "SQLiteResultCode": NSNumber(value: 11)
        ])

        var parameters = [String: String]()
        parameters.appendErrorPixelParams(error: topLevelError)

        XCTAssertEqual(parameters[PixelKit.Parameters.underlyingErrorSQLiteCode], "11",
                       "the outermost error carrying a code wins")
        XCTAssertNil(parameters[PixelKit.Parameters.underlyingErrorSQLiteExtendedCode],
                     "the deeper error's extended code must not be paired with the outer plain code")
    }

    /// The chain walk is bounded, so an error that reports itself as its own underlying error
    /// terminates instead of spinning. Asserted on the lookup itself: `appendErrorPixelParams`
    /// also walks the chain to build `ue`/`ud`, and that recursion has no bound of its own.
    func testSQLiteResultCodeLookupTerminatesOnASelfReferencingChain() {
        let selfReferencingError = SelfReferencingError(domain: "cycle", code: 1)

        XCTAssertTrue(selfReferencingError.sqliteResultCodeParameters.isEmpty)
    }

    /// Reports itself as its own underlying error, forever.
    private final class SelfReferencingError: NSError {
        override var userInfo: [String: Any] {
            [NSUnderlyingErrorKey: self]
        }
    }
}
