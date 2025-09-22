//
//  BufferBloatTester.swift
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

/// Service responsible for buffer bloat testing
public final class BufferBloatTester: BufferBloatTesting {

    // MARK: - Constants

    private enum Constants {
        static let progressMessage = "Testing buffer bloat..."
        static let baselineSampleCount = 10
        static let loadedSampleCount = 15
        static let sampleDelay: UInt64 = 100_000_000  // 100ms between samples
        static let downloadStartDelay: UInt64 = 500_000_000  // 500ms to let download start

        // Buffer bloat grades based on latency increase (ms)
        static let gradeAThreshold = 50.0
        static let gradeBThreshold = 100.0
        static let gradeCThreshold = 200.0
        static let gradeDThreshold = 400.0
    }
    private let session: NetworkSession
    private let latencyMeasurer: LatencyMeasuring

    public init(session: NetworkSession = URLSession.shared) {
        self.session = session
        self.latencyMeasurer = DefaultLatencyMeasurer(session: session)
    }

    init(session: NetworkSession = URLSession.shared,
         latencyMeasurer: LatencyMeasuring) {
        self.session = session
        self.latencyMeasurer = latencyMeasurer
    }

    public func performTest(configuration: TestConfiguration,
                            progressCallback: ((String) -> Void)? = nil) async throws -> BufferBloatResult {
        progressCallback?(Constants.progressMessage)

        // Measure baseline latency
        let baselineLatency = try await measureBaselineLatency(configuration: configuration)

        // Start download task to create network load
        let downloadTask = createDownloadTask(configuration: configuration)

        // Wait for download to start
        try? await Task.sleep(nanoseconds: Constants.downloadStartDelay)

        // Measure latency under load
        let loadedLatency = try await measureLoadedLatency(configuration: configuration)

        // Cancel download
        downloadTask.cancel()

        // Calculate increase and grade
        let increase = loadedLatency - baselineLatency
        let grade = gradeBufferBloat(increase: increase)

        return BufferBloatResult(
            baselineLatency: baselineLatency,
            loadedLatency: loadedLatency,
            increase: increase,
            grade: grade
        )
    }

    // MARK: - Private Methods

    private func measureLatency(sampleCount: Int, configuration: TestConfiguration) async throws -> Double {
        var measurements: [Double] = []

        // Take measurements
        for _ in 0..<sampleCount {
            if let latency = try? await latencyMeasurer.measureSingle(configuration: configuration) {
                measurements.append(latency)
            }
            try? await Task.sleep(nanoseconds: Constants.sampleDelay)
        }

        guard !measurements.isEmpty else {
            throw NetworkError.insufficientData
        }

        // Use median for stability
        return NetworkTestConstants.median(of: measurements) ?? 0
    }

    private func measureBaselineLatency(configuration: TestConfiguration) async throws -> Double {
        return try await measureLatency(sampleCount: Constants.baselineSampleCount, configuration: configuration)
    }

    private func measureLoadedLatency(configuration: TestConfiguration) async throws -> Double {
        return try await measureLatency(sampleCount: Constants.loadedSampleCount, configuration: configuration)
    }

    private func createDownloadTask(configuration: TestConfiguration) -> Task<Void, Never> {
        Task {
            // Download from first available bandwidth test URL
            if let url = configuration.bandwidthTestURLs.first {
                var request = URLRequest(url: url)
                request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                request.timeoutInterval = 30 // Reasonable timeout for background download
                _ = try? await session.data(for: request)
            }
        }
    }

    private func gradeBufferBloat(increase: Double) -> String {
        // Grade based on absolute latency increase in milliseconds
        switch increase {
        case ..<Constants.gradeAThreshold: return "A"      // Excellent - minimal buffer bloat
        case Constants.gradeAThreshold..<Constants.gradeBThreshold: return "B"   // Good - some buffer bloat
        case Constants.gradeBThreshold..<Constants.gradeCThreshold: return "C"  // Fair - moderate buffer bloat
        case Constants.gradeCThreshold..<Constants.gradeDThreshold: return "D"  // Poor - significant buffer bloat
        default: return "F"         // Very Poor - severe buffer bloat
        }
    }
}

// MARK: - Latency Measuring Protocol

protocol LatencyMeasuring {
    func measureSingle(configuration: TestConfiguration) async throws -> Double
}

// MARK: - Default Latency Measurer

private final class DefaultLatencyMeasurer: LatencyMeasuring {
    private let session: NetworkSession

    init(session: NetworkSession) {
        self.session = session
    }

    func measureSingle(configuration: TestConfiguration) async throws -> Double {
        guard let endpoint = configuration.latencyTestURLs.randomElement() else {
            throw NetworkError.insufficientData
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "HEAD"
        request.timeoutInterval = configuration.latencyTestTimeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let startTime = CFAbsoluteTimeGetCurrent()
        let (_, _) = try await session.data(for: request)
        let endTime = CFAbsoluteTimeGetCurrent()

        return (endTime - startTime) * 1000 // Convert to milliseconds
    }
}
