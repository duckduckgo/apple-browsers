//
//  GeographicLatencyTests.swift
//  NetworkQualityMonitorTests
//
//  Tests to validate that geographic latency is properly reflected in scores
//

import XCTest
@testable import NetworkQualityMonitor

final class GeographicLatencyTests: XCTestCase {
    
    let calculator = NetworkScoreCalculator()
    
    func testGeographicLatencyScenarios() {
        print("\n=== GEOGRAPHIC LATENCY VALIDATION ===\n")
        
        // Test scenarios with REALISTIC latencies for the new scale
        // New scale: Excellent <150ms, Good 150-250ms, Fair 250-400ms, Poor >400ms
        let scenarios = [
            // EXCELLENT (<150ms) - Well-optimized services with CDN
            ("US East → US East CDN", 15, 5, .excellent),       // Same coast, CDN edge
            ("US West → US West CDN", 12, 4, .excellent),       // Local CDN  
            ("Tokyo → Japan CDN", 8, 3, .excellent),            // Japan local
            ("London → UK CDN", 10, 4, .excellent),             // UK local
            ("US East → US West", 65, 15, .excellent),          // NYC to SF
            ("Germany → UK", 25, 8, .excellent),                // Frankfurt to London
            ("US East → EU West", 85, 20, .excellent),          // NYC to London (optimized)
            ("US West → Asia Pacific", 120, 30, .excellent),    // SF to Tokyo (CDN)
            
            // GOOD (150-250ms) - Normal production services
            ("US West → EU Central", 180, 35, .good),           // SF to Frankfurt  
            ("US East → Asia Pacific", 170, 40, .good),         // NYC to Tokyo
            ("EU → Asia Pacific", 180, 45, .good),              // London to Singapore
            ("US → Australia", 200, 50, .good),                 // US to Sydney (optimized)
            ("Google Service Average", 170, 30, .good),         // Typical Google latency
            ("AWS Cross-Region", 220, 40, .good),               // AWS inter-region
            
            // FAIR (250-400ms) - Acceptable but could be optimized
            ("EU → Australia", 280, 70, .fair),                 // London to Sydney
            ("South America → US", 260, 80, .fair),             // Brazil to US
            ("Africa → Europe", 320, 90, .fair),                // South Africa to EU
            ("Middle East → US", 350, 100, .fair),              // Dubai to US West
            ("Unoptimized Service", 300, 150, .fair),           // No CDN
            
            // POOR (>400ms) - Needs investigation
            ("South America → Asia", 450, 120, .poor),          // Brazil to Japan
            ("Rural Satellite (GEO)", 600, 150, .poor),         // Geostationary satellite
            ("Poor Mobile → Remote", 445, 713, .poor),          // Your actual measurement
            ("Congested Public WiFi", 500, 400, .poor),         // Hotel/conference WiFi
            ("Failing Service", 800, 500, .poor)                // Service with issues
        ]
        
        for (description, latency, variance, expected) in scenarios {
            let score = calculateScoreForLatency(latency, variance: variance)
            let quality = calculator.determineQuality(from: score.overall)
            
            print(String(format: "%-30s: Latency=%3.0fms Var=%3.0fms → Score=%3.0f Quality=%-9s (Expected: %@)",
                        description,
                        latency,
                        variance,
                        score.overall,
                        quality.rawValue,
                        expected.rawValue))
            
            // Verify geographic differences are reflected with new weights
            if description.contains("US East → US") && description.contains("CDN") {
                XCTAssertGreaterThan(score.overall, 75, "Local CDN users should have excellent scores")
            } else if description.contains("Poor Mobile") || description.contains("Satellite") {
                XCTAssertLessThan(score.overall, 45, "Poor connections should have low scores")
            }
        }
    }
    
