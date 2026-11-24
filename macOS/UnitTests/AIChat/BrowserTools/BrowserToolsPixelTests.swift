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
    @Test("A successful search or list call carries its bucketed result count; a failed one doesn't", .timeLimit(.minutes(1)))
    func resultCountIsSentForSuccessfulCountedCallsOnly() {
        instrumentation.toolCallDidFinish(tool: "searchHistory", response: .success(callId: "call", value: ["results": []]),
                                          trace: BrowserToolCallTrace(permissionPath: .always, executionDuration: 0.01, resultCount: 7))
        instrumentation.toolCallDidFinish(tool: "searchHistory", response: .failure(callId: "call", error: .executionFailed),
                                          trace: BrowserToolCallTrace(permissionPath: .always, executionDuration: 0.01, resultCount: 7))

        #expect(pixels.actualFireCalls[0].pixel.parameters?["result_count"] == "6-20")
        #expect(pixels.actualFireCalls[3].pixel.name == "aichat_tools_call_macos")
        #expect(pixels.actualFireCalls[3].pixel.parameters?["result_count"] == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A closed prompt fires its answer, bucketed time and chat number", .timeLimit(.minutes(1)))
    func closedPromptFiresPromptAnswered() {
        instrumentation.promptDidClose(tool: "pinTab", answer: .allowForChat, promptNumberInChat: 5, timeToAnswer: 12)
        instrumentation.promptDidClose(tool: "searchHistory", answer: .timeout, promptNumberInChat: nil, timeToAnswer: 120)
        instrumentation.promptDidClose(tool: "https://example.com", answer: .never, promptNumberInChat: 1, timeToAnswer: 1)

        #expect(pixels.actualFireCalls.map(\.pixel.name) == ["aichat_tools_prompt_answered_macos", "aichat_tools_prompt_answered_macos"])
        #expect(pixels.actualFireCalls.map(\.frequency) == [.standard, .standard])
        #expect(pixels.actualFireCalls.map(\.pixel.parameters) == [
            ["tool": "pin_tab", "answer": "allow_for_chat", "prompt_number_in_chat": "4_plus", "time_to_answer": "lt_60s"],
            ["tool": "search_history", "answer": "timeout", "time_to_answer": "gte_60s"]
        ])
    }

    @available(iOS 16, macOS 13, *)
    @Test("A finished requestAccess fires its counts and decision, then one result per known tool", .timeLimit(.minutes(1)))
    func accessRequestFiresRequestedAndResults() {
        instrumentation.accessRequestDidFinish(BrowserToolAccessRequestOutcome(
            decision: .allow, requested: 3, asked: 2, removed: 1,
            results: [("searchHistory", .granted), ("pinTab", .removed), ("https://example.com", .unavailable)]))
        instrumentation.accessRequestDidFinish(BrowserToolAccessRequestOutcome(decision: .invalid))

        #expect(pixels.actualFireCalls.map(\.pixel.name) == ["aichat_tools_access_requested_macos", "aichat_tools_access_result_macos",
                                                             "aichat_tools_access_result_macos", "aichat_tools_access_requested_macos"])
        #expect(pixels.actualFireCalls.map(\.pixel.parameters) == [
            ["decision": "allow", "requested": "3", "asked": "2", "removed": "1"],
            ["tool": "search_history", "access": "granted"],
            ["tool": "pin_tab", "access": "removed"],
            ["decision": "invalid"]
        ])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Times to answer fall into the spec's buckets", .timeLimit(.minutes(1)),
          arguments: zip([0, 1.999, 2, 9.999, 10, 59.999, 60, 600], ["lt_2s", "lt_2s", "lt_10s", "lt_10s", "lt_60s", "lt_60s", "gte_60s", "gte_60s"]))
    func timeToAnswerBuckets(seconds: Double, bucket: String) {
        #expect(BrowserToolsPixel.timeToAnswerBucket(seconds) == bucket)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Result counts fall into the spec's buckets", .timeLimit(.minutes(1)),
          arguments: zip([0, 1, 5, 6, 20, 21, 500], ["0", "1-5", "1-5", "6-20", "6-20", "21_plus", "21_plus"]))
    func resultCountBuckets(count: Int, bucket: String) {
        #expect(BrowserToolsPixel.resultCountBucket(count) == bucket)
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
    @Test("Answer rows keep each tool's best result, bucket the count and give any the best result", .timeLimit(.minutes(1)))
    func answerRowsBucketAndRank() {
        let tools = [("listOpenTabs", "error"), ("listOpenTabs", "not_allowed"), ("pinTab", "error"), ("openTab", "error"),
                     ("closeTabs", "error"), ("searchHistory", "error")].map { AIChatBrowserToolAnswerTool(name: $0.0, result: $0.1) }

        let rows = BrowserToolsPixel.answerRows(tools)

        #expect(rows.map(\.tool) == ["close_tabs", "list_open_tabs", "open_tab", "pin_tab", "search_history", "any"])
        #expect(rows.map(\.toolResult) == ["error", "not_allowed", "error", "error", "error", "not_allowed"])
        #expect(Set(rows.map(\.toolsInAnswer)) == ["4_plus"])
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
