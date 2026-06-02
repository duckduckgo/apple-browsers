//
//  JSBridgePlayground.swift
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

import Foundation
import UIKit
import UserNotifications
import UserScript
import WebKit

/// Describes a feature whose JS bridge can be exercised inside the in-app playground.
///
/// See `JSBridgePlaygroundAddingFeatures.md` for the registration recipe.
protocol JSBridgePlaygroundFeature {

    /// Human-readable name shown in the debug menu (e.g. "Subscription").
    var displayName: String { get }

    /// The `WKScriptMessageHandler` name JS calls via `window.webkit.messageHandlers.<name>`.
    var messageHandlerName: String { get }

    /// The `context` field in the postMessage payload sent to native.
    var messageContext: String { get }

    /// The `featureName` field in the postMessage payload sent to native.
    var featureName: String { get }

    /// Origin used as the `baseURL` for `loadHTMLString`. Must satisfy the subfeature's `messageOriginPolicy`.
    var baseURL: URL { get }

    /// Methods to surface as quick-fill chips on the page. `sampleParamsJSON` is optional pre-filled params.
    var knownMethods: [JSBridgePlaygroundMethod] { get }

    /// Returns user scripts that already have their subfeatures registered. Called once per playground session.
    @MainActor
    func makeUserScripts() -> [UserScript]
}

struct JSBridgePlaygroundMethod {
    let name: String
    let sampleParamsJSON: String?
}

final class JSBridgePlaygroundViewController: UIViewController {

    private let feature: JSBridgePlaygroundFeature
    private var webView: WKWebView!
    private var userScripts: [UserScript] = []

    init(feature: JSBridgePlaygroundFeature) {
        self.feature = feature
        super.init(nibName: nil, bundle: nil)
        title = "JS Bridge: \(feature.displayName)"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupWebView()
        loadPlaygroundPage()
    }

    @MainActor
    private func setupWebView() {
        let contentController = WKUserContentController()
        userScripts = feature.makeUserScripts()
        for userScript in userScripts {
            contentController.addUserScript(userScript.makeWKUserScriptSync())
            contentController.addHandler(userScript)
        }
        contentController.addScriptMessageHandler(self, contentWorld: .page, name: "__playgroundNotifications")
        contentController.addScriptMessageHandler(self, contentWorld: .page, name: "__playgroundSchedulerDiagnostics")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
#if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
#endif

        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @MainActor
    private func loadPlaygroundPage() {
        let html = JSBridgePlaygroundHTML.render(for: feature)
        webView.loadHTMLString(html, baseURL: feature.baseURL)
    }
}

extension JSBridgePlaygroundViewController: WKScriptMessageHandlerWithReply {

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        switch message.name {
        case "__playgroundNotifications":
            Task { @MainActor in
                let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
                let payload = requests.map { request -> [String: Any] in
                    [
                        "identifier": request.identifier,
                        "title": request.content.title,
                        "body": request.content.body,
                        "categoryIdentifier": request.content.categoryIdentifier,
                        "trigger": Self.describe(trigger: request.trigger)
                    ]
                }
                replyHandler(payload, nil)
            }
        case "__playgroundSchedulerDiagnostics":
            Task { @MainActor in
                let featureFlagEnabled = AppDependencyProvider.shared.featureFlagger.isFeatureOn(.subscriptionExpirationReminderNotification)
                let authStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus

                var subscriptionDescription: String
                var subscriptionWarrantsReminder: Bool = false
                do {
                    if let sub = try await AppDependencyProvider.shared.subscriptionManager.getSubscription(forceRefresh: false) {
                        subscriptionDescription = "\(sub.status) (expires \(Self.dateFormatter.string(from: sub.expiresOrRenewsAt)))"
                        switch sub.status {
                        case .autoRenewable, .notAutoRenewable, .gracePeriod:
                            subscriptionWarrantsReminder = true
                        default:
                            subscriptionWarrantsReminder = false
                        }
                    } else {
                        subscriptionDescription = "(no subscription)"
                    }
                } catch {
                    subscriptionDescription = "(error: \(error.localizedDescription))"
                }

                replyHandler([
                    "featureFlagEnabled": featureFlagEnabled,
                    "authorizationStatus": Self.describe(authStatus: authStatus),
                    "subscription": subscriptionDescription,
                    "subscriptionWarrantsReminder": subscriptionWarrantsReminder
                ], nil)
            }
        default:
            replyHandler(nil, "Unknown handler: \(message.name)")
        }
    }

