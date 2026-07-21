//
//  ConfigurationValidationTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
@testable import PIRDebugKit

final class ConfigurationValidationTests: XCTestCase {

    private func makeConfiguration(operationAwaitTime: TimeInterval) throws -> PIRDebugSessionConfiguration {
        try PIRDebugSessionConfiguration(
            rulesSource: InlineJSONBrokerRulesProvider(json: "{}"),
            authManager: StaticTokenAuthenticationManager(),
            operationAwaitTime: operationAwaitTime)
    }

    func testOperationAwaitTimeZeroIsAccepted() throws {
        let config = try makeConfiguration(operationAwaitTime: 0)
        XCTAssertEqual(config.operationAwaitTime, 0)
    }

    func testOperationAwaitTimeFractionalIsAccepted() throws {
        let config = try makeConfiguration(operationAwaitTime: 0.5)
        XCTAssertEqual(config.operationAwaitTime, 0.5, accuracy: 0.0001)
    }

    func testOperationAwaitTimeNegativeIsRejected() {
        XCTAssertThrowsError(try makeConfiguration(operationAwaitTime: -1)) { error in
            guard case PIRDebugError.negativeOperationAwaitTime(let value) = error else {
                return XCTFail("Expected negativeOperationAwaitTime, got \(error)")
            }
            XCTAssertEqual(value, -1)
        }
    }
}
