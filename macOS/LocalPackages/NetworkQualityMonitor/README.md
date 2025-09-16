# NetworkQualityMonitor

A comprehensive network quality testing framework for macOS that measures and analyzes various network performance metrics for browser and application usage.

## Overview

NetworkQualityMonitor performs detailed network quality assessments by testing:
- **HTTP Response Times (40% weight)** - Measures latency to various global endpoints with variance analysis
- **Bandwidth (35% weight)** - Tests download and upload speeds
- **DNS Resolution (10% weight)** - Measures domain name resolution performance
- **Buffer Bloat (15% weight)** - Detects network congestion issues

## Architecture

The package follows SOLID principles with a modular, testable design:

```
NetworkQualityMonitor
├── Services/
│   ├── HttpResponseTester     # HTTP latency testing
│   ├── BandwidthTester        # Speed testing
│   ├── DNSTester              # DNS resolution
│   ├── BufferBloatTester      # Buffer bloat detection
│   └── NetworkScoreCalculator # Score computation
├── Protocols/
│   └── NetworkTestProtocols   # Service interfaces
├── Configuration/
│   └── TestConfiguration      # Test parameters
└── UI/
    └── NetworkQualityView     # SwiftUI interface
```

## How Metrics Are Calculated

### HTTP Response Score (40% weight)

#### Measurement Process
1. **Endpoint Testing**: Tests 10 global endpoints including DuckDuckGo, major CDNs, and popular platforms
2. **Sampling**: 15 requests per endpoint with interleaved ordering to avoid bias
3. **Statistical Analysis**:
   - Calculates median response time for each site
   - Uses median of all site medians for overall response time
   - Calculates standard deviation for each site's measurements
   - Uses median of all site standard deviations for consistency metric

#### Scoring Algorithm
```swift
// Base score from response time
baseScore = scoreResponseTime(adjustedResponseTime)

// Calculate Coefficient of Variation (CV) = stdDev / mean
// Normalizes variance relative to baseline latency for fair comparison
coefficientOfVariation = stdDev / averageResponseTime

// Apply CV-based penalty (fairer than raw standard deviation)
// <10% CV: no penalty, 10-20%: -10pts, 20-35%: -25pts, >75%: -70pts
finalScore = baseScore - cvPenalty - p95Penalty - failurePenalty
```

#### Response Time Thresholds
- **Excellent (100 points)**: < 50ms
- **Good (85 points)**: 50-100ms
- **Fair (60 points)**: 100-200ms
- **Poor (30 points)**: > 200ms

#### Statistical Metrics
- **Failure Rate**: `(expected_attempts - successful_attempts) / expected_attempts`
- **Standard Deviation**: Median of per-site standard deviations (typical consistency within endpoints)
- **Coefficient of Variation (CV)**: `stdDev / mean` - Normalizes variance for fair comparison
  - 10ms stdDev on 50ms mean = 20% CV (moderate penalty)
  - 10ms stdDev on 200ms mean = 5% CV (no penalty)
- **Percentiles**: Tracks P50 (median) and P95 (worst-case) for comprehensive analysis

### Bandwidth Score (35% weight)

#### Download Testing (85% of bandwidth score)
- **Process**: Downloads from CloudFlare (25MB), OVH (10MB), and Hetzner (10MB)
- **Calculation**: `totalBytes / totalTime` converted to Mbps
- **Scoring Scale**:
  - 100+ Mbps: 100 points
  - 50-100 Mbps: 85 points
  - 25-50 Mbps: 70 points
  - 10-25 Mbps: 50 points
  - < 10 Mbps: 30 points

#### Upload Testing (15% of bandwidth score)
- **Process**: Uploads 5MB chunks to multiple endpoints
- **Scoring Scale**:
  - 50+ Mbps: 100 points
  - 20-50 Mbps: 85 points
  - 10-20 Mbps: 70 points
  - 5-10 Mbps: 50 points
  - < 5 Mbps: 30 points

