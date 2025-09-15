//
//  NetworkQualityMonitorTests.swift
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
@testable import NetworkQualityMonitor

final class NetworkQualityMonitorTests: XCTestCase {

    // MARK: - Basic Initialization Tests

    func testMonitorInitialization() {
        let monitor = NetworkQualityMonitor()
        XCTAssertNotNil(monitor)
    }

    func testMonitorWithCustomConfiguration() {
        let customConfig = TestConfiguration(
            latencyTestURLs: [URL(string: "https://example.com")!],
            bandwidthTestURLs: [URL(string: "https://example.com/test.bin")!],
            uploadTestURLs: [URL(string: "https://example.com/upload")!],
            dnsTestDomains: ["example.com"]
        )
        let monitor = NetworkQualityMonitor(configuration: customConfig)
        XCTAssertNotNil(monitor)
    }

    // MARK: - Network Quality Enum Tests

    func testNetworkQualityEnum() {
        XCTAssertEqual(NetworkQuality.excellent.emoji, "🟢")
        XCTAssertEqual(NetworkQuality.good.emoji, "🟡")
        XCTAssertEqual(NetworkQuality.fair.emoji, "🟠")
        XCTAssertEqual(NetworkQuality.poor.emoji, "🔴")

        XCTAssertEqual(NetworkQuality.excellent.rawValue, "Excellent")
        XCTAssertEqual(NetworkQuality.good.rawValue, "Good")
        XCTAssertEqual(NetworkQuality.fair.rawValue, "Fair")
        XCTAssertEqual(NetworkQuality.poor.rawValue, "Poor")
    }

    // MARK: - Configuration Tests

    func testTestConfigurationDefaults() {
        let config = TestConfiguration.standard
        XCTAssertEqual(config.latencySamplesPerEndpoint, 15)
        XCTAssertEqual(config.bandwidthRunsPerServer, 1)
        XCTAssertEqual(config.uploadChunkSize, 5_242_880)
        XCTAssertEqual(config.uploadChunkCount, 1)
        XCTAssertEqual(config.latencyTestTimeout, 5)
        XCTAssertEqual(config.bandwidthTestTimeout, 20)
        XCTAssertEqual(config.uploadTestTimeout, 15)
        XCTAssertFalse(config.latencyTestURLs.isEmpty)
        XCTAssertFalse(config.bandwidthTestURLs.isEmpty)
        XCTAssertFalse(config.uploadTestURLs.isEmpty)
        XCTAssertFalse(config.dnsTestDomains.isEmpty)
        XCTAssertNotNil(config.connectivityCheckURL)
    }

    // MARK: - Score Calculator Tests

    func testScoreCalculator() {
        let calculator = NetworkScoreCalculator()

        let httpResponse = HttpResponseResult(
            averageResponseTime: 100,
            responseVariance: 20,
            failureRate: 0,
            sampleCount: 15
        )

        let bandwidth = BandwidthResult(
            downloadSpeedMbps: 100,
            uploadSpeedMbps: 50
        )

        let dns = DNSResult(
            averageResolutionTime: 20,
            failureRate: 0
        )

        let bufferBloat = BufferBloatResult(
            baselineLatency: 50,
            loadedLatency: 80,
            increase: 30,
            grade: "A"
        )

        let score = calculator.calculateOverallScore(
            httpResponse: httpResponse,
            bandwidth: bandwidth,
            dns: dns,
            bufferBloat: bufferBloat
        )

        XCTAssertGreaterThan(score.overall, 0)
        XCTAssertLessThanOrEqual(score.overall, 100)
        XCTAssertNotNil(score.httpResponse)
        XCTAssertNotNil(score.bandwidth)
        XCTAssertNotNil(score.dns)
        XCTAssertNotNil(score.bufferBloat)
    }

    func testQualityDetermination() {
        let calculator = NetworkScoreCalculator()

        XCTAssertEqual(calculator.determineQuality(from: 85), .excellent)
        XCTAssertEqual(calculator.determineQuality(from: 70), .good)
        XCTAssertEqual(calculator.determineQuality(from: 50), .fair)
        XCTAssertEqual(calculator.determineQuality(from: 30), .poor)
    }

