//
//  WebViewTestHelper.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import Common
import ContentBlocking
import Foundation
import Network
import PrivacyConfig
import PrivacyConfigTestsUtils
import TrackerRadarKit
import UserScript
import WebKit
import XCTest

// ╔══════════════════════════════════════════════════════════════════════════════╗
// ║  NEW PROXY-BASED TEST INFRASTRUCTURE (macOS 14+ / iOS 17+)                ║
// ║                                                                            ║
// ║  Uses WKWebsiteDataStore.proxyConfigurations with a loopback CONNECT       ║
// ║  proxy and real PSL-listed domains for faithful eTLD+1 semantics.          ║
// ╚══════════════════════════════════════════════════════════════════════════════╝

// MARK: - TestTrackerProtectionDelegate

/// Collects DetectedRequest objects produced by the real TrackerProtectionEventMapper.
/// This is the ONLY test-double in the full stack. Everything else is real production code.
@MainActor
final class TestTrackerProtectionDelegate: NSObject, TrackerProtectionSubfeatureDelegate {

    private(set) var detectedTrackers: [DetectedRequest] = []
    private(set) var detectedThirdPartyRequests: [DetectedRequest] = []
    private(set) var detectedSurrogates: [(DetectedRequest, String)] = []

    /// Keyed by resource URL string. Fulfilled when C-S-S observes the resource
    /// (regardless of whether a DetectedRequest is produced or the observation
    /// is silently dropped as same-site).
    var expectations: [String: XCTestExpectation] = [:]

    private let eventMapper: TrackerProtectionEventMapper

    init(eventMapper: TrackerProtectionEventMapper) {
        self.eventMapper = eventMapper
        super.init()
    }

    func reset() {
        detectedTrackers.removeAll()
        detectedThirdPartyRequests.removeAll()
        detectedSurrogates.removeAll()
        expectations.removeAll()
    }

    // MARK: - TrackerProtectionSubfeatureDelegate

    func trackerProtectionShouldProcessTrackers(_ subfeature: TrackerProtectionSubfeature) -> Bool {
        return true
    }

    func trackerProtection(_ subfeature: TrackerProtectionSubfeature,
                           didObserveResource observation: TrackerProtectionSubfeature.ResourceObservation) {
        let vendor = subfeature.currentAdClickAttributionVendor

        if let detected = eventMapper.classifyResource(observation, adClickAttributionVendor: vendor) {
            if detected.state == .blocked {
                detectedTrackers.append(detected)
            } else {
                // Mapper guarantees same-site observations are filtered upstream
                // (see `classifyResource` / `makeThirdPartyRequest`), so any
                // non-blocked classification here is a real cross-site allow.
                detectedThirdPartyRequests.append(detected)
            }
        } else if let thirdParty = eventMapper.makeThirdPartyRequest(from: observation) {
            detectedThirdPartyRequests.append(thirdParty)
        }

        fulfillExpectation(for: observation.url)
    }

    func trackerProtection(_ subfeature: TrackerProtectionSubfeature,
                           didInjectSurrogate surrogate: TrackerProtectionSubfeature.SurrogateInjection) {
        let vendor = subfeature.currentAdClickAttributionVendor

        if let detected = eventMapper.classifySurrogate(surrogate, adClickAttributionVendor: vendor),
           let host = eventMapper.surrogateHost(from: surrogate) {
            detectedSurrogates.append((detected, host))
        }

        fulfillExpectation(for: surrogate.url)
    }

    private func fulfillExpectation(for urlString: String) {
        if let expectation = expectations[urlString] {
            expectation.fulfill()
        }
    }
}

// MARK: - TestLoopbackProxy

