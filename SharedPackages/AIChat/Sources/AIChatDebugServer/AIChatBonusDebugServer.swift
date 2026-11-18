//
//  AIChatBonusDebugServer.swift
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
import DebugServer
import Foundation
import os

/// A local HTTP server showing the bonus offer state and the messages native and Duck.ai exchange for it.
public final class AIChatBonusDebugServer {
    private let server: DebugHTTPServer
    private let stateProvider: () -> [String: Any]
    private let messageLog: AIChatBonusMessageLog
    private let port: UInt16
    private let logger = Logger(subsystem: "com.duckduckgo", category: "AIChatBonusDebugServer")

    public var isRunning: Bool {
        if case .running = server.state { return true }
        return false
    }

    public var stateDidChange: (@Sendable (ServerState) -> Void)? {
        get { server.stateDidChange }
        set { server.stateDidChange = newValue }
    }

    /// Initialize an instance with the specified parameters.
    /// - Parameters:
    ///   - stateProvider: The bonus offer state as a JSON object, with the Bonus ID masked.
    ///   - messageLog: The messages to show. Recording is on while the server runs.
    ///   - port: The port to listen on. Differs from the storage server's, so both can run.
    public init(
        stateProvider: @escaping () -> [String: Any],
        messageLog: AIChatBonusMessageLog,
        port: UInt16 = 8474
    ) {
        self.server = DebugHTTPServer(port: port)
        self.stateProvider = stateProvider
        self.messageLog = messageLog
        self.port = port
    }

    public func start() throws {
        registerRoutes()
        try server.start()
        messageLog.isEnabled = true
        logger.info("Duck.ai Bonus Debug Server started on port \(self.port)")
    }

    public func stop() {
        server.stop()
        messageLog.isEnabled = false
        logger.info("Duck.ai Bonus Debug Server stopped")
    }

    private func registerRoutes() {
        server.addStaticRoute("/", htmlString: Self.dashboardHTML)

        server.addRoute("/api/state", method: .GET) { [stateProvider] _ in
            .json(try JSONSerialization.data(withJSONObject: stateProvider(), options: .sortedKeys))
        }

        server.addRoute("/api/messages", method: .GET) { [messageLog] _ in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let result: [[String: Any]] = messageLog.recentEntries.map { entry in
                var item: [String: Any] = [
                    "date": formatter.string(from: entry.date),
                    "kind": entry.kind.rawValue,
                    "method": entry.method
                ]
                item["params"] = entry.params
                item["body"] = entry.body
                item["note"] = entry.note
                return item
            }
            return .json(try JSONSerialization.data(withJSONObject: result, options: .sortedKeys))
        }

        server.addRoute("/api/messages", method: .DELETE) { [messageLog] _ in
            messageLog.clear()
            return .json(try JSONSerialization.data(withJSONObject: ["deleted": true], options: .sortedKeys))
        }
    }
}

// MARK: - Dashboard HTML

extension AIChatBonusDebugServer {

    // swiftlint:disable line_length
    static let dashboardHTML = """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Duck.ai Bonus Offer Debug</title>
        <style>
            * { box-sizing: border-box; }
            body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; background: #1a1a2e; color: #e0e0e0; margin: 0; padding: 24px; }
            h1 { color: #de5833; margin: 0 0 16px; font-size: 22px; }
            h2 { color: #de5833; font-size: 15px; margin: 24px 0 8px; }
            .toolbar { display: flex; gap: 8px; align-items: center; margin-bottom: 12px; }
            .toolbar label { color: #aaa; font-size: 13px; margin-left: 8px; }
            button { background: #de5833; color: white; border: none; padding: 8px 16px; border-radius: 6px; cursor: pointer; font-size: 14px; }
            button:hover { background: #c44a2a; }
            button.danger { background: #e74c3c; }
            pre { margin: 0; font-family: 'SF Mono', monospace; font-size: 12px; color: #ccc; white-space: pre-wrap; word-break: break-word; }
            table { width: 100%; border-collapse: collapse; }
            th, td { text-align: left; vertical-align: top; padding: 8px 12px; border-bottom: 1px solid #2a2a4a; font-size: 13px; }
            th { color: #de5833; font-weight: 600; }
            .kind { font-size: 11px; font-weight: 700; text-transform: uppercase; }
            .kind.request { color: #4a9eff; }
            .kind.notification { color: #f0a040; }
            .kind.push { color: #50c878; }
            .method { font-family: 'SF Mono', monospace; }
            .note { color: #ef5350; margin-top: 4px; }
            .empty { color: #666; font-style: italic; padding: 12px; }
            .error { color: #ef5350; }
        </style>
    </head>
    <body>
        <h1>Duck.ai Bonus Offer Debug</h1>
        <div class="toolbar">
            <button onclick="load()">Refresh</button>
            <button class="danger" onclick="clearMessages()">Clear Messages</button>
            <label><input type="checkbox" id="autoRefresh" checked onchange="toggleAutoRefresh()"> Auto-refresh</label>
        </div>

        <h2>State</h2>
        <pre id="state"></pre>

        <h2>Messages <span id="count"></span></h2>
        <div id="messages"></div>

        <script>
            function esc(value) {
                const d = document.createElement('div');
                d.textContent = value || '';
                return d.innerHTML;
            }

            function json(value) {
                return value === undefined ? '' : `<pre>${esc(JSON.stringify(value, null, 2))}</pre>`;
            }

            async function api(path, method = 'GET') {
                const res = await fetch(path, { method });
                if (!res.ok) throw new Error(await res.text());
                return res.json();
            }

            async function load() {
                try {
                    const [state, messages] = await Promise.all([api('/api/state'), api('/api/messages')]);
                    document.getElementById('state').textContent = JSON.stringify(state, null, 2);
                    document.getElementById('count').textContent = `(${messages.length})`;
                    if (messages.length === 0) {
                        document.getElementById('messages').innerHTML = '<div class="empty">No messages yet. Open or reload Duck.ai in the app.</div>';
                        return;
                    }
                    const rows = messages.map(m => `
                        <tr>
                            <td>${esc(new Date(m.date).toLocaleTimeString())}</td>
                            <td><span class="kind ${esc(m.kind)}">${esc(m.kind)}</span><div class="method">${esc(m.method)}</div></td>
                            <td>${json(m.params)}</td>
                            <td>${json(m.body)}${m.note ? `<div class="note">${esc(m.note)}</div>` : ''}</td>
                        </tr>`).join('');
                    document.getElementById('messages').innerHTML =
                        `<table><tr><th>Time</th><th>Message</th><th>Params</th><th>Reply / Payload</th></tr>${rows}</table>`;
                } catch (e) {
                    document.getElementById('messages').innerHTML = `<div class="error">${esc(e.message)}</div>`;
                }
            }

            async function clearMessages() {
                await api('/api/messages', 'DELETE');
                load();
            }

            let timer = null;
            function toggleAutoRefresh() {
                clearInterval(timer);
                timer = document.getElementById('autoRefresh').checked ? setInterval(load, 2000) : null;
            }

            load();
            toggleAutoRefresh();
        </script>
    </body>
    </html>
    """
    // swiftlint:enable line_length
}
