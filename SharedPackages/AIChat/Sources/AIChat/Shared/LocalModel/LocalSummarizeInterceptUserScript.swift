//
//  LocalSummarizeInterceptUserScript.swift
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

import Foundation
import os.log
import UserScript
import WebKit

/// Prototype only, for internal builds.
///
/// duck.ai has no way yet to ask the browser for a local model, so this script wraps `fetch` on
/// duck.ai pages and answers the "Summarize this page." chat request itself: the page text goes
/// to `LocalPageSummarizer` and the answer streams back in duck.ai's current reply format.
/// Anything else, and any local failure before the first word, goes to the network as usual.
///
/// It depends on duck.ai's private request and stream format, so it is a demo only and must be
/// replaced by a proper duck.ai API before anything ships.
public final class LocalSummarizeInterceptUserScript: NSObject, UserScript {

    static let messageName = "ddgLocalSummarize"

    public var messageNames: [String] { [Self.messageName] }
    public let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    public let forMainFrameOnly = true
    public let requiresRunInPageContentWorld = true

    private var runs: [String: Task<Void, Never>] = [:]

    public override init() {
        super.init()
    }

    static func isDuckAIHost(_ host: String) -> Bool {
        ["duck.ai", "duckduckgo.com"].contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard Self.isDuckAIHost(message.frameInfo.securityOrigin.host),
              let body = message.body as? [String: Any],
              let id = body["id"] as? String,
              let type = body["type"] as? String else {
            return
        }

        switch type {
        case "start":
            let request = LocalPageSummarizerRequest(title: body["title"] as? String ?? "",
                                                     url: body["url"] as? String ?? "",
                                                     content: body["content"] as? String ?? "")
            start(id: id, request: request, webView: message.webView)
        case "cancel":
            runs.removeValue(forKey: id)?.cancel()
        default:
            break
        }
    }

    private func start(id: String, request: LocalPageSummarizerRequest, webView: WKWebView?) {
        Logger.aiChat.debug("[LocalSummarize] start \(id, privacy: .public) chars=\(request.content.count, privacy: .public)")
        runs[id] = Task { @MainActor [weak self, weak webView] in
            do {
                for try await event in LocalPageSummarizer.summarize(request) {
                    switch event {
                    case .delta(let text):
                        Self.send(["id": id, "type": "delta", "text": text], to: webView)
                    case .done(let timings):
                        var payload: [String: Any] = ["id": id,
                                                      "type": "done",
                                                      "totalSeconds": timings.totalSeconds,
                                                      "inputCharacters": timings.inputCharacters,
                                                      "inputWasTrimmed": timings.inputWasTrimmed]
                        payload["firstTokenSeconds"] = timings.firstTokenSeconds
                        Self.send(payload, to: webView)
                    }
                }
            } catch is CancellationError {
            } catch {
                Logger.aiChat.error("[LocalSummarize] failed: \(String(describing: error), privacy: .public)")
                Self.send(["id": id, "type": "error", "reason": String(describing: error)], to: webView)
            }
            self?.runs[id] = nil
        }
    }

    @MainActor
    private static func send(_ event: [String: Any], to webView: WKWebView?) {
        webView?.callAsyncJavaScript("window.__ddgLocalSummarize && window.__ddgLocalSummarize.receive(event)",
                                     arguments: ["event": event],
                                     in: nil,
                                     in: .page,
                                     completionHandler: nil)
    }