    private static func describe(authStatus: UNAuthorizationStatus) -> String {
        switch authStatus {
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .authorized: return "authorized"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        @unknown default: return "unknown(\(authStatus.rawValue))"
        }
    }

    private static func describe(trigger: UNNotificationTrigger?) -> String {
        switch trigger {
        case let trigger as UNTimeIntervalNotificationTrigger:
            let fires = Date().addingTimeInterval(trigger.timeInterval)
            return "TimeInterval(\(Int(trigger.timeInterval))s -> ~\(Self.dateFormatter.string(from: fires)), repeats: \(trigger.repeats))"
        case let trigger as UNCalendarNotificationTrigger:
            return "Calendar(\(trigger.dateComponents), repeats: \(trigger.repeats))"
        case let trigger?:
            return "\(type(of: trigger))"
        case nil:
            return "(no trigger — delivers immediately)"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f
    }()
}

enum JSBridgePlaygroundHTML {

    static func render(for feature: JSBridgePlaygroundFeature) -> String {
        let chips = feature.knownMethods.map { method -> String in
            let nameHtml = htmlEscape(method.name)
            return #"<span class="method-chip" data-method="\#(nameHtml)">\#(nameHtml)</span>"#
        }.joined()

        let samplesDictEntries = feature.knownMethods.map { method -> String in
            let key = jsStringLiteral(method.name)
            let value = method.sampleParamsJSON.map { jsStringLiteral($0) } ?? "\"\""
            return "\(key): \(value)"
        }.joined(separator: ", ")

        let defaultMethod = feature.knownMethods.first?.name ?? ""
        let defaultParams = feature.knownMethods.first?.sampleParamsJSON ?? "{}"

        return template
            .replacingOccurrences(of: "{{HANDLER}}", with: htmlEscape(feature.messageHandlerName))
            .replacingOccurrences(of: "{{CONTEXT}}", with: htmlEscape(feature.messageContext))
            .replacingOccurrences(of: "{{FEATURE}}", with: htmlEscape(feature.featureName))
            .replacingOccurrences(of: "{{HANDLER_JS}}", with: jsStringLiteral(feature.messageHandlerName))
            .replacingOccurrences(of: "{{CONTEXT_JS}}", with: jsStringLiteral(feature.messageContext))
            .replacingOccurrences(of: "{{FEATURE_JS}}", with: jsStringLiteral(feature.featureName))
            .replacingOccurrences(of: "{{METHOD_CHIPS}}", with: chips)
            .replacingOccurrences(of: "{{METHOD_SAMPLES}}", with: "{\(samplesDictEntries)}")
            .replacingOccurrences(of: "{{DEFAULT_METHOD}}", with: htmlEscape(defaultMethod))
            .replacingOccurrences(of: "{{DEFAULT_PARAMS}}", with: htmlEscape(defaultParams))
    }

    private static func htmlEscape(_ s: String) -> String {
        s
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func jsStringLiteral(_ s: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: s, options: .fragmentsAllowed)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }

