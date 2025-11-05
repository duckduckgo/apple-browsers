//
//  DDGErrorTests.swift
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
import Foundation
@testable import Common

final class DDGErrorTests: XCTestCase {

    // MARK: - Test Types

    enum TestError: DDGError {
        case simpleError(code: Int, description: String)
        case errorWithUnderlying(code: Int, description: String)

        static var errorDomain: String { "TestErrorDomain" }

        var errorCode: Int {
            switch self {
            case .simpleError(let code, _):
                return code
            case .errorWithUnderlying(let code, _):
                return code
            }
        }

        var underlyingError: Error? {
            switch self {
            case .simpleError:
                return nil
            case .errorWithUnderlying:
                return SimpleError(message: "Underlying error")
            }
        }

        var description: String {
            switch self {
            case .simpleError(_, let description):
                return description
            case .errorWithUnderlying(_, let description):
                return description
            }
        }
    }

    struct SimpleError: Error {
        let message: String
    }

    // MARK: - DDGError Protocol Tests

    func testDDGErrorBasicProperties() {
        let error = TestError.simpleError(code: 100, description: "Test error")

        XCTAssertEqual(TestError.errorDomain, "TestErrorDomain")
        XCTAssertEqual(error.errorCode, 100)
        XCTAssertEqual(error.description, "Test error")
        XCTAssertNil(error.underlyingError)
    }

    func testDDGErrorWithUnderlyingError() {
        let error = TestError.errorWithUnderlying(code: 200, description: "Main error")

        XCTAssertEqual(error.errorCode, 200)
        XCTAssertEqual(error.description, "Main error")
        XCTAssertNotNil(error.underlyingError)
    }

    func testDDGErrorEquality() {
        let error1 = TestError.simpleError(code: 100, description: "Same error")
        let error2 = TestError.simpleError(code: 100, description: "Same error")
        let error3 = TestError.simpleError(code: 101, description: "Different error")

        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
    }

    // MARK: - Errors Chain Tests

    func testErrorsChainWithSingleError() {
        let error = TestError.simpleError(code: 100, description: "Single error")
        let chain = error.errorsChain

        XCTAssertEqual(chain.count, 1)
        XCTAssertTrue(chain[0] is TestError)
        XCTAssertEqual((chain[0] as! TestError).errorCode, 100)
    }

    func testErrorsChainWithMultipleDDGErrors() {
        let error = TestError.errorWithUnderlying(code: 3, description: "Top error")

        let chain = error.errorsChain

        XCTAssertEqual(chain.count, 2)
        XCTAssertEqual((chain[0] as! TestError).errorCode, 3)
        XCTAssertTrue(chain[1] is SimpleError)
    }

    func testErrorsChainWithMixedErrorTypes() {
        let ddgError = TestError.errorWithUnderlying(code: 100, description: "DDG error")

        let chain = ddgError.errorsChain

        XCTAssertEqual(chain.count, 2)
        XCTAssertTrue(chain[0] is TestError)
        XCTAssertTrue(chain[1] is SimpleError)
        XCTAssertEqual((chain[0] as! TestError).errorCode, 100)
        XCTAssertEqual((chain[1] as! SimpleError).message, "Underlying error")
    }

    // MARK: - Errors Chain Description Tests

    func testErrorsChainDescriptionWithSingleError() {
        let error = TestError.simpleError(code: 100, description: "Single error")
        let description = error.errorsChainDescription

        XCTAssertEqual(description, "- Single error")
    }

    func testErrorsChainDescriptionWithMultipleErrors() {
        let error = TestError.errorWithUnderlying(code: 3, description: "Top error")

        let description = error.errorsChainDescription
        let expected = "- Top error\n- SimpleError(message: \"Underlying error\")"

        XCTAssertEqual(description, expected)
    }

    func testErrorsChainDescriptionWithMixedErrorTypes() {
        let ddgError = TestError.errorWithUnderlying(code: 100, description: "DDG error")

        let description = ddgError.errorsChainDescription

        XCTAssertTrue(description.contains("- DDG error"))
        XCTAssertTrue(description.contains("- SimpleError(message: \"Underlying error\")"))
    }

    // MARK: - CustomNSError Conformance Tests

    func testDDGErrorUserInfo() {
        let error = TestError.errorWithUnderlying(code: 100, description: "Main error")

        let userInfo = error.errorUserInfo

        XCTAssertEqual(userInfo[NSDebugDescriptionErrorKey] as? String, "Main error")
        XCTAssertNotNil(userInfo[NSUnderlyingErrorKey])
        XCTAssertTrue(userInfo[NSUnderlyingErrorKey] is SimpleError)
    }

    func testDDGErrorUserInfoWithoutUnderlyingError() {
        let error = TestError.simpleError(code: 100, description: "Main error")

        let userInfo = error.errorUserInfo

        XCTAssertEqual(userInfo[NSDebugDescriptionErrorKey] as? String, "Main error")
        XCTAssertNil(userInfo[NSUnderlyingErrorKey]) // Should not be present when there is no underlying error
    }
}
