//
//  CPMBackgroundReadinessRecovery.swift
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
import WebKit
import os.log

public enum CPMRecoveryFix: String, CaseIterable, Sendable {
    case installReadiness = "install_readiness"
    case upgradeReadiness = "upgrade_readiness"
    case backgroundWake = "background_wake"
    case backgroundLoadRetry = "background_load_retry"
    case lateDocumentReload = "late_document_reload"
}

public enum CPMRecoveryOutcome: String, Sendable {
    /// A slow public WebKit background callback completed successfully; not proof of a page response.
    case backgroundReady = "background_ready"
    case reloadStarted = "reload_started"
    /// An unambiguously attributed dashboard response, not an initResp acknowledgement.
    case responseReceived = "response_received"
}

@available(macOS 15.4, iOS 18.4, *)
protocol CPMRecoveryInstrumentation {
    func record(_ fix: CPMRecoveryFix, outcome: CPMRecoveryOutcome)
}

@available(macOS 15.4, iOS 18.4, *)
struct WebExtensionCPMRecoveryInstrumentation: CPMRecoveryInstrumentation {
    let pixels: WebExtensionPixelFiring

    func record(_ fix: CPMRecoveryFix, outcome: CPMRecoveryOutcome) {
        pixels.fire(.cpmRecovery(fix, outcome: outcome))
    }
}

/// Repairs only a document committed during a known, unfinished background startup. The normal
/// navigation deadline remains unchanged. A missing dashboard response and a successful background
/// callback are both required. Navigation changes, errors and context replacement invalidate work.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMBackgroundReadinessRecovery {
    private struct Startup {
        let identifier: UUID
        let beganAt: Date
        var isReady = false
    }

    private struct Document {
        let identifier = UUID()
        let startup: UUID
        let url: URL
        var failed = false
        var reload: (@MainActor () async -> Bool)?
        var attempted = false
    }

    private let isEnabled: @MainActor () -> Bool
    private let isApplicationInBackground: @MainActor () -> Bool
    private let instrumentation: CPMRecoveryInstrumentation
    private let now: () -> Date
    private var startups: [UUID: Startup] = [:]
    private var activeStartup: UUID?
    private var documents: [String: Document] = [:]
    private var awaitingReloadResponse: [String: URL] = [:]
    private var reloadNavigationStarted: Set<String> = []

    init(isEnabled: @escaping @MainActor () -> Bool,
         isApplicationInBackground: @escaping @MainActor () -> Bool,
         instrumentation: CPMRecoveryInstrumentation,
         now: @escaping () -> Date = Date.init) {
        self.isEnabled = isEnabled
        self.isApplicationInBackground = isApplicationInBackground
        self.instrumentation = instrumentation
        self.now = now
    }

    func backgroundStarted(_ identifier: UUID) {
        startups = startups.filter { now().timeIntervalSince($0.value.beganAt) < 30 }
        activeStartup = identifier
        startups[identifier] = Startup(identifier: identifier, beganAt: now())
    }

    func backgroundCompleted(_ identifier: UUID, succeeded: Bool) {
        guard startups[identifier] != nil else { return }
        if activeStartup == identifier { activeStartup = nil }
        guard succeeded else {
            startups[identifier] = nil
            documents = documents.filter { $0.value.startup != identifier }
            return
        }
        startups[identifier]?.isReady = true
        for tab in Array(documents.keys) { attemptRecovery(in: tab) }
    }

    func navigationStarted(in tab: String) {
        documents[tab] = nil
        if awaitingReloadResponse[tab] != nil, !reloadNavigationStarted.contains(tab) {
            reloadNavigationStarted.insert(tab)
        } else {
            awaitingReloadResponse[tab] = nil
            reloadNavigationStarted.remove(tab)
        }
    }

    func navigationCommitted(in tab: String, url: URL) {
        if awaitingReloadResponse[tab]?.matchesCPMDiagnosticsDocument(url) == false {
            awaitingReloadResponse[tab] = nil
        }
        guard isEnabled(), let identifier = activeStartup, let startup = startups[identifier], !startup.isReady,
              now().timeIntervalSince(startup.beganAt) < 30,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        documents[tab] = Document(startup: startup.identifier, url: url)
        Logger.webExtensions.debug("[CPM Recovery] Armed document during pending background startup")
    }

    func registerDocument(in tab: String, reload: @escaping @MainActor () async -> Bool) {
        Logger.webExtensions.debug("[CPM Recovery] Registering reload; candidate=\(self.documents[tab] != nil)")
        documents[tab]?.reload = reload
    }

    func initializationFailed(in tab: String) {
        Logger.webExtensions.debug("[CPM Recovery] Missing response; candidate=\(self.documents[tab] != nil), enabled=\(self.isEnabled())")
        documents[tab]?.failed = true
        attemptRecovery(in: tab)
    }

    func responseReceived(in tab: String) {
        documents[tab] = nil
        if awaitingReloadResponse.removeValue(forKey: tab) != nil {
            // A late response to the original document during the asynchronous safety check
            // must not be credited to a reload that has not started.
            if reloadNavigationStarted.remove(tab) != nil {
                instrumentation.record(.lateDocumentReload, outcome: .responseReceived)
            }
        }
    }

    func navigationCancelled(in tab: String) {
        documents[tab] = nil
        awaitingReloadResponse[tab] = nil
        reloadNavigationStarted.remove(tab)
    }

    func invalidate() {
        startups.removeAll()
        activeStartup = nil
        documents.removeAll()
        awaitingReloadResponse.removeAll()
        reloadNavigationStarted.removeAll()
    }

    private func attemptRecovery(in tab: String) {
        guard isEnabled(), !isApplicationInBackground(), let document = documents[tab],
              let startup = startups[document.startup], startup.isReady,
              now().timeIntervalSince(startup.beganAt) < 30,
              document.failed, !document.attempted, let reload = document.reload else { return }
        documents[tab]?.attempted = true
        Task { @MainActor [weak self] in
            guard let self, self.isEnabled(), !self.isApplicationInBackground(),
                  self.documents[tab]?.identifier == document.identifier else { return }
            // Install before calling reload: WebKit can synchronously send a navigation callback.
            self.awaitingReloadResponse[tab] = document.url
            if await reload() {
                self.instrumentation.record(.lateDocumentReload, outcome: .reloadStarted)
            } else {
                self.awaitingReloadResponse[tab] = nil
            }
        }
    }
}

