//
//  PageContextExtractionPixelHandlerTests.swift
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

import AIChat
import Testing

@testable import DuckDuckGo_Privacy_Browser

struct PageContextExtractionPixelHandlerTests {

    private func capture(_ outcome: PageContextExtractionOutcome,
                         trigger: PageContextExtractionTrigger = .navigation,
                         latency: PageContextExtractionLatencyBucket? = nil) -> AIChatPixel? {
        var fired: AIChatPixel?
        let handler = PageContextExtractionPixelHandler(firePixel: { fired = $0 })
        handler.fire(outcome, trigger: trigger, latency: latency)
        return fired
    }

    @available(iOS 16, macOS 13, *)
    @Test("success maps to the extraction-success pixel with no extra params", .timeLimit(.minutes(1)))
    func successMapsToSuccessPixel() {
        let pixel = capture(.success, trigger: .navigation, latency: .under1s)
        #expect(pixel?.name == "aichat_page_context_extraction_success")
        #expect(pixel?.parameters?["reason"] == nil)
        #expect(pixel?.parameters?["trigger"] == nil)
        #expect(pixel?.parameters?["latency"] == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("failure(emptyContent) maps to failed pixel with reason, trigger, latency", .timeLimit(.minutes(1)))
    func emptyContentMapsToFailedWithParams() {
        let pixel = capture(.failure(.emptyContent), trigger: .auto, latency: .oneToFiveSeconds)
        #expect(pixel?.name == "aichat_page_context_extraction_failed")
        #expect(pixel?.parameters?["reason"] == "empty_content")
        #expect(pixel?.parameters?["trigger"] == "auto")
        #expect(pixel?.parameters?["latency"] == "1_to_5s")
    }

    @available(iOS 16, macOS 13, *)
    @Test("failure(deserializeFailed) maps to failed pixel with snake_case reason", .timeLimit(.minutes(1)))
    func deserializeFailedMapsToFailedWithReason() {
        #expect(capture(.failure(.deserializeFailed))?.parameters?["reason"] == "deserialize_failed")
    }

    @available(iOS 16, macOS 13, *)
    @Test("failure without a latency omits the latency param", .timeLimit(.minutes(1)))
    func failureWithoutLatencyOmitsLatency() {
        let pixel = capture(.failure(.noWebView), trigger: .navigation, latency: nil)
        #expect(pixel?.parameters?["reason"] == "no_webview")
        #expect(pixel?.parameters?["latency"] == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("prevented maps to prevented pixel with category, reason, trigger", .timeLimit(.minutes(1)))
    func preventedMapsToPreventedWithParams() {
        let pixel = capture(.prevented("pdf"), trigger: .tabContent)
        #expect(pixel?.name == "aichat_page_context_extraction_prevented")
        #expect(pixel?.parameters?["category"] == "pdf")
        #expect(pixel?.parameters?["reason"] == "non_attachable")
        #expect(pixel?.parameters?["trigger"] == "tab_content")
    }
}