/// Minimal HTTP CONNECT proxy bound to 127.0.0.1 for use with
/// `WKWebsiteDataStore.proxyConfigurations`. Routes traffic by Host header
/// and serves registered canned responses.
///
/// WKWebView sends `CONNECT host:port HTTP/1.1` through this proxy; the proxy
/// responds 200 and then relays HTTP request/response pairs over the tunnel.
/// The tunnel is kept alive for same-host sub-resource reuse.
@available(macOS 14.0, iOS 17.0, *)
final class TestLoopbackProxy: @unchecked Sendable {

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "TestLoopbackProxy")
    private(set) var port: UInt16 = 0

    private let lock = NSLock()
    private var _received: [(host: String, path: String)] = []
    private var _content: [String: Data] = [:]

    /// Register a canned response for a given host + path combination.
    func registerContent(host: String, path: String, body: String, mimeType: String = "text/html") {
        let resolvedMime: String
        if path.hasSuffix(".js") {
            resolvedMime = "application/javascript"
        } else if path.hasSuffix(".png") || path.hasSuffix(".gif") {
            resolvedMime = "image/png"
        } else {
            resolvedMime = mimeType
        }
        let bodyData = body.data(using: .utf8)!
        let header = "HTTP/1.1 200 OK\r\nContent-Type: \(resolvedMime)\r\nContent-Length: \(bodyData.count)\r\nAccess-Control-Allow-Origin: *\r\nConnection: keep-alive\r\n\r\n"
        var full = header.data(using: .utf8)!
        full.append(bodyData)
        lock.withLock { _content["\(host)\(path)"] = full }
    }

    func start() async throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let l = try NWListener(using: params)
        self.listener = l

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var resumed = false
            l.stateUpdateHandler = { [weak self] state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    self?.port = l.port?.rawValue ?? 0
                    cont.resume()
                case .failed(let error):
                    resumed = true
                    cont.resume(throwing: error)
                default: break
                }
            }
            l.newConnectionHandler = { [weak self] conn in
                self?.handleConnection(conn)
            }
            l.start(queue: queue)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    /// Clear the recorded request log (call between test iterations).
    func clearReceivedRequests() {
        lock.withLock { _received.removeAll() }
    }

    /// All requests the proxy has received, in order.
    func receivedRequests() -> [(host: String, path: String)] {
        lock.withLock { _received }
    }

    /// Whether the proxy received a request for the given host + path.
    func didReceive(host: String, path: String) -> Bool {
        lock.withLock { _received.contains { $0.host == host && $0.path == path } }
    }

    // MARK: - Connection handling

    private func handleConnection(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let self, let data, let text = String(data: data, encoding: .utf8) else {
                conn.cancel(); return
            }
            let lines = text.components(separatedBy: "\r\n")
            guard let reqLine = lines.first else { conn.cancel(); return }
            let parts = reqLine.components(separatedBy: " ")
            guard parts.count >= 2 else { conn.cancel(); return }

            if parts[0] == "CONNECT" {
                self.handleConnect(conn: conn, target: parts[1])
            } else {
                self.handleForwardProxy(conn: conn, fullURL: parts[1])
            }
        }
    }

    private func handleConnect(conn: NWConnection, target: String) {
        let targetHost = target.components(separatedBy: ":").first ?? target
        let established = "HTTP/1.1 200 Connection Established\r\n\r\n".data(using: .utf8)!

        conn.send(content: established, completion: .contentProcessed { [weak self] _ in
            self?.readTunnelRequest(conn: conn, defaultHost: targetHost)
        })
    }

    private func readTunnelRequest(conn: NWConnection, defaultHost: String) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let self, let data, !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                conn.cancel(); return
            }
            let lines = text.components(separatedBy: "\r\n")
            guard let reqLine = lines.first else { conn.cancel(); return }
            let reqParts = reqLine.components(separatedBy: " ")
            guard reqParts.count >= 2 else { conn.cancel(); return }

            let path = reqParts[1]
            let host = lines.first(where: { $0.lowercased().hasPrefix("host:") })
                .map { String($0.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
                .map { $0.components(separatedBy: ":").first ?? $0 }
                ?? defaultHost

            self.lock.withLock { self._received.append((host: host, path: path)) }
            self.serveKeepAlive(conn: conn, host: host, path: path, defaultHost: defaultHost)
        }
    }

    private func handleForwardProxy(conn: NWConnection, fullURL: String) {
        guard let url = URL(string: fullURL) else { conn.cancel(); return }
        let host = url.host ?? ""
        let path = url.path.isEmpty ? "/" : url.path

        lock.withLock { _received.append((host: host, path: path)) }
        let key = "\(host)\(path)"
        let resp: Data = lock.withLock {
            _content[key] ?? notFoundResponse
        }
        conn.send(content: resp, completion: .contentProcessed { _ in conn.cancel() })
    }

    private func serveKeepAlive(conn: NWConnection, host: String, path: String, defaultHost: String) {
        let key = "\(host)\(path)"
        let resp: Data = lock.withLock { _content[key] ?? notFoundResponse }
        conn.send(content: resp, completion: .contentProcessed { [weak self] _ in
            self?.readTunnelRequest(conn: conn, defaultHost: defaultHost)
        })
    }

    private var notFoundResponse: Data {
        "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: keep-alive\r\n\r\n".data(using: .utf8)!
    }
}

