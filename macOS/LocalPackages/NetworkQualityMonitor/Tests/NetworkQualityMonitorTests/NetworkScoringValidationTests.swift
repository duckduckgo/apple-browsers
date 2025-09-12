//
//  NetworkScoringValidationTests.swift
//  NetworkQualityMonitorTests
//
//  Comprehensive validation suite with 50+ network scenarios
//

import XCTest
@testable import NetworkQualityMonitor

final class NetworkScoringValidationTests: XCTestCase {
    
    let calculator = NetworkScoreCalculator()
    
    // MARK: - Test Data Structures
    
    struct NetworkScenario {
        let name: String
        let httpResponse: Double      // ms
        let variance: Double          // ms
        let download: Double          // Mbps
        let upload: Double            // Mbps
        let dns: Double               // ms
        let bufferBloatGrade: String
        let expectedQuality: NetworkQuality
        let description: String
    }
    
    // MARK: - Comprehensive Test Scenarios (50+)
    
    func testAllNetworkScenarios() {
        // Split into smaller array to avoid stack overflow
        var scenarios: [NetworkScenario] = []
        
        // Add scenarios in groups
        scenarios.append(contentsOf: [
            // FIBER CONNECTIONS (Excellent - like your example)
            NetworkScenario(name: "Fiber - Perfect", httpResponse: 15, variance: 5, download: 500, upload: 200, dns: 10, bufferBloatGrade: "A", expectedQuality: .excellent, description: "Premium fiber connection"),
            NetworkScenario(name: "Fiber - Your Example", httpResponse: 243, variance: 160, download: 316, upload: 136, dns: 25, bufferBloatGrade: "B", expectedQuality: .excellent, description: "Your actual fiber connection"),
            NetworkScenario(name: "Fiber - Good", httpResponse: 50, variance: 20, download: 300, upload: 100, dns: 15, bufferBloatGrade: "A", expectedQuality: .excellent, description: "Standard fiber"),
            NetworkScenario(name: "Fiber - Congested", httpResponse: 100, variance: 80, download: 250, upload: 80, dns: 30, bufferBloatGrade: "B", expectedQuality: .good, description: "Fiber with network congestion"),
            NetworkScenario(name: "Fiber - High Variance", httpResponse: 40, variance: 200, download: 400, upload: 150, dns: 20, bufferBloatGrade: "A", expectedQuality: .good, description: "Fast but inconsistent"),
            
            // CABLE CONNECTIONS (Good to Excellent)
            NetworkScenario(name: "Cable - Excellent", httpResponse: 80, variance: 30, download: 150, upload: 30, dns: 25, bufferBloatGrade: "A", expectedQuality: .excellent, description: "Top-tier cable"),
            NetworkScenario(name: "Cable - Standard", httpResponse: 120, variance: 50, download: 100, upload: 20, dns: 35, bufferBloatGrade: "B", expectedQuality: .good, description: "Typical cable connection"),
            NetworkScenario(name: "Cable - Budget", httpResponse: 150, variance: 70, download: 50, upload: 10, dns: 40, bufferBloatGrade: "B", expectedQuality: .good, description: "Budget cable plan"),
            NetworkScenario(name: "Cable - Peak Hours", httpResponse: 200, variance: 150, download: 40, upload: 8, dns: 50, bufferBloatGrade: "C", expectedQuality: .fair, description: "Cable during peak usage"),
            NetworkScenario(name: "Cable - Degraded", httpResponse: 250, variance: 200, download: 25, upload: 5, dns: 60, bufferBloatGrade: "D", expectedQuality: .fair, description: "Degraded cable service"),
            
            // DSL CONNECTIONS (Fair to Good)
            NetworkScenario(name: "DSL - VDSL Good", httpResponse: 150, variance: 60, download: 50, upload: 20, dns: 35, bufferBloatGrade: "B", expectedQuality: .good, description: "VDSL2 connection"),
            NetworkScenario(name: "DSL - Standard", httpResponse: 200, variance: 80, download: 25, upload: 5, dns: 45, bufferBloatGrade: "C", expectedQuality: .fair, description: "Standard DSL"),
            NetworkScenario(name: "DSL - Rural", httpResponse: 300, variance: 120, download: 15, upload: 2, dns: 55, bufferBloatGrade: "C", expectedQuality: .fair, description: "Rural DSL"),
            NetworkScenario(name: "DSL - Old", httpResponse: 400, variance: 180, download: 10, upload: 1, dns: 70, bufferBloatGrade: "D", expectedQuality: .poor, description: "Legacy DSL"),
            NetworkScenario(name: "DSL - Overloaded", httpResponse: 500, variance: 300, download: 5, upload: 0.5, dns: 100, bufferBloatGrade: "F", expectedQuality: .poor, description: "Overloaded DSL"),
            
            // 5G MOBILE (Good to Excellent)
            NetworkScenario(name: "5G - Ultra", httpResponse: 20, variance: 10, download: 800, upload: 100, dns: 15, bufferBloatGrade: "A", expectedQuality: .excellent, description: "5G Ultra Wideband"),
            NetworkScenario(name: "5G - Standard", httpResponse: 40, variance: 25, download: 300, upload: 50, dns: 20, bufferBloatGrade: "A", expectedQuality: .excellent, description: "Standard 5G"),
            NetworkScenario(name: "5G - Edge", httpResponse: 60, variance: 40, download: 150, upload: 30, dns: 25, bufferBloatGrade: "B", expectedQuality: .excellent, description: "5G edge coverage"),
            NetworkScenario(name: "5G - Congested", httpResponse: 80, variance: 100, download: 100, upload: 20, dns: 30, bufferBloatGrade: "C", expectedQuality: .good, description: "Congested 5G tower"),
            
            // 4G LTE (Fair to Good)
            NetworkScenario(name: "LTE - Excellent", httpResponse: 50, variance: 30, download: 80, upload: 25, dns: 30, bufferBloatGrade: "B", expectedQuality: .good, description: "Strong LTE signal"),
            NetworkScenario(name: "LTE - Good", httpResponse: 80, variance: 50, download: 40, upload: 15, dns: 40, bufferBloatGrade: "B", expectedQuality: .good, description: "Good LTE coverage"),
            NetworkScenario(name: "LTE - Fair", httpResponse: 120, variance: 80, download: 20, upload: 8, dns: 50, bufferBloatGrade: "C", expectedQuality: .fair, description: "Fair LTE signal"),
            NetworkScenario(name: "LTE - Weak", httpResponse: 200, variance: 150, download: 10, upload: 3, dns: 70, bufferBloatGrade: "D", expectedQuality: .fair, description: "Weak LTE signal"),
            NetworkScenario(name: "LTE - Edge", httpResponse: 300, variance: 250, download: 5, upload: 1, dns: 100, bufferBloatGrade: "F", expectedQuality: .poor, description: "LTE edge coverage"),
            
            // MOBILE HOTSPOT (Your poor example)
            NetworkScenario(name: "Hotspot - Your Example", httpResponse: 445, variance: 713, download: 13.1, upload: 3.6, dns: 28, bufferBloatGrade: "A", expectedQuality: .poor, description: "Your hotspot in low coverage"),
            NetworkScenario(name: "Hotspot - Good", httpResponse: 150, variance: 100, download: 30, upload: 10, dns: 50, bufferBloatGrade: "C", expectedQuality: .fair, description: "Good hotspot signal"),
            NetworkScenario(name: "Hotspot - Congested", httpResponse: 250, variance: 200, download: 15, upload: 5, dns: 60, bufferBloatGrade: "D", expectedQuality: .poor, description: "Congested hotspot"),
            NetworkScenario(name: "Hotspot - Throttled", httpResponse: 350, variance: 300, download: 8, upload: 2, dns: 80, bufferBloatGrade: "D", expectedQuality: .poor, description: "Throttled hotspot"),
            NetworkScenario(name: "Hotspot - Rural", httpResponse: 500, variance: 400, download: 3, upload: 0.5, dns: 120, bufferBloatGrade: "F", expectedQuality: .poor, description: "Rural hotspot"),
            
            // SATELLITE INTERNET (Poor to Fair)
            NetworkScenario(name: "Satellite - LEO Good", httpResponse: 40, variance: 30, download: 150, upload: 20, dns: 35, bufferBloatGrade: "B", expectedQuality: .good, description: "Starlink good conditions"),
            NetworkScenario(name: "Satellite - LEO Fair", httpResponse: 80, variance: 100, download: 100, upload: 10, dns: 50, bufferBloatGrade: "C", expectedQuality: .fair, description: "Starlink fair conditions"),
            NetworkScenario(name: "Satellite - GEO", httpResponse: 600, variance: 100, download: 25, upload: 3, dns: 600, bufferBloatGrade: "D", expectedQuality: .poor, description: "Traditional satellite"),
            
            // PUBLIC WIFI SCENARIOS
            NetworkScenario(name: "WiFi - Airport Premium", httpResponse: 100, variance: 50, download: 50, upload: 25, dns: 40, bufferBloatGrade: "B", expectedQuality: .good, description: "Premium airport WiFi"),
            NetworkScenario(name: "WiFi - Coffee Shop", httpResponse: 200, variance: 150, download: 20, upload: 5, dns: 60, bufferBloatGrade: "C", expectedQuality: .fair, description: "Coffee shop WiFi"),
            NetworkScenario(name: "WiFi - Hotel Basic", httpResponse: 300, variance: 250, download: 10, upload: 2, dns: 80, bufferBloatGrade: "D", expectedQuality: .poor, description: "Hotel free WiFi"),
            NetworkScenario(name: "WiFi - Conference", httpResponse: 400, variance: 500, download: 5, upload: 1, dns: 100, bufferBloatGrade: "F", expectedQuality: .poor, description: "Crowded conference WiFi"),
            
            // ENTERPRISE CONNECTIONS
            NetworkScenario(name: "Enterprise - Datacenter", httpResponse: 5, variance: 2, download: 10000, upload: 10000, dns: 5, bufferBloatGrade: "A", expectedQuality: .excellent, description: "Datacenter connection"),
            NetworkScenario(name: "Enterprise - Office", httpResponse: 20, variance: 10, download: 1000, upload: 1000, dns: 10, bufferBloatGrade: "A", expectedQuality: .excellent, description: "Corporate office"),
            NetworkScenario(name: "Enterprise - Branch", httpResponse: 50, variance: 30, download: 200, upload: 200, dns: 20, bufferBloatGrade: "A", expectedQuality: .excellent, description: "Branch office"),
            
            // EDGE CASES
            NetworkScenario(name: "Edge - All Excellent", httpResponse: 10, variance: 5, download: 1000, upload: 1000, dns: 5, bufferBloatGrade: "A", expectedQuality: .excellent, description: "Perfect conditions"),
            NetworkScenario(name: "Edge - All Poor", httpResponse: 1000, variance: 1000, download: 0.5, upload: 0.1, dns: 500, bufferBloatGrade: "F", expectedQuality: .poor, description: "Worst case scenario"),
            NetworkScenario(name: "Edge - Fast but Inconsistent", httpResponse: 30, variance: 500, download: 500, upload: 100, dns: 15, bufferBloatGrade: "A", expectedQuality: .fair, description: "High speed, high variance"),
            NetworkScenario(name: "Edge - Slow but Stable", httpResponse: 400, variance: 20, download: 5, upload: 1, dns: 100, bufferBloatGrade: "B", expectedQuality: .poor, description: "Low speed, low variance"),
            
            // REGIONAL VARIATIONS
            NetworkScenario(name: "Asia - Tokyo Fiber", httpResponse: 8, variance: 3, download: 2000, upload: 2000, dns: 8, bufferBloatGrade: "A", expectedQuality: .excellent, description: "Tokyo gigabit fiber"),
            NetworkScenario(name: "EU - Amsterdam IX", httpResponse: 12, variance: 5, download: 1000, upload: 1000, dns: 10, bufferBloatGrade: "A", expectedQuality: .excellent, description: "Amsterdam Internet Exchange"),
            NetworkScenario(name: "US - Rural Broadband", httpResponse: 250, variance: 150, download: 25, upload: 3, dns: 70, bufferBloatGrade: "C", expectedQuality: .fair, description: "US rural broadband"),
            NetworkScenario(name: "AU - NBN Standard", httpResponse: 30, variance: 20, download: 50, upload: 20, dns: 25, bufferBloatGrade: "B", expectedQuality: .good, description: "Australian NBN"),
            
            // DEGRADED CONDITIONS
            NetworkScenario(name: "Degraded - Packet Loss", httpResponse: 200, variance: 400, download: 50, upload: 10, dns: 100, bufferBloatGrade: "F", expectedQuality: .poor, description: "High packet loss"),
            NetworkScenario(name: "Degraded - DNS Issues", httpResponse: 100, variance: 50, download: 100, upload: 50, dns: 300, bufferBloatGrade: "B", expectedQuality: .good, description: "DNS server issues"),
            NetworkScenario(name: "Degraded - Buffer Bloat", httpResponse: 150, variance: 100, download: 50, upload: 20, dns: 40, bufferBloatGrade: "F", expectedQuality: .fair, description: "Severe buffer bloat"),
            NetworkScenario(name: "Degraded - Congestion", httpResponse: 300, variance: 250, download: 20, upload: 5, dns: 80, bufferBloatGrade: "D", expectedQuality: .poor, description: "Network congestion"),
            NetworkScenario(name: "Degraded - Throttled", httpResponse: 400, variance: 100, download: 5, upload: 0.5, dns: 60, bufferBloatGrade: "C", expectedQuality: .poor, description: "ISP throttling"),
            
            // VPN SCENARIOS
            NetworkScenario(name: "VPN - Corporate", httpResponse: 150, variance: 50, download: 80, upload: 40, dns: 50, bufferBloatGrade: "B", expectedQuality: .good, description: "Corporate VPN"),
            NetworkScenario(name: "VPN - Consumer", httpResponse: 200, variance: 100, download: 40, upload: 20, dns: 80, bufferBloatGrade: "C", expectedQuality: .fair, description: "Consumer VPN service"),
            NetworkScenario(name: "VPN - Free Tier", httpResponse: 400, variance: 300, download: 10, upload: 5, dns: 150, bufferBloatGrade: "D", expectedQuality: .poor, description: "Free VPN service")
        ])
        
        print("\n=== NETWORK SCORING VALIDATION (50+ Scenarios) ===\n")
        
        var excellentCount = 0
        var goodCount = 0
        var fairCount = 0
        var poorCount = 0
        var correctPredictions = 0
        
        for scenario in scenarios {
            let score = calculateScore(for: scenario)
            let quality = calculator.determineQuality(from: score.overall)
            let correct = quality == scenario.expectedQuality
            
            if correct {
                correctPredictions += 1
            }
            
            switch quality {
            case .excellent: excellentCount += 1
            case .good: goodCount += 1
            case .fair: fairCount += 1
            case .poor: poorCount += 1
            }
            
            print(String(format: "%-30s: Score=%3.0f Quality=%-9s Expected=%-9s %@ | %@",
                        scenario.name,
                        score.overall,
                        quality.rawValue,
                        scenario.expectedQuality.rawValue,
                        correct ? "✅" : "❌",
                        scenario.description))
            
            // Show detailed breakdown for mismatches
            if !correct {
                print("  → HTTP: \(score.httpResponse), BW: \(score.bandwidth), DNS: \(score.dns), BB: \(score.bufferBloat ?? 0)")
                print("  → Response: \(scenario.httpResponse)ms (var: \(scenario.variance)ms), DL: \(scenario.download)Mbps, UL: \(scenario.upload)Mbps")
            }
        }
        
        print("\n=== SUMMARY ===")
        print("Total Scenarios: \(scenarios.count)")
        print("Distribution: Excellent=\(excellentCount), Good=\(goodCount), Fair=\(fairCount), Poor=\(poorCount)")
        print("Accuracy: \(correctPredictions)/\(scenarios.count) (\(Int(Double(correctPredictions)/Double(scenarios.count)*100))%)")
        
        // Assert reasonable distribution and accuracy
        XCTAssertGreaterThan(Double(correctPredictions)/Double(scenarios.count), 0.85, "Scoring accuracy should be > 85%")
        XCTAssertGreaterThan(excellentCount, 5, "Should have some excellent networks")
        XCTAssertGreaterThan(goodCount, 5, "Should have some good networks")
        XCTAssertGreaterThan(fairCount, 5, "Should have some fair networks")
        XCTAssertGreaterThan(poorCount, 5, "Should have some poor networks")
    }
    
    // MARK: - Helper Functions
    
    private func calculateScore(for scenario: NetworkScenario) -> NetworkScore {
        let httpResponse = HttpResponseResult(
            averageResponseTime: scenario.httpResponse,
            responseVariance: scenario.variance,
            failureRate: 0,
            sampleCount: 15
            // p50 and p95 are optional and not used in scoring
        )
        
        let bandwidth = BandwidthResult(
            downloadSpeedMbps: scenario.download,
            uploadSpeedMbps: scenario.upload
        )
        
        let dns = DNSResult(
            averageResolutionTime: scenario.dns,
            failureRate: 0
        )
        
        let bufferBloat = BufferBloatResult(
            baselineLatency: 50,
            loadedLatency: scenario.bufferBloatGrade == "A" ? 60 : 
                           scenario.bufferBloatGrade == "B" ? 90 :
                           scenario.bufferBloatGrade == "C" ? 150 :
                           scenario.bufferBloatGrade == "D" ? 250 : 450,
            increase: 0, // Will be calculated
            grade: scenario.bufferBloatGrade
        )
        
        return calculator.calculateOverallScore(
            httpResponse: httpResponse,
            bandwidth: bandwidth,
            dns: dns,
            bufferBloat: bufferBloat
        )
    }
}