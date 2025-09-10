//
//  SwitchBarSubmissionMetrics.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Core

/// Privacy-safe text length categorization for input analysis
enum SwitchBarTextBucket: String, CaseIterable {
    /// Short: 1-15 characters
    case short
    /// Medium: 16-40 characters
    case medium
    /// Long: 41-100 characters
    case long
    /// Very long: 100+ characters
    case veryLong = "very_long"
    
    /// Categorizes text by character count
    init?(_ text: String) {
        guard text.count > 0 else { return nil }
        switch text.count {
        case 1...15:
            self = .short
        case 16...40:
            self = .medium
        case 41...100:
            self = .long
        default:
            self = .veryLong
        }
    }
}

/// Protocol for processing submission metrics with text length bucketing
protocol SwitchBarSubmissionMetricsProviding {
    /// Process text submission and fire pixel with length bucket parameter
    func process(_ text: String, for submissionMode: TextEntryMode)
}

/// Handles text length analysis and pixel firing
struct SwitchBarSubmissionMetrics: SwitchBarSubmissionMetricsProviding {
    
    private let featureDiscovery: FeatureDiscovery
    private let textLengthBucketKey = "text_length_bucket"
    
    /// Initialize with feature discovery service for entry point data.
    /// - Parameter featureDiscovery: Service for first-time vs returning user behavior
    init(featureDiscovery: FeatureDiscovery = DefaultFeatureDiscovery()) {
        self.featureDiscovery = featureDiscovery
    }
    
    /// Process text submission and fire pixel with length bucket and feature discovery parameters
    /// - Note: AI Chat submissions also include "was_used_before" parameter via feature discovery
    /// - Parameters:
    ///   - text: Input text
    ///   - submissionMode: Whether this is a search query or AI chat prompt
    func process(_ text: String, for submissionMode: TextEntryMode) {
        // Temp disable until privacy triage done
//        guard let bucket = SwitchBarTextBucket(text) else { return }
        
        // Temp disable until privacy triage done
//        let additionalParams = [textLengthBucketKey: bucket.rawValue]
        
        switch submissionMode {
        case .search:
            // Temp disable until privacy triage done
//            DailyPixel.fireDailyAndCount(pixel: .aiChatExperimentalOmnibarQuerySubmitted, withAdditionalParameters: additionalParams)
            DailyPixel.fireDailyAndCount(pixel: .aiChatExperimentalOmnibarQuerySubmitted)
        case .aiChat:
            // Temp disable until privacy trige done
//            let mergedParams = additionalParams.merging(featureDiscovery.addToParams([:], forFeature: .aiChat)) { (_, new) in new }
//            DailyPixel.fireDailyAndCount(pixel: .aiChatExperimentalOmnibarPromptSubmitted, withAdditionalParameters: mergedParams)
            DailyPixel.fireDailyAndCount(pixel: .aiChatExperimentalOmnibarPromptSubmitted, withAdditionalParameters: featureDiscovery.addToParams([:], forFeature: .aiChat))
            featureDiscovery.setWasUsedBefore(.aiChat)
        }
    }
}
