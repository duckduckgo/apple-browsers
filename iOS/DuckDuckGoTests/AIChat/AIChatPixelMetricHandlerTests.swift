//
//  AIChatPixelMetricHandlerTests.swift
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

import XCTest
@testable import Core
@testable import DuckDuckGo
import AIChat

final class AIChatPixelMetricHandlerTests: XCTestCase {

    private var handler: AIChatPixelMetricHandler!

    override func tearDown() {
        handler = nil
        PixelFiringMock.tearDown()
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitializationWithTimeElapsed() {
        // Given
        let timeElapsed = 5

        // When
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: timeElapsed, pixelFiring: PixelFiringMock.self)

        // Then
        XCTAssertNotNil(handler)
    }

    func testInitializationWithNilTimeElapsed() {
        // When
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: nil, pixelFiring: PixelFiringMock.self)

        // Then
        XCTAssertNotNil(handler)
    }

    // MARK: - fireOpenAIChat Tests

    func testFireOpenAIChatWithoutTimeElapsed() {
        // Given
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: nil, pixelFiring: PixelFiringMock.self)

        // When
        handler.fireOpenAIChat()

        // Then
        XCTAssertEqual(PixelFiringMock.allPixelsFired.count, 1)
        XCTAssertEqual(PixelFiringMock.lastPixelName, Pixel.Event.aiChatOpen.name)
        XCTAssertTrue(PixelFiringMock.lastParams?.isEmpty ?? false)
    }

    func testFireOpenAIChatWithTimeElapsed() {
        // Given
        let timeElapsed = 10
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: timeElapsed, pixelFiring: PixelFiringMock.self)

        // When
        handler.fireOpenAIChat()

        // Then
        XCTAssertEqual(PixelFiringMock.allPixelsFired.count, 1)
        XCTAssertEqual(PixelFiringMock.lastPixelName, Pixel.Event.aiChatOpen.name)
        XCTAssertEqual(PixelFiringMock.lastParams?["delta-timestamp-minutes"], "10")
    }

    func testFireOpenAIChatWithZeroTimeElapsed() {
        // Given
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: 0, pixelFiring: PixelFiringMock.self)

        // When
        handler.fireOpenAIChat()

        // Then
        XCTAssertEqual(PixelFiringMock.allPixelsFired.count, 1)
        XCTAssertEqual(PixelFiringMock.lastPixelName, Pixel.Event.aiChatOpen.name)
        XCTAssertEqual(PixelFiringMock.lastParams?["delta-timestamp-minutes"], "0")
    }

    // MARK: - firePixelWithMetric Tests

    func testFirePixelWithMetricForKnownMetric() {
        // Given
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: nil, pixelFiring: PixelFiringMock.self)
        let metric = AIChatMetric(metricName: .userDidSubmitPrompt)

        // When
        handler.firePixelWithMetric(metric)

        // Then
        XCTAssertEqual(PixelFiringMock.allPixelsFired.count, 1)
        XCTAssertEqual(PixelFiringMock.lastPixelName, Pixel.Event.aiChatMetricSentPromptOngoingChat.name)
        XCTAssertTrue(PixelFiringMock.lastParams?.isEmpty ?? false)
    }

    func testFirePixelWithMetricForKnownMetricWithTimeElapsed() {
        // Given
        let timeElapsed = 15
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: timeElapsed, pixelFiring: PixelFiringMock.self)
        let metric = AIChatMetric(metricName: .userDidSubmitFirstPrompt)

        // When
        handler.firePixelWithMetric(metric)

        // Then
        XCTAssertEqual(PixelFiringMock.allPixelsFired.count, 1)
        XCTAssertEqual(PixelFiringMock.lastPixelName, Pixel.Event.aiChatMetricStartNewConversation.name)
        XCTAssertEqual(PixelFiringMock.lastParams?["delta-timestamp-minutes"], "15")
    }

    func testFirePixelWithMetricForAllKnownMetrics() {
        // Given
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: nil, pixelFiring: PixelFiringMock.self)
        let testCases: [(AIChatMetricName, Pixel.Event)] = [
            (.userDidSubmitPrompt, .aiChatMetricSentPromptOngoingChat),
            (.userDidSubmitFirstPrompt, .aiChatMetricStartNewConversation),
            (.userDidOpenHistory, .aiChatMetricOpenHistory),
            (.userDidSelectFirstHistoryItem, .aiChatMetricOpenMostRecentHistoryChat),
            (.userDidCreateNewChat, .aiChatMetricStartNewConversationButtonClicked)
        ]

        // When & Then
        for (index, testCase) in testCases.enumerated() {
            let metric = AIChatMetric(metricName: testCase.0)
            handler.firePixelWithMetric(metric)

            XCTAssertEqual(PixelFiringMock.allPixelsFired.count, index + 1)
            XCTAssertEqual(PixelFiringMock.allPixelsFired[index].pixelName, testCase.1.name)
        }
    }

    func testFirePixelWithMetricForUnknownMetricDoesNothing() {
        // Given
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: nil, pixelFiring: PixelFiringMock.self)

        // When
        let validMetric = AIChatMetric(metricName: .userDidSubmitPrompt)
        handler.firePixelWithMetric(validMetric)

        // Then
        XCTAssertEqual(PixelFiringMock.allPixelsFired.count, 1)
    }

    // MARK: - Integration Tests

    func testMultiplePixelFiresWithConsistentParameters() {
        // Given
        let timeElapsed = 20
        handler = AIChatPixelMetricHandler(timeElapsedInMinutes: timeElapsed, pixelFiring: PixelFiringMock.self)

        // When
        handler.fireOpenAIChat()
        handler.firePixelWithMetric(AIChatMetric(metricName: .userDidSubmitPrompt))
        handler.firePixelWithMetric(AIChatMetric(metricName: .userDidOpenHistory))

        // Then
        XCTAssertEqual(PixelFiringMock.allPixelsFired.count, 3)

        // All pixels should have the same timestamp parameter
        for capturedPixel in PixelFiringMock.allPixelsFired {
            XCTAssertEqual(capturedPixel.params?["delta-timestamp-minutes"], "20")
        }
    }
}
