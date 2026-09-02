//
//  DebugControlRouter.swift
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

import AppKit
import BrowserServicesKit
import Foundation
import FoundationExtensions
import PrivacyConfig
import WebKit
import os.log

@MainActor
final class DebugControlRouter {

    private let windowControllersManager: WindowControllersManager
    private let contentBlocking: AnyContentBlocking
    private let recorder: DebugControlRecorder

    init(windowControllersManager: WindowControllersManager,
         contentBlocking: AnyContentBlocking,
         recorder: DebugControlRecorder) {
        self.windowControllersManager = windowControllersManager
        self.contentBlocking = contentBlocking
        self.recorder = recorder
    }

    func handle(_ request: DebugControlRequest) async -> DebugControlResponse {
        Logger.debugControlServer.debug("\(request.method) \(request.path)")
        do {
            switch (request.method, request.path) {
            case ("GET", "/status"): return status()
            case ("POST", "/navigate"): return try await navigate(request)
            case ("POST", "/eval"): return try await evaluate(request)
            case ("GET", "/console"): return try console(request)
            case ("GET", "/network"): return try network(request)
            case ("GET", "/protections"): return protectionsState(request)
            case ("POST", "/protections"): return try setProtections(request)
            case ("GET", "/config"): return try configuration(request)
            case ("POST", "/config"): return try loadConfiguration(request)
            case ("POST", "/screenshot"): return try await screenshot(request)
            case ("POST", "/reload"): return try reload(request)
            case ("POST", "/clear-data"): return await clearData(request)
            case ("GET", "/source"): return try await source(request)
            case ("POST", "/ua"): return try userAgent(request)
            case ("POST", "/tab"): return try selectTab(request)
            case ("POST", "/tab/new"): return try newTab(request)
            case ("GET", "/userscripts"): return try userScripts()
            default:
                return .failure("no handler for \(request.method) \(request.path)", status: 404)
            }
        } catch let error as DebugControlError {
            return .failure(error.message)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    // MARK: - Tabs

    private struct DebugControlError: Error {
        let message: String
    }

    private var tabCollectionViewModel: TabCollectionViewModel? {
        windowControllersManager.lastKeyMainWindowController?.mainViewController.tabCollectionViewModel
    }

    /// Pinned tabs first, then unpinned — the order `/status` reports and `/tab` indexes into.
    private var flattenedTabIndices: [TabIndex] {
        guard let tabCollectionViewModel else { return [] }
        let pinnedCount = tabCollectionViewModel.pinnedTabsCollection?.tabs.count ?? 0
        return (0..<pinnedCount).map { TabIndex.pinned($0) }
            + tabCollectionViewModel.tabCollection.tabs.indices.map { TabIndex.unpinned($0) }
    }

    private func tab(at index: TabIndex) -> AnyTab? {
        guard let tabCollectionViewModel else { return nil }
        switch index {
        case .pinned(let item): return tabCollectionViewModel.pinnedTabsCollection?.tabs[safe: item]
        case .unpinned(let item): return tabCollectionViewModel.tabCollection.tabs[safe: item]
        }
    }

    private func selectedTab() throws -> Tab {
        guard let tab = tabCollectionViewModel?.selectedTabViewModel?.tab else {
            throw DebugControlError(message: "no selected tab")
        }
        recorder.ensureAttached(to: tab)
        return tab
    }

    func attachToAllTabs() {
        guard let tabCollectionViewModel else { return }
        let tabs = (tabCollectionViewModel.pinnedTabsCollection?.tabs ?? []) + tabCollectionViewModel.tabCollection.tabs
        recorder.ensureAttachedToAllTabs(tabs.compactMap { if case .loaded(let tab) = $0 { return tab } else { return nil } })
    }

    // MARK: - /status

    private func status() -> DebugControlResponse {
        attachToAllTabs()
        let selectedUUID = tabCollectionViewModel?.selectedTabViewModel?.tab.uuid
        let tabs = flattenedTabIndices.enumerated().compactMap { offset, index -> [String: Any]? in
            guard let tab = tab(at: index) else { return nil }
            return [
                "index": offset,
                "uuid": tab.uuid,
                "title": tab.title ?? NSNull(),
                "url": tab.url?.absoluteString ?? NSNull(),
                "isSelected": tab.uuid == selectedUUID,
                "isPinned": index.isPinnedTab
            ]
        }
        let info = Bundle.main.infoDictionary ?? [:]
        return .ok([
            "serverVersion": DebugControlServer.serverVersion,
            "appVersion": info["CFBundleShortVersionString"] as? String ?? "unknown",
            "buildNumber": info["CFBundleVersion"] as? String ?? "unknown",
            "bundleIdentifier": Bundle.main.bundleIdentifier ?? "unknown",
            "windowCount": windowControllersManager.mainWindowControllers.count,
            "isLoading": tabCollectionViewModel?.selectedTabViewModel?.tab.isLoading ?? false,
            "tabs": tabs
        ])
    }

    // MARK: - /navigate

    private func navigate(_ request: DebugControlRequest) async throws -> DebugControlResponse {
        guard let urlString = request.string("url"), let url = URL(string: urlString) else {
            throw DebugControlError(message: "missing or invalid `url`")
        }
        let tab = try selectedTab()
        windowControllersManager.lastKeyMainWindowController?.window?.makeKeyAndOrderFront(nil)
        tab.setContent(.contentFromURL(url, source: .ui))

        guard request.bool("wait", default: false) else {
            return .ok(["url": url.absoluteString, "waited": false])
        }
        let settled = await waitUntilSettled(tab: tab, timeout: request.double("timeout") ?? 30)
        return .ok(["url": tab.webView.url?.absoluteString ?? url.absoluteString, "waited": true, "settled": settled])
    }

    private func waitUntilSettled(tab: Tab, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        // Give the navigation a moment to start before treating `isLoading == false` as "finished".
        try? await Task.sleep(nanoseconds: 300_000_000)
        while tab.isLoading {
            guard Date() < deadline else { return false }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return true
    }

    // MARK: - /eval

    private func evaluate(_ request: DebugControlRequest) async throws -> DebugControlResponse {
        guard let js = request.string("js") else {
            throw DebugControlError(message: "missing `js`")
        }
        let world = try contentWorld(named: request.string("world") ?? "page")
        let tab = try selectedTab()
        let value = try await run(js, in: world, on: tab.webView, isExpression: request.json["expression"] as? Bool)
        return .ok(["result": value, "world": request.string("world") ?? "page"])
    }

    private func contentWorld(named name: String) throws -> WKContentWorld {
        switch name {
        case "page": return .page
        case "isolated": return .defaultClient
        default: throw DebugControlError(message: "unknown world `\(name)`, expected `page` or `isolated`")
        }
    }

    /// `callAsyncJavaScript` runs a function body, so a bare expression is wrapped in a `return`.
    /// Anything containing a `return` statement is passed through untouched; override with `"expression"`.
    private func run(_ js: String, in world: WKContentWorld, on webView: WKWebView, isExpression: Bool?) async throws -> Any {
        let looksLikeExpression = isExpression ?? (js.range(of: "\\breturn\\b", options: .regularExpression) == nil)
        let body = looksLikeExpression ? "return (\(js));" : js
        do {
            let result = try await webView.callAsyncJavaScript(body, arguments: [:], in: nil, contentWorld: world)
            return Self.jsonSafe(result)
        } catch {
            throw DebugControlError(message: "\(error.localizedDescription) — evaluated: \(body.prefix(400))")
        }
    }

    private static func jsonSafe(_ value: Any?) -> Any {
        guard let value, !(value is NSNull) else { return NSNull() }
        if JSONSerialization.isValidJSONObject([value]) { return value }
        return String(describing: value)
    }

    // MARK: - /console and /network

    private func console(_ request: DebugControlRequest) throws -> DebugControlResponse {
        let tab = try selectedTab()
        let entries = recorder.consoleEntries(forTab: tab.uuid, since: request.double("since"))
        if request.bool("clear", default: false) {
            recorder.clearConsole(forTab: tab.uuid)
        }
        return .ok(["messages": entries, "count": entries.count])
    }

    private func network(_ request: DebugControlRequest) throws -> DebugControlResponse {
        let tab = try selectedTab()
        let entries = recorder.networkEntries(forTab: tab.uuid, since: request.double("since"))
        if request.bool("clear", default: false) {
            recorder.clearNetwork(forTab: tab.uuid)
        }
        return .ok(["requests": entries, "count": entries.count])
    }

    // MARK: - /protections

    private func domain(from request: DebugControlRequest) -> String? {
        if let domain = request.string("domain"), !domain.isEmpty { return domain }
        return tabCollectionViewModel?.selectedTabViewModel?.tab.webView.url?.host
    }

    private func protectionsState(_ request: DebugControlRequest) -> DebugControlResponse {
        guard let domain = domain(from: request) else {
            return .failure("missing `domain` and no selected tab URL to fall back on")
        }
        let config = contentBlocking.privacyConfigurationManager.privacyConfig
        return .ok([
            "domain": domain,
            "isProtected": config.isProtected(domain: domain),
            "isUserUnprotected": config.isUserUnprotected(domain: domain),
            "isTempUnprotected": config.isTempUnprotected(domain: domain),
            "userUnprotectedDomains": config.userUnprotectedDomains
        ])
    }

    private func setProtections(_ request: DebugControlRequest) throws -> DebugControlResponse {
        guard let domain = domain(from: request) else {
            throw DebugControlError(message: "missing `domain` and no selected tab URL to fall back on")
        }
        guard let enabled = request.json["enabled"] as? Bool else {
            throw DebugControlError(message: "missing `enabled`")
        }
        let config = contentBlocking.privacyConfigurationManager.privacyConfig
        if enabled {
            config.userEnabledProtection(forDomain: domain)
        } else {
            config.userDisabledProtection(forDomain: domain)
        }
        contentBlocking.contentBlockingManager.scheduleCompilation()
        return .ok([
            "domain": domain,
            "enabled": enabled,
            "isProtected": config.isProtected(domain: domain),
            "note": "content blocking rules are recompiling; reload the tab once they land"
        ])
    }

    // MARK: - /config

    private func configuration(_ request: DebugControlRequest) throws -> DebugControlResponse {
        let manager = contentBlocking.privacyConfigurationManager
        guard let root = try JSONSerialization.jsonObject(with: manager.currentConfig) as? [String: Any] else {
            throw DebugControlError(message: "privacy configuration is not a JSON object")
        }
        let features = root["features"] as? [String: Any] ?? [:]
        let domain = domain(from: request)
        let config = manager.privacyConfig

        if let featureName = request.string("feature") {
            guard let feature = features[featureName] as? [String: Any] else {
                throw DebugControlError(message: "no feature named `\(featureName)` in the current configuration")
            }
            let settings = feature["settings"] as? [String: Any] ?? [:]
            return .ok([
                "domain": domain ?? NSNull(),
                "feature": featureName,
                "state": feature["state"] as? String ?? "unknown",
                "matchedExceptions": Self.matchedExceptions(in: feature, domain: domain),
                "matchedDomainOverrides": Self.matchedDomainOverrides(in: settings, domain: domain),
                "settings": Self.jsonSafe(settings),
                "subfeatures": Self.jsonSafe(feature["features"] ?? [:]),
                "isUserUnprotected": domain.map { config.isUserUnprotected(domain: $0) } ?? false,
                "isTempUnprotected": domain.map { config.isTempUnprotected(domain: $0) } ?? false
            ])
        }

        var summary: [String: Any] = [:]
        for (name, value) in features {
            guard let feature = value as? [String: Any] else { continue }
            let matched = Self.matchedExceptions(in: feature, domain: domain)
            summary[name] = [
                "state": feature["state"] as? String ?? "unknown",
                "matchedExceptions": matched,
                "enabledForDomain": (feature["state"] as? String == "enabled") && matched.isEmpty
            ]
        }
        let unprotectedTemporary = (root["unprotectedTemporary"] as? [[String: Any]] ?? [])
            .filter { Self.matches(domain: domain, pattern: $0["domain"] as? String) }

        return .ok([
            "domain": domain ?? NSNull(),
            "version": Self.jsonSafe(root["version"]),
            "identifier": config.identifier,
            "isProtected": domain.map { config.isProtected(domain: $0) } ?? true,
            "userUnprotectedDomains": config.userUnprotectedDomains,
            "unprotectedTemporaryMatches": unprotectedTemporary,
            "features": summary
        ])
    }

    private static func matchedExceptions(in feature: [String: Any], domain: String?) -> [[String: Any]] {
        (feature["exceptions"] as? [[String: Any]] ?? [])
            .filter { matches(domain: domain, pattern: $0["domain"] as? String) }
    }

    private static func matchedDomainOverrides(in settings: [String: Any], domain: String?) -> [Any] {
        guard let entries = settings["domains"] as? [[String: Any]] else { return [] }
        return entries.filter { entry in
            switch entry["domain"] {
            case let pattern as String: return matches(domain: domain, pattern: pattern)
            case let patterns as [String]: return patterns.contains { matches(domain: domain, pattern: $0) }
            default: return false
            }
        }
    }

    /// Replaces the in-memory privacy configuration with one read from disk, so a candidate
    /// change to the privacy-configuration repo can be exercised without shipping it.
    /// The next scheduled config refresh overwrites this, as does `{"reset": true}`.
    private func loadConfiguration(_ request: DebugControlRequest) throws -> DebugControlResponse {
        let manager = contentBlocking.privacyConfigurationManager

        if request.bool("reset", default: false) {
            let result = manager.reload(etag: nil, data: nil)
            regenerateUserScripts()
            return .ok([
                "reset": true,
                "result": String(describing: result),
                "note": "user scripts regenerated; open a new tab to run against this configuration"
            ])
        }

        guard let path = request.string("path"), path.hasPrefix("/") else {
            throw DebugControlError(message: "missing absolute `path` (or pass `reset: true`)")
        }
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw DebugControlError(message: "could not read \(path): \(error.localizedDescription)")
        }
        let etag = "debug-\(UInt64(Date().timeIntervalSince1970 * 1000))"
        let result = manager.reload(etag: etag, data: data)
        guard result == .downloaded else {
            throw DebugControlError(message: "config at \(path) failed to parse; the manager fell back to \(result)")
        }
        regenerateUserScripts()

        let root = try? JSONSerialization.jsonObject(with: manager.currentConfig) as? [String: Any]
        return .ok([
            "path": path,
            "bytes": data.count,
            "etag": etag,
            "version": Self.jsonSafe(root?["version"]),
            "featureCount": (root?["features"] as? [String: Any])?.count ?? 0,
            "note": "user scripts regenerated; open a new tab to run against this configuration"
        ])
    }

    /// Rebuilds the content-scope user scripts against the configuration now in the manager.
    /// `scheduleCompilation()` alone is not enough: `UserContentUpdating` only regenerates when
    /// `ContentBlockerRulesManager` emits, and a config swap that leaves the compiled rules
    /// unchanged produces no such event. This notification is the other input to that pipeline.
    private func regenerateUserScripts() {
        contentBlocking.contentBlockingManager.scheduleCompilation()
        NotificationCenter.default.post(name: .contentScopeDebugStateDidChange, object: nil)
    }

    private static func matches(domain: String?, pattern: String?) -> Bool {
        guard let pattern else { return false }
        if pattern == "<all>" { return true }
        guard let domain else { return false }
        return domain == pattern || domain.hasSuffix("." + pattern)
    }

    // MARK: - /screenshot

    private func screenshot(_ request: DebugControlRequest) async throws -> DebugControlResponse {
        let tab = try selectedTab()
        let image: NSImage = try await withCheckedThrowingContinuation { continuation in
            tab.webView.takeSnapshot(with: WKSnapshotConfiguration()) { image, error in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: DebugControlError(message: error?.localizedDescription ?? "snapshot failed"))
                }
            }
        }
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw DebugControlError(message: "failed to encode PNG")
        }
        let path = try write(png, extension: "png", suggestedName: request.string("path"))
        return .ok(["path": path, "bytes": png.count])
    }

    private func write(_ data: Data, extension pathExtension: String, suggestedName: String?) throws -> String {
        let url: URL
        if let suggestedName, suggestedName.hasPrefix("/") {
            url = URL(fileURLWithPath: suggestedName)
        } else {
            url = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("ddg-debug-\(Int(Date().timeIntervalSince1970 * 1000))")
                .appendingPathExtension(pathExtension)
        }
        try data.write(to: url)
        return url.path
    }

    // MARK: - /reload, /clear-data

    private func reload(_ request: DebugControlRequest) throws -> DebugControlResponse {
        let tab = try selectedTab()
        let bypassCache = request.bool("bypassCache", default: false)
        if bypassCache {
            tab.webView.reloadFromOrigin()
        } else {
            tab.reload()
        }
        return .ok(["bypassCache": bypassCache])
    }

    private func clearData(_ request: DebugControlRequest) async -> DebugControlResponse {
        let dataStore = tabCollectionViewModel?.selectedTabViewModel?.tab.webView.configuration.websiteDataStore ?? .default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()

        guard let domain = request.string("domain"), !domain.isEmpty, domain != "all" else {
            await dataStore.removeData(ofTypes: types, modifiedSince: .distantPast)
            return .ok(["cleared": "all"])
        }

        let records = await dataStore.dataRecords(ofTypes: types)
        let matching = records.filter { $0.displayName == domain || domain.hasSuffix("." + $0.displayName) || $0.displayName.hasSuffix("." + domain) }
        await dataStore.removeData(ofTypes: types, for: matching)
        return .ok(["cleared": domain, "records": matching.map(\.displayName)])
    }

    // MARK: - /source

    private func source(_ request: DebugControlRequest) async throws -> DebugControlResponse {
        let tab = try selectedTab()
        let value = try await run("return document.documentElement.outerHTML;",
                                  in: .page,
                                  on: tab.webView,
                                  isExpression: false)
        guard let html = value as? String else {
            throw DebugControlError(message: "page did not return an HTML string")
        }
        let data = Data(html.utf8)
        guard data.count > 256 * 1024 else {
            return .ok(["html": html, "bytes": data.count])
        }
        let path = try write(data, extension: "html", suggestedName: request.string("path"))
        return .ok(["path": path, "bytes": data.count])
    }

    // MARK: - /ua, /tab, /userscripts

    private func userAgent(_ request: DebugControlRequest) throws -> DebugControlResponse {
        guard let value = request.string("value") else {
            throw DebugControlError(message: "missing `value`")
        }
        let tab = try selectedTab()
        tab.webView.customUserAgent = value.isEmpty ? nil : value
        return .ok([
            "value": value,
            "note": "Tab.decidePolicy re-applies UserAgent.for(url) on the next main frame navigation, so set this after navigating"
        ])
    }

    private func selectTab(_ request: DebugControlRequest) throws -> DebugControlResponse {
        guard let offset = request.int("index") else {
            throw DebugControlError(message: "missing `index`")
        }
        let indices = flattenedTabIndices
        guard let index = indices[safe: offset] else {
            throw DebugControlError(message: "index \(offset) out of range, \(indices.count) tabs")
        }
        guard let tab = tabCollectionViewModel?.selectTab(at: index) else {
            throw DebugControlError(message: "failed to select tab at index \(offset)")
        }
        recorder.ensureAttached(to: tab)
        return .ok(["index": offset, "uuid": tab.uuid, "url": tab.webView.url?.absoluteString ?? NSNull()])
    }

    private func newTab(_ request: DebugControlRequest) throws -> DebugControlResponse {
        guard let tabCollectionViewModel else {
            throw DebugControlError(message: "no window")
        }
        let url = request.string("url").flatMap(URL.init(string:))
        tabCollectionViewModel.appendNewTab(with: url.map { .contentFromURL($0, source: .ui) } ?? .newtab, selected: true)
        guard let tab = tabCollectionViewModel.selectedTabViewModel?.tab else {
            throw DebugControlError(message: "new tab was not selected")
        }
        recorder.ensureAttached(to: tab)
        return .ok(["uuid": tab.uuid, "index": flattenedTabIndices.count - 1, "url": url?.absoluteString ?? NSNull()])
    }

    private func userScripts() throws -> DebugControlResponse {
        let tab = try selectedTab()
        let scripts = tab.userContentController?.contentBlockingAssets?.userScripts.userScripts ?? []
        let described = scripts.map { script -> [String: Any] in
            [
                "type": String(describing: type(of: script)),
                "sourceLength": script.source.count,
                "injectionTime": script.injectionTime == .atDocumentStart ? "documentStart" : "documentEnd",
                "forMainFrameOnly": script.forMainFrameOnly,
                "world": script.requiresRunInPageContentWorld ? "page" : "isolated",
                "messageNames": script.messageNames
            ]
        }
        return .ok([
            "userScripts": described,
            "count": described.count,
            "wkUserScriptCount": tab.webView.configuration.userContentController.userScripts.count
        ])
    }
}

#endif
