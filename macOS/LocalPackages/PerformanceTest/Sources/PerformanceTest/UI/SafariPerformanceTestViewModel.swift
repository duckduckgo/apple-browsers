//
//  SafariPerformanceTestViewModel.swift
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

import Foundation
import SwiftUI
import os.log

@MainActor
public final class SafariPerformanceTestViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published public var currentURL: URL?
    @Published public var isRunning = false
    @Published public var progress: Double = 0
    @Published public var statusText = ""
    @Published public var currentIteration = 0
    @Published public var totalIterations = PerformanceTestConstants.TestConfig.defaultIterations
    @Published public var selectedIterations = PerformanceTestConstants.TestConfig.defaultIterations
    @Published public var isCancelled = false
    @Published public var testResults: PerformanceTestResults?
    @Published public var selectedStatView = PerformanceTestConstants.StatViews.median
    @Published public var errorMessage: String?

    // MARK: - Private Properties

    private var runner: SafariTestExecuting?
    private let runnerFactory: @MainActor (URL, Int) -> SafariTestExecuting
    private let logger = Logger(
        subsystem: "com.duckduckgo.macos.browser.performancetest",
        category: "SafariPerformanceTestViewModel"
    )

    // MARK: - Initialization

    public init(url: URL, runnerFactory: (@MainActor (URL, Int) -> SafariTestExecuting)? = nil) {
        self.currentURL = url
        self.runnerFactory = runnerFactory ?? { url, iterations in SafariTestRunner(url: url, iterations: iterations) }
    }

    public init(runnerFactory: (@MainActor (URL, Int) -> SafariTestExecuting)? = nil) {
        self.currentURL = nil
        self.runnerFactory = runnerFactory ?? { url, iterations in SafariTestRunner(url: url, iterations: iterations) }
    }

    // MARK: - Public Methods

    public func runTest() async {
        guard let url = currentURL else {
            errorMessage = "No URL provided"
            return
        }

        resetTestState()
        logger.log("Starting Safari performance test for \(url.absoluteString)")

        let runner = createAndConfigureRunner(url: url)
        self.runner = runner

        do {
            let resultsPath = try await runner.runTest()
            try await parseResults(from: resultsPath)
        } catch {
            handleTestError(error)
        }

        isRunning = false
    }

    public func cancelTest() {
        logger.log("Cancelling Safari performance test")
        isCancelled = true
        statusText = "Cancelling..."
    }

    public func reset() {
        logger.log("Resetting Safari performance test state")
        isRunning = false
        progress = 0
        statusText = ""
        currentIteration = 0
        isCancelled = false
        testResults = nil
        errorMessage = nil
    }

    public func cleanup() {
        logger.log("Cleaning up Safari performance test resources")
        runner?.cleanup()
        runner = nil
    }

    // MARK: - Internal Methods (for testing)

    internal func handleProgress(iteration: Int, total: Int, status: String) {
        currentIteration = iteration
        totalIterations = total
        statusText = status

        if total > 0, iteration > 0 {
            progress = Double(iteration) / Double(total)
        }
    }

    // MARK: - Private Methods

    private func resetTestState() {
        isRunning = true
        isCancelled = false
        progress = 0
        errorMessage = nil
        testResults = nil
        statusText = "Initializing Safari test..."
    }

    private func createAndConfigureRunner(url: URL) -> SafariTestExecuting {
        var runner = runnerFactory(url, selectedIterations)

        runner.progressHandler = { [weak self] iteration, total, status in
            Task { @MainActor in
                self?.handleProgress(iteration: iteration, total: total, status: status)
            }
        }

        runner.isCancelled = { [weak self] in
            self?.isCancelled ?? false
        }

        return runner
    }

    private func parseResults(from path: String) async throws {
        let parser = SafariResultsParser()
        let results = try parser.parse(filePath: path)
        self.testResults = results
        self.statusText = "Test completed successfully"
        self.progress = 1.0
        logger.log("Safari test completed and parsed successfully")
    }

    private func handleTestError(_ error: Error) {
        let (message, status) = errorDetails(for: error)
        self.errorMessage = message
        self.statusText = status
        logger.log("Safari test failed: \(message)")
    }

    private func errorDetails(for error: Error) -> (message: String, status: String) {
        switch error {
        case SafariTestRunner.RunnerError.cancelled:
            return ("Test was cancelled", "Test cancelled")
        case SafariTestRunner.RunnerError.nodeNotFound:
            return ("Node.js not found. Please install Node.js to run Safari performance tests.", "Error: Node.js not found")
        case SafariTestRunner.RunnerError.npmNotFound:
            return ("npm not found. Please install Node.js (which includes npm) to run Safari performance tests.", "Error: npm not found")
        case SafariTestRunner.RunnerError.dependenciesInstallFailed(let errorOutput):
            return ("Failed to install test dependencies:\n\n\(errorOutput)", "Error: Dependency installation failed")
        case SafariTestRunner.RunnerError.scriptNotFound:
            return ("Safari test script not found in bundle.", "Error: Script not found")
        case SafariTestRunner.RunnerError.invalidIterationCount:
            return ("Invalid iteration count. Please select at least 1 iteration.", "Error: Invalid iteration count")
        case SafariTestRunner.RunnerError.invalidURL:
            return ("Invalid URL. Please provide a valid HTTP or HTTPS URL.", "Error: Invalid URL")
        case SafariTestRunner.RunnerError.processFailedWithError(let code, let errorOutput):
            return ("Safari test failed (exit code \(code)):\n\n\(errorOutput)", "Error: Process failed")
        case SafariTestRunner.RunnerError.processFailedWithExitCode(let code):
            return ("Safari test process failed with exit code \(code). Check Console.app for details.", "Error: Process failed")
        default:
            return ("Unexpected error: \(error.localizedDescription)", "Error: \(error.localizedDescription)")
        }
    }
}
