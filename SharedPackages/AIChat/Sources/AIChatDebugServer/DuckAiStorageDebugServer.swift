//
//  DuckAiStorageDebugServer.swift
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
import DuckAiDataStore
import Foundation
import os

/// A local HTTP server exposing Duck.ai native storage for inspection and manipulation.
///
/// Serves a web dashboard plus REST API for chats, files, and settings.
public final class DuckAiStorageDebugServer {

    private let server: DebugHTTPServer
    private let storageHandler: DuckAiNativeStorageHandling
    private let logger = Logger(subsystem: "com.duckduckgo", category: "DuckAiStorageDebugServer")

    public var isRunning: Bool {
        if case .running = server.state { return true }
        return false
    }

    public var stateDidChange: (@Sendable (ServerState) -> Void)? {
        get { server.stateDidChange }
        set { server.stateDidChange = newValue }
    }

    private let port: UInt16

    public init(storageHandler: DuckAiNativeStorageHandling, port: UInt16 = 8473) {
        self.port = port
        self.server = DebugHTTPServer(port: port)
        self.storageHandler = storageHandler
    }

    public func start() throws {
        registerRoutes()
        try server.start()
        logger.info("DuckAi Storage Debug Server started on port \(self.port)")
    }

    public func stop() {
        server.stop()
        logger.info("DuckAi Storage Debug Server stopped")
    }

    // MARK: - Route Registration

    private func registerRoutes() {
        registerDashboardRoute()
        registerChatRoutes()
        registerFileRoutes()
        registerSettingsRoutes()
    }

    // MARK: - Dashboard

    private func registerDashboardRoute() {
        server.addStaticRoute("/", htmlString: Self.dashboardHTML)
    }

    // MARK: - Chat Routes

    private func registerChatRoutes() {
        server.addRoute("/api/chats", method: .GET) { [storageHandler] _ in
            let chats = try storageHandler.getAllChats()
            let result = chats.map { chat in
                [
                    "chatId": chat.chatId,
                    "data": chat.data.base64EncodedString()
                ]
            }
            return .json(try JSONSerialization.data(withJSONObject: result))
        }

        server.addRoute("/api/chats", method: .DELETE) { [storageHandler] _ in
            try storageHandler.deleteAllChats()
            return .json(try JSONSerialization.data(withJSONObject: ["deleted": true]))
        }

        server.addPrefixRoute("/api/chats/", method: .GET) { [storageHandler] request in
            let chatId = String(request.path.dropFirst("/api/chats/".count))
            guard !chatId.isEmpty else {
                return .text("Missing chat ID", status: .badRequest)
            }

            let chats = try storageHandler.getAllChats()
            guard let chat = chats.first(where: { $0.chatId == chatId }) else {
                return .text("Chat not found: \(chatId)", status: .notFound)
            }

            let result: [String: String] = [
                "chatId": chat.chatId,
                "data": chat.data.base64EncodedString()
            ]
            return .json(try JSONSerialization.data(withJSONObject: result))
        }

        server.addPrefixRoute("/api/chats/", method: .DELETE) { [storageHandler] request in
            let chatId = String(request.path.dropFirst("/api/chats/".count))
            guard !chatId.isEmpty else {
                return .text("Missing chat ID", status: .badRequest)
            }

            try storageHandler.deleteChat(chatId: chatId)
            return .json(try JSONSerialization.data(withJSONObject: ["deleted": chatId]))
        }
    }

    // MARK: - File Routes

