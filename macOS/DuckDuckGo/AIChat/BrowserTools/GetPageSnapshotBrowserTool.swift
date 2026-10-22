//
//  GetPageSnapshotBrowserTool.swift
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

/// Describes the visible forms on a tab Duck.ai opened, with refs the other form tools act on.
@MainActor
final class GetPageSnapshotBrowserTool: BrowserTool {

    /// Matches `AIChatBrowserToolsSubfeature.getPageSnapshot`, which is how the catalog gates it.
    let name = "getPageSnapshot"
    let title = "Get page snapshot"
    let description = "Describe the visible forms on a tab Duck.ai opened: fields by label, buttons and page messages."
    let permissionMode = BrowserToolPermissionMode.auto

    let inputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "tabId": ["type": "string", "description": "A tabId returned by openTab."]
        ],
        "required": ["tabId"]
    ]

    let outputSchema: JSONValue? = BrowserToolFormSchemas.snapshot

    let annotations: MCPToolAnnotations? = MCPToolAnnotations(readOnlyHint: true,
                                                              destructiveHint: false,
                                                              idempotentHint: true,
                                                              openWorldHint: false)

    private let windowControllersManager: WindowControllersManagerProtocol
    private let openedTabs: BrowserToolOpenedTabs
    private let driver: BrowserToolFormDriving

    init(windowControllersManager: WindowControllersManagerProtocol,
         openedTabs: BrowserToolOpenedTabs,
         driver: BrowserToolFormDriving) {
        self.windowControllersManager = windowControllersManager
        self.openedTabs = openedTabs
        self.driver = driver
    }

    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        guard !context.isBurner else { return .failure(.unavailable) }
        switch BrowserToolTargetTab.openedTab(tabIDArgument: arguments?["tabId"], context: context, openedTabs: openedTabs, in: windowControllersManager) {
        case .failure(let failure):
            return .failure(failure)
        case .resolved(let tabID, let tab):
            guard let page = await driver.page(in: tab.webView) else { return .failure(.unavailable) }
            return .success(BrowserToolForms.snapshot(of: page, tabID: tabID))
        }
    }
}

/// Output schemas shared by the form tools: `clickElement` returns a snapshot too.
enum BrowserToolFormSchemas {

    static let errors: JSONValue = [
        "type": "array",
        "items": [
            "type": "object",
            "properties": [
                "ref": ["type": "string"],
                "message": ["type": "string"]
            ],
            "required": ["message"]
        ]
    ]

    static let snapshot: JSONValue = [
        "type": "object",
        "properties": [
            "tabId": ["type": "string"],
            "url": ["type": "string"],
            "title": ["type": "string"],
            "forms": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "ref": ["type": "string"],
                        "name": ["type": "string"],
                        "fields": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "ref": ["type": "string"],
                                    "label": ["type": "string"],
                                    "type": ["type": "string"],
                                    "required": ["type": "boolean"],
                                    "value": ["type": "string"],
                                    "options": [
                                        "type": "array",
                                        "items": [
                                            "type": "object",
                                            "properties": [
                                                "value": ["type": "string"],
                                                "label": ["type": "string"]
                                            ],
                                            "required": ["value", "label"]
                                        ]
                                    ],
                                    "error": ["type": "string"],
                                    "autocomplete": ["type": "string"],
                                    "readOnly": ["type": "boolean"],
                                    "sensitive": ["type": "string", "enum": ["payment"]]
                                ],
                                "required": ["ref", "label", "type", "required", "autocomplete"]
                            ]
                        ],
                        "buttons": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "ref": ["type": "string"],
                                    "text": ["type": "string"],
                                    "isSubmit": ["type": "boolean"]
                                ],
                                "required": ["ref", "text", "isSubmit"]
                            ]
                        ],
                        "hasPaymentFields": ["type": "boolean"]
                    ],
                    "required": ["ref", "fields", "buttons", "hasPaymentFields"]
                ]
            ],
            "messages": ["type": "array", "items": ["type": "string"]]
        ],
        "required": ["tabId", "url", "title", "forms", "messages"]
    ]
}