#### Combined Score
```swift
bandwidthScore = (downloadScore * 0.85) + (uploadScore * 0.15)
```

### DNS Score (10% weight)

#### Measurement
- **Domains Tested**: 11 popular domains including duckduckgo.com, google.com, cloudflare.com
- **Resolution Method**: Uses `CFHostStartInfoResolution` with `.userInitiated` priority
- **Statistical Analysis**: Uses median resolution time (resistant to outliers)

#### Scoring Thresholds
- **Excellent (100 points)**: < 10ms
- **Good (85 points)**: 10-30ms
- **Fair (70 points)**: 30-50ms
- **Poor (50 points)**: 50-100ms
- **Very Poor (30 points)**: > 100ms

#### Implementation Details
```swift
// Wrapped in Task to avoid priority inversion
let result = await Task(priority: .userInitiated) {
    let startTime = CFAbsoluteTimeGetCurrent()
    let resolved = CFHostStartInfoResolution(host, .addresses, nil)
    let endTime = CFAbsoluteTimeGetCurrent()
    return (resolved, (endTime - startTime) * 1000)
}.value
```

### Buffer Bloat Score (15% weight)

#### Measurement Process
1. **Baseline Phase**: 10 latency measurements without load
2. **Loaded Phase**: 15 measurements during concurrent download
3. **Calculation**: `loadedLatency - baselineLatency`

#### Grading System
- **Grade A (100 points)**: < 5ms increase - Excellent, no congestion
- **Grade B (85 points)**: 5-30ms increase - Good, minimal impact
- **Grade C (70 points)**: 30-100ms increase - Fair, noticeable under load
- **Grade D (50 points)**: 100-200ms increase - Poor, significant congestion
- **Grade F (30 points)**: > 200ms increase - Very poor, severe issues

### Overall Score Calculation

```swift
overallScore = (httpResponse * 0.40) +
               (bandwidth * 0.35) +
               (dns * 0.10) +
               (bufferBloat * 0.15)
```

### Quality Determination
```swift
func determineQuality(from score: Double) -> NetworkQuality {
    switch score {
    case 80...: return .excellent
    case 60..<80: return .good
    case 40..<60: return .fair
    default: return .poor
    }
}
```

## Usage

### Basic Usage

```swift
import NetworkQualityMonitor

let monitor = NetworkQualityMonitor()

// Run complete test suite
let results = try await monitor.runTests { progress in
    print("Progress: \(progress)")
}

print("Overall Score: \(results.overall)")
print("Quality: \(results.quality)")
```

### SwiftUI Integration

```swift
import SwiftUI
import NetworkQualityMonitor

struct ContentView: View {
    var body: some View {
        NetworkQualityView()
    }
}
```

### Custom Configuration

```swift
let customConfig = TestConfiguration(
    latencyTestURLs: [/* your URLs */],
    bandwidthTestURLs: [/* speed test URLs */],
    uploadTestURLs: [/* upload endpoints */],
    dnsTestDomains: [/* domains to resolve */],
    latencySamplesPerEndpoint: 15,
    bandwidthRunsPerServer: 1,
    uploadChunkSize: 5_242_880, // 5MB
    uploadChunkCount: 1,
    latencyTestTimeout: 5,
    bandwidthTestTimeout: 20,
    uploadTestTimeout: 15,
    connectivityCheckURL: URL(string: "https://example.com/check")!
)

let monitor = NetworkQualityMonitor(configuration: customConfig)
```

### Focused Configurations

Extract specific configurations for individual services:

```swift
let httpConfig = configuration.httpResponseConfig()
let bandwidthConfig = configuration.bandwidthConfig()
let dnsConfig = configuration.dnsConfig()
let bufferBloatConfig = configuration.bufferBloatConfig()
```

### Individual Test Services

