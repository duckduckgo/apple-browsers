//
//  AIChatScreenshotProviderTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import FeatureFlags_macOS
import Foundation
import PrivacyConfig
import Testing
@testable import DuckDuckGo_Privacy_Browser

@MainActor
@Suite("Duck.ai screenshot provider")
struct AIChatScreenshotProviderTests {

    @available(macOS 13, *)
    @Test("The flag off omits screenshot modes", .timeLimit(.minutes(1)))
    func flagOffOmitsModes() {
        let provider = AIChatScreenshotProvider(featureFlagger: MockFeatureFlagger())
        #expect(provider.screenshotModes == nil)
    }

    @available(macOS 13, *)
    @Test("The flag on offers both modes, Drag to Select first", .timeLimit(.minutes(1)))
    func flagOnOffersBothModes() {
        let provider = AIChatScreenshotProvider(featureFlagger: makeFeatureFlagger(enabled: true))
        #expect(provider.screenshotModes == ["dragToSelect", "selectWindowOrDisplay"])
    }

    @available(macOS 13, *)
    @Test("A capture with the flag off is a cancel", .timeLimit(.minutes(1)))
    func captureWithFlagOffCancels() async {
        let provider = AIChatScreenshotProvider(featureFlagger: MockFeatureFlagger())
        #expect(await provider.captureScreenshot(mode: "dragToSelect", requestingWebView: nil, source: .duckai) == .cancelled)
    }

    @available(macOS 13, *)
    @Test("An unknown mode is a cancel", .timeLimit(.minutes(1)))
    func unknownModeCancels() async {
        let provider = AIChatScreenshotProvider(featureFlagger: makeFeatureFlagger(enabled: true))
        #expect(await provider.captureScreenshot(mode: "wholeDesk", requestingWebView: nil, source: .sidebar) == .cancelled)
    }

    @available(macOS 13, *)
    @Test("Replies encode to the shape Duck.ai expects", .timeLimit(.minutes(1)))
    func repliesEncodeToTheContractShape() throws {
        #expect(try json(.cancelled) == "{}")
        #expect(try json(.failed) == #"{"error":"screenshotFailed"}"#)
        let image = AIChatCaptureScreenshotResponse(image: .init(data: "AAA=", format: "png", kind: "window"), error: nil)
        #expect(try json(image) == #"{"image":{"data":"AAA=","format":"png","kind":"window"}}"#)
    }

    @available(macOS 13, *)
    @Test("The pixels carry kind or reason, and source", .timeLimit(.minutes(1)))
    func pixelsCarryTheirParameters() {
        let taken = AIChatPixel.aiChatDuckAiScreenshotTaken(kind: .selection, source: .sidebar)
        #expect(taken.name == "aichat_duckai_screenshot_taken")
        #expect(taken.parameters == ["kind": "selection", "source": "sidebar"])

        let failed = AIChatPixel.aiChatDuckAiScreenshotFailed(reason: .failed, source: .duckai)
        #expect(failed.name == "aichat_duckai_screenshot_failed")
        #expect(failed.parameters == ["reason": "failed", "source": "duckai"])
    }

    private func makeFeatureFlagger(enabled: Bool) -> MockFeatureFlagger {
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = enabled ? [.aiChatDuckAiScreenshot] : []
        return featureFlagger
    }

    private func json(_ response: AIChatCaptureScreenshotResponse) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try #require(String(bytes: try encoder.encode(response), encoding: .utf8))
    }
}
