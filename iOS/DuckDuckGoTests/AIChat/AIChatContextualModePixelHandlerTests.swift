//
//  AIChatContextualModePixelHandlerTests.swift
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

import Testing
import Core
@testable import DuckDuckGo

@Suite("AI Chat Contextual Mode Pixel Handler Tests", .serialized)
final class AIChatContextualModePixelHandlerTests {

    deinit {
        PixelFiringMock.tearDown()
    }

    // MARK: - Sheet Lifecycle Pixels

    @Test("Sheet opened pixel fires correctly")
    func testSheetOpenedPixel() {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { event in
            PixelFiringMock.fire(event, withAdditionalParameters: [:])
        })

        // WHEN
        sut.fireSheetOpened()

        // THEN
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.aiChatContextualSheetOpened.name)
    }

    @Test("Sheet dismissed pixel fires correctly")
    func testSheetDismissedPixel() {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { event in
            PixelFiringMock.fire(event, withAdditionalParameters: [:])
        })

        // WHEN
        sut.fireSheetDismissed()

        // THEN
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.aiChatContextualSheetDismissed.name)
    }

    @Test("Session restored pixel fires correctly")
    func testSessionRestoredPixel() {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { event in
            PixelFiringMock.fire(event, withAdditionalParameters: [:])
        })

        // WHEN
        sut.fireSessionRestored()

        // THEN
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.aiChatContextualSessionRestored.name)
    }

    // MARK: - Sheet Action Pixels

    @Test("Expand button tapped pixel fires correctly")
    func testExpandButtonTappedPixel() {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { event in
            PixelFiringMock.fire(event, withAdditionalParameters: [:])
        })

        // WHEN
        sut.fireExpandButtonTapped()

        // THEN
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.aiChatContextualExpandButtonTapped.name)
    }

    @Test("New chat button tapped pixel fires correctly")
    func testNewChatButtonTappedPixel() {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { event in
            PixelFiringMock.fire(event, withAdditionalParameters: [:])
        })

        // WHEN
        sut.fireNewChatButtonTapped()

        // THEN
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.aiChatContextualNewChatButtonTapped.name)
    }

    @Test("Quick action summarize selected pixel fires correctly")
    func testQuickActionSummarizeSelectedPixel() {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { event in
            PixelFiringMock.fire(event, withAdditionalParameters: [:])
        })

        // WHEN
        sut.fireQuickActionSummarizeSelected()

        // THEN
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.aiChatContextualQuickActionSummarizeSelected.name)
    }

    // MARK: - Page Context Attachment Pixels

    @Test("Page context auto attached pixel fires correctly")
    func testPageContextAutoAttachedPixel() {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { event in
            PixelFiringMock.fire(event, withAdditionalParameters: [:])
        })

        // WHEN
        sut.firePageContextAutoAttached()

        // THEN
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.aiChatContextualPageContextAutoAttached.name)
    }

    @Test("Page context manually attached native pixel fires correctly")
    func testPageContextManuallyAttachedNativePixel() {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { event in
            PixelFiringMock.fire(event, withAdditionalParameters: [:])
        })

        // WHEN
        sut.firePageContextManuallyAttachedNative()

        // THEN
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.aiChatContextualPageContextManuallyAttachedNative.name)
    }

    @Test("Page context manually attached frontend pixel fires correctly")
    func testPageContextManuallyAttachedFrontendPixel() {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { event in
            PixelFiringMock.fire(event, withAdditionalParameters: [:])
        })

        // WHEN
        sut.firePageContextManuallyAttachedFrontend()

        // THEN
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.aiChatContextualPageContextManuallyAttachedFrontend.name)
    }

    // MARK: - Navigation Pixel with Deduplication

    @Test("Page context updated on navigation fires for new URL")
    func testPageContextUpdatedOnNavigationFirstTime() {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { event in
            PixelFiringMock.fire(event, withAdditionalParameters: [:])
        })

        // WHEN
        sut.firePageContextUpdatedOnNavigation(url: "https://example.com")

        // THEN
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.aiChatContextualPageContextUpdatedOnNavigation.name)
    }

    @Test("Page context updated on navigation fires for different URL")
    func testPageContextUpdatedOnNavigationDifferentURLs() {
        // GIVEN
        var pixelCount = 0
        let sut = AIChatContextualModePixelHandler(firePixel: { _ in
            pixelCount += 1
        })

        // WHEN
        sut.firePageContextUpdatedOnNavigation(url: "https://example.com")
        sut.firePageContextUpdatedOnNavigation(url: "https://different.com")

        // THEN
        #expect(pixelCount == 2)
    }

    // MARK: - Page Context Removal Pixels

    @Test("Page context removed native pixel fires correctly")
    func testPageContextRemovedNativePixel() {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { event in
            PixelFiringMock.fire(event, withAdditionalParameters: [:])
        })

        // WHEN
        sut.firePageContextRemovedNative()

        // THEN
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.aiChatContextualPageContextRemovedNative.name)
    }

    @Test("Page context removed frontend pixel fires correctly")
    func testPageContextRemovedFrontendPixel() {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { event in
            PixelFiringMock.fire(event, withAdditionalParameters: [:])
        })

        // WHEN
        sut.firePageContextRemovedFrontend()

        // THEN
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.aiChatContextualPageContextRemovedFrontend.name)
    }

    // MARK: - Prompt Submission Pixels

    @Test("Prompt submitted with context pixel fires correctly")
    func testPromptSubmittedWithContextPixel() {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { event in
            PixelFiringMock.fire(event, withAdditionalParameters: [:])
        })

        // WHEN
        sut.firePromptSubmittedWithContext()

        // THEN
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.aiChatContextualPromptSubmittedWithContextNative.name)
    }

    @Test("Prompt submitted without context pixel fires correctly")
    func testPromptSubmittedWithoutContextPixel() {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { event in
            PixelFiringMock.fire(event, withAdditionalParameters: [:])
        })

        // WHEN
        sut.firePromptSubmittedWithoutContext()

        // THEN
        #expect(PixelFiringMock.lastPixelName == Pixel.Event.aiChatContextualPromptSubmittedWithoutContextNative.name)
    }

    // MARK: - Manual Attach State Management

    @Test("Manual attach state begins correctly")
    func testBeginManualAttach() {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { _ in })

        // WHEN
        sut.beginManualAttach()

        // THEN
        #expect(sut.isManualAttachInProgress == true)
    }

    @Test("Manual attach state ends correctly")
    func testEndManualAttach() {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { _ in })

        // WHEN
        sut.beginManualAttach()
        sut.endManualAttach()

        // THEN
        #expect(sut.isManualAttachInProgress == false)
    }

    @Test("Manual attach state is initially false")
    func testManualAttachStateInitiallyFalse() {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { _ in })

        // THEN
        #expect(sut.isManualAttachInProgress == false)
    }

    // MARK: - Reset Functionality

    @Test("Reset clears navigation URL")
    func testResetClearsNavigationURL() {
        // GIVEN
        var pixelCount = 0
        let sut = AIChatContextualModePixelHandler(firePixel: { _ in
            pixelCount += 1
        })

        // WHEN
        sut.firePageContextUpdatedOnNavigation(url: "https://example.com")
        sut.reset()
        sut.firePageContextUpdatedOnNavigation(url: "https://example.com")

        // THEN
        #expect(pixelCount == 2)
    }

    @Test("Reset clears manual attach state")
    func testResetClearsManualAttachState() {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { _ in })

        // WHEN
        sut.beginManualAttach()
        sut.reset()

        // THEN
        #expect(sut.isManualAttachInProgress == false)
    }

    // MARK: - Thread Safety Tests

    @Test("Concurrent access to manual attach state is thread-safe")
    func testConcurrentManualAttachAccess() async {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { _ in })

        // WHEN
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    sut.beginManualAttach()
                    _ = sut.isManualAttachInProgress
                    sut.endManualAttach()
                }
            }
        }

        // THEN
        #expect(sut.isManualAttachInProgress == false)
    }

    @Test("Concurrent navigation pixel calls are thread-safe")
    func testConcurrentNavigationPixelCalls() async {
        // GIVEN
        var pixelCount = 0
        let sut = AIChatContextualModePixelHandler(firePixel: { _ in
            pixelCount += 1
        })

        // WHEN
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    sut.firePageContextUpdatedOnNavigation(url: "https://example\(i).com")
                }
            }
        }

        // THEN
        #expect(pixelCount == 10)
    }

    @Test("Concurrent reset and navigation calls are thread-safe")
    func testConcurrentResetAndNavigation() async {
        // GIVEN
        let sut = AIChatContextualModePixelHandler(firePixel: { _ in })

        // WHEN
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    if i % 2 == 0 {
                        sut.reset()
                    } else {
                        sut.firePageContextUpdatedOnNavigation(url: "https://example.com")
                    }
                }
            }
        }

        // THEN - Should complete without crashing
        #expect(true)
    }
}
