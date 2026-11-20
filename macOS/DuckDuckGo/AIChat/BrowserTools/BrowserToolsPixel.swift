//
//  BrowserToolsPixel.swift
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
import Foundation
import PixelKit

/// Duck.ai browser tools. Parameters carry fixed values only: never URLs, titles, page text, search terms or IDs.
enum BrowserToolsPixel: PixelKit.Event {

    /// Event Trigger: A browser tool call finished, whatever its result. `tool` is a slug from `toolSlugs`.
    /// `resultCount` is set for a successful search or list tool only.
    case call(tool: String, result: ClientToolError?, permissionPath: BrowserToolPermissionPath, duration: TimeInterval?, resultCount: Int?)

    /// Event Trigger: A browser tool call succeeded. Fired daily.
    case used

    /// Event Trigger: A single-tool permission prompt closed, answered or not. `tool` is a slug from `toolSlugs`.
    /// `promptNumberInChat` is set only with batch access on, when calls carry their chat.
    case promptAnswered(tool: String, answer: BrowserToolPromptAnswer, promptNumberInChat: Int?, timeToAnswer: TimeInterval)

    /// Event Trigger: A `requestAccess` call finished, with or without a prompt.
    case accessRequested(BrowserToolAccessRequestOutcome)

    /// Event Trigger: One tool's result in a finished `requestAccess` call. `tool` is a slug from `toolSlugs`.
    case accessResult(tool: String, access: BrowserToolAccessRequestOutcome.ToolResult)

    /// Event Trigger: Duck.ai was offered browser tools. Fired daily.
    case enabled

    /// Event Trigger: Duck.ai sent a tool call native could not read, or for a capability this app doesn't know.
    /// `tool` is the raw capability name, sent only as a slug from `toolSlugs`, otherwise as `unknown`.
    case protocolError(ProtocolErrorReason, tool: String?)

    enum ProtocolErrorReason: String {
        case invalidRequest = "invalid_request"
        case unknownCapability = "unknown_capability"
    }

    /// Event Trigger: A call to this tool succeeded. Fired daily. `tool` is a slug from `toolSlugs`.
    case usedTool(String)

    /// Catalog names to pixel slugs. Any other name came from the page and is never sent.
    static let toolSlugs = [
        "listOpenTabs": "list_open_tabs",
        "readTabContent": "read_tab_content",
        "searchHistory": "search_history",
        "findInPage": "find_in_page",
        "highlightInPage": "highlight_in_page",
        "switchToTab": "switch_to_tab",
        "pinTab": "pin_tab",
        "openTab": "open_tab",
        "bookmarkTab": "bookmark_tab",
        "closeTabs": "close_tabs",
        "searchDownloads": "search_downloads",
        "searchBookmarks": "search_bookmarks"
    ]

    var namePrefix: PixelKitNamePrefix { .none }

    var name: String {
        switch self {
        case .call: "aichat_tools_call_macos"
        case .used: "aichat_tools_used_macos"
        case .promptAnswered: "aichat_tools_prompt_answered_macos"
        case .accessRequested: "aichat_tools_access_requested_macos"
        case .accessResult: "aichat_tools_access_result_macos"
        case .enabled: "aichat_tools_enabled_macos"
        case .protocolError: "aichat_tools_protocol_error_macos"
        case .usedTool(let tool): "aichat_tools_used_\(tool)_macos"
        }
    }

    var parameters: [String: String]? {
        if case .promptAnswered(let tool, let answer, let number, let timeToAnswer) = self {
            var parameters = ["tool": tool, "answer": answer.rawValue, "time_to_answer": Self.timeToAnswerBucket(timeToAnswer)]
            parameters["prompt_number_in_chat"] = number.map { $0 >= 4 ? "4_plus" : String($0) }
            return parameters
        }
        if case .accessRequested(let outcome) = self {
            var parameters = ["decision": outcome.decision.rawValue]
            parameters["requested"] = outcome.requested.map(String.init)
            parameters["asked"] = outcome.asked.map(String.init)
            parameters["removed"] = outcome.removed.map(String.init)
            return parameters
        }
        if case .accessResult(let tool, let access) = self {
            return ["tool": tool, "access": access.rawValue]
        }
        if case .protocolError(let reason, let tool) = self {
            return ["reason": reason.rawValue, "tool": tool.flatMap { Self.toolSlugs[$0] } ?? "unknown"]
        }
        guard case .call(let tool, let result, let permissionPath, let duration, let resultCount) = self else { return nil }
        var parameters = ["tool": tool, "result": result?.rawValue ?? "success", "permission_path": permissionPath.rawValue]
        parameters["duration"] = duration.map(Self.durationBucket)
        parameters["result_count"] = resultCount.map(Self.resultCountBucket)
        return parameters
    }

    var standardParameters: [PixelKitStandardParameter]? { [.pixelSource] }

    static func durationBucket(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<0.1: "lt_100ms"
        case ..<0.5: "lt_500ms"
        case ..<2: "lt_2s"
        case ..<10: "lt_10s"
        default: "gte_10s"
        }
    }

    static func timeToAnswerBucket(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<2: "lt_2s"
        case ..<10: "lt_10s"
        case ..<60: "lt_60s"
        default: "gte_60s"
        }
    }

    static func resultCountBucket(_ count: Int) -> String {
        switch count {
        case ...0: "0"
        case ...5: "1-5"
        case ...20: "6-20"
        default: "21_plus"
        }
    }
}

struct BrowserToolsPixelInstrumentation: BrowserToolsInstrumentation {
    let pixelFiring: PixelFiring?

    func toolCallDidFinish(tool: String, response: ExecuteClientToolResponse, trace: BrowserToolCallTrace) {
        guard let slug = BrowserToolsPixel.toolSlugs[tool] else { return }
        let error: ClientToolError? = if case .failure(_, let error) = response { error } else { nil }
        pixelFiring?.fire(BrowserToolsPixel.call(tool: slug, result: error, permissionPath: trace.permissionPath,
                                                 duration: trace.executionDuration, resultCount: error == nil ? trace.resultCount : nil))
        guard error == nil else { return }
        pixelFiring?.fire(BrowserToolsPixel.used, frequency: .daily)
        pixelFiring?.fire(BrowserToolsPixel.usedTool(slug), frequency: .daily)
    }

    func promptDidClose(tool: String, answer: BrowserToolPromptAnswer, promptNumberInChat: Int?, timeToAnswer: TimeInterval) {
        guard let slug = BrowserToolsPixel.toolSlugs[tool] else { return }
        pixelFiring?.fire(BrowserToolsPixel.promptAnswered(tool: slug, answer: answer, promptNumberInChat: promptNumberInChat,
                                                           timeToAnswer: timeToAnswer))
    }

    func accessRequestDidFinish(_ outcome: BrowserToolAccessRequestOutcome) {
        pixelFiring?.fire(BrowserToolsPixel.accessRequested(outcome))
        // A name outside the catalog came from the page and is never sent.
        for result in outcome.results {
            guard let slug = BrowserToolsPixel.toolSlugs[result.tool] else { continue }
            pixelFiring?.fire(BrowserToolsPixel.accessResult(tool: slug, access: result.result))
        }
    }
}
