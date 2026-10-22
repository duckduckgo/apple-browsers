//
//  ShowTabBrowserTool.swift
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

/// Brings a tab Duck.ai opened to the front, optionally focusing one element. This is how a
/// checkout is handed to the user: with the card field focused, Autofill offers their saved card,
/// and they pay and place the order themselves.
@MainActor
final class ShowTabBrowserTool: BrowserTool {

    /// How long the tab's page gets to land in its window before the element is focused.
    static let windowWaitTimeout: TimeInterval = 1

    /// Matches `AIChatBrowserToolsSubfeature.showTab`, which is how the catalog gates it.
    let name = "showTab"
    let title = "Show tab"
    let description = "Bring a tab you opened to the front, optionally focusing an element. Use it to hand a checkout to the user: focus the card-number field so they can pay with their saved card and place the order themselves. You can't fill payment fields or submit payment forms."
    let permissionMode = BrowserToolPermissionMode.auto

    let inputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "tabId": ["type": "string", "description": "A tabId returned by openTab."],
            "focusRef": ["type": "string", "description": "Optional. A field or button ref from getPageSnapshot to scroll to and focus."]
        ],
        "required": ["tabId"]
    ]

    let outputSchema: JSONValue? = [
        "type": "object",
        "properties": [
            "tabId": ["type": "string"],
            "url": ["type": "string"],
            "title": ["type": "string"],
            "shown": ["type": "boolean"]
        ],
        "required": ["tabId", "url", "title", "shown"]
    ]

    let annotations: MCPToolAnnotations? = MCPToolAnnotations(readOnlyHint: false,
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
        let tabID: TabIdentifier
        let tab: Tab
        switch BrowserToolTargetTab.openedTab(tabIDArgument: arguments?["tabId"], context: context, openedTabs: openedTabs, in: windowControllersManager) {
        case .failure(let failure): return .failure(failure)
        case .resolved(let resolvedID, let resolvedTab):
            tabID = resolvedID
            tab = resolvedTab
        }

        let focusRef: String?
        switch arguments?["focusRef"] {
        case .none, .some(.null):
            focusRef = nil
        case .some(.string(let ref)) where !ref.isEmpty:
            focusRef = ref
        default:
            return .failure(.invalidArguments)
        }
        // Checked before anything moves, so a wrong ref does not leave the user looking at the wrong thing.
        if let focusRef {
            guard let page = await driver.page(in: tab.webView) else { return .failure(.unavailable) }
            let exists = page.fields.contains { $0.ref == focusRef && $0.visible } || page.buttons.contains { $0.ref == focusRef && $0.visible }
            guard exists else { return .failure(.notFound) }
        }

        // The tab may have been dragged to another window.
        guard let collection = windowControllersManager.allTabCollectionViewModels.first(where: { $0.indexInAllTabs(where: { $0.uuid == tabID }) != nil }),
              let index = collection.indexInAllTabs(where: { $0.uuid == tabID }),
              collection.selectTab(at: index) != nil else {
            return .failure(.notFound)
        }
        let window = windowControllersManager.windowController(for: collection)?.window
        window?.makeKeyAndOrderFront(nil)

        if let focusRef {
            if let window {
                await waitUntilShown(tab)
                window.makeFirstResponder(tab.webView)
            }
            _ = await driver.focus(focusRef, in: tab.webView)
        }

        return .success([
            "tabId": .string(tabID),
            "url": .string(tab.webView.url?.absoluteString ?? tab.content.userEditableUrl?.absoluteString ?? ""),
            "title": .string(tab.title ?? ""),
            "shown": true
        ])
    }

    /// Selecting a tab puts its web view in the window on a later turn of the main queue.
    private func waitUntilShown(_ tab: Tab) async {
        let deadline = Date().addingTimeInterval(Self.windowWaitTimeout)
        while tab.webView.window == nil, Date() < deadline, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