    public var source: String {
        """
        const host = location.hostname;
        if (!["duck.ai", "duckduckgo.com"].some((d) => host === d || host.endsWith("." + d))) { return; }

        const messageName = "\(Self.messageName)";
        const firstWordTimeoutMs = 15000;
        const listeners = new Map();
        const log = (...args) => console.info("[DDG local summarize]", ...args);

        window.__ddgLocalSummarize = {
            receive(event) {
                const listener = listeners.get(event.id);
                if (listener) { listener(event); }
            }
        };

        const post = (message) => window.webkit.messageHandlers[messageName].postMessage(message);

        function summarizeRequest(input, init) {
            try {
                const method = ((init && init.method) || (input && input.method) || "GET").toUpperCase();
                const url = new URL(typeof input === "string" ? input : (input && input.url) || "", location.href);
                if (method !== "POST" || !url.pathname.endsWith("/duckchat/v1/chat")) { return null; }
                if (!init || typeof init.body !== "string") { return null; }

                const messages = JSON.parse(init.body).messages || [];
                const last = messages[messages.length - 1];
                if (!last || last.role !== "user" || !Array.isArray(last.content)) { return null; }

                const text = last.content.find((part) => part.type === "text");
                const page = last.content.find((part) => part.type === "page-context");
                if (!text || !/^summarize this page/i.test((text.text || "").trim())) { return null; }
                if (!page || !page.content || !page.content.content) { return null; }

                return { title: page.content.title || "", url: page.content.url || "", content: page.content.content };
            } catch (e) {
                return null;
            }
        }

        const frame = (data) => "data: " + (typeof data === "string" ? data : JSON.stringify(data)) + "\\n\\n";

        function footer(event) {
            const seconds = (value) => (typeof value === "number" ? value.toFixed(1) + " s" : "n/a");
            const trimmed = event.inputWasTrimmed ? ", trimmed to fit" : "";
            return "\\n\\n---\\n*Summarized on this Mac by Apple's on-device model. First word " + seconds(event.firstTokenSeconds) +
                ", total " + seconds(event.totalSeconds) + ", " + event.inputCharacters + " characters of page text" + trimmed + ".*";
        }

        // Resolves with a streaming Response once the first word arrives, or with null so the caller
        // can fall back to the network. Native failures before the first word never reach the user.
        function startLocal(id, request, signal) {
            return new Promise((resolve) => {
                const encoder = new TextEncoder();
                const responseId = "local-" + id;
                let controller = null;
                let settled = false;
                const pending = [];

                const enqueue = (data) => {
                    const chunk = encoder.encode(frame(data));
                    if (controller) { controller.enqueue(chunk); } else { pending.push(chunk); }
                };
                const message = (text) => ({ action: "success", role: "assistant", message: text, id: responseId, model: "apple-on-device", created: Math.floor(Date.now() / 1000) });
                const finish = () => {
                    listeners.delete(id);
                    enqueue("[DONE]");
                    if (controller) { controller.close(); }
                };
                const giveUp = (reason) => {
                    clearTimeout(timer);
                    listeners.delete(id);
                    post({ type: "cancel", id });
                    log("falling back to cloud:", reason);
                    resolve(null);
                };

                const timer = setTimeout(() => { if (!settled) { giveUp("no first word in time"); } }, firstWordTimeoutMs);

                const respond = () => {
                    settled = true;
                    clearTimeout(timer);
                    const body = new ReadableStream({
                        start(c) {
                            controller = c;
                            pending.splice(0).forEach((chunk) => c.enqueue(chunk));
                        },
                        cancel() {
                            listeners.delete(id);
                            post({ type: "cancel", id });
                        }
                    });
                    resolve(new Response(body, { status: 200, headers: { "content-type": "text/event-stream" } }));
                };

                listeners.set(id, (event) => {
                    if (event.type === "delta") {
                        enqueue(message(event.text));
                        if (!settled) { respond(); }
                    } else if (event.type === "done") {
                        if (!settled) { return giveUp("empty answer"); }
                        enqueue(message(footer(event)));
                        log("done", event);
                        finish();
                    } else if (event.type === "error") {
                        if (!settled) { return giveUp(event.reason); }
                        enqueue(message("\\n\\n*The on-device summary stopped early: " + event.reason + "*"));
                        finish();
                    }
                });

                if (signal) {
                    signal.addEventListener("abort", () => {
                        listeners.delete(id);
                        post({ type: "cancel", id });
                        if (!settled) { clearTimeout(timer); resolve(null); }
                        else if (controller) { try { controller.close(); } catch (e) {} }
                    });
                }

                post(Object.assign({ type: "start", id }, request));
            });
        }

        const originalFetch = window.fetch;
        window.fetch = async function (input, init) {
            const request = summarizeRequest(input, init);
            if (!request) { return originalFetch.apply(this, arguments); }

            const id = (crypto.randomUUID && crypto.randomUUID()) || String(Date.now());
            log("summarizing locally", { chars: request.content.length });
            const response = await startLocal(id, request, init && init.signal);
            if (response) { return response; }
            if (init && init.signal && init.signal.aborted) { throw new DOMException("Aborted", "AbortError"); }
            return originalFetch.apply(this, arguments);
        };
        """
    }
}