// MARK: - HarnessNavigationDelegate

@MainActor
private final class HarnessNavigationDelegate: NSObject, WKNavigationDelegate {

    var onDidFinish: (() -> Void)?
    var onDidFail: ((Error) -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let callback = onDidFinish
        onDidFinish = nil
        onDidFail = nil
        callback?()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let callback = onDidFail
        onDidFinish = nil
        onDidFail = nil
        callback?(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let callback = onDidFail
        onDidFinish = nil
        onDidFail = nil
        callback?(error)
    }
}

// MARK: - TestPrivacyConfigurationJSONGenerator

private struct TestPrivacyConfigurationJSONGenerator: CustomisedPrivacyConfigurationJSONGenerating {
    let privacyConfigManager: PrivacyConfigurationManaging
    var privacyConfiguration: Data? {
        privacyConfigManager.currentConfig
    }
}

// MARK: - WebViewTestHarness

/// Bundles the full ContentScopeUserScript + TrackerProtectionSubfeature + EventMapper
/// test stack with a real WKWebView routed through a loopback CONNECT proxy.
///
/// Uses `WKWebsiteDataStore.proxyConfigurations` so that real PSL-listed domain
/// names (e.g. `page.example.com`, `tracker.example.org`) resolve through the
/// local proxy instead of the internet.  This preserves production-like eTLD+1
/// and same-site semantics without modifying `/etc/hosts` or production code.
@available(macOS 14.0, iOS 17.0, *)
@MainActor
final class WebViewTestHarness: NSObject {

    let webView: WKWebView
    let proxy: TestLoopbackProxy
    let delegate: TestTrackerProtectionDelegate

    private let contentScopeUserScript: ContentScopeUserScript
    private let trackerProtectionSubfeature: TrackerProtectionSubfeature
    private let eventMapper: TrackerProtectionEventMapper
    private let navigationDelegate: HarnessNavigationDelegate

