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
    
    public func calculateOverallScore(httpResponse: HttpResponseResult,
                              bandwidth: BandwidthResult,
                              dns: DNSResult,
                              bufferBloat: BufferBloatResult) -> NetworkScore {
        
        // Calculate individual component scores (0-100 scale)
        let httpResponseScore = calculateHttpResponseScore(httpResponse.averageResponseTime)
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
        case 80...: return .excellent
        case 60..<80: return .good
        case 40..<60: return .fair
        default: return .poor
        }
    }
    
    // MARK: - Private Score Calculations
    
    private func calculateHttpResponseScore(_ responseTime: Double) -> Double {
        // Score based on adjusted response time thresholds
        switch responseTime {
        case ..<100: return 100    // Excellent
        case 100..<200: return 85  // Very Good
        case 200..<300: return 70  // Good
        case 300..<400: return 55  // Fair
        case 400..<500: return 40  // Below Average
        case 500..<600: return 25  // Poor
        default: return 10          // Very Poor
        }
    }
    
    private func calculateBandwidthScore(_ bandwidth: BandwidthResult) -> Double {
        // Combined score from download and upload speeds
        let downloadScore = scoreDownloadSpeed(bandwidth.downloadSpeedMbps)
        let uploadScore = scoreUploadSpeed(bandwidth.uploadSpeedMbps)
        
        // Weight download more heavily (70/30 split)
        return downloadScore * 0.7 + uploadScore * 0.3
    }
    
    private func scoreDownloadSpeed(_ speedMbps: Double) -> Double {
        switch speedMbps {
        case 100...: return 100    // Excellent (100+ Mbps)
        case 50..<100: return 85   // Very Good
        case 25..<50: return 70    // Good
        case 10..<25: return 55    // Fair
        case 5..<10: return 40     // Below Average
        case 2..<5: return 25      // Poor
        default: return 10         // Very Poor
        }
    }
    
    private func scoreUploadSpeed(_ speedMbps: Double) -> Double {
        switch speedMbps {
        case 50...: return 100     // Excellent (50+ Mbps)
        case 25..<50: return 85    // Very Good
        case 10..<25: return 70    // Good
        case 5..<10: return 55     // Fair
        case 2..<5: return 40      // Below Average
        case 1..<2: return 25      // Poor
        default: return 10         // Very Poor
        }
    }
    
    private func calculateDNSScore(_ resolutionTime: Double) -> Double {
        switch resolutionTime {
        case ..<20: return 100     // Excellent
        case 20..<50: return 85    // Very Good
        case 50..<100: return 70   // Good
        case 100..<150: return 55  // Fair
        case 150..<200: return 40  // Below Average
        case 200..<300: return 25  // Poor
        default: return 10         // Very Poor
        }
    }
    
    private func calculateBufferBloatScore(_ grade: String) -> Double {
        switch grade {
        case "A": return 90  // Excellent
        case "B": return 70  // Good
        case "C": return 50  // Fair
        case "D": return 30  // Poor
        default: return 10   // Very Poor (F)
        }
    }
    
    private func calculateWeightedScore(httpResponseScore: Double,
                                       bandwidthScore: Double,
                                       dnsScore: Double,
                                       bufferBloatScore: Double) -> Double {
        // Weights optimized for browser performance testing
        let weights = ScoreWeights(
            httpResponse: 0.35,  // Most important for browser experience
            bandwidth: 0.35,     // Important for content loading
            dns: 0.15,          // Important for initial connections
            bufferBloat: 0.15   // Affects real-time performance
        )
        
        return httpResponseScore * weights.httpResponse +
               bandwidthScore * weights.bandwidth +
               dnsScore * weights.dns +
               bufferBloatScore * weights.bufferBloat
    }
}

// MARK: - Supporting Types

private struct ScoreWeights {
    let httpResponse: Double
    let bandwidth: Double
    let dns: Double
    let bufferBloat: Double
}