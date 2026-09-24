//
//  BrowserToolsDebugViewController.swift
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
import Persistence
import UserScript
import WebKit

struct BrowserToolsDebugSettings: StoringKeys {
    let showsPanelInSidebar = StorageKey<Bool>(BrowserToolsDebugSettingsKey.showsPanelInSidebar)
}

enum BrowserToolsDebugSettingsKey: String, StorageKeyDescribing {
    case showsPanelInSidebar = "ai-chat_browser-tools-debug-panel-in-sidebar"
}

/// DEBUG-only stand-in for the Duck.ai front end. Drives the same dispatch and handlers a page
/// message would, receives the pushes a page would, and answers permission prompts.
///
/// The owner tab comes from `ownerTabProvider`: the selected tab when shown as a window, the host
/// tab when shown inside a chat sidebar.
@MainActor
final class BrowserToolsDebugViewController: NSViewController {

    private let userScript: AIChatUserScript
    private let chatHandler: AIChatUserScriptHandler
    private let windowControllersManager: WindowControllersManagerProtocol
    private let service: AIChatBrowserToolsService
    private let ownerTabProvider: () -> Tab?

    private let targetLabel = NSTextField(labelWithString: "")
    private let toolPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let argumentsField = NSTextField(string: "{}")
    private let promptsStack = NSStackView()
    private let logStack = NSStackView()
    private let logScroll = NSScrollView()
    private var promptRows: [String: NSView] = [:]

