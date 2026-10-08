//
//  WebExtensionsInspector.swift
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

#if os(macOS)
import AppKit
import WebKit

/// Serves the internal extensions page, which lists each third-party extension's keyboard shortcuts
/// and lets the user change them.
///
/// The app serves it at `duck://extensions`. The page and its script are inline; its data comes
/// from `/api/` requests on the same URL.
@available(macOS 15.4, *)
@MainActor
public struct WebExtensionsInspector {

    private let manager: WebExtensionManager?

    public init(manager: WebExtensionManager?) {
        self.manager = manager
    }

    public func handle(requestURL: URL, urlSchemeTask: WKURLSchemeTask) {
        switch requestURL.path {
        case "", "/", "/index.html":
            send(Data(Page.html.utf8), mimeType: "text/html", for: requestURL, to: urlSchemeTask)
        case "/api/list":
            send(listResponse(), mimeType: "application/json", for: requestURL, to: urlSchemeTask)
        case "/api/set", "/api/reset":
            let statusCode = update(requestURL) ? 200 : 404
            send(Data("{}".utf8), mimeType: "application/json", statusCode: statusCode, for: requestURL, to: urlSchemeTask)
        default:
            send(Data(), mimeType: "text/plain", statusCode: 404, for: requestURL, to: urlSchemeTask)
        }
    }

    // MARK: - API

    private var contexts: [WKWebExtensionContext] {
        (manager?.loadedExtensions ?? [])
            .filter(\.needsChromeCompatibility)
            .sorted { ($0.webExtension.displayName ?? "") < ($1.webExtension.displayName ?? "") }
    }

    private func listResponse() -> Data {
        let extensions = contexts.map { context in
            ExtensionRow(id: context.uniqueIdentifier,
                         name: context.webExtension.displayName ?? context.uniqueIdentifier,
                         version: context.webExtension.version ?? "",
                         commands: context.commands.map { command in
                CommandRow(id: command.id,
                           title: command.title,
                           key: command.activationKey,
                           modifiers: Self.modifierNames(command.modifierFlags),
                           isCustomized: manager?.commandShortcuts.isCustomized(command, in: context) ?? false)
            })
        }
        return (try? JSONEncoder().encode(extensions)) ?? Data("[]".utf8)
    }

    /// Handles `/api/set?extension=&command=&key=&modifiers=command,shift` and `/api/reset?extension=&command=`.
    /// An empty `key` removes the command's shortcut.
    private func update(_ requestURL: URL) -> Bool {
        let queryItems = URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func queryValue(_ name: String) -> String? { queryItems.first { $0.name == name }?.value }

        guard let store = manager?.commandShortcuts,
              let context = contexts.first(where: { $0.uniqueIdentifier == queryValue("extension") }),
              let command = context.commands.first(where: { $0.id == queryValue("command") }) else {
            return false
        }

        if requestURL.path == "/api/reset" {
            store.resetShortcut(for: command, in: context)
            return true
        }

        let key = queryValue("key").flatMap { $0.isEmpty ? nil : $0.lowercased() }
        let modifiers = (queryValue("modifiers") ?? "").split(separator: ",").reduce(into: NSEvent.ModifierFlags()) { flags, name in
            flags.formUnion(Self.modifierFlags[String(name)] ?? [])
        }
        store.setShortcut(WebExtensionCommandShortcut(activationKey: key, modifierFlags: key == nil ? [] : modifiers),
                          for: command, in: context)
        return true
    }

    private static let modifierFlags: [String: NSEvent.ModifierFlags] = [
        "control": .control, "option": .option, "shift": .shift, "command": .command
    ]

    private static func modifierNames(_ flags: NSEvent.ModifierFlags) -> [String] {
        ["control", "option", "shift", "command"].filter { flags.contains(modifierFlags[$0] ?? []) }
    }

    private struct ExtensionRow: Encodable {
        let id: String
        let name: String
        let version: String
        let commands: [CommandRow]
    }

    private struct CommandRow: Encodable {
        let id: String
        let title: String
        let key: String?
        let modifiers: [String]
        let isCustomized: Bool
    }

    // MARK: - Responses

    private func send(_ data: Data, mimeType: String, statusCode: Int = 200, for url: URL, to task: WKURLSchemeTask) {
        // An HTTP response, so the page's `fetch()` sees `response.ok`.
        let headers = ["Content-Type": mimeType, "Content-Length": String(data.count)]
        guard let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers) else {
            task.didFailWithError(URLError(.badServerResponse))
            return
        }
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    // MARK: - Page

