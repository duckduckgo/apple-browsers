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

/// Counts first-startup response failures independently of the repair flag. Repairs only a
/// document committed during a known, unfinished background startup. The normal
/// navigation deadline remains unchanged. A missing dashboard response and a successful background
/// callback are both required. Navigation changes, errors and context replacement invalidate work.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMBackgroundReadinessRecovery {
    typealias Reload = @MainActor () -> WKNavigation?
    private struct Startup {
        let identifier: UUID
        let beganAt: Date
        let isFirstLoad: Bool
        var isReady = false
    }

    private struct Document {
        let identifier = UUID()
        let startup: UUID
        let url: URL
        /// Enabling recovery later must not reload a document tracked only for detection.
        let allowsRecovery: Bool
        var failed = false
        var didReportMissingResponse = false
        var prepareReload: (@MainActor () async -> Reload?)?
        var attempted = false
    }

    private struct ReloadResponse {
        let url: URL
        weak var navigation: WKNavigation?
        var hasStarted: Bool
    }

    private let isEnabled: @MainActor () -> Bool
    private let isApplicationInBackground: @MainActor () -> Bool
    private let pixelFiring: WebExtensionPixelFiring
    private let now: () -> Date
    private var startups: [UUID: Startup] = [:]
    private var activeStartup: UUID?
    private var documents: [String: Document] = [:]
    private var awaitingReloadResponse: [String: ReloadResponse] = [:]
    private var startingReload: Set<String> = []
    private var synchronousNavigationMatches: [String: @MainActor (WKNavigation) -> Bool] = [:]

    init(isEnabled: @escaping @MainActor () -> Bool,
         isApplicationInBackground: @escaping @MainActor () -> Bool,
         pixelFiring: WebExtensionPixelFiring,
         now: @escaping () -> Date = Date.init) {
        self.isEnabled = isEnabled
        self.isApplicationInBackground = isApplicationInBackground
        self.pixelFiring = pixelFiring
        self.now = now
    }

    func backgroundStarted(_ identifier: UUID, isFirstLoad: Bool = false) {
        startups = startups.filter { now().timeIntervalSince($0.value.beganAt) < 30 }
        activeStartup = identifier
        startups[identifier] = Startup(identifier: identifier, beganAt: now(), isFirstLoad: isFirstLoad)
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
        for tab in Array(documents.keys) {
            reportStartupResponseMissingIfNeeded(in: tab)
            attemptRecovery(in: tab)
        }
    }

    func navigationStarted(in tab: String) {
        documents[tab] = nil
        if awaitingReloadResponse[tab]?.hasStarted == true {
            awaitingReloadResponse[tab] = nil
        }
    }

    func matchNavigationStarted(in tab: String, matches: @escaping @MainActor (WKNavigation) -> Bool) {
        if let response = awaitingReloadResponse[tab] {
            if let navigation = response.navigation, matches(navigation) {
                awaitingReloadResponse[tab]?.hasStarted = true
            } else {
                awaitingReloadResponse[tab] = nil
            }
        } else if startingReload.contains(tab) {
            // Preserve a delegate callback delivered synchronously inside WKWebView.reload().
            synchronousNavigationMatches[tab] = matches
        }
    }

    func navigationCommitted(in tab: String, url: URL) {
        if awaitingReloadResponse[tab]?.url.matchesCPMDiagnosticsDocument(url) == false {
            awaitingReloadResponse[tab] = nil
        }
        guard let identifier = activeStartup, let startup = startups[identifier], !startup.isReady,
              now().timeIntervalSince(startup.beganAt) < 30,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        documents[tab] = Document(startup: startup.identifier, url: url, allowsRecovery: isEnabled())
        Logger.webExtensions.debug("[CPM Recovery] Armed document during pending background startup")
    }

    func registerDocument(in tab: String, prepareReload: @escaping @MainActor () async -> Reload?) {
        Logger.webExtensions.debug("[CPM Recovery] Registering reload; candidate=\(self.documents[tab] != nil)")
        documents[tab]?.prepareReload = prepareReload
    }

    func initializationFailed(in tab: String) {
        Logger.webExtensions.debug("[CPM Recovery] Missing response; candidate=\(self.documents[tab] != nil), enabled=\(self.isEnabled())")
        documents[tab]?.failed = true
        reportStartupResponseMissingIfNeeded(in: tab)
        attemptRecovery(in: tab)
    }

    func responseReceived(in tab: String) {
        documents[tab] = nil
        if awaitingReloadResponse.removeValue(forKey: tab)?.hasStarted == true {
            pixelFiring.fire(.cpmRecovery(.lateDocumentReload, outcome: .responseReceived))
        }
    }

    func navigationCancelled(in tab: String) {
        documents[tab] = nil
        awaitingReloadResponse[tab] = nil
        synchronousNavigationMatches[tab] = nil
    }

    func invalidate() {
        startups.removeAll()
        activeStartup = nil
        documents.removeAll()
        awaitingReloadResponse.removeAll()
        synchronousNavigationMatches.removeAll()
    }

    private func reportStartupResponseMissingIfNeeded(in tab: String) {
        guard let document = documents[tab], document.failed, !document.didReportMissingResponse,
              let startup = startups[document.startup], startup.isFirstLoad, startup.isReady,
              now().timeIntervalSince(startup.beganAt) < 30 else { return }
        documents[tab]?.didReportMissingResponse = true
        pixelFiring.fire(.cpmStartupResponseMissing)
    }

    private func attemptRecovery(in tab: String) {
        guard isEnabled(), !isApplicationInBackground(), let document = documents[tab],
              document.allowsRecovery,
              let startup = startups[document.startup], startup.isReady,
              now().timeIntervalSince(startup.beganAt) < 30,
              document.failed, !document.attempted, let prepareReload = document.prepareReload else { return }
        documents[tab]?.attempted = true
        Task { @MainActor [weak self] in
            guard let self, self.isEnabled(), !self.isApplicationInBackground(),
                  self.documents[tab]?.identifier == document.identifier else { return }
            guard let reload = await prepareReload(),
                  self.isEnabled(), !self.isApplicationInBackground(),
                  self.documents[tab]?.identifier == document.identifier,
                  self.now().timeIntervalSince(startup.beganAt) < 30 else { return }
            // All asynchronous checks finish before attribution is armed. Only the navigation
            // returned by this accepted reload can supply its response pixel.
            self.startingReload.insert(tab)
            let navigation = reload()
            self.startingReload.remove(tab)
            let synchronousMatch = self.synchronousNavigationMatches.removeValue(forKey: tab)
            if let navigation {
                self.awaitingReloadResponse[tab] = ReloadResponse(url: document.url, navigation: navigation,
                                                                hasStarted: synchronousMatch?(navigation) == true)
                self.pixelFiring.fire(.cpmRecovery(.lateDocumentReload, outcome: .reloadStarted))
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
                  !webView.isLoading, webView.backForwardList.currentItem === item else { return nil }
            Logger.webExtensions.debug("[CPM Recovery] Checking unchanged GET document")
            let documentID = self.documents[tab]?.identifier
            let pristine = try? await webView.evaluateJavaScript("""
                !document.querySelector('iframe,[contenteditable]:not([contenteditable="false"])') &&
                (!document.activeElement || document.activeElement === document.body) &&
                !Array.from(document.querySelectorAll('input,textarea,select')).some(e =>
                    e.tagName === 'SELECT' ? Array.from(e.options).some(o => o.selected !== o.defaultSelected) :
                    (e.type === 'checkbox' || e.type === 'radio') ? e.checked !== e.defaultChecked : e.value !== e.defaultValue)
                """, in: nil, contentWorld: .defaultClient) as? Bool
            Logger.webExtensions.debug("[CPM Recovery] Document pristine=\(pristine == true)")
            guard pristine == true, self.isEnabled(), !self.isApplicationInBackground(),
                  documentID != nil, self.documents[tab]?.identifier == documentID,
                  !webView.isLoading, webView.backForwardList.currentItem === item else { return nil }
            return { [weak webView] in webView?.reload() }
        }
    }
}
