# NetworkQualityMonitor

A network quality testing framework optimized for real-world browser performance evaluation. This package provides accurate pre-flight connectivity checks to guide performance testing decisions.

## Overview

NetworkQualityMonitor performs browser-centric network tests with realistic scoring:
- **HTTP Response Times (60% weight)** - Latency and consistency measurements with variance penalties
- **Bandwidth (25% weight)** - Download/upload speeds with browser-appropriate thresholds  
- **DNS Resolution (10% weight)** - First-visit impact only (cached thereafter)
- **Buffer Bloat (5% weight)** - Minimal impact on typical browsing

## Architecture

The package follows SOLID principles with dependency injection for testability:

```
NetworkQualityMonitor (Main Coordinator)
├── HttpResponseTester
├── BandwidthTester  
├── DNSTester
├── BufferBloatTester
└── NetworkScoreCalculator
```

## Key Components

### NetworkQualityMonitor
Main orchestrator that coordinates all test services and provides progress reporting via callbacks. Uses dependency injection to allow custom test implementations for testing.

### Test Services

#### HttpResponseTester
- **Smart Testing**: Warm-up phase discards first "cold" request to each endpoint
- **Interleaved Sampling**: Avoids consecutive requests to same endpoint for unbiased results
- **Dual Variance Tracking**: Standard deviation + P95-P50 spread for consistency assessment
- **Geographic Reality**: Uses median of all sites to reflect actual cross-region latencies
- **Percentile Analysis**: Tracks P50 (typical) and P95 (worst-case) latencies

#### BandwidthTester  
- Downloads test files to measure download speed
- Uploads data chunks to measure upload speed
- Performs quick server selection before full tests
- Returns speeds in Mbps

#### DNSTester
- Resolves configured domains to measure DNS performance
- Tracks resolution times and failure rates
- Critical for identifying DNS-related issues

#### BufferBloatTester
- Measures latency under network load using accurate median calculations
- Compares baseline vs loaded latency
- Assigns grades (A-F) based on latency increase
- Helps identify network congestion issues

### NetworkScoreCalculator
- **Browser-Optimized Weights**: 60% latency, 25% bandwidth, 10% DNS, 5% buffer bloat
- **Variance Penalties**: Up to 75 points deducted for inconsistent connections
- **Realistic Thresholds**: 
  - Latency: <150ms excellent, 150-250ms good, 250-400ms fair
  - Download: 25+ Mbps good, 10-25 Mbps fair (browsing, not streaming)
  - Upload: 10+ Mbps good, 5-10 Mbps fair (video calls)

## Usage

### Basic Usage

```swift
import NetworkQualityMonitor

// Create monitor with default configuration
let monitor = NetworkQualityMonitor()

// Run complete test suite
let results = try await monitor.runTest()

print("Network Quality: \(results.quality.rawValue) \(results.quality.emoji)")
print("Overall Score: \(results.overallScore.overall)/100")
```

### With Progress Reporting

```swift
let monitor = NetworkQualityMonitor()

// Set progress callback
monitor.progressCallback = { progress, message in
    print("[\(Int(progress * 100))%] \(message)")
}

let results = try await monitor.runTest()
```

### Custom Configuration

```swift
let customConfig = TestConfiguration(
    latencyTestURLs: [URL(string: "https://example.com")!],
    bandwidthTestURLs: [URL(string: "https://example.com/test.bin")!],
    uploadTestURLs: [URL(string: "https://example.com/upload")!],
    dnsTestDomains: ["example.com"],
    latencySamplesPerEndpoint: 10,
    bandwidthRunsPerServer: 3
)

let monitor = NetworkQualityMonitor(configuration: customConfig)
```

### Quick Connectivity Check

```swift
let monitor = NetworkQualityMonitor()
let hasConnectivity = await monitor.checkConnectivity()
```

## Test Configuration

Default configuration optimized for speed and accuracy:
- **Latency**: 15 samples per endpoint, 5s timeout
- **Bandwidth**: 50MB files, 1 run per server, 20s timeout
- **Upload**: 20MB chunks x 2 (40MB total), 25s timeout
- **DNS**: Multiple popular domains

### Performance Optimizations
- **Download**: 50MB files (reduced from 100MB) - provides 4-16 second measurement window
- **Upload**: 40MB total (reduced from 100MB) - sufficient for accurate speed detection
- **Total data**: ~190MB (down from 900MB) - much faster completion
- **Timeouts**: Reduced by 40% while maintaining reliability

## Network Quality Ratings

| Score | Quality | Emoji | Browser Experience |
|-------|---------|-------|--------------------|
| 80-100 | Excellent | 🟢 | Instant page loads, smooth experience |
| 60-79 | Good | 🟡 | Normal browsing, HD streaming works |
| 40-59 | Fair | 🟠 | Basic browsing OK, may see delays |
| 0-39 | Poor | 🔴 | Sluggish experience, frequent issues |

## Scoring Algorithm Details

### Latency Scoring (60% of total)
- **Base Score**: Response time thresholds
- **Variance Penalty**: 0-55 points based on standard deviation
- **P95 Penalty**: 0-20 points based on P95-P50 spread
- **Failure Penalty**: Up to 50 points for request failures

### Example Scores
- **Fiber (50ms, low variance)**: ~85-95 (Excellent)
- **Cable (120ms, moderate variance)**: ~70-80 (Good)
- **DSL (200ms, higher variance)**: ~50-65 (Fair)
- **Poor Mobile (400ms+, high variance)**: ~20-40 (Poor)

## Testing

### Unit Tests

```bash
swift test
```

The package includes comprehensive unit tests with mocks for all network operations:
- `NetworkQualityMonitorTests` - Core functionality tests
- `NetworkQualityMonitorMockTests` - Tests using mock implementations

### Mock Implementations

Mock implementations are provided for testing:
- `MockHttpResponseTester`
- `MockBandwidthTester`
- `MockDNSTester`
- `MockBufferBloatTester`
- `MockNetworkSession`