```swift
// Test only HTTP response times
let httpTester = HttpResponseTester()
let httpResult = try await httpTester.performTest(
    configuration: .standard,
    progressCallback: { print($0) }
)

// Test only bandwidth
let bandwidthTester = BandwidthTester()
let downloadSpeed = try await bandwidthTester.performDownloadTest(
    configuration: .standard,
    progressCallback: { print($0) }
)
```

## Test Configuration Details

### Default Endpoints

**Latency Testing URLs**:
- DuckDuckGo: Main site and tracking endpoint
- CDNs: CloudFlare (300+ locations), Fastly (80+ POPs), AWS CloudFront (450+ POPs)
- Google CDN, jsDelivr CDN
- Major platforms: YouTube, Facebook, GitHub API

**Bandwidth Testing**:
- CloudFlare Speed Test: 25MB download
- OVH Proof: 10MB download
- Hetzner: 10MB download
- Total: ~45MB for comprehensive speed testing

**DNS Test Domains**:
```swift
["duckduckgo.com", "google.com", "cloudflare.com", "apple.com",
 "amazon.com", "microsoft.com", "facebook.com", "netflix.com",
 "github.com", "stackoverflow.com", "wikipedia.org"]
```

## Statistical Methods

### Median Calculation
Used for DNS and buffer bloat measurements to resist outliers:
```swift
func median(of values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let count = sorted.count

    if count % 2 == 0 {
        return (sorted[count/2 - 1] + sorted[count/2]) / 2.0
    } else {
        return sorted[count/2]
    }
}
```

### Standard Deviation
Used for response time variance to measure consistency:
```swift
func calculateStandardDeviation(_ measurements: [Double]) -> Double {
    guard measurements.count > 1 else { return 0 }

    let mean = measurements.reduce(0, +) / Double(measurements.count)
    let squaredDifferences = measurements.map { pow($0 - mean, 2) }
    let variance = squaredDifferences.reduce(0, +) / Double(measurements.count - 1)

    return sqrt(variance)
}
```

### Coefficient of Variation (CV) Penalty
Applied based on relative consistency (stdDev/mean):
- CV < 10%: No penalty (excellent consistency)
- CV 10-20%: 10 point penalty (good consistency)
- CV 20-35%: 25 point penalty (acceptable consistency)
- CV 35-50%: 40 point penalty (poor consistency)
- CV 50-75%: 55 point penalty (very poor consistency)
- CV > 75%: 70 point penalty (severe instability)

This approach fairly compares different latency ranges - a 10ms variance on 50ms latency (20% CV) is penalized more than 10ms variance on 200ms latency (5% CV).

## Performance Optimizations

1. **Concurrent Testing**: Tests run in parallel where possible
2. **Adaptive Bandwidth Testing**: Can stop early for very slow connections
3. **Interleaved HTTP Requests**: Avoids consecutive requests to same endpoint
4. **Priority Management**: DNS uses `.userInitiated` to avoid thread priority inversion
5. **Statistical Robustness**: Median for outlier resistance, standard deviation for consistency

## Testing

The package includes comprehensive test coverage:

```bash
swift test
```

### Test Suite
- **NetworkQualityMonitorTests**: Core functionality and calculations
- **NetworkQualityMonitorMockTests**: Mock implementations verification
- **Statistical Tests**: Median calculation with various data sets
- **High Variance Tests**: Ensures poor consistency is properly penalized

### Mock Implementations

All service protocols have mock implementations:

```swift
let mockHttpTester = MockHttpResponseTester()
let mockBandwidthTester = MockBandwidthTester()
let mockDNSTester = MockDNSTester()
let mockBufferBloatTester = MockBufferBloatTester()
```

## Requirements

- macOS 11.4+
- Swift 5.0+
- SwiftUI for UI components

## License

Copyright © 2024 DuckDuckGo. All rights reserved.
Licensed under the Apache License, Version 2.0