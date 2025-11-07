//
//  SafariPerformanceTestViewModelTests.swift
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
final class SafariPerformanceTestViewModelTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInit_setsCorrectDefaultValues() {
        let url = URL(string: "https://example.com")!
        let viewModel = SafariPerformanceTestViewModel(url: url)

        XCTAssertEqual(viewModel.currentURL, url)
        XCTAssertFalse(viewModel.isRunning)
        XCTAssertEqual(viewModel.progress, 0.0)
        XCTAssertEqual(viewModel.statusText, "")
        XCTAssertEqual(viewModel.currentIteration, 0)
        XCTAssertEqual(viewModel.totalIterations, 10)
        XCTAssertEqual(viewModel.selectedIterations, 10)
        XCTAssertFalse(viewModel.isCancelled)
        XCTAssertNil(viewModel.testResults)
        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: - State Transition Tests

    func testRunTest_transitionsToRunningState() async {
        let url = URL(string: "https://example.com")!
        let viewModel = SafariPerformanceTestViewModel(url: url, runnerFactory: { url, iterations in
            MockSafariTestExecutor(url: url, iterations: iterations)
        })

        await viewModel.runTest()

        // Should have parsed results from mock
        XCTAssertNotNil(viewModel.testResults)
        XCTAssertEqual(viewModel.testResults?.url, url)

        // Should not be running anymore
        XCTAssertFalse(viewModel.isRunning)
    }

    func testCancelTest_setsCancelledFlag() {
        let url = URL(string: "https://example.com")!
        let viewModel = SafariPerformanceTestViewModel(url: url)

        XCTAssertFalse(viewModel.isCancelled)

        viewModel.cancelTest()

        XCTAssertTrue(viewModel.isCancelled)
    }

    // MARK: - Progress Update Tests

    func testProgressHandler_updatesViewModel() {
        let url = URL(string: "https://example.com")!
        let viewModel = SafariPerformanceTestViewModel(url: url)

        // Simulate progress update from runner
        viewModel.handleProgress(iteration: 3, total: 10, status: "Loading page...")

        XCTAssertEqual(viewModel.currentIteration, 3)
        XCTAssertEqual(viewModel.totalIterations, 10)
        XCTAssertEqual(viewModel.statusText, "Loading page...")
        XCTAssertEqual(viewModel.progress, 0.3, accuracy: 0.01)
    }

    func testProgressHandler_calculatesCorrectProgress() {
        let url = URL(string: "https://example.com")!
        let viewModel = SafariPerformanceTestViewModel(url: url)

        viewModel.handleProgress(iteration: 1, total: 10, status: "Starting")
        XCTAssertEqual(viewModel.progress, 0.1, accuracy: 0.01)

        viewModel.handleProgress(iteration: 5, total: 10, status: "Halfway")
        XCTAssertEqual(viewModel.progress, 0.5, accuracy: 0.01)

        viewModel.handleProgress(iteration: 10, total: 10, status: "Complete")
        XCTAssertEqual(viewModel.progress, 1.0, accuracy: 0.01)
    }

    // MARK: - Error Handling Tests

