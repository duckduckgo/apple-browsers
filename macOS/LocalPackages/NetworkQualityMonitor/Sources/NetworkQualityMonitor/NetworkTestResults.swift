//
//  NetworkTestResults.swift
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

// MARK: - Result Types

public struct NetworkTestResults {
    public let timestamp: Date
    public let quality: NetworkQuality
    public let overallScore: NetworkScore
    public let httpResponse: HttpResponseResult  // Renamed from latency
    public let bandwidth: BandwidthResult
    public let dns: DNSResult
    public let bufferBloat: BufferBloatResult
}

public struct HttpResponseResult {  // Renamed from LatencyResult
    public let averageResponseTime: Double  // Renamed from averageRTT
    public let responseVariance: Double     // Standard deviation in ms (not variance)
    public let failureRate: Double          // Renamed from packetLoss
    public let sampleCount: Int
    public let p50: Double?
    public let p95: Double?

    // Computed property for P95-P50 spread (indicates consistency)
    public var latencySpread: Double? {
        guard let p50 = p50, let p95 = p95 else { return nil }
        return p95 - p50
    }

    public init(averageResponseTime: Double,
                responseVariance: Double,
                failureRate: Double,
                sampleCount: Int,
                p50: Double? = nil,
                p95: Double? = nil) {
        self.averageResponseTime = averageResponseTime
        self.responseVariance = responseVariance
        self.failureRate = failureRate
        self.sampleCount = sampleCount
        self.p50 = p50
        self.p95 = p95
    }
}

public struct BandwidthResult {
    public let downloadSpeedMbps: Double
    public let uploadSpeedMbps: Double

    public init(downloadSpeedMbps: Double, uploadSpeedMbps: Double) {
        self.downloadSpeedMbps = downloadSpeedMbps
        self.uploadSpeedMbps = uploadSpeedMbps
    }
}

public struct DNSResult {
    public let averageResolutionTime: Double
    public let failureRate: Double

    public init(averageResolutionTime: Double, failureRate: Double) {
        self.averageResolutionTime = averageResolutionTime
        self.failureRate = failureRate
    }
}

public struct BufferBloatResult {
    public let baselineLatency: Double
    public let loadedLatency: Double
    public let increase: Double
    public let grade: String

    public init(baselineLatency: Double, loadedLatency: Double, increase: Double, grade: String) {
        self.baselineLatency = baselineLatency
        self.loadedLatency = loadedLatency
        self.increase = increase
        self.grade = grade
    }
}

public struct NetworkScore {
    public let overall: Double
    public let httpResponse: Double      // Renamed from latency
    public let bandwidth: Double
    public let dns: Double
    public let bufferBloat: Double?

    public init(overall: Double, httpResponse: Double, bandwidth: Double, dns: Double, bufferBloat: Double? = nil) {
        self.overall = overall
        self.httpResponse = httpResponse
        self.bandwidth = bandwidth
        self.dns = dns
        self.bufferBloat = bufferBloat
    }
}

public enum NetworkQuality: String {
    case excellent = "Excellent"
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"

    public var emoji: String {
        switch self {
        case .excellent: return "🟢"
        case .good: return "🟡"
        case .fair: return "🟠"
        case .poor: return "🔴"
        }
    }
}

enum NetworkError: Error, LocalizedError {
    case invalidResponse
    case allTestsFailed
    case insufficientData

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .allTestsFailed:
            return "All network tests failed - check your connection"
        case .insufficientData:
            return "Insufficient data collected for accurate measurement"
        }
    }
}
