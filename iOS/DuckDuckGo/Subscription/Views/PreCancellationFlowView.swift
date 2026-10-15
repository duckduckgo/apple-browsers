//
//  PreCancellationFlowView.swift
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

import Common
import Foundation
import Subscription
import SwiftUI
import UserScript
import WebKit

struct PreCancellationContext: Encodable {
    struct Feature: Encodable {
        let id: String
        let title: String
        let activated: Bool
    }

    let platform: String
    let isTrial: Bool
    let trialDay: Int?
    let isOnboardingComplete: Bool
    let shouldShowFinishSetup: Bool
    let features: [Feature]

    static func make(subscription: DuckDuckGoSubscription?,
                     completedItems: Set<SubscriptionOnboardingChecklistItem>,
                     checklist: [SubscriptionOnboardingChecklistItem],
                     now: Date = Date()) -> PreCancellationContext {
        let isTrial = subscription?.hasActiveTrialOffer ?? false
        let trialDay: Int? = isTrial ? subscription.map {
            (Calendar.current.dateComponents([.day], from: $0.startedAt, to: now).day ?? 0) + 1
        } : nil
        let isOnboardingComplete = checklist.allSatisfy { completedItems.contains($0) }
        let shouldShowFinishSetup: Bool
        if isTrial {
            shouldShowFinishSetup = !isOnboardingComplete && (trialDay ?? 0) >= 6
        } else {
            shouldShowFinishSetup = !isOnboardingComplete
        }
        return PreCancellationContext(
            platform: subscription?.platform.rawValue ?? "unknown",
            isTrial: isTrial,
            trialDay: trialDay,
            isOnboardingComplete: isOnboardingComplete,
            shouldShowFinishSetup: shouldShowFinishSetup,
            features: checklist.map { Feature(id: $0.rawValue, title: $0.title, activated: completedItems.contains($0)) }
        )
    }
}

struct PreCancellationSheet: Identifiable {
    let id = UUID()
    let context: PreCancellationContext
}

final class PreCancellationFlowFeature: Subfeature {

    struct ShowFeatureInfoParams: Decodable {
        let feature: String
    }

    weak var broker: UserScriptMessageBroker?
    let featureName = "preCancellationFlow"
    let messageOriginPolicy: MessageOriginPolicy

    private let context: PreCancellationContext
    var onFinishSetup: (() -> Void)?
    var onShowFeatureInfo: ((SubscriptionOnboardingChecklistItem) -> Void)?
    var onCancelSubscription: (() -> Void)?

    init(context: PreCancellationContext, baseURL: URL) {
        self.context = context
        self.messageOriginPolicy = .only(rules: [
            HostnameMatchingRule.makeExactRule(for: baseURL) ?? .exact(hostname: "duckduckgo.com")
        ])
    }

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch methodName {
        case "getPreCancellationContext": return getPreCancellationContext
        case "finishSetup": return finishSetup
        case "showFeatureInfo": return showFeatureInfo
        case "cancelSubscription": return cancelSubscription
        default: return nil
        }
    }

    private func getPreCancellationContext(params: Any, original: WKScriptMessage) async -> Encodable? {
        context
    }

    @MainActor
    private func finishSetup(params: Any, original: WKScriptMessage) async -> Encodable? {
        onFinishSetup?()
        return nil
    }

    @MainActor
    private func showFeatureInfo(params: Any, original: WKScriptMessage) async -> Encodable? {
        guard let params: ShowFeatureInfoParams = CodableHelper.decode(from: params),
              let item = SubscriptionOnboardingChecklistItem(rawValue: params.feature) else { return nil }
        onShowFeatureInfo?(item)
        return nil
    }

    @MainActor
    private func cancelSubscription(params: Any, original: WKScriptMessage) async -> Encodable? {
        onCancelSubscription?()
        return nil
    }
}

struct PreCancellationFlowView: View {

    enum Action {
        case finishSetup
        case cancelSubscription
    }

    let context: PreCancellationContext
    let baseURL: URL
    let onAction: (Action) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var infoItem: SubscriptionOnboardingChecklistItem?