    private static let template = #"""
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<style>
:root { color-scheme: light dark; }
body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 12px; font-size: 14px; }
h2 { margin: 12px 0 6px; font-size: 16px; }
label { font-weight: 600; display: block; margin: 10px 0 4px; }
input, textarea { font-family: inherit; font-size: 14px; padding: 8px; border: 1px solid #c8c8c8; border-radius: 6px; width: 100%; box-sizing: border-box; }
textarea { min-height: 100px; font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 12px; }
.row-buttons { display: flex; gap: 8px; margin-top: 10px; }
button { font-family: inherit; font-size: 14px; padding: 10px 14px; border: none; border-radius: 6px; font-weight: 600; cursor: pointer; flex: 1; }
button.primary { background: #de5833; color: #fff; }
button.secondary { background: #ccc; color: #000; }
button:active { opacity: 0.65; }
.methods { display: flex; flex-wrap: wrap; gap: 6px; margin: 4px 0; }
.method-chip { padding: 5px 10px; background: rgba(127,127,127,0.18); border-radius: 14px; font-size: 12px; cursor: pointer; }
.method-chip:active { background: rgba(127,127,127,0.35); }
.meta { color: #888; font-size: 12px; margin-bottom: 4px; line-height: 1.5; }
.meta code { background: rgba(127,127,127,0.18); padding: 1px 4px; border-radius: 3px; }
#log { background: #111; color: #eee; padding: 10px; border-radius: 6px; font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 11px; white-space: pre-wrap; word-break: break-all; min-height: 200px; max-height: 55vh; overflow-y: auto; }
.row-out { color: #7aa2f7; }
.row-in { color: #9ece6a; }
.row-err { color: #f7768e; }
.row-time { color: #888; }
#pending { margin-top: 8px; font-size: 13px; }
.pending-item { padding: 8px; margin-top: 6px; background: rgba(127,127,127,0.1); border-radius: 6px; }
.pending-id { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 11px; color: #888; word-break: break-all; margin-bottom: 2px; }
.pending-meta { color: #888; font-size: 11px; margin-top: 2px; }
.diagnostic-note { background: rgba(127,127,127,0.08); border-left: 3px solid #f7c948; padding: 8px 10px; border-radius: 4px; font-size: 12px; margin-top: 4px; }
.diagnostic-title { font-weight: 600; color: #888; font-size: 11px; margin-bottom: 4px; text-transform: uppercase; letter-spacing: 0.5px; }
.diagnostic-row { display: flex; gap: 8px; padding: 2px 0; font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 11px; }
.diagnostic-pass { color: #5cb85c; min-width: 18px; }
.diagnostic-fail { color: #d9534f; min-width: 18px; }
.diagnostic-label { color: #888; min-width: 110px; }
</style>
</head>
<body>
<h2>JS Bridge Playground</h2>
<div class="meta">
Handler <code>{{HANDLER}}</code> · Context <code>{{CONTEXT}}</code> · Feature <code>{{FEATURE}}</code>
</div>

<label>Quick fill</label>
<div class="methods">{{METHOD_CHIPS}}</div>

<label for="method">Method</label>
<input id="method" type="text" autocapitalize="off" autocorrect="off" spellcheck="false" value="{{DEFAULT_METHOD}}">

<label for="params">Params (JSON)</label>
<textarea id="params" autocapitalize="off" autocorrect="off" spellcheck="false">{{DEFAULT_PARAMS}}</textarea>

<div class="row-buttons">
<button class="primary" onclick="send()">Send</button>
<button class="secondary" onclick="clearLog()">Clear log</button>
</div>

<h2>Response log</h2>
<div id="log"></div>

<h2>Pending notifications <button class="secondary" style="flex:none;padding:4px 10px;font-size:12px;margin-left:6px" onclick="refreshPending()">Refresh</button></h2>
<div class="diagnostic-note">
<div class="diagnostic-title">Scheduler guards (all must pass for a notification to actually be added):</div>
<div id="diagnostics">(tap Refresh)</div>
</div>
<div id="pending">(tap Refresh)</div>

<script>
const HANDLER = {{HANDLER_JS}};
const CONTEXT = {{CONTEXT_JS}};
const FEATURE = {{FEATURE_JS}};
const SAMPLES = {{METHOD_SAMPLES}};

function fillMethod(name) {
    document.getElementById('method').value = name;
    if (SAMPLES[name]) {
        document.getElementById('params').value = SAMPLES[name];
    }
}

document.querySelectorAll('.method-chip').forEach(function(chip) {
    chip.addEventListener('click', function() {
        fillMethod(chip.getAttribute('data-method'));
    });
});

document.getElementById('method').addEventListener('input', function() {
    var name = this.value.trim();
    if (SAMPLES[name]) {
        document.getElementById('params').value = SAMPLES[name];
    }
});

function diagnosticRow(label, value, passing) {
    var row = document.createElement('div');
    row.className = 'diagnostic-row';
    var icon = document.createElement('span');
    icon.className = passing ? 'diagnostic-pass' : 'diagnostic-fail';
    icon.textContent = passing ? '✓' : '✗';
    var lbl = document.createElement('span'); lbl.className = 'diagnostic-label'; lbl.textContent = label;
    var val = document.createElement('span'); val.textContent = value;
    row.appendChild(icon); row.appendChild(lbl); row.appendChild(val);
    return row;
}

async function refreshDiagnostics() {
    var handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.__playgroundSchedulerDiagnostics;
    var el = document.getElementById('diagnostics');
    if (!handler) { el.textContent = '(handler not available)'; return; }
    el.textContent = '(loading...)';
    try {
        var d = await handler.postMessage(null);
        el.innerHTML = '';
        el.appendChild(diagnosticRow('feature flag', String(d.featureFlagEnabled), d.featureFlagEnabled === true));
        el.appendChild(diagnosticRow('auth status', d.authorizationStatus, d.authorizationStatus === 'authorized'));
        el.appendChild(diagnosticRow('subscription', d.subscription, d.subscriptionWarrantsReminder === true));
    } catch (e) {
        el.textContent = 'Error: ' + (e && e.message ? e.message : String(e));
    }
}

async function refreshPending() {
    refreshDiagnostics();
    var handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.__playgroundNotifications;
    var el = document.getElementById('pending');
    if (!handler) { el.textContent = '(handler not available)'; return; }
    el.textContent = '(loading...)';
    try {
        var list = await handler.postMessage(null);
        el.innerHTML = '';
        if (!list || list.length === 0) {
            el.textContent = '(none scheduled)';
            return;
        }
        list.forEach(function(n) {
            var item = document.createElement('div');
            item.className = 'pending-item';
            var id = document.createElement('div'); id.className = 'pending-id'; id.textContent = n.identifier; item.appendChild(id);
            if (n.title) { var t = document.createElement('div'); t.textContent = n.title; t.style.fontWeight = '600'; item.appendChild(t); }
            if (n.body) { var b = document.createElement('div'); b.textContent = n.body; item.appendChild(b); }
            if (n.categoryIdentifier) { var c = document.createElement('div'); c.className = 'pending-meta'; c.textContent = 'category: ' + n.categoryIdentifier; item.appendChild(c); }
            if (n.trigger) { var tr = document.createElement('div'); tr.className = 'pending-meta'; tr.textContent = n.trigger; item.appendChild(tr); }
            el.appendChild(item);
        });
    } catch (e) {
        el.textContent = 'Error: ' + (e && e.message ? e.message : String(e));
    }
}

function clearLog() { document.getElementById('log').textContent = ''; }

function append(text, cls) {
    const log = document.getElementById('log');
    const line = document.createElement('div');
    if (cls) line.className = cls;
    const ts = document.createElement('span');
    ts.className = 'row-time';
    ts.textContent = '[' + new Date().toLocaleTimeString() + '] ';
    line.appendChild(ts);
    line.appendChild(document.createTextNode(text));
    log.appendChild(line);
    log.scrollTop = log.scrollHeight;
}

async function send() {
    const method = document.getElementById('method').value.trim();
    const raw = document.getElementById('params').value.trim();
    if (!method) { append('Method required', 'row-err'); return; }
    let params;
    try { params = raw ? JSON.parse(raw) : {}; }
    catch (e) { append('Params is not valid JSON: ' + e.message, 'row-err'); return; }

    append('-> ' + method + ' ' + JSON.stringify(params), 'row-out');

    const handlerObj = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[HANDLER];
    if (!handlerObj) { append('No JS handler attached: ' + HANDLER, 'row-err'); return; }

    try {
        const response = await handlerObj.postMessage({
            context: CONTEXT,
            featureName: FEATURE,
            method: method,
            params: params,
            id: 'playground-' + Date.now() + '-' + Math.random().toString(36).slice(2, 8)
        });
        if (response === undefined || response === null) {
            append('<- (no value)', 'row-in');
        } else {
            var display = response;
            if (typeof response === 'string') {
                try { display = JSON.parse(response); } catch (_) { /* keep as string */ }
            }
            append('<- ' + JSON.stringify(display, null, 2), 'row-in');
        }
    } catch (e) {
        append('x ' + (e && e.message ? e.message : String(e)), 'row-err');
    }
}
</script>
</body>
</html>
"""#
}
