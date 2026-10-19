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
import StoreKit
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
    private let subscriptionManager: any SubscriptionManager
    var onFinishSetup: (() -> Void)?
    var onShowFeatureInfo: ((SubscriptionOnboardingChecklistItem) -> Void)?
    var onCancelSubscription: (() -> Void)?

    init(context: PreCancellationContext, baseURL: URL, subscriptionManager: any SubscriptionManager) {
        self.context = context
        self.subscriptionManager = subscriptionManager
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
        case "endSubscription": return endSubscription
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

    struct EndSubscriptionResult: Encodable {
        let outcome: String
        let platform: String
        let storeKitWillAutoRenewBefore: Bool?
        let storeKitWillAutoRenewAfter: Bool?
        let backendStatusBefore: String?
        let backendStatusAfter: String?
        let resultCheck: String
        let elapsedMs: Int?
        let expiresOrRenewsAt: String?
    }

    enum ResultCheck {
        case received(DuckDuckGoSubscription?)
        case timedOut
        case cancelled
    }

    @MainActor
    final class PendingResultCheck {
        private var continuation: CheckedContinuation<ResultCheck, Never>?
        var tasks: [Task<Void, Never>] = []

        init(continuation: CheckedContinuation<ResultCheck, Never>) {
            self.continuation = continuation
        }

        func finish(_ result: ResultCheck) {
            guard let continuation else { return }
            self.continuation = nil
            tasks.forEach { $0.cancel() }
            continuation.resume(returning: result)
        }
    }

    private static let resultSafetyTimeoutSeconds: UInt64 = 8

    var onShowStripePortal: (@MainActor (URL) async -> Void)?
    private var pendingResultCheck: PendingResultCheck?

    @MainActor
    func cancelPendingResultCheck() {
        pendingResultCheck?.finish(.cancelled)
    }

    @MainActor
    private func endSubscription(params: Any, original: WKScriptMessage) async -> Encodable? {
        let isApple = context.platform == DuckDuckGoSubscription.Platform.apple.rawValue
        let isStripe = context.platform == DuckDuckGoSubscription.Platform.stripe.rawValue
        guard isApple || isStripe else {
            return EndSubscriptionResult(outcome: "unsupported", platform: context.platform, storeKitWillAutoRenewBefore: nil, storeKitWillAutoRenewAfter: nil,
                                         backendStatusBefore: nil, backendStatusAfter: nil, resultCheck: "notStarted", elapsedMs: nil, expiresOrRenewsAt: nil)
        }

        let storeKitBefore = isApple ? await Self.storeKitWillAutoRenew() : nil
        let backendBefore = try? await subscriptionManager.getSubscription(forceRefresh: true)

        if isApple {
            if let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) {
                try? await AppStore.showManageSubscriptions(in: windowScene)
            }
        } else {
            guard let portalURL = try? await subscriptionManager.getCustomerPortalURL() else {
                return EndSubscriptionResult(outcome: "portalUnavailable", platform: context.platform, storeKitWillAutoRenewBefore: nil, storeKitWillAutoRenewAfter: nil,
                                             backendStatusBefore: backendBefore?.status.rawValue, backendStatusAfter: nil, resultCheck: "notStarted",
                                             elapsedMs: nil, expiresOrRenewsAt: nil)
            }
            await onShowStripePortal?(portalURL)
        }

        let storeKitAfter = isApple ? await Self.storeKitWillAutoRenew() : nil

        let closedAt = Date()
        let resultCheck: ResultCheck = await withCheckedContinuation { continuation in
            let pending = PendingResultCheck(continuation: continuation)
            pendingResultCheck = pending
            pending.tasks = [
                Task { [subscriptionManager] in
                    subscriptionManager.clearSubscriptionCache()
                    let subscription = try? await subscriptionManager.getSubscription(forceRefresh: true)
                    NotificationCenter.default.post(name: .subscriptionDidChange, object: self)
                    pending.finish(.received(subscription))
                },
                Task {
                    try? await Task.sleep(nanoseconds: Self.resultSafetyTimeoutSeconds * 1_000_000_000)
                    pending.finish(.timedOut)
                }
            ]
        }
        let elapsedMs = Int(Date().timeIntervalSince(closedAt) * 1000)
        pendingResultCheck = nil

        let backendAfter: DuckDuckGoSubscription?
        let resultCheckName: String
        switch resultCheck {
        case .received(let subscription):
            backendAfter = subscription
            resultCheckName = "received"
        case .timedOut:
            backendAfter = nil
            resultCheckName = "timedOut"
        case .cancelled:
            backendAfter = nil
            resultCheckName = "cancelled"
        }

        let cancelledByStoreKit = storeKitBefore == true && storeKitAfter == false
        let cancelledByBackend = backendBefore?.status == .autoRenewable && backendAfter?.status == .notAutoRenewable
        let outcome: String
        if cancelledByStoreKit || cancelledByBackend {
            outcome = "cancelled"
        } else if backendAfter == nil {
            outcome = "unknown"
        } else {
            outcome = "unchanged"
        }
        return EndSubscriptionResult(
            outcome: outcome,
            platform: context.platform,
            storeKitWillAutoRenewBefore: storeKitBefore,
            storeKitWillAutoRenewAfter: storeKitAfter,
            backendStatusBefore: backendBefore?.status.rawValue,
            backendStatusAfter: backendAfter?.status.rawValue,
            resultCheck: resultCheckName,
            elapsedMs: elapsedMs,
            expiresOrRenewsAt: (backendAfter ?? backendBefore).map { ISO8601DateFormatter().string(from: $0.expiresOrRenewsAt) }
        )
    }

    private static func storeKitWillAutoRenew() async -> Bool? {
        for await case .verified(let transaction) in StoreKit.Transaction.currentEntitlements where transaction.productType == .autoRenewable {
            guard let groupID = transaction.subscriptionGroupID,
                  let statuses = try? await StoreKit.Product.SubscriptionInfo.status(for: groupID) else { return nil }
            for status in statuses {
                if case .verified(let renewalInfo) = status.renewalInfo {
                    return renewalInfo.willAutoRenew
                }
            }
            return nil
        }
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
    let subscriptionManager: any SubscriptionManager
    let makeStripePortalViewModel: (URL) -> SubscriptionExternalLinkViewModel
    let onAction: (Action) -> Void

    struct StripePortal: Identifiable {
        let id = UUID()
        let viewModel: SubscriptionExternalLinkViewModel
    }

    @Environment(\.dismiss) private var dismiss
    @State private var infoItem: SubscriptionOnboardingChecklistItem?
    @State private var stripePortal: StripePortal?
    @State private var stripePortalDismissal: CheckedContinuation<Void, Never>?

    var body: some View {
        NavigationView {
            PreCancellationWebView(context: context,
                                   baseURL: baseURL,
                                   subscriptionManager: subscriptionManager,
                                   onFinishSetup: { onAction(.finishSetup) },
                                   onShowFeatureInfo: { infoItem = $0 },
                                   onCancelSubscription: { onAction(.cancelSubscription) },
                                   onShowStripePortal: { url in
                                       await withCheckedContinuation { continuation in
                                           stripePortalDismissal = continuation
                                           stripePortal = StripePortal(viewModel: makeStripePortalViewModel(url))
                                       }
                                   })
                .sheet(item: $stripePortal, onDismiss: {
                    stripePortalDismissal?.resume()
                    stripePortalDismissal = nil
                }, content: { portal in
                    SubscriptionExternalLinkView(viewModel: portal.viewModel, title: UserText.subscriptionManagePlan)
                })
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
    let subscriptionManager: any SubscriptionManager
    let onFinishSetup: () -> Void
    let onShowFeatureInfo: (SubscriptionOnboardingChecklistItem) -> Void
    let onCancelSubscription: () -> Void
    let onShowStripePortal: @MainActor (URL) async -> Void

    final class Coordinator {
        let userScript = SubscriptionPagesUserScript()
        var feature: PreCancellationFlowFeature?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let feature = PreCancellationFlowFeature(context: self.context, baseURL: baseURL, subscriptionManager: subscriptionManager)
        feature.onFinishSetup = onFinishSetup
        feature.onShowFeatureInfo = onShowFeatureInfo
        feature.onCancelSubscription = onCancelSubscription
        feature.onShowStripePortal = onShowStripePortal
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

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.feature?.cancelPendingResultCheck()
    }

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
<button onclick="showStep('step3')">Continue</button>
</div>
<div id="step3" class="hidden">
<h3>Step 3: Feedback</h3>
<p id="feedbackState">Feedback: not selected</p>
<button onclick="setFeedback(true)">Feedback</button>
<button onclick="setFeedback(false)">No Feedback</button>
<button onclick="endSubscription().catch(function(e) { document.getElementById('resultSummary').textContent = 'Error: ' + e.message; showStep('step4'); })">End Subscription</button>
<p id="waiting" class="hidden">Waiting for native result...</p>
</div>
<div id="step4" class="hidden">
<h3>Step 4: Result</h3>
<p id="resultSummary"></p>
<p id="resultTiming"></p>
<pre id="resultJSON"></pre>
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

function showStep(id) {
    ['step1', 'step2', 'step3', 'step4'].forEach(function(step) {
        document.getElementById(step).classList.toggle('hidden', step !== id);
    });
}

function showStep2() {
    showStep('step2');
}

let hadFeedback = null;

function setFeedback(value) {
    hadFeedback = value;
    document.getElementById('feedbackState').textContent = 'Feedback: ' + (value ? 'given' : 'not given');
}

async function endSubscription() {
    document.getElementById('waiting').classList.remove('hidden');
    const raw = await send('endSubscription', {}, true);
    const response = typeof raw === 'string' ? JSON.parse(raw) : raw;
    document.getElementById('waiting').classList.add('hidden');
    if (response.error) {
        throw new Error(JSON.stringify(response.error));
    }
    const result = response.result;
    document.getElementById('resultSummary').textContent =
        'Subscription status: ' + result.outcome + ' | Feedback: ' + (hadFeedback === null ? 'not selected' : (hadFeedback ? 'given' : 'not given'));
    document.getElementById('resultTiming').textContent =
        'Result check: ' + result.resultCheck + (result.elapsedMs === null || result.elapsedMs === undefined ? '' : ' in ' + (result.elapsedMs / 1000).toFixed(2) + ' s after store UI closed');
    document.getElementById('resultJSON').textContent = JSON.stringify(result, null, 2);
    showStep('step4');
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
