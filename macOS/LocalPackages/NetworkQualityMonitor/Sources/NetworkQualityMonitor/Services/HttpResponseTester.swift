//
//  HttpResponseTester.swift
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

/// Service responsible for HTTP response testing
public final class HttpResponseTester: HttpResponseTesting {

    // MARK: - Constants

    private enum Constants {
        static let progressMessage = "Testing HTTP response times..."
        static let httpMethodHead = "HEAD"
        static let measurementDelay: UInt64 = 50_000_000  // 50ms
        static let percentile50 = 0.5
        static let percentile95 = 0.95
        static let percentile75Multiplier = 1.25
        static let penaltyMultiplier = 0.1
    }
    private let session: NetworkSession

    public init(session: NetworkSession = URLSession.shared) {
        self.session = session
    }

    public func performTest(configuration: TestConfiguration,
                            progressCallback: ((String) -> Void)? = nil) async throws -> HttpResponseResult {
        progressCallback?(Constants.progressMessage)

        // WARM-UP PHASE: Perform one request to each endpoint
        // This "primes" the connection by:
        // - Resolving DNS (gets cached)
        // - Establishing TCP connection (may be reused)
        // - Completing TLS handshake (session may be resumed)
        // - Warming up CDN edge caches
        // These initial "cold" measurements are discarded
        for endpoint in configuration.latencyTestURLs {
            _ = await measureSingleRequest(to: endpoint, timeout: configuration.latencyTestTimeout)
            // Small delay after warm-up
            try? await Task.sleep(nanoseconds: Constants.measurementDelay)
        }

        // MEASUREMENT PHASE: Perform interleaved measurements
        // Endpoints are measured in rounds with shuffling to:
        // - Avoid consecutive requests to the same endpoint
        // - Distribute load evenly over time
        // - Get more representative latency samples
        let allMeasurements = await performInterleavedMeasurements(
            endpoints: configuration.latencyTestURLs,
            samplesPerEndpoint: configuration.latencySamplesPerEndpoint,
            timeout: configuration.latencyTestTimeout
        )

        guard !allMeasurements.isEmpty else {
            throw NetworkError.allTestsFailed
        }

        return calculateResults(from: allMeasurements, samplesPerEndpoint: configuration.latencySamplesPerEndpoint)
    }

    // MARK: - Private Methods

    private func performInterleavedMeasurements(endpoints: [URL],
                                                samplesPerEndpoint: Int,
                                                timeout: TimeInterval) async -> [EndpointMeasurement] {
        // Initialize storage for measurements
        var measurementsByEndpoint: [URL: [Double]] = [:]
        for endpoint in endpoints {
            measurementsByEndpoint[endpoint] = []
        }

        // Perform measurements in rounds, hitting each endpoint once per round
        // This avoids consecutive requests to the same endpoint
        for _ in 0..<samplesPerEndpoint {
            // Shuffle endpoints for each round to avoid patterns
            let shuffledEndpoints = endpoints.shuffled()

            for endpoint in shuffledEndpoints {
                if let measurement = await measureSingleRequest(to: endpoint, timeout: timeout) {
                    measurementsByEndpoint[endpoint]?.append(measurement)
                }

                // Small delay between different endpoints
                try? await Task.sleep(nanoseconds: Constants.measurementDelay)
            }
        }

        // Convert to EndpointMeasurement array
        var allMeasurements: [EndpointMeasurement] = []
        for (endpoint, measurements) in measurementsByEndpoint where !measurements.isEmpty {
            allMeasurements.append(EndpointMeasurement(endpoint: endpoint, measurements: measurements))
        }

        return allMeasurements
    }

    private func measureSingleRequest(to url: URL, timeout: TimeInterval) async -> Double? {
        var request = URLRequest(url: url)
        request.httpMethod = Constants.httpMethodHead
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            let (_, response) = try await session.data(for: request)
            let endTime = CFAbsoluteTimeGetCurrent()

            if let httpResponse = response as? HTTPURLResponse,
               200...299 ~= httpResponse.statusCode {
                return (endTime - startTime) * 1000  // Convert to milliseconds
            }
        } catch {
            // Request failed, skip this measurement
        }

