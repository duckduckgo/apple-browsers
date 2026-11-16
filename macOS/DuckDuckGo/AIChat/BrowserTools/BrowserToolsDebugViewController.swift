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

/// Debug and Review builds' stand-in for the Duck.ai front end.
/// Reads configuration through the real chat's user script and invokes its native tool handlers.
/// Shows permission prompts in its log and answers them the way the browser's native prompt does.
///
/// Shown in place of the chat inside a sidebar; `ownerTabProvider` resolves that sidebar's host tab.
@MainActor
final class BrowserToolsDebugViewController: NSViewController {

    private let chatContextProvider: () -> (script: AIChatUserScript, webView: WKWebView)?
    private let windowControllersManager: WindowControllersManagerProtocol
    private let service: AIChatBrowserToolsService
    private let ownerTabProvider: () -> Tab?

    enum ConfigurationState {
        case loading
        case loaded(ClientToolsConfiguration?)
        case failed(String)
    }

    private(set) var configurationState: ConfigurationState = .loading
    private var capabilities: [ClientToolCapability] = []
    private var configurationGeneration = UUID()
    private(set) var configurationTask: Task<Void, Never>?
    private(set) var operationTask: Task<Void, Never>?
    private var activeCallID: String?
    private var permissionSource: PermissionSource!

    private let targetLabel = NSTextField(labelWithString: "")
    private let configurationLabel = NSTextField(labelWithString: "Loading config…")
    private let callButton = NSButton(title: "Call", target: nil, action: nil)
    private let toolPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let argumentsForm = NSStackView()
    private var argumentFields: [ArgumentField] = []
    private let logStack = NSStackView()
    private let logScroll = NSScrollView()
    private let permissionsStack = NSStackView()
    private struct PromptEntry {
        let prompt: ClientToolPermissionPrompt
        let view: LogEntryView
    }
    private var promptEntries: [String: PromptEntry] = [:]

    init(windowControllersManager: WindowControllersManagerProtocol,
         service: AIChatBrowserToolsService = NSApp.delegateTyped.aiChatBrowserToolsService,
         chatContextProvider: @escaping () -> (script: AIChatUserScript, webView: WKWebView)?,
         ownerTabProvider: @escaping () -> Tab?) {
        self.windowControllersManager = windowControllersManager
        self.service = service
        self.chatContextProvider = chatContextProvider
        self.ownerTabProvider = ownerTabProvider
        super.init(nibName: nil, bundle: nil)
        permissionSource = PermissionSource(panel: self, coordinator: service.clientToolPermissions)
        service.register(self)
    }

    deinit {
        configurationTask?.cancel()
        operationTask?.cancel()
        let source = permissionSource!
        Task { @MainActor in source.cancelClientToolPermissionRequests() }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = makeContentView()
        refreshTarget()
        refreshConfiguration()
    }

    var canCallTool: Bool { callButton.isEnabled }
    var toolTitles: [String] { toolPicker.itemTitles }

    // MARK: - Actions

    @objc func refreshConfiguration() {
        refreshTarget()
        guard let request = beginConfigurationRequest() else { return }
        configurationTask?.cancel()
        configurationTask = Task { @MainActor [weak self] in
            let response = await request.script.getAIChatNativeConfigValues(params: [:], message: request.message)
            guard !Task.isCancelled else { return }
            _ = self?.acceptConfiguration(response, request: request)
        }
    }

