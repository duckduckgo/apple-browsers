//
//  NetworkScoreCalculator.swift
//  NetworkQualityMonitor
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

/// Service responsible for calculating network quality scores
public final class NetworkScoreCalculator: NetworkScoreCalculating {
    
    // MARK: - Constants
    
    private enum Constants {
        // Score weights optimized for BROWSER PERFORMANCE testing decisions
        static let httpResponseWeight = 0.50  // Critical - page load latency & consistency  
        static let bandwidthWeight = 0.35     // Important - resource download speed
        static let dnsWeight = 0.10           // Moderate - initial page load only (cached after)
        static let bufferBloatWeight = 0.05   // Minor - less relevant for browsing vs real-time apps
        
        // Bandwidth sub-weights (optimized for browsing - download much more important)
        static let downloadWeight = 0.85    // Critical - page resources, images, JS, CSS
        static let uploadWeight = 0.15      // Minor - only forms, file uploads
        
        // Score values
        static let excellent = 100.0
        static let veryGood = 85.0
        static let good = 70.0
        static let fair = 55.0
        static let belowAverage = 40.0
        static let poor = 25.0
        static let veryPoor = 10.0
        
        // Buffer bloat specific scores
        static let bufferBloatGradeA = 90.0
        static let bufferBloatGradeB = 70.0
        static let bufferBloatGradeC = 50.0
        static let bufferBloatGradeD = 30.0
        static let bufferBloatGradeF = 10.0
        
        // Quality thresholds
        static let excellentThreshold = 80.0
        static let goodThreshold = 60.0
        static let fairThreshold = 40.0
        
        // HTTP Response thresholds (ms) - realistic for global services
        // Based on real-world browser performance expectations
        static let httpResponseExcellent = 150.0      // <150ms: Excellent (CDN-optimized)
        static let httpResponseVeryGood = 200.0       // 150-200ms: Very good
        static let httpResponseGood = 250.0           // 200-250ms: Good (normal production)
        static let httpResponseFair = 325.0           // 250-325ms: Fair (acceptable)
        static let httpResponseBelowAverage = 400.0   // 325-400ms: Below average
        static let httpResponsePoor = 500.0           // >400ms: Poor (needs investigation)
        
        // Response Variance penalty thresholds (standard deviation in ms)
        // Scaled appropriately for the new latency thresholds
        // Variance should be proportional to expected latency ranges
        static let varianceGoodThreshold = 50.0       // <50ms std dev: Excellent consistency
        static let varianceFairThreshold = 100.0      // 50-100ms std dev: Acceptable variance
        static let variancePoorThreshold = 200.0      // 100-200ms std dev: High variance
        static let varianceVeryPoorThreshold = 400.0  // >200ms std dev: Severe instability
        
        // Download speed thresholds (Mbps)
        static let downloadExcellent = 100.0
        static let downloadVeryGood = 50.0
        static let downloadGood = 25.0
        static let downloadFair = 10.0
        static let downloadBelowAverage = 5.0
        static let downloadPoor = 2.0
        
        // Upload speed thresholds (Mbps)
        static let uploadExcellent = 50.0
        static let uploadVeryGood = 25.0
        static let uploadGood = 10.0
        static let uploadFair = 5.0
        static let uploadBelowAverage = 2.0
        static let uploadPoor = 1.0
        
        // DNS resolution thresholds (ms)
        static let dnsExcellent = 20.0
        static let dnsVeryGood = 50.0
        static let dnsGood = 100.0
        static let dnsFair = 150.0
        static let dnsBelowAverage = 200.0
        static let dnsPoor = 300.0
    }
    
    public func calculateOverallScore(httpResponse: HttpResponseResult,
                              bandwidth: BandwidthResult,
                              dns: DNSResult,
                              bufferBloat: BufferBloatResult) -> NetworkScore {
        
        // Calculate individual component scores (0-100 scale)
        let httpResponseScore = calculateHttpResponseScore(httpResponse)
        let bandwidthScore = calculateBandwidthScore(bandwidth)
        let dnsScore = calculateDNSScore(dns.averageResolutionTime)
        let bufferBloatScore = calculateBufferBloatScore(bufferBloat.grade)
        
        // Calculate weighted overall score
        let overallScore = calculateWeightedScore(
            httpResponseScore: httpResponseScore,
            bandwidthScore: bandwidthScore,
            dnsScore: dnsScore,
            bufferBloatScore: bufferBloatScore
        )
        
        return NetworkScore(
            overall: overallScore,
            httpResponse: httpResponseScore,
            bandwidth: bandwidthScore,
            dns: dnsScore,
            bufferBloat: bufferBloatScore
        )
    }
    
    public func determineQuality(from score: Double) -> NetworkQuality {
        switch score {
        case Constants.excellentThreshold...: return .excellent
        case Constants.goodThreshold..<Constants.excellentThreshold: return .good
        case Constants.fairThreshold..<Constants.goodThreshold: return .fair
        default: return .poor
        }
    }
    
    // MARK: - Private Score Calculations
    
    private func calculateHttpResponseScore(_ httpResponse: HttpResponseResult) -> Double {
        // Calculate base score from response time
        let baseScore = calculateResponseTimeScore(httpResponse.averageResponseTime)
        
        // Calculate variance penalty
        let variancePenalty = calculateVariancePenalty(httpResponse.responseVariance)
        
        // Calculate failure rate penalty
        let failurePenalty = httpResponse.failureRate * 50.0 // Up to 50 point penalty for failures
        
        // Apply penalties - ensure minimum score of 0
        let finalScore = max(0, baseScore - variancePenalty - failurePenalty)
        
        return finalScore
    }
    