    /// Creates a fully-wired test harness.
    ///
    /// Note: this init only configures the EventMapper, ContentScopeUserScript, and
    /// WKWebView. WKContentRuleList compilation/installation is a separate step —
    /// callers must invoke `compileAndInstallRules(...)` to install rule lists. The
    /// WKContentRuleList side of the pipeline therefore takes its tracker allowlist
    /// (`trackerExceptions`) and unprotected/exception domains from that call, not
    /// from this init. The `create(...)` factory wires both ends together.
    ///
    /// - Parameters:
    ///   - trackerData: TDS used for native classification (EventMapper mainTrackerData)
    ///     and, unless `cssTrackerData` is provided, also for C-S-S injection.
    ///   - supplementaryTrackerData: Additional TDS arrays for the mapper's multi-TDS loop
    ///     (e.g. CTL split TDS when CTL is active). Defaults to empty.
    ///   - cssTrackerData: If provided, C-S-S receives this TDS instead of `trackerData`.
    ///     Use when C-S-S needs the full/merged TDS while the mapper receives a split subset.
    ///   - privacyConfigManager: Provides the JSON injected into C-S-S at runtime.
    ///   - temporaryUnprotectedDomains: Domains temporarily unprotected (EventMapper).
    ///   - userUnprotectedDomains: Domains user-unprotected (EventMapper).
    ///   - contentBlockingEnabled: Whether content blocking is logically enabled in the EventMapper.
    ///   - trackerAllowlist: Tracker allowlist passed to the EventMapper for native
    ///     allowlist override (parity with WKContentRuleList allowlist matching).
    ///   - proxy: A started `TestLoopbackProxy` instance.
    ///   - useDefaultDataStore: When `true`, uses `WKWebsiteDataStore.default()` instead
    ///     of `.nonPersistent()`. Required as a workaround for a macOS 26 WebKit crash
    ///     triggered by large WKContentRuleLists + WKUserScript + nonPersistent proxy
    ///     configuration.
    init(trackerData: TrackerData,
         supplementaryTrackerData: [TrackerData] = [],
         cssTrackerData: TrackerData? = nil,
         privacyConfigManager: PrivacyConfigurationManaging,
         temporaryUnprotectedDomains: [String] = [],
         userUnprotectedDomains: [String] = [],
         contentBlockingEnabled: Bool = true,
         trackerAllowlist: PrivacyConfigurationData.TrackerAllowlistData = [:],
         proxy: TestLoopbackProxy,
         useDefaultDataStore: Bool = false) throws {

        self.proxy = proxy

        let tld = TLD()
        navigationDelegate = HarnessNavigationDelegate()

        eventMapper = TrackerProtectionEventMapper(
            tld: tld,
            mainTrackerData: trackerData,
            supplementaryTrackerData: supplementaryTrackerData,
            unprotectedSites: userUnprotectedDomains,
            tempList: temporaryUnprotectedDomains,
            contentBlockingEnabled: contentBlockingEnabled,
            trackerAllowlist: trackerAllowlist
        )

        delegate = TestTrackerProtectionDelegate(eventMapper: eventMapper)

        trackerProtectionSubfeature = TrackerProtectionSubfeature()
        trackerProtectionSubfeature.delegate = delegate

        let properties = ContentScopeProperties(
            gpcEnabled: false,
            sessionKey: UUID().uuidString,
            messageSecret: UUID().uuidString,
            featureToggles: .allTogglesOn
        )

        contentScopeUserScript = try ContentScopeUserScript(
            privacyConfigManager,
            properties: properties,
            scriptContext: .contentScope(surrogateTrackerData: ContentBlockerRulesManager.extractSurrogates(from: cssTrackerData ?? trackerData)),
            allowedNonisolatedFeatures: [TrackerProtectionSubfeature.featureNameValue],
            privacyConfigurationJSONGenerator: TestPrivacyConfigurationJSONGenerator(
                privacyConfigManager: privacyConfigManager
            )
        )
        contentScopeUserScript.registerSubfeature(delegate: trackerProtectionSubfeature)

        let configuration = WKWebViewConfiguration()

        let proxyEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: proxy.port)!
        )
        if useDefaultDataStore {
            let dataStore = WKWebsiteDataStore.default()
            dataStore.proxyConfigurations = [ProxyConfiguration(httpCONNECTProxy: proxyEndpoint)]
            configuration.websiteDataStore = dataStore
        } else {
            let dataStore = WKWebsiteDataStore.nonPersistent()
            dataStore.proxyConfigurations = [ProxyConfiguration(httpCONNECTProxy: proxyEndpoint)]
            configuration.websiteDataStore = dataStore
        }

        let ucc = configuration.userContentController
        ucc.addUserScript(contentScopeUserScript.makeWKUserScriptSync())
        for messageName in contentScopeUserScript.messageNames {
            ucc.addScriptMessageHandler(
                contentScopeUserScript,
                contentWorld: contentScopeUserScript.getContentWorld(),
                name: messageName
            )
        }

        webView = WKWebView(
            frame: .init(origin: .zero, size: .init(width: 500, height: 1000)),
            configuration: configuration
        )
        webView.navigationDelegate = navigationDelegate

