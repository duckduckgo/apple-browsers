//
//  HttpResponseTester.swift
//  NetworkQualityMonitor
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

        var allMeasurements: [EndpointMeasurement] = []

        for endpoint in configuration.latencyTestURLs {
            let measurements = await measureEndpoint(endpoint,
                                                    sampleCount: configuration.latencySamplesPerEndpoint,
                                                    timeout: configuration.latencyTestTimeout)

            if !measurements.isEmpty {
                allMeasurements.append(EndpointMeasurement(endpoint: endpoint, measurements: measurements))
            }
        }

        guard !allMeasurements.isEmpty else {
            throw NetworkError.allTestsFailed
        }

        return calculateResults(from: allMeasurements)
    }

    // MARK: - Private Methods

    private func measureEndpoint(_ endpoint: URL, sampleCount: Int, timeout: TimeInterval) async -> [Double] {
        var measurements: [Double] = []

        for _ in 0..<sampleCount {
            if let measurement = await measureSingleRequest(to: endpoint, timeout: timeout) {
                measurements.append(measurement)
            }

            // Small delay between measurements
            try? await Task.sleep(nanoseconds: Constants.measurementDelay)
        }

        return measurements
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

    private func calculateResults(from allMeasurements: [EndpointMeasurement]) -> HttpResponseResult {
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
        
        // Calculate variance for EACH site, then take the median of those variances
        // This gives us a representative measure of how consistent each site is
        let siteVariances = allMeasurements.map { endpoint in
            calculateVarianceForSite(endpoint.measurements)
        }
        
        // Use median of site variances (not affected by outliers)
        // Convert to standard deviation for more intuitive understanding
        let medianVariance = NetworkTestConstants.median(of: siteVariances) ?? 0
        let responseVariance = sqrt(medianVariance) // Standard deviation in ms

        // Calculate failure rate
        let totalAttempts = allMeasurements.reduce(0) { $0 + $1.measurements.count }
        let expectedAttempts = allMeasurements.count * (allMeasurements.first?.measurements.count ?? 0)
        let failureRate = Double(expectedAttempts - totalAttempts) / Double(expectedAttempts)

        return HttpResponseResult(
            averageResponseTime: adjustedResponseTime,
            responseVariance: responseVariance,
            failureRate: failureRate,
            sampleCount: totalAttempts,
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
        let cv = mean > 0 ? stdDev / mean : 0

        return SiteStatistics(
            median: median,
            mean: mean,
            standardDeviation: stdDev,
            coefficientOfVariation: cv
        )
    }

    private func calculateAdjustedResponseTime(bestSiteStats: SiteStatistics,
                                              allSiteStats: [SiteStatistics]) -> Double {
        // Start with best site's median as baseline
        var adjustedTime = bestSiteStats.median

        // Add penalty based on how much worse other sites are
        for stats in allSiteStats {
            if stats.median > bestSiteStats.median {
                let p75 = stats.median * Constants.percentile75Multiplier
                adjustedTime += (p75 - bestSiteStats.median) * Constants.penaltyMultiplier
            }
        }

        return adjustedTime
    }

    private func percentile(_ sorted: [Double], _ p: Double) -> Double? {
        guard !sorted.isEmpty else { return nil }
        let index = Int(Double(sorted.count - 1) * p)
        return sorted[index]
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
