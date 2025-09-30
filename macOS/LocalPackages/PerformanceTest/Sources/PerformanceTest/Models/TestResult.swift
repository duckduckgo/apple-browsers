//
//  TestResult.swift
//  PerformanceTest
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
//

import Foundation

/// Result of a single performance test
public struct TestResult: Codable, Equatable {

    // MARK: - Properties

    /// URL that was tested
    public let url: URL

    /// Performance metrics if test succeeded
    public let metrics: PerformanceMetrics?

    /// Whether the test completed successfully
    public let success: Bool

    /// Error if test failed
    public let error: TestError?

    /// When the test started
    public let timestamp: Date

    /// When the test ended (optional for duration calculation)
    public let endTime: Date?

    // MARK: - Initialization

    public init(
        url: URL,
        metrics: PerformanceMetrics?,
        success: Bool,
        error: TestError? = nil,
        timestamp: Date,
        endTime: Date? = nil
    ) {
        self.url = url
        self.metrics = metrics
        self.success = success
        self.error = error
        self.timestamp = timestamp
        self.endTime = endTime
    }

    // Convenience initializer without error type for basic errors
    public init(
        url: URL,
        metrics: PerformanceMetrics?,
        success: Bool,
        error: Error?,
        timestamp: Date,
        endTime: Date? = nil
    ) {
        self.url = url
        self.metrics = metrics
        self.success = success
        self.error = error.map { TestError.otherError(message: $0.localizedDescription) }
        self.timestamp = timestamp
        self.endTime = endTime
    }

    // MARK: - Computed Properties

    /// Duration of the test if endTime is available
    public var duration: TimeInterval? {
        guard let endTime = endTime else { return nil }
        return endTime.timeIntervalSince(timestamp)
    }

    /// Display-friendly status
    public var displayStatus: String {
        success ? "✅ Success" : "❌ Failed"
    }

    /// Display-friendly duration
    public var displayDuration: String {
        if let metrics = metrics {
            return String(format: "%.2fs", metrics.loadTime)
        } else {
            return "Failed"
        }
    }

    /// Extract site name from URL
    public var siteName: String {
        guard let host = url.host else {
            return url.absoluteString
        }
        // Remove www. prefix if present
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// Error types for test results
public enum TestError: LocalizedError, Codable, Equatable {
    case timeout(duration: TimeInterval)
    case networkError(message: String)
    case invalidURL
    case cancelled
    case otherError(message: String)

    public var errorDescription: String? {
        switch self {
        case .timeout(let duration):
            return "Test timed out after \(duration) seconds"
        case .networkError(let message):
            return "Network error: \(message)"
        case .invalidURL:
            return "Invalid URL"
        case .cancelled:
            return "Test was cancelled"
        case .otherError(let message):
            return message
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type
        case duration
        case message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "timeout":
            let duration = try container.decode(TimeInterval.self, forKey: .duration)
            self = .timeout(duration: duration)
        case "networkError":
            let message = try container.decode(String.self, forKey: .message)
            self = .networkError(message: message)
        case "invalidURL":
            self = .invalidURL
        case "cancelled":
            self = .cancelled
        case "otherError":
            let message = try container.decode(String.self, forKey: .message)
            self = .otherError(message: message)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown error type")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .timeout(let duration):
            try container.encode("timeout", forKey: .type)
            try container.encode(duration, forKey: .duration)
        case .networkError(let message):
            try container.encode("networkError", forKey: .type)
            try container.encode(message, forKey: .message)
        case .invalidURL:
            try container.encode("invalidURL", forKey: .type)
        case .cancelled:
            try container.encode("cancelled", forKey: .type)
        case .otherError(let message):
            try container.encode("otherError", forKey: .type)
            try container.encode(message, forKey: .message)
        }
    }
}