        super.init()
    }

    // MARK: - Content Rule List

    /// Compiles a WKContentRuleList from tracker data and adds it to the web view.
    /// No scheme replacement — rules naturally match http:// URLs.
    func compileAndInstallRules(trackerData: TrackerData,
                                exceptions: [String],
                                tempUnprotected: [String],
                                trackerExceptions: [TrackerException]) async throws {
        let rules = ContentBlockerRulesBuilder(trackerData: trackerData)
            .buildRules(withExceptions: exceptions,
                        andTemporaryUnprotectedDomains: tempUnprotected,
                        andTrackerAllowlist: trackerExceptions)

        let data = try JSONEncoder().encode(rules)
        let ruleList = String(data: data, encoding: .utf8)!

        let compiled = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<WKContentRuleList, Error>) in
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "harness-\(UUID().uuidString)",
                encodedContentRuleList: ruleList
            ) { list, error in
                if let list {
                    cont.resume(returning: list)
                } else {
                    cont.resume(throwing: error ?? NSError(domain: "WebViewTestHarness", code: -1,
                                                            userInfo: [NSLocalizedDescriptionKey: "Failed to compile content rule list"]))
                }
            }
        }
        webView.configuration.userContentController.add(compiled)
    }

    // MARK: - Content Registration

    /// Register a page or resource on the proxy, keyed by host + path.
    func registerContent(host: String, path: String, body: String, mimeType: String = "text/html") {
        proxy.registerContent(host: host, path: path, body: body, mimeType: mimeType)
    }

    // MARK: - Page Loading

    /// Loads a URL through the proxy and waits for navigation to finish.
    func load(_ url: URL) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            navigationDelegate.onDidFinish = { cont.resume() }
            navigationDelegate.onDidFail = { cont.resume(throwing: $0) }
            webView.load(URLRequest(url: url))
        }
    }

    /// Convenience: loads `http://host/path`.
    func load(host: String, path: String = "/index.html") async throws {
        try await load(URL(string: "http://\(host)\(path)")!)
    }

    /// Loads an HTML string with a base URL and waits for navigation to finish.
    func loadHTMLString(_ html: String, baseURL: URL) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            navigationDelegate.onDidFinish = { cont.resume() }
            navigationDelegate.onDidFail = { cont.resume(throwing: $0) }
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    // MARK: - Observation Helpers

    /// Creates an expectation fulfilled when C-S-S observes a resource at `urlString`.
    /// The expectation fires regardless of whether a DetectedRequest is produced.
    func expectObservation(of urlString: String, testCase: XCTestCase) -> XCTestExpectation {
        let exp = testCase.expectation(description: "C-S-S observes \(urlString)")
        delegate.expectations[urlString] = exp
        return exp
    }

    /// Whether the proxy received a request for the given host + path.
    func proxyDidReceive(host: String, path: String) -> Bool {
        proxy.didReceive(host: host, path: path)
    }

    /// Clears WebKit caches on the data store. Call between test iterations
    /// when using the default (persistent) data store to avoid stale pages.
    func clearWebKitCaches() async {
        await webView.configuration.websiteDataStore.removeData(
            ofTypes: Set([WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache]),
            modifiedSince: Date(timeIntervalSince1970: 0)
        )
    }

    // MARK: - JavaScript Evaluation

    /// Evaluate JavaScript in the harness's web view, disambiguating the WebKit vs
    /// Common `evaluateJavaScript` overloads.
    func evaluateJS(_ script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { cont in
            webView.evaluateJavaScript(script) { result, error in
                if let error { cont.resume(throwing: error) } else { cont.resume(returning: result) }
            }
        }
    }
}

// MARK: - WebViewTestHarness Convenience Factory

@available(macOS 14.0, iOS 17.0, *)
extension WebViewTestHarness {