    init(windowControllersManager: WindowControllersManagerProtocol,
         service: AIChatBrowserToolsService = NSApp.delegateTyped.aiChatBrowserToolsService,
         ownerTabProvider: @escaping () -> Tab?) {
        self.windowControllersManager = windowControllersManager
        self.service = service
        self.ownerTabProvider = ownerTabProvider
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
        self.userScript = AIChatUserScript(handler: chatHandler, urlSettings: UserDefaults.standard.keyedStoring(), browserTools: nil)
        super.init(nibName: nil, bundle: nil)
        service.register(self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = makeContentView()
        reloadToolPicker()
        refreshTarget()
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
        guard let name = toolPicker.titleOfSelectedItem, !name.isEmpty else {
            appendToLog(summary: "→ no tool selected", detail: nil)
            return
        }
        guard let argumentsData = argumentsField.stringValue.data(using: .utf8),
              let arguments = try? JSONSerialization.jsonObject(with: argumentsData) else {
            appendToLog(summary: "→ arguments are not valid JSON; nothing sent", detail: argumentsField.stringValue)
            return
        }
        run("tools/call", params: [
            "name": name,
            "callId": "panel-\(Int(Date().timeIntervalSince1970 * 1000))",
            "arguments": arguments
        ])
    }

    @objc private func toolPicked() {
        argumentsField.stringValue = exampleArguments(for: toolPicker.titleOfSelectedItem ?? "")
    }

    /// Reads the owner's window directly — there is no tool for discovering a tabId to hand to
    /// `switchToTab`.
    @objc private func listWindowTabs() {
        guard let collection = ownerCollection else {
            appendToLog(summary: "→ no window", detail: nil)
            return
        }
        let tabs = (collection.pinnedTabsCollection?.tabs ?? []) + collection.tabCollection.tabs
        let lines = tabs.map { "\($0.title ?? $0.url?.absoluteString ?? "")\n   {\"tabId\": \"\($0.uuid)\"}" }
        appendToLog(summary: "→ \(tabs.count) tabs in this window (panel only, not a tool)", detail: lines.joined(separator: "\n"), expanded: true)
    }

    @objc private func clearLog() {
        for row in logStack.arrangedSubviews {
            logStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
    }

    /// The owner tab is re-read on every click, so the header shows which one and its session state.
    @objc func refreshTarget() {
        reloadToolPicker()
        guard let tab = ownerTabProvider() else {
            targetLabel.stringValue = "No owner tab — open a tab to act as the Duck.ai owner tab."
            return
        }
        let burner = tab.burnerMode.isBurner ? "  ·  Fire Window" : ""
        let session = service.sessions.session(forOwnerTabID: tab.uuid)
        let state = switch session {
        case .none: "no session — run initialize"
        case .some(let session) where !session.isInitialized: "awaiting notifications/initialized"
        case .some: "initialized"
        }
        let title = tab.title.map { " (\($0.prefix(40)))" } ?? ""
        targetLabel.stringValue = "Owner tab: \(tab.uuid)\(title)\(burner)  ·  \(state)"
    }

    // MARK: - Tool picker

    private func reloadToolPicker() {
        let names = service.catalog.enabledTools.map(\.name)
        let selected = toolPicker.titleOfSelectedItem
        guard names != toolPicker.itemTitles else { return }
        toolPicker.removeAllItems()
        toolPicker.addItems(withTitles: names)
        if let selected, names.contains(selected) {
            toolPicker.selectItem(withTitle: selected)
        } else {
            toolPicker.selectItem(at: 0)
            toolPicked()
        }
    }

    /// Ready-to-run arguments per tool, so a tester never starts from an empty object.
    private func exampleArguments(for tool: String) -> String {
        switch tool {
        case "listOpenTabs": return #"{"limit": 10}"#
        case "switchToTab":
            let owner = ownerTabProvider()?.uuid
            let other = ownerCollection.map { ($0.pinnedTabsCollection?.tabs ?? []) + $0.tabCollection.tabs }?
                .first { $0.uuid != owner }
            return #"{"tabId": "\#(other?.uuid ?? "<paste from Show tab IDs>")"}"#
        case "searchHistory": return #"{"query": "wiki", "limit": 5}"#
        case "readTabContent": return "{}"
        case "findInPage": return #"{"query": "games"}"#
        case "highlightInPage": return #"{"quotes": ["games"]}"#
        default: return "{}"
        }
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
            button.controlSize = .small
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

    // MARK: - Running messages

    private func run(_ method: String, params: [String: Any]) {
        refreshTarget()
        guard let webView = ownerTabProvider()?.webView else {
            appendToLog(summary: "→ no owner tab; cannot resolve a session", detail: nil)
            return
        }

        // Same lookup a page message performs. Its closure needs a concrete `WKScriptMessage`,
        // which only WebKit can make, so the typed handler behind it is invoked directly below.
        guard userScript.handler(forMethodNamed: method) != nil else {
            appendToLog(summary: "→ \(method): not wired into the dispatch switch", detail: nil)
            return
        }
        guard let invoke = typedHandler(for: method) else {
            appendToLog(summary: "→ \(method): no typed handler", detail: nil)
            return
        }

        appendToLog(summary: "→ \(method)", detail: prettyPrinted(params))
        Task { @MainActor in
            let response = await invoke(params, SyntheticUserScriptMessage(name: method, body: params, webView: webView))
            let json = response.flatMap(Self.jsonObject) ?? [:]
            appendToLog(summary: "← \(method)  \(Self.summary(of: json, for: method))", detail: prettyPrinted(Self.displayForm(of: json)))
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

    private var ownerCollection: TabCollectionViewModel? {
        guard let tab = ownerTabProvider() else { return nil }
        return AIChatTabPickerSource.ownerCollection(for: tab.webView, ownerTabID: tab.uuid, in: windowControllersManager)
    }

    // MARK: - Log formatting

    private static func jsonObject(_ encodable: Encodable) -> Any? {
        guard let data = try? JSONEncoder().encode(encodable) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    /// One line a tester can scan without expanding: the failure token, the tool count, or `ok`.
    private static func summary(of json: Any, for method: String) -> String {
        guard let dictionary = json as? [String: Any] else { return "" }
        if let error = dictionary["error"] as? String { return error }
        if let tools = dictionary["tools"] as? [Any] { return "\(tools.count) tools" }
        if let result = dictionary["result"] as? [String: Any] {
            if result["isError"] as? Bool == true,
               let text = (result["content"] as? [[String: Any]])?.first?["text"] as? String {
                return text
            }
            return "ok"
        }
        if let version = dictionary["protocolVersion"] as? String { return version }
        return dictionary.isEmpty ? "{}" : "ok"
    }

    /// The `content` text block duplicates `structuredContent` as an escaped string; showing both
    /// only obscures the payload.
    private static func displayForm(of json: Any) -> Any {
        guard var dictionary = json as? [String: Any],
              var result = dictionary["result"] as? [String: Any],
              result["structuredContent"] != nil else { return json }
        result.removeValue(forKey: "content")
        dictionary["result"] = result
        return dictionary
    }

    private func prettyPrinted(_ value: Any) -> String {
        if let encodable = value as? Encodable, !(value is [String: Any]), !(value is [Any]) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            if let data = try? encoder.encode(encodable), let string = String(data: data, encoding: .utf8) {
                return string
            }
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: value)
    }

    private func appendToLog(summary: String, detail: String?, expanded: Bool = false) {
        let entry = LogEntryView(summary: summary, detail: detail, expanded: expanded)
        logStack.addArrangedSubview(entry)
        entry.widthAnchor.constraint(equalTo: logStack.widthAnchor).isActive = true
        view.layoutSubtreeIfNeeded()
        logScroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, logStack.frame.height - logScroll.contentSize.height)))
    }

    // MARK: - Layout

    private func makeContentView() -> NSView {
        let buttons = NSStackView(views: [
            makeButton("initialize", #selector(initializeSession)),
            makeButton("notifications/initialized", #selector(notifyInitialized)),
            makeButton("tools/list", #selector(listTools)),
            makeButton("Show tab IDs", #selector(listWindowTabs)),
            makeButton("Refresh", #selector(refreshTarget)),
            makeButton("Clear log", #selector(clearLog))
        ])
        buttons.orientation = .horizontal
        buttons.spacing = 6
        buttons.setClippingResistancePriority(.defaultLow, for: .horizontal)

        toolPicker.target = self
        toolPicker.action = #selector(toolPicked)
        toolPicker.controlSize = .small
        argumentsField.placeholderString = "{}"
        argumentsField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        let call = NSStackView(views: [
            NSTextField(labelWithString: "tools/call"),
            toolPicker,
            argumentsField,
            makeButton("Call", #selector(callTool))
        ])
        call.orientation = .horizontal
        call.spacing = 6
        call.setClippingResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            toolPicker.widthAnchor.constraint(equalToConstant: 130),
            argumentsField.widthAnchor.constraint(greaterThanOrEqualToConstant: 140)
        ])

        promptsStack.orientation = .vertical
        promptsStack.alignment = .leading
        promptsStack.spacing = 6

        logStack.orientation = .vertical
        logStack.alignment = .leading
        logStack.spacing = 2
        logStack.translatesAutoresizingMaskIntoConstraints = false
        let logDocument = LogDocumentView()
        logDocument.translatesAutoresizingMaskIntoConstraints = false
        logDocument.addSubview(logStack)
        logScroll.documentView = logDocument
        logScroll.hasVerticalScroller = true
        logScroll.drawsBackground = false
        NSLayoutConstraint.activate([
            logStack.topAnchor.constraint(equalTo: logDocument.topAnchor),
            logStack.leadingAnchor.constraint(equalTo: logDocument.leadingAnchor),
            logStack.trailingAnchor.constraint(equalTo: logDocument.trailingAnchor),
            logStack.bottomAnchor.constraint(equalTo: logDocument.bottomAnchor),
            logDocument.widthAnchor.constraint(equalTo: logScroll.contentView.widthAnchor)
        ])

        targetLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        targetLabel.lineBreakMode = .byTruncatingMiddle

        let stack = NSStackView(views: [targetLabel, buttons, call, promptsStack, logScroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        logScroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            logScroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20),
            logScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
            targetLabel.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20)
        ])
        return stack
    }

    private func makeButton(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        return button
    }
}

/// Receives the pushes a page would, since no page is listening.
extension BrowserToolsDebugViewController: AIChatBrowserToolsPushing {

    var pushTargetWebView: WKWebView? { ownerTabProvider()?.webView }

    func pushToolsListChanged() {
        appendToLog(summary: "⇠ notifications/tools/list_changed", detail: nil)
        reloadToolPicker()
    }

    func pushTabChanged(_ data: AIChatTabChangedData) {
        appendToLog(summary: "⇠ aiChatTabChanged  \(data.url ?? "")", detail: prettyPrinted(data))
    }
}

extension BrowserToolsDebugViewController: AIChatElicitationPushing {

    func pushElicitationCreate(_ params: MCPElicitationCreateParams) -> Bool {
        appendToLog(summary: "⇠ elicitation/create  \(params.message)", detail: prettyPrinted(params))
        addPromptRow(for: params)
        return true
    }
}

/// One exchange in the log: a scannable header, and the payload behind a disclosure triangle.
private final class LogEntryView: NSView {

    private let disclosure = NSButton()
    private let detailLabel = NSTextField(wrappingLabelWithString: "")

    init(summary: String, detail: String?, expanded: Bool) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        disclosure.setButtonType(.pushOnPushOff)
        disclosure.bezelStyle = .disclosure
        disclosure.title = ""
        disclosure.state = expanded ? .on : .off
        disclosure.isHidden = detail == nil
        disclosure.target = self
        disclosure.action = #selector(toggle)

        let summaryLabel = NSTextField(labelWithString: summary)
        summaryLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        summaryLabel.lineBreakMode = .byTruncatingTail

        detailLabel.stringValue = detail ?? ""
        detailLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        detailLabel.isSelectable = true
        detailLabel.isHidden = !expanded || detail == nil

        let header = NSStackView(views: [disclosure, summaryLabel])
        header.orientation = .horizontal
        header.spacing = 2
        let column = NSStackView(views: [header, detailLabel])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 2
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor),
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),
            detailLabel.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: 18),
            detailLabel.trailingAnchor.constraint(equalTo: column.trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func toggle() {
        detailLabel.isHidden = disclosure.state != .on
    }
}

private final class LogDocumentView: NSView {
    override var isFlipped: Bool { true }
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
