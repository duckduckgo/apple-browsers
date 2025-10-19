//
//  SafariResultsParser.swift
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
import os.log

/// Parser for Safari performance test JSON results
public struct SafariResultsParser {

    private let logger = Logger(
        subsystem: "com.duckduckgo.macos.browser.performancetest",
        category: "SafariResultsParser"
    )

    public init() {}

    /// Parse Safari JSON results file
    /// - Parameter filePath: Path to the JSON results file
    /// - Returns: PerformanceTestResults object
    /// - Throws: ParsingError if parsing fails
    public func parse(filePath: String) throws -> PerformanceTestResults {
        let fileURL = URL(fileURLWithPath: filePath)

        guard FileManager.default.fileExists(atPath: filePath) else {
            throw ParsingError.fileNotFound(filePath)
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw ParsingError.fileReadError(error.localizedDescription)
        }

        let jsonResult: SafariJSONResults
        do {
            jsonResult = try JSONDecoder().decode(SafariJSONResults.self, from: data)
        } catch {
            throw ParsingError.jsonDecodingError(error.localizedDescription)
        }

        return try convertToPerformanceTestResults(jsonResult)
    }

    /// Convert Safari JSON structure to PerformanceTestResults
    private func convertToPerformanceTestResults(_ jsonResult: SafariJSONResults) throws -> PerformanceTestResults {
        guard let url = URL(string: jsonResult.testConfiguration.url) else {
            throw ParsingError.invalidURL(jsonResult.testConfiguration.url)
        }

        // Extract successful iterations
        let successfulIterations = jsonResult.iterations.filter { $0.success }

        guard !successfulIterations.isEmpty else {
            throw ParsingError.noSuccessfulIterations
        }

        // Build CollectedMetrics from iterations
        var collectedMetrics = CollectedMetrics()
        var loadTimes: [TimeInterval] = []

        for iteration in successfulIterations {
            guard let metrics = iteration.metrics else { continue }

            // Convert milliseconds to seconds for time-based metrics
            let detailedMetrics = DetailedPerformanceMetrics(
                loadComplete: metrics.loadComplete / 1000.0,
                domComplete: metrics.domComplete / 1000.0,
                domContentLoaded: metrics.domContentLoaded / 1000.0,
                domInteractive: metrics.domInteractive / 1000.0,
                firstContentfulPaint: metrics.fcp / 1000.0,
                timeToFirstByte: metrics.ttfb / 1000.0,
                responseTime: metrics.responseTime / 1000.0,
                serverTime: metrics.serverTime / 1000.0,
                transferSize: metrics.transferSize,
                encodedBodySize: metrics.encodedBodySize,
                decodedBodySize: metrics.decodedBodySize,
                resourceCount: metrics.resourceCount,
                totalResourcesSize: metrics.totalResourcesSize ?? 0,
                protocol: metrics.protocol,
                redirectCount: metrics.redirectCount ?? 0,
                navigationType: metrics.navigationType ?? "navigate"
            )

            collectedMetrics.append(detailedMetrics)
            loadTimes.append(detailedMetrics.loadComplete)
        }

        let failedAttempts = jsonResult.iterations.count - successfulIterations.count
        let cancelled = jsonResult.metadata.interrupted

        return PerformanceTestResults(
            url: url,
            loadTimes: loadTimes,
            detailedMetrics: collectedMetrics,
            failedAttempts: failedAttempts,
            iterations: successfulIterations.count,
            cancelled: cancelled
        )
    }

    // MARK: - Error Types

    public enum ParsingError: Error, LocalizedError {
        case fileNotFound(String)
        case fileReadError(String)
        case jsonDecodingError(String)
        case invalidURL(String)
        case noSuccessfulIterations

        public var errorDescription: String? {
            switch self {
            case .fileNotFound(let path):
                return "Results file not found at: \(path)"
            case .fileReadError(let message):
                return "Failed to read results file: \(message)"
            case .jsonDecodingError(let message):
                return "Failed to decode JSON: \(message)"
            case .invalidURL(let url):
                return "Invalid URL in results: \(url)"
            case .noSuccessfulIterations:
                return "No successful test iterations found in results"
            }
        }
    }
}

// MARK: - JSON Decodable Structures

private struct SafariJSONResults: Decodable {
    let testConfiguration: TestConfiguration
    let iterations: [Iteration]
    let metadata: Metadata

    struct TestConfiguration: Decodable {
        let url: String
        let iterations: Int
        let browser: String
        let browserVersion: String?
        let platform: String
        let startTime: String
        let timeout: Int
        let maxRetries: Int
    }

    struct Iteration: Decodable {
        let iteration: Int
        let success: Bool
        let url: String
        let timestamp: String
        let duration: Int
        let metrics: Metrics?
        let error: String?

        struct Metrics: Decodable {
            let loadComplete: Double
            let domComplete: Double
            let domContentLoaded: Double
            let domInteractive: Double
            let fcp: Double
            let ttfb: Double
            let responseTime: Double
            let serverTime: Double
            let transferSize: Double
            let encodedBodySize: Double
            let decodedBodySize: Double
            let resourceCount: Int
            let totalResourcesSize: Double?
            let `protocol`: String?
            let redirectCount: Int?
            let navigationType: String?
        }
    }

    struct Metadata: Decodable {
        let interrupted: Bool
        let endTime: String?
    }
}
