//
//  DDGErrorPixelComparisonTests.swift
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

import XCTest
@testable import PixelKit
import Common

final class DDGErrorPixelComparisonTests: XCTestCase {

    private func userDefaults() -> UserDefaults {
        UserDefaults(suiteName: "testing_\(UUID().uuidString)")!
    }

    // MARK: - Test DDGError

    private enum TestDDGError: DDGError {

        case testError
        case testErrorWithUnderlying(underlying: Error?)

        static var errorDomain: String { "com.duckduckgo.test.ddgerror" }

        var errorCode: Int {
            switch self {
            case .testError: return 1001
            case .testErrorWithUnderlying: return 1002
            }
        }

        var underlyingError: Error? {
            switch self {
            case .testError: return nil
            case .testErrorWithUnderlying(let underlying): return underlying
            }
        }

        var description: String {
            switch self {
            case .testError: return "Test DDGError"
            case .testErrorWithUnderlying(let underlying): return "Test DDGError with underlying error: \(String(describing: underlying))"
            }
        }

        static func == (lhs: DDGErrorPixelComparisonTests.TestDDGError, rhs: DDGErrorPixelComparisonTests.TestDDGError) -> Bool {
            switch (lhs, rhs) {
            case (.testError, .testError): return true
            case (.testErrorWithUnderlying(let lhsError), .testErrorWithUnderlying(let rhsError)):
                return String(describing: lhsError) == String(describing: rhsError)
            default: return false
            }
        }
    }

    // MARK: - Test Standard Error

    private enum TestStandardError: Error, CustomNSError {
        case testError
        case testErrorWithUnderlying(underlying: Error?)

        static var errorDomain: String { "com.duckduckgo.test.standard" }

        var errorCode: Int {
            switch self {
            case .testError: return 2001
            case .testErrorWithUnderlying: return 2002
            }
        }

        var errorUserInfo: [String: Any] {
            switch self {
            case .testError:
                return [:]
            case .testErrorWithUnderlying(let underlying):
                if let underlying = underlying {
                    return [NSUnderlyingErrorKey: underlying]
                }
                return [:]
            }
        }
    }

    // MARK: - Test Events

    private struct TestEventWithDDGError: PixelKitEvent {
        let name = "test_ddg_error_event"
        let error: Error?
        var parameters: [String: String]? { nil }
    }

    private struct TestEventWithStandardError: PixelKitEvent {
        let name = "test_standard_error_event"
        let error: Error?
        var parameters: [String: String]? { nil }
    }

    // MARK: - Tests

    func testSimpleErrorComparison() {
        // Create a simple DDGError
        let ddgError = TestDDGError.testError

        // Create equivalent standard error (CustomNSError)
        let standardError = TestStandardError.testError

        // Capture parameters for both approaches
        var ddgErrorParams: [String: String]?
        var standardErrorParams: [String: String]?
        var callCount = 0

        // Setup PixelKit with callback to capture parameters
        let pixelKit = PixelKit(
            dryRun: false,
            appVersion: "1.0.0",
            defaultHeaders: [:],
            dailyPixelCalendar: nil,
            defaults: userDefaults()
        ) { pixelName, headers, parameters, _, _, _ in
            print("DEBUG: FireRequest called #\(callCount + 1) for pixel: \(pixelName) with parameters: \(parameters)")
            callCount += 1
            if ddgErrorParams == nil {
                ddgErrorParams = parameters
            } else {
                standardErrorParams = parameters
            }
        }

        // Fire pixel with DDGError
        let ddgEvent = TestEventWithDDGError(error: ddgError)
        pixelKit.fire(ddgEvent)

        // Fire pixel with standard Error
        let standardEvent = TestEventWithStandardError(error: standardError)
        pixelKit.fire(standardEvent)

        // Verify both approaches generate parameters
        XCTAssertNotNil(ddgErrorParams, "DDGError should generate parameters")
        XCTAssertNotNil(standardErrorParams, "Standard Error should generate parameters")

        // Compare error code parameters
        XCTAssertEqual(ddgErrorParams?["e"], String(ddgError.errorCode), "DDGError should set error code")
        XCTAssertNotNil(standardErrorParams?["e"], "Standard Error should set error code")

        // Compare error domain parameters
        XCTAssertEqual(ddgErrorParams?["d"], TestDDGError.errorDomain, "DDGError should set error domain")
        XCTAssertNotNil(standardErrorParams?["d"], "Standard Error should set error domain")
    }

