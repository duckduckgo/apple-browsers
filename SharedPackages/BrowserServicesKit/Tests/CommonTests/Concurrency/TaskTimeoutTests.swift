//
//  TaskTimeoutTests.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
@testable import Common

final class TaskTimeoutTests: XCTestCase {

    func testWithTimeoutPasses() async throws {
        struct TestError: Error {
            init() {
                fatalError("should never timeout")
            }
        }
        let result = try await withTimeout(1, throwing: TestError()) {
            try await Task.sleep(interval: 0.0001)
            return 1
        }

        XCTAssertEqual(result, 1)
    }

    func testWithTimeoutThrowsTimeoutError() async {
        do {
            try await withTimeout(0.0001) {
                for await _ in AsyncStream<Never>.never {}
                throw CancellationError()
            }

            XCTFail("should timeout")
        } catch {
        }
    }

    // MARK: - Task.value(cancellingTaskOnTimeout:) Tests

    func testTaskValueWithTimeoutSucceeds() async throws {
        // Given - a task that completes quickly
        let task = Task<Int, Error> {
            try await Task.sleep(interval: 0.0001)
            return 42
        }

        // When - waiting for value with timeout
        let result = try await task.value(cancellingTaskOnTimeout: 1.0)

        // Then - should return the value
        XCTAssertEqual(result, 42)
    }

    func testTaskValueWithTimeoutThrowsTimeoutError() async {
        // Given - a long-running task
        let task = Task<Int, Error> {
            try await Task.sleep(interval: 10.0)
            return 42
        }

        // When - waiting with short timeout
        do {
            _ = try await task.value(cancellingTaskOnTimeout: 0.0001)
            XCTFail("should timeout")
        } catch is TimeoutError {
            // Then - should throw TimeoutError
        } catch {
            XCTFail("should throw TimeoutError, got: \(error)")
        }
    }

    func testTaskValueWithTimeoutCancelsTask() async {
        // Given - a task that tracks cancellation
        let taskCancelledExpectation = expectation(description: "Task cancelled")
        let task = Task<Int, Error> {
            defer {
                if Task.isCancelled {
                    taskCancelledExpectation.fulfill()
                }
            }
            try await Task.sleep(interval: 10.0)
            return 42
        }

        // When - waiting with short timeout
        do {
            _ = try await task.value(cancellingTaskOnTimeout: 0.0001)
            XCTFail("should timeout")
        } catch is TimeoutError {
            // Then - task should be cancelled
            await fulfillment(of: [taskCancelledExpectation], timeout: 1.0)
        } catch {
            XCTFail("should throw TimeoutError, got: \(error)")
        }
    }

    func testTaskValueWithTimeoutPropagatesTaskError() async {
        // Given - a task that throws an error
        struct CustomError: Error, Equatable {}
        let task = Task<Int, Error> {
            try await Task.sleep(interval: 0.0001)
            throw CustomError()
        }

        // When - waiting for value with timeout
        do {
            _ = try await task.value(cancellingTaskOnTimeout: 1.0)
            XCTFail("should throw CustomError")
        } catch is CustomError {
            // Then - should propagate the task's error
        } catch {
            XCTFail("should throw CustomError, got: \(error)")
        }
    }

    // MARK: - Task.value(cancellingTaskOnTimeout:) Tests for Non-Throwing Tasks

    func testNonThrowingTaskValueWithTimeoutSucceeds() async throws {
        // Given - a non-throwing task that completes quickly
        let task = Task<Int, Never> {
            await Task.yield()
            return 42
        }

        // When - waiting for value with timeout
        let result = try await task.value(cancellingTaskOnTimeout: 1.0)

        // Then - should return the value
        XCTAssertEqual(result, 42)
    }

    func testNonThrowingTaskValueWithTimeoutThrowsTimeoutError() async {
        // Given - a long-running non-throwing task
        let task = Task {
            try await Task.sleep(interval: 10.0)
            return 42
        }

        // When - waiting with short timeout
        do {
            _ = try await task.value(cancellingTaskOnTimeout: 0.0001)
            XCTFail("should timeout")
        } catch is TimeoutError {
            // Then - should throw TimeoutError
        } catch {
            XCTFail("should throw TimeoutError, got: \(error)")
        }
    }

    func testNonThrowingTaskValueWithTimeoutCancelsTask() async {
        // Given - a non-throwing task that tracks cancellation
        let taskCancelledExpectation = expectation(description: "Task cancelled")
        let task = Task {
            defer {
                if Task.isCancelled {
                    taskCancelledExpectation.fulfill()
                }
            }
            try await Task.sleep(interval: 10.0)
            return 42
        }

        // When - waiting with short timeout
        do {
            _ = try await task.value(cancellingTaskOnTimeout: 0.0001)
            XCTFail("should timeout")
        } catch is TimeoutError {
            // Then - task should be cancelled
            await fulfillment(of: [taskCancelledExpectation], timeout: 1.0)
        } catch {
            XCTFail("should throw TimeoutError, got: \(error)")
        }
    }

}