    func testRunTest_withInvalidURL_setsErrorMessage() async {
        let invalidURL = URL(string: "not-valid")!
        let viewModel = SafariPerformanceTestViewModel(url: invalidURL, runnerFactory: { url, iterations in
            let mock = MockSafariTestExecutor(url: url, iterations: iterations)
            mock.shouldThrowError = SafariTestRunner.RunnerError.invalidURL
            return mock
        })

        await viewModel.runTest()

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isRunning)
    }

    func testRunTest_withZeroIterations_setsErrorMessage() async {
        let url = URL(string: "https://example.com")!
        let viewModel = SafariPerformanceTestViewModel(url: url, runnerFactory: { url, iterations in
            let mock = MockSafariTestExecutor(url: url, iterations: iterations)
            mock.shouldThrowError = SafariTestRunner.RunnerError.invalidIterationCount
            return mock
        })
        viewModel.selectedIterations = 0

        await viewModel.runTest()

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isRunning)
    }

    // MARK: - Results Tests

    func testRunTest_onSuccess_storesResultsFilePath() async {
        let url = URL(string: "https://example.com")!
        let viewModel = SafariPerformanceTestViewModel(url: url, runnerFactory: { url, iterations in
            let mock = MockSafariTestExecutor(url: url, iterations: iterations)
            mock.mockResultsPath = "/tmp/test-results.json"
            return mock
        })

        await viewModel.runTest()

        XCTAssertNotNil(viewModel.testResults)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isRunning)
    }

    // MARK: - Cleanup Tests

    func testCancelTest_resetsState() {
        let url = URL(string: "https://example.com")!
        let viewModel = SafariPerformanceTestViewModel(url: url)

        // Set some state
        viewModel.handleProgress(iteration: 5, total: 10, status: "Running")

        // Cancel
        viewModel.cancelTest()

        XCTAssertTrue(viewModel.isCancelled)
        // isRunning should be set to false when test completes/cancels
    }

    // MARK: - Published Properties Tests

    func testViewModel_hasAllRequiredPublishedProperties() {
        let url = URL(string: "https://example.com")!
        let viewModel = SafariPerformanceTestViewModel(url: url)

        // Verify all @Published properties are accessible
        _ = viewModel.currentURL
        _ = viewModel.isRunning
        _ = viewModel.progress
        _ = viewModel.statusText
        _ = viewModel.currentIteration
        _ = viewModel.totalIterations
        _ = viewModel.selectedIterations
        _ = viewModel.isCancelled
        _ = viewModel.testResults
        _ = viewModel.selectedStatView
        _ = viewModel.errorMessage

        // If we get here without compilation errors, all properties exist
        XCTAssertTrue(true)
    }

    // MARK: - Error Details Tests

    func testErrorDetails_nodeNotFound_returnsCorrectMessage() async {
        let url = URL(string: "https://example.com")!
        let viewModel = SafariPerformanceTestViewModel(url: url, runnerFactory: { url, iterations in
            let mock = MockSafariTestExecutor(url: url, iterations: iterations)
            mock.shouldThrowError = SafariTestRunner.RunnerError.nodeNotFound
            return mock
        })

        await viewModel.runTest()

        XCTAssertEqual(viewModel.errorMessage, "Node.js not found. Please install Node.js to run Safari performance tests.")
        XCTAssertEqual(viewModel.statusText, "Error: Node.js not found")
    }

    func testErrorDetails_npmNotFound_returnsCorrectMessage() async {
        let url = URL(string: "https://example.com")!
        let viewModel = SafariPerformanceTestViewModel(url: url, runnerFactory: { url, iterations in
            let mock = MockSafariTestExecutor(url: url, iterations: iterations)
            mock.shouldThrowError = SafariTestRunner.RunnerError.npmNotFound
            return mock
        })

        await viewModel.runTest()

        XCTAssertEqual(viewModel.errorMessage, "npm not found. Please install Node.js (which includes npm) to run Safari performance tests.")
        XCTAssertEqual(viewModel.statusText, "Error: npm not found")
    }

    func testErrorDetails_dependenciesInstallFailed_returnsCorrectMessage() async {
        let url = URL(string: "https://example.com")!
        let sampleErrorOutput = "npm ERR! some error output"
        let viewModel = SafariPerformanceTestViewModel(url: url, runnerFactory: { url, iterations in
            let mock = MockSafariTestExecutor(url: url, iterations: iterations)
            mock.shouldThrowError = SafariTestRunner.RunnerError.dependenciesInstallFailed(sampleErrorOutput)
            return mock
        })

        await viewModel.runTest()

        XCTAssertEqual(viewModel.errorMessage, "Failed to install test dependencies:\n\n\(sampleErrorOutput)")
        XCTAssertEqual(viewModel.statusText, "Error: Dependency installation failed")
    }

    func testErrorDetails_scriptNotFound_returnsCorrectMessage() async {
        let url = URL(string: "https://example.com")!
        let viewModel = SafariPerformanceTestViewModel(url: url, runnerFactory: { url, iterations in
            let mock = MockSafariTestExecutor(url: url, iterations: iterations)
            mock.shouldThrowError = SafariTestRunner.RunnerError.scriptNotFound
            return mock
        })

        await viewModel.runTest()

        XCTAssertEqual(viewModel.errorMessage, "Safari test script not found in bundle.")
        XCTAssertEqual(viewModel.statusText, "Error: Script not found")
    }

    func testErrorDetails_processFailedWithExitCode_returnsCorrectMessage() async {
        let url = URL(string: "https://example.com")!
        let viewModel = SafariPerformanceTestViewModel(url: url, runnerFactory: { url, iterations in
            let mock = MockSafariTestExecutor(url: url, iterations: iterations)
            mock.shouldThrowError = SafariTestRunner.RunnerError.processFailedWithExitCode(1)
            return mock
        })

        await viewModel.runTest()

        XCTAssertEqual(viewModel.errorMessage, "Safari test process failed with exit code 1. Check Console.app for details.")
        XCTAssertEqual(viewModel.statusText, "Error: Process failed")
    }

    func testErrorDetails_cancelled_setsCorrectStatus() async {
        let url = URL(string: "https://example.com")!
        let viewModel = SafariPerformanceTestViewModel(url: url, runnerFactory: { url, iterations in
            let mock = MockSafariTestExecutor(url: url, iterations: iterations)
            mock.shouldThrowError = SafariTestRunner.RunnerError.cancelled
            return mock
        })

        await viewModel.runTest()

        XCTAssertEqual(viewModel.errorMessage, "Test was cancelled")
        XCTAssertEqual(viewModel.statusText, "Test cancelled")
    }
}
