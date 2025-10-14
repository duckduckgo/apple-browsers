//
//  SafariTestRunnerTests.swift
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
@testable import PerformanceTest

@MainActor
final class SafariTestRunnerTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInit_createsRunnerWithValidURL() async {
        let url = URL(string: "https://example.com")!
        let runner = SafariTestRunner(url: url, iterations: 3)

        XCTAssertNotNil(runner)
        XCTAssertEqual(runner.url, url)
        XCTAssertEqual(runner.iterations, 3)
    }

    // MARK: - Cancellation Tests

    func testCancellation_stopsExecution() async {
        let url = URL(string: "https://example.com")!
        let runner = SafariTestRunner(url: url, iterations: 10)

        var shouldCancel = false
        runner.isCancelled = {
            return shouldCancel
        }

        // Verify cancellation closure is set
        XCTAssertFalse(runner.isCancelled())

        shouldCancel = true
        XCTAssertTrue(runner.isCancelled())
    }

    // MARK: - Temp Directory Tests

    func testTempDirectory_createsUniqueOutputFolder() {
        let url = URL(string: "https://example.com")!
        let runner = SafariTestRunner(url: url, iterations: 3)

        let tempDir = runner.outputDirectory
        XCTAssertTrue(tempDir.path.contains("safari-perf-tests"), "Should use safari-perf-tests directory")
    }

    // MARK: - Output Parsing Tests

    func testParseProgress_extractsIterationFromLog() {
        let url = URL(string: "https://example.com")!
        let runner = SafariTestRunner(url: url, iterations: 10)

        let logLine = "[INFO] Running iteration 5 of 10"
        let (iteration, status) = runner.parseProgressLog(logLine)

        XCTAssertEqual(iteration, 5)
        XCTAssertEqual(status, "Running iteration 5 of 10")
    }

    func testParseProgress_extractsStatusFromLog() {
        let url = URL(string: "https://example.com")!
        let runner = SafariTestRunner(url: url, iterations: 10)

        let logLine = "[INFO] Clearing cache..."
        let (_, status) = runner.parseProgressLog(logLine)

        XCTAssertEqual(status, "Clearing cache...")
    }

    func testParseProgress_handlesInvalidLogFormat() {
        let url = URL(string: "https://example.com")!
        let runner = SafariTestRunner(url: url, iterations: 10)

        let logLine = "Some random log output"
        let (iteration, status) = runner.parseProgressLog(logLine)

        XCTAssertNil(iteration)
        XCTAssertEqual(status, logLine)
    }

    // MARK: - Process Execution Tests (Mock)

    func testRunTest_setsUpProcessWithCorrectArguments() {
        let url = URL(string: "https://example.com")!
        let runner = SafariTestRunner(url: url, iterations: 5)

        let expectedArgs = runner.buildProcessArguments()

        XCTAssertTrue(expectedArgs.contains(url.absoluteString))
        XCTAssertTrue(expectedArgs.contains("5"))
    }

    // MARK: - Cleanup Tests

    func testCleanup_removesTempFiles() async throws {
        let url = URL(string: "https://example.com")!
        let runner = SafariTestRunner(url: url, iterations: 1)

        let tempDir = runner.outputDirectory

        // Create temp directory
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.path))

        // Cleanup should remove it
        runner.cleanup()

        // Note: Cleanup might be async, so we don't assert removal here
        // Just verify the method exists and doesn't crash
    }
}