    @objc func callTool() {
        guard case .loaded = configurationState,
              activeCallID == nil, let capability = selectedCapability else { return }
        let arguments: [String: Any]
        switch collectArguments() {
        case .success(let collected): arguments = collected
        case .failure(let problem):
            appendToLog(summary: "→ \(problem.message); nothing sent", detail: nil)
            return
        }
        let callID = "panel-\(UUID().uuidString)"
        activeCallID = callID
        updateCallAvailability()
        guard let request = beginConfigurationRequest() else {
            finishCall(callID)
            return
        }
        let source = permissionSource!
        operationTask = Task { @MainActor [weak self] in
            let response = await request.script.getAIChatNativeConfigValues(params: [:], message: request.message)
            guard !Task.isCancelled,
                  self?.acceptConfiguration(response, request: request) == true,
                  self?.capabilities.contains(capability) == true else {
                self?.finishCall(callID)
                return
            }
            let params: [String: Any] = [
                "callId": callID,
                "capability": ["name": capability.name, "version": capability.version],
                "input": arguments
            ]
            request.script.registerClientToolPermissionCancellation(source)
            self?.appendToLog(summary: "→ executeClientTool", detail: self?.prettyPrinted(params))
            let result = await request.script.handler.executeClientTool(params: params, message: request.message, permissionPrompter: source)
            self?.logResponse(result, method: "executeClientTool")
            self?.finishCall(callID)
        }
    }

    @objc private func toolPicked() {
        rebuildArgumentsForm(for: selectedCapability?.name ?? "")
    }

    private struct ConfigurationRequest {
        let generation: UUID
        let script: AIChatUserScript
        let message: SyntheticUserScriptMessage
        let url: URL?
    }

    private func beginConfigurationRequest() -> ConfigurationRequest? {
        configurationGeneration = UUID()
        configurationState = .loading
        configurationLabel.stringValue = "Loading config…"
        updateCallAvailability()
        guard let context = chatContextProvider(),
              context.script.isClientToolsDocumentReady(context.webView) else {
            failConfiguration("Chat document or user script is not ready")
            return nil
        }
        context.script.registerClientToolPermissionCancellation(permissionSource)
        appendToLog(summary: "→ getAIChatNativeConfigValues", detail: "{}")
        let message = SyntheticUserScriptMessage(name: "getAIChatNativeConfigValues", body: [:], webView: context.webView)
        return ConfigurationRequest(generation: configurationGeneration, script: context.script, message: message, url: context.webView.url)
    }

    @discardableResult
    private func acceptConfiguration(_ response: Encodable?, request: ConfigurationRequest) -> Bool {
        guard request.generation == configurationGeneration else { return false }
        guard let context = chatContextProvider(), context.webView === request.message.webView,
              context.script === request.script,
              context.webView.url == request.url,
              request.script.isClientToolsDocumentReady(context.webView) else {
            failConfiguration("Chat document changed while loading config")
            return false
        }
        logResponse(response, method: "getAIChatNativeConfigValues")
        guard let config = response as? AIChatNativeConfigValues else {
            failConfiguration("Native configuration response is missing or invalid")
            return false
        }
        configurationState = .loaded(config.clientTools)
        capabilities = config.clientTools?.capabilities ?? []
        configurationLabel.stringValue = capabilities.isEmpty
            ? "Config loaded · no tools available" : "Config loaded · \(capabilities.count) \(capabilities.count == 1 ? "tool" : "tools")"
        reloadToolPicker()
        updateCallAvailability()
        return true
    }

    private func failConfiguration(_ reason: String) {
        configurationState = .failed(reason)
        capabilities = []
        configurationLabel.stringValue = "Failed to load config"
        reloadToolPicker()
        updateCallAvailability()
        appendToLog(summary: "· Failed to load config", detail: reason)
    }

    private func updateCallAvailability() {
        if case .loaded = configurationState {
            callButton.isEnabled = activeCallID == nil && selectedCapability != nil
        } else {
            callButton.isEnabled = false
        }
    }