    private func registerFileRoutes() {
        server.addRoute("/api/files", method: .GET) { [storageHandler] _ in
            let files = try storageHandler.listFiles()
            let result = files.map { file in
                [
                    "uuid": file.uuid,
                    "chatId": file.chatId,
                    "dataSize": "\(file.dataSize)"
                ]
            }
            return .json(try JSONSerialization.data(withJSONObject: result))
        }

        server.addRoute("/api/files", method: .DELETE) { [storageHandler] _ in
            try storageHandler.deleteAllFiles()
            return .json(try JSONSerialization.data(withJSONObject: ["deleted": true]))
        }

        server.addPrefixRoute("/api/files/", method: .GET) { [storageHandler] request in
            let uuid = String(request.path.dropFirst("/api/files/".count))
            guard !uuid.isEmpty else {
                return .text("Missing file UUID", status: .badRequest)
            }

            guard let file = try storageHandler.getFile(uuid: uuid) else {
                return .text("File not found: \(uuid)", status: .notFound)
            }

            let result: [String: String] = [
                "uuid": file.uuid,
                "chatId": file.chatId,
                "data": file.data.base64EncodedString()
            ]
            return .json(try JSONSerialization.data(withJSONObject: result))
        }

        server.addPrefixRoute("/api/files/", method: .DELETE) { [storageHandler] request in
            let uuid = String(request.path.dropFirst("/api/files/".count))
            guard !uuid.isEmpty else {
                return .text("Missing file UUID", status: .badRequest)
            }

            try storageHandler.deleteFile(uuid: uuid)
            return .json(try JSONSerialization.data(withJSONObject: ["deleted": uuid]))
        }
    }

    // MARK: - Settings Routes

    private func registerSettingsRoutes() {
        server.addRoute("/api/settings", method: .GET) { [storageHandler] _ in
            var result: [String: Any] = [:]

            let entries = try storageHandler.getAllEntries()
            result["entries"] = entries

            let migrationKeys = [DuckAiMigrationKey.chats, DuckAiMigrationKey.files]
            var migration: [String: Bool] = [:]
            for key in migrationKeys {
                migration[key] = (try? storageHandler.isMigrationDone(key: key)) ?? false
            }
            result["migration"] = migration

            return .json(try JSONSerialization.data(withJSONObject: result))
        }

        server.addRoute("/api/settings", method: .DELETE) { [storageHandler] _ in
            try storageHandler.deleteAllEntries()
            return .json(try JSONSerialization.data(withJSONObject: ["deleted": true]))
        }
    }
}

// MARK: - Dashboard HTML

extension DuckAiStorageDebugServer {