        return nil
    }

    private func calculateResults(from allMeasurements: [EndpointMeasurement], samplesPerEndpoint: Int) -> HttpResponseResult {
        // Calculate per-site statistics
        let siteStatistics = allMeasurements.map { endpoint in
            calculateSiteStatistics(endpoint.measurements)
        }

        // Find the best performing site (lowest median)
        let bestSiteIndex = siteStatistics.enumerated().min(by: { $0.element.median < $1.element.median })?.offset ?? 0
        let bestSiteStats = siteStatistics[bestSiteIndex]

        // Calculate adjusted response time
        let adjustedResponseTime = calculateAdjustedResponseTime(
            bestSiteStats: bestSiteStats,
            allSiteStats: siteStatistics
        )

        // Calculate percentiles from all measurements
        let allSortedMeasurements = allMeasurements.flatMap { $0.measurements }.sorted()
        let p50 = percentile(allSortedMeasurements, Constants.percentile50)
        let p95 = percentile(allSortedMeasurements, Constants.percentile95)

        // Calculate the median of per-site standard deviations
        // This represents the typical consistency within endpoints
        // rather than variance across different geographic locations
        let siteStdDevs = siteStatistics.map { $0.standardDeviation }
        let responseVariance = NetworkTestConstants.median(of: siteStdDevs) ?? 0

        // Calculate failure rate based on expected vs actual measurements
        // Expected: number of endpoints × configured samples per endpoint
        let totalSuccessfulMeasurements = allMeasurements.reduce(0) { $0 + $1.measurements.count }
        let expectedAttempts = allMeasurements.count * samplesPerEndpoint
        let failureRate = Double(expectedAttempts - totalSuccessfulMeasurements) / Double(expectedAttempts)

        return HttpResponseResult(
            averageResponseTime: adjustedResponseTime,
            responseVariance: responseVariance,
            failureRate: failureRate,
            sampleCount: totalSuccessfulMeasurements,
            p50: p50,
            p95: p95
        )
    }

    private func calculateSiteStatistics(_ measurements: [Double]) -> SiteStatistics {
        let median = NetworkTestConstants.median(of: measurements) ?? 0
        let mean = measurements.reduce(0, +) / Double(measurements.count)

        // Calculate standard deviation
        let squaredDiffs = measurements.map { pow($0 - mean, 2) }
        let variance = squaredDiffs.reduce(0, +) / Double(squaredDiffs.count)
        let stdDev = sqrt(variance)

        // Coefficient of Variation
        let coefficientOfVariation = mean > 0 ? stdDev / mean : 0

        return SiteStatistics(
            median: median,
            mean: mean,
            standardDeviation: stdDev,
            coefficientOfVariation: coefficientOfVariation
        )
    }

    private func calculateAdjustedResponseTime(bestSiteStats: SiteStatistics,
                                               allSiteStats: [SiteStatistics]) -> Double {
        // Calculate the MEDIAN of all site medians
        // This properly reflects real-world latency expectations:
        // 
        // EXCELLENT (<150ms): Well-optimized services with good CDN coverage
        // GOOD (150-250ms): Normal, expected performance for most services
        // FAIR (250-400ms): Acceptable but could be optimized
        // POOR (>400ms): Needs investigation, users will perceive as slow
        //
        // Geographic reality examples:
        // - Local CDN edge: 10-50ms
        // - Same continent: 50-150ms  
        // - Cross-ocean: 150-300ms
        // - Opposite side of world: 250-400ms
        // - Satellite/poor mobile: 400-700ms
        //
        // Using median ensures we get the "typical" latency experience
        // and naturally reflects geographic distance to servers

        let allMedians = allSiteStats.map { $0.median }
        let overallMedian = NetworkTestConstants.median(of: allMedians) ?? bestSiteStats.median

        return overallMedian
    }

    private func percentile(_ sorted: [Double], _ percentileValue: Double) -> Double? {
        guard !sorted.isEmpty else { return nil }
        let index = Int(Double(sorted.count - 1) * percentileValue)
        return sorted[index]
    }

    private func calculateVariance(_ measurements: [Double]) -> Double {
        guard measurements.count > 1 else { return 0 }

        let mean = measurements.reduce(0, +) / Double(measurements.count)
        let squaredDifferences = measurements.map { pow($0 - mean, 2) }
        let variance = squaredDifferences.reduce(0, +) / Double(measurements.count - 1)

        return variance
    }

    private func calculateStandardDeviation(_ measurements: [Double]) -> Double {
        return sqrt(calculateVariance(measurements))
    }

    private func calculateVarianceForSite(_ measurements: [Double]) -> Double {
        guard measurements.count > 1 else { return 0 }

        let mean = measurements.reduce(0, +) / Double(measurements.count)
        let squaredDifferences = measurements.map { pow($0 - mean, 2) }
        let variance = squaredDifferences.reduce(0, +) / Double(measurements.count)

        return variance
    }
}

// MARK: - Supporting Types

private struct EndpointMeasurement {
    let endpoint: URL
    let measurements: [Double]
}

private struct SiteStatistics {
    let median: Double
    let mean: Double
    let standardDeviation: Double
    let coefficientOfVariation: Double
}
