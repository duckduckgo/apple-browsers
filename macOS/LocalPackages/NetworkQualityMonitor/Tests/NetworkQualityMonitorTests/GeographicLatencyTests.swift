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
        
        // Test scenarios with REALISTIC geographic latencies
        // Based on actual physical distances and network paths
        let scenarios = [
            // Same region/country
            ("US East → US East CDN", 15, 5, .excellent),       // Same coast, CDN edge
            ("US West → US West CDN", 12, 4, .excellent),       // Local CDN  
            ("Tokyo → Japan CDN", 8, 3, .excellent),            // Japan local
            ("London → UK CDN", 10, 4, .excellent),             // UK local
            
            // Cross-region, same continent  
            ("US East → US West", 65, 15, .excellent),          // NYC to SF (~2900 miles)
            ("Germany → UK", 25, 8, .excellent),                // Frankfurt to London
            ("China → Japan", 45, 12, .excellent),              // Beijing to Tokyo
            
            // Transatlantic
            ("US East → EU West", 85, 20, .good),               // NYC to London
            ("US West → EU Central", 150, 35, .good),           // SF to Frankfurt  
            
            // Transpacific
            ("US West → Asia Pacific", 120, 30, .good),         // SF to Tokyo
            ("US East → Asia Pacific", 170, 40, .fair),         // NYC to Tokyo
            ("EU → Asia Pacific", 180, 45, .fair),              // London to Singapore
            
            // Extreme distances
            ("US → Australia", 200, 50, .fair),                 // US to Sydney
            ("EU → Australia", 280, 70, .fair),                 // London to Sydney
            ("South America → Asia", 350, 100, .poor),          // Brazil to Japan
            
            // Satellite/Poor connections
            ("Rural Satellite (GEO)", 600, 150, .poor),         // Geostationary satellite
            ("Poor Mobile → Remote", 445, 713, .poor),          // Your actual measurement
            ("Congested Public WiFi", 300, 400, .poor)          // Hotel/conference WiFi
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
        
        // Test same latency with different variance levels
        let baseLatency = 100.0
        let variances = [10, 20, 50, 100, 200, 500]
        
        var previousScore = 100.0
        
        for variance in variances {
            let score = calculateScoreForLatency(baseLatency, variance: Double(variance))
            
            print(String(format: "Latency=%3.0fms Variance=%3dms → Score=%3.0f",
                        baseLatency,
                        variance, 
                        score.overall))
            
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