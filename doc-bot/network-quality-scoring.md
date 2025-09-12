---
alwaysApply: false
title: "NetworkQualityMonitor Scoring Algorithm"
description: "Comprehensive documentation of the NetworkQualityMonitor scoring algorithm optimized for browser performance"
keywords: ["NetworkQualityMonitor", "scoring", "algorithm", "latency", "bandwidth", "variance", "P95", "browser", "performance"]
---

# NetworkQualityMonitor Scoring Algorithm

## Overview
NetworkQualityMonitor uses a browser-optimized scoring algorithm that prioritizes latency and consistency over raw bandwidth, accurately reflecting real-world browsing experience.

## Component Weights (Browser-Optimized)
- **HTTP Response: 60%** - Latency dominates browser experience
- **Bandwidth: 25%** - Diminishing returns above minimum thresholds
- **DNS: 10%** - Only affects first page load (cached thereafter)
- **Buffer Bloat: 5%** - Minimal impact on typical browsing

## HTTP Response Testing (Most Critical)

### Smart Testing Methodology
1. **Warm-up Phase**: First request to each endpoint is discarded (eliminates DNS/TLS cold start)
2. **Interleaved Sampling**: Endpoints tested in rounds with shuffling (avoids TCP reuse bias)
3. **Geographic Reality**: Uses median of all site medians (not best site + penalties)

### Variance Tracking (Dual System)
- **Standard Deviation**: Consistency measure across samples
- **P95-P50 Spread**: Difference between worst-case and typical latency

### Scoring Penalties
```swift
httpResponseScore = baseScore - variancePenalty - p95Penalty - failurePenalty
```

**Variance Penalties (0-55 points):**
- <50ms std dev: 0 points
- 50-100ms: -10 points
- 100-200ms: -25 points  
- 200-400ms: -40 points
- >400ms: -55 points

**P95 Spread Penalties (0-20 points):**
- <100ms: 0 points
- 100-200ms: -5 points
- 200-400ms: -10 points
- 400-600ms: -15 points
- >600ms: -20 points

**Total possible variance penalty: 75 points** (correctly penalizes jittery connections)

## Bandwidth Thresholds (Realistic for Browsing)

### Download (85% of bandwidth score)
- **Excellent**: >100 Mbps (instant loads, 4K streaming)
- **Good**: 25-100 Mbps (smooth browsing, HD perfect)
- **Fair**: 10-25 Mbps (basic browsing works)
- **Poor**: <10 Mbps (modern web sluggish)

### Upload (15% of bandwidth score)
- **Good**: >10 Mbps (HD video calls)
- **Fair**: 5-10 Mbps (may reduce quality)
- **Poor**: <5 Mbps (struggles with video)

## Latency Thresholds
- **Excellent**: <150ms (CDN-optimized services)
- **Good**: 150-250ms (normal production services)
- **Fair**: 250-400ms (acceptable but could optimize)
- **Poor**: >400ms (needs investigation)

## Overall Quality Ratings
- **80-100**: Excellent (instant loads, smooth experience)
- **60-79**: Good (normal browsing, HD streaming works)
- **40-59**: Fair (basic browsing OK, may see delays)
- **0-39**: Poor (sluggish experience, frequent issues)

## Key Implementation Details

### Why These Weights?
- Most performance issues are latency, not bandwidth
- Bandwidth above 25 Mbps has diminishing returns for browsing
- Consistency (low variance) critical for user experience
- DNS only impacts first visit to a domain

### Example Scenarios
- **Fiber (50ms, 20ms variance, 300 Mbps)**: Score ~85-95 (Excellent)
- **Cable (120ms, 50ms variance, 100 Mbps)**: Score ~70-80 (Good)
- **DSL (200ms, 80ms variance, 25 Mbps)**: Score ~50-65 (Fair)
- **Poor Mobile (445ms, 713ms variance, 13 Mbps)**: Score ~20-35 (Poor)