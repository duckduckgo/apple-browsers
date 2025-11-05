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

        // Create a mock JSON results file
        let mockJSON = createMockJSONResults()
        let fileURL = URL(fileURLWithPath: mockResultsPath)
        try mockJSON.write(to: fileURL, atomically: true, encoding: .utf8)

        return mockResultsPath
    }

    private func createMockJSONResults() -> String {
        let json = """
        {
          "testConfiguration": {
            "url": "\(url.absoluteString)",
            "iterations": \(iterations),
            "browser": "Safari",
            "browserVersion": "18.0",
            "platform": "darwin",
            "startTime": "2024-01-01T00:00:00.000Z",
            "timeout": 30000,
            "maxRetries": 3
          },
          "iterations": [
            {
              "iteration": 1,
              "success": true,
              "url": "\(url.absoluteString)",
              "timestamp": "2024-01-01T00:00:01.000Z",
              "duration": 1500,
              "metrics": {
                "loadComplete": 1500.5,
                "domComplete": 1300.2,
                "domContentLoaded": 1100.8,
                "domInteractive": 900.4,
                "fcp": 800.1,
                "ttfb": 200.3,
                "responseTime": 150.2,
                "serverTime": 100.1,
                "transferSize": 524288,
                "encodedBodySize": 262144,
                "decodedBodySize": 524288,
                "resourceCount": 25,
                "totalResourcesSize": 1048576,
                "protocol": "h2",
                "redirectCount": 0,
                "navigationType": "navigate"
              }
            }
          ],
          "metadata": {
            "interrupted": false,
            "endTime": "2024-01-01T00:00:02.000Z"
          }
        }
        """
        return json
    }

    func cleanup() {
        cleanupCalled = true
    }
}
