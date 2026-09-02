//
//  DebugControlRecorder.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import Combine
import Foundation
import Navigation
import WebKit
import os.log

/// Collects console output and every request the browser is able to report, per tab.
@MainActor
final class DebugControlRecorder: NSObject {

    @MainActor
    private final class TabRecord {
        let console = DebugControlEventLog(limit: 5000)
        let network = DebugControlEventLog(limit: 20000)
        var cancellables = Set<AnyCancellable>()
        var observedContentControllers = Set<ObjectIdentifier>()
    }

    /// Tabs report into the recorder from `Tab.init`, but nothing is observed until the server starts.
    var isEnabled = false

    private var records: [String: TabRecord] = [:]
    private var tabIdentifiersByWebView: [ObjectIdentifier: String] = [:]

    // MARK: - Attaching

    func makeNavigationResponder(for tab: Tab) -> DebugControlNavigationResponder {
        DebugControlNavigationResponder(tab: tab, recorder: self)
    }

    /// Installs the page observer script and the tracker subscription for a tab. Safe to call repeatedly.
    func ensureAttached(to tab: Tab) {
        guard isEnabled else { return }

        let record = records[tab.uuid] ?? {
            let record = TabRecord()
            records[tab.uuid] = record
            return record
        }()

        tabIdentifiersByWebView[ObjectIdentifier(tab.webView)] = tab.uuid

        if record.cancellables.isEmpty {
            tab.trackersPublisher
                .sink { [weak self] detected in
                    self?.record(detected, for: tab.uuid)
                }
                .store(in: &record.cancellables)
        }

        let controller = tab.webView.configuration.userContentController
        let controllerID = ObjectIdentifier(controller)
        guard !record.observedContentControllers.contains(controllerID) else { return }
        record.observedContentControllers.insert(controllerID)

        // The isolated world used by content-scope-scripts, so the observer sees the same page as the DDG scripts do.
        let world = WKContentWorld.defaultClient
        controller.add(self, contentWorld: world, name: DebugControlPageObserverScript.messageName)
        controller.addUserScript(WKUserScript(source: DebugControlPageObserverScript.source,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: false,
                                              in: world))
    }

    func ensureAttachedToAllTabs(_ tabs: [Tab]) {
        tabs.forEach(ensureAttached(to:))
    }

    // MARK: - Reading

    func consoleEntries(forTab uuid: String, since: Double?) -> [[String: Any]] {
        records[uuid]?.console.snapshot(since: since) ?? []
    }

    func networkEntries(forTab uuid: String, since: Double?) -> [[String: Any]] {
        records[uuid]?.network.snapshot(since: since) ?? []
    }

    func clearConsole(forTab uuid: String) {
        records[uuid]?.console.clear()
    }

    func clearNetwork(forTab uuid: String) {
        records[uuid]?.network.clear()
    }

    // MARK: - Writing

    fileprivate func recordNetwork(_ fields: [String: Any], forTab uuid: String) {
        records[uuid]?.network.record(fields)
    }

    private func record(_ detected: DetectedTracker, for uuid: String) {
        let request = detected.request
        let resourceType: String
        switch detected.type {
        case .tracker: resourceType = "tracker"
        case .trackerWithSurrogate(let host): resourceType = "tracker-surrogate:\(host)"
        case .thirdPartyRequest: resourceType = "third-party"
        }

        var blockReason = "detected"
        if case .allowed(let reason) = request.state {
            blockReason = reason.rawValue
        }

        recordNetwork([
            "url": request.url,
            "method": NSNull(),
            "status": -1,
            "initiator": "content-scope-scripts",
            "resourceType": resourceType,
            "redirectedFrom": NSNull(),
            "blocked": request.isBlocked,
            "reason": blockReason,
            "entity": request.entityName ?? NSNull(),
            "pageUrl": request.pageUrl
        ], forTab: uuid)
    }
}

// MARK: - WKScriptMessageHandler