    // swiftlint:disable line_length function_body_length
    static let dashboardHTML = """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <title>Duck.ai Storage Debug</title>
        <style>
            * { box-sizing: border-box; margin: 0; padding: 0; }
            body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; background: #1a1a2e; color: #e0e0e0; padding: 24px; }
            h1 { color: #de5833; margin-bottom: 16px; }
            .tabs { display: flex; gap: 0; margin-bottom: 20px; border-bottom: 2px solid #2a2a4a; }
            .tab { padding: 10px 24px; cursor: pointer; color: #888; font-weight: 600; font-size: 15px; border-bottom: 2px solid transparent; margin-bottom: -2px; transition: all 0.15s; }
            .tab:hover { color: #ccc; }
            .tab.active { color: #de5833; border-bottom-color: #de5833; }
            .tab .badge { background: #2a2a4a; color: #aaa; padding: 2px 8px; border-radius: 10px; font-size: 12px; margin-left: 6px; }
            .tab-content { display: none; }
            .tab-content.active { display: block; }
            .section { background: #16213e; border-radius: 8px; padding: 16px; margin-bottom: 16px; }
            .toolbar { display: flex; gap: 8px; margin-bottom: 12px; }
            button { background: #de5833; color: white; border: none; padding: 8px 16px; border-radius: 6px; cursor: pointer; font-size: 14px; }
            button:hover { background: #c44a2a; }
            button.danger { background: #e74c3c; }
            button.danger:hover { background: #c0392b; }
            button.small { padding: 4px 10px; font-size: 12px; }
            .empty { color: #666; font-style: italic; padding: 12px; }
            .status { padding: 8px 12px; border-radius: 6px; margin-bottom: 16px; display: none; }
            .status.success { display: block; background: #1e4620; color: #4caf50; }
            .status.error { display: block; background: #4a1c1c; color: #ef5350; }
            table { width: 100%; border-collapse: collapse; }
            th, td { text-align: left; padding: 8px 12px; border-bottom: 1px solid #2a2a4a; font-size: 13px; }
            th { color: #de5833; font-weight: 600; }
            td { font-family: 'SF Mono', monospace; }
            .chat-card { background: #1e2a4a; border-radius: 8px; padding: 16px; margin-bottom: 12px; }
            .chat-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px; }
            .chat-title { font-size: 16px; font-weight: 600; color: #fff; }
            .chat-meta { display: flex; gap: 12px; font-size: 12px; color: #888; margin-bottom: 12px; flex-wrap: wrap; }
            .chat-meta span { background: #2a2a4a; padding: 2px 8px; border-radius: 4px; }
            .chat-meta .pinned { background: #3a2a1a; color: #f0a040; }
            .messages { border-left: 2px solid #2a2a4a; margin-left: 4px; }
            .message { padding: 8px 12px; margin-bottom: 4px; }
            .message .role { font-size: 11px; font-weight: 700; text-transform: uppercase; margin-bottom: 4px; }
            .message .role.user { color: #4a9eff; }
            .message .role.assistant { color: #50c878; }
            .message .content { font-size: 13px; color: #ccc; line-height: 1.5; white-space: pre-wrap; word-break: break-word; }
            .message .time { font-size: 11px; color: #555; margin-top: 4px; }
            .message .model-tag { font-size: 11px; color: #777; background: #222; padding: 1px 6px; border-radius: 3px; margin-left: 8px; }
            .file-refs { font-size: 12px; color: #888; margin-top: 8px; }
            .file-refs code { background: #2a2a4a; padding: 1px 4px; border-radius: 3px; font-size: 11px; }
            .chat-image { max-width: 320px; max-height: 240px; border-radius: 6px; margin-top: 6px; border: 1px solid #333; cursor: pointer; }
            .chat-image:hover { border-color: #de5833; }
            .chat-image-placeholder { display: inline-block; background: #2a2a4a; color: #666; padding: 8px 12px; border-radius: 6px; font-size: 12px; margin-top: 6px; }
            .collapsed .messages { display: none; }
            .toggle-btn { background: none; border: 1px solid #444; color: #aaa; padding: 4px 10px; font-size: 12px; cursor: pointer; border-radius: 4px; }
            .toggle-btn:hover { background: #2a2a4a; color: #fff; }
        </style>
    </head>
    <body>
        <h1>Duck.ai Storage Debug</h1>
        <div id="status" class="status"></div>

        <div class="tabs">
            <div class="tab active" onclick="switchTab('chats')">Chats <span id="chatCount" class="badge">0</span></div>
            <div class="tab" onclick="switchTab('files')">Files <span id="fileCount" class="badge">0</span></div>
            <div class="tab" onclick="switchTab('settings')">Settings</div>
        </div>

        <div id="tab-chats" class="tab-content active">
            <div class="toolbar">
                <button onclick="loadChats()">Refresh</button>
                <button class="danger" onclick="deleteAllChats()">Delete All</button>
            </div>
            <div id="chatsContainer"></div>
        </div>

        <div id="tab-files" class="tab-content">
            <div class="toolbar">
                <button onclick="loadFiles()">Refresh</button>
                <button class="danger" onclick="deleteAllFiles()">Delete All</button>
            </div>
            <div id="filesTable"></div>
        </div>

        <div id="tab-settings" class="tab-content">
            <div class="toolbar">
                <button onclick="loadSettings()">Refresh</button>
                <button class="danger" onclick="deleteAllSettings()">Delete All</button>
            </div>
            <pre id="settingsContent" style="margin-top:8px; font-size:13px; color:#ccc;"></pre>
        </div>

        <script>
            function switchTab(name) {
                document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
                document.querySelectorAll('.tab-content').forEach(t => t.classList.remove('active'));
                document.querySelector(`.tab-content#tab-${name}`).classList.add('active');
                document.querySelectorAll('.tab').forEach(t => {
                    if (t.textContent.toLowerCase().includes(name)) t.classList.add('active');
                });
            }

            function showStatus(msg, isError) {
                const el = document.getElementById('status');
                el.textContent = msg;
                el.className = 'status ' + (isError ? 'error' : 'success');
                setTimeout(() => el.className = 'status', 3000);
            }

            async function api(path, method = 'GET') {
                try {
                    const res = await fetch(path, { method });
                    if (!res.ok) throw new Error(await res.text());
                    return await res.json();
                } catch (e) {
                    showStatus(e.message, true);
                    throw e;
                }
            }

            function parseChat(raw) {
                try {
                    const json = atob(raw.data);
                    return { chatId: raw.chatId, ...JSON.parse(json) };
                } catch {
                    return { chatId: raw.chatId, title: '(unparseable)', messages: [], raw: atob(raw.data) };
                }
            }

            function esc(str) {
                const d = document.createElement('div');
                d.textContent = str || '';
                return d.innerHTML;
            }

            function escJS(str) {
                return (str || '').replace(/\\\\/g, '\\\\\\\\').replace(/'/g, "\\\\'");
            }

            function formatTime(iso) {
                if (!iso) return '';
                try { return new Date(iso).toLocaleString(); } catch { return iso; }
            }

            function renderChat(chat) {
                const pinned = chat.pinned ? '<span class="pinned">pinned</span>' : '';
                const model = chat.model ? `<span>${esc(chat.model)}</span>` : '';
                const lastEdit = chat.lastEdit ? `<span>${formatTime(chat.lastEdit)}</span>` : '';
                const msgCount = `<span>${(chat.messages || []).length} messages</span>`;

                let messagesHtml = '';
                for (const m of (chat.messages || [])) {
                    const role = m.role || 'unknown';
                    const roleClass = role === 'user' ? 'user' : 'assistant';
                    const text = (m.content && typeof m.content === 'object') ? (m.content.text || '') : (m.content || '');
                    const modelTag = m.model ? `<span class="model-tag">${esc(m.model)}</span>` : '';
                    const time = m.createdAt ? `<div class="time">${formatTime(m.createdAt)}</div>` : '';

                    let imagesHtml = '';
                    const msgImages = (m.content && m.content.images) || [];
                    for (const img of msgImages) {
                        const fileId = img.savedData && img.savedData.id;
                        if (fileId) {
                            imagesHtml += `<div class="chat-image-placeholder" data-file-id="${esc(fileId)}">Loading image ${esc(fileId.substring(0, 8))}...</div>`;
                        }
                    }

                    messagesHtml += `<div class="message">
                        <div class="role ${roleClass}">${esc(role)}${modelTag}${msgImages.length > 0 ? ` <span class="model-tag">${msgImages.length} image(s)</span>` : ''}</div>
                        ${imagesHtml}
                        <div class="content">${esc(text)}</div>
                        ${time}
                    </div>`;
                }

                let fileRefsHtml = '';
                if (chat.fileRefs && chat.fileRefs.length) {
                    fileRefsHtml = `<div class="file-refs">Files: ${chat.fileRefs.map(f => `<code>${esc(f)}</code>`).join(' ')}</div>`;
                }

                return `<div class="chat-card" id="chat-${chat.chatId}">
                    <div class="chat-header">
                        <span class="chat-title">${esc(chat.title || chat.chatId)}</span>
                        <span style="display:flex;gap:6px;">
                            <button class="toggle-btn" onclick="toggleChat('${escJS(chat.chatId)}')">Collapse</button>
                            <button class="danger small" onclick="deleteChat('${escJS(chat.chatId)}')">Delete</button>
                        </span>
                    </div>
                    <div class="chat-meta">${pinned}${model}${lastEdit}${msgCount}<span style="color:#555">${esc(chat.chatId)}</span></div>
                    ${fileRefsHtml}
                    <div class="messages">${messagesHtml}</div>
                </div>`;
            }

            function toggleChat(id) {
                const el = document.getElementById('chat-' + id);
                el.classList.toggle('collapsed');
                const btn = el.querySelector('.toggle-btn');
                btn.textContent = el.classList.contains('collapsed') ? 'Expand' : 'Collapse';
            }

            async function loadFileImage(placeholder) {
                const fileId = placeholder.dataset.fileId;
                try {
                    const file = await api('/api/files/' + encodeURIComponent(fileId));
                    const decoded = atob(file.data);
                    let mimeType = 'image/png';
                    let imageB64 = file.data;
                    try {
                        const meta = JSON.parse(decoded);
                        if (meta.data) {
                            imageB64 = meta.data;
                            mimeType = meta.mimeType || mimeType;
                        }
                    } catch { /* not JSON, use raw data as image */ }
                    const img = document.createElement('img');
                    img.className = 'chat-image';
                    img.title = fileId;
                    img.src = `data:${mimeType};base64,${imageB64}`;
                    img.onclick = () => window.open(img.src, '_blank');
                    placeholder.replaceWith(img);
                } catch {
                    placeholder.remove();
                }
            }

            async function loadChats() {
                const raw = await api('/api/chats');
                document.getElementById('chatCount').textContent = raw.length;
                if (!raw.length) {
                    document.getElementById('chatsContainer').innerHTML = '<div class="empty">No chats stored</div>';
                    return;
                }
                const chats = raw.map(parseChat);
                chats.sort((a, b) => (b.lastEdit || '').localeCompare(a.lastEdit || ''));
                document.getElementById('chatsContainer').innerHTML = chats.map(renderChat).join('');
                document.querySelectorAll('.chat-image-placeholder').forEach(loadFileImage);
            }

            async function deleteChat(id) {
                await api('/api/chats/' + encodeURIComponent(id), 'DELETE');
                showStatus('Chat deleted: ' + id);
                loadChats();
            }

            async function deleteAllChats() {
                if (!confirm('Delete ALL chats?')) return;
                await api('/api/chats', 'DELETE');
                showStatus('All chats deleted');
                loadChats();
            }

            async function loadFiles() {
                const files = await api('/api/files');
                document.getElementById('fileCount').textContent = files.length;
                if (!files.length) {
                    document.getElementById('filesTable').innerHTML = '<div class="empty">No files stored</div>';
                    return;
                }
                let html = '<table><tr><th>UUID</th><th>Chat ID</th><th>Size</th><th>Preview</th><th></th></tr>';
                for (const f of files) {
                    html += `<tr>
                        <td>${esc(f.uuid)}</td>
                        <td>${esc(f.chatId)}</td>
                        <td>${f.dataSize} bytes</td>
                        <td><div class="chat-image-placeholder" data-file-id="${esc(f.uuid)}">Loading...</div></td>
                        <td><button class="danger small" onclick="deleteFile('${escJS(f.uuid)}')">Delete</button></td>
                    </tr>`;
                }
                html += '</table>';
                document.getElementById('filesTable').innerHTML = html;
                document.querySelectorAll('#filesTable .chat-image-placeholder').forEach(loadFileImage);
            }

            async function deleteFile(uuid) {
                await api('/api/files/' + encodeURIComponent(uuid), 'DELETE');
                showStatus('File deleted: ' + uuid);
                loadFiles();
            }

            async function deleteAllFiles() {
                if (!confirm('Delete ALL files?')) return;
                await api('/api/files', 'DELETE');
                showStatus('All files deleted');
                loadFiles();
            }

            async function loadSettings() {
                const settings = await api('/api/settings');
                document.getElementById('settingsContent').textContent = JSON.stringify(settings, null, 2);
            }

            async function deleteAllSettings() {
                if (!confirm('Delete ALL settings?')) return;
                await api('/api/settings', 'DELETE');
                showStatus('All settings deleted');
                loadSettings();
            }

            loadChats();
            loadFiles();
            loadSettings();
        </script>
    </body>
    </html>
    """
    // swiftlint:enable line_length function_body_length
}
