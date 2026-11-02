//
//  BrowserToolsDebugView.swift
//  DuckDuckGo
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

#if DEBUG || ALPHA
import AIChat
import SwiftUI
import UserScript
import WebKit

struct BrowserToolsDebugView: View {
    @StateObject private var model: BrowserToolsDebugModel

    init(tabManager: TabManager) {
        _model = StateObject(wrappedValue: BrowserToolsDebugModel(
            service: tabManager.browserToolsService,
            handler: tabManager.makeBrowserToolsDebugHandler(),
            contextsProvider: { [weak tabManager] in
                guard let tabManager else { return [] }
                return tabManager.allTabsModel.tabs.compactMap { tabManager.makeBrowserToolScope(for: $0) }
            }
        ))
    }

    var body: some View {
        Form {
            Section {
                Text(verbatim: "Native client; JavaScript bridge is not tested.")
                Text(verbatim: "Refresh contexts to select an open tab. Initializing here resets that tab’s shared tools session, including its web clients.")
                    .font(.footnote)
            }
            contextSection
            protocolSection
            toolSection
            elicitationSection
            Section(header: Text(verbatim: "Result")) {
                Text(verbatim: model.result).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
            }
            notificationsSection
            permissionsSection
        }
        .navigationTitle("Browser Tools")
        .onAppear { model.refreshContexts() }
        .onDisappear { model.disconnect() }
        .onChange(of: model.contextID) { _ in model.disconnect() }
        .onChange(of: model.surface) { _ in model.disconnect() }
        .onChange(of: model.toolName) { _ in model.useDefaultArguments() }
    }

    private var contextSection: some View {
        Section(header: Text(verbatim: "Context")) {
            Button("Refresh contexts") { model.refreshContexts() }
            Picker("Owner context", selection: $model.contextID) {
                Text(verbatim: "Select context").tag("")
                ForEach(model.contexts, id: \.ownerTabID) { scope in
                    Text(verbatim: model.contextLabel(scope)).tag(scope.ownerTabID)
                }
            }
            Picker("Surface", selection: $model.surface) {
                Text(verbatim: "Contextual sheet").tag(AIChatBrowserToolsService.Surface.contextual)
                Text(verbatim: "Full Duck.ai tab").tag(AIChatBrowserToolsService.Surface.fullTab)
            }
            Text(verbatim: "Surface changes protocol context only; owner remains selected tab.").font(.footnote)
            Button("Connect new native session") { model.connect() }.disabled(model.contextID.isEmpty)
            Button("Disconnect") { model.disconnect() }.disabled(!model.isConnected)
            Text(verbatim: model.contextStatus).font(.footnote).textSelection(.enabled)
        }
    }

    private var protocolSection: some View {
        Section(header: Text(verbatim: "Protocol")) {
            TextField("Protocol version", text: $model.protocolVersion)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
            Toggle("Declare elicitation.form", isOn: $model.supportsElicitation)
            Toggle("Receive elicitation/create", isOn: $model.receivesElicitation)
            Button("1. initialize") { model.initialize() }.disabled(!model.isConnected)
            Button("2. notifications/initialized") { model.initialized() }.disabled(!model.isConnected)
            Button("3. tools/list") { model.listTools() }.disabled(!model.isConnected)
            Text(verbatim: "Controls stay available out of order to check handshake errors. Unanswered prompts cancel after 120 seconds.")
                .font(.footnote)
        }
    }

    private var toolSection: some View {
        Section(header: Text(verbatim: "Tool")) {
            Text(verbatim: "Catalog: " + model.catalog.joined(separator: ", ")).font(.footnote)
            Picker("Tool name", selection: $model.toolName) {
                ForEach(BrowserToolsDebugModel.toolNames, id: \.self) { Text(verbatim: $0).tag($0) }
            }
            Button("Use default arguments") { model.useDefaultArguments() }
            Text(verbatim: "Arguments (JSON)").font(.footnote)
            TextEditor(text: $model.arguments)
                .font(.system(.footnote, design: .monospaced))
                .frame(minHeight: 100)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
            Button("4. tools/call") { model.callTool() }.disabled(!model.isConnected || model.isCalling)
            if model.isCalling {
                SwiftUI.ProgressView("Waiting for tool result")
                Button("Cancel pending call") { model.cancelCall() }
            }
        }
    }

    private var elicitationSection: some View {
        Section(header: Text(verbatim: "Elicitation")) {
            if let prompt = model.pendingPrompt {
                Text(verbatim: prompt.message)
                Text(verbatim: prompt.id).font(.caption).textSelection(.enabled)
                Button("Allow once") { model.respond(action: .accept, choice: .allowOnce) }
                Button("Always") { model.respond(action: .accept, choice: .alwaysAllow) }
                Button("Never") { model.respond(action: .accept, choice: .neverAllow) }
                Button("Decline") { model.respond(action: .decline) }
                Button("Cancel") { model.respond(action: .cancel) }
            } else {
                Text(verbatim: "No pending prompt")
            }
        }
    }