    func testVariancePenalties() {
        print("\n=== VARIANCE PENALTY VALIDATION ===\n")
        
        // Test with a latency in the "good" range (200ms)
        let baseLatency = 200.0
        
        // Variance levels aligned with new thresholds
        let variances = [
            (25, "Excellent"),    // <50ms: No penalty
            (50, "Good"),         // 50ms threshold
            (75, "Acceptable"),   // 50-100ms: Minor penalty
            (100, "Fair"),        // 100ms threshold
            (150, "High"),        // 100-200ms: Moderate penalty
            (200, "Poor"),        // 200ms threshold
            (300, "Very Poor"),   // 200-400ms: Heavy penalty
            (500, "Severe"),      // >400ms: Severe penalty
            (713, "Your Example") // Your actual measurement
        ]
        
        var previousScore = 100.0
        
        for (variance, description) in variances {
            let score = calculateScoreForLatency(baseLatency, variance: Double(variance))
            
            print(String(format: "Latency=%3.0fms Variance=%3dms → Score=%3.0f (%@)",
                        baseLatency,
                        variance, 
                        score.overall,
                        description))
            
            // Verify that higher variance results in lower scores
            XCTAssertLessThanOrEqual(score.overall, previousScore, 
                                     "Higher variance should not increase score")
            previousScore = score.overall
        }
    }
    
    func testRealisticBrowserScenarios() {
        print("\n=== REALISTIC BROWSER SCENARIOS ===\n")
        
        // Test with actual measurements and new bandwidth scale
        let scenarios = [
            ("Fiber 300/100", 50, 20, 316.0, 136.0),      // Excellent everything
            ("Cable 100/20", 120, 50, 100.0, 20.0),        // Good typical cable
            ("DSL 25/5", 200, 80, 25.0, 5.0),              // Fair connection
            ("Your Fiber", 243, 160, 316.0, 136.0),        // Your actual fiber
            ("Your Hotspot", 445, 713, 13.1, 3.6),         // Your actual hotspot
            ("4G LTE", 80, 40, 40.0, 15.0),                // Good mobile
            ("Public WiFi", 300, 400, 10.0, 2.0)           // Poor public
        ]
        
        for (name, latency, variance, download, upload) in scenarios {
            let score = calculateScoreForLatency(Double(latency), 
                                                variance: Double(variance), 
                                                download: download, 
                                                upload: upload)
            let quality = calculator.determineQuality(from: score.overall)
            
            print(String(format: "%-15s: L=%3dms V=%3dms D=%6.1f U=%5.1f → Score=%3.0f Quality=%@",
                        name,
                        latency,
                        variance,
                        download,
                        upload,
                        score.overall,
                        quality.rawValue))
        }
        
        // Verify scoring makes sense
        let fiber = calculateScoreForLatency(50, variance: 20, download: 300, upload: 100)
        let hotspot = calculateScoreForLatency(445, variance: 713, download: 13.1, upload: 3.6)
        
        XCTAssertGreaterThan(fiber.overall, hotspot.overall + 25,
                            "Fiber should score much better than poor hotspot with new weights")
    }
    
    // MARK: - Helper Functions
    
    private func calculateScoreForLatency(_ latency: Double, 
                                         variance: Double,
                                         download: Double = 100,
                                         upload: Double = 50) -> NetworkScore {
        let httpResponse = HttpResponseResult(
            averageResponseTime: latency,
            responseVariance: variance,
            failureRate: 0,
            sampleCount: 15
        )
        
        let bandwidth = BandwidthResult(
            downloadSpeedMbps: download,
            uploadSpeedMbps: upload
        )
        
        let dns = DNSResult(
            averageResolutionTime: 30,
            failureRate: 0
        )
        
        let bufferBloat = BufferBloatResult(
            baselineLatency: 50,
            loadedLatency: 80,
            increase: 30,
            grade: "B"
        )
        
        return calculator.calculateOverallScore(
            httpResponse: httpResponse,
            bandwidth: bandwidth,
            dns: dns,
            bufferBloat: bufferBloat
        )
    }
}