    // MARK: - Network Error Tests

    func testNetworkErrorDescriptions() {
        XCTAssertEqual(NetworkError.invalidResponse.localizedDescription, "Invalid response from server")
        XCTAssertEqual(NetworkError.allTestsFailed.localizedDescription,
                       "All network tests failed - check your connection")
        XCTAssertEqual(NetworkError.insufficientData.localizedDescription,
                       "Insufficient data collected for accurate measurement")
    }

    // MARK: - Statistical Function Tests

    func testMedianCalculationWithOddCount() {
        let measurements = [1.0, 3.0, 2.0, 5.0, 4.0] // Sorted: [1,2,3,4,5]
        let median = NetworkTestConstants.median(of: measurements)
        XCTAssertNotNil(median)
        XCTAssertEqual(median!, 3.0, accuracy: 0.001) // Middle value
    }

    func testMedianCalculationWithEvenCount() {
        let measurements = [1.0, 4.0, 2.0, 3.0] // Sorted: [1,2,3,4]
        let median = NetworkTestConstants.median(of: measurements)
        XCTAssertNotNil(median)
        XCTAssertEqual(median!, 2.5, accuracy: 0.001) // Average of middle two values (2+3)/2 = 2.5
    }

    func testMedianCalculationWithSingleValue() {
        let measurements = [42.0]
        let median = NetworkTestConstants.median(of: measurements)
        XCTAssertNotNil(median)
        XCTAssertEqual(median!, 42.0, accuracy: 0.001)
    }

    func testMedianCalculationWithTwoValues() {
        let measurements = [10.0, 20.0]
        let median = NetworkTestConstants.median(of: measurements)
        XCTAssertNotNil(median)
        XCTAssertEqual(median!, 15.0, accuracy: 0.001) // (10+20)/2 = 15
    }

    func testMedianCalculationWithEmptyArray() {
        let measurements: [Double] = []
        let median = NetworkTestConstants.median(of: measurements)
        XCTAssertNil(median)
    }

    func testMedianCalculationWithDuplicateValues() {
        let measurements = [5.0, 5.0, 5.0, 5.0] // All same values
        let median = NetworkTestConstants.median(of: measurements)
        XCTAssertNotNil(median)
        XCTAssertEqual(median!, 5.0, accuracy: 0.001)
    }

    func testMedianCalculationWithLargeDataset() {
        // Test with larger dataset to ensure performance
        let measurements = Array(1...1000).map { Double($0) } // 1.0 to 1000.0
        let median = NetworkTestConstants.median(of: measurements)
        XCTAssertNotNil(median)
        XCTAssertEqual(median!, 500.5, accuracy: 0.001) // Average of 500 and 501
    }

    // MARK: - New Scoring Algorithm Tests

    func testHighVariancePenalty() {
        // Test case based on real user data showing high variance should severely penalize score
        let calculator = NetworkScoreCalculator()

        let httpResponse = HttpResponseResult(
            averageResponseTime: 445,     // Poor latency
            responseVariance: 713.6,      // Extremely high variance - should heavily penalize
            failureRate: 0,
            sampleCount: 15
        )

        let bandwidth = BandwidthResult(
            downloadSpeedMbps: 13.1,      // Fair download speed  
            uploadSpeedMbps: 3.6          // Poor upload speed
        )

        let dns = DNSResult(
            averageResolutionTime: 28,    // Good DNS
            failureRate: 0
        )

        let bufferBloat = BufferBloatResult(
            baselineLatency: 50,
            loadedLatency: 80,
            increase: 30,
            grade: "A"                    // Excellent buffer bloat
        )

        let score = calculator.calculateOverallScore(
            httpResponse: httpResponse,
            bandwidth: bandwidth,
            dns: dns,
            bufferBloat: bufferBloat
        )

        // With high variance (713ms), the overall score should be very low despite good DNS/buffer bloat
        XCTAssertLessThan(score.overall, 40, "High variance should result in poor overall score")
        XCTAssertLessThan(score.httpResponse, 10, "High variance should severely penalize HTTP response score")
        XCTAssertEqual(calculator.determineQuality(from: score.overall), .poor, "High variance should result in 'poor' quality rating")
    }
}