@available(macOS 15.4, iOS 18.4, *)
extension CPMBackgroundReadinessRecovery {
    /// Never resubmit a POST or reload a changed/loading document. The boolean script checks for
    /// edits without transferring any field values to native code or telemetry.
    func registerDocument(in tab: String, webView: WKWebView, isGET: Bool) {
        Logger.webExtensions.debug("[CPM Recovery] Document registration GET=\(isGET), historyItem=\(webView.backForwardList.currentItem != nil)")
        guard isGET, let item = webView.backForwardList.currentItem else { return }
        registerDocument(in: tab) { [weak self, weak webView, weak item] in
            Logger.webExtensions.debug("[CPM Recovery] Reload preflight view=\(webView != nil), item=\(item != nil), loading=\(webView?.isLoading == true), sameItem=\(webView?.backForwardList.currentItem === item)")
            guard let self, let webView, let item,
                  !webView.isLoading, webView.backForwardList.currentItem === item else { return false }
            Logger.webExtensions.debug("[CPM Recovery] Checking unchanged GET document")
            let documentID = self.documents[tab]?.identifier
            let pristine = try? await webView.evaluateJavaScript("""
                !document.querySelector('[contenteditable]:not([contenteditable="false"])') &&
                !document.activeElement?.matches('input,textarea,select') &&
                !Array.from(document.querySelectorAll('input,textarea,select')).some(e =>
                    e.tagName === 'SELECT' ? Array.from(e.options).some(o => o.selected !== o.defaultSelected) :
                    (e.type === 'checkbox' || e.type === 'radio') ? e.checked !== e.defaultChecked : e.value !== e.defaultValue)
                """, in: nil, contentWorld: .defaultClient) as? Bool
            Logger.webExtensions.debug("[CPM Recovery] Document pristine=\(pristine == true)")
            guard pristine == true, self.isEnabled(), !self.isApplicationInBackground(),
                  documentID != nil, self.documents[tab]?.identifier == documentID,
                  !webView.isLoading, webView.backForwardList.currentItem === item else { return false }
            return webView.reload() != nil
        }
    }
}
