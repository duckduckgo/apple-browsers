---
alwaysApply: false
title: "NetworkQualityMonitor Test Configuration"
description: "Test configuration parameters and optimization details"
keywords: ["NetworkQualityMonitor", "test", "configuration", "bandwidth", "upload", "download", "file size", "optimization", "timeout"]
---

# NetworkQualityMonitor Test Configuration

## Optimized Test Parameters

The NetworkQualityMonitor uses carefully tuned parameters to balance speed and accuracy for browser performance testing.

## Test Phases and Data Sizes

### HTTP Response Testing (Latency)
- **Samples**: 15 per endpoint
- **Endpoints**: ~12 globally distributed CDNs and services
- **Methodology**: Warm-up phase + interleaved sampling
- **Timeout**: 5 seconds
- **Total time**: ~3-4 minutes

### Bandwidth Testing (Download)
- **File size**: 50MB per server (reduced from 100MB)
- **Servers**: 3 test servers (CloudFlare, OVH, Hetzner)
- **Runs**: 1 per server (reduced from 2)
- **Total download**: ~150MB (was 800MB)
- **Timeout**: 20 seconds per server
- **Measurement window**: 
  - At 100 Mbps: ~4 seconds
  - At 25 Mbps: ~16 seconds
  - At 10 Mbps: ~40 seconds

### Upload Testing
- **Chunk size**: 20MB (reduced from 50MB)
- **Chunks**: 2 sequential uploads
- **Total upload**: 40MB (was 100MB)
- **Timeout**: 25 seconds total
- **Servers**: 3 endpoints

### DNS Resolution Testing
- **Domains**: 11 popular domains
- **Tests**: Resolution time and failure rate
- **Timeout**: Default system resolver timeout

## Performance Optimizations

### Why These Sizes?

**50MB for Downloads:**
- Large enough to overcome TCP slow start
- Provides stable measurement window (4-40 seconds)
- Small enough to complete quickly on slower connections
- Balances accuracy with user experience

**20MB for Uploads:**
- Sufficient to measure upload capacity
- Most users have asymmetric connections (slower upload)
- Reduces test time significantly

### Total Test Duration

**Typical completion times:**
- Fast connection (100+ Mbps): ~2-3 minutes
- Good connection (25-50 Mbps): ~3-4 minutes
- Fair connection (10-25 Mbps): ~4-5 minutes
- Poor connection (<10 Mbps): ~5-7 minutes

### Data Usage

**Total data transferred:**
- Download: ~150MB
- Upload: ~40MB
- **Total: ~190MB** (reduced from ~900MB)

## Configuration Code

```swift
TestConfiguration(
    latencyTestURLs: [/* 12 CDN endpoints */],
    bandwidthTestURLs: [
        "https://speed.cloudflare.com/__down?bytes=52428800",  // 50MB
        "https://proof.ovh.net/files/50Mb.dat",                // 50MB
        "https://speed.hetzner.de/50MB.bin"                    // 50MB
    ],
    uploadTestURLs: [/* 3 upload endpoints */],
    dnsTestDomains: [/* 11 popular domains */],
    latencySamplesPerEndpoint: 15,
    bandwidthRunsPerServer: 1,
    uploadChunkSize: 20_971_520,    // 20MB
    uploadChunkCount: 2,
    latencyTestTimeout: 5,
    bandwidthTestTimeout: 20,
    uploadTestTimeout: 25
)
```

## Quick Test Mode

For rapid connectivity checks, the system also supports:
- 10MB quick downloads for server selection
- HEAD requests for basic connectivity
- Reduced sample counts for faster results