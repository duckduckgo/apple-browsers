//
//  CloseTabsBrowserTool.swift
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

import Foundation
import PrivacyConfig

@MainActor
public final class CloseTabsBrowserTool: BrowserTool {

    public static let maxTabIDs = 50

    public let name = AIChatBrowserToolsSubfeature.closeTabs.rawValue
    public let permissionMode = BrowserToolPermissionMode.ask

    public let inputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "tabIds": [
                "type": "array",
                "items": ["type": "string"],
                "minItems": 1,
                "maxItems": .int(CloseTabsBrowserTool.maxTabIDs),
                "description": "1 to 50 tab IDs from listOpenTabs. Never the chat's own tab: a call that names it closes nothing."
            ]
        ],
        "required": ["tabIds"],
        "additionalProperties": false
    ]

    public struct PreparedBatch {
        let ids: [String]
        let close: @MainActor () -> Set<String>

        public init(ids: [String], close: @escaping @MainActor () -> Set<String>) {
            self.ids = ids
            self.close = close
        }
    }

    private let prepareBatch: @MainActor ([String], BrowserToolCallContext) -> Result<PreparedBatch, BrowserToolFailure>

    public init(prepareBatch: @escaping @MainActor ([String], BrowserToolCallContext) -> Result<PreparedBatch, BrowserToolFailure>) {
        self.prepareBatch = prepareBatch
    }

    public func acceptsArguments(_ arguments: JSONValue?) -> Bool {
        if case .ids = BrowserToolTabIDs(arguments: arguments, maxCount: Self.maxTabIDs) { return true }
        return false
    }

    public func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        guard !context.isBurner else { return .failure(.unavailable) }
        guard case .ids(let requestedIDs) = BrowserToolTabIDs(arguments: arguments, maxCount: Self.maxTabIDs) else {
            return .failure(.invalidArguments)
        }

        switch prepareBatch(requestedIDs, context) {
        case .failure(let failure):
            return .failure(failure)
        case .success(let batch):
            // Closing the chat's own tab would close the chat, so a call that names it closes nothing.
            guard !batch.ids.contains(context.ownerTabID) else { return .failure(.unavailable) }
            guard !Task.isCancelled else { return .failure(.cancelled) }

            let closedIDs = batch.close()
            return .success(["tabs": .array(batch.ids.map { id in
                ["tabId": .string(id), "closed": .bool(closedIDs.contains(id))]
            })])
        }
    }
}
