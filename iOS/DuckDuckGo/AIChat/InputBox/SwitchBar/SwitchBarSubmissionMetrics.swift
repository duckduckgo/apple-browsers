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
    
    private let textLengthBucketKey = "text_length_bucket"
    
    /// Process text submission and fire pixel with length bucket parameter
    func process(_ text: String, for submissionMode: TextEntryMode) {
        guard let bucket = SwitchBarTextBucket(text) else { return }
        
        let additionalParams = [textLengthBucketKey: bucket.rawValue]
        
        switch submissionMode {
        case .search:
            DailyPixel.fireDailyAndCount(pixel: .aiChatExperimentalOmnibarQuerySubmitted, withAdditionalParameters: additionalParams)
        case .aiChat:
            DailyPixel.fireDailyAndCount(pixel: .aiChatExperimentalOmnibarPromptSubmitted, withAdditionalParameters: additionalParams)
        }
    }
}
