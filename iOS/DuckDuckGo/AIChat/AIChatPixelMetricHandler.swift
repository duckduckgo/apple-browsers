//
//  AIChatPixelMetricHandler.swift
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
import AIChat
import Core

// MARK: - Protocol

protocol AIChatPixelMetricHandling {
    func fireOpenAIChat()
    func firePixelWithMetric(_ metric: AIChatMetric)
}

// MARK: - Implementation

final class AIChatPixelMetricHandler: AIChatPixelMetricHandling {

    // MARK: - Private Properties

    private let timeElapsedInMinutes: Int?
    private let pixelFiring: PixelFiring.Type
    private let timestampParameterKey = "delta-timestamp-minutes"

    private let metricToEventMap: [AIChatMetricName: Pixel.Event] = [
        .userDidSubmitPrompt: .aiChatMetricSentPromptOngoingChat,
        .userDidSubmitFirstPrompt: .aiChatMetricStartNewConversation,
        .userDidOpenHistory: .aiChatMetricOpenHistory,
        .userDidSelectFirstHistoryItem: .aiChatMetricOpenMostRecentHistoryChat,
        .userDidCreateNewChat: .aiChatMetricStartNewConversationButtonClicked,
        .userDidTapKeyboardReturnKey: .aiChatMetricDuckAIKeyboardReturnPressed
    ]

    // MARK: - Initialization

    init(timeElapsedInMinutes: Int?, pixelFiring: PixelFiring.Type = Pixel.self) {
        self.timeElapsedInMinutes = timeElapsedInMinutes
        self.pixelFiring = pixelFiring
    }

    // MARK: - AIChatPixelMetricHandling

    func fireOpenAIChat() {
        let parameters = timestampParameters ?? [:]
        pixelFiring.fire(.aiChatOpen, withAdditionalParameters: parameters)
    }

    func firePixelWithMetric(_ metric: AIChatMetric) {
        guard let event = metricToEventMap[metric.metricName] else {
            return
        }

        var parameters: [String: String] = [:]
        if metric.shouldIncludeTimestampParameters {
            parameters = timestampParameters ?? [:]
        }
        
        pixelFiring.fire(event, withAdditionalParameters: parameters)
    }

    // MARK: - Private Helpers

    private var timestampParameters: [String: String]? {
        guard let timeElapsed = timeElapsedInMinutes else { return nil }
        return [timestampParameterKey: "\(timeElapsed)"]
    }
}
