//
//  CPMAppIntegrationHarness.swift
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

import AppKit
import Combine
import FeatureFlags_macOS
import PrivacyConfig
import PrivacyConfigTestsUtils
import SharedTestUtilities
import WebExtensions
import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

#if DEBUG
@available(macOS 15.4, *)
@MainActor
final class CPMAppIntegrationHarness {
    struct NavigationGateWait {
        let beganAt: Date
        let elapsed: TimeInterval
        let startupWasPendingAtRelease: Bool
    }

    struct Probe {
        let label: String
        let url: URL
        let responded: Bool
        let pageReceivedInitResponse: Bool
        let elapsed: TimeInterval
        let diagnostics: [String: String]
        let failures: [[String: String]]

        var report: [String: Any] {
            ["label": label, "url": url.absoluteString, "responded": responded,
             "pageReceivedInitResponse": pageReceivedInitResponse, "elapsed": elapsed,
             "diagnostics": diagnostics, "failures": failures]
        }
    }

    private struct Preferences: AutoconsentPreferencesProviding {
        let cookiePopupPreference: CookiePopupPreference = .default
    }

    let app: AppDelegate
    let pixels = CPMAppPixelRecorder()
    let native = CPMAppNativeRecorder()
    let server = CPMAppFixtureServer()
    private var ownedDataStore: WKWebsiteDataStore?
    var dataStore: WKWebsiteDataStore { ownedDataStore! }
    let directory: URL
    private let flags: MockFeatureFlagger
    private let savedFlags: [String: Bool]
    private let contentBlocking = ContentBlockingMock()
    private let nativeConfiguration = MockPrivacyConfigurationManager()
    private var privacyFeatures: AnyPrivacyFeatures?
    private(set) var windows: [NSWindow] = []
    private var generations: [WebExtensionManager] = []
    private(set) var installationStore: CPMAppInstallationStore?
    private(set) var observedContextSets: [[String]] = []
    private var failureRecorders: [CPMAppFailureRecorder] = []
    private var failureDiagnostics: [[String: String]] { failureRecorders.flatMap(\.failures) }
    private(set) var storages: [CPMAppExtensionStorage] = []
    private var warmup: WKWebView?
    private var cancellables: Set<AnyCancellable> = []
    private var finishedURLs: Set<URL> = []
    private(set) var finishedURLDates: [URL: [Date]] = [:]
    private var finishedNavigationCounts: [String: Int] = [:]
    private(set) var navigationGateWaits: [NavigationGateWait] = []
    private var frozenProcesses: Set<Int32> = []
    private(set) var backgroundLoadErrorContexts: Set<ObjectIdentifier> = []
    private var probes: [Probe] = []
    private var observations: [[String: Any]] = []
    private var port: UInt16 = 0
    private var ownsEnvironment = false
    var startupDelayMilliseconds = 0

    var manager: WebExtensionManager { app.webExtensionManager as! WebExtensionManager }
    var context: WKWebExtensionContext? { (app.webExtensionManager as? WebExtensionManager)?.contexts.first }

    init() throws {
        app = try XCTUnwrap(Application.appDelegate)
        ownedDataStore = .nonPersistent()
        flags = try XCTUnwrap(Application.appDelegate.featureFlagger as? MockFeatureFlagger)
        savedFlags = flags.featuresStub
        // TestRunHelper swizzles FileManager.temporaryDirectory to a shared folder and deletes
        // that folder from other test-host lifecycles. Keep extension resources outside it.
        directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cpm-app-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        privacyFeatures = AppPrivacyFeatures(contentBlocking: contentBlocking, httpsUpgradeStore: HTTPSUpgradeStoreMock())
        (contentBlocking.privacyConfigurationManager.privacyConfig as? MockPrivacyConfiguration)?.isFeatureEnabledCheck = { _, _ in false }
        nativeConfiguration.currentConfigString = """
        {"version":"1","features":{"autoconsent":{"state":"enabled","exceptions":[],"settings":{"disabledCMPs":[]}}},"unprotectedTemporary":[]}
        """
    }

