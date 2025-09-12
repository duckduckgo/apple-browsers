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
    private let session: NetworkSession
    
    public init(session: NetworkSession = URLSession.shared) {
        self.session = session
    }
    
    public func performTest(configuration: TestConfiguration,
                    progressCallback: ((String) -> Void)? = nil) async throws -> HttpResponseResult {
        progressCallback?("Testing HTTP response times...")
        
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
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
        
        return measurements
    }
    
    private func measureSingleRequest(to url: URL, timeout: TimeInterval) async -> Double? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            let (_, response) = try await session.data(for: request)
            let endTime = CFAbsoluteTimeGetCurrent()
            
            if let httpResponse = response as? HTTPURLResponse,
               200...299 ~= httpResponse.statusCode {
                return (endTime - startTime) * 1000 // Convert to milliseconds
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
        
        // Calculate variance (CV at P95)
        let variances = siteStatistics.map { $0.coefficientOfVariation }
        let sortedVariances = variances.sorted()
        let p95Index = Int(Double(sortedVariances.count - 1) * 0.95)
        let p95Variance = sortedVariances[p95Index]
        
        // Convert CV to milliseconds for display
        let responseVariance = p95Variance * adjustedResponseTime
        
        // Calculate failure rate
        let totalAttempts = allMeasurements.reduce(0) { $0 + $1.measurements.count }
        let expectedAttempts = allMeasurements.count * (allMeasurements.first?.measurements.count ?? 0)
        let failureRate = Double(expectedAttempts - totalAttempts) / Double(expectedAttempts)
        
        // Calculate percentiles from all measurements
        let allSortedMeasurements = allMeasurements.flatMap { $0.measurements }.sorted()
        let p50 = percentile(allSortedMeasurements, 0.5)
        let p95 = percentile(allSortedMeasurements, 0.95)
        
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
        let sorted = measurements.sorted()
        let median = sorted[sorted.count / 2]
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
                let p75 = stats.median * 1.25 // Approximate P75
                adjustedTime += (p75 - bestSiteStats.median) * 0.1
            }
        }
        
        return adjustedTime
    }
    
    private func percentile(_ sorted: [Double], _ p: Double) -> Double? {
        guard !sorted.isEmpty else { return nil }
        let index = Int(Double(sorted.count - 1) * p)
        return sorted[index]
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