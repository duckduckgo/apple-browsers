//
//  MockAIChatPixelMetricHandler.swift
//  DuckDuckGoTests
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
@testable import DuckDuckGo
@testable import AIChat

/// Mock implementation of AIChatPixelMetricHandling for testing
final class MockAIChatPixelMetricHandler: AIChatPixelMetricHandling {

    // MARK: - Tracking Properties

    private(set) var fireOpenAIChatCallCount = 0
    private(set) var firePixelWithMetricCallCount = 0
    private(set) var capturedMetrics: [AIChatMetric] = []

    // MARK: - Configuration Properties

    var delayInSeconds: TimeInterval = 0
    
    // MARK: - Initialization

    // MARK: - AIChatPixelMetricHandling

    func fireOpenAIChat() {
        fireOpenAIChatCallCount += 1

        if delayInSeconds > 0 {
            Thread.sleep(forTimeInterval: delayInSeconds)
        }
    }

    func firePixelWithMetric(_ metric: AIChatMetric) {
        firePixelWithMetricCallCount += 1
        capturedMetrics.append(metric)

        if delayInSeconds > 0 {
            Thread.sleep(forTimeInterval: delayInSeconds)
        }
    }

    // MARK: - Test Helper Methods

    func reset() {
        fireOpenAIChatCallCount = 0
        firePixelWithMetricCallCount = 0
        capturedMetrics.removeAll()
        delayInSeconds = 0
    }

    func hasReceivedMetric(withName name: AIChatMetricName) -> Bool {
        return capturedMetrics.contains { $0.metricName == name }
    }

    func countOfMetrics(withName name: AIChatMetricName) -> Int {
        return capturedMetrics.filter { $0.metricName == name }.count
    }
}
