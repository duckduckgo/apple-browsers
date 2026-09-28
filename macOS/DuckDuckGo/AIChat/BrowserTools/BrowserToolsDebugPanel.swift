//
//  BrowserToolsDebugPanel.swift
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

#if DEBUG

import AIChat
import AppKit
import UserScript
import WebKit

/// DEBUG-only stand-in for the Duck.ai front end, driving the same dispatch and handlers a page
/// message would. It also receives the permission prompts a page would, and answers them.
@MainActor
final class BrowserToolsDebugPanel: NSWindowController {

    private let userScript: AIChatUserScript
    private let chatHandler: AIChatUserScriptHandler
    private let windowControllersManager: WindowControllersManagerProtocol
    private let service: AIChatBrowserToolsService

    private let targetLabel = NSTextField(labelWithString: "")
    private let toolNameField = NSTextField(string: "listOpenTabs")
    private let argumentsField = NSTextField(string: "{}")
    private let promptsStack = NSStackView()
    private let logView = NSTextView()
    private var promptRows: [String: NSView] = [:]

    init(windowControllersManager: WindowControllersManagerProtocol,
         service: AIChatBrowserToolsService = NSApp.delegateTyped.aiChatBrowserToolsService) {
        self.windowControllersManager = windowControllersManager
        self.service = service
        let chatHandler = AIChatUserScriptHandler(
            storage: DefaultAIChatPreferencesStorage(),
            windowControllersManager: windowControllersManager,
            pixelFiring: nil,
            statisticsLoader: nil,
            syncServiceProvider: { nil },
            syncErrorHandler: NSApp.delegateTyped.syncErrorHandler,
            featureFlagger: NSApp.delegateTyped.featureFlagger,
            browserTools: service
        )
        self.chatHandler = chatHandler
        self.userScript = AIChatUserScript(handler: chatHandler, urlSettings: UserDefaults.standard.keyedStoring())

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = "Duck.ai Browser Tools"
        super.init(window: window)
        window.contentView = makeContentView()
        window.center()
        refreshTarget()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Actions

    @objc private func initializeSession() {
        run("initialize", params: [
            "protocolVersion": "2025-11-25",
            "capabilities": ["elicitation": ["form": [:] as [String: Any]]],
            "clientInfo": ["name": "browser-tools-debug-panel", "version": "1"]
        ])
    }

    @objc private func notifyInitialized() {
        run("notifications/initialized", params: [:])
    }

    @objc private func listTools() {
        run("tools/list", params: [:])
    }

    @objc private func callTool() {
        let name = toolNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.contains(where: \.isWhitespace), !name.contains("{") else {
            appendToLog("→ '\(name)' is not a tool name — arguments JSON belongs in the arguments field\n")
            return
        }
        guard let argumentsData = argumentsField.stringValue.data(using: .utf8),
              let arguments = try? JSONSerialization.jsonObject(with: argumentsData) else {
            appendToLog("→ arguments are not valid JSON; nothing sent")
            return
        }
        run("tools/call", params: [
            "name": name,
            "callId": "panel-\(Int(Date().timeIntervalSince1970 * 1000))",
            "arguments": arguments
        ])
    }

    /// Reads the window directly — there is no tool for discovering a tabId to hand to
    /// `switchToTab`.
    @objc private func listWindowTabs() {
        guard let collection = windowControllersManager.lastKeyMainWindowController?
            .mainViewController.tabCollectionViewModel else {
            appendToLog("→ no window")
            return
        }
        let tabs = (collection.pinnedTabsCollection?.tabs ?? []) + collection.tabCollection.tabs
        appendToLog("→ tabs in this window (panel only, not a tool)")
        for tab in tabs {
            appendToLog("   \(tab.title ?? tab.url?.absoluteString ?? "")")
            appendToLog("      {\"tabId\": \"\(tab.uuid)\"}")
        }
        appendToLog("")
    }

    /// The owner tab is re-read on every click, so switching tabs mid-handshake lands you on one
    /// with no session. Showing the state beats discovering it as `not_initialized` on a call.
    @objc private func refreshTarget() {
        guard let tab = selectedTab else {
            targetLabel.stringValue = "No tab selected — open a tab to act as the Duck.ai owner tab."
            return
        }
        let burner = tab.burnerMode.isBurner ? "  ·  Fire Window" : ""
        let session = service.sessions.session(forOwnerTabID: tab.uuid)
        let state = switch session {
        case .none: "no session — run initialize"
        case .some(let session) where !session.isInitialized: "awaiting notifications/initialized"
        case .some: "initialized"
        }
        targetLabel.stringValue = "Owner tab: \(tab.uuid)\(burner)  ·  \(state)"
    }

    // MARK: - Prompts

    private static let answers: [(title: String, result: MCPElicitationResult)] = [
        ("Allow once", MCPElicitationResult(action: .accept, content: ["choice": "allowOnce"])),
        ("Always", MCPElicitationResult(action: .accept, content: ["choice": "alwaysAllow"])),
        ("Never", MCPElicitationResult(action: .accept, content: ["choice": "neverAllow"])),
        ("Decline", MCPElicitationResult(action: .decline)),
        ("Cancel", MCPElicitationResult(action: .cancel))
    ]

    private func addPromptRow(for params: MCPElicitationCreateParams) {
        let label = NSTextField(labelWithString: "\(params.message)  [\(params.id.prefix(8))]")
        label.lineBreakMode = .byTruncatingTail
        var views: [NSView] = [label]
        for answer in Self.answers {
            let button = PromptButton(title: answer.title, target: self, action: #selector(answerPrompt(_:)))
            button.bezelStyle = .rounded
            button.promptID = params.id
            button.result = answer.result
            views.append(button)
        }
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.spacing = 6
        promptsStack.addArrangedSubview(row)
        promptRows[params.id] = row
    }

    /// Goes through `elicitation/response` exactly as the page would, so the answer exercises the
    /// same decode, correlation and persistence.
    @objc private func answerPrompt(_ sender: PromptButton) {
        removePromptRow(id: sender.promptID)
        var result: [String: Any] = ["action": sender.result.action]
        if let choice = sender.result.content?["choice"]?.stringValue {
            result["content"] = ["choice": choice]
        }
        run("elicitation/response", params: ["id": sender.promptID, "result": result])
    }

    private func removePromptRow(id: String) {
        guard let row = promptRows.removeValue(forKey: id) else { return }
        promptsStack.removeArrangedSubview(row)
        row.removeFromSuperview()
    }

    /// Drops rows whose prompt already resolved — timed out, or answered from elsewhere.
    private func pruneStalePromptRows() {
        let pending = Set(service.elicitations.pendingPrompts.map(\.id))
        for id in promptRows.keys where !pending.contains(id) {
            removePromptRow(id: id)
        }
    }

    // MARK: -

    private func run(_ method: String, params: [String: Any]) {
        refreshTarget()
        guard let webView = selectedTab?.webView else {
            appendToLog("→ no selected tab; cannot resolve an owner tab")
            return
        }

        // Same lookup a page message performs. Its closure needs a concrete `WKScriptMessage`,
        // which only WebKit can make, so the typed handler behind it is invoked directly below.
        guard userScript.handler(forMethodNamed: method) != nil else {
            appendToLog("→ \(method): not wired into the dispatch switch")
            return
        }
        guard let invoke = typedHandler(for: method) else {
            appendToLog("→ \(method): no typed handler")
            return
        }

        appendToLog("→ \(method) \(prettyPrinted(params))")
        Task { @MainActor in
            let response = await invoke(params, SyntheticUserScriptMessage(name: method, body: params, webView: webView))
            appendToLog("← \(method) \(response.map(prettyPrinted) ?? "(no reply)")\n")
            pruneStalePromptRows()
            refreshTarget()
        }
    }

    private func typedHandler(for method: String) -> ((Any, UserScriptMessage) async -> Encodable?)? {
        switch AIChatUserScriptMessages(rawValue: method) {
        case .initialize: chatHandler.mcpInitialize
        case .notificationsInitialized: chatHandler.mcpNotificationsInitialized
        case .toolsList: chatHandler.mcpToolsList
        case .toolsCall: { [chatHandler, weak self] params, message in
            await chatHandler.mcpToolsCall(params: params, message: message, elicitationPusher: self)
        }
        case .elicitationResponse: chatHandler.mcpElicitationResponse
        default: nil
        }
    }

    private var selectedTab: Tab? {
        windowControllersManager.lastKeyMainWindowController?.mainViewController.tabCollectionViewModel.selectedTab
    }

    private func prettyPrinted(_ value: Any) -> String {
        if let encodable = value as? Encodable {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            if let data = try? encoder.encode(encodable), let string = String(data: data, encoding: .utf8) {
                return string
            }
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: value)
    }

    private func appendToLog(_ text: String) {
        logView.string += text + "\n"
        logView.scrollToEndOfDocument(nil)
    }

    // MARK: - Layout

    private func makeContentView() -> NSView {
        let buttons = NSStackView(views: [
            makeButton("initialize", #selector(initializeSession)),
            makeButton("notifications/initialized", #selector(notifyInitialized)),
            makeButton("tools/list", #selector(listTools)),
            makeButton("Show tab IDs", #selector(listWindowTabs)),
            makeButton("Refresh target", #selector(refreshTarget))
        ])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        toolNameField.placeholderString = "tool name"
        argumentsField.placeholderString = "{\"limit\": 10}"
        let call = NSStackView(views: [
            NSTextField(labelWithString: "tools/call  name:"),
            toolNameField,
            NSTextField(labelWithString: "arguments:"),
            argumentsField,
            makeButton("Call", #selector(callTool))
        ])
        call.orientation = .horizontal
        call.spacing = 8
        NSLayoutConstraint.activate([
            toolNameField.widthAnchor.constraint(equalToConstant: 130),
            argumentsField.widthAnchor.constraint(greaterThanOrEqualToConstant: 280)
        ])

        promptsStack.orientation = .vertical
        promptsStack.alignment = .leading
        promptsStack.spacing = 6

        logView.isEditable = false
        logView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        let scroll = NSScrollView()
        scroll.documentView = logView
        scroll.hasVerticalScroller = true

        targetLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        targetLabel.lineBreakMode = .byTruncatingMiddle

        let stack = NSStackView(views: [targetLabel, buttons, call, promptsStack, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.setHuggingPriority(.defaultLow, for: .vertical)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 320)
        ])
        return stack
    }

    private func makeButton(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }
}

/// Receives the prompt a page would, since no page is listening.
extension BrowserToolsDebugPanel: AIChatElicitationPushing {

    func pushElicitationCreate(_ params: MCPElicitationCreateParams) -> Bool {
        appendToLog("⇠ elicitation/create \(prettyPrinted(params))\n")
        addPromptRow(for: params)
        return true
    }
}

private final class PromptButton: NSButton {
    var promptID = ""
    var result = MCPElicitationResult.cancel
}

/// Stands in for the `WKScriptMessage` a real page would send. Only `messageWebView` matters to the
/// handlers — it is how the owner tab is resolved.
private struct SyntheticUserScriptMessage: UserScriptMessage {
    let name: String
    let body: Any
    let webView: WKWebView

    var messageName: String { name }
    var messageBody: Any { body }
    var messageHost: String { "duck.ai" }
    var isMainFrame: Bool { true }
    var messageWebView: WKWebView? { webView }
}

#endif
