---
alwaysApply: false
title: "NetworkQualityMonitor Scoring Algorithm"
description: "Comprehensive documentation of the NetworkQualityMonitor scoring algorithm optimized for browser performance"
keywords: ["NetworkQualityMonitor", "scoring", "latency", "bandwidth", "DNS", "buffer bloat", "network quality", "coefficient of variation", "CV", "standard deviation"]
---

# NetworkQualityMonitor Scoring Algorithm

## Overview

NetworkQualityMonitor uses a browser-optimized scoring algorithm that prioritizes latency and consistency over raw bandwidth. The scoring is weighted as follows:

- **HTTP Response (40%)**: Most critical for browser experience
- **Bandwidth (35%)**: Important for media and downloads  
- **DNS (10%)**: Foundation of all connections
- **Buffer Bloat (15%)**: Network congestion under load

## HTTP Response Scoring (40% Weight)

### Measurement Process

1. **Endpoints**: Tests 10+ global endpoints including DuckDuckGo, major CDNs, and popular platforms
2. **Sampling**: 15 requests per endpoint with interleaved ordering to avoid bias
3. **Statistical Analysis**:
   - Calculates median response time for each site
   - Uses **median of all site medians** for overall response time
   - Calculates standard deviation for each site's measurements
   - Uses **median of all site standard deviations** for consistency metric

### Response Time Calculation

```swift
// For each site: calculate median of its measurements
let siteMedians = sites.map { calculateMedian($0.measurements) }

// Overall response time: median of all site medians
let overallResponseTime = median(siteMedians)
```

This approach:
- Resists outliers at both per-site and cross-site levels
- Provides typical latency experience across geographic regions
- Doesn't get skewed by one particularly fast CDN or slow server

### Consistency Calculation

```swift
// For each site: calculate standard deviation of its measurements
let siteStdDevs = sites.map { calculateStdDev($0.measurements) }

// Overall consistency: median of all site standard deviations
let overallStdDev = median(siteStdDevs)
```

This avoids mixing different latency populations (e.g., 20ms CDN vs 300ms cross-ocean).

### Coefficient of Variation (CV) Scoring

The scoring uses Coefficient of Variation to fairly compare different latency ranges:

```swift
// CV = stdDev / mean - normalizes variance relative to baseline
let coefficientOfVariation = stdDev / averageResponseTime

// Apply CV-based penalty (fairer than raw standard deviation)
// Example: 10ms variance on 50ms latency (20% CV) penalized more than
//         10ms variance on 200ms latency (5% CV)
```

#### CV Penalty Thresholds

- **< 10% CV**: No penalty (excellent consistency)
- **10-20% CV**: -10 points (good consistency)
- **20-35% CV**: -25 points (acceptable consistency)
- **35-50% CV**: -40 points (poor consistency)
- **50-75% CV**: -55 points (very poor consistency)
- **> 75% CV**: -70 points (severe instability)

### Response Time Thresholds

- **Excellent (100 pts)**: < 50ms - Instantaneous
- **Very Good (85 pts)**: 50-75ms - Very responsive
- **Good (70 pts)**: 75-100ms - Target for production
- **Fair (55 pts)**: 100-150ms - Slight delay noticeable
- **Below Average (40 pts)**: 150-200ms - Definitely noticeable
- **Poor (25 pts)**: 200-300ms - Users frustrated
- **Very Poor (10 pts)**: > 300ms - Severe issues

## Bandwidth Scoring (35% Weight)

### Download (85% of bandwidth score)

Tests multiple endpoints with adaptive sizing:
- CloudFlare: 25MB
- OVH: 10MB  
- Hetzner: 10MB

#### Download Speed Thresholds

- **100+ Mbps (100 pts)**: Excellent - instant page loads, 4K streaming
- **50-100 Mbps (85 pts)**: Very good - smooth HD streaming
- **25-50 Mbps (70 pts)**: Good - normal browsing experience
- **10-25 Mbps (55 pts)**: Fair - acceptable for most tasks
- **5-10 Mbps (40 pts)**: Below average - noticeable delays
- **2-5 Mbps (25 pts)**: Poor - significant limitations
- **< 2 Mbps (10 pts)**: Very poor - barely usable

### Upload (15% of bandwidth score)

Tests 5MB chunks to multiple endpoints.

#### Upload Speed Thresholds

- **50+ Mbps (100 pts)**: Excellent
- **20-50 Mbps (85 pts)**: Very good
- **10-20 Mbps (70 pts)**: Good
- **5-10 Mbps (55 pts)**: Fair
- **2-5 Mbps (40 pts)**: Below average
- **1-2 Mbps (25 pts)**: Poor
- **< 1 Mbps (10 pts)**: Very poor

## DNS Scoring (10% Weight)

### Measurement

- Tests 11 popular domains
- Uses median resolution time (resistant to outliers)
- Measures with `CFHostStartInfoResolution`

### DNS Resolution Thresholds

- **< 10ms (100 pts)**: Excellent - likely cached
- **10-30ms (85 pts)**: Good - fast resolver
- **30-50ms (70 pts)**: Fair - acceptable
- **50-100ms (50 pts)**: Poor - noticeable delay
- **> 100ms (30 pts)**: Very poor - severe issues

## Buffer Bloat Scoring (15% Weight)

### Measurement Process

1. **Baseline**: 10 latency measurements without load
2. **Loaded**: 15 measurements during concurrent download
3. **Calculation**: `loadedLatency - baselineLatency`

### Buffer Bloat Grades

- **Grade A (90 pts)**: < 5ms increase - No congestion
- **Grade B (70 pts)**: 5-30ms increase - Minimal impact
- **Grade C (50 pts)**: 30-100ms increase - Noticeable under load
- **Grade D (30 pts)**: 100-200ms increase - Significant congestion
- **Grade F (10 pts)**: > 200ms increase - Severe issues

## Overall Score Calculation

```swift
overallScore = (httpResponse * 0.40) +
               (bandwidth * 0.35) +
               (dns * 0.10) +
               (bufferBloat * 0.15)
```

## Quality Determination

```swift
func determineQuality(from score: Double) -> NetworkQuality {
    switch score {
    case 80...: return .excellent  // 🟢
    case 60..<80: return .good     // 🟡
    case 40..<60: return .fair     // 🟠
    default: return .poor          // 🔴
    }
}
```

## Key Design Decisions

1. **Median-based calculations**: Resistant to outliers and network spikes
2. **Coefficient of Variation**: Fair comparison across different latency ranges
3. **Browser-optimized weights**: Prioritizes latency over bandwidth
4. **Interleaved testing**: Avoids consecutive requests to same endpoint
5. **Per-site then overall**: Avoids mixing different geographic populations