    func start(mainEnabled: Bool = true, embeddedEnabled: Bool = true) async throws {
        guard app.windowControllersManager.mainWindowControllers.isEmpty, app.pinnedTabsManager.isEmpty else {
            throw XCTSkip("CPM tests require an empty Integration Tests host; existing windows/pins are preserved")
        }
        ownsEnvironment = true
        port = try await server.start()
        // Every relevant remote flag is explicit, including the treatment and recovery kill switches.
        flags.featuresStub = [
            FeatureFlag.webExtensions.rawValue: mainEnabled,
            FeatureFlag.embeddedExtension.rawValue: embeddedEnabled,
            FeatureFlag.webExtensionStateRestorationGate.rawValue: true,
            FeatureFlag.cpmDiagnosticsRecorder.rawValue: true,
            FeatureFlag.cpmBackgroundDelegateProxy.rawValue: true,
            FeatureFlag.cpmBackgroundGraveyardTreatment.rawValue: false,
            FeatureFlag.cpmLateBackgroundDocumentRecovery.rawValue: ProcessInfo.processInfo.environment["CPM_APP_INTEGRATION_DISABLE_LATE_RECOVERY"] != "1",
            FeatureFlag.cpmMessagingHangRecovery.rawValue: false
        ]
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        warmup = WKWebView(frame: .zero, configuration: configuration)
        warmup?.load(URLRequest(url: url("network-warmup")))
        try await wait("owned Network process", timeout: 10) { CPMAppWebKit.network(self.warmup) != nil }
        app.configureWebExtensionsForIntegrationTests { [unowned self] in makeManager() }
        if mainEnabled {
            await app.webExtensionLifecycleCoordinator?.loadAndSync().value
            if embeddedEnabled {
                try await wait("embedded context", timeout: 20) { self.app.webExtensionManager?.isAutoconsentExtensionLoaded == true }
                await manager.loadEmbeddedExtensionBackgroundContent()
            }
        }
    }

    private func makeManager() -> WebExtensionManager {
        let storage = CPMAppExtensionStorage(directory: directory.appendingPathComponent("extensions-\(storages.count)"))
        storage.startupDelayMilliseconds = startupDelayMilliseconds
        storages.append(storage)
        let monitor = CPMMessagingHealthMonitor(pixelFiring: pixels)
        let diagnostics = CPMMessagingDiagnosticsRecorder(
            tabResolver: { [weak app] identifier in
                guard let app else { return nil }
                for controller in app.windowControllersManager.mainWindowControllers {
                    let model = controller.mainViewController.tabCollectionViewModel
                    if let tab = (model.loadedPinnedTabs + model.loadedTabs).first(where: { $0.uuid == identifier }) {
                        return (tab.webView, tab)
                    }
                }
                return nil
            },
            observesMemoryPressure: false,
            featureFlags: MacOSCPMDiagnosticsFeatureFlags(featureFlagger: flags),
            appSession: app.cpmAppSessionDiagnostics
        )
        let configuration = WKWebExtensionController.Configuration.nonPersistent()
        configuration.defaultWebsiteDataStore = dataStore
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.websiteDataStore = dataStore
        configuration.webViewConfiguration = webConfiguration
        let handler = WebExtensionHandlerProvider(privacyConfigurationManager: nativeConfiguration,
                                                  autoconsentPreferences: Preferences(),
                                                  cpmMessagingHealthMonitor: monitor)
        let installationStore = CPMAppInstallationStore()
        self.installationStore = installationStore
        let manager = WebExtensionManager(
            configuration: WebExtensionConfigurationProvider(),
            controllerConfiguration: configuration,
            windowTabProvider: WebExtensionWindowTabProvider(),
            storageProvider: storage,
            installationStore: installationStore,
            pixelFiring: pixels,
            cpmMessagingHealthMonitor: monitor,
            cpmDiagnosticsRecorder: diagnostics,
            isCPMMessagingHangRecoveryEnabled: { [weak flags] in flags?.isFeatureOn(FeatureFlag.cpmMessagingHangRecovery) == true },
            isCPMLateBackgroundDocumentRecoveryEnabled: { [weak flags] in flags?.isFeatureOn(FeatureFlag.cpmLateBackgroundDocumentRecovery) == true },
            handlerProvider: CPMAppHandlerProvider(production: handler, native: native)
        )
        let failureRecorder = CPMAppFailureRecorder(recorder: diagnostics)
        failureRecorders.append(failureRecorder)
        monitor.diagnosticsProvider = failureRecorder
        NotificationCenter.default.publisher(for: .webExtensionsDidChangeLoadedExtensions, object: manager)
            .sink { [weak self, weak manager] _ in
                MainActor.assumeIsolated {
                    autoreleasepool {
                        guard let manager else { return }
                        self?.observedContextSets.append(manager.contexts.map(\.uniqueIdentifier))
                    }
                }
            }.store(in: &cancellables)
        generations.append(manager)
        return manager
    }