    private enum Page {
        static let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>Extensions</title>
        <style>
        :root { color-scheme: light dark; font: 13px -apple-system, sans-serif; }
        body { max-width: 760px; margin: 32px auto; padding: 0 16px; }
        h1 { font-size: 22px; }
        h2 { font-size: 15px; margin: 28px 0 8px; }
        h2 small { font-weight: normal; opacity: 0.6; }
        table { width: 100%; border-collapse: collapse; }
        td { padding: 8px 4px; border-top: 1px solid rgba(128, 128, 128, 0.25); vertical-align: middle; }
        td.shortcut { width: 200px; }
        td.actions { width: 140px; text-align: right; }
        button.recorder { min-width: 150px; padding: 4px 10px; font: inherit; border-radius: 6px; border: 1px solid rgba(128, 128, 128, 0.5); background: transparent; cursor: pointer; }
        button.recorder.recording { border-color: #3969ef; color: #3969ef; }
        button.link { border: none; background: none; color: #3969ef; cursor: pointer; font: inherit; }
        .empty { opacity: 0.6; }
        .hint { opacity: 0.6; margin-bottom: 16px; }
        </style>
        </head>
        <body>
        <h1>Extensions</h1>
        <div class="hint">Keyboard shortcuts for extension commands. Click a shortcut, then press the new keys. Press Esc to cancel.</div>
        <div id="content"></div>
        <script>
        const symbols = { control: "⌃", option: "⌥", shift: "⇧", command: "⌘" };
        let recording = null;

        function describe(command) {
            if (!command.key) { return "Not set"; }
            return command.modifiers.map(name => symbols[name]).join("") + command.key.toUpperCase();
        }

        async function request(path, parameters) {
            const query = new URLSearchParams(parameters).toString();
            await fetch(path + "?" + query);
            await render();
        }

        async function render() {
            const response = await fetch("/api/list");
            const extensions = await response.json();
            const content = document.getElementById("content");
            content.replaceChildren();
            if (extensions.length === 0) {
                content.innerHTML = '<p class="empty">No third-party extensions are loaded.</p>';
                return;
            }
            for (const extension of extensions) {
                const heading = document.createElement("h2");
                heading.textContent = extension.name + " ";
                const version = document.createElement("small");
                version.textContent = extension.version;
                heading.append(version);
                content.append(heading);

                const table = document.createElement("table");
                if (extension.commands.length === 0) {
                    const row = table.insertRow();
                    const cell = row.insertCell();
                    cell.className = "empty";
                    cell.textContent = "No commands.";
                }
                for (const command of extension.commands) {
                    const row = table.insertRow();
                    row.insertCell().textContent = command.title || command.id;

                    const recorder = document.createElement("button");
                    recorder.className = "recorder";
                    recorder.textContent = describe(command);
                    recorder.onclick = () => startRecording(recorder, extension, command);
                    const shortcutCell = row.insertCell();
                    shortcutCell.className = "shortcut";
                    shortcutCell.append(recorder);

                    const actions = row.insertCell();
                    actions.className = "actions";
                    if (command.key) {
                        actions.append(linkButton("Clear", () => request("/api/set", { extension: extension.id, command: command.id, key: "" })));
                    }
                    if (command.isCustomized) {
                        actions.append(linkButton("Reset", () => request("/api/reset", { extension: extension.id, command: command.id })));
                    }
                }
                content.append(table);
            }
        }

        function linkButton(title, action) {
            const button = document.createElement("button");
            button.className = "link";
            button.textContent = title;
            button.onclick = action;
            return button;
        }

        function startRecording(button, extension, command) {
            if (recording) { recording.button.textContent = recording.title; recording.button.classList.remove("recording"); }
            recording = { button, extension, command, title: button.textContent };
            button.textContent = "Type shortcut…";
            button.classList.add("recording");
        }

        // The key a command uses, from the physical key, so Shift+9 records as 9 rather than (.
        function keyName(event) {
            if (event.code.startsWith("Key")) { return event.code.slice(3).toLowerCase(); }
            if (event.code.startsWith("Digit")) { return event.code.slice(5); }
            return event.key.length === 1 ? event.key.toLowerCase() : null;
        }

        document.addEventListener("keydown", event => {
            if (!recording) { return; }
            event.preventDefault();
            event.stopPropagation();
            if (event.key === "Escape") {
                recording.button.textContent = recording.title;
                recording.button.classList.remove("recording");
                recording = null;
                return;
            }
            if (!(event.metaKey || event.ctrlKey || event.altKey)) { return; }
            const key = keyName(event);
            if (!key) { return; }
            const modifiers = [];
            if (event.ctrlKey) { modifiers.push("control"); }
            if (event.altKey) { modifiers.push("option"); }
            if (event.shiftKey) { modifiers.push("shift"); }
            if (event.metaKey) { modifiers.push("command"); }
            const { extension, command } = recording;
            recording = null;
            request("/api/set", { extension: extension.id, command: command.id, key, modifiers: modifiers.join(",") });
        }, true);

        render();
        </script>
        </body>
        </html>
        """
    }
}
#endif
