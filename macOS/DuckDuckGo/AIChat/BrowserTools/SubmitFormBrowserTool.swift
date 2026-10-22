//
//  SubmitFormBrowserTool.swift
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

/// Submits a form on a tab Duck.ai opened. The user approves every submit from a preview of what
/// the site will receive; no decision is remembered, and login and checkout pages are refused.
@MainActor
final class SubmitFormBrowserTool: BrowserTool {

    static let quietPeriod: TimeInterval = 0.5
    static let timeout: TimeInterval = 15

    /// Matches `AIChatBrowserToolsSubfeature.submitForm`, which is how the catalog gates it.
    let name = "submitForm"
    let title = "Submit form"
    let description = "Submit a form on a tab Duck.ai opened. The user approves every submit from a preview of what will be sent."
    let permissionMode = BrowserToolPermissionMode.ask
    let approvesEachCall = true

    let inputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "tabId": ["type": "string", "description": "A tabId returned by openTab."],
            "formRef": ["type": "string", "description": "A form ref from getPageSnapshot."]
        ],
        "required": ["tabId", "formRef"]
    ]

    let outputSchema: JSONValue? = [
        "type": "object",
        "properties": [
            "tabId": ["type": "string"],
            "url": ["type": "string"],
            "title": ["type": "string"],
            "submitted": ["type": "boolean"],
            "confirmationText": ["type": "string"],
            "errors": BrowserToolFormSchemas.errors
        ],
        "required": ["tabId", "url", "title", "submitted", "confirmationText", "errors"]
    ]

    /// Sending a form cannot be undone, and it reaches a site outside the browser.
    let annotations: MCPToolAnnotations? = MCPToolAnnotations(readOnlyHint: false,
                                                              destructiveHint: true,
                                                              idempotentHint: false,
                                                              openWorldHint: true)

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

    func approvalPrompt(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolApprovalPrompt {
        switch await target(arguments: arguments, context: context) {
        case .failure(let failure):
            return .refuse(failure)
        case .ready(_, _, let page, let formRef):
            guard let preview = BrowserToolForms.preview(of: formRef, in: page) else { return .refuse(.notFound) }
            return .ask(message: "Duck.ai wants to submit a form on \(preview.site).", meta: ["formPreview": preview.jsonValue])
        }
    }

    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        let tabID: TabIdentifier
        let tab: Tab
        let page: BrowserToolRawPage
        let formRef: String
        switch await target(arguments: arguments, context: context) {
        case .failure(let failure):
            return .failure(failure)
        case .ready(let readyTabID, let readyTab, let readyPage, let readyFormRef):
            tabID = readyTabID
            tab = readyTab
            page = readyPage
            formRef = readyFormRef
        }

        let submitter = page.buttons.first { $0.formRef == formRef && $0.visible && !$0.disabled && BrowserToolForms.isSubmit($0) }
        let startURL = tab.webView.url
        guard await driver.submit(formRef: formRef, submitterRef: submitter?.ref, in: tab.webView) else { return .failure(.notFound) }
        let navigated: Bool
        do {
            navigated = try await settler.settle(tab, from: startURL, quietPeriod: Self.quietPeriod, timeout: Self.timeout)
        } catch {
            return .failure(.cancelled)
        }

        let after = await driver.page(in: tab.webView)
        let outcome = BrowserToolForms.submitOutcome(navigated: navigated, formRef: formRef, before: page, after: after)
        return .success([
            "tabId": .string(tabID),
            "url": .string(after?.url ?? tab.webView.url?.absoluteString ?? page.url),
            "title": .string(after?.title ?? tab.title ?? ""),
            "submitted": .bool(outcome.submitted),
            "confirmationText": .string(BrowserToolForms.confirmationText(of: after)),
            "errors": .array(outcome.errors.map(\.jsonValue))
        ])
    }

    private enum Target {
        case ready(tabID: TabIdentifier, tab: Tab, page: BrowserToolRawPage, formRef: String)
        case failure(BrowserToolFailure)
    }

    /// Shared by the prompt and the submit, so the checks that guard the prompt also guard the submit.
    private func target(arguments: JSONValue?, context: BrowserToolCallContext) async -> Target {
        guard !context.isBurner else { return .failure(.unavailable) }
        let tabID: TabIdentifier
        let tab: Tab
        switch BrowserToolTargetTab.openedTab(tabIDArgument: arguments?["tabId"], context: context, openedTabs: openedTabs, in: windowControllersManager) {
        case .failure(let failure): return .failure(failure)
        case .resolved(let resolvedID, let resolvedTab):
            tabID = resolvedID
            tab = resolvedTab
        }
        guard let formRef = arguments?["formRef"]?.stringValue, !formRef.isEmpty else { return .failure(.invalidArguments) }
        guard let page = await driver.page(in: tab.webView) else { return .failure(.unavailable) }
        guard !BrowserToolForms.isRestrictedPage(page) else { return .failure(.restricted) }
        guard page.forms.contains(where: { $0.ref == formRef && $0.visible }) else { return .failure(.notFound) }
        return .ready(tabID: tabID, tab: tab, page: page, formRef: formRef)
    }
}