    func testErrorWithUnderlyingErrorComparison() {
        // Create underlying errors
        let underlyingDDGError = TestDDGError.testError
        let underlyingStandardError = TestStandardError.testError

        // Create main errors with underlying
        let ddgError = TestDDGError.testErrorWithUnderlying(underlying: underlyingDDGError)
        let standardError = TestStandardError.testErrorWithUnderlying(underlying: underlyingStandardError)

        // Capture parameters for both approaches
        var ddgErrorParams: [String: String]?
        var standardErrorParams: [String: String]?

        // Setup PixelKit with callback to capture parameters
        let pixelKit = PixelKit(
            dryRun: false,
            appVersion: "1.0.0",
            defaultHeaders: [:],
            dailyPixelCalendar: nil,
            defaults: userDefaults()
        ) { _, _, parameters, _, _, _ in
            if ddgErrorParams == nil {
                ddgErrorParams = parameters
            } else {
                standardErrorParams = parameters
            }
        }

        // Fire pixel with DDGError
        let ddgEvent = TestEventWithDDGError(error: ddgError)
        pixelKit.fire(ddgEvent)

        // Fire pixel with standard NSError (use withDDGError parameter to pass the error)
        let standardEvent = TestEventWithStandardError(error: standardError)
        pixelKit.fire(standardEvent)

        // Verify both approaches generate parameters
        XCTAssertNotNil(ddgErrorParams, "DDGError with underlying should generate parameters")
        XCTAssertNotNil(standardErrorParams, "Standard NSError with underlying should generate parameters")

        // Compare main error parameters
        XCTAssertEqual(ddgErrorParams?["e"], String(ddgError.errorCode), "DDGError should set main error code")
        XCTAssertEqual(standardErrorParams?["e"], String(standardError.errorCode), "Standard Error should set main error code")

        XCTAssertEqual(ddgErrorParams?["d"], ddgError.errorDomain, "DDGError should set main error domain")
        XCTAssertEqual(standardErrorParams?["d"], TestStandardError.errorDomain, "Standard Error should set main error domain")

        // Compare underlying error parameters
        XCTAssertEqual(ddgErrorParams?["ue"], String(underlyingDDGError.errorCode), "DDGError should set underlying error code")
        XCTAssertNotNil(standardErrorParams?["ue"], "Standard Error should set underlying error code")

        XCTAssertEqual(ddgErrorParams?["ud"], underlyingDDGError.errorDomain, "DDGError should set underlying error domain")
        XCTAssertNotNil(standardErrorParams?["ud"], "Standard Error should set underlying error domain")
    }

