//
//  NetworkScoreCalculator.swift
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
        // Score weights optimized for REAL BROWSER EXPERIENCE
        // Based on analysis: latency dominates, bandwidth sufficient at 10+ Mbps
        static let httpResponseWeight = 0.60  // CRITICAL - latency dominates browser experience
        static let bandwidthWeight = 0.25     // MODERATE - diminishing returns above 15 Mbps
        static let dnsWeight = 0.10           // LOW - only affects first visit (then cached)
        static let bufferBloatWeight = 0.05   // MINIMAL - affects video calls more than browsing

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

        // HTTP Response thresholds (ms) - Based on user perception
        // Aligned with how users actually perceive delays
        static let httpResponseExcellent = 50.0       // <50ms: Feels instantaneous
        static let httpResponseVeryGood = 75.0        // 50-75ms: Very responsive
        static let httpResponseGood = 100.0           // 75-100ms: Target for production
        static let httpResponseFair = 150.0           // 100-150ms: Slight delay noticeable
        static let httpResponseBelowAverage = 200.0   // 150-200ms: Definitely noticeable
        static let httpResponsePoor = 300.0           // >200ms: Users frustrated

        // Coefficient of Variation (CV) thresholds for consistency scoring
        // CV = stdDev / mean - normalizes variance relative to baseline latency
        static let cvExcellentThreshold = 0.1    // <10% CV: Excellent consistency
        static let cvGoodThreshold = 0.2         // 10-20% CV: Good consistency
        static let cvFairThreshold = 0.35        // 20-35% CV: Acceptable consistency
        static let cvPoorThreshold = 0.5         // 35-50% CV: Poor consistency
        static let cvVeryPoorThreshold = 0.75    // 50-75% CV: Very poor consistency

        // Download speed thresholds (Mbps) - Based on real browsing experience
        // Excellent: Pages load instantly, 4K streaming, multiple users
        // Good: Smooth browsing, HD streaming perfect
        // Fair: Basic browsing fine, HD may buffer initially
        // Poor: Pages slow, limited to SD streaming
        static let downloadExcellent = 100.0  // >100 Mbps - instant page loads
        static let downloadVeryGood = 50.0    // 50-100 Mbps - very smooth
        static let downloadGood = 25.0        // 25-50 Mbps - target for households
        static let downloadFair = 10.0        // 10-25 Mbps - basic browsing works
        static let downloadBelowAverage = 5.0 // 5-10 Mbps - noticeable delays
        static let downloadPoor = 2.0         // <5 Mbps - modern web feels sluggish

        // Upload speed thresholds (Mbps) - Based on video calls and sharing needs
        // Excellent: HD video calls, streaming, quick sharing
        // Good: Video calls work well, reasonable uploads
        // Fair: Video calls may reduce quality, slower uploads
        // Poor: Frequent quality drops, very slow uploads
        static let uploadExcellent = 25.0     // >25 Mbps - HD video calls, can stream
        static let uploadVeryGood = 15.0      // 15-25 Mbps - very good experience
        static let uploadGood = 10.0          // 10-15 Mbps - adequate for most users
        static let uploadFair = 5.0           // 5-10 Mbps - video calls may reduce quality
        static let uploadBelowAverage = 2.5   // 2.5-5 Mbps - noticeable limitations
        static let uploadPoor = 1.0           // <2.5 Mbps - struggle with video calls

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

        // Calculate Coefficient of Variation (CV) = stdDev / mean
        // This normalizes variance relative to the baseline latency
        let coefficientOfVariation = httpResponse.averageResponseTime > 0
            ? httpResponse.responseVariance / httpResponse.averageResponseTime
            : 0

        // Calculate variance penalty based on CV
        let variancePenalty = calculateCVPenalty(coefficientOfVariation)

        // Additional penalty based on P95-P50 spread (if available)
        var p95Penalty = 0.0
        if let spread = httpResponse.latencySpread {
            // Tighter thresholds for P95 spread with new scale
            // Good connections should have minimal spread
            switch spread {
            case ..<30: p95Penalty = 0      // Excellent consistency
            case 30..<60: p95Penalty = 5    // Minor spikes
            case 60..<100: p95Penalty = 10  // Noticeable spikes
            case 100..<150: p95Penalty = 15 // Significant inconsistency
            default: p95Penalty = 20        // Severe inconsistency
            }
        }

        // Calculate failure rate penalty
        let failurePenalty = httpResponse.failureRate * 50.0 // Up to 50 point penalty for failures

        // Apply all penalties - ensure minimum score of 0
        let finalScore = max(0, baseScore - variancePenalty - p95Penalty - failurePenalty)

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

    private func calculateCVPenalty(_ cv: Double) -> Double {
        // Penalties based on Coefficient of Variation
        // This fairly compares consistency across different latency ranges
        switch cv {
        case ..<Constants.cvExcellentThreshold: return 0       // <10% CV: No penalty
        case Constants.cvExcellentThreshold..<Constants.cvGoodThreshold: return 10  // 10-20% CV: Minor penalty
        case Constants.cvGoodThreshold..<Constants.cvFairThreshold: return 25       // 20-35% CV: Moderate penalty
        case Constants.cvFairThreshold..<Constants.cvPoorThreshold: return 40       // 35-50% CV: Significant penalty
        case Constants.cvPoorThreshold..<Constants.cvVeryPoorThreshold: return 55   // 50-75% CV: Heavy penalty
        default: return 70  // >75% CV: Severe penalty
        }
    }

    private func calculateBandwidthScore(_ bandwidth: BandwidthResult) -> Double {
        // Combined score from download and upload speeds
        let downloadScore = scoreDownloadSpeed(bandwidth.downloadSpeedMbps)
        let uploadScore = scoreUploadSpeed(bandwidth.uploadSpeedMbps)

        // Weight download more heavily (85/15 split)
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