    private func finishCall(_ callID: String) {
        for (id, entry) in promptEntries where entry.prompt.callID == callID {
            resolvePromptEntry(id: id, outcome: "settled")
        }
        guard activeCallID == callID else { return }
        activeCallID = nil
        operationTask = nil
        refreshPermissions()
        updateCallAvailability()
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
        let pendingViews = Set(promptEntries.values.map { ObjectIdentifier($0.view) })
        for row in logStack.arrangedSubviews where !pendingViews.contains(ObjectIdentifier(row)) {
            logStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
    }

    @objc func refreshTarget() {
        refreshPermissions()
        guard let tab = ownerTabProvider() else {
            targetLabel.stringValue = "No owner tab — open a tab to act as the Duck.ai owner tab."
            return
        }
        let burner = tab.burnerMode.isBurner ? "  ·  Fire Window" : ""
        let title = tab.title.map { " (\($0.prefix(40)))" } ?? ""
        targetLabel.stringValue = "Owner tab: \(tab.uuid)\(title)\(burner)"
    }

    // MARK: - Tool picker

    private var selectedCapability: ClientToolCapability? {
        guard capabilities.indices.contains(toolPicker.indexOfSelectedItem) else { return nil }
        return capabilities[toolPicker.indexOfSelectedItem]
    }

    private func reloadToolPicker() {
        let titles = capabilities.map { "\($0.name) · v\($0.version)" }
        let selectedName = toolPicker.titleOfSelectedItem?.components(separatedBy: " · v").first
        guard titles != toolPicker.itemTitles else { return }
        toolPicker.removeAllItems()
        toolPicker.addItems(withTitles: titles)
        guard !capabilities.isEmpty else {
            rebuildArgumentsForm(for: "")
            return
        }
        if let index = capabilities.firstIndex(where: { $0.name == selectedName }) {
            toolPicker.selectItem(at: index)
        } else {
            toolPicker.selectItem(at: 0)
            toolPicked()
        }
    }

    // MARK: - Permissions

    /// Stored Always/Never decisions per tool, editable in place: the same store Duck.ai pages write to.
    private func refreshPermissions() {
        for row in permissionsStack.arrangedSubviews {
            permissionsStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        let header = NSTextField(labelWithString: "Permissions")
        header.font = .systemFont(ofSize: 11, weight: .semibold)
        permissionsStack.addArrangedSubview(header)

        let decisions = service.permissions.storedDecisions
        let askTools = service.catalog.enabledTools.filter { $0.permissionMode == .ask }.map(\.name)
        // A decision outlives its tool's flag, so it stays listed and resettable on its own.
        let orphanedTools = decisions.keys.filter { !askTools.contains($0) }.sorted()
        for toolName in askTools + orphanedTools {
            let state = decisions[toolName]
            let label = NSTextField(labelWithString: "\(toolName): \(state?.rawValue ?? "ask")")
            label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            label.textColor = state == nil ? .secondaryLabelColor : .labelColor
            var views: [NSView] = [label]
            if state != nil {
                let reset = PermissionButton(title: "Reset", target: self, action: #selector(resetPermission(_:)))
                reset.bezelStyle = .rounded
                reset.controlSize = .mini
                reset.toolName = toolName
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

    /// Stands in for the browser's native prompt: the panel answers it directly, as the browser does.
    private func addPromptEntry(for prompt: ClientToolPermissionPrompt) -> Bool {
        guard prompt.callID == activeCallID else { return false }
        let answers: [(String, ClientToolPermissionDecision)] = [("Allow once", .allowOnce), ("Always", .always), ("Never", .never), ("Dismiss", .dismiss)]
        let buttons = answers.map { title, decision -> NSView in
            let button = PromptButton(title: title, target: self, action: #selector(answerPrompt(_:)))
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.requestID = prompt.requestID
            button.decision = decision
            return button
        }
        let reason = service.catalog.enabledTools.first { $0.name == prompt.toolName }?.permissionReason ?? prompt.toolName
        let entry = appendToLog(summary: "⇠ permission prompt  \(reason)",
                                detail: "{\"requestID\": \"\(prompt.requestID)\", \"callID\": \"\(prompt.callID)\", \"tool\": \"\(prompt.toolName)\"}",
                                accessories: buttons, highlighted: true)
        promptEntries[prompt.requestID] = PromptEntry(prompt: prompt, view: entry)
        return true
    }

    @objc private func answerPrompt(_ sender: PromptButton) {
        guard let entry = promptEntries[sender.requestID] else { return }
        resolvePromptEntry(id: sender.requestID, outcome: sender.title)
        appendToLog(summary: "→ \(sender.title)", detail: nil)
        service.clientToolPermissions.respond(to: entry.prompt, decision: sender.decision, from: permissionSource)
    }

    private func resolvePromptEntry(id: String, outcome: String) {
        promptEntries.removeValue(forKey: id)?.view.resolve(outcome: outcome)
    }

    private func logResponse(_ response: Encodable?, method: String) {
        guard let response, let json = Self.jsonObject(response) else {
            appendToLog(summary: "← \(method)  invalid response", detail: nil)
            return
        }
        appendToLog(summary: "← \(method)  \(Self.summary(of: json))", detail: prettyPrinted(json))
    }

    private final class PermissionSource: ClientToolPermissionPrompting, AIChatClientToolPermissionCancellation {
        private weak var panel: BrowserToolsDebugViewController?
        private let coordinator: ClientToolPermissionCoordinator

        init(panel: BrowserToolsDebugViewController, coordinator: ClientToolPermissionCoordinator) {
            self.panel = panel
            self.coordinator = coordinator
        }

        func presentClientToolPermissionPrompt(_ prompt: ClientToolPermissionPrompt) -> Bool {
            panel?.addPromptEntry(for: prompt) ?? false
        }

        func withdrawClientToolPermissionPrompt(requestID: String) {
            panel?.resolvePromptEntry(id: requestID, outcome: "withdrawn")
        }

        func cancelClientToolPermissionRequests() {
            coordinator.cancelRequests(from: self)
            panel?.configurationGeneration = UUID()
            panel?.configurationTask?.cancel()
            panel?.operationTask?.cancel()
            panel?.failConfiguration("Chat document is no longer available")
            if let callID = panel?.activeCallID { panel?.finishCall(callID) }
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

    private static func summary(of json: Any) -> String {
        guard let dictionary = json as? [String: Any] else { return "" }
        if let code = (dictionary["error"] as? [String: Any])?["code"] as? String { return code }
        if let ok = dictionary["ok"] as? Bool { return "\(dictionary["callId"] as? String ?? "") · ok=\(ok)" }
        return dictionary.isEmpty ? "{}" : "ok"
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
            makeButton("Show tab IDs", #selector(listWindowTabs)),
            makeButton("Refresh", #selector(refreshConfiguration)),
            makeButton("Clear log", #selector(clearLog))
        ])
        buttons.orientation = .horizontal
        buttons.spacing = 6
        buttons.setClippingResistancePriority(.defaultLow, for: .horizontal)

        toolPicker.target = self
        toolPicker.action = #selector(toolPicked)
        toolPicker.controlSize = .small
        callButton.target = self
        callButton.action = #selector(callTool)
        callButton.bezelStyle = .rounded
        callButton.controlSize = .small
        callButton.isEnabled = false
        let call = NSStackView(views: [toolPicker, callButton])
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
        configurationLabel.lineBreakMode = .byTruncatingTail

        let stack = NSStackView(views: [targetLabel, configurationLabel, buttons, call, argumentsForm, logScroll, permissionsStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        logScroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            logScroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20),
            logScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
            targetLabel.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20),
            configurationLabel.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20),
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

    var pushTargetWebView: WKWebView? { chatContextProvider()?.webView }

    func pushClientToolsChanged(_ data: ClientToolsChangedData) {
        guard isViewLoaded else { return }
        configurationState = .loaded(data.clientTools)
        capabilities = data.clientTools?.capabilities ?? []
        configurationLabel.stringValue = capabilities.isEmpty
            ? "Config changed · no tools available" : "Config changed · \(capabilities.count) \(capabilities.count == 1 ? "tool" : "tools")"
        reloadToolPicker()
        updateCallAvailability()
        appendToLog(summary: "⇠ clientToolsChanged", detail: prettyPrinted(data))
    }

    func pushTabChanged(_ data: AIChatTabChangedData) {
        appendToLog(summary: "⇠ aiChatTabChanged  \(data.url ?? "")", detail: prettyPrinted(data))
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
    var requestID = ""
    var decision = ClientToolPermissionDecision.dismiss
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
    var messageHost: String { webView.url?.host ?? "" }
    var isMainFrame: Bool { true }
    var messageWebView: WKWebView? { webView }
}

#endif
