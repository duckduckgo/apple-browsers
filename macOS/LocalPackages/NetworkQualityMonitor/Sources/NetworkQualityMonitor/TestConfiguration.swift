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
            // We use full URLs here as latency is calculating by using HEAD requests, which better resembles real world use.

            // DuckDuckGo endpoints - most important for DDG browser
            URL(string: "https://duckduckgo.com/")!,
            // Common user destinations
            URL(string: "https://www.youtube.com/")!,
            URL(string: "https://www.facebook.com/")!,
            URL(string: "https://www.amazon.com/")!,
            URL(string: "https://www.reddit.com/")!,
            URL(string: "https://www.twitter.com/")!,
            URL(string: "https://www.netflix.com/")!,
            URL(string: "https://www.github.com/")!,

            // CDNs and infrastructure
            URL(string: "https://www.cloudflare.com/")!,
            URL(string: "https://aws.amazon.com/")!
        ],
        bandwidthTestURLs: [
            URL(string: "https://speed.cloudflare.com/__down?bytes=104857600")!,  // 100MB
            URL(string: "https://proof.ovh.net/files/100Mb.dat")!,
            URL(string: "https://speed.hetzner.de/100MB.bin")!,
            URL(string: "http://speedtest.tele2.net/100MB.zip")!
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
        latencySamplesPerEndpoint: 15,  // Increased for more stable statistics
        bandwidthRunsPerServer: 2,
        uploadChunkSize: 52_428_800,  // 50MB
        uploadChunkCount: 2,
        latencyTestTimeout: 5,
        bandwidthTestTimeout: 30,
        uploadTestTimeout: 45,
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
