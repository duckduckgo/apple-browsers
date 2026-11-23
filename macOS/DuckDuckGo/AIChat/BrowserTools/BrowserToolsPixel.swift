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

    /// Event Trigger: The user changed a tool's permission in Settings or in the tab bar panel, including a row reset.
    case permissionChanged(tool: String, from: BrowserToolPermissionState, to: BrowserToolPermissionState, source: PermissionSource)

    /// Event Trigger: The user reset every tool permission in Settings.
    case permissionsReset

    /// Event Trigger: Duck.ai reported that an answer finished in a chat with browser tools. One per row of `answerRows`.
    case answerCompleted(AnswerRow, modelTier: String)

    /// Event Trigger: The user rated such an answer with a thumb. One per row of `answerRows`.
    case answerRated(AnswerRow, modelTier: String, rating: String)

    /// `tool` is a slug, `any` (the answer used tools) or `none` (it used none, and has no `toolResult`).
    struct AnswerRow: Equatable {
        let tool: String
        let toolResult: String?
        let toolsInAnswer: String
    }

    enum PermissionSource: String {
        case settings, panel
    }

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
        case .permissionChanged: "aichat_tools_permission_changed_macos"
        case .permissionsReset: "aichat_tools_permissions_reset_macos"
        case .answerCompleted: "aichat_tools_answer_completed_macos"
        case .answerRated: "aichat_tools_answer_rated_macos"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .call(let tool, let result, let permissionPath, let duration, let resultCount):
            var parameters = ["tool": tool, "result": result?.rawValue ?? "success", "permission_path": permissionPath.rawValue]
            parameters["duration"] = duration.map(Self.durationBucket)
            parameters["result_count"] = resultCount.map(Self.resultCountBucket)
            return parameters
        case .promptAnswered(let tool, let answer, let number, let timeToAnswer):
            var parameters = ["tool": tool, "answer": answer.rawValue, "time_to_answer": Self.timeToAnswerBucket(timeToAnswer)]
            parameters["prompt_number_in_chat"] = number.map { $0 >= 4 ? "4_plus" : String($0) }
            return parameters
        case .accessRequested(let outcome):
            var parameters = ["decision": outcome.decision.rawValue]
            parameters["requested"] = outcome.requested.map(String.init)
            parameters["asked"] = outcome.asked.map(String.init)
            parameters["removed"] = outcome.removed.map(String.init)
            return parameters
        case .accessResult(let tool, let access):
            return ["tool": tool, "access": access.rawValue]
        case .protocolError(let reason, let tool):
            return ["reason": reason.rawValue, "tool": tool.flatMap { Self.toolSlugs[$0] } ?? "unknown"]
        case .permissionChanged(let tool, let from, let to, let source):
            return ["tool": tool, "from": from.rawValue, "to": to.rawValue, "source": source.rawValue]
        case .answerCompleted(let row, let modelTier):
            return row.parameters(modelTier: modelTier)
        case .answerRated(let row, let modelTier, let rating):
            return row.parameters(modelTier: modelTier).merging(["rating": rating]) { $1 }
        case .used, .enabled, .usedTool, .permissionsReset:
            return nil
        }
    }

    /// The pixels for a browser tools answer metric from Duck.ai. Unknown tools and results are dropped;
    /// a rating other than `up` or `down` drops the metric.
    static func answerPixels(for metric: AIChatMetric) -> [BrowserToolsPixel] {
        let rows = answerRows(metric.browserTools ?? [])
        let modelTier = (metric.modelTier ?? .unknown).rawValue
        switch metric.metricName {
        case .browserToolsAnswerCompleted:
            return rows.map { .answerCompleted($0, modelTier: modelTier) }
        case .browserToolsAnswerRated:
            guard let rating = metric.rating, ["up", "down"].contains(rating) else { return [] }
            return rows.map { .answerRated($0, modelTier: modelTier, rating: rating) }
        default:
            return []
        }
    }

    /// Results from worst to best.
    private static let answerResultRanks = ["error": 0, "not_allowed": 1, "success": 2]

    /// One row per known tool, plus `any`, whose result is the best of them. An answer without known tools is one `none` row.
    static func answerRows(_ tools: [AIChatBrowserToolAnswerTool]) -> [AnswerRow] {
        var ranks: [String: Int] = [:]
        for tool in tools {
            guard let slug = toolSlugs[tool.name], let rank = answerResultRanks[tool.result] else { continue }
            ranks[slug] = max(ranks[slug] ?? rank, rank)
        }
        let count = ranks.count < 4 ? String(ranks.count) : "4_plus"
        let result = { (rank: Int) in answerResultRanks.first { $0.value == rank }?.key }
        guard let best = ranks.values.max() else {
            return [AnswerRow(tool: "none", toolResult: nil, toolsInAnswer: count)]
        }
        return ranks.sorted { $0.key < $1.key }.map { AnswerRow(tool: $0.key, toolResult: result($0.value), toolsInAnswer: count) }
            + [AnswerRow(tool: "any", toolResult: result(best), toolsInAnswer: count)]
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

private extension BrowserToolsPixel.AnswerRow {
    func parameters(modelTier: String) -> [String: String] {
        var parameters = ["tool": tool, "tools_in_answer": toolsInAnswer, "model_tier": modelTier]
        parameters["tool_result"] = toolResult
        return parameters
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
