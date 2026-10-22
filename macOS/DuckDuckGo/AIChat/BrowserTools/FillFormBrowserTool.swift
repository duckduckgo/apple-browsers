//
//  FillFormBrowserTool.swift
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

/// Fills fields on a tab Duck.ai opened, the way a person would. Never submits: that is
/// `submitForm`, which the user approves. A field native refuses fails alone; the rest still fill.
@MainActor
final class FillFormBrowserTool: BrowserTool {

    static let maxFields = 50

    /// How long the page gets to show validation after the last change, for checks run on change or blur.
    static let quietPeriod: TimeInterval = 0.3
    static let timeout: TimeInterval = 2

    /// Matches `AIChatBrowserToolsSubfeature.fillForm`, which is how the catalog gates it.
    let name = "fillForm"
    let title = "Fill form"
    let description = "Fill fields on a tab Duck.ai opened, by the refs getPageSnapshot returned. Never submits."
    let permissionMode = BrowserToolPermissionMode.auto

    let inputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "tabId": ["type": "string", "description": "A tabId returned by openTab."],
            "fields": [
                "type": "array",
                "minItems": 1,
                "maxItems": .int(FillFormBrowserTool.maxFields),
                "items": [
                    "type": "object",
                    "properties": [
                        "ref": ["type": "string", "description": "A field ref from getPageSnapshot."],
                        "value": [
                            "type": "string",
                            "description": "Select and radio: an option value or label. Checkbox: \"true\" or \"false\". Date: YYYY-MM-DD."
                        ]
                    ],
                    "required": ["ref", "value"]
                ]
            ]
        ],
        "required": ["tabId", "fields"]
    ]

    let outputSchema: JSONValue? = [
        "type": "object",
        "properties": [
            "tabId": ["type": "string"],
            "filled": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": ["ref": ["type": "string"], "value": ["type": "string"]],
                    "required": ["ref", "value"]
                ]
            ],
            "failed": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "ref": ["type": "string"],
                        "error": ["type": "string", "enum": ["not_found", "restricted", "invalid_option", "disabled", "user_action_required"]]
                    ],
                    "required": ["ref", "error"]
                ]
            ],
            "errors": BrowserToolFormSchemas.errors
        ],
        "required": ["tabId", "filled", "failed", "errors"]
    ]

    let annotations: MCPToolAnnotations? = MCPToolAnnotations(readOnlyHint: false,
                                                              destructiveHint: false,
                                                              idempotentHint: true,
                                                              openWorldHint: false)

    private let windowControllersManager: WindowControllersManagerProtocol
    private let openedTabs: BrowserToolOpenedTabs
    private let driver: BrowserToolFormDriving
    private let settler: BrowserToolPageSettling

    init(windowControllersManager: WindowControllersManagerProtocol,
         openedTabs: BrowserToolOpenedTabs,
         driver: BrowserToolFormDriving,
         settler: BrowserToolPageSettling) {
        self.windowControllersManager = windowControllersManager
        self.openedTabs = openedTabs
        self.driver = driver
        self.settler = settler
    }

    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        guard !context.isBurner else { return .failure(.unavailable) }
        let tabID: TabIdentifier
        let tab: Tab
        switch BrowserToolTargetTab.openedTab(tabIDArgument: arguments?["tabId"], context: context, openedTabs: openedTabs, in: windowControllersManager) {
        case .failure(let failure): return .failure(failure)
        case .resolved(let resolvedID, let resolvedTab):
            tabID = resolvedID
            tab = resolvedTab
        }
        guard let entries = Self.entries(from: arguments?["fields"]) else { return .failure(.invalidArguments) }
        guard let page = await driver.page(in: tab.webView) else { return .failure(.unavailable) }

        // Payment fields fail as `user_action_required`: the user fills those with their own Autofill.
        let plan = BrowserToolForms.fillPlan(for: entries, fields: BrowserToolForms.fields(in: page))
        var filled: [JSONValue] = []
        var failed: [JSONValue] = plan.failed.map { ["ref": .string($0.ref), "error": .string($0.error)] }

        if !plan.steps.isEmpty {
            let startURL = tab.webView.url
            guard let readback = await driver.apply(plan.steps.map(\.action), in: tab.webView) else { return .failure(.unavailable) }
            for (step, result) in zip(plan.steps, readback) {
                guard result.found else {
                    failed.append(["ref": .string(step.fieldRef), "error": "not_found"])
                    continue
                }
                filled.append(["ref": .string(step.fieldRef), "value": .string(Self.valueReadBack(for: step, from: result))])
            }
            do {
                _ = try await settler.settle(tab, from: startURL, quietPeriod: Self.quietPeriod, timeout: Self.timeout)
            } catch {
                return .failure(.cancelled)
            }
        }

        let errors = await driver.page(in: tab.webView).map { BrowserToolForms.errors(in: $0) } ?? []
        return .success([
            "tabId": .string(tabID),
            "filled": .array(filled),
            "failed": .array(failed),
            "errors": .array(errors.map(\.jsonValue))
        ])
    }

    /// 1 to 50 `{ref, value}` objects, both strings, or nil.
    static func entries(from argument: JSONValue?) -> [(ref: String, value: String)]? {
        guard let items = argument?.arrayValue, (1...maxFields).contains(items.count) else { return nil }
        var entries: [(ref: String, value: String)] = []
        for item in items {
            guard let ref = item["ref"]?.stringValue, !ref.isEmpty, let value = item["value"]?.stringValue else { return nil }
            entries.append((ref, value))
        }
        return entries
    }

    /// What the page holds now, in the same terms the snapshot uses.
    private static func valueReadBack(for step: BrowserToolFillPlan.Step, from result: BrowserToolFillReadback) -> String {
        switch step.fieldType {
        case "checkbox":
            return result.checked == true ? "true" : "false"
        case "radio":
            return result.checked == true ? result.value ?? "" : ""
        default:
            return result.value ?? ""
        }
    }
}
