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

#if DEBUG || REVIEW

import AIChat
import AppKit
import UserScript
import WebKit

/// Debug and Review builds' stand-in for the Duck.ai front end. Drives the same dispatch and
/// handlers a page message would, receives the pushes a page would, and answers permission prompts.
///
/// Shown in place of the chat inside a sidebar; `ownerTabProvider` resolves that sidebar's host tab.
@MainActor
final class BrowserToolsDebugViewController: NSViewController {

    private let userScript: AIChatUserScript
    private let chatHandler: AIChatUserScriptHandler
    private let windowControllersManager: WindowControllersManagerProtocol
    private let service: AIChatBrowserToolsService
    private let ownerTabProvider: () -> Tab?

    private let targetLabel = NSTextField(labelWithString: "")
    private let toolPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let argumentsForm = NSStackView()
    private var argumentFields: [ArgumentField] = []
    private let logStack = NSStackView()
    private let logScroll = NSScrollView()
    private let permissionsStack = NSStackView()
    private var promptEntries: [String: LogEntryView] = [:]

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
        let arguments: [String: Any]
        switch collectArguments() {
        case .success(let collected): arguments = collected
        case .failure(let problem):
            appendToLog(summary: "→ \(problem.message); nothing sent", detail: nil)
            return
        }
        run("tools/call", params: [
            "name": name,
            "callId": "panel-\(Int(Date().timeIntervalSince1970 * 1000))",
            "arguments": arguments
        ])
    }

    @objc private func toolPicked() {
        rebuildArgumentsForm(for: toolPicker.titleOfSelectedItem ?? "")
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
        refreshPermissions()
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
        guard names != toolPicker.itemTitles else {
            if argumentFields.isEmpty, let selected { rebuildArgumentsForm(for: selected) }
            return
        }
        toolPicker.removeAllItems()
        toolPicker.addItems(withTitles: names)
        if let selected, names.contains(selected) {
            toolPicker.selectItem(withTitle: selected)
        } else {
            toolPicker.selectItem(at: 0)
            toolPicked()
        }
    }

    // MARK: - Permissions

    /// Stored Always/Never decisions per tool, editable in place: the same store the debug menu manages.
    private func refreshPermissions() {
        for row in permissionsStack.arrangedSubviews {
            permissionsStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        let header = NSTextField(labelWithString: "Permissions")
        header.font = .systemFont(ofSize: 11, weight: .semibold)
        permissionsStack.addArrangedSubview(header)

        let decisions = service.permissions.storedDecisions
        for tool in service.catalog.enabledTools where tool.permissionMode == .ask {
            let state = decisions[tool.name]
            let label = NSTextField(labelWithString: "\(tool.name): \(state?.rawValue ?? "ask")")
            label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            label.textColor = state == nil ? .secondaryLabelColor : .labelColor
            var views: [NSView] = [label]
            if state != nil {
                let reset = PermissionButton(title: "Reset", target: self, action: #selector(resetPermission(_:)))
                reset.bezelStyle = .rounded
                reset.controlSize = .mini
                reset.toolName = tool.name
                views.append(reset)
            }
            let row = NSStackView(views: views)
            row.orientation = .horizontal
            row.spacing = 6
            permissionsStack.addArrangedSubview(row)
        }
        if !decisions.isEmpty {
            permissionsStack.addArrangedSubview(makeButton("Reset all", #selector(resetAllPermissions)))
        }
    }

    @objc private func resetPermission(_ sender: PermissionButton) {
        service.permissions.setState(.ask, forToolNamed: sender.toolName)
        appendToLog(summary: "· reset permission for \(sender.toolName)", detail: nil)
        refreshPermissions()
    }

    @objc private func resetAllPermissions() {
        service.permissions.clearAll()
        appendToLog(summary: "· reset all permissions", detail: nil)
        refreshPermissions()
    }

    // MARK: - Arguments form

    /// One row per property of the tool's input schema, typed from the schema and prefilled with a
    /// runnable example, so a tester never starts from an empty object.
    private func rebuildArgumentsForm(for tool: String) {
        for row in argumentsForm.arrangedSubviews {
            argumentsForm.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        argumentFields = []
        guard let descriptor = service.catalog.enabledTools.first(where: { $0.name == tool }),
              let properties = descriptor.inputSchema["properties"]?.objectValue else { return }
        let required = Set(descriptor.inputSchema["required"]?.arrayValue?.compactMap(\.stringValue) ?? [])

        for name in properties.keys.sorted(by: { ($0 == "query" || $0 == "quotes") != ($1 == "query" || $1 == "quotes") ? ($0 == "query" || $0 == "quotes") : $0 < $1 }) {
            let schema = properties[name] ?? .null
            let field = ArgumentField(name: name,
                                      type: schema["type"]?.stringValue ?? "string",
                                      itemType: schema["items"]?["type"]?.stringValue,
                                      isRequired: required.contains(name))
            field.setExample(exampleValue(tool: tool, property: name))
            field.control.toolTip = schema["description"]?.stringValue
            argumentFields.append(field)
            argumentsForm.addArrangedSubview(field.row)
            field.row.widthAnchor.constraint(equalTo: argumentsForm.widthAnchor).isActive = true
        }
    }

    private func collectArguments() -> Result<[String: Any], ArgumentProblem> {
        var arguments: [String: Any] = [:]
        for field in argumentFields {
            switch field.value() {
            case .success(let value):
                if let value { arguments[field.name] = value }
            case .failure(let problem):
                return .failure(problem)
            }
        }
        return .success(arguments)
    }

    private func exampleValue(tool: String, property: String) -> String? {
        switch (tool, property) {
        case ("listOpenTabs", "limit"): return "10"
        case ("switchToTab", "tabId"):
            let owner = ownerTabProvider()?.uuid
            return ownerCollection.map { ($0.pinnedTabsCollection?.tabs ?? []) + $0.tabCollection.tabs }?
                .first { $0.uuid != owner }?.uuid
        case ("searchHistory", "query"): return "wiki"
        case ("searchHistory", "limit"): return "5"
        case ("findInPage", "query"): return "games"
        case ("highlightInPage", "quotes"): return "games"
        default: return nil
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

    /// The prompt is a log entry like any other, in sequence, with its answers in the header so it
    /// cannot be missed and the history shows what was chosen.
    private func addPromptEntry(for params: MCPElicitationCreateParams) {
        let buttons = Self.answers.map { answer -> NSView in
            let button = PromptButton(title: answer.title, target: self, action: #selector(answerPrompt(_:)))
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.promptID = params.id
            button.result = answer.result
            return button
        }
        let entry = appendToLog(summary: "⇠ elicitation/create  \(params.message)",
                                detail: prettyPrinted(params),
                                accessories: buttons,
                                highlighted: true)
        promptEntries[params.id] = entry
    }

    /// Goes through `elicitation/response` exactly as the page would, so the answer exercises the
    /// same decode, correlation and persistence.
    @objc private func answerPrompt(_ sender: PromptButton) {
        resolvePromptEntry(id: sender.promptID, outcome: sender.title)
        var result: [String: Any] = ["action": sender.result.action]
        if let choice = sender.result.content?["choice"]?.stringValue {
            result["content"] = ["choice": choice]
        }
        run("elicitation/response", params: ["id": sender.promptID, "result": result])
    }

    private func resolvePromptEntry(id: String, outcome: String) {
        promptEntries.removeValue(forKey: id)?.resolve(outcome: outcome)
    }

    /// Prompts that resolved without us — timed out, or answered from elsewhere.
    private func pruneStalePromptEntries() {
        let pending = Set(service.elicitations.pendingPrompts.map(\.id))
        for id in promptEntries.keys where !pending.contains(id) {
            resolvePromptEntry(id: id, outcome: "expired")
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
            pruneStalePromptEntries()
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

    @discardableResult
    private func appendToLog(summary: String,
                             detail: String?,
                             expanded: Bool = false,
                             accessories: [NSView] = [],
                             highlighted: Bool = false) -> LogEntryView {
        let entry = LogEntryView(summary: summary, detail: detail, expanded: expanded, accessories: accessories,
                                 highlighted: highlighted, tint: Self.tint(for: summary))
        logStack.addArrangedSubview(entry)
        entry.widthAnchor.constraint(equalTo: logStack.widthAnchor).isActive = true
        view.layoutSubtreeIfNeeded()
        logScroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, logStack.frame.height - logScroll.contentSize.height)))
        return entry
    }

    /// Direction at a glance: page→native, native→page reply, native→page push.
    private static func tint(for summary: String) -> NSColor {
        switch summary.first {
        case "→": return .systemBlue
        case "←": return .systemGreen
        case "⇠": return .systemPurple
        default: return .secondaryLabelColor
        }
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
        let call = NSStackView(views: [
            NSTextField(labelWithString: "tools/call"),
            toolPicker,
            makeButton("Call", #selector(callTool))
        ])
        call.orientation = .horizontal
        call.spacing = 6
        toolPicker.widthAnchor.constraint(equalToConstant: 150).isActive = true

        argumentsForm.orientation = .vertical
        argumentsForm.alignment = .leading
        argumentsForm.spacing = 4
        argumentsForm.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)

        permissionsStack.orientation = .vertical
        permissionsStack.alignment = .leading
        permissionsStack.spacing = 3

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

        let stack = NSStackView(views: [targetLabel, buttons, call, argumentsForm, logScroll, permissionsStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        logScroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            logScroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20),
            logScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
            targetLabel.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20),
            argumentsForm.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20)
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
        addPromptEntry(for: params)
        return true
    }
}

/// One exchange in the log: a scannable header, and the payload behind a disclosure triangle.
private final class LogEntryView: NSView {

    private let disclosure = NSButton()
    private let summaryLabel: NSTextField
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let accessories: [NSView]

    private let accessoryRow: NSStackView?

    init(summary: String, detail: String?, expanded: Bool, accessories: [NSView] = [], highlighted: Bool = false, tint: NSColor = .labelColor) {
        self.summaryLabel = NSTextField(labelWithString: summary)
        self.accessories = accessories
        self.accessoryRow = accessories.isEmpty ? nil : NSStackView(views: accessories)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        if highlighted {
            wantsLayer = true
            layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.18).cgColor
            layer?.cornerRadius = 4
        }

        disclosure.setButtonType(.pushOnPushOff)
        disclosure.bezelStyle = .disclosure
        disclosure.title = ""
        disclosure.state = expanded ? .on : .off
        disclosure.isHidden = detail == nil
        disclosure.target = self
        disclosure.action = #selector(toggle)

        summaryLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        summaryLabel.textColor = tint
        summaryLabel.lineBreakMode = .byTruncatingTail
        summaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        detailLabel.stringValue = detail ?? ""
        detailLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        detailLabel.isSelectable = true
        detailLabel.isHidden = !expanded || detail == nil

        let header = NSStackView(views: [disclosure, summaryLabel])
        header.orientation = .horizontal
        header.spacing = 2
        accessoryRow?.orientation = .horizontal
        accessoryRow?.spacing = 4
        accessoryRow?.setClippingResistancePriority(.defaultLow, for: .horizontal)
        let column = NSStackView(views: [header] + (accessoryRow.map { [$0] } ?? []) + [detailLabel])
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
        ] + (accessoryRow.map { [$0.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: 18)] } ?? []))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func toggle() {
        detailLabel.isHidden = disclosure.state != .on
    }

    /// Swaps the answer buttons for the outcome, so the history reads as a transcript.
    func resolve(outcome: String) {
        accessoryRow?.removeFromSuperview()
        summaryLabel.stringValue += "  → \(outcome)"
        layer?.backgroundColor = nil
    }
}

private struct ArgumentProblem: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

/// One schema property as a form row. Empty means "omit"; the value is typed from the schema.
@MainActor
private final class ArgumentField {

    let name: String
    let row: NSStackView
    let control: NSControl
    private let type: String
    private let itemType: String?

    init(name: String, type: String, itemType: String?, isRequired: Bool) {
        self.name = name
        self.type = type
        self.itemType = itemType
        let label = NSTextField(labelWithString: isRequired ? "\(name) *" : name)
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.widthAnchor.constraint(equalToConstant: 110).isActive = true
        if type == "boolean" {
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.addItems(withTitles: ["(omit)", "true", "false"])
            popup.controlSize = .small
            control = popup
        } else {
            let field = NSTextField(string: "")
            field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            field.placeholderString = Self.placeholder(type: type, itemType: itemType)
            control = field
        }
        row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.spacing = 6
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    func setExample(_ value: String?) {
        guard let value, let field = control as? NSTextField else { return }
        field.stringValue = value
    }

    /// `.success(nil)` means the property is left out of the call.
    func value() -> Result<Any?, ArgumentProblem> {
        if let popup = control as? NSPopUpButton {
            switch popup.indexOfSelectedItem {
            case 1: return .success(true)
            case 2: return .success(false)
            default: return .success(nil)
            }
        }
        let text = (control as? NSTextField)?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return .success(nil) }
        switch type {
        case "integer":
            guard let number = Int(text) else { return .failure(ArgumentProblem("\(name) must be an integer")) }
            return .success(number)
        case "number":
            guard let number = Double(text) else { return .failure(ArgumentProblem("\(name) must be a number")) }
            return .success(number)
        case "array":
            if text.hasPrefix("["), let data = text.data(using: .utf8), let parsed = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                return .success(parsed)
            }
            let items = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if itemType == "integer" {
                let numbers = items.compactMap(Int.init)
                guard numbers.count == items.count else { return .failure(ArgumentProblem("\(name) must be integers separated by commas")) }
                return .success(numbers)
            }
            return .success(items)
        default:
            return .success(text)
        }
    }

    private static func placeholder(type: String, itemType: String?) -> String {
        switch type {
        case "integer": return "integer"
        case "number": return "number"
        case "array": return itemType == "integer" ? "0, 1, 2" : "comma separated, or a JSON array"
        default: return "string"
        }
    }
}

private final class LogDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private final class PromptButton: NSButton {
    var promptID = ""
    var result = MCPElicitationResult.cancel
}

private final class PermissionButton: NSButton {
    var toolName = ""
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
