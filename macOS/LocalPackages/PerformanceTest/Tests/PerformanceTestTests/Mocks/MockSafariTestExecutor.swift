//
//  MockSafariTestExecutor.swift
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
@testable import PerformanceTest

@MainActor
final class MockSafariTestExecutor: SafariTestExecuting {
    let url: URL
    let iterations: Int
    var progressHandler: ((Int, Int, String) -> Void)?
    var isCancelled: () -> Bool = { false }

    // Mock configuration
    var shouldThrowError: Error?
    var mockResultsPath: String = "/tmp/mock-results.json"
    var simulateProgressUpdates: Bool = true
    var progressDelay: UInt64 = 10_000_000 // 10ms per iteration

    // Test observations
    private(set) var runTestCalled = false
    private(set) var cleanupCalled = false

    init(url: URL, iterations: Int) {
        self.url = url
        self.iterations = iterations
    }

    func runTest() async throws -> String {
        runTestCalled = true

        // Throw configured error if set
        if let error = shouldThrowError {
            throw error
        }

        // Simulate progress updates
        if simulateProgressUpdates {
            for iteration in 1...iterations {
                if isCancelled() {
                    throw SafariTestRunner.RunnerError.cancelled
                }

                let status = "Running iteration \(iteration) of \(iterations)"
                progressHandler?(iteration, iterations, status)

                // Simulate work
                try await Task.sleep(nanoseconds: progressDelay)
            }
        }

        return mockResultsPath
    }

    func cleanup() {
        cleanupCalled = true
    }
}