    private func calculateResponseTimeScore(_ responseTime: Double) -> Double {
        // Base score from response time only
        switch responseTime {
        case ..<Constants.httpResponseExcellent: return Constants.excellent
        case Constants.httpResponseExcellent..<Constants.httpResponseVeryGood: return Constants.veryGood
        case Constants.httpResponseVeryGood..<Constants.httpResponseGood: return Constants.good
        case Constants.httpResponseGood..<Constants.httpResponseFair: return Constants.fair
        case Constants.httpResponseFair..<Constants.httpResponseBelowAverage: return Constants.belowAverage
        case Constants.httpResponseBelowAverage..<Constants.httpResponsePoor: return Constants.poor
        default: return Constants.veryPoor
        }
    }
    
    private func calculateVariancePenalty(_ variance: Double) -> Double {
        // Variance penalty scaled for new latency thresholds
        // More lenient since we expect higher absolute variance with higher latencies
        switch variance {
        case ..<Constants.varianceGoodThreshold: return 0      // <50ms std dev: No penalty
        case Constants.varianceGoodThreshold..<Constants.varianceFairThreshold: return 10   // 50-100ms: Minor penalty
        case Constants.varianceFairThreshold..<Constants.variancePoorThreshold: return 25   // 100-200ms: Moderate penalty
        case Constants.variancePoorThreshold..<Constants.varianceVeryPoorThreshold: return 40  // 200-400ms: Heavy penalty
        default: return 55  // >400ms std dev: Severe penalty
        }
    }
    
    private func calculateBandwidthScore(_ bandwidth: BandwidthResult) -> Double {
        // Combined score from download and upload speeds
        let downloadScore = scoreDownloadSpeed(bandwidth.downloadSpeedMbps)
        let uploadScore = scoreUploadSpeed(bandwidth.uploadSpeedMbps)
        
        // Weight download more heavily (70/30 split)
        return downloadScore * Constants.downloadWeight + uploadScore * Constants.uploadWeight
    }
    
    private func scoreDownloadSpeed(_ speedMbps: Double) -> Double {
        switch speedMbps {
        case Constants.downloadExcellent...: return Constants.excellent
        case Constants.downloadVeryGood..<Constants.downloadExcellent: return Constants.veryGood
        case Constants.downloadGood..<Constants.downloadVeryGood: return Constants.good
        case Constants.downloadFair..<Constants.downloadGood: return Constants.fair
        case Constants.downloadBelowAverage..<Constants.downloadFair: return Constants.belowAverage
        case Constants.downloadPoor..<Constants.downloadBelowAverage: return Constants.poor
        default: return Constants.veryPoor
        }
    }
    
    private func scoreUploadSpeed(_ speedMbps: Double) -> Double {
        switch speedMbps {
        case Constants.uploadExcellent...: return Constants.excellent
        case Constants.uploadVeryGood..<Constants.uploadExcellent: return Constants.veryGood
        case Constants.uploadGood..<Constants.uploadVeryGood: return Constants.good
        case Constants.uploadFair..<Constants.uploadGood: return Constants.fair
        case Constants.uploadBelowAverage..<Constants.uploadFair: return Constants.belowAverage
        case Constants.uploadPoor..<Constants.uploadBelowAverage: return Constants.poor
        default: return Constants.veryPoor
        }
    }
    
    private func calculateDNSScore(_ resolutionTime: Double) -> Double {
        switch resolutionTime {
        case ..<Constants.dnsExcellent: return Constants.excellent
        case Constants.dnsExcellent..<Constants.dnsVeryGood: return Constants.veryGood
        case Constants.dnsVeryGood..<Constants.dnsGood: return Constants.good
        case Constants.dnsGood..<Constants.dnsFair: return Constants.fair
        case Constants.dnsFair..<Constants.dnsBelowAverage: return Constants.belowAverage
        case Constants.dnsBelowAverage..<Constants.dnsPoor: return Constants.poor
        default: return Constants.veryPoor
        }
    }
    
    private func calculateBufferBloatScore(_ grade: String) -> Double {
        switch grade {
        case "A": return Constants.bufferBloatGradeA
        case "B": return Constants.bufferBloatGradeB
        case "C": return Constants.bufferBloatGradeC
        case "D": return Constants.bufferBloatGradeD
        default: return Constants.bufferBloatGradeF
        }
    }
    
    private func calculateWeightedScore(httpResponseScore: Double,
                                       bandwidthScore: Double,
                                       dnsScore: Double,
                                       bufferBloatScore: Double) -> Double {
        // Weights optimized for browser performance testing decisions:
        // - HTTP Response (50%): Page load latency & consistency most critical
        // - Bandwidth (35%): Resource download speed for images, JS, CSS  
        // - DNS (10%): Initial page load (cached after first request)
        // - Buffer Bloat (5%): Less relevant for typical web browsing
        return httpResponseScore * Constants.httpResponseWeight +
               bandwidthScore * Constants.bandwidthWeight +
               dnsScore * Constants.dnsWeight +
               bufferBloatScore * Constants.bufferBloatWeight
    }
}