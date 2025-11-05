//
//  TestConfiguration.swift
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

/// Configuration for network quality tests
public struct TestConfiguration {
    /// URLs for latency testing
    public let latencyTestURLs: [URL]

    /// URLs for bandwidth/speed testing
    public let bandwidthTestURLs: [URL]

    /// URLs for upload testing
    public let uploadTestURLs: [URL]

    /// Domains for DNS testing
    public let dnsTestDomains: [String]

    /// Number of samples per endpoint for latency tests
    public let latencySamplesPerEndpoint: Int

    /// Number of bandwidth test runs per server
    public let bandwidthRunsPerServer: Int

    /// Upload test chunk size in bytes
    public let uploadChunkSize: Int

    /// Number of upload test chunks
    public let uploadChunkCount: Int

    /// Request timeout for latency tests
    public let latencyTestTimeout: TimeInterval

    /// Request timeout for bandwidth tests
    public let bandwidthTestTimeout: TimeInterval

    /// Request timeout for upload tests
    public let uploadTestTimeout: TimeInterval

    /// URL for connectivity check
    public let connectivityCheckURL: URL

    /// Default configuration with standard test endpoints
    public static let standard = TestConfiguration(
        latencyTestURLs: [
            // IMPORTANT: Using mix of CDN endpoints and specific regional servers
            // to get realistic geographic latency distribution. CDNs will show best-case
            // (nearest edge), while specific regions show real-world cross-region latency

            // DuckDuckGo - Critical for DDG browser experience
            URL(string: "https://duckduckgo.com/")!,
            URL(string: "https://improving.duckduckgo.com/t/test")!,  // DDG tracking endpoint

            // Global CDN endpoints - these have edge servers worldwide
            URL(string: "https://www.cloudflare.com/cdn-cgi/trace")!,  // CloudFlare (300+ locations)
            URL(string: "https://www.fastly.com/")!,  // Fastly CDN (80+ POPs)
            URL(string: "https://cloudfront.amazonaws.com/")!,  // AWS CloudFront (450+ POPs)
            URL(string: "https://ajax.googleapis.com/ajax/libs/jquery/3.6.0/jquery.min.js")!,  // Google CDN
            URL(string: "https://cdn.jsdelivr.net/npm/vue/dist/vue.js")!,  // jsDelivr CDN

            // Major platforms with global CDN presence
            URL(string: "https://www.youtube.com/")!,  // Google's global CDN
            URL(string: "https://www.facebook.com/")!,  // Meta's global CDN
            URL(string: "https://api.github.com/")!  // GitHub's API (Azure CDN)

            // Note: These CDNs automatically serve from the nearest geographic location,
            // so users in Asia get Asian servers, Europeans get EU servers, etc.
        ],
        bandwidthTestURLs: [
            URL(string: "https://speed.cloudflare.com/__down?bytes=26214400")!,  // 25MB
            URL(string: "https://proof.ovh.net/files/10Mb.dat")!,                // 10MB
            URL(string: "https://speed.hetzner.de/10MB.bin")!                   // 10MB
            // Total: ~25MB for fast connections, less for slow (adaptive)
        ],
        uploadTestURLs: [
            URL(string: "https://speed.cloudflare.com/__up")!,
            URL(string: "https://httpbin.org/post")!,
            URL(string: "https://www.speedtest.net/api/upload")!
        ],
        dnsTestDomains: [
            "duckduckgo.com", "google.com", "cloudflare.com", "apple.com",
            "amazon.com", "microsoft.com", "facebook.com", "netflix.com",
            "github.com", "stackoverflow.com", "wikipedia.org"
        ],
        latencySamplesPerEndpoint: 15,  // Good for stable statistics
        bandwidthRunsPerServer: 1,      // One run per server
        uploadChunkSize: 5_242_880,     // 5MB per test URL (much faster)
        uploadChunkCount: 1,            // Single upload per URL (faster, matches download approach)
        latencyTestTimeout: 5,
        bandwidthTestTimeout: 20,       // Reasonable for 25MB max
        uploadTestTimeout: 15,          // Reasonable for 5MB uploads
        connectivityCheckURL: URL(string: "https://www.apple.com/library/test/success.html")!
    )

    public init(
        latencyTestURLs: [URL],
        bandwidthTestURLs: [URL],
        uploadTestURLs: [URL],
        dnsTestDomains: [String],
        latencySamplesPerEndpoint: Int = 10,
        bandwidthRunsPerServer: Int = 2,
        uploadChunkSize: Int = 52_428_800,
        uploadChunkCount: Int = 2,
        latencyTestTimeout: TimeInterval = 5,
        bandwidthTestTimeout: TimeInterval = 30,
        uploadTestTimeout: TimeInterval = 45,
        connectivityCheckURL: URL = URL(string: "https://www.apple.com/library/test/success.html")!
    ) {
        self.latencyTestURLs = latencyTestURLs
        self.bandwidthTestURLs = bandwidthTestURLs
        self.uploadTestURLs = uploadTestURLs
        self.dnsTestDomains = dnsTestDomains
        self.latencySamplesPerEndpoint = latencySamplesPerEndpoint
        self.bandwidthRunsPerServer = bandwidthRunsPerServer
        self.uploadChunkSize = uploadChunkSize
        self.uploadChunkCount = uploadChunkCount
        self.latencyTestTimeout = latencyTestTimeout
        self.bandwidthTestTimeout = bandwidthTestTimeout
        self.uploadTestTimeout = uploadTestTimeout
        self.connectivityCheckURL = connectivityCheckURL
    }
}

// MARK: - Focused Configuration Types

public struct HttpResponseConfig {
    public let testURLs: [URL]
    public let samplesPerEndpoint: Int
    public let timeout: TimeInterval

    public init(testURLs: [URL], samplesPerEndpoint: Int, timeout: TimeInterval) {
        self.testURLs = testURLs
        self.samplesPerEndpoint = samplesPerEndpoint
        self.timeout = timeout
    }
}

public struct BandwidthConfig {
    public let downloadURLs: [URL]
    public let uploadURLs: [URL]
    public let runsPerServer: Int
    public let uploadChunkSize: Int
    public let uploadChunkCount: Int
    public let downloadTimeout: TimeInterval
    public let uploadTimeout: TimeInterval

    public init(
        downloadURLs: [URL],
        uploadURLs: [URL],
        runsPerServer: Int,
        uploadChunkSize: Int,
        uploadChunkCount: Int,
        downloadTimeout: TimeInterval,
        uploadTimeout: TimeInterval
    ) {
        self.downloadURLs = downloadURLs
        self.uploadURLs = uploadURLs
        self.runsPerServer = runsPerServer
        self.uploadChunkSize = uploadChunkSize
        self.uploadChunkCount = uploadChunkCount
        self.downloadTimeout = downloadTimeout
        self.uploadTimeout = uploadTimeout
    }
}

public struct DNSConfig {
    public let testDomains: [String]

    public init(testDomains: [String]) {
        self.testDomains = testDomains
    }
}
public struct BufferBloatConfig {
    public let downloadURL: URL?

    public init(downloadURL: URL?) {
        self.downloadURL = downloadURL
    }
}

public struct ConnectivityConfig {
    public let checkURL: URL

    public init(checkURL: URL) {
        self.checkURL = checkURL
    }
}

// MARK: - Configuration Extraction Methods

public extension TestConfiguration {

    func httpResponseConfig() -> HttpResponseConfig {
        HttpResponseConfig(
            testURLs: latencyTestURLs,
            samplesPerEndpoint: latencySamplesPerEndpoint,
            timeout: latencyTestTimeout
        )
    }

    func bandwidthConfig() -> BandwidthConfig {
        BandwidthConfig(
            downloadURLs: bandwidthTestURLs,
            uploadURLs: uploadTestURLs,
            runsPerServer: bandwidthRunsPerServer,
            uploadChunkSize: uploadChunkSize,
            uploadChunkCount: uploadChunkCount,
            downloadTimeout: bandwidthTestTimeout,
            uploadTimeout: uploadTestTimeout
        )
    }

    func dnsConfig() -> DNSConfig {
        DNSConfig(testDomains: dnsTestDomains)
    }

    func bufferBloatConfig() -> BufferBloatConfig {
        BufferBloatConfig(downloadURL: bandwidthTestURLs.first)
    }

    func connectivityConfig() -> ConnectivityConfig {
        ConnectivityConfig(checkURL: connectivityCheckURL)
    }
}