    func setFlag(_ flag: FeatureFlag, enabled: Bool) {
        flags.featuresStub[flag.rawValue] = enabled
        flags.triggerUpdate()
    }

    @discardableResult
    func openWindow(tabs count: Int = 1) throws -> [Tab] {
        try autoreleasepool {
            let tabs = (0..<count).map { _ in makeTab() }
            let collection = TabCollection()
            tabs.forEach { collection.append(tab: $0) }
            let model = TabCollectionViewModel(tabCollection: collection, windowControllersManager: app.windowControllersManager)
            let window = try XCTUnwrap(WindowsManager.openNewWindow(with: model, burnerMode: .regular))
            window.animationBehavior = .none
            windows.append(window)
            return tabs
        }
    }

    func appendTab(to windowIndex: Int) throws -> Tab {
        try autoreleasepool {
            let tab = makeTab()
            let controller = try XCTUnwrap(windows[windowIndex].windowController as? MainWindowController)
            controller.mainViewController.tabCollectionViewModel.append(tab: tab, selected: true)
            return tab
        }
    }

    private func makeTab() -> Tab {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        let tab = Tab(content: .none, webViewConfiguration: configuration, privacyFeatures: privacyFeatures,
                      webExtensionInitialLoadWaiterProvider: { [weak self] in
            guard let waiter = self?.app.webExtensionLifecycleCoordinator?.initialLoadWaiter else { return nil }
            return { [weak self] in
                let began = Date()
                await waiter()
                let pending = self?.app.webExtensionManager?.pendingEmbeddedBackgroundStartup != nil
                self?.navigationGateWaits.append(NavigationGateWait(beganAt: began, elapsed: Date().timeIntervalSince(began),
                                                                  startupWasPendingAtRelease: pending))
            }
        })
        tab.webViewDidFinishNavigationPublisher.sink { [weak self, weak tab] in
            guard let self, let tab else { return }
            self.finishedNavigationCounts[tab.uuid, default: 0] += 1
            if let url = tab.webView.url {
                self.finishedURLs.insert(url)
                self.finishedURLDates[url, default: []].append(Date())
            }
        }.store(in: &cancellables)
        return tab
    }

    /// Prime the real window/web process before timing an install. about:blank is ineligible
    /// for CPM health measurement, so this cannot create a stale warm-up response deadline.
    func warmUpWindow(for tab: Tab) async throws {
        let previousFinishes = finishedNavigationCounts[tab.uuid, default: 0]
        autoreleasepool {
            tab.webView.loadHTMLString("<!doctype html><html><body></body></html>", baseURL: nil)
        }
        try await wait("initial window document", timeout: 15) {
            self.finishedNavigationCounts[tab.uuid, default: 0] > previousFinishes
        }
    }

    func url(_ label: String) -> URL {
        URL(string: "http://127.0.0.1:\(port)/\(label)\(label.contains("?") ? "&" : "?")document=\(UUID().uuidString)")!
    }

