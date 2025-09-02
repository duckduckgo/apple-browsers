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
        
        var errorDomain: String { "com.duckduckgo.test.ddgerror" }
        
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
            case .testErrorWithUnderlying: return "Test DDGError with underlying"
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
    
    private enum TestStandardError: Error {
        case testError
        case testErrorWithUnderlying(underlying: Error?)
    }
    
    // MARK: - Test Events
    
    private struct TestEventWithDDGError: PixelKitEventV2 {
        let name = "test_ddg_error_event"
        let error: (any DDGError)?
        var parameters: [String: String]? { nil }
    }
    
    private struct TestEventWithStandardError: PixelKitEvent {
        let name = "test_standard_error_event"
        let error: Error?
        var parameters: [String: String]? { nil }
    }
    
    // MARK: - Tests
    
    func testSimpleErrorComparison() async {
        // Create a simple DDGError
        let ddgError = TestDDGError.testError
        
        // Create equivalent standard error
        let standardError = TestStandardError.testError
        
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
        ) { _, parameters, _, _, _, _ in
            if ddgErrorParams == nil {
                ddgErrorParams = parameters
            } else {
                standardErrorParams = parameters
            }
        }
        
        // Fire pixel with DDGError
        let ddgEvent = TestEventWithDDGError(error: ddgError)
        pixelKit.fire(ddgEvent)
        
        // Fire pixel with standard Error (deprecated approach)
        let standardEvent = TestEventWithStandardError(error: standardError)
        pixelKit.fire(standardEvent)
        
        // Verify both approaches generate parameters
        XCTAssertNotNil(ddgErrorParams, "DDGError should generate parameters")
        XCTAssertNotNil(standardErrorParams, "Standard Error should generate parameters")
        
        // Compare error code parameters
        XCTAssertEqual(ddgErrorParams?["e"], String(ddgError.errorCode), "DDGError should set error code")
        XCTAssertNotNil(standardErrorParams?["e"], "Standard Error should set error code")
        
        // Compare error domain parameters
        XCTAssertEqual(ddgErrorParams?["d"], ddgError.errorDomain, "DDGError should set error domain")
        XCTAssertNotNil(standardErrorParams?["d"], "Standard Error should set error domain")
    }
    
    func testErrorWithUnderlyingErrorComparison() async {
        // Create underlying errors
        let underlyingDDGError = TestDDGError.testError
        let underlyingStandardError = TestStandardError.testError
        
        // Create main errors with underlying
        let ddgError = TestDDGError.testErrorWithUnderlying(underlying: underlyingDDGError)
        let standardNSError = NSError(
            domain: "com.duckduckgo.test.standard",
            code: 2001,
            userInfo: [NSUnderlyingErrorKey: NSError(domain: "com.duckduckgo.test.underlying", code: 3001)]
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
        ) { _, parameters, _, _, _, _ in
            if ddgErrorParams == nil {
                ddgErrorParams = parameters
            } else {
                standardErrorParams = parameters
            }
        }
        
        // Fire pixel with DDGError
        let ddgEvent = TestEventWithDDGError(error: ddgError)
        pixelKit.fire(ddgEvent)
        
        // Fire pixel with standard NSError
        let standardEvent = TestEventWithStandardError(error: standardNSError)
        pixelKit.fire(standardEvent)
        
        // Verify both approaches generate parameters
        XCTAssertNotNil(ddgErrorParams, "DDGError with underlying should generate parameters")
        XCTAssertNotNil(standardErrorParams, "Standard NSError with underlying should generate parameters")
        
        // Compare main error parameters
        XCTAssertEqual(ddgErrorParams?["e"], String(ddgError.errorCode), "DDGError should set main error code")
        XCTAssertEqual(standardErrorParams?["e"], String(standardNSError.code), "Standard Error should set main error code")
        
        XCTAssertEqual(ddgErrorParams?["d"], ddgError.errorDomain, "DDGError should set main error domain")
        XCTAssertEqual(standardErrorParams?["d"], standardNSError.domain, "Standard Error should set main error domain")
        
        // Compare underlying error parameters
        XCTAssertEqual(ddgErrorParams?["ue"], String(underlyingDDGError.errorCode), "DDGError should set underlying error code")
        XCTAssertNotNil(standardErrorParams?["ue"], "Standard Error should set underlying error code")
        
        XCTAssertEqual(ddgErrorParams?["ud"], underlyingDDGError.errorDomain, "DDGError should set underlying error domain")
        XCTAssertNotNil(standardErrorParams?["ud"], "Standard Error should set underlying error domain")
    }
    
    func testErrorChainComparison() async {
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
        ) { _, parameters, _, _, _, _ in
            if ddgErrorParams == nil {
                ddgErrorParams = parameters
            } else {
                standardErrorParams = parameters
            }
        }
        
        // Fire pixel with DDGError chain
        let ddgEvent = TestEventWithDDGError(error: topDDGError)
        pixelKit.fire(ddgEvent)
        
        // Fire pixel with NSError chain
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
    
    func testDeprecatedErrorWrapping() async {
        // Create a standard error
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
        ) { _, parameters, _, _, _, _ in
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
        
        // Verify the wrapper is working (it wraps the error in DDGErrorPixelKitWrapper)
        // The actual error info should be in the underlying error parameters
        XCTAssertNotNil(wrappedErrorParams?["ue"], "Wrapped error should preserve original as underlying")
    }
}