    var body: some View {
        NavigationView {
            PreCancellationWebView(context: context,
                                   baseURL: baseURL,
                                   onFinishSetup: { onAction(.finishSetup) },
                                   onShowFeatureInfo: { infoItem = $0 },
                                   onCancelSubscription: { onAction(.cancelSubscription) })
                .navigationTitle("Pre-cancellation POV")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Close") { dismiss() }
                    }
                }
        }
        .subscriptionOnboardingInfoSheet(item: $infoItem)
    }
}

private struct PreCancellationWebView: UIViewRepresentable {

    let context: PreCancellationContext
    let baseURL: URL
    let onFinishSetup: () -> Void
    let onShowFeatureInfo: (SubscriptionOnboardingChecklistItem) -> Void
    let onCancelSubscription: () -> Void

    final class Coordinator {
        let userScript = SubscriptionPagesUserScript()
        var feature: PreCancellationFlowFeature?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let feature = PreCancellationFlowFeature(context: self.context, baseURL: baseURL)
        feature.onFinishSetup = onFinishSetup
        feature.onShowFeatureInfo = onShowFeatureInfo
        feature.onCancelSubscription = onCancelSubscription
        context.coordinator.feature = feature
        context.coordinator.userScript.registerSubfeature(delegate: feature)

        let contentController = WKUserContentController()
        contentController.addUserScript(context.coordinator.userScript.makeWKUserScriptSync())
        contentController.addHandler(context.coordinator.userScript)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
#if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
#endif
        webView.loadHTMLString(Self.html, baseURL: baseURL)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    private static let html = #"""
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
:root { color-scheme: light dark; }
body { font-family: -apple-system, sans-serif; margin: 16px; font-size: 15px; }
pre { background: rgba(127,127,127,0.15); padding: 8px; border-radius: 6px; white-space: pre-wrap; word-break: break-all; font-size: 12px; }
button { display: block; width: 100%; margin: 8px 0; padding: 12px; font-size: 15px; }
.hidden { display: none; }
</style>
</head>
<body>
<div id="step1" class="hidden">
<h3>Step 1: Finish setup?</h3>
<p>Bridge message from native:</p>
<pre id="contextJSON"></pre>
<button onclick="send('finishSetup')">Finish Setup</button>
<button onclick="showStep2()">Continue to Cancel</button>
</div>
<div id="step2" class="hidden">
<h3>Step 2: Features</h3>
<div id="features"></div>
<button onclick="send('cancelSubscription')">Cancel Subscription</button>
</div>
<script>
function send(method, params, expectsResponse) {
    const message = {
        context: 'subscriptionPages',
        featureName: 'preCancellationFlow',
        method: method,
        params: params || {}
    };
    if (expectsResponse) {
        message.id = method + '-' + Date.now();
    }
    return window.webkit.messageHandlers.subscriptionPages.postMessage(message);
}

function showStep2() {
    document.getElementById('step1').classList.add('hidden');
    document.getElementById('step2').classList.remove('hidden');
}

async function load() {
    const raw = await send('getPreCancellationContext', {}, true);
    const response = typeof raw === 'string' ? JSON.parse(raw) : raw;
    if (response.error) {
        throw new Error(JSON.stringify(response.error));
    }
    const ctx = response.result;
    document.getElementById('contextJSON').textContent = JSON.stringify(ctx, null, 2);
    const container = document.getElementById('features');
    ctx.features.forEach(function(f) {
        const button = document.createElement('button');
        button.textContent = f.title + (f.activated ? ' (activated)' : ' (not activated)');
        button.onclick = function() { send('showFeatureInfo', { feature: f.id }); };
        container.appendChild(button);
    });
    if (ctx.shouldShowFinishSetup) {
        document.getElementById('step1').classList.remove('hidden');
    } else {
        showStep2();
    }
}

load().catch(function(e) {
    document.body.insertAdjacentHTML('beforeend', '<pre id="error"></pre>');
    document.getElementById('error').textContent = 'Error: ' + (e && e.message ? e.message : String(e));
});
</script>
</body>
</html>
"""#
}
