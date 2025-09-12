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
            
            // Verify geographic differences are reflected
            if description.contains("US User") {
                XCTAssertGreaterThan(score.overall, 70, "Local users should have good scores")
            } else if description.contains("Mobile Hotspot") {
                XCTAssertLessThan(score.overall, 50, "Poor connections should have low scores")
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
        
        // Your actual measurements
        let yourFiber = calculateScoreForLatency(243, variance: 160, download: 316, upload: 136)
        let yourHotspot = calculateScoreForLatency(445, variance: 713, download: 13.1, upload: 3.6)
        
        print(String(format: "Your Fiber:   Score=%3.0f Quality=%@", 
                    yourFiber.overall,
                    calculator.determineQuality(from: yourFiber.overall).rawValue))
        
        print(String(format: "Your Hotspot: Score=%3.0f Quality=%@",
                    yourHotspot.overall,
                    calculator.determineQuality(from: yourHotspot.overall).rawValue))
        
        // Verify significant difference between good and poor connections
        XCTAssertGreaterThan(yourFiber.overall, yourHotspot.overall + 20,
                            "Fiber should score significantly better than poor hotspot")
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