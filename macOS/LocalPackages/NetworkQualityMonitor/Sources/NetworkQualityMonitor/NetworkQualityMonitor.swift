//
//  NetworkQualityMonitor.swift
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

/// Main network quality monitor using dependency injection and SOLID principles
public final class NetworkQualityMonitor: NetworkQualityMonitoring, NetworkTestProgressReporting {

    // MARK: - Dependencies (Injected for testability)

    private let httpResponseTester: HttpResponseTesting
    private let bandwidthTester: BandwidthTesting
    private let dnsTester: DNSTesting
    private let bufferBloatTester: BufferBloatTesting
    private let scoreCalculator: NetworkScoreCalculating
    private let configuration: TestConfiguration
    private let session: NetworkSession

    // MARK: - Progress Reporting

    public var progressCallback: ((Double, String) -> Void)?

    // MARK: - Initialization

    /// Initialize with default dependencies
    public convenience init(configuration: TestConfiguration = .standard,
                            session: NetworkSession = URLSession.shared) {

        self.init(
            configuration: configuration,
            session: session,
            httpResponseTester: HttpResponseTester(session: session),
            bandwidthTester: BandwidthTester(session: session),
            dnsTester: DNSTester(),
            bufferBloatTester: BufferBloatTester(session: session),
            scoreCalculator: NetworkScoreCalculator()
        )
    }

    /// Initialize with custom dependencies (for testing)
    init(configuration: TestConfiguration,
         session: NetworkSession,
         httpResponseTester: HttpResponseTesting,
         bandwidthTester: BandwidthTesting,
         dnsTester: DNSTesting,
         bufferBloatTester: BufferBloatTesting,
         scoreCalculator: NetworkScoreCalculating) {

        self.configuration = configuration
        self.session = session
        self.httpResponseTester = httpResponseTester
        self.bandwidthTester = bandwidthTester
        self.dnsTester = dnsTester
        self.bufferBloatTester = bufferBloatTester
        self.scoreCalculator = scoreCalculator
    }

    // MARK: - Public Methods

    /// Run complete network quality test
    public func runTest() async throws -> NetworkTestResults {
        progressCallback?(0.0, "Starting network quality test...")

        // Run tests in sequence with progress updates
        let httpResponse = try await runHttpResponseTest()
        let bandwidth = try await runBandwidthTest()
        let dns = try await runDNSTest()
        let bufferBloat = try await runBufferBloatTest()

        progressCallback?(0.95, "Calculating results...")

        // Calculate scores and quality
        let overallScore = scoreCalculator.calculateOverallScore(
            httpResponse: httpResponse,
            bandwidth: bandwidth,
            dns: dns,
            bufferBloat: bufferBloat
        )

        let quality = scoreCalculator.determineQuality(from: overallScore.overall)

        progressCallback?(1.0, "Test complete")

        return NetworkTestResults(
            timestamp: Date(),
            quality: quality,
            overallScore: overallScore,
            httpResponse: httpResponse,
            bandwidth: bandwidth,
            dns: dns,
            bufferBloat: bufferBloat
        )
    }

    /// Quick connectivity check
    public func checkConnectivity() async -> Bool {
        do {
            let (_, response) = try await session.data(from: configuration.connectivityCheckURL)

            if let httpResponse = response as? HTTPURLResponse {
                return 200...299 ~= httpResponse.statusCode
            }
            return false
        } catch {
            return false
        }
    }

    // MARK: - Private Test Methods

    private func runHttpResponseTest() async throws -> HttpResponseResult {
        progressCallback?(0.1, "Testing HTTP response times...")

        let result = try await httpResponseTester.performTest(
            configuration: configuration,
            progressCallback: { message in
                self.progressCallback?(0.2, message)
            }
        )

        progressCallback?(0.3, "HTTP response test complete")
        return result
    }

    private func runBandwidthTest() async throws -> BandwidthResult {
        progressCallback?(0.35, "Testing bandwidth...")

        let downloadSpeed = try await bandwidthTester.performDownloadTest(
            configuration: configuration,
            progressCallback: { message in
                self.progressCallback?(0.45, message)
            }
        )

        progressCallback?(0.55, "Testing upload speed...")

        let uploadSpeed = try await bandwidthTester.performUploadTest(
            configuration: configuration,
            progressCallback: { message in
                self.progressCallback?(0.65, message)
            }
        )

        progressCallback?(0.7, "Bandwidth test complete")

        return BandwidthResult(
            downloadSpeedMbps: downloadSpeed,
            uploadSpeedMbps: uploadSpeed
        )
    }

    private func runDNSTest() async throws -> DNSResult {
        progressCallback?(0.72, "Testing DNS resolution...")

        let result = try await dnsTester.performTest(
            configuration: configuration,
            progressCallback: { message in
                self.progressCallback?(0.8, message)
            }
        )

        progressCallback?(0.85, "DNS test complete")
        return result
    }

    private func runBufferBloatTest() async throws -> BufferBloatResult {
        progressCallback?(0.87, "Analyzing buffer bloat...")

        let result = try await bufferBloatTester.performTest(
            configuration: configuration,
            progressCallback: { message in
                self.progressCallback?(0.93, message)
            }
        )

        progressCallback?(0.94, "Buffer bloat test complete")
        return result
    }
}

// MARK: - Factory for Creating Monitors

/// Factory for creating network quality monitors with different configurations
public enum NetworkQualityMonitorFactory {

    /// Create a standard monitor
    public static func createStandard(session: NetworkSession = URLSession.shared) -> NetworkQualityMonitoring {
        NetworkQualityMonitor(configuration: .standard, session: session)
    }

    /// Create a monitor with custom configuration
    public static func create(with configuration: TestConfiguration,
                              session: NetworkSession = URLSession.shared) -> NetworkQualityMonitoring {
        NetworkQualityMonitor(configuration: configuration, session: session)
    }
}
