//
//  ClickElementBrowserTool.swift
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

/// Clicks a button that moves through a form, such as Next or Back, on a tab Duck.ai opened, and
/// returns the page afterwards. A submit button is refused: submitting needs the user's approval.
@MainActor
final class ClickElementBrowserTool: BrowserTool {

    static let quietPeriod: TimeInterval = 0.5
    static let timeout: TimeInterval = 10

    /// Matches `AIChatBrowserToolsSubfeature.clickElement`, which is how the catalog gates it.
    let name = "clickElement"
    let title = "Click element"
    let description = "Click a non-submit button on a tab Duck.ai opened, such as Next or Back, and return the page afterwards. Submit buttons go through submitForm."
    let permissionMode = BrowserToolPermissionMode.auto

    let inputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "tabId": ["type": "string", "description": "A tabId returned by openTab."],
            "ref": ["type": "string", "description": "A button ref from getPageSnapshot."]
        ],
        "required": ["tabId", "ref"]
    ]

    let outputSchema: JSONValue? = [
        "type": "object",
        "properties": [
            "tabId": ["type": "string"],
            "url": ["type": "string"],
            "title": ["type": "string"],
            "navigated": ["type": "boolean"],
            "errors": BrowserToolFormSchemas.errors,
            "snapshot": BrowserToolFormSchemas.snapshot
        ],
        "required": ["tabId", "url", "title", "navigated", "snapshot"]
    ]

    let annotations: MCPToolAnnotations? = MCPToolAnnotations(readOnlyHint: false,
                                                              destructiveHint: false,
                                                              idempotentHint: false,
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
        guard let ref = arguments?["ref"]?.stringValue, !ref.isEmpty else { return .failure(.invalidArguments) }
        guard let page = await driver.page(in: tab.webView) else { return .failure(.unavailable) }

        // Only what the snapshot lists can be clicked.
        guard let button = page.buttons.first(where: { $0.ref == ref && $0.visible && !$0.disabled }) else {
            return .failure(.notFound)
        }
        guard !BrowserToolForms.isSubmit(button) else { return .failure(.useSubmitForm) }

        let startURL = tab.webView.url
        guard await driver.click(ref, in: tab.webView) else { return .failure(.notFound) }
        let navigated: Bool
        do {
            navigated = try await settler.settle(tab, from: startURL, quietPeriod: Self.quietPeriod, timeout: Self.timeout)
        } catch {
            return .failure(.cancelled)
        }
        guard let after = await driver.page(in: tab.webView) else { return .failure(.unavailable) }

        var result: [String: JSONValue] = [
            "tabId": .string(tabID),
            "url": .string(after.url),
            "title": .string(after.title),
            "navigated": .bool(navigated),
            "snapshot": BrowserToolForms.snapshot(of: after, tabID: tabID)
        ]
        let errors = BrowserToolForms.errors(in: after)
        if !errors.isEmpty {
            result["errors"] = .array(errors.map(\.jsonValue))
        }
        return .success(.object(result))
    }
}