    func testErrorChainComparison() {
        // Create a chain of DDGErrors
        let rootDDGError = TestDDGError.testError
        let middleDDGError = TestDDGError.testErrorWithUnderlying(underlying: rootDDGError)
        let topDDGError = TestDDGError.testErrorWithUnderlying(underlying: middleDDGError)

        // Create equivalent chain with NSError
        let rootNSError = NSError(domain: "com.duckduckgo.root", code: 3001)
        let middleNSError = NSError(
            domain: "com.duckduckgo.middle",
            code: 2001,
            userInfo: [NSUnderlyingErrorKey: rootNSError]
        )
        let topNSError = NSError(
            domain: "com.duckduckgo.top",
            code: 1001,
            userInfo: [NSUnderlyingErrorKey: middleNSError]
        )

        // Capture parameters for both approaches
        var ddgErrorParams: [String: String]?
        var standardErrorParams: [String: String]?

        // Setup PixelKit with callback to capture parameters
        let pixelKit = PixelKit(
            dryRun: false,
            appVersion: "1.0.0",
            defaultHeaders: [:],
            dailyPixelCalendar: nil,
            defaults: userDefaults()
        ) { _, _, parameters, _, _, _ in
            if ddgErrorParams == nil {
                ddgErrorParams = parameters
            } else {
                standardErrorParams = parameters
            }
        }

        // Fire pixel with DDGError chain
        let ddgEvent = TestEventWithDDGError(error: topDDGError)
        pixelKit.fire(ddgEvent)

        // Fire pixel with NSError chain (use withDDGError parameter to pass the error)
        let standardEvent = TestEventWithStandardError(error: topNSError)
        pixelKit.fire(standardEvent)

        // Verify both approaches generate parameters
        XCTAssertNotNil(ddgErrorParams, "DDGError chain should generate parameters")
        XCTAssertNotNil(standardErrorParams, "NSError chain should generate parameters")

        // Compare top-level error
        XCTAssertNotNil(ddgErrorParams?["e"], "DDGError should set top error code")
        XCTAssertNotNil(ddgErrorParams?["d"], "DDGError should set top error domain")
        XCTAssertEqual(standardErrorParams?["e"], String(topNSError.code), "NSError should set top error code")
        XCTAssertEqual(standardErrorParams?["d"], topNSError.domain, "NSError should set top error domain")

        // Compare first underlying error (middle)
        XCTAssertNotNil(ddgErrorParams?["ue"], "DDGError should set first underlying error code")
        XCTAssertNotNil(ddgErrorParams?["ud"], "DDGError should set first underlying error domain")
        XCTAssertEqual(standardErrorParams?["ue"], String(middleNSError.code), "NSError should set first underlying error code")
        XCTAssertEqual(standardErrorParams?["ud"], middleNSError.domain, "NSError should set first underlying error domain")

        // Compare second underlying error (root)
        XCTAssertNotNil(ddgErrorParams?["ue2"], "DDGError should set second underlying error code")
        XCTAssertNotNil(ddgErrorParams?["ud2"], "DDGError should set second underlying error domain")
        XCTAssertEqual(standardErrorParams?["ue2"], String(rootNSError.code), "NSError should set second underlying error code")
        XCTAssertEqual(standardErrorParams?["ud2"], rootNSError.domain, "NSError should set second underlying error domain")
    }

    func testErrorWrapping() {
        // Create a standard error (not an NSError, just a plain Swift Error)
        let standardError = TestStandardError.testError

        // Capture parameters when using deprecated method
        var wrappedErrorParams: [String: String]?

        // Setup PixelKit with callback to capture parameters
        let pixelKit = PixelKit(
            dryRun: false,
            appVersion: "1.0.0",
            defaultHeaders: [:],
            dailyPixelCalendar: nil,
            defaults: userDefaults()
        ) { _, _, parameters, _, _, _ in
            wrappedErrorParams = parameters
        }

        // Use the deprecated fire method with standard Error
        let standardEvent = TestEventWithStandardError(error: standardError)
        pixelKit.fire(standardEvent)

        // Verify wrapped error generates parameters
        XCTAssertNotNil(wrappedErrorParams, "Wrapped standard error should generate parameters")

        // The wrapper should create proper error parameters
        XCTAssertNotNil(wrappedErrorParams?["e"], "Wrapped error should have error code")
        XCTAssertNotNil(wrappedErrorParams?["d"], "Wrapped error should have error domain")

        // When wrapping a standard error in DDGErrorPixelKitWrapper, the implementation
        // unwraps it and uses the original error directly (see line 762-765 in PixelKit.swift)
        // So the error appears as the main error, not as an underlying error
        XCTAssertEqual(wrappedErrorParams?["e"], String(standardError.errorCode), "Should use wrapped error's code")
        XCTAssertEqual(wrappedErrorParams?["d"], TestStandardError.errorDomain, "Should use wrapped error's domain")
    }
}
