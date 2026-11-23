//
//  BrowserToolsPixelTests.swift
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
@_spi(Testing) import PixelKit
import Testing
@testable import DuckDuckGo_Privacy_Browser

@MainActor
struct BrowserToolsPixelTests {

    private let pixels = PixelKitMock()
    private var instrumentation: BrowserToolsPixelInstrumentation { BrowserToolsPixelInstrumentation(pixelFiring: pixels) }

    @available(iOS 16, macOS 13, *)
    @Test("A successful call fires the call pixel and both daily used pixels", .timeLimit(.minutes(1)))
    func successfulCallFiresCallAndDailyUsedPixels() {
        instrumentation.toolCallDidFinish(tool: "listOpenTabs", response: .success(callId: "call", value: ["tabs": []]),
                                          trace: BrowserToolCallTrace(permissionPath: .prompt, executionDuration: 0.3))

        #expect(pixels.actualFireCalls.map(\.pixel.name) == ["aichat_tools_call_macos", "aichat_tools_used_macos",
                                                             "aichat_tools_used_list_open_tabs_macos"])
        #expect(pixels.actualFireCalls.map(\.frequency) == [.standard, .daily, .daily])
        #expect(pixels.actualFireCalls[0].pixel.parameters == ["tool": "list_open_tabs", "result": "success",
                                                               "permission_path": "prompt", "duration": "lt_500ms"])
        #expect(pixels.actualFireCalls[1].pixel.parameters == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A refused call fires only the call pixel, without a duration", .timeLimit(.minutes(1)))
    func refusedCallFiresOnlyTheCallPixel() {
        instrumentation.toolCallDidFinish(tool: "searchHistory", response: .failure(callId: "call", error: .denied),
                                          trace: BrowserToolCallTrace(permissionPath: .never))

        #expect(pixels.actualFireCalls.map(\.pixel.name) == ["aichat_tools_call_macos"])
        #expect(pixels.actualFireCalls[0].pixel.parameters == ["tool": "search_history", "result": "denied", "permission_path": "never"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("A success over the result limit reports execution_failed and is not a use", .timeLimit(.minutes(1)))
    func oversizedSuccessReportsExecutionFailed() {
        let oversized = ExecuteClientToolResponse.success(callId: "call", value: .string(String(repeating: "a", count: 600_000)))

        instrumentation.toolCallDidFinish(tool: "readTabContent", response: oversized.limitedToResultBytes(),
                                          trace: BrowserToolCallTrace(permissionPath: .chat, executionDuration: 12))

        #expect(pixels.actualFireCalls.map(\.pixel.name) == ["aichat_tools_call_macos"])
        #expect(pixels.actualFireCalls[0].pixel.parameters == ["tool": "read_tab_content", "result": "execution_failed",
                                                               "permission_path": "chat", "duration": "gte_10s"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("A tool name outside the catalog is never sent", .timeLimit(.minutes(1)))
    func unknownToolNameFiresNothing() {
        instrumentation.toolCallDidFinish(tool: "https://example.com", response: .failure(callId: "call", error: .unavailable),
                                          trace: BrowserToolCallTrace())

        #expect(pixels.actualFireCalls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Every catalog tool has a slug", .timeLimit(.minutes(1)))
    func everyCatalogToolHasASlug() {
        #expect(Set(BrowserToolsPixel.toolSlugs.keys) == Set(ClientToolCapability.browserTools.map(\.name)))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Durations fall into the spec's buckets", .timeLimit(.minutes(1)),
          arguments: zip([0, 0.099, 0.1, 0.499, 0.5, 1.999, 2, 9.999, 10, 60],
                         ["lt_100ms", "lt_100ms", "lt_500ms", "lt_500ms", "lt_2s", "lt_2s", "lt_10s", "lt_10s", "gte_10s", "gte_10s"]))
    func durationBuckets(seconds: Double, bucket: String) {
        #expect(BrowserToolsPixel.durationBucket(seconds) == bucket)
    }
}
