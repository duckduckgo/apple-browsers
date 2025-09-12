//
//  SimpleNetworkScoringTest.swift
//  NetworkQualityMonitorTests
//

import XCTest
@testable import NetworkQualityMonitor

final class SimpleNetworkScoringTest: XCTestCase {
    
    func testSimpleScoring() {
        let calculator = NetworkScoreCalculator()
        
        // Create simple test data
        let httpResponse = HttpResponseResult(
            averageResponseTime: 100,
            responseVariance: 50,
            failureRate: 0,
            sampleCount: 15
        )
        
        let bandwidth = BandwidthResult(
            downloadSpeedMbps: 100,
            uploadSpeedMbps: 50
        )
        
        let dns = DNSResult(
            averageResolutionTime: 30,
            failureRate: 0
        )
        
        let bufferBloat = BufferBloatResult(
            baselineLatency: 50,
            loadedLatency: 100,
            increase: 50,
            grade: "B"
        )
        
        // Calculate score
        let score = calculator.calculateOverallScore(
            httpResponse: httpResponse,
            bandwidth: bandwidth,
            dns: dns,
            bufferBloat: bufferBloat
        )
        
        print("Score calculated: \(score.overall)")
        XCTAssertGreaterThan(score.overall, 0)
        XCTAssertLessThanOrEqual(score.overall, 100)
    }
}