---
alwaysApply: false
title: "Network Quality Variance Scoring Using Coefficient of Variation"
description: "Guide to NetworkQualityMonitor's dual variance system: millisecond display with CV-based scoring"
keywords: ["variance", "coefficient of variation", "CV", "network quality", "performance testing", "statistical significance", "test iterations", "latency variance", "milliseconds"]
---

# Network Quality Variance Scoring Using Coefficient of Variation

## Overview

NetworkQualityMonitor displays variance in **milliseconds** (user-friendly) but scores using **Coefficient of Variation (CV)** internally. This provides fair comparison across different latency ranges.

## Display vs Scoring

- **UI Display**: Shows variance in milliseconds (e.g., "5.2 ms (10.4%)")
- **Internal Scoring**: Uses CV = (stdDev/mean) × 100 for penalties
- **Quality Labels**: Based on CV percentage thresholds

## Why CV for Scoring?

A 10ms variance means different things at different latencies:
- 10ms variance on 50ms latency = 20% CV (moderate issue)
- 10ms variance on 200ms latency = 5% CV (excellent consistency)

Using CV ensures fair scoring regardless of base latency.

## CV Thresholds and Test Iterations

| CV Range | Quality | Penalty | Test Iterations | Testing Impact |
|----------|---------|---------|-----------------|----------------|
| <10% | Excellent | 0 pts | ~30 iterations | Quick reliable tests |
| 10-20% | Good | -20 pts | ~100 iterations | Reasonable test time |
| 20-40% | Fair | -40 pts | ~400 iterations | Lengthy test cycles |
| >40% | Poor | -60 to -80 pts | 1000+ iterations | Practically unreliable |

## Implementation

```swift
// Display shows milliseconds
value: String(format: "%.1f ms", responseVariance)

// Quality label uses CV internally
let cv = (variance / avgResponseTime) * 100
if cv < 10 { return "Excellent" }
else if cv < 20 { return "Good" }
else if cv < 40 { return "Fair" }
else { return "Poor" }

// Scoring penalty based on CV
switch coefficientOfVariation {
case ..<10: penalty = 0
case 10..<20: penalty = 20
case 20..<40: penalty = 40
case 40..<60: penalty = 60
default: penalty = 80
}
```

## Statistical Analysis

Smart Warm-up Phase:
  - Initial "cold" request to each endpoint (DNS resolution, TLS handshake)
  - These measurements are discarded to eliminate first-request bias
  - Ensures subsequent measurements reflect warm connection performance

Interleaved Sampling:
  - Endpoints tested in randomized rounds (not consecutively)
  - Prevents TCP connection reuse artifacts
  - 15 samples per endpoint with 50ms delays between measurements
  - More representative of real browsing patterns

Per-Site Calculations:
  - Calculate median response time (robust to outliers)
  - Calculate variance and standard deviation
  - Track individual site consistency

Global Aggregation:
  adjustedResponseTime = median(all_site_medians)

Variance Scoring:
  - Display: Standard deviation in milliseconds (user-friendly)
  - Scoring: Coefficient of Variation (CV = stdDev/mean × 100)
  - CV determines penalties based on relative variance

Dual Penalty System:
  1. CV-based: Relative variance penalties (up to 80 points)
  2. P95-P50 Spread: Percentage-based spike penalties (up to 40 points)

## Key Metrics

- **averageResponseTime**: Median of all site medians (geographic reality)
- **responseVariance**: Standard deviation in ms (consistency indicator)
- **latencySpread**: P95-P50 difference (spike detection)
- **p50/p95**: Percentiles for typical and worst-case assessment

## Testing Impact

The CV directly determines test reliability:
- **<10% CV**: Standard test suite (30-50 iterations)
- **10-20% CV**: Increase to 100-150 iterations
- **20-40% CV**: Need 400+ iterations for confidence
- **>40% CV**: Results unreliable even with 1000+ iterations

## Key Principle

**Variance has HUGE impact on performance testing.** High CV connections can turn a 1-hour test into a 10-hour marathon with less reliable results than a 30-minute test on a stable connection.