    private var notificationsSection: some View {
        Section(header: Text(verbatim: "Notifications")) {
            Text(verbatim: "notifications/tools/list_changed: \(model.listChangedCount)")
            Button("Clear notifications") { model.clearNotifications() }
            ForEach(Array(model.notifications.enumerated()), id: \.offset) { _, entry in
                Text(verbatim: entry).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }
        }
    }

    private var permissionsSection: some View {
        Section(header: Text(verbatim: "Permissions")) {
            Text(verbatim: model.permissionSummary).font(.footnote)
            Button("Reset selected tool permission") { model.resetPermission() }.disabled(!model.isConnected)
            Button("Reset all tool permissions") { model.resetAllPermissions() }.disabled(!model.isConnected)
        }
    }
}

@MainActor
private final class BrowserToolsDebugModel: ObservableObject, AIChatBrowserToolsPushing, AIChatElicitationPushing {
    static let toolNames = ["listOpenTabs", "switchToTab", "searchHistory", "readTabContent", "findInPage", "highlightInPage"]

    @Published var contexts: [BrowserToolScope] = []
    @Published var contextID = ""
    @Published var surface = AIChatBrowserToolsService.Surface.contextual
    @Published var protocolVersion = MCPProtocol.version
    @Published var supportsElicitation = true
    @Published var receivesElicitation = true
    @Published var toolName = "listOpenTabs"
    @Published var arguments = "{}"
    @Published var catalog: [String] = []
    @Published var result = "No request sent"
    @Published var contextStatus = "Disconnected"
    @Published var permissionSummary = "Connect to inspect stored decisions"
    @Published var pendingPrompt: MCPElicitationCreateParams?
    @Published var notifications: [String] = []
    @Published var listChangedCount = 0
    @Published var isConnected = false
    @Published var isCalling = false

    private let service: AIChatBrowserToolsService
    private let contextsProvider: () -> [BrowserToolScope]
    private let handler: AIChatUserScriptHandler
    private var scope: BrowserToolScope?

    var browserToolsScope: BrowserToolScope? { scope }
    var browserToolsSurface: AIChatBrowserToolsService.Surface { surface }
    private var callTask: Task<Void, Never>?
    private var callID: UUID?

    init(service: AIChatBrowserToolsService, handler: AIChatUserScriptHandler, contextsProvider: @escaping () -> [BrowserToolScope]) {
        self.service = service
        self.handler = handler
        self.contextsProvider = contextsProvider
    }

    func contextLabel(_ scope: BrowserToolScope) -> String {
        let owner = scope.tabs.first { $0.uid == scope.ownerTabID }
        return owner?.link?.displayTitle ?? scope.ownerTabID
    }

    func refreshContexts() {
        contexts = contextsProvider()
        if !contexts.contains(where: { $0.ownerTabID == contextID }) {
            disconnect()
            contextID = contexts.first?.ownerTabID ?? ""
        }
    }

    func connect() {
        disconnect()
        guard let scope = contextsProvider().first(where: { $0.ownerTabID == contextID }) else { return }
        self.scope = scope
        handler.configureBrowserTools(service: service, source: self)
        service.register(self)
        isConnected = true
        refreshContextStatus()
        refreshPermissions()
    }

    func disconnect() {
        cancelCall()
        service.unregister(self)
        if let scope { service.invalidate(scope: scope) }
        handler.configureBrowserTools(service: nil, source: nil)
        scope = nil
        isConnected = false
        catalog = []
        contextStatus = "Disconnected"
        permissionSummary = "Connect to inspect stored decisions"
    }

    func initialize() {
        guard let scope, isConnected else { return }
        cancelCall()
        let capabilities: [String: Any] = supportsElicitation ? ["elicitation": ["form": [String: Any]()]] : [:]
        let params: [String: Any] = ["protocolVersion": protocolVersion, "capabilities": capabilities,
                                     "clientInfo": ["name": "ios-native-debug"]]
        Task { @MainActor in
            guard self.scope === scope else { return }
            result = encodedResponse(await handler.mcpInitialize(params: params, message: message("initialize", params: params)))
            catalog = []
        }
    }

    func initialized() {
        guard let scope, isConnected else { return }
        Task { @MainActor in
            guard self.scope === scope else { return }
            result = encodedResponse(await handler.mcpNotificationsInitialized(params: [:], message: message("notifications/initialized")))
        }
    }

