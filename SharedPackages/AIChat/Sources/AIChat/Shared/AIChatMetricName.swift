//
//  AIChatMetricName.swift
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

/// https://app.asana.com/1/137249556945/project/481882893211075/task/1210422904669751?focus=true
/// Data structure sent from AI Chat to the native layer
public enum AIChatMetricName: String, Codable {
    case userDidSubmitPrompt
    case userDidSubmitFirstPrompt
    case userDidOpenHistory
    case userDidSelectFirstHistoryItem
    case userDidCreateNewChat
    case userDidTapKeyboardReturnKey
}

public struct AIChatMetric: Codable {
    public let metricName: AIChatMetricName

     public init(metricName: AIChatMetricName) {
         self.metricName = metricName
     }
}

extension AIChatMetric {
    public var shouldIncludeTimestampParameters: Bool {
        switch metricName {
        case .userDidTapKeyboardReturnKey:
            return false
        default:
            return true
        }
    }
}
