---
alwaysApply: false
title: "NetworkQualityMonitor Testing Framework"
description: "Comprehensive network quality testing framework for pre-flight checks including latency, bandwidth, DNS, and buffer bloat testing"
keywords: ["NetworkQualityMonitor", "network", "testing", "latency", "bandwidth", "DNS", "buffer bloat", "performance", "pre-flight", "connectivity"]
---

# NetworkQualityMonitor Testing Framework

## Overview

The NetworkQualityMonitor is a comprehensive network quality testing framework designed for the DuckDuckGo Privacy Browser. It provides pre-flight network connectivity and performance checks to ensure optimal browser performance.

## Architecture Principles

### SOLID Design
- **Single Responsibility**: Each tester handles one specific network metric
- **Open/Closed**: Protocol-based design allows extension without modification
- **Dependency Injection**: All dependencies injected for testability
- **Interface Segregation**: Focused protocols for each test type

### Component Structure
```
NetworkQualityMonitor (Orchestrator)
├── HttpResponseTester (Latency)
├── BandwidthTester (Speed)
├── DNSTester (Resolution)
├── BufferBloatTester (Congestion)
└── NetworkScoreCalculator (Scoring)
```

## Test Implementation Details

### HTTP Response Testing (Latency)
- **Multi-endpoint sampling**: Tests CDN endpoints (CloudFlare, Fastly, CloudFront)
- **Statistical analysis**: Calculates median, mean, standard deviation, CV
- **Smart aggregation**: Best site selection with weighted penalties
- **Metrics**: P50/P95 percentiles, variance, failure rate

### Bandwidth Testing
- **Server selection**: Quick 10MB test, then full test on best servers
- **Download measurement**: Multiple runs, returns maximum speed
- **Upload measurement**: Chunked uploads (50MB x 2)
- **Optimization**: Range requests, cache-busting, timeout protection

### DNS Testing
- **Domain resolution**: Popular domains (google.com, cloudflare.com)
- **Timing precision**: CFAbsoluteTime for microsecond accuracy
- **Failure tracking**: Resolution success/failure rates
- **System resolver**: Uses native DNS resolution

### Buffer Bloat Testing
- **Baseline measurement**: Unloaded network latency
- **Load testing**: Concurrent downloads during latency measurement
- **Grade assignment**: A-F based on latency increase percentage
- **Real-time impact**: Critical for video calls, gaming

## Scoring Algorithm

### Component Weights
- HTTP Response: 25%
- Bandwidth: 35%
- DNS: 15%
- Buffer Bloat: 25%

### Quality Ratings
- **Excellent (80-100)**: Optimal performance
- **Good (60-79)**: Good for most tasks
- **Fair (40-59)**: May experience issues
- **Poor (0-39)**: Significant issues likely

## Testing Best Practices

### Unit Testing
```swift
// Use protocol-based mocks
class MockHttpResponseTester: HttpResponseTesting {
    func performTest(...) async throws -> HttpResponseResult {
        // Return deterministic results
    }
}
```

### Integration Testing
- Mock NetworkSession for controlled responses
- Test error scenarios and edge cases
- Verify progress callback behavior

### Performance Testing
- Monitor memory usage during large downloads
- Verify timeout handling
- Test concurrent execution

## Usage Patterns

### Basic Implementation
```swift
let monitor = NetworkQualityMonitor()
let results = try await monitor.runTest()
print("Quality: \(results.quality.rawValue)")
```

### With Progress Reporting
```swift
monitor.progressCallback = { progress, message in
    // Update UI with progress
}
```

### Custom Configuration
```swift
let config = TestConfiguration(
    latencyTestURLs: customURLs,
    latencySamplesPerEndpoint: 20
)
let monitor = NetworkQualityMonitor(configuration: config)
```

## Security Considerations

- **HTTPS only**: All endpoints use secure connections
- **No user data**: Only generic test payloads
- **Certificate validation**: Standard validation enabled
- **Rate limiting**: Built-in delays between samples

## Error Handling

### Error Types
- `invalidResponse`: HTTP errors, malformed data
- `allTestsFailed`: Complete connectivity loss
- `insufficientData`: Not enough samples collected
- `timeout`: Test exceeded time limit

### Recovery Strategies
- Continue testing if individual endpoints fail
- Provide partial results when possible
- Clear error reporting with localized descriptions

## Performance Optimizations

- **HEAD requests**: Minimal data for latency tests
- **Range requests**: Efficient server selection
- **Connection reuse**: URLSession connection pooling
- **Memory streaming**: Large downloads streamed, not buffered

## Package Integration

### Adding to Project
1. Add NetworkQualityMonitor package dependency
2. Import NetworkQualityMonitor module
3. Initialize with configuration
4. Handle async test execution

### Debug Menu Integration
- Available under Debug → Network Quality
- Individual test execution
- Detailed result display

## Future Enhancements

- IPv6 testing separation
- Jitter analysis
- Packet loss detection
- Geographic server selection
- Historical trending