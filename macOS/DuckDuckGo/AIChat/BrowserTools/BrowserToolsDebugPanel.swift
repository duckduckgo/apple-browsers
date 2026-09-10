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

/// DEBUG-only panel for exercising the Duck.ai browser tools bridge by hand.
///
/// A web page cannot do this on macOS: the message handlers live in an isolated content world page
/// scripts cannot reach, and content-scope-scripts grants the `aiChat` page-world bridge only to
/// duckduckgo.com / duck.co / duck.ai. So the panel stands in for the front end from inside the
/// app, driving the same dispatch and handlers a page message would.
@MainActor
final class BrowserToolsDebugPanel: NSWindowController {

    private let userScript: AIChatUserScript
    private let chatHandler: AIChatUserScriptHandler
    private let windowControllersManager: WindowControllersManagerProtocol

    private let targetLabel = NSTextField(labelWithString: "")
    private let toolNameField = NSTextField(string: "switchToTab")
    private let argumentsField = NSTextField(string: "{}")
    private let logView = NSTextView()

    init(windowControllersManager: WindowControllersManagerProtocol) {
        self.windowControllersManager = windowControllersManager
        let chatHandler = AIChatUserScriptHandler(
            storage: DefaultAIChatPreferencesStorage(),
            windowControllersManager: windowControllersManager,
            pixelFiring: nil,
            statisticsLoader: nil,
            syncServiceProvider: { nil },
            syncErrorHandler: NSApp.delegateTyped.syncErrorHandler,
            featureFlagger: NSApp.delegateTyped.featureFlagger
        )
        self.chatHandler = chatHandler
        self.userScript = AIChatUserScript(handler: chatHandler, urlSettings: UserDefaults.standard.keyedStoring())

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
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

    /// Sessions are keyed per owner tab, and the owner tab is re-read on every click — so selecting
    /// a different tab between the handshake and a call silently moves you to a tab that has no
    /// session. Showing the state makes that visible instead of surfacing it as `not_initialized`.
    @objc private func refreshTarget() {
        guard let tab = selectedTab else {
            targetLabel.stringValue = "No tab selected — open a tab to act as the Duck.ai owner tab."
            return
        }
        let burner = tab.burnerMode.isBurner ? "  ·  Fire Window" : ""
        let session = NSApp.delegateTyped.aiChatBrowserToolsService.sessions.session(forOwnerTabID: tab.uuid)
        let state = switch session {
        case .none: "no session — run initialize"
        case .some(let session) where !session.isInitialized: "awaiting notifications/initialized"
        case .some: "initialized"
        }
        targetLabel.stringValue = "Owner tab: \(tab.uuid)\(burner)  ·  \(state)"
    }

    // MARK: -

    private func run(_ method: String, params: [String: Any]) {
        refreshTarget()
        guard let webView = selectedTab?.webView else {
            appendToLog("→ no selected tab; cannot resolve an owner tab")
            return
        }

        // Check the method really is wired into the production dispatch switch — the same lookup a
        // page message performs. Its closure takes a concrete `WKScriptMessage`, which only WebKit
        // can create, so the typed handler behind it is invoked directly below.
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
            appendToLog("← \(response.map(prettyPrinted) ?? "(no reply)")\n")
            refreshTarget()
        }
    }

    private func typedHandler(for method: String) -> ((Any, UserScriptMessage) async -> Encodable?)? {
        switch AIChatUserScriptMessages(rawValue: method) {
        case .initialize: chatHandler.mcpInitialize
        case .notificationsInitialized: chatHandler.mcpNotificationsInitialized
        case .toolsList: chatHandler.mcpToolsList
        case .toolsCall: chatHandler.mcpToolsCall
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
        argumentsField.placeholderString = "{\"tabId\": \"…\"}"
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

        logView.isEditable = false
        logView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        let scroll = NSScrollView()
        scroll.documentView = logView
        scroll.hasVerticalScroller = true

        targetLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        targetLabel.lineBreakMode = .byTruncatingMiddle

        let stack = NSStackView(views: [targetLabel, buttons, call, scroll])
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
