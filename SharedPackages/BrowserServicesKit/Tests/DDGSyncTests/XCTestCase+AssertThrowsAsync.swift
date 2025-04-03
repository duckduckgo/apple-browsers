//
//  XCTestCase+AssertThrowsAsync.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

extension XCTestCase {
    func assertThrowsError<E: Error & Equatable, T>(_ expectedError: E, _ expression: () async throws -> T, file: StaticString = #file, line: UInt = #line) async {
        do {
            _ = try await expression()
            XCTFail("Expected error \(expectedError) was not thrown", file: file, line: line)
        } catch {
            guard let error = error as? E else {
                XCTFail("Unexpected error \(error) was thrown", file: file, line: line)
                return
            }
            XCTAssertEqual(error, expectedError, file: file, line: line)
        }
    }

    func assertThrowsAnyError<T>(_ expression: () async throws -> T, errorHandler: (Error) -> Void = { _ in }, file: StaticString = #file, line: UInt = #line) async {
        do {
            _ = try await expression()
            XCTFail("Expected error was not thrown", file: file, line: line)
        } catch {
            errorHandler(error)
        }
    }
}