    func navigate(_ tab: Tab, label: String, timeout: TimeInterval = 12) async throws -> Probe {
        let target = url(label)
        let oldFailures = failureDiagnostics.count
        let started = Date()
        autoreleasepool {
            let openControllers = app.windowControllersManager.mainWindowControllers
            let controller = openControllers.first { $0.window === tab.webView.window }
                ?? openControllers.first { $0.mainViewController.tabCollectionViewModel.indexInAllTabs(of: tab) != nil }
            controller?.window?.makeKeyAndOrderFront(nil)
            controller?.mainViewController.tabCollectionViewModel.select(tab: tab)
            tab.setContent(.contentFromURL(target, source: .ui))
        }
        try await wait("real navigation finish: \(label)", timeout: timeout) { self.finishedURLs.contains(target) }
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline && !native.forwardedDashboardURLs.contains(target.absoluteString) && failureDiagnostics.count == oldFailures {
            try await pause(0.05)
        }
        let responded = native.forwardedDashboardURLs.contains(target.absoluteString)
        if responded {
            // The native dashboard can precede delivery of initResp to the page after a reload.
            // Observe the real acknowledgement rather than treating a fixed sleep as evidence.
            _ = try await waitForPageInitResponse(in: tab)
        }
        let marksJSON = try await evaluate("JSON.stringify(Object.fromEntries([...document.documentElement.attributes].filter(a => a.name.startsWith('data-cpm-app-')).map(a => [a.name,a.value])))", in: tab.webView) ?? "{}"
        let marksData = Data(marksJSON.utf8)
        let marks = (try JSONSerialization.jsonObject(with: marksData)) as? [String: String] ?? [:]
        let pageReceived = marks["data-cpm-app-initresp"] != nil
        observations.append(["label": label, "pageMarks": marks, "nativeMethods": native.arrivals.map(\.method)])
        print("CPM APP MARKS \(marks) NATIVE \(native.arrivals.map(\.method))")
        let diagnostics = autoreleasepool {
            manager.cpmDiagnosticsRecorder?.collectDiagnostics(tabIdentifier: tab.uuid).appIntegrationParameters ?? [:]
        }
        let probe = Probe(label: label, url: target, responded: responded, pageReceivedInitResponse: pageReceived,
                          elapsed: Date().timeIntervalSince(started),
                          diagnostics: diagnostics,
                          failures: Array(failureDiagnostics.dropFirst(oldFailures)))
        probes.append(probe)
        print("CPM APP PROBE \(probe.report)")
        return probe
    }

