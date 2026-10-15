//
//  CPMReproHarness.swift
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
import PrivacyConfig
import PrivacyConfigTestsUtils
import WebKit
@testable import WebExtensions

/// Runs the production embedded extension, `WebExtensionManager` and `CPMMessagingHealthMonitor`
/// against system WebKit with real web views. Faults are injected only through test seams:
/// the native handler interceptor, the background prelude, and WebKit process control.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMReproHarness: AutoconsentMessageHandlerDelegate {

    enum Outcome: Equatable, CustomStringConvertible {
        case responded(latency: TimeInterval)
        case timedOut

        var description: String {
            switch self {
            case .responded(let latency): return String(format: "responded %.3fs", latency)
            case .timedOut: return "timed out"
            }
        }
    }

    let log = CPMReproLog()
    let pixels: CPMReproPixelRecorder
    let monitor: CPMMessagingHealthMonitor
    let handlerProvider: CPMReproHandlerProvider
    let manager: WebExtensionManager
    let coordinator: WebExtensionLifecycleCoordinator
    let window = CPMReproWindow()
    /// Embedded extension types the app has enabled; tests change it to install mid-session.
    var enabledTypes: Set<DuckDuckGoWebExtensionType> = [.embedded]
    /// Whether tabs pass the app's navigation gate. Disable only to observe raw WebKit behavior.
    var isNavigationGateEnabled = true
    let storage: CPMReproStorageProvider
    private let windowProvider: CPMReproWindowProvider
    private let directory: URL
    private let privacyConfigurationManager = MockPrivacyConfigurationManager()
    private let preferences = MockAutoconsentPreferences()
    private var navigationCounter = 0
    private var finishTimes: [String: TimeInterval] = [:]
    private var responseTimes: [String: TimeInterval] = [:]
    private var lastResponseTimes: [String: TimeInterval] = [:]
    private var frozenPIDs: Set<pid_t> = []
    private var watcher: Task<Void, Never>?
    private let keepsInstallation: Bool
    /// Records the install as an older version, so the next sync upgrades it: on the next harness
    /// start (an app update) or on `coordinator.sync()` in this session.
    func markInstalledVersionAsOutdated() throws {
        let outdated = installationStore.installedExtensions.map {
            InstalledWebExtension(uniqueIdentifier: $0.uniqueIdentifier,
                                  filename: $0.filename,
                                  name: $0.name,
                                  version: "2000.1.1",
                                  embeddedType: $0.embeddedType)
        }
        installationStore.installedExtensions = outdated
        try JSONEncoder().encode(outdated).write(to: installationRecordURL)
    }

    /// Whether this harness loads an extension that an earlier harness installed.
    private(set) var isRelaunch = false
    private let installationStore = InstalledWebExtensionStoringMock()
    private var installationRecordURL: URL { directory.appendingPathComponent("installed.json") }

    /// Pass an installation directory to keep the installed extension between harnesses, as an
    /// app relaunch does. Without one, every harness installs the extension for the first time.
    init(prelude: CPMReproPrelude? = nil,
         isHangRecoveryEnabled: Bool = true,
         installationDirectory: URL? = nil) throws {
        keepsInstallation = installationDirectory != nil
        directory = installationDirectory
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("cpm-repro-\(UUID().uuidString)")
        // The manager deletes unknown entries in the extensions directory, so keep the
        // installation record next to it rather than inside it.
        storage = CPMReproStorageProvider(extensionsDirectory: directory.appendingPathComponent("extensions"))
        storage.backgroundPrelude = try prelude?.javaScript()
        pixels = CPMReproPixelRecorder(log: log)
        monitor = CPMMessagingHealthMonitor(pixelFiring: pixels)
        windowProvider = CPMReproWindowProvider(window: window)
        preferences.cookiePopupPreference = .default
        privacyConfigurationManager.currentConfigString = Self.privacyConfig
        let log = self.log
        let configManager = privacyConfigurationManager
        let preferences = self.preferences
        let monitor = self.monitor
        weak var weakDelegate: CPMReproHarness?
        handlerProvider = CPMReproHandlerProvider(log: log) {
            AutoconsentWebExtensionMessageHandler(privacyConfigurationManager: configManager,
                                                  autoconsentPreferences: preferences,
                                                  cpmMessagingHealthMonitor: monitor,
                                                  delegate: weakDelegate)
        }
        let configuration = WebExtensionConfigurationProvidingMock()
        configuration.isInspectable = true
        manager = WebExtensionManager(configuration: configuration,
                                      windowTabProvider: windowProvider,
                                      storageProvider: storage,
                                      installationStore: installationStore,
                                      pixelFiring: pixels,
                                      cpmMessagingHealthMonitor: monitor,
                                      isCPMMessagingHangRecoveryEnabled: { isHangRecoveryEnabled },
                                      handlerProvider: handlerProvider)
        weak var weakSelf: CPMReproHarness?
        coordinator = WebExtensionLifecycleCoordinator(manager: manager,
                                                       initialLoadGateEnabledProvider: { weakSelf?.isNavigationGateEnabled ?? false },
                                                       enabledTypesProvider: { weakSelf?.enabledTypes ?? [] })
        weakSelf = self
        weakDelegate = self
        if let data = try? Data(contentsOf: installationRecordURL) {
            installationStore.installedExtensions = try JSONDecoder().decode([InstalledWebExtension].self, from: data)
        }
        isRelaunch = !installationStore.installedExtensions.isEmpty
    }

    // MARK: Lifecycle

    /// Loads and syncs extensions through the app's lifecycle coordinator. With `waitForLoad`
    /// false, returns at once like app launch does, and tabs rely on the navigation gate.
    func start(waitForLoad: Bool = true) async {
        log.add("start: loading embedded extension")
        let load = coordinator.loadAndSync()
        startBackgroundWatcher()
        guard waitForLoad else { return }
        await load.value
        log.add("start: embedded loaded=\(manager.isAutoconsentExtensionLoaded) relaunch=\(isRelaunch)")
        saveInstallation()
    }

    /// Persists the installed extension records so a later harness can load them as a relaunch.
    func saveInstallation() {
        guard keepsInstallation else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(installationStore.installedExtensions).write(to: installationRecordURL)
    }

    /// Logs every change of the background web view or its WebContent process.
    private func startBackgroundWatcher() {
        watcher = Task { @MainActor [weak self] in
            var last = "none"
            while !Task.isCancelled, let self {
                let webView = self.backgroundWebView
                let pid = CPMReproWebKitSPI.processIdentifier(of: webView).map(String.init) ?? "-"
                let state = webView.map { "view=\(ObjectIdentifier($0).hashValue % 10000) pid=\(pid)" } ?? "none"
                if state != last {
                    self.log.add("background \(state)")
                    last = state
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    /// Whether the background script received `init` from the document at `url`.
    func backgroundReceivedInit(from url: URL) -> Bool {
        log.lines.contains { $0.contains("recv init") && $0.hasSuffix("url=\(url.absoluteString)") }
    }

    func tearDown() async {
        watcher?.cancel()
        coordinator.cancelAll()
        frozenPIDs.forEach { kill($0, SIGCONT) }
        for tab in window.tabs {
            tab.webView.navigationDelegate = nil
            manager.eventsListener.didCloseTab(tab, windowIsClosing: true)
        }
        window.tabs.removeAll()
        for context in manager.contexts {
            try? manager.controller.unload(context)
        }
        if !keepsInstallation {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    var embeddedContext: WKWebExtensionContext? {
        manager.contexts.first { $0.webExtension.duckDuckGoWebExtensionType == .embedded }
    }

    // MARK: Tabs

    @discardableResult
    func openTab() -> CPMReproTab {
        let tab = CPMReproTab(identifier: "tab-\(window.tabs.count + 1)",
                              controller: manager.controller,
                              monitor: monitor,
                              log: log,
                              navigationWaiterProvider: { [weak coordinator] in coordinator?.initialLoadWaiter }) { [weak manager] in
            manager?.isAutoconsentExtensionLoaded ?? false
        }
        tab.window = window
        tab.onNavigationFinished = { [weak self] url in self?.recordFinish(url) }
        window.tabs.append(tab)
        manager.eventsListener.didOpenTab(tab)
        return tab
    }

    /// Navigates to a URL that is unique to this navigation so every dashboard refresh can be
    /// attributed to exactly one document.
    @discardableResult
    func navigate(_ tab: CPMReproTab, site: String? = nil) -> URL {
        navigationCounter += 1
        let host = site ?? "site-\(navigationCounter).cpm-repro.test"
        let url = URL(string: "https://\(host)/page?nav=\(navigationCounter)")!
        log.add("tab \(tab.identifier) navigate \(url.absoluteString)")
        tab.load(url)
        return url
    }

    /// Waits for navigation to finish, then for the CPM dashboard refresh of that document,
    /// using the same 4 s grace period as the production health monitor.
    func outcome(for url: URL, grace: TimeInterval = 4, finishTimeout: TimeInterval = 10) async -> Outcome {
        let key = url.absoluteString
        _ = await waitUntil(timeout: finishTimeout) { self.finishTimes[key] != nil }
        guard let finished = finishTimes[key] else { return .timedOut }
        _ = await waitUntil(timeout: grace) { self.responseTimes[key] != nil }
        guard let responded = responseTimes[key], responded - finished <= grace else { return .timedOut }
        return .responded(latency: responded - finished)
    }

    func navigateAndMeasure(_ tab: CPMReproTab, site: String? = nil) async -> Outcome {
        let url = navigate(tab, site: site)
        let result = await outcome(for: url)
        let marks = await contentMarks(in: tab)
        log.add("tab \(tab.identifier) \(url.absoluteString) -> \(result) content=\(marks)")
        return result
    }

    /// Asks the document currently loaded in `tab` to send CPM's `init` again, without navigating,
    /// and waits for the dashboard refresh it should produce.
    func reinitExistingDocument(in tab: CPMReproTab, grace: TimeInterval = 4) async -> Outcome {
        guard let url = tab.webView.url else { return .timedOut }
        let key = url.absoluteString
        let sentAt = log.elapsed
        _ = try? await tab.webView.evaluateJavaScript("document.dispatchEvent(new CustomEvent('cpm-repro-reinit'))")
        let responded = await waitUntil(timeout: grace) { (self.lastResponseTimes[key] ?? 0) > sentAt }
        let result: Outcome = responded ? .responded(latency: (lastResponseTimes[key] ?? sentAt) - sentAt) : .timedOut
        log.add("tab \(tab.identifier) existing document re-init \(key) -> \(result) content=\(await contentMarks(in: tab))")
        return result
    }

    /// Reads the content-script instrumentation marks from the page's document element.
    func contentMarks(in tab: CPMReproTab) async -> String {
        let script = """
        JSON.stringify(Object.fromEntries([...document.documentElement.attributes]
            .filter((a) => a.name.startsWith("data-cpm-repro-"))
            .map((a) => [a.name.slice(15), a.value])))
        """
        let value = try? await tab.webView.evaluateJavaScript(script)
        return value as? String ?? "?"
    }

    // MARK: WebKit processes

    var backgroundWebView: WKWebView? {
        embeddedContext.flatMap(CPMReproWebKitSPI.backgroundWebView(of:))
    }

    var backgroundPID: pid_t? {
        CPMReproWebKitSPI.processIdentifier(of: backgroundWebView)
    }

    func freezeBackground(for duration: TimeInterval) async {
        guard let pid = backgroundPID else {
            log.add("freeze: no background process")
            return
        }
        log.add("freeze background pid=\(pid) for \(duration)s")
        frozenPIDs.insert(pid)
        await CPMReproWebKitSPI.freeze(pid: pid, for: duration)
        frozenPIDs.remove(pid)
        log.add("thaw background pid=\(pid)")
    }

    // MARK: Waiting

    func waitUntil(timeout: TimeInterval, _ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    func sleep(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func recordFinish(_ url: URL) {
        finishTimes[url.absoluteString] = finishTimes[url.absoluteString] ?? log.elapsed
    }

    // MARK: AutoconsentMessageHandlerDelegate

    nonisolated func refreshDashboardState(url: URL, consentStatus: ConsentStatusInfo) {
        let elapsed = log.elapsed
        let key = url.absoluteString
        log.add("dashboard refresh \(key) stage=\(consentStatus.cpmStage ?? "-")")
        Task { @MainActor in
            self.responseTimes[key] = self.responseTimes[key] ?? elapsed
            self.lastResponseTimes[key] = elapsed
        }
    }

    nonisolated func showCookiePopupAnimation(topUrl: URL, isCosmetic: Bool) {}
    nonisolated func handleCookiePopup(_ popupInfo: CookiePopupHandledInfo) {}
    nonisolated func sendPixel(_ pixelInfo: PixelInfo) {}

    // MARK: Fixtures

    static let privacyConfig = """
    {
        "version": "1",
        "features": {
            "autoconsent": {
                "state": "enabled",
                "exceptions": [],
                "settings": { "disabledCMPs": [] }
            }
        },
        "unprotectedTemporary": []
    }
    """
}
