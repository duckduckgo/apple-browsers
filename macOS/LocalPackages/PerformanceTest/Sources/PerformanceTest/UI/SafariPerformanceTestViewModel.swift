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
    @Published public var resultsFilePath: String?
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

        // Reset state
        isRunning = true
        isCancelled = false
        progress = 0
        errorMessage = nil
        resultsFilePath = nil
        statusText = "Initializing Safari test..."

        logger.log("Starting Safari performance test for \(url.absoluteString)")

        // Create runner using factory
        var runner = runnerFactory(url, selectedIterations)
        self.runner = runner

        // Set up progress handler
        runner.progressHandler = { [weak self] iteration, total, status in
            Task { @MainActor in
                self?.handleProgress(iteration: iteration, total: total, status: status)
            }
        }

        // Set up cancellation check
        runner.isCancelled = { [weak self] in
            self?.isCancelled ?? false
        }

        // Run the test
        do {
            let resultsPath = try await runner.runTest()
            self.resultsFilePath = resultsPath
            self.statusText = "Test completed successfully"
            self.progress = 1.0
            logger.log("Safari test completed. Results saved to: \(resultsPath)")
        } catch SafariTestRunner.RunnerError.cancelled {
            self.statusText = "Test cancelled"
            logger.log("Safari test was cancelled by user")
        } catch SafariTestRunner.RunnerError.nodeNotFound {
            self.errorMessage = "Node.js not found. Please install Node.js to run Safari performance tests."
            self.statusText = "Error: Node.js not found"
            logger.log("Safari test failed: Node.js not found")
        } catch SafariTestRunner.RunnerError.npmInstallFailed {
            self.errorMessage = "Failed to install npm dependencies. Check Console.app for details."
            self.statusText = "Error: npm install failed"
            logger.log("Safari test failed: npm install failed")
        } catch SafariTestRunner.RunnerError.scriptNotFound {
            self.errorMessage = "Safari test script not found in bundle."
            self.statusText = "Error: Script not found"
            logger.log("Safari test failed: Script not found")
        } catch SafariTestRunner.RunnerError.invalidIterationCount {
            self.errorMessage = "Invalid iteration count. Please select at least 1 iteration."
            self.statusText = "Error: Invalid iteration count"
            logger.log("Safari test failed: Invalid iteration count")
        } catch SafariTestRunner.RunnerError.invalidURL {
            self.errorMessage = "Invalid URL. Please provide a valid HTTP or HTTPS URL."
            self.statusText = "Error: Invalid URL"
            logger.log("Safari test failed: Invalid URL")
        } catch SafariTestRunner.RunnerError.processFailedWithExitCode(let code) {
            self.errorMessage = "Safari test process failed with exit code \(code). Check Console.app for details."
            self.statusText = "Error: Process failed"
            logger.log("Safari test failed with exit code: \(code)")
        } catch {
            self.errorMessage = "Unexpected error: \(error.localizedDescription)"
            self.statusText = "Error: \(error.localizedDescription)"
            logger.log("Safari test failed with error: \(error.localizedDescription)")
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
        resultsFilePath = nil
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

        if total > 0 {
            progress = Double(iteration) / Double(total)
        }
    }
}