    func listTools() {
        guard let scope, isConnected else { return }
        Task { @MainActor in
            guard self.scope === scope else { return }
            let response = await handler.mcpToolsList(params: [:], message: message("tools/list"))
            catalog = (response as? BrowserToolsListResponse)?.tools.map(\.name) ?? []
            result = encodedResponse(response)
            refreshPermissions()
        }
    }

    func useDefaultArguments() {
        switch toolName {
        case "switchToTab":
            arguments = encoded(["tabId": scope?.ownerTabID ?? "replace-with-tab-id"])
        case "findInPage": arguments = encoded(["query": "example"])
        case "highlightInPage": arguments = encoded(["quotes": ["example"]])
        default: arguments = "{}"
        }
    }

    func callTool() {
        guard let scope, isConnected, !isCalling else { return }
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: Data(arguments.utf8), options: [.fragmentsAllowed])
        } catch {
            result = "Invalid JSON: \(error.localizedDescription)"
            return
        }
        let id = UUID()
        callID = id
        isCalling = true
        result = "Calling \(toolName)…"
        let params: [String: Any] = ["name": toolName, "callId": id.uuidString, "arguments": parsed]
        callTask = Task { [weak self] in
            guard let self, self.scope === scope, self.callID == id, !Task.isCancelled else { return }
            let response = await self.handler.mcpToolsCall(params: params, message: self.message("tools/call", params: params),
                                                          elicitationPusher: self.receivesElicitation ? self : nil)
            guard self.callID == id else { return }
            self.result = self.encodedResponse(response)
            self.pendingPrompt = nil
            self.isCalling = false
            self.callTask = nil
            self.callID = nil
            self.refreshPermissions()
        }
    }

    func cancelCall() {
        if pendingPrompt != nil { respond(action: .cancel) }
        callTask?.cancel()
        if isCalling { result = "Call cancelled by native debug client" }
        callTask = nil
        callID = nil
        isCalling = false
        pendingPrompt = nil
    }

    func respond(action: MCPElicitationAction, choice: BrowserToolPermissionChoice? = nil) {
        guard let scope, let prompt = pendingPrompt, isConnected else { return }
        var response: [String: Any] = ["action": action.rawValue]
        if let choice { response["content"] = ["choice": choice.rawValue] }
        let params: [String: Any] = ["id": prompt.id, "result": response]
        Task { @MainActor in
            guard self.scope === scope else { return }
            _ = await handler.mcpElicitationResponse(params: params, message: message("elicitation/response", params: params))
        }
        pendingPrompt = nil
    }

    func pushElicitationCreate(_ params: MCPElicitationCreateParams) -> Bool {
        guard isCalling, receivesElicitation else { return false }
        pendingPrompt = params
        return true
    }

    func pushToolsListChanged() {
        refreshContextStatus()
        listChangedCount += 1
        appendNotification("notifications/tools/list_changed")
    }

    func pushTabChanged(_ data: AIChatTabChangedData) {
        appendNotification("aiChatTabChanged\n" + encoded(data))
    }

    func clearNotifications() {
        notifications = []
        listChangedCount = 0
    }

    func resetPermission() {
        service.permissions.setState(.ask, forToolNamed: toolName)
        refreshPermissions()
    }

    func resetAllPermissions() {
        service.permissions.clearAll()
        refreshPermissions()
    }

    private func refreshContextStatus() {
        guard let scope else { return }
        contextStatus = "Owner: \(scope.ownerTabID)\nSurface: \(surface.rawValue)"
            + "\nSupports browser tools: \(service.isAvailable(in: scope))"
    }

    private func refreshPermissions() {
        let permissions = service.permissions
        permissionSummary = Self.toolNames.map { "\($0): \(permissions.state(forToolNamed: $0).rawValue)" }.joined(separator: "\n")
            + "\nStored decisions apply globally. Auto tools execute without prompting."
    }

    private func appendNotification(_ value: String) {
        notifications.append(value)
        if notifications.count > 100 { notifications.removeFirst() }
    }

    private func message(_ method: String, params: Any = [String: Any]()) -> BrowserToolsDebugMessage {
        BrowserToolsDebugMessage(messageName: method, messageBody: params)
    }

    private func encodedResponse(_ response: (any Encodable)?) -> String {
        guard let response else { return "No response" }
        return encoded(response)
    }

    private func encoded(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            return String(data: try encoder.encode(value), encoding: .utf8) ?? "Encoding failed: invalid UTF-8"
        } catch {
            return "Encoding failed: \(error.localizedDescription)"
        }
    }
}
private struct BrowserToolsDebugMessage: UserScriptMessage {
    let messageName: String
    let messageBody: Any
    var messageHost: String { "duck.ai" }
    var isMainFrame: Bool { true }
    var messageWebView: WKWebView? { nil }
}
#endif