    /// High-level factory: creates a started proxy, builds all config objects,
    /// compiles content rules, and returns a ready-to-use harness.
    static func create(
        trackerDataJSON: String,
        locallyUnprotected: [String] = [],
        tempUnprotected: [String] = [],
        trackerAllowlist: [String: [PrivacyConfigurationData.TrackerAllowlist.Entry]] = [:],
        contentBlockingEnabled: Bool = true,
        exceptions: [String] = [],
        useDefaultDataStore: Bool = false
    ) async throws -> WebViewTestHarness {
        let trackerData = try JSONDecoder().decode(TrackerData.self, from: Data(trackerDataJSON.utf8))

        let privacyConfig = WebViewTestConfig.preparePrivacyConfig(
            locallyUnprotected: locallyUnprotected,
            tempUnprotected: tempUnprotected,
            trackerAllowlist: trackerAllowlist,
            contentBlockingEnabled: contentBlockingEnabled,
            exceptions: exceptions
        )

        var cssAllowlist: [String: [[String: Any]]] = [:]
        for (domain, entries) in trackerAllowlist {
            cssAllowlist[domain] = entries.map { entry in
                ["rule": entry.rule, "domains": entry.domains] as [String: Any]
            }
        }

        let configJSON = try WebViewTestConfig.makeConfig(
            trackerProtectionEnabled: true,
            contentBlockingEnabled: contentBlockingEnabled,
            trackerAllowlist: cssAllowlist,
            tempUnprotectedDomains: tempUnprotected
        )

        let manager = WebViewTestConfig.makeManager(configJSON: configJSON, privacyConfig: privacyConfig)

        var combinedTempUnprotected = privacyConfig.tempUnprotectedDomains.filter { !$0.trimmingWhitespace().isEmpty }
        combinedTempUnprotected.append(contentsOf: privacyConfig.exceptionsList(forFeature: .contentBlocking))

        let trackerExceptions = DefaultContentBlockerRulesExceptionsSource.transform(
            allowList: privacyConfig.trackerAllowlist.entries
        )

        let proxy = TestLoopbackProxy()
        try await proxy.start()

        let harness = try WebViewTestHarness(
            trackerData: trackerData,
            privacyConfigManager: manager,
            temporaryUnprotectedDomains: combinedTempUnprotected,
            userUnprotectedDomains: privacyConfig.userUnprotectedDomains,
            contentBlockingEnabled: contentBlockingEnabled,
            trackerAllowlist: trackerAllowlist,
            proxy: proxy,
            useDefaultDataStore: useDefaultDataStore
        )

        try await harness.compileAndInstallRules(
            trackerData: trackerData,
            exceptions: privacyConfig.userUnprotectedDomains,
            tempUnprotected: combinedTempUnprotected,
            trackerExceptions: trackerExceptions
        )

        return harness
    }
}

// MARK: - Config Builder Helpers

enum WebViewTestConfig {