extension DebugControlRecorder: WKScriptMessageHandler {

    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated {
            guard let body = message.body as? [String: Any],
                  let webView = message.webView,
                  let uuid = tabIdentifiersByWebView[ObjectIdentifier(webView)],
                  let record = records[uuid] else { return }

            switch body["kind"] as? String {
            case "console":
                record.console.record([
                    "level": body["level"] as? String ?? "log",
                    "text": body["text"] as? String ?? "",
                    "url": body["url"] as? String ?? "",
                    "frame": body["frame"] as? String ?? "main",
                    "line": body["line"] as? Int ?? 0,
                    "column": body["column"] as? Int ?? 0,
                    "source": body["source"] as? String ?? ""
                ])
            case "resource":
                record.network.record([
                    "url": body["name"] as? String ?? "",
                    "method": NSNull(),
                    "status": body["responseStatus"] as? Int ?? -1,
                    "initiator": "resource-timing",
                    "resourceType": body["initiatorType"] as? String ?? "",
                    "redirectedFrom": NSNull(),
                    "blocked": false,
                    "duration": body["duration"] as? Double ?? 0,
                    "transferSize": body["transferSize"] as? Int ?? -1,
                    "pageUrl": body["url"] as? String ?? ""
                ])
            default:
                break
            }
        }
    }
}

/// Passive responder recording every navigation the delegate chain sees. Always returns `.next`.
@MainActor
final class DebugControlNavigationResponder: NavigationResponder {

    private weak var tab: Tab?
    private weak var recorder: DebugControlRecorder?

    init(tab: Tab, recorder: DebugControlRecorder) {
        self.tab = tab
        self.recorder = recorder
    }

    private func record(_ fields: [String: Any]) {
        guard let tab, let recorder, recorder.isEnabled else { return }
        recorder.ensureAttached(to: tab)
        recorder.recordNetwork(fields, forTab: tab.uuid)
    }

    func decidePolicy(for navigationAction: NavigationAction, preferences: inout NavigationPreferences) async -> NavigationActionPolicy? {
        record([
            "url": navigationAction.url.absoluteString,
            "method": navigationAction.request.httpMethod ?? "GET",
            "status": -1,
            "initiator": "navigation-action",
            "resourceType": navigationAction.isForMainFrame ? "document" : "subframe",
            "redirectedFrom": navigationAction.redirectHistory?.last?.url.absoluteString ?? NSNull(),
            "blocked": false,
            "navigationType": String(describing: navigationAction.navigationType),
            "identifier": navigationAction.identifier
        ])
        return .next
    }

    func decidePolicy(for navigationResponse: NavigationResponse) async -> NavigationResponsePolicy? {
        record([
            "url": navigationResponse.url.absoluteString,
            "method": NSNull(),
            "status": navigationResponse.httpStatusCode ?? -1,
            "initiator": "navigation-response",
            "resourceType": navigationResponse.isForMainFrame ? "document" : "subframe",
            "redirectedFrom": NSNull(),
            "blocked": false,
            "mimeType": navigationResponse.response.mimeType ?? NSNull()
        ])
        return .next
    }

    func didReceiveRedirect(_ navigationAction: NavigationAction, for navigation: Navigation) {
        record([
            "url": navigationAction.url.absoluteString,
            "method": navigationAction.request.httpMethod ?? "GET",
            "status": -1,
            "initiator": "redirect",
            "resourceType": "document",
            "redirectedFrom": navigation.url.absoluteString,
            "blocked": false
        ])
    }

    func navigation(_ navigation: Navigation, didFailWith error: WKError) {
        record([
            "url": navigation.url.absoluteString,
            "method": NSNull(),
            "status": -1,
            "initiator": "navigation-failed",
            "resourceType": "document",
            "redirectedFrom": NSNull(),
            "blocked": false,
            "error": error.localizedDescription
        ])
    }

    var shouldDisableLongDecisionMakingChecks: Bool { true }
}

#endif