    /// Keep WebKit's non-Sendable Any result inside its callback; only a String crosses suspension.
    private func evaluate(_ script: String, in webView: WKWebView) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: value as? String)
                }
            }
        }
    }

    func waitForIdle() async throws {
        try await wait("WebKit idle unload", timeout: 45) { CPMAppWebKit.background(self.context) == nil
                && self.manager.cpmDiagnosticsRecorder?.snapshot().backgroundWebViewAlive == false
        }
        try await pause(0.5)
    }

    func waitForPageInitResponse(in tab: Tab, timeout: TimeInterval = 2) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try await evaluate("document.documentElement.getAttribute('data-cpm-app-initresp')", in: tab.webView) != nil { return true }
            try await pause(0.05)
        }
        return false
    }

    func observeBackgroundLoadErrors(in context: WKWebExtensionContext) {
        NotificationCenter.default.publisher(for: WKWebExtensionContext.errorsDidUpdateNotification, object: context)
            .sink { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let context = notification.object as? WKWebExtensionContext,
                          context.errors.contains(where: {
                              ($0 as NSError).code == WKWebExtensionContext.Error.Code.backgroundContentFailedToLoad.rawValue
                          }) else { return }
                    self?.backgroundLoadErrorContexts.insert(ObjectIdentifier(context))
                    self?.note(["actualBackgroundLoadError": context.errors.map { ($0 as NSError).code },
                                "diagnosticsAtError": self?.manager.cpmDiagnosticsRecorder?.snapshot().appIntegrationParameters ?? [:]])
                }
            }.store(in: &cancellables)
    }

    func freezeBackground() throws -> Int32 {
        let process = try XCTUnwrap(CPMAppWebKit.process(CPMAppWebKit.background(context)))
        guard kill(process, SIGSTOP) == 0 else { throw failure("SIGSTOP failed for test extension process") }
        frozenProcesses.insert(process)
        observations.append(["action": "SIGSTOP owned background", "pid": process])
        print("CPM APP SIGSTOP background PID \(process)")
        return process
    }

    func resume(_ process: Int32) {
        kill(process, SIGCONT)
        frozenProcesses.remove(process)
    }

    func note(_ value: [String: Any]) { observations.append(value) }

    func attach(to test: XCTestCase) throws {
        let events = pixels.events.compactMap { event -> [String: Any]? in
            guard let metadata = CPMWebExtensionPixelMetadata(event: event) else { return nil }
            return ["name": metadata.name, "parameters": metadata.parameters]
        }
        let report: [String: Any] = ["host": Bundle.main.bundleIdentifier ?? "unknown", "os": ProcessInfo.processInfo.operatingSystemVersionString,
                                     "probes": probes.map(\.report), "events": events, "observations": observations]
        let json = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: json, uniformTypeIdentifier: "public.json")
        attachment.name = "\(test.name)-CPM-app-evidence.json"
        attachment.lifetime = .keepAlways
        test.add(attachment)
    }

    func stop() async {
        guard ownsEnvironment else {
            try? FileManager.default.removeItem(at: directory)
            return
        }
        for process in frozenProcesses { kill(process, SIGCONT) }
        frozenProcesses.removeAll()
        autoreleasepool {
            app.configureWebExtensionsForIntegrationTests(factory: nil)
            for window in windows { window.close() }
            windows.removeAll()
            for manager in generations { manager.unloadAllExtensions() }
            cancellables.removeAll()
            warmup?.stopLoading()
            warmup = nil
            privacyFeatures = nil
        }
        autoreleasepool {
            generations.removeAll()
            installationStore = nil
            failureRecorders.removeAll()
            ownedDataStore = nil
        }
        flags.featuresStub = savedFlags
        server.stop()
        try? await pause(0.2)
        try? FileManager.default.removeItem(at: directory)
    }

    func pause(_ seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    func wait(_ description: String, timeout: TimeInterval, condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !autoreleasepool(invoking: condition) {
            guard Date() < deadline else { throw failure("Timed out waiting for \(description)") }
            try await pause(0.05)
        }
    }

    private func failure(_ description: String) -> NSError {
        NSError(domain: "CPMAppIntegration", code: 1, userInfo: [NSLocalizedDescriptionKey: description])
    }
}

@available(macOS 15.4, *)
@MainActor
class CPMAppIntegrationTestCase: XCTestCase {
    var harness: CPMAppIntegrationHarness?

    // Opt in through the dedicated review-only test scheme.
    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CPM_APP_INTEGRATION"] == "1",
                          "Run the CPM Integration Tests scheme to opt into real app/WebKit process tests")
        harness = try CPMAppIntegrationHarness()
    }

    override func tearDown() async throws {
        if let harness {
            try harness.attach(to: self)
            await harness.stop()
        }
        harness = nil
        try await super.tearDown()
    }

    func start(mainEnabled: Bool = true, embeddedEnabled: Bool = true) async throws -> CPMAppIntegrationHarness {
        let harness = try XCTUnwrap(harness)
        try await harness.start(mainEnabled: mainEnabled, embeddedEnabled: embeddedEnabled)
        return harness
    }

    func assertHealthy(_ probe: CPMAppIntegrationHarness.Probe, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(probe.responded, probe.label, file: file, line: line)
        XCTAssertTrue(probe.pageReceivedInitResponse, probe.label, file: file, line: line)
        XCTAssertTrue(probe.failures.isEmpty, probe.label, file: file, line: line)
    }

    func assertFailed(_ probe: CPMAppIntegrationHarness.Probe, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(probe.responded, probe.label, file: file, line: line)
        XCTAssertFalse(probe.pageReceivedInitResponse, probe.label, file: file, line: line)
        XCTAssertFalse(probe.failures.isEmpty, "Production timeout must emit diagnostics for \(probe.label)", file: file, line: line)
    }
}
#endif