    /// Builds a full remote-config-shaped JSON Data matching the structure C-S-S expects.
    static func makeConfig(
        trackerProtectionEnabled: Bool = true,
        contentBlockingEnabled: Bool = true,
        surrogateInjectionEnabled: Bool = true,
        ctlEnabled: Bool = false,
        trackerAllowlist: [String: [[String: Any]]] = [:],
        unprotectedDomains: [String] = [],
        tempUnprotectedDomains: [String] = [],
        userUnprotectedDomains: [String] = [],
        trackerProtectionExceptions: [[String: String]] = []
    ) throws -> Data {

        let exceptions = trackerProtectionExceptions.map { entry -> [String: String] in
            var result = [String: String]()
            if let domain = entry["domain"] { result["domain"] = domain }
            if let reason = entry["reason"] { result["reason"] = reason }
            return result
        }

        let settings: [String: Any] = [
            "blockingEnabled": contentBlockingEnabled,
            "ctlEnabled": ctlEnabled,
            "surrogateInjectionEnabled": surrogateInjectionEnabled,
            "allowlist": trackerAllowlist,
            "tempUnprotectedDomains": tempUnprotectedDomains,
            "userUnprotectedDomains": userUnprotectedDomains
        ]

        let trackerProtectionFeature: [String: Any] = [
            "state": trackerProtectionEnabled ? "enabled" : "disabled",
            "exceptions": exceptions,
            "settings": settings
        ]

        let contentBlockingFeature: [String: Any] = [
            "state": contentBlockingEnabled ? "enabled" : "disabled",
            "exceptions": [] as [[String: String]]
        ]

        // C-S-S compiled bundle reads the allowlist from
        // bundledConfig.features.trackerAllowlist.settings.allowlistedTrackers
        // using the native format: { domain: { rules: [{rule, domains}] } }
        var allowlistedTrackers = [String: [String: Any]]()
        for (domain, entries) in trackerAllowlist {
            allowlistedTrackers[domain] = ["rules": entries]
        }
        let trackerAllowlistFeature: [String: Any] = [
            "state": trackerAllowlist.isEmpty ? "disabled" : "enabled",
            "exceptions": [] as [[String: String]],
            "settings": ["allowlistedTrackers": allowlistedTrackers]
        ]

        var features: [String: Any] = [
            "trackerProtection": trackerProtectionFeature,
            "contentBlocking": contentBlockingFeature
        ]
        if !trackerAllowlist.isEmpty {
            features["trackerAllowlist"] = trackerAllowlistFeature
        }
        // The pre-built C-S-S bundle determines _ctlEnabled from
        // `features.clickToLoad.state` (via _isStateEnabled), while the local
        // submodule source reads `trackerProtection.settings.ctlEnabled`.
        // Both paths must be set so tests work with either bundle version.
        if ctlEnabled {
            features["clickToLoad"] = [
                "state": "enabled",
                "exceptions": [] as [[String: String]]
            ] as [String: Any]
        }

        let config: [String: Any] = [
            "version": 1,
            "features": features,
            "unprotectedTemporary": unprotectedDomains.map { ["domain": $0] }
        ]

        return try JSONSerialization.data(withJSONObject: config, options: [])
    }

    /// Creates a PrivacyConfiguration for WKContentRuleList compilation and EventMapper.
    static func preparePrivacyConfig(
        locallyUnprotected: [String] = [],
        tempUnprotected: [String] = [],
        trackerAllowlist: [String: [PrivacyConfigurationData.TrackerAllowlist.Entry]] = [:],
        contentBlockingEnabled: Bool = true,
        exceptions: [String] = []
    ) -> PrivacyConfiguration {
        let contentBlockingExceptions = exceptions.map { PrivacyConfigurationData.ExceptionEntry(domain: $0, reason: nil) }
        let contentBlockingStatus = contentBlockingEnabled ? "enabled" : "disabled"
        let features = [
            PrivacyFeature.contentBlocking.rawValue: PrivacyConfigurationData.PrivacyFeature(
                state: contentBlockingStatus,
                exceptions: contentBlockingExceptions
            )
        ]
        let unprotectedTemporary = tempUnprotected.map { PrivacyConfigurationData.ExceptionEntry(domain: $0, reason: nil) }
        let privacyData = PrivacyConfigurationData(
            features: features,
            unprotectedTemporary: unprotectedTemporary,
            trackerAllowlist: trackerAllowlist
        )

        let localProtection = MockDomainsProtectionStore()
        localProtection.unprotectedDomains = Set(locallyUnprotected)

        return AppPrivacyConfiguration(
            data: privacyData,
            identifier: "",
            localProtection: localProtection,
            internalUserDecider: MockInternalUserDecider()
        )
    }

    /// Creates a MockPrivacyConfigurationManager wired with config JSON and PrivacyConfiguration.
    static func makeManager(
        configJSON: Data,
        privacyConfig: PrivacyConfiguration
    ) -> MockPrivacyConfigurationManager {
        let manager = MockPrivacyConfigurationManager(privacyConfig: privacyConfig)
        manager.currentConfigString = String(data: configJSON, encoding: .utf8) ?? "{}"
        return manager
    }
}

