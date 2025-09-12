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
    public let responseVariance: Double     // Renamed from jitter
    public let failureRate: Double          // Renamed from packetLoss
    public let sampleCount: Int
    public let p50: Double?
    public let p95: Double?

    init(averageResponseTime: Double, responseVariance: Double, failureRate: Double, sampleCount: Int, p50: Double? = nil, p95: Double? = nil) {
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
}

public struct DNSResult {
    public let averageResolutionTime: Double
    public let failureRate: Double
}

public struct BufferBloatResult {
    public let baselineLatency: Double
    public let loadedLatency: Double
    public let increase: Double
    public let grade: String
}

public struct NetworkScore {
    public let overall: Double
    public let httpResponse: Double      // Renamed from latency
    public let bandwidth: Double
    public let dns: Double
    public let bufferBloat: Double?

    init(overall: Double, httpResponse: Double, bandwidth: Double, dns: Double, bufferBloat: Double? = nil) {
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
