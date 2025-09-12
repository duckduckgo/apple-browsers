# NetworkQualityMonitor

A network quality testing framework that provides pre-flight network connectivity and performance checks. This package helps ensure optimal browser performance by testing network conditions.

## Overview

NetworkQualityMonitor performs a suite of network tests to assess:
- **HTTP Response Times** - Latency measurements across multiple endpoints
- **Bandwidth** - Download and upload speed testing
- **DNS Resolution** - Domain name resolution performance
- **Buffer Bloat** - Network congestion under load

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
- Measures HTTP HEAD request latency across multiple endpoints
- Takes 15 samples per endpoint by default
- Calculates accurate median values (properly handles even/odd sample counts)
- Calculates percentiles (P50, P95) and variance
- Uses best-performing site with penalties for slower sites

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
- Combines individual test results into overall score (0-100)
- Determines network quality rating: Excellent/Good/Fair/Poor
- Weights different metrics appropriately

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

Default configuration includes:
- **Latency**: 15 samples per endpoint, 5s timeout
- **Bandwidth**: 2 runs per server, 30s timeout  
- **Upload**: 50MB chunks x 2, 45s timeout
- **DNS**: Multiple popular domains

## Network Quality Ratings

| Score | Quality | Emoji | Description |
|-------|---------|-------|-------------|
| 80-100 | Excellent | 🟢 | Optimal performance |
| 60-79 | Good | 🟡 | Good for most tasks |
| 40-59 | Fair | 🟠 | May experience issues |
| 0-39 | Poor | 🔴 | Significant issues likely |

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