// ╔══════════════════════════════════════════════════════════════════════════════╗
// ║  LEGACY HELPERS — PRESERVED FOR UNMIGRATED TESTS                           ║
// ║                                                                            ║
// ║  The types below are used by tests that still rely on the old              ║
// ║  ContentBlockerRulesUserScript / SurrogatesUserScript / test:// pipeline.  ║
// ║  Do NOT use them in new or migrated tests.                                 ║
// ║  Remove once all dependent tests have been migrated.                       ║
// ╚══════════════════════════════════════════════════════════════════════════════╝

// MARK: - LEGACY -- WebKitTestHelper

final class WebKitTestHelper {

    static func preparePrivacyConfig(locallyUnprotected: [String],
                                     tempUnprotected: [String],
                                     trackerAllowlist: [String: [PrivacyConfigurationData.TrackerAllowlist.Entry]],
                                     contentBlockingEnabled: Bool,
                                     exceptions: [String],
                                     httpsUpgradesEnabled: Bool = false,
                                     clickToLoadEnabled: Bool = true) -> PrivacyConfiguration {
        let contentBlockingExceptions = exceptions.map { PrivacyConfigurationData.ExceptionEntry(domain: $0, reason: nil) }
        let contentBlockingStatus = contentBlockingEnabled ? "enabled" : "disabled"
        let httpsStatus = httpsUpgradesEnabled ? "enabled" : "disabled"
        let clickToLoadStatus = clickToLoadEnabled ? "enabled" : "disabled"
        let features = [PrivacyFeature.contentBlocking.rawValue: PrivacyConfigurationData.PrivacyFeature(state: contentBlockingStatus,
                                                                                                         exceptions: contentBlockingExceptions),
                        PrivacyFeature.httpsUpgrade.rawValue: PrivacyConfigurationData.PrivacyFeature(state: httpsStatus, exceptions: []),
                        PrivacyFeature.clickToLoad.rawValue: PrivacyConfigurationData.PrivacyFeature(state: clickToLoadStatus,
                                                                                                         exceptions: contentBlockingExceptions)]
        let unprotectedTemporary = tempUnprotected.map { PrivacyConfigurationData.ExceptionEntry(domain: $0, reason: nil) }
        let privacyData = PrivacyConfigurationData(features: features,
                                                   unprotectedTemporary: unprotectedTemporary,
                                                   trackerAllowlist: trackerAllowlist)

        let localProtection = MockDomainsProtectionStore()
        localProtection.unprotectedDomains = Set(locallyUnprotected)

        return AppPrivacyConfiguration(data: privacyData,
                                       identifier: "",
                                       localProtection: localProtection,
                                       internalUserDecider: MockInternalUserDecider())
    }

    static func prepareContentBlockingRules(trackerData: TrackerData,
                                            exceptions: [String],
                                            tempUnprotected: [String],
                                            trackerExceptions: [TrackerException],
                                            identifier: String = "test",
                                            completion: @escaping (WKContentRuleList?) -> Void) {

        let rules = ContentBlockerRulesBuilder(trackerData: trackerData).buildRules(withExceptions: exceptions,
                                                                                    andTemporaryUnprotectedDomains: tempUnprotected,
                                                                                    andTrackerAllowlist: trackerExceptions)

        let data = (try? JSONEncoder().encode(rules))!
        var ruleList = String(data: data, encoding: .utf8)!

        ruleList = ruleList.replacingOccurrences(of: "https", with: "test", options: [], range: nil)

        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: ruleList) { list, _ in
            DispatchQueue.main.async {
                completion(list)
            }
        }
    }
}

// MARK: - LEGACY -- MockNavigationDelegate

final class MockNavigationDelegate: NSObject, WKNavigationDelegate {

    var onDidFinishNavigation: (() -> Void)?

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        XCTFail("Could to navigate to test site")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onDidFinishNavigation?()
    }
}

// MARK: - MockExperimentCohortsManager

class MockExperimentCohortsManager: ExperimentCohortsManaging {
    func resolveCohort(for experiment: ExperimentSubfeature, allowCohortAssignment: Bool) -> CohortID? {
        return nil
    }

    var experiments: Experiments?
}
