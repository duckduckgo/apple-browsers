//
//  WebExtensionManagerTests.swift
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

@_spi(Testing) import Persistence
import XCTest
import PrivacyConfig
import WebKit
import ZIPFoundation
@testable import WebExtensions
import WebExtensionsTestSupport

@available(macOS 15.4, iOS 18.4, *)
final class WebExtensionManagerTests: XCTestCase {

    var installedExtensionStoringMock: InstalledWebExtensionStoringMock!
    var storageProvidingMock: WebExtensionStorageProvidingMock!
    var webExtensionLoadingMock: WebExtensionLoadingMock!
    var windowTabProviderMock: WebExtensionWindowTabProvidingMock!
    var lifecycleDelegateMock: WebExtensionLifecycleDelegateMock!
    var configurationMock: WebExtensionConfigurationProvidingMock!
    private var createdTestExtensionDirs: [URL] = []
    private var recordedSleeps: [TimeInterval] = []
    /// Whether the loader had already been asked to unload when each sleep began, so the tests can
    /// tell a wait that precedes the unload from one that follows it.
    private var unloadCalledAtSleepTime: [Bool] = []
    private var currentDate = Date()

    @MainActor
    override func setUp() {
        super.setUp()

        installedExtensionStoringMock = InstalledWebExtensionStoringMock()
        storageProvidingMock = WebExtensionStorageProvidingMock()
        webExtensionLoadingMock = WebExtensionLoadingMock()
        windowTabProviderMock = WebExtensionWindowTabProvidingMock()
        lifecycleDelegateMock = WebExtensionLifecycleDelegateMock()
        configurationMock = WebExtensionConfigurationProvidingMock()
        recordedSleeps = []
        unloadCalledAtSleepTime = []
        currentDate = Date()
    }

    override func tearDown() {
        webExtensionLoadingMock?.cleanupTestExtensions()
        for dir in createdTestExtensionDirs {
            try? FileManager.default.removeItem(at: dir)
        }
        createdTestExtensionDirs.removeAll()
        installedExtensionStoringMock = nil
        storageProvidingMock = nil
        webExtensionLoadingMock = nil
        windowTabProviderMock = nil
        lifecycleDelegateMock = nil
        configurationMock = nil

        super.tearDown()
    }

    // MARK: - Web view configuration

    @MainActor
    func testWhenExtensionsAreAttached_ThenConfigurationUsesController() {
        let manager = makeManager()
        let configuration = WKWebViewConfiguration()

        configuration.attachWebExtensions(of: manager)

        let attachedController = configuration.webExtensionController
        XCTAssertIdentical(attachedController, manager.controller)
    }

    @MainActor
    func testWhenOtherManagerIsAttached_ThenThatManagerAttaches() throws {
        let manager = MockWebExtensionManaging()
        let configuration = WKWebViewConfiguration()

        configuration.attachWebExtensions(of: manager)

        XCTAssertEqual(manager.attachedConfigurations, [configuration])
    }

    // MARK: - Helper

    @MainActor
    private func makeManager(controllerConfiguration: WKWebExtensionController.Configuration? = nil,
                             cpmMessagingHealthMonitor: CPMMessagingHealthMonitoring? = nil,
                             pixelFiring: WebExtensionPixelFiring = NoOpWebExtensionPixelFiring(),
                             isCPMMessagingHangRecoveryEnabled: @escaping @MainActor () -> Bool = { true },
                             isCPMBackgroundLoadRecoveryEnabled: @escaping @MainActor () -> Bool = { true },
                             isCPMBackgroundLoadRestartEnabled: @escaping @MainActor () -> Bool = { false },
                             isCPMStableBaseURLEnabled: @escaping @MainActor () -> Bool = { false },
                             isCPMLateBackgroundDocumentRecoveryEnabled: @escaping @MainActor () -> Bool = { false },
                             isApplicationInBackground: @escaping @MainActor () -> Bool = { false },
                             storageProvider: WebExtensionStorageProviding? = nil,
                             now: @escaping () -> Date = Date.init,
                             bundledExtensionURL: @escaping (EmbeddedWebExtensionDescriptor) -> URL? = { _ in
                                 XCTFail("Unexpected bundled extension lookup")
                                 return nil
                             }) -> WebExtensionManager {
        let manager = WebExtensionManager(
            configuration: configurationMock,
            controllerConfiguration: controllerConfiguration,
            windowTabProvider: windowTabProviderMock,
            storageProvider: storageProvider ?? storageProvidingMock,
            installationStore: installedExtensionStoringMock,
            loader: webExtensionLoadingMock,
            lifecycleDelegate: lifecycleDelegateMock,
            pixelFiring: pixelFiring,
            cpmMessagingHealthMonitor: cpmMessagingHealthMonitor,
            isCPMMessagingHangRecoveryEnabled: isCPMMessagingHangRecoveryEnabled,
            isCPMBackgroundLoadRecoveryEnabled: isCPMBackgroundLoadRecoveryEnabled,
            isCPMBackgroundLoadRestartEnabled: isCPMBackgroundLoadRestartEnabled,
            isApplicationInBackground: isApplicationInBackground,
            isCPMLateBackgroundDocumentRecoveryEnabled: isCPMLateBackgroundDocumentRecoveryEnabled,
            isCPMStableBaseURLEnabled: isCPMStableBaseURLEnabled,
            bundledExtensionURL: bundledExtensionURL,
            now: now
        )
        manager.unloadGuard = WebExtensionUnloadGuard(
            now: { [unowned self] in currentDate },
            sleeper: { [unowned self] in
                recordedSleeps.append($0)
                unloadCalledAtSleepTime.append(webExtensionLoadingMock.unloadExtensionCalled)
            }
        )
        return manager
    }

    private func makeInstalledWebExtension(uniqueIdentifier: String,
                                           filename: String = "extension.zip",
                                           name: String? = nil,
                                           version: String? = nil,
                                           embeddedType: DuckDuckGoWebExtensionType? = nil) -> InstalledWebExtension {
        InstalledWebExtension(
            uniqueIdentifier: uniqueIdentifier,
            filename: filename,
            name: name,
            version: version,
            embeddedType: embeddedType
        )
    }

    /// A permission controller whose prompts the user always approves.
    @MainActor
    private func makePermissionController() -> WebExtensionPermissionController {
        WebExtensionPermissionController(store: WebExtensionPermissionStore(keyValueStore: InMemoryThrowingKeyValueStore()),
                                         installationStore: installedExtensionStoringMock,
                                         prompter: ApprovingPermissionPrompter())
    }

    /// Loads a real (backgroundless) extension context into the controller so that
    /// `unloadAllExtensions()` has something to capture for the lightweight reload tests.
    @MainActor
    @discardableResult
    private func loadRealContext(identifier: String,
                                 into controller: WKWebExtensionController,
                                 permissions: [String] = [],
                                 optionalPermissions: [String] = [],
                                 embeddedType: DuckDuckGoWebExtensionType? = nil) async throws -> WKWebExtensionContext {
        let dir = try makeTestExtensionDirectory(permissions: permissions, optionalPermissions: optionalPermissions, embeddedType: embeddedType)
        let webExtension = try await WKWebExtension(resourceBaseURL: dir)
        let context = WKWebExtensionContext(for: webExtension)
        context.uniqueIdentifier = identifier
        try controller.load(context)
        return context
    }

    private func makeTestExtensionDirectory(permissions: [String] = [],
                                            optionalPermissions: [String] = [],
                                            embeddedType: DuckDuckGoWebExtensionType? = nil) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ReloadTestExtension-\(UUID().uuidString)")
        var manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Reload Test Extension",
            "version": "1.0.0",
            "description": "Minimal backgroundless test extension for reload unit tests",
            "permissions": permissions,
            "optional_permissions": optionalPermissions
        ]
        if let embeddedType {
            manifest["browser_specific_settings"] = ["duckduckgo": ["id": embeddedType.rawValue]]
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: manifest).write(to: dir.appendingPathComponent("manifest.json"))
        createdTestExtensionDirs.append(dir)
        return dir
    }

    // MARK: - Background wake selection and recovery safety

    @MainActor
    func testError6PersistsNextOriginBeforeRetryOrReloadWhileAppIsBackgrounded() async throws {
        for enabled in [false, true] {
            let manager = makeManager(controllerConfiguration: .nonPersistent(),
                                      isCPMMessagingHangRecoveryEnabled: { false },
                                      isCPMBackgroundLoadRecoveryEnabled: { false },
                                      isCPMStableBaseURLEnabled: { enabled },
                                      isApplicationInBackground: { true })
            let context = try await loadDeferredEmbeddedContext(UUID().uuidString, into: manager)
            defer { manager.unloadAllExtensions() }
            let liveOrigin = context.baseURL
            context.recordedErrors = [NSError(domain: WKWebExtensionContext.errorDomain, code: 6)]

            NotificationCenter.default.post(name: WKWebExtensionContext.errorsDidUpdateNotification, object: context)

            let saved = installedExtensionStoringMock.installedExtension(withUniqueIdentifier: context.uniqueIdentifier)?.cpmOriginIdentifier
            if enabled {
                XCTAssertNotNil(saved, "The next-launch origin must be saved synchronously before recovery can run")
            } else {
                XCTAssertNil(saved, "The P3 kill switch must veto error-triggered rotation")
            }
            XCTAssertEqual(context.baseURL, liveOrigin, "Persisting a replacement must not mutate the live context")
            NotificationCenter.default.post(name: WKWebExtensionContext.errorsDidUpdateNotification, object: context)
            XCTAssertEqual(installedExtensionStoringMock.installedExtension(withUniqueIdentifier: context.uniqueIdentifier)?.cpmOriginIdentifier, saved)
            XCTAssertFalse(webExtensionLoadingMock.unloadExtensionCalled)
            XCTAssertTrue(context.completions.isEmpty)
        }
    }

    @MainActor
    private func loadDeferredEmbeddedContext(_ identifier: String, into manager: WebExtensionManager) async throws -> DeferredCPMBackgroundContext {
        let directory = try makeTestExtensionDirectory(embeddedType: .embedded)
        let manifestURL = directory.appendingPathComponent("manifest.json")
        var manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        manifest["manifest_version"] = 2
        manifest["background"] = ["scripts": ["background.js"], "persistent": false]
        try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)
        try "// Background completion ordering fixture".write(to: directory.appendingPathComponent("background.js"), atomically: true, encoding: .utf8)
        let webExtension = try await WKWebExtension(resourceBaseURL: directory)
        let context = DeferredCPMBackgroundContext(for: webExtension)
        context.uniqueIdentifier = identifier
        try manager.controller.load(context)
        installedExtensionStoringMock.add(makeInstalledWebExtension(uniqueIdentifier: identifier, embeddedType: .embedded))
        return context
    }

    @MainActor
    func testFailedFirstStartupCannotReportP4OrReloadAfterRetainedCallbacksSucceed() async throws {
        for lateRecoveryEnabled in [false, true] {
            let pixels = CapturingCPMStartupPixels()
            let monitor = CPMMessagingHealthMonitor(pixelFiring: pixels)
            let manager = makeManager(controllerConfiguration: .nonPersistent(), cpmMessagingHealthMonitor: monitor,
                                      pixelFiring: pixels, isCPMLateBackgroundDocumentRecoveryEnabled: { lateRecoveryEnabled })
            let context = try await loadDeferredEmbeddedContext(UUID().uuidString, into: manager)
            defer { manager.unloadAllExtensions() }
            let startup = try XCTUnwrap(manager.prepareEmbeddedBackgroundForNavigation())
            let url = URL(string: "https://example.com/first")!
            monitor.handle(.navigationStarted(tabIdentifier: "tab", navigationKind: .other))
            monitor.handle(.navigationCommitted(tabIdentifier: "tab", url: url))
            var preflightCalls = 0
            try XCTUnwrap(monitor.backgroundReadinessRecovery).registerDocument(in: "tab") {
                preflightCalls += 1
                return nil
            }
            monitor.reportFailure(monitor.beginMeasurement(tabIdentifier: "tab", navigationKind: .other))
            let retryStarted = expectation(description: "Error 6 starts a background-only retry")
            context.onBackgroundLoad = { retryStarted.fulfill() }
            context.recordedErrors = [NSError(domain: "WKWebExtensionContextErrorDomain", code: 6)]
            NotificationCenter.default.post(name: WKWebExtensionContext.errorsDidUpdateNotification, object: context)
            await fulfillment(of: [retryStarted], timeout: 2)
            XCTAssertEqual(context.completions.count, 2)
            // WebKit can retain the failed load's callback and complete it successfully with the retry.
            context.finishBackgroundLoads()
            await startup.value
            for _ in 0..<10 { await Task.yield() }
            XCTAssertEqual(pixels.missingResponseCount, 0)
            XCTAssertEqual(preflightCalls, 0, "A known failed startup must not trigger document recovery")
            monitor.handle(.tabClosed(tabIdentifier: "tab"))
        }
    }

    @MainActor
    func testUnrelatedErrorPreservesCurrentFirstStartupDetection() async throws {
        for errorOnCurrentContext in [false, true] {
            let pixels = CapturingCPMStartupPixels()
            let monitor = CPMMessagingHealthMonitor(pixelFiring: pixels)
            let manager = makeManager(controllerConfiguration: .nonPersistent(), cpmMessagingHealthMonitor: monitor, pixelFiring: pixels)
            let old = try await loadDeferredEmbeddedContext("old", into: manager)
            let replacement = try await loadDeferredEmbeddedContext("replacement", into: manager)
            defer { manager.unloadAllExtensions() }
            let startup = try XCTUnwrap(manager.prepareEmbeddedBackgroundForNavigation())
            monitor.handle(.navigationStarted(tabIdentifier: "tab", navigationKind: .other))
            monitor.handle(.navigationCommitted(tabIdentifier: "tab", url: URL(string: "https://example.com/first")!))
            monitor.reportFailure(monitor.beginMeasurement(tabIdentifier: "tab", navigationKind: .other))
            let source = errorOnCurrentContext ? replacement : old
            let domain = errorOnCurrentContext ? "UnrelatedErrorDomain" : "WKWebExtensionContextErrorDomain"
            source.recordedErrors = [NSError(domain: domain, code: 6)]
            NotificationCenter.default.post(name: WKWebExtensionContext.errorsDidUpdateNotification, object: source)
            for _ in 0..<10 { await Task.yield() }
            XCTAssertEqual(manager.pendingEmbeddedBackgroundStartup, startup)
            XCTAssertEqual(old.completions.count, 0, "An obsolete context must not be retried")
            replacement.finishBackgroundLoads()
            await startup.value
            XCTAssertEqual(pixels.missingResponseCount, 1)
            monitor.handle(.tabClosed(tabIdentifier: "tab"))
        }
    }

    @MainActor
    private func loadEmbeddedContext(_ identifier: String, into manager: WebExtensionManager) async throws -> WKWebExtensionContext {
        let directory = try makeTestExtensionDirectory(embeddedType: .embedded)
        let webExtension = try await WKWebExtension(resourceBaseURL: directory)
        let context = WKWebExtensionContext(for: webExtension)
        context.uniqueIdentifier = identifier
        try manager.controller.load(context)
        installedExtensionStoringMock.add(makeInstalledWebExtension(uniqueIdentifier: identifier, embeddedType: .embedded))
        return context
    }

    @MainActor
    func testNavigationSelectsNewInstallationWhileOldContextStillExists() async throws {
        let manager = makeManager()
        let oldContext = try await loadEmbeddedContext("old", into: manager)
        let replacement = try await loadEmbeddedContext("replacement", into: manager)
        XCTAssertEqual(manager.controller.extensionContexts.count, 2)
        XCTAssertTrue(manager.embeddedBackgroundContextForNavigation === replacement)
        XCTAssertFalse(manager.embeddedBackgroundContextForNavigation === oldContext)
        manager.unloadAllExtensions()
    }

    @MainActor
    func testNavigationFallsBackWhenReplacementContextIsRemoved() async throws {
        let manager = makeManager()
        let original = try await loadEmbeddedContext("original", into: manager)
        let replacement = try await loadEmbeddedContext("replacement", into: manager)
        try manager.controller.unload(replacement)
        installedExtensionStoringMock.remove(uniqueIdentifier: replacement.uniqueIdentifier)
        XCTAssertTrue(manager.embeddedBackgroundContextForNavigation === original)
        manager.unloadAllExtensions()
    }

    @MainActor
    func testBackgroundRecoveryWithoutDiagnosticsSkipsBackgroundAndAllowsForeground() async throws {
        var isBackground = true
        let manager = makeManager(isApplicationInBackground: { isBackground })
        let context = try await loadEmbeddedContext("embedded", into: manager)
        let error = NSError(domain: "WKWebExtensionContextErrorDomain", code: 6)
        XCTAssertNil(manager.cpmDiagnosticsRecorder)
        let skipped = manager.recoverEmbeddedBackgroundLoadFailure(error, context: context)
        XCTAssertFalse(skipped)
        isBackground = false
        let scheduled = manager.recoverEmbeddedBackgroundLoadFailure(error, context: context)
        XCTAssertTrue(scheduled, "Skipping in background must not consume the foreground retry")
        let throttled = manager.recoverEmbeddedBackgroundLoadFailure(error, context: context)
        XCTAssertFalse(throttled)
        manager.unloadAllExtensions()
    }

    @MainActor
    func testBackgroundRecoveryHonorsRuntimeKillSwitchWithoutDiagnostics() async throws {
        var isEnabled = false
        let manager = makeManager(isCPMBackgroundLoadRecoveryEnabled: { isEnabled })
        let context = try await loadEmbeddedContext("embedded", into: manager)
        let error = NSError(domain: "WKWebExtensionContextErrorDomain", code: 6)
        let skipped = manager.recoverEmbeddedBackgroundLoadFailure(error, context: context)
        XCTAssertFalse(skipped)
        isEnabled = true
        let scheduled = manager.recoverEmbeddedBackgroundLoadFailure(error, context: context)
        XCTAssertTrue(scheduled)
        manager.unloadAllExtensions()
    }

    @MainActor
    func testBackgroundLoadRecoveryWorksWithHangRecoveryDisabled() async throws {
        let manager = makeManager(controllerConfiguration: .nonPersistent(),
                                  isCPMMessagingHangRecoveryEnabled: { false },
                                  isCPMBackgroundLoadRecoveryEnabled: { true })
        let context = try await loadDeferredEmbeddedContext("embedded", into: manager)
        defer { manager.unloadAllExtensions() }
        let retried = expectation(description: "Background-only recovery is independent of the restart flag")
        context.onBackgroundLoad = { retried.fulfill() }

        let scheduled = manager.recoverEmbeddedBackgroundLoadFailure(
            NSError(domain: "WKWebExtensionContextErrorDomain", code: 6), context: context)

        XCTAssertTrue(scheduled)
        await fulfillment(of: [retried], timeout: 2)
        let startup = try XCTUnwrap(manager.pendingEmbeddedBackgroundStartup)
        XCTAssertEqual(context.completions.count, 1)
        XCTAssertFalse(webExtensionLoadingMock.unloadExtensionCalled)
        XCTAssertFalse(webExtensionLoadingMock.loadWebExtensionCalled)
        context.finishBackgroundLoads()
        await startup.value
    }

    /// WebKit's `loadBackgroundWebViewIfNeeded` returns early while the failed background view still exists,
    /// so `loadBackgroundContent` can never replace it. Only restarting the context gets out of that state.
    @MainActor
    func testRetainedFailedBackgroundViewRestartsContextInsteadOfRetrying() async throws {
        let manager = makeManager(controllerConfiguration: .nonPersistent(),
                                  isCPMBackgroundLoadRecoveryEnabled: { true },
                                  isCPMBackgroundLoadRestartEnabled: { true })
        let context = try await loadDeferredEmbeddedContext("embedded", into: manager)
        defer { manager.unloadAllExtensions() }
        context.retainedBackgroundWebView = WKWebView()
        let reloaded = expectation(description: "A retained failed background view restarts the context")
        let observer = Task { @MainActor in
            for await event in manager.lifecycleEvents {
                guard case .reloaded(let identifier, _, _) = event, identifier == "embedded" else { continue }
                reloaded.fulfill()
                return
            }
        }
        defer { observer.cancel() }

        let scheduled = manager.recoverEmbeddedBackgroundLoadFailure(
            NSError(domain: "WKWebExtensionContextErrorDomain", code: 6), context: context)

        XCTAssertTrue(scheduled)
        await fulfillment(of: [reloaded], timeout: 3)
        XCTAssertTrue(webExtensionLoadingMock.unloadExtensionCalled, "The failed view is replaced by unloading its context")
        XCTAssertEqual(webExtensionLoadingMock.loadedIdentifiers, ["embedded"])
        observer.cancel()
        await observer.value
    }

    @MainActor
    func testError6DoesNotRestartBackgroundReplacedBeforeQueuedRecovery() async throws {
        try await assertError6DoesNotRestartNewBackground(retainedFailedView: true)
    }

    @MainActor
    func testError6DoesNotRestartNewBackgroundWhenFailedViewWasReleased() async throws {
        try await assertError6DoesNotRestartNewBackground(retainedFailedView: false)
    }

    @MainActor
    private func assertError6DoesNotRestartNewBackground(retainedFailedView: Bool) async throws {
        let manager = makeManager(controllerConfiguration: .nonPersistent(),
                                  isCPMBackgroundLoadRestartEnabled: { true })
        let context = try await loadDeferredEmbeddedContext("embedded", into: manager)
        defer { manager.unloadAllExtensions() }
        context.retainedBackgroundWebView = retainedFailedView ? WKWebView() : nil
        context.recordedErrors = [NSError(domain: "WKWebExtensionContextErrorDomain", code: 6)]

        NotificationCenter.default.post(name: WKWebExtensionContext.errorsDidUpdateNotification, object: context)
        // WebKit replaces the failed view before the queued recovery gets its main-actor turn.
        let replacement = WKWebView()
        context.retainedBackgroundWebView = replacement
        context.recordedErrors = []
        let restarted = expectation(description: "A self-recovered background must not be restarted")
        restarted.isInverted = true
        let observer = Task { @MainActor in
            for await event in manager.lifecycleEvents {
                if case .reloaded = event { restarted.fulfill() }
            }
        }
        defer { observer.cancel() }

        await fulfillment(of: [restarted], timeout: 0.2)

        XCTAssertFalse(webExtensionLoadingMock.unloadExtensionCalled)
        XCTAssertIdentical(context.retainedBackgroundWebView, replacement)
        XCTAssertTrue(context.completions.isEmpty, "Do not disturb the replacement with another load request")
    }

    @MainActor
    func testHistoricalError6NotificationDoesNotRestartHealthyBackground() async throws {
        var recoveryEnabled = false
        let manager = makeManager(controllerConfiguration: .nonPersistent(),
                                  isCPMBackgroundLoadRecoveryEnabled: { recoveryEnabled },
                                  isCPMBackgroundLoadRestartEnabled: { true })
        let context = try await loadDeferredEmbeddedContext("embedded", into: manager)
        defer { manager.unloadAllExtensions() }
        let error = NSError(domain: WKWebExtensionContext.errorDomain, code: 6)
        context.recordedErrors = [error]
        NotificationCenter.default.post(name: WKWebExtensionContext.errorsDidUpdateNotification, object: context)

        // Recovery can happen independently while WebKit keeps the historical error entry.
        let healthyView = WKWebView()
        context.retainedBackgroundWebView = healthyView
        recoveryEnabled = true
        context.recordedErrors = [NSError(domain: WKWebExtensionContext.errorDomain, code: 6), NSError(domain: "unrelated", code: 1)]
        NotificationCenter.default.post(name: WKWebExtensionContext.errorsDidUpdateNotification, object: context)
        let restarted = expectation(description: "Historical error must not restart a healthy context")
        restarted.isInverted = true
        let observer = Task { @MainActor in
            for await event in manager.lifecycleEvents {
                if case .reloaded = event { restarted.fulfill() }
            }
        }
        defer { observer.cancel() }
        await fulfillment(of: [restarted], timeout: 0.2)
        XCTAssertFalse(webExtensionLoadingMock.unloadExtensionCalled)
        XCTAssertIdentical(context.retainedBackgroundWebView, healthyView)
        XCTAssertTrue(context.completions.isEmpty)
    }

    @MainActor
    func testAdditionalEqualError6StillRestartsRetainedBackground() async throws {
        try await assertNewError6RestartsRetainedBackground(removeHistoricalError: false)
    }

    @MainActor
    func testError6ReappearingAfterRemovalStillRestartsRetainedBackground() async throws {
        try await assertNewError6RestartsRetainedBackground(removeHistoricalError: true)
    }

    @MainActor
    private func assertNewError6RestartsRetainedBackground(removeHistoricalError: Bool) async throws {
        var recoveryEnabled = false
        let manager = makeManager(controllerConfiguration: .nonPersistent(),
                                  isCPMBackgroundLoadRecoveryEnabled: { recoveryEnabled },
                                  isCPMBackgroundLoadRestartEnabled: { true })
        let context = try await loadDeferredEmbeddedContext("embedded", into: manager)
        defer { manager.unloadAllExtensions() }
        let error = NSError(domain: WKWebExtensionContext.errorDomain, code: 6)
        context.recordedErrors = [error]
        NotificationCenter.default.post(name: WKWebExtensionContext.errorsDidUpdateNotification, object: context)
        if removeHistoricalError {
            context.recordedErrors = []
            NotificationCenter.default.post(name: WKWebExtensionContext.errorsDidUpdateNotification, object: context)
        }
        recoveryEnabled = true
        context.retainedBackgroundWebView = WKWebView()
        let restarted = expectation(description: "A new failure must still restart the retained view")
        context.onBackgroundLoad = { restarted.fulfill() }
        context.recordedErrors = removeHistoricalError ? [error] : [error, error]
        NotificationCenter.default.post(name: WKWebExtensionContext.errorsDidUpdateNotification, object: context)
        await fulfillment(of: [restarted], timeout: 2)
        XCTAssertTrue(webExtensionLoadingMock.unloadExtensionCalled)
        context.finishBackgroundLoads()
    }

    @MainActor
    func testQueuedError6RestartHonorsRuntimeKillSwitch() async throws {
        var restartEnabled = true
        let manager = makeManager(controllerConfiguration: .nonPersistent(),
                                  isCPMBackgroundLoadRestartEnabled: { restartEnabled })
        let context = try await loadDeferredEmbeddedContext("embedded", into: manager)
        defer { manager.unloadAllExtensions() }
        context.retainedBackgroundWebView = WKWebView()
        let retried = expectation(description: "Disabling restart before execution keeps the plain retry")
        context.onBackgroundLoad = { retried.fulfill() }
        XCTAssertTrue(manager.recoverEmbeddedBackgroundLoadFailure(
            NSError(domain: "WKWebExtensionContextErrorDomain", code: 6), context: context))
        restartEnabled = false

        await fulfillment(of: [retried], timeout: 1)
        XCTAssertFalse(webExtensionLoadingMock.unloadExtensionCalled)
        context.finishBackgroundLoads()
    }

    @MainActor
    func testError6RestartBackgroundReadinessDoesNotClaimPageRecovery() async throws {
        let pixels = CapturingCPMRestartPixels()
        let manager = makeManager(controllerConfiguration: .nonPersistent(), pixelFiring: pixels,
                                  isCPMBackgroundLoadRestartEnabled: { true })
        let context = try await loadDeferredEmbeddedContext("embedded", into: manager)
        defer { manager.unloadAllExtensions() }
        context.retainedBackgroundWebView = WKWebView()
        let requested = expectation(description: "Replacement background load requested")
        context.onBackgroundLoad = { requested.fulfill() }
        XCTAssertTrue(manager.recoverEmbeddedBackgroundLoadFailure(
            NSError(domain: "WKWebExtensionContextErrorDomain", code: 6), context: context))
        await fulfillment(of: [requested], timeout: 2)
        XCTAssertEqual(pixels.outcomes, [.restartStarted])

        context.finishBackgroundLoads()

        XCTAssertEqual(pixels.outcomes, [.restartStarted, .backgroundReady])
        XCTAssertFalse(pixels.outcomes.contains(.responseReceived), "Only a dashboard response proves messaging recovery")
    }

    @MainActor
    func testError6RestartReportsContextReloadFailure() async throws {
        let pixels = CapturingCPMRestartPixels()
        let manager = makeManager(controllerConfiguration: .nonPersistent(), pixelFiring: pixels,
                                  isCPMBackgroundLoadRestartEnabled: { true })
        let context = try await loadDeferredEmbeddedContext("embedded", into: manager)
        defer { manager.unloadAllExtensions() }
        context.retainedBackgroundWebView = WKWebView()
        webExtensionLoadingMock.mockUnloadError = NSError(domain: "test", code: 1)
        let failed = expectation(description: "Failed context replacement is reported")
        pixels.onOutcome = { if $0 == .reloadFailed { failed.fulfill() } }
        XCTAssertTrue(manager.recoverEmbeddedBackgroundLoadFailure(
            NSError(domain: "WKWebExtensionContextErrorDomain", code: 6), context: context))
        await fulfillment(of: [failed], timeout: 2)

        XCTAssertEqual(pixels.outcomes, [.restartStarted, .reloadFailed])
    }

    @MainActor
    func testRetainedFailedBackgroundViewKeepsPlainRetryWhenRestartFlagIsOff() async throws {
        let manager = makeManager(controllerConfiguration: .nonPersistent(),
                                  isCPMBackgroundLoadRecoveryEnabled: { true },
                                  isCPMBackgroundLoadRestartEnabled: { false })
        let context = try await loadDeferredEmbeddedContext("embedded", into: manager)
        defer { manager.unloadAllExtensions() }
        context.retainedBackgroundWebView = WKWebView()
        let retried = expectation(description: "With the restart flag off the plain retry is kept")
        context.onBackgroundLoad = { retried.fulfill() }

        let scheduled = manager.recoverEmbeddedBackgroundLoadFailure(
            NSError(domain: "WKWebExtensionContextErrorDomain", code: 6), context: context)

        XCTAssertTrue(scheduled)
        await fulfillment(of: [retried], timeout: 2)
        XCTAssertFalse(webExtensionLoadingMock.unloadExtensionCalled, "The restart flag must veto the context reload")
        context.finishBackgroundLoads()
    }

    @MainActor
    func testReleasedFailedBackgroundViewStillRetriesWithoutRestartingContext() async throws {
        let manager = makeManager(controllerConfiguration: .nonPersistent(),
                                  isCPMBackgroundLoadRecoveryEnabled: { true },
                                  isCPMBackgroundLoadRestartEnabled: { true })
        let context = try await loadDeferredEmbeddedContext("embedded", into: manager)
        defer { manager.unloadAllExtensions() }
        XCTAssertNil(context.retainedBackgroundWebView)
        let retried = expectation(description: "A released failed view is replaced by the plain retry")
        context.onBackgroundLoad = { retried.fulfill() }

        let scheduled = manager.recoverEmbeddedBackgroundLoadFailure(
            NSError(domain: "WKWebExtensionContextErrorDomain", code: 6), context: context)

        XCTAssertTrue(scheduled)
        await fulfillment(of: [retried], timeout: 2)
        XCTAssertFalse(webExtensionLoadingMock.unloadExtensionCalled)
        context.finishBackgroundLoads()
    }

    @MainActor
    func testDisabledBackgroundLoadRecoveryPreservesConfirmedHangRestart() async throws {
        let monitor = CPMMessagingHealthMonitor(pixelFiring: NoOpWebExtensionPixelFiring())
        let manager = makeManager(cpmMessagingHealthMonitor: monitor,
                                  isCPMMessagingHangRecoveryEnabled: { true },
                                  isCPMBackgroundLoadRecoveryEnabled: { false })
        let context = try await loadEmbeddedContext("embedded", into: manager)
        defer { manager.unloadAllExtensions() }
        let reloaded = expectation(description: "Confirmed-hang restart retains its own flag")
        let observer = Task { @MainActor in
            for await event in manager.lifecycleEvents
                where event == .reloaded(identifier: "embedded", type: .embedded, trigger: .cpmMessagingHang) {
                reloaded.fulfill()
                return
            }
        }
        defer { observer.cancel() }
        let scheduled = manager.recoverEmbeddedBackgroundLoadFailure(
            NSError(domain: "WKWebExtensionContextErrorDomain", code: 6), context: context)
        XCTAssertFalse(scheduled)
        XCTAssertFalse(webExtensionLoadingMock.unloadExtensionCalled)

        monitor.onConfirmedHang?()

        await fulfillment(of: [reloaded], timeout: 3)
        XCTAssertTrue(webExtensionLoadingMock.unloadExtensionCalled)
        XCTAssertEqual(webExtensionLoadingMock.loadedIdentifiers, ["embedded"])
        observer.cancel()
        await observer.value
    }

    @MainActor
    func testBackgroundLoadRecoveryRechecksItsFlagBeforeDeferredExecution() async throws {
        var enabled = true
        let manager = makeManager(controllerConfiguration: .nonPersistent(),
                                  isCPMMessagingHangRecoveryEnabled: { true },
                                  isCPMBackgroundLoadRecoveryEnabled: { enabled })
        let context = try await loadDeferredEmbeddedContext("embedded", into: manager)
        defer { manager.unloadAllExtensions() }
        let retried = expectation(description: "Disabling the retry flag vetoes queued recovery")
        retried.isInverted = true
        context.onBackgroundLoad = { retried.fulfill() }
        let scheduled = manager.recoverEmbeddedBackgroundLoadFailure(
            NSError(domain: "WKWebExtensionContextErrorDomain", code: 6), context: context)
        XCTAssertTrue(scheduled)
        enabled = false

        await fulfillment(of: [retried], timeout: 0.2)

        XCTAssertTrue(context.completions.isEmpty)
        XCTAssertNil(manager.pendingEmbeddedBackgroundStartup)
    }

    @MainActor
    func testError6NotificationHonorsBackgroundLoadRecoveryFlagWithRestartEnabled() async throws {
        let manager = makeManager(controllerConfiguration: .nonPersistent(),
                                  isCPMMessagingHangRecoveryEnabled: { true },
                                  isCPMBackgroundLoadRecoveryEnabled: { false })
        let context = try await loadDeferredEmbeddedContext("embedded", into: manager)
        defer { manager.unloadAllExtensions() }
        let startup = try XCTUnwrap(manager.prepareEmbeddedBackgroundForNavigation())
        let retried = expectation(description: "Error notification must not bypass the retry flag")
        retried.isInverted = true
        context.onBackgroundLoad = { retried.fulfill() }
        context.recordedErrors = [NSError(domain: "WKWebExtensionContextErrorDomain", code: 6)]

        NotificationCenter.default.post(name: WKWebExtensionContext.errorsDidUpdateNotification, object: context)

        await fulfillment(of: [retried], timeout: 0.2)
        XCTAssertEqual(context.completions.count, 1)
        XCTAssertNil(manager.pendingEmbeddedBackgroundStartup)
        context.finishBackgroundLoads()
        await startup.value
        XCTAssertFalse(webExtensionLoadingMock.unloadExtensionCalled)
    }

    @MainActor
    func testBackgroundRecoveryIgnoresSupersededContextDuringUpgrade() async throws {
        let manager = makeManager()
        let oldContext = try await loadEmbeddedContext("old", into: manager)
        let replacement = try await loadEmbeddedContext("replacement", into: manager)
        let error = NSError(domain: "WKWebExtensionContextErrorDomain", code: 6)
        let skipped = manager.recoverEmbeddedBackgroundLoadFailure(error, context: oldContext)
        XCTAssertFalse(skipped)
        let scheduled = manager.recoverEmbeddedBackgroundLoadFailure(error, context: replacement)
        XCTAssertTrue(scheduled)
        manager.unloadAllExtensions()
    }

    @MainActor
    func testUninstallingActiveEmbeddedContextCancelsPendingDocumentRecovery() async throws {
        try await verifyUninstallDuringDocumentRecovery(removingSupersededContext: false, unloadFails: false)
    }

    @MainActor
    func testUninstallingOldEmbeddedContextPreservesReplacementDocumentRecovery() async throws {
        try await verifyUninstallDuringDocumentRecovery(removingSupersededContext: true, unloadFails: false)
    }

    @MainActor
    func testFailedUninstallPreservesActiveDocumentRecovery() async throws {
        try await verifyUninstallDuringDocumentRecovery(removingSupersededContext: false, unloadFails: true)
    }

    @MainActor
    private func verifyUninstallDuringDocumentRecovery(removingSupersededContext: Bool, unloadFails: Bool) async throws {
        let monitor = CPMMessagingHealthMonitor(pixelFiring: NoOpWebExtensionPixelFiring())
        let manager = WebExtensionManager(
            configuration: configurationMock,
            windowTabProvider: windowTabProviderMock,
            storageProvider: storageProvidingMock,
            installationStore: installedExtensionStoringMock,
            loader: unloadFails ? webExtensionLoadingMock : nil,
            cpmMessagingHealthMonitor: monitor,
            isCPMLateBackgroundDocumentRecoveryEnabled: { true }
        )
        let original = try await loadEmbeddedContext("original", into: manager)
        if removingSupersededContext {
            _ = try await loadEmbeddedContext("replacement", into: manager)
        }
        let recovery = try XCTUnwrap(monitor.backgroundReadinessRecovery)
        let startup = UUID()
        recovery.backgroundStarted(startup)
        recovery.navigationStarted(in: "tab")
        recovery.navigationCommitted(in: "tab", url: URL(string: "https://example.com/page")!)
        var completeCheck: CheckedContinuation<CPMBackgroundReadinessRecovery.Reload?, Never>?
        recovery.registerDocument(in: "tab") { await withCheckedContinuation { completeCheck = $0 } }
        recovery.initializationFailed(in: "tab")
        recovery.backgroundCompleted(startup, succeeded: true)
        while completeCheck == nil { await Task.yield() }

        if unloadFails {
            webExtensionLoadingMock.mockUnloadError = NSError(domain: "Test", code: 1)
            XCTAssertThrowsError(try manager.uninstallExtension(identifier: original.uniqueIdentifier))
            XCTAssertTrue(manager.context(for: original.uniqueIdentifier) === original)
        } else {
            try manager.uninstallExtension(identifier: original.uniqueIdentifier)
            XCTAssertNil(manager.context(for: original.uniqueIdentifier), "The production loader must actually unload the context")
            XCTAssertNil(installedExtensionStoringMock.installedExtension(withUniqueIdentifier: original.uniqueIdentifier))
        }

        let shouldReload = removingSupersededContext || unloadFails
        let reload = expectation(description: "Only removal of the active context cancels its recovery")
        reload.isInverted = !shouldReload
        completeCheck?.resume(returning: { reload.fulfill(); return nil })
        await fulfillment(of: [reload], timeout: 0.2)
        manager.unloadAllExtensions()
    }

    // MARK: - Install Extension Tests

    @MainActor
    func testWhenExtensionIsInstalled_ThenStorageProviderIsCalled() async throws {
        let manager = makeManager()
        let sourceURL = try createTestWebExtension()

        try await manager.installExtension(from: sourceURL)

        XCTAssertTrue(storageProvidingMock.copyExtensionCalled)
        XCTAssertEqual(storageProvidingMock.copyExtensionSourceURL, sourceURL)
    }

    @MainActor
    func testWhenExtensionIsInstalled_ThenExtensionIsStored() async throws {
        let manager = makeManager()
        let sourceURL = try createTestWebExtension()

        try await manager.installExtension(from: sourceURL)

        XCTAssertTrue(installedExtensionStoringMock.addCalled)
        XCTAssertNotNil(installedExtensionStoringMock.addedExtension?.uniqueIdentifier)
        XCTAssertEqual(storageProvidingMock.copyExtensionIdentifier, installedExtensionStoringMock.addedExtension?.uniqueIdentifier)
    }

    @MainActor
    func testWhenPermissionsAreDisabled_ThenDDGIdentityIsPreservedWithoutBundleLookup() async throws {
        let manager = makeManager()
        let sourceURL = try makeTestExtensionDirectory(embeddedType: .embedded)

        try await manager.installExtension(from: sourceURL)

        XCTAssertEqual(installedExtensionStoringMock.addedExtension?.embeddedType, .embedded)
    }

    @MainActor
    func testWhenExtensionIsInstalled_ThenLoaderIsCalled() async throws {
        let manager = makeManager()
        let sourceURL = try createTestWebExtension()

        try await manager.installExtension(from: sourceURL)

        XCTAssertTrue(webExtensionLoadingMock.loadWebExtensionCalled)
    }

    @MainActor
    func testWhenExtensionIsInstalled_ThenLifecycleDelegateDidUpdateIsCalled() async throws {
        let manager = makeManager()
        let sourceURL = try createTestWebExtension()

        try await manager.installExtension(from: sourceURL)

        XCTAssertTrue(lifecycleDelegateMock.didUpdateExtensionsCalled)
    }

    @MainActor
    func testWhenInstallFails_ThenStorageIsCleanedUp() async throws {
        let manager = makeManager()
        let sourceURL = try createTestWebExtension()
        webExtensionLoadingMock.mockError = NSError(domain: "test", code: 1)

        do {
            try await manager.installExtension(from: sourceURL)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertFalse(installedExtensionStoringMock.addCalled)
            XCTAssertTrue(storageProvidingMock.removeExtensionCalled)
        }
    }

    @MainActor
    func testStoreExtensionInstallationNotifiesWithStoreIDAfterStateUpdate() async throws {
        let manager = makeManager()
        let sourceURL = try createTestWebExtension()
        let identity = WebExtensionStoreIdentity(store: .chromeWebStore, id: String(repeating: "a", count: 32))
        let store = installedExtensionStoringMock!
        let changed = expectation(forNotification: .chromeWebStoreExtensionChanged, object: manager) { notification in
            XCTAssertEqual(notification.userInfo?["extensionId"] as? String, identity.id)
            XCTAssertEqual(store.installedExtensions.first?.storeIdentity, identity)
            return true
        }

        try await manager.installExtension(from: sourceURL, storeIdentity: identity)

        await fulfillment(of: [changed], timeout: 1)
    }

    @MainActor
    func testNonStoreExtensionInstallationDoesNotSendStoreNotification() async throws {
        let manager = makeManager()
        let sourceURL = try createTestWebExtension()
        let changed = expectation(forNotification: .chromeWebStoreExtensionChanged, object: manager)
        changed.isInverted = true

        try await manager.installExtension(from: sourceURL)

        await fulfillment(of: [changed], timeout: 0.01)
    }

    @MainActor
    func testFailedStoreExtensionInstallationDoesNotSendChangeNotification() async throws {
        let manager = makeManager()
        let sourceURL = try createTestWebExtension()
        webExtensionLoadingMock.mockError = NSError(domain: "test", code: 1)
        let changed = expectation(forNotification: .chromeWebStoreExtensionChanged, object: manager)
        changed.isInverted = true

        do {
            try await manager.installExtension(
                from: sourceURL,
                storeIdentity: .init(store: .chromeWebStore, id: String(repeating: "a", count: 32))
            )
            XCTFail("Expected installation to fail")
        } catch {
            XCTAssertTrue(installedExtensionStoringMock.installedExtensions.isEmpty)
        }

        await fulfillment(of: [changed], timeout: 0.01)
    }

    // MARK: - Uninstall Extension Tests

    @MainActor
    func testWhenExtensionIsUninstalled_ThenIdentifierIsRemovedFromStore() throws {
        let manager = makeManager()
        let identifier = "extension.zip"
        installedExtensionStoringMock.installedExtensions = [makeInstalledWebExtension(uniqueIdentifier: identifier)]

        try manager.uninstallExtension(identifier: identifier)

        XCTAssertTrue(installedExtensionStoringMock.removeCalled)
        XCTAssertEqual(installedExtensionStoringMock.removedIdentifier, identifier)
    }

    @MainActor
    func testWhenExtensionIsUninstalled_ThenLoaderUnloadIsCalled() throws {
        let manager = makeManager()
        let identifier = "extension.zip"
        installedExtensionStoringMock.installedExtensions = [makeInstalledWebExtension(uniqueIdentifier: identifier)]

        try manager.uninstallExtension(identifier: identifier)

        XCTAssertTrue(webExtensionLoadingMock.unloadExtensionCalled)
        XCTAssertEqual(webExtensionLoadingMock.unloadedIdentifier, identifier)
    }

    @MainActor
    func testWhenExtensionIsUninstalled_ThenStorageProviderRemovesExtension() throws {
        let manager = makeManager()
        let identifier = "extension.zip"
        installedExtensionStoringMock.installedExtensions = [makeInstalledWebExtension(uniqueIdentifier: identifier)]

        try manager.uninstallExtension(identifier: identifier)

        XCTAssertTrue(storageProvidingMock.removeExtensionCalled)
        XCTAssertEqual(storageProvidingMock.removeExtensionIdentifier, identifier)
    }

    @MainActor
    func testWhenExtensionIsUninstalled_ThenLifecycleDelegateDidUpdateIsCalled() throws {
        let manager = makeManager()
        let identifier = "extension.zip"
        installedExtensionStoringMock.installedExtensions = [makeInstalledWebExtension(uniqueIdentifier: identifier)]

        try manager.uninstallExtension(identifier: identifier)

        XCTAssertTrue(lifecycleDelegateMock.didUpdateExtensionsCalled)
    }

    @MainActor
    func testStoreExtensionRemovalNotifiesWithStoreIDAfterStateUpdate() throws {
        let manager = makeManager()
        let storeID = String(repeating: "a", count: 32)
        let store = installedExtensionStoringMock!
        store.installedExtensions = [InstalledWebExtension(uniqueIdentifier: "local-id", filename: "extension.zip",
                                                          name: nil, version: nil, storeIdentity: .init(store: .chromeWebStore, id: storeID))]
        let removed = expectation(forNotification: .chromeWebStoreExtensionChanged, object: manager) { notification in
            XCTAssertEqual(notification.userInfo?["extensionId"] as? String, storeID)
            XCTAssertTrue(store.installedExtensions.isEmpty)
            return true
        }

        try manager.uninstallExtension(identifier: "local-id")

        wait(for: [removed], timeout: 1)
    }

    @MainActor
    func testNonStoreExtensionRemovalDoesNotSendStoreNotification() throws {
        let manager = makeManager()
        installedExtensionStoringMock.installedExtensions = [makeInstalledWebExtension(uniqueIdentifier: "local-id")]
        let removed = expectation(forNotification: .chromeWebStoreExtensionChanged, object: manager)
        removed.isInverted = true

        try manager.uninstallExtension(identifier: "local-id")

        wait(for: [removed], timeout: 0.01)
    }

    @MainActor
    func testFailedStoreExtensionRemovalDoesNotSendSuccessNotification() {
        let manager = makeManager()
        installedExtensionStoringMock.installedExtensions = [
            InstalledWebExtension(uniqueIdentifier: "local-id", filename: "extension.zip", name: nil, version: nil,
                                  storeIdentity: .init(store: .chromeWebStore, id: String(repeating: "a", count: 32)))
        ]
        storageProvidingMock.mockRemoveError = NSError(domain: "test", code: 1)
        let removed = expectation(forNotification: .chromeWebStoreExtensionChanged, object: manager)
        removed.isInverted = true

        XCTAssertThrowsError(try manager.uninstallExtension(identifier: "local-id"))

        wait(for: [removed], timeout: 0.01)
    }

    // MARK: - Uninstall All Extensions Tests

    @MainActor
    func testWhenUninstallAllExtensions_ThenAllIdentifiersAreUninstalled() {
        let manager = makeManager()
        installedExtensionStoringMock.installedExtensions = [
            makeInstalledWebExtension(uniqueIdentifier: "extension1.zip"),
            makeInstalledWebExtension(uniqueIdentifier: "extension2.zip")
        ]

        let results = manager.uninstallAllExtensions()

        XCTAssertEqual(results.count, 2)
    }

    @MainActor
    func testWhenUninstallAllExtensions_ThenResultsContainSuccessAndFailures() {
        let manager = makeManager()
        installedExtensionStoringMock.installedExtensions = [
            makeInstalledWebExtension(uniqueIdentifier: "extension1.zip"),
            makeInstalledWebExtension(uniqueIdentifier: "extension2.zip")
        ]

        let results = manager.uninstallAllExtensions()

        for result in results {
            switch result {
            case .success:
                continue
            case .failure:
                XCTFail("Expected all uninstalls to succeed with mock")
            }
        }
    }

    // MARK: - Disable/Enable Extension Tests

    @MainActor
    func testWhenExtensionIsDisabled_ThenLoaderUnloadsItAndStoreMarksItDisabled() async throws {
        let manager = makeManager()
        let identifier = "extension1"
        installedExtensionStoringMock.installedExtensions = [makeInstalledWebExtension(uniqueIdentifier: identifier)]
        try await loadRealContext(identifier: identifier, into: manager.controller)

        try await manager.disableExtension(identifier: identifier)

        XCTAssertEqual(webExtensionLoadingMock.unloadedIdentifier, identifier)
        XCTAssertEqual(installedExtensionStoringMock.installedExtension(withUniqueIdentifier: identifier)?.isDisabled, true)
        XCTAssertFalse(storageProvidingMock.removeExtensionCalled)
        XCTAssertTrue(lifecycleDelegateMock.didUpdateExtensionsCalled)
    }

    @MainActor
    func testWhenEmbeddedExtensionIsDisabled_ThenDisablingFailsAndExtensionStaysEnabled() async {
        let manager = makeManager()
        let identifier = "embedded"
        installedExtensionStoringMock.installedExtensions = [makeInstalledWebExtension(uniqueIdentifier: identifier, embeddedType: .embedded)]

        do {
            try await manager.disableExtension(identifier: identifier)
            XCTFail("Expected an error")
        } catch WebExtensionError.embeddedExtensionCannotBeDisabled {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertFalse(webExtensionLoadingMock.unloadExtensionCalled)
        XCTAssertEqual(installedExtensionStoringMock.installedExtension(withUniqueIdentifier: identifier)?.isDisabled, false)
    }

    @MainActor
    func testWhenUnloadingFails_ThenExtensionIsNotMarkedDisabled() async throws {
        let manager = makeManager()
        let identifier = "extension1"
        installedExtensionStoringMock.installedExtensions = [makeInstalledWebExtension(uniqueIdentifier: identifier)]
        try await loadRealContext(identifier: identifier, into: manager.controller)
        webExtensionLoadingMock.mockUnloadError = NSError(domain: "test", code: 1)

        do {
            try await manager.disableExtension(identifier: identifier)
            XCTFail("Expected an error")
        } catch {}

        XCTAssertEqual(installedExtensionStoringMock.installedExtension(withUniqueIdentifier: identifier)?.isDisabled, false)
    }

    @MainActor
    func testWhenLoadInstalledExtensions_ThenDisabledExtensionsAreSkipped() async {
        installedExtensionStoringMock.installedExtensions = [
            makeInstalledWebExtension(uniqueIdentifier: "extension1"),
            InstalledWebExtension(uniqueIdentifier: "extension2", filename: "extension.zip", name: nil, version: nil, isDisabled: true)
        ]
        let manager = makeManager()

        await manager.loadInstalledExtensions()

        XCTAssertEqual(webExtensionLoadingMock.loadedIdentifiers, ["extension1"])
        XCTAssertEqual(storageProvidingMock.cleanupOrphanedExtensionsKnownIdentifiers, ["extension1", "extension2"])
    }

    @MainActor
    func testWhenDisabledExtensionIsEnabled_ThenLoaderLoadsItAndStoreMarksItEnabled() async throws {
        let manager = makeManager()
        let identifier = "extension1"
        installedExtensionStoringMock.installedExtensions = [
            InstalledWebExtension(uniqueIdentifier: identifier, filename: "extension.zip", name: nil, version: nil, isDisabled: true)
        ]

        try await manager.enableExtension(identifier: identifier)

        XCTAssertEqual(webExtensionLoadingMock.loadedIdentifiers, [identifier])
        XCTAssertEqual(installedExtensionStoringMock.installedExtension(withUniqueIdentifier: identifier)?.isDisabled, false)
        XCTAssertTrue(lifecycleDelegateMock.didUpdateExtensionsCalled)
    }

    @MainActor
    func testWhenLoadingFails_ThenExtensionStaysDisabled() async {
        let manager = makeManager()
        let identifier = "extension1"
        installedExtensionStoringMock.installedExtensions = [
            InstalledWebExtension(uniqueIdentifier: identifier, filename: "extension.zip", name: nil, version: nil, isDisabled: true)
        ]
        webExtensionLoadingMock.mockError = NSError(domain: "test", code: 1)

        do {
            try await manager.enableExtension(identifier: identifier)
            XCTFail("Expected an error")
        } catch {}

        XCTAssertEqual(installedExtensionStoringMock.installedExtension(withUniqueIdentifier: identifier)?.isDisabled, true)
    }

    @MainActor
    func testWhenDisabledExtensionNameIsRequested_ThenReturnsNameFromStore() {
        let manager = makeManager()
        installedExtensionStoringMock.installedExtensions = [
            InstalledWebExtension(uniqueIdentifier: "extension1", filename: "extension.zip", name: "Stored Name", version: nil, isDisabled: true)
        ]

        XCTAssertEqual(manager.extensionName(for: "extension1"), "Stored Name")
    }

    @MainActor
    func testWhenExtensionIsDisabledBeforeLightweightReload_ThenItIsNotReloaded() async throws {
        let manager = makeManager()
        installedExtensionStoringMock.installedExtensions = [makeInstalledWebExtension(uniqueIdentifier: "extension1")]
        try await loadRealContext(identifier: "extension1", into: manager.controller)
        manager.unloadAllExtensions()

        try await manager.disableExtension(identifier: "extension1")
        await manager.reloadInstalledExtensions()

        XCTAssertFalse(webExtensionLoadingMock.reloadWebExtensionCalled)
        XCTAssertNil(manager.context(for: "extension1"))
    }

    @MainActor
    func testWhenExtensionIsDisabledDuringLightweightReload_ThenItIsUnloadedAgain() async throws {
        let manager = makeManager()
        installedExtensionStoringMock.installedExtensions = [makeInstalledWebExtension(uniqueIdentifier: "extension1")]
        try await loadRealContext(identifier: "extension1", into: manager.controller)
        manager.unloadAllExtensions()
        webExtensionLoadingMock.loadHandler = { [unowned self] identifier, controller in
            // The disable finds no context yet, so it only marks the record.
            try await manager.disableExtension(identifier: identifier)
            XCTAssertFalse(webExtensionLoadingMock.unloadExtensionCalled)
            try await loadRealContext(identifier: identifier, into: controller)
        }

        await manager.reloadInstalledExtensions()

        XCTAssertEqual(webExtensionLoadingMock.unloadedIdentifier, "extension1")
        XCTAssertEqual(installedExtensionStoringMock.installedExtension(withUniqueIdentifier: "extension1")?.isDisabled, true)
    }

    @MainActor
    func testWhenExtensionIsDisabledDuringInstalledExtensionsLoad_ThenItIsUnloadedAgain() async throws {
        installedExtensionStoringMock.installedExtensions = [makeInstalledWebExtension(uniqueIdentifier: "extension1")]
        webExtensionLoadingMock.mockLoadResults = [.success(WebExtensionLoadResult(identifier: "extension1",
                                                                                   filename: "extension.zip",
                                                                                   displayName: nil,
                                                                                   version: nil))]
        let manager = makeManager()
        webExtensionLoadingMock.loadHandler = { [unowned self] identifier, controller in
            try await manager.disableExtension(identifier: identifier)
            try await loadRealContext(identifier: identifier, into: controller)
        }

        await manager.loadInstalledExtensions()

        XCTAssertEqual(webExtensionLoadingMock.unloadedIdentifier, "extension1")
        XCTAssertEqual(installedExtensionStoringMock.installedExtension(withUniqueIdentifier: "extension1")?.isDisabled, true)
    }

    // MARK: - Load Installed Extensions Tests

    @MainActor
    func testWhenLoadInstalledExtensions_ThenLoaderIsCalledWithIdentifiers() async {
        installedExtensionStoringMock.installedExtensions = [
            makeInstalledWebExtension(uniqueIdentifier: "extension1"),
            makeInstalledWebExtension(uniqueIdentifier: "extension2")
        ]
        let manager = makeManager()

        await manager.loadInstalledExtensions()

        XCTAssertTrue(webExtensionLoadingMock.loadWebExtensionsCalled)
        XCTAssertEqual(webExtensionLoadingMock.loadedIdentifiers, ["extension1", "extension2"])
    }

    @MainActor
    func testWhenLoadInstalledExtensions_ThenLifecycleDelegateWillLoadIsCalled() async {
        let manager = makeManager()

        await manager.loadInstalledExtensions()

        XCTAssertTrue(lifecycleDelegateMock.willLoadExtensionsCalled)
    }

    @MainActor
    func testWhenLoadInstalledExtensions_ThenLifecycleDelegateDidUpdateIsCalled() async {
        let manager = makeManager()

        await manager.loadInstalledExtensions()

        XCTAssertTrue(lifecycleDelegateMock.didUpdateExtensionsCalled)
    }

    @MainActor
    func testWhenExtensionsLoad_ThenListenerForwardsToController() async {
        let manager = makeManager()
        let listener = manager.eventsListener as? WebExtensionEventsListener
        let message = "Events before the first load are dropped"
        XCTAssertNil(listener?.controller, message)

        await manager.loadInstalledExtensions()

        XCTAssertIdentical(listener?.controller, manager.controller)
    }

    @MainActor
    func testWhenLoadInstalledExtensions_ThenOrphanedExtensionsAreCleaned() async {
        installedExtensionStoringMock.installedExtensions = [
            makeInstalledWebExtension(uniqueIdentifier: "extension1"),
            makeInstalledWebExtension(uniqueIdentifier: "extension2")
        ]
        let manager = makeManager()

        await manager.loadInstalledExtensions()

        XCTAssertTrue(storageProvidingMock.cleanupOrphanedExtensionsCalled)
        XCTAssertEqual(storageProvidingMock.cleanupOrphanedExtensionsKnownIdentifiers, Set(["extension1", "extension2"]))
    }

    // MARK: - Reload Installed Extensions Tests

    @MainActor
    func testWhenExplicitReloadUnloadFails_ThenFiresReloadErrorPixel() async throws {
        let pixelFiring = CapturingReloadErrorPixelFiring()
        let manager = makeManager(pixelFiring: pixelFiring)
        installedExtensionStoringMock.installedExtensions = [
            makeInstalledWebExtension(uniqueIdentifier: "extension1", embeddedType: .embedded)
        ]
        webExtensionLoadingMock.mockUnloadError = NSError(domain: "test", code: 1)

        do {
            try await manager.reloadExtension(identifier: "extension1")
            XCTFail("Expected reload to fail")
        } catch {
            XCTAssertEqual(pixelFiring.records, [
                .init(type: .embedded, trigger: .explicit, phase: .unload, errorDomain: "test", errorCode: "1")
            ])
        }
    }

    @MainActor
    func testWhenExplicitReloadLoadFails_ThenFiresReloadErrorPixel() async throws {
        let pixelFiring = CapturingReloadErrorPixelFiring()
        let manager = makeManager(pixelFiring: pixelFiring)
        installedExtensionStoringMock.installedExtensions = [
            makeInstalledWebExtension(uniqueIdentifier: "extension1", embeddedType: .embedded)
        ]
        webExtensionLoadingMock.mockError = NSError(
            domain: WKWebExtensionContext.errorDomain,
            code: WKWebExtensionContext.Error.Code.baseURLAlreadyInUse.rawValue
        )

        do {
            try await manager.reloadExtension(identifier: "extension1")
            XCTFail("Expected reload to fail")
        } catch {
            XCTAssertEqual(pixelFiring.records, [
                .init(type: .embedded, trigger: .explicit, phase: .load,
                      errorDomain: WKWebExtensionContext.errorDomain,
                      errorCode: String(WKWebExtensionContext.Error.Code.baseURLAlreadyInUse.rawValue))
            ])
        }
    }

    @MainActor
    func testWhenReloadInstalledExtensionsCalledWithEmptyCache_ThenFallsBackToFullLoad() async {
        installedExtensionStoringMock.installedExtensions = [
            makeInstalledWebExtension(uniqueIdentifier: "extension1")
        ]
        webExtensionLoadingMock.mockLoadResults = [
            .success(WebExtensionLoadResult(identifier: "extension1", filename: "extension.zip", displayName: "Extension 1", version: "1.0"))
        ]
        let manager = makeManager()

        await manager.reloadInstalledExtensions()

        // With nothing captured by a prior unload, reload must fall back to the full load path.
        XCTAssertTrue(webExtensionLoadingMock.loadWebExtensionsCalled)
        XCTAssertFalse(webExtensionLoadingMock.reloadWebExtensionCalled)
    }

    @MainActor
    func testWhenFullLoadFollowsDataClearing_ThenReportsEmbeddedExtensionReload() async throws {
        installedExtensionStoringMock.installedExtensions = [
            makeInstalledWebExtension(uniqueIdentifier: "extension1", embeddedType: .embedded)
        ]
        webExtensionLoadingMock.mockLoadResults = [
            .success(WebExtensionLoadResult(identifier: "extension1", filename: "extension.zip", displayName: "Extension 1", version: "1.0"))
        ]
        let manager = makeManager()
        try await loadRealContext(identifier: "extension1", into: manager.controller)

        manager.unloadAllExtensions()
        await manager.loadInstalledExtensions()

        let monitor = try XCTUnwrap(manager.cpmMessagingHealthMonitor as? CPMMessagingHealthMonitor)
        XCTAssertEqual(monitor.extensionReloadGeneration, 1)
    }

    @MainActor
    func testWhenExtensionsAreUnloadedForDataClearingThenWillReloadIsReportedImmediately() async throws {
        let monitor = CapturingCPMLifecycleMonitor()
        let manager = makeManager(cpmMessagingHealthMonitor: monitor)
        try await loadRealContext(identifier: "extension1", into: manager.controller)
        installedExtensionStoringMock.installedExtensions = [
            makeInstalledWebExtension(uniqueIdentifier: "extension1", embeddedType: .embedded)
        ]

        manager.unloadAllExtensions()

        XCTAssertEqual(monitor.lifecycleEvents, [
            .willReload(identifier: "extension1", type: .embedded, trigger: .dataClearing)
        ])
    }

    @MainActor
    func testWhenReloadInstalledExtensionsCalledAfterUnload_ThenUsesLightweightReloadAndSkipsFullLoad() async throws {
        let manager = makeManager()
        installedExtensionStoringMock.installedExtensions = [makeInstalledWebExtension(uniqueIdentifier: "extension1")]
        try await loadRealContext(identifier: "extension1", into: manager.controller)

        manager.unloadAllExtensions()
        await manager.reloadInstalledExtensions()

        // The cached extension is re-created via the lightweight path, not re-parsed from disk.
        XCTAssertTrue(webExtensionLoadingMock.reloadWebExtensionCalled)
        XCTAssertTrue(webExtensionLoadingMock.loadedIdentifiers.contains("extension1"))
        XCTAssertFalse(webExtensionLoadingMock.loadWebExtensionsCalled)
        // The heavy install-store reconciliation / orphan cleanup is skipped on the lightweight path.
        XCTAssertFalse(storageProvidingMock.cleanupOrphanedExtensionsCalled)
    }

    @MainActor
    func testWhenLightweightReloadFails_ThenFallsBackToFullLoad() async throws {
        let pixelFiring = CapturingReloadErrorPixelFiring()
        let manager = makeManager(pixelFiring: pixelFiring)
        try await loadRealContext(identifier: "extension1", into: manager.controller)
        installedExtensionStoringMock.installedExtensions = [
            makeInstalledWebExtension(uniqueIdentifier: "extension1")
        ]
        webExtensionLoadingMock.mockLoadResults = [
            .success(WebExtensionLoadResult(identifier: "extension1", filename: "extension.zip", displayName: "Extension 1", version: "1.0"))
        ]

        manager.unloadAllExtensions()
        webExtensionLoadingMock.mockError = NSError(domain: "test", code: 1)

        await manager.reloadInstalledExtensions()

        // The lightweight reload was attempted, failed, and recovery used the full load path.
        XCTAssertTrue(webExtensionLoadingMock.reloadWebExtensionCalled)
        XCTAssertTrue(webExtensionLoadingMock.loadWebExtensionsCalled)
        XCTAssertEqual(pixelFiring.records, [
            .init(type: nil, trigger: .dataClearing, phase: .lightweightLoad, errorDomain: "test", errorCode: "1")
        ])
    }

    @MainActor
    func testWhenLightweightAndFallbackReloadFail_ThenFiresBothReloadErrorPhases() async throws {
        let pixelFiring = CapturingReloadErrorPixelFiring()
        let manager = makeManager(pixelFiring: pixelFiring)
        try await loadRealContext(identifier: "extension1", into: manager.controller)
        installedExtensionStoringMock.installedExtensions = [
            makeInstalledWebExtension(uniqueIdentifier: "extension1", embeddedType: .embedded)
        ]
        webExtensionLoadingMock.mockLoadResults = [.failure(NSError(domain: "fallback", code: 2))]

        manager.unloadAllExtensions()
        webExtensionLoadingMock.mockError = NSError(domain: "lightweight", code: 1)
        await manager.reloadInstalledExtensions()

        XCTAssertEqual(pixelFiring.records, [
            .init(type: .embedded, trigger: .dataClearing, phase: .lightweightLoad, errorDomain: "lightweight", errorCode: "1"),
            .init(type: .embedded, trigger: .dataClearing, phase: .fallbackLoad, errorDomain: "fallback", errorCode: "2")
        ])
    }

    @MainActor
    func testWhenLightweightReloadFallsBack_ThenLifecycleHasOneReloadPairAndNoLoadedEvent() async throws {
        let manager = makeManager()
        try await loadRealContext(identifier: "extension1", into: manager.controller)
        installedExtensionStoringMock.installedExtensions = [
            makeInstalledWebExtension(uniqueIdentifier: "extension1", embeddedType: .embedded)
        ]
        webExtensionLoadingMock.mockLoadResults = [
            .success(WebExtensionLoadResult(identifier: "extension1", filename: "extension.zip", displayName: "Extension 1", version: "1.0"))
        ]
        var lifecycleEvents = manager.lifecycleEvents.makeAsyncIterator()

        manager.unloadAllExtensions()
        webExtensionLoadingMock.mockError = NSError(domain: "test", code: 1)
        await manager.reloadInstalledExtensions()
        let firstEvent = await lifecycleEvents.next()
        let secondEvent = await lifecycleEvents.next()

        XCTAssertEqual(
            firstEvent,
            .willReload(identifier: "extension1", type: .embedded, trigger: .dataClearing)
        )
        XCTAssertEqual(
            secondEvent,
            .reloaded(identifier: "extension1", type: .embedded, trigger: .dataClearing)
        )
    }

    // MARK: - Unload Guard Integration Tests

    // The guard's windowing logic is covered in WebExtensionUnloadGuardTests; these prove the
    // manager's unload/reload paths actually consult the guard and record loads with it.

    /// Loads a real DNR-permission context into the manager's controller and records its load date
    /// via `loadInstalledExtensions()`, so the settle window can be exercised.
    @MainActor
    private func makeManagerWithLoadedExtension(identifier: String,
                                                filename: String = "extension.zip",
                                                embeddedType: DuckDuckGoWebExtensionType? = nil,
                                                bundledExtensionURL: @escaping (EmbeddedWebExtensionDescriptor) -> URL? = { _ in
                                                    XCTFail("Unexpected bundled extension lookup")
                                                    return nil
                                                }) async throws -> WebExtensionManager {
        installedExtensionStoringMock.installedExtensions = [
            makeInstalledWebExtension(uniqueIdentifier: identifier, filename: filename, version: "0.0.1", embeddedType: embeddedType)
        ]
        webExtensionLoadingMock.mockLoadResults = [
            .success(WebExtensionLoadResult(identifier: identifier, filename: filename, displayName: nil, version: "0.0.1"))
        ]
        let manager = makeManager(bundledExtensionURL: bundledExtensionURL)
        try await loadRealContext(identifier: identifier, into: manager.controller, permissions: ["declarativeNetRequest"])
        await manager.loadInstalledExtensions()
        return manager
    }

    /// Loads the embedded ad blocker, the only bundled extension that requests declarativeNetRequest.
    @MainActor
    private func makeManagerWithLoadedAdBlocker() async throws -> WebExtensionManager {
        try await makeManagerWithLoadedExtension(identifier: "old-adblock",
                                                 filename: "content-blocker-extension-apple.zip",
                                                 embeddedType: .adBlockingExtension)
    }

    /// The window is only useful if it elapses before the unload, so every path asserts both.
    private func assertSleptForRemainderBeforeUnloading(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(recordedSleeps.count, 1, "expected exactly one settle wait", file: file, line: line)
        XCTAssertEqual(recordedSleeps.first ?? 0, 2.0, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(unloadCalledAtSleepTime, [false],
                       "the wait must happen before the unload, not after it", file: file, line: line)
        XCTAssertTrue(webExtensionLoadingMock.unloadExtensionCalled,
                      "the unload should still happen once the window elapses", file: file, line: line)
    }

    @MainActor
    func testWhenDNRExtensionIsReloadedWithinSettleWindow_ThenReloadSleepsForRemainder() async throws {
        let manager = try await makeManagerWithLoadedExtension(identifier: "dnr-extension")

        currentDate = currentDate.addingTimeInterval(1)
        try await manager.reloadExtension(identifier: "dnr-extension")

        assertSleptForRemainderBeforeUnloading()
    }

    @MainActor
    func testWhenDisabledDNRExtensionIsUninstalledWithinSettleWindow_ThenSyncSleepsFirst() async throws {
        let manager = try await makeManagerWithLoadedAdBlocker()

        currentDate = currentDate.addingTimeInterval(1)
        await manager.syncEmbeddedExtensions(enabledTypes: [])

        assertSleptForRemainderBeforeUnloading()
        XCTAssertFalse(installedExtensionStoringMock.installedExtensions.contains { $0.uniqueIdentifier == "old-adblock" },
                       "disabling should have uninstalled the extension after the settle window")
    }

    @MainActor
    func testWhenEmbeddedDNRExtensionIsUpgradedWithinSettleWindow_ThenSyncSleepsBeforeUninstall() async throws {
        let bundledDirectory = try makeTestExtensionDirectory(permissions: ["declarativeNetRequest"], embeddedType: .adBlockingExtension)
        let bundledURL = bundledDirectory.appendingPathExtension("zip")
        createdTestExtensionDirs.append(bundledURL)
        try FileManager.default.zipItem(at: bundledDirectory, to: bundledURL, shouldKeepParent: false)
        let manager = try await makeManagerWithLoadedExtension(identifier: "old-adblock",
                                                              filename: "content-blocker-extension-apple.zip",
                                                              embeddedType: .adBlockingExtension,
                                                              bundledExtensionURL: { descriptor in
                                                                  XCTAssertEqual(descriptor.type, .adBlockingExtension)
                                                                  return bundledURL
                                                              })

        currentDate = currentDate.addingTimeInterval(1)
        await manager.syncEmbeddedExtensions(enabledTypes: [.adBlockingExtension])

        assertSleptForRemainderBeforeUnloading()
        XCTAssertFalse(installedExtensionStoringMock.installedExtensions.contains { $0.uniqueIdentifier == "old-adblock" },
                       "upgrade should have uninstalled the old extension after the settle window")
    }

#if os(macOS)
    // MARK: - Bitwarden Pixels

    /// Bitwarden is recognized by its Chrome Web Store catalog entry, so its pixels carry the catalog's name and
    /// never its identifier.
    @MainActor
    func testWhenBrowsingWithBitwardenLoaded_ThenItsDailyPixelReportsWhetherItIsTheDefaultPasswordManager() async throws {
        let bitwardenStoreID = String(repeating: "n", count: 32)
        let pixels = EventCapturingPixelFiring()
        var date = Date(timeIntervalSince1970: 0)
        installedExtensionStoringMock.installedExtensions = [
            InstalledWebExtension(uniqueIdentifier: "bitwarden", filename: "bitwarden", name: nil, version: "1",
                                  embeddedType: nil, storeIdentity: WebExtensionStoreIdentity(store: .chromeWebStore, id: bitwardenStoreID))
        ]
        let manager = WebExtensionManager(configuration: configurationMock,
                                          windowTabProvider: windowTabProviderMock,
                                          storageProvider: storageProvidingMock,
                                          installationStore: installedExtensionStoringMock,
                                          permissionController: makePermissionController(),
                                          loader: webExtensionLoadingMock,
                                          lifecycleDelegate: lifecycleDelegateMock,
                                          pixelFiring: pixels,
                                          keyValueStore: InMemoryThrowingKeyValueStore(),
                                          now: { date })
        let webStore = CatalogNamingWebStore(entries: [bitwardenStoreID: .bitwarden])
        manager.chromeWebStore = webStore
        let context = try await loadRealContext(identifier: "bitwarden", into: manager.controller, permissions: ["privacy"])
        try await manager.permissionController?.prepare(context)
        let loadResult = WebExtensionLoadResult(identifier: "bitwarden", filename: "bitwarden", displayName: nil, version: "1")

        webExtensionLoadingMock.mockLoadResults = [.success(loadResult)]
        await manager.loadInstalledExtensions()
        XCTAssertEqual(pixels.events, [])

        manager.eventsListener.onBrowsingActivity?()
        XCTAssertEqual(pixels.events, ["bitwarden dau, default: false"])

        let store = try XCTUnwrap(manager.privacySettings)
        try store.set(false, for: .passwordSavingEnabled, by: "bitwarden")
        date += 59 * 60
        manager.eventsListener.onBrowsingActivity?()
        XCTAssertEqual(pixels.events, ["bitwarden dau, default: false", "default set: bitwarden"], "Activity within the hour isn't checked again")

        date += 60
        manager.eventsListener.onBrowsingActivity?()
        XCTAssertEqual(pixels.events.filter { !$0.hasPrefix("gaps") },
                       ["bitwarden dau, default: false", "default set: bitwarden", "bitwarden dau, default: true"])
    }

    /// Only a loaded Bitwarden counts: an installed Bitwarden that isn't loaded, or another catalog extension
    /// that is, sends nothing.
    @MainActor
    func testWhenBitwardenIsNotLoaded_ThenBrowsingSendsNoDailyPixelEvenWithAnotherCatalogExtensionLoaded() async throws {
        let bitwardenStoreID = String(repeating: "n", count: 32)
        let onePasswordStoreID = String(repeating: "o", count: 32)
        let pixels = EventCapturingPixelFiring()
        installedExtensionStoringMock.installedExtensions = [
            InstalledWebExtension(uniqueIdentifier: "bitwarden", filename: "bitwarden", name: nil, version: "1",
                                  embeddedType: nil, storeIdentity: WebExtensionStoreIdentity(store: .chromeWebStore, id: bitwardenStoreID)),
            InstalledWebExtension(uniqueIdentifier: "onePassword", filename: "onePassword", name: nil, version: "1",
                                  embeddedType: nil, storeIdentity: WebExtensionStoreIdentity(store: .chromeWebStore, id: onePasswordStoreID))
        ]
        let manager = WebExtensionManager(configuration: configurationMock,
                                          windowTabProvider: windowTabProviderMock,
                                          storageProvider: storageProvidingMock,
                                          installationStore: installedExtensionStoringMock,
                                          loader: webExtensionLoadingMock,
                                          lifecycleDelegate: lifecycleDelegateMock,
                                          pixelFiring: pixels,
                                          keyValueStore: InMemoryThrowingKeyValueStore())
        manager.chromeWebStore = CatalogNamingWebStore(entries: [bitwardenStoreID: .bitwarden, onePasswordStoreID: .onePassword])
        _ = try await loadRealContext(identifier: "onePassword", into: manager.controller)

        manager.eventsListener.onBrowsingActivity?()
        XCTAssertEqual(pixels.events, [])

        _ = try await loadRealContext(identifier: "bitwarden", into: manager.controller)
        manager.eventsListener.onBrowsingActivity?()
        XCTAssertEqual(pixels.events, ["bitwarden dau, default: false"])
    }

    /// Each loaded catalog extension reports its version and distinct gaps once the app has run for an
    /// hour, zeros included; stubs, dropped permissions and rejected arguments don't count, and
    /// extensions outside the catalog don't report.
    @MainActor
    func testWhenBrowsingAnHourAfterLaunch_ThenEachLoadedCatalogExtensionReportsItsGapCounts() async throws {
        let bitwardenStoreID = String(repeating: "n", count: 32)
        let lastPassStoreID = String(repeating: "l", count: 32)
        let pixels = EventCapturingPixelFiring()
        var date = Date(timeIntervalSince1970: 0)
        installedExtensionStoringMock.installedExtensions = [
            InstalledWebExtension(uniqueIdentifier: "bitwarden", filename: "bitwarden", name: nil, version: "1",
                                  embeddedType: nil, storeIdentity: WebExtensionStoreIdentity(store: .chromeWebStore, id: bitwardenStoreID)),
            InstalledWebExtension(uniqueIdentifier: "lastPass", filename: "lastPass", name: nil, version: "1",
                                  embeddedType: nil, storeIdentity: WebExtensionStoreIdentity(store: .chromeWebStore, id: lastPassStoreID)),
            InstalledWebExtension(uniqueIdentifier: "sideloaded", filename: "sideloaded", name: nil, version: "1",
                                  embeddedType: nil, storeIdentity: nil)
        ]
        let manager = WebExtensionManager(configuration: configurationMock,
                                          windowTabProvider: windowTabProviderMock,
                                          storageProvider: storageProvidingMock,
                                          installationStore: installedExtensionStoringMock,
                                          loader: webExtensionLoadingMock,
                                          lifecycleDelegate: lifecycleDelegateMock,
                                          pixelFiring: pixels,
                                          keyValueStore: InMemoryThrowingKeyValueStore(),
                                          now: { date })
        manager.chromeWebStore = CatalogNamingWebStore(entries: [bitwardenStoreID: .bitwarden, lastPassStoreID: .lastPass])
        for identifier in ["bitwarden", "lastPass", "sideloaded"] {
            _ = try await loadRealContext(identifier: identifier, into: manager.controller)
        }
        manager.recordAPICompatibilityIssue(.init(kind: .missing, api: "chrome.sidePanel"), for: "bitwarden")
        manager.recordAPICompatibilityIssue(.init(kind: .missing, api: "chrome.sidePanel"), for: "bitwarden")
        manager.recordAPICompatibilityIssue(.init(kind: .missing, api: "js:Object.groupBy"), for: "bitwarden")
        manager.recordAPICompatibilityIssue(.init(kind: .stubbed, api: "chrome.offscreen.createDocument"), for: "bitwarden")
        manager.recordAPICompatibilityIssue(.init(kind: .missing, api: "permission:offscreen"), for: "bitwarden")
        manager.recordAPICompatibilityIssue(.init(kind: .invalidArgs, api: "chrome.tabs.query"), for: "bitwarden")
        manager.recordAPICompatibilityIssue(.init(kind: .unsupportedURL, api: "chrome://password-manager/settings"), for: "bitwarden")
        manager.recordAPICompatibilityIssue(.init(kind: .missing, api: "chrome.sidePanel"), for: "sideloaded")

        date += 59 * 60
        manager.eventsListener.onBrowsingActivity?()
        XCTAssertEqual(pixels.events.filter { $0.hasPrefix("gaps") }, [], "Too soon after launch")

        date += 60
        manager.eventsListener.onBrowsingActivity?()
        XCTAssertEqual(Set(pixels.events.filter { $0.hasPrefix("gaps") }),
                       ["gaps bitwarden 1.0.0: 2 apis, 1 urls", "gaps lastPass 1.0.0: 0 apis, 0 urls"])
    }

    @MainActor
    func testWhenNativeAPIsAreUnsupportedThenGapCountsAreDistinctAndExcludeEmbeddedExtensions() async throws {
        let extensionTypes: [DuckDuckGoWebExtensionType?] = [nil, .embedded]
        for embeddedType in extensionTypes {
            let firstStoreID = String(repeating: "a", count: 32)
            let secondStoreID = String(repeating: "b", count: 32)
            installedExtensionStoringMock.installedExtensions = [
                InstalledWebExtension(uniqueIdentifier: "first", filename: "first", name: nil, version: "1",
                                      storeIdentity: WebExtensionStoreIdentity(store: .chromeWebStore, id: firstStoreID)),
                InstalledWebExtension(uniqueIdentifier: "second", filename: "second", name: nil, version: "1",
                                      storeIdentity: WebExtensionStoreIdentity(store: .chromeWebStore, id: secondStoreID))
            ]
            let pixels = EventCapturingPixelFiring()
            var date = Date(timeIntervalSince1970: 0)
            let manager = makeManager(pixelFiring: pixels, now: { date })
            manager.chromeWebStore = CatalogNamingWebStore(entries: [firstStoreID: .onePassword, secondStoreID: .bitwarden])
            let firstContext = try await loadRealContext(identifier: "first", into: manager.controller, embeddedType: embeddedType)
            let secondContext = try await loadRealContext(identifier: "second", into: manager.controller)

            _ = WebExtensionAPICompatibilityLog.unsupportedAPI("tabs.setZoom", in: firstContext)
            _ = WebExtensionAPICompatibilityLog.unsupportedAPI("tabs.setZoom", in: firstContext)
            _ = WebExtensionAPICompatibilityLog.unsupportedAPI("tabs.duplicate", in: firstContext)
            _ = WebExtensionAPICompatibilityLog.unsupportedAPI("tabs.setZoom", in: secondContext)
            date += 60 * 60
            manager.eventsListener.onBrowsingActivity?()

            let firstCount = embeddedType == nil ? 2 : 0
            XCTAssertEqual(Set(pixels.events.filter { $0.hasPrefix("gaps") }),
                           ["gaps onePassword 1.0.0: \(firstCount) apis, 0 urls", "gaps bitwarden 1.0.0: 1 apis, 0 urls"])
        }
    }

    @MainActor
    func testWhenUnsupportedAPIContextIsNotLoadedThenItStillReturnsAnError() async throws {
        let directory = try makeTestExtensionDirectory()
        let context = WKWebExtensionContext(for: try await WKWebExtension(resourceBaseURL: directory))
        XCTAssertNil(context.webExtensionController)

        let error = WebExtensionAPICompatibilityLog.unsupportedAPI("tabs.setZoom", in: context)

        XCTAssertEqual(error.domain, "WebExtensionUnsupportedAPI")
        XCTAssertEqual(error.code, 1)
        XCTAssertEqual(error.localizedDescription, "Unsupported extension API: tabs.setZoom")
    }

    // MARK: - Native messaging ports

    /// iCloud Passwords posts its hello in the same JS turn as `connectNative()`. WebKit drops every port
    /// message posted before the connect delegate calls its completion handler, so the hello must reach
    /// the host even though the host takes a while to start.
    @MainActor
    func testWhenAnExtensionPostsInTheSameTurnAsConnectNative_ThenTheHostReceivesTheMessage() async throws {
        let host = SlowStartingNativeMessagingHandler(startupDelay: .milliseconds(300))
        let manager = WebExtensionManager(configuration: configurationMock,
                                          windowTabProvider: windowTabProviderMock,
                                          storageProvider: storageProvidingMock,
                                          installationStore: installedExtensionStoringMock,
                                          loader: webExtensionLoadingMock,
                                          lifecycleDelegate: lifecycleDelegateMock,
                                          nativeMessagingHandler: host)
        let directory = try makeTestExtensionDirectory(permissions: ["nativeMessaging"])
        let manifestURL = directory.appendingPathComponent("manifest.json")
        var manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        manifest["background"] = ["page": "bg.html"]
        try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)
        try #"<!DOCTYPE html><html><head><meta charset="utf-8"></head><body><script src="bg.js"></script></body></html>"#
            .write(to: directory.appendingPathComponent("bg.html"), atomically: true, encoding: .utf8)
        try """
        const port = chrome.runtime.connectNative("com.example.host");
        port.onMessage.addListener(function() {});
        port.postMessage({ cmd: "hello" });
        """.write(to: directory.appendingPathComponent("bg.js"), atomically: true, encoding: .utf8)

        let webExtension = try await WKWebExtension(resourceBaseURL: directory)
        XCTAssertTrue(webExtension.needsChromeCompatibility)
        let context = WKWebExtensionContext(for: webExtension)
        context.uniqueIdentifier = "native-messaging-hello"
        for permission in webExtension.requestedPermissions {
            context.setPermissionStatus(.grantedExplicitly, for: permission)
        }
        try manager.controller.load(context)
        addTeardownBlock { try? manager.controller.unload(context) }
        context.loadBackgroundContent { _ in }

        await fulfillment(of: [host.receivedFirstMessage], timeout: 5)
        XCTAssertEqual(host.receivedMessages.first as? [String: String], ["cmd": "hello"])
    }

    // MARK: - Autofill Takeover Flag

    /// The app's flag decides whether any extension may take over autofill, read each time, so turning it
    /// off hands autofill back and turning it on again restores what the extension chose.
    @MainActor
    func testWhenAutofillTakeoverIsTurnedOffAndOn_ThenAnExtensionsControlFollows() async throws {
        var isTakeoverEnabled = true
        let manager = WebExtensionManager(configuration: configurationMock,
                                          windowTabProvider: windowTabProviderMock,
                                          storageProvider: storageProvidingMock,
                                          installationStore: installedExtensionStoringMock,
                                          permissionController: makePermissionController(),
                                          loader: webExtensionLoadingMock,
                                          lifecycleDelegate: lifecycleDelegateMock,
                                          keyValueStore: InMemoryThrowingKeyValueStore(),
                                          isAutofillTakeoverEnabled: { isTakeoverEnabled })
        let context = try await loadRealContext(identifier: "bitwarden", into: manager.controller, permissions: ["privacy"])
        try await manager.permissionController?.prepare(context)
        let store = try XCTUnwrap(manager.privacySettings)
        XCTAssertNoThrow(try store.set(false, for: .passwordSavingEnabled, by: "bitwarden"))

        isTakeoverEnabled = false

        XCTAssertNil(store.identifierTurningOff(.passwordSavingEnabled))
        XCTAssertEqual(store.details(of: .passwordSavingEnabled, for: "bitwarden").levelOfControl, .notControllable)
        XCTAssertThrowsError(try store.set(false, for: .autofillAddressEnabled, by: "bitwarden"))
        XCTAssertThrowsError(try store.clear(.passwordSavingEnabled, for: "bitwarden"))

        isTakeoverEnabled = true

        XCTAssertEqual(store.identifierTurningOff(.passwordSavingEnabled), "bitwarden")
    }

    /// `privacy` is a permission the user grants: until then, or once it's taken back, the extension
    /// can't take over autofill, and taking it back hands autofill back to DuckDuckGo.
    @MainActor
    func testWhenTheUserGrantsAndTakesBackPrivacy_ThenTheExtensionsControlFollows() async throws {
        let manager = WebExtensionManager(configuration: configurationMock,
                                          windowTabProvider: windowTabProviderMock,
                                          storageProvider: storageProvidingMock,
                                          installationStore: installedExtensionStoringMock,
                                          permissionController: makePermissionController(),
                                          loader: webExtensionLoadingMock,
                                          lifecycleDelegate: lifecycleDelegateMock,
                                          keyValueStore: InMemoryThrowingKeyValueStore())
        let context = try await loadRealContext(identifier: "bitwarden", into: manager.controller, optionalPermissions: ["privacy"])
        let permissionController = try XCTUnwrap(manager.permissionController)
        try await permissionController.prepare(context)
        let store = try XCTUnwrap(manager.privacySettings)
        XCTAssertThrowsError(try store.set(false, for: .passwordSavingEnabled, by: "bitwarden"))

        let granted = await permissionController.request(.init(appPermissions: [.privacy]), for: context)
        XCTAssertTrue(granted)
        XCTAssertNoThrow(try store.set(false, for: .passwordSavingEnabled, by: "bitwarden"))
        XCTAssertEqual(store.identifierTurningOff(.passwordSavingEnabled), "bitwarden")

        XCTAssertTrue(permissionController.revoke(.privacy, from: context))
        XCTAssertNil(store.identifierTurningOff(.passwordSavingEnabled))
        XCTAssertNil(store.controllingIdentifier(for: .passwordSavingEnabled))
    }

    /// Without the permissions system nothing is granted, so no extension can take over autofill.
    @MainActor
    func testWhenThereIsNoPermissionController_ThenNoExtensionCanTakeOverAutofill() async throws {
        let manager = WebExtensionManager(configuration: configurationMock,
                                          windowTabProvider: windowTabProviderMock,
                                          storageProvider: storageProvidingMock,
                                          installationStore: installedExtensionStoringMock,
                                          loader: webExtensionLoadingMock,
                                          lifecycleDelegate: lifecycleDelegateMock,
                                          keyValueStore: InMemoryThrowingKeyValueStore())
        _ = try await loadRealContext(identifier: "bitwarden", into: manager.controller, permissions: ["privacy"])
        let store = try XCTUnwrap(manager.privacySettings)

        XCTAssertThrowsError(try store.set(false, for: .passwordSavingEnabled, by: "bitwarden"))
    }

    @MainActor
    func testWhenAnExtensionDoesNotDeclarePrivacy_ThenItCannotTakeOverAutofill() async throws {
        let manager = WebExtensionManager(configuration: configurationMock,
                                          windowTabProvider: windowTabProviderMock,
                                          storageProvider: storageProvidingMock,
                                          installationStore: installedExtensionStoringMock,
                                          loader: webExtensionLoadingMock,
                                          lifecycleDelegate: lifecycleDelegateMock,
                                          keyValueStore: InMemoryThrowingKeyValueStore())
        _ = try await loadRealContext(identifier: "other", into: manager.controller, permissions: ["storage"])
        let store = try XCTUnwrap(manager.privacySettings)

        XCTAssertThrowsError(try store.set(false, for: .passwordSavingEnabled, by: "other"))
        XCTAssertNil(store.controllingIdentifier(for: .passwordSavingEnabled))
    }

    // MARK: - Zip to Folder Upgrade Tests

    /// Existing Dark Reader installs are stored as a zip, which WebKit unzips on the main thread on
    /// every load. Upgrading to a bundled version that requires extraction must leave a folder install.
    @MainActor
    func testWhenZipInstalledExtensionIsUpgradedToVersionRequiringExtraction_ThenFolderInstallReplacesZip() async throws {
        let extensionsDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("ZipUpgradeTest-\(UUID().uuidString)")
        createdTestExtensionDirs.append(extensionsDirectory)
        let storageProvider = WebExtensionStorageProvider(extensionsDirectory: extensionsDirectory)

        let bundledURL = try XCTUnwrap(EmbeddedWebExtensionRegistry.descriptor(for: .darkReader)?.bundledURL)
        let bundledMetadata = try await WebExtensionMetadata.fromZip(at: bundledURL)
        XCTAssertTrue(bundledMetadata.requiresExtraction, "precondition: the bundled Dark Reader requires extraction")

        let oldIdentifier = "old-darkreader"
        _ = try storageProvider.copyExtension(from: bundledURL, identifier: oldIdentifier)
        XCTAssertEqual(storageProvider.resolveInstalledExtension(identifier: oldIdentifier)?.pathExtension, "zip",
                       "precondition: the old install resolves to its zip")
        installedExtensionStoringMock.installedExtensions = [
            makeInstalledWebExtension(uniqueIdentifier: oldIdentifier, filename: "darkreader.zip", version: "4.9.128.1", embeddedType: .darkReader)
        ]

        let manager = makeManager(storageProvider: storageProvider, bundledExtensionURL: { descriptor in
            XCTAssertEqual(descriptor.type, .darkReader)
            return bundledURL
        })
        await manager.syncEmbeddedExtensions(enabledTypes: [.darkReader])

        let installed = try XCTUnwrap(manager.installedEmbeddedExtension(for: .darkReader))
        XCTAssertNotEqual(installed.uniqueIdentifier, oldIdentifier)
        XCTAssertFalse(FileManager.default.fileExists(atPath: extensionsDirectory.appendingPathComponent(oldIdentifier).path),
                       "the old zip install should have been removed")

        let resolvedURL = try XCTUnwrap(storageProvider.resolveInstalledExtension(identifier: installed.uniqueIdentifier))
        XCTAssertEqual(resolvedURL.lastPathComponent, installed.uniqueIdentifier,
                       "the new install should resolve to its extracted folder, not a zip")
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolvedURL.appendingPathComponent("manifest.json").path))
    }
#endif

    // MARK: - Computed Properties Tests

    @MainActor
    func testThatWebExtensionIdentifiers_ReturnsIdentifiersFromStore() {
        let manager = makeManager()
        installedExtensionStoringMock.installedExtensions = [
            makeInstalledWebExtension(uniqueIdentifier: "extension1.zip"),
            makeInstalledWebExtension(uniqueIdentifier: "extension2.zip")
        ]

        let resultIdentifiers = manager.webExtensionIdentifiers

        XCTAssertEqual(resultIdentifiers, ["extension1.zip", "extension2.zip"])
    }

    // MARK: - Extension Version Lookup Tests

    @MainActor
    func testWhenExtensionVersionRequested_ThenReturnsVersionFromStore() {
        let manager = makeManager()
        installedExtensionStoringMock.installedExtensions = [
            makeInstalledWebExtension(uniqueIdentifier: "ext-1", version: "1.2.3")
        ]

        let version = manager.extensionVersion(for: "ext-1")

        XCTAssertEqual(version, "1.2.3")
    }

    @MainActor
    func testWhenExtensionVersionRequestedForUnknownIdentifier_ThenReturnsNil() {
        let manager = makeManager()
        installedExtensionStoringMock.installedExtensions = [
            makeInstalledWebExtension(uniqueIdentifier: "ext-1", version: "1.0.0")
        ]

        let version = manager.extensionVersion(for: "unknown-ext")

        XCTAssertNil(version)
    }

    @MainActor
    func testWhenExtensionHasNoVersion_ThenReturnsNil() {
        let manager = makeManager()
        installedExtensionStoringMock.installedExtensions = [
            makeInstalledWebExtension(uniqueIdentifier: "ext-1", version: nil)
        ]

        let version = manager.extensionVersion(for: "ext-1")

        XCTAssertNil(version)
    }

    // MARK: - Extension Origin Tests

    @MainActor
    func testWhenChromeWebStoreExtensionIsInstalledAndReloaded_ThenOriginUsesStoreIdentifier() async throws {
        let extensionURL = try createTestWebExtension()
        storageProvidingMock.resolvedExtensionURL = extensionURL
        storageProvidingMock.mockCopyResult = extensionURL
        let identity = WebExtensionStoreIdentity(store: .chromeWebStore, id: String(repeating: "b", count: 32))
        let manager = makeManagerWithRealLoader()

        try await manager.installExtension(from: extensionURL, storeIdentity: identity)

        let installed = try XCTUnwrap(installedExtensionStoringMock.installedExtensions.first)
        let context = try XCTUnwrap(manager.context(for: installed.uniqueIdentifier))
        let expectedURL = URL(string: "webkit-extension://\(identity.id)/")
        XCTAssertEqual(context.baseURL, expectedURL)
        XCTAssertEqual(context.uniqueIdentifier, installed.uniqueIdentifier)
        XCTAssertNotEqual(context.uniqueIdentifier, identity.id)

        manager.unloadAllExtensions()
        await manager.reloadInstalledExtensions()

        let restoredContext = try XCTUnwrap(manager.context(for: installed.uniqueIdentifier))
        XCTAssertEqual(restoredContext.baseURL, expectedURL)
        XCTAssertEqual(restoredContext.uniqueIdentifier, installed.uniqueIdentifier)
        manager.unloadAllExtensions()
    }

    @MainActor
    func testWhenChromeWebStoreReplacementFails_ThenExistingExtensionIsRestored() async throws {
        let extensionURL = try createTestWebExtension()
        storageProvidingMock.resolvedExtensionURL = extensionURL
        storageProvidingMock.mockCopyResult = extensionURL
        let identity = WebExtensionStoreIdentity(store: .chromeWebStore, id: String(repeating: "b", count: 32))
        let manager = makeManagerWithRealLoader()
        try await manager.installExtension(from: extensionURL, storeIdentity: identity)
        let installed = try XCTUnwrap(installedExtensionStoringMock.installedExtensions.first)
        let originalContext = try XCTUnwrap(manager.context(for: installed.uniqueIdentifier))
        storageProvidingMock.shouldReturnNilForResolve = true

        do {
            try await manager.installExtension(from: extensionURL, storeIdentity: identity, replacing: installed.uniqueIdentifier)
            XCTFail("Expected replacement loading to fail")
        } catch WebExtensionError.failedToLoadWebExtension {
            // Expected: the new installation cannot be resolved.
        }

        let restoredContext = try XCTUnwrap(manager.context(for: installed.uniqueIdentifier))
        XCTAssertTrue(restoredContext === originalContext)
        XCTAssertEqual(restoredContext.baseURL, URL(string: "webkit-extension://\(identity.id)/"))
        XCTAssertEqual(manager.contexts.count, 1)
        XCTAssertEqual(installedExtensionStoringMock.installedExtensions.map(\.uniqueIdentifier), [installed.uniqueIdentifier])
        XCTAssertTrue(manager.installingStoreIdentities.isEmpty)
        manager.unloadAllExtensions()
    }

    // MARK: - Configuration Tests

    @MainActor
    func testWhenManagerCreatedWithoutLoader_ThenLoaderReceivesIsInspectableFromConfiguration() async throws {
        configurationMock.isInspectable = true

        let extensionURL = try createTestWebExtension()
        storageProvidingMock.resolvedExtensionURL = extensionURL
        storageProvidingMock.mockCopyResult = extensionURL

        let manager = makeManagerWithRealLoader()

        try await manager.installExtension(from: extensionURL)

        let context = manager.contexts.first
        XCTAssertNotNil(context)
        XCTAssertTrue(context?.isInspectable == true)
    }

    @MainActor
    func testWhenManagerCreatedWithIsInspectableFalse_ThenContextIsNotInspectable() async throws {
        configurationMock.isInspectable = false

        let extensionURL = try createTestWebExtension()
        storageProvidingMock.resolvedExtensionURL = extensionURL
        storageProvidingMock.mockCopyResult = extensionURL

        let manager = makeManagerWithRealLoader()

        try await manager.installExtension(from: extensionURL)

        let context = manager.contexts.first
        XCTAssertNotNil(context)
        XCTAssertFalse(context?.isInspectable == true)
    }

    @MainActor
    func testWhenManagerIsCreated_ThenThirdPartyScriptsAreNotAddedForEveryExtension() throws {
        let manager = makeManager()

        let userScripts = manager.controller.configuration.webViewConfiguration.userContentController.userScripts

        XCTAssertFalse(userScripts.contains { WebExtensionLoader.thirdPartyScriptSources.contains($0.source) })
    }

    // MARK: - Additional Helpers

    @MainActor
    private func makeManagerWithRealLoader() -> WebExtensionManager {
        WebExtensionManager(
            configuration: configurationMock,
            windowTabProvider: windowTabProviderMock,
            storageProvider: storageProvidingMock,
            installationStore: installedExtensionStoringMock,
            loader: nil,
            lifecycleDelegate: lifecycleDelegateMock
        )
    }

    private func createTestWebExtension() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let extensionDir = tempDir.appendingPathComponent("TestExtension-\(UUID().uuidString)")

        let manifest = """
        {
            "manifest_version": 3,
            "name": "Test Extension",
            "version": "1.0.0",
            "description": "Minimal test extension for unit tests"
        }
        """

        try FileManager.default.createDirectory(at: extensionDir, withIntermediateDirectories: true)
        try manifest.write(to: extensionDir.appendingPathComponent("manifest.json"),
                          atomically: true, encoding: .utf8)

        addTeardownBlock {
            try? FileManager.default.removeItem(at: extensionDir)
        }

        return extensionDir
    }

}

@available(macOS 15.4, iOS 18.4, *)
@MainActor
private final class CapturingCPMLifecycleMonitor: CPMMessagingHealthMonitoring {
    private(set) var lifecycleEvents: [WebExtensionLifecycleEvent] = []

    func handle(_ event: CPMMessagingHealthEvent) {
        guard case .extensionLifecycle(let lifecycleEvent) = event else { return }
        lifecycleEvents.append(lifecycleEvent)
    }
}

@available(macOS 15.4, iOS 18.4, *)
private final class DeferredCPMBackgroundContext: WKWebExtensionContext {
    var completions: [(Swift.Error?) -> Void] = []
    var recordedErrors: [Swift.Error] = []
    var onBackgroundLoad: (() -> Void)?
    /// Stands in for WebKit's private `_backgroundWebView`, which the manager reads to see whether a failed view is retained.
    @objc(_backgroundWebView) var retainedBackgroundWebView: WKWebView?

    override var errors: [Swift.Error] { recordedErrors }

    override func loadBackgroundContent(completionHandler: @escaping (Swift.Error?) -> Void) {
        completions.append(completionHandler)
        onBackgroundLoad?()
    }

    func finishBackgroundLoads() {
        recordedErrors = []
        let pending = completions
        completions.removeAll()
        onBackgroundLoad = nil
        for completion in pending { completion(nil) }
    }
}

@available(macOS 15.4, iOS 18.4, *)
private final class CapturingCPMRestartPixels: WebExtensionPixelFiring {
    private(set) var outcomes: [CPMBackgroundLoadRestartOutcome] = []
    var onOutcome: ((CPMBackgroundLoadRestartOutcome) -> Void)?

    func fire(_ event: WebExtensionPixelEvent) {
        guard case .cpmBackgroundLoadRestart(let outcome) = event else { return }
        outcomes.append(outcome)
        onOutcome?(outcome)
    }
}

@available(macOS 15.4, iOS 18.4, *)
private final class CapturingCPMStartupPixels: WebExtensionPixelFiring {
    private(set) var missingResponseCount = 0

    func fire(_ event: WebExtensionPixelEvent) {
        if case .cpmStartupResponseMissing = event { missingResponseCount += 1 }
    }
}

@available(macOS 15.4, iOS 18.4, *)
private final class CapturingReloadErrorPixelFiring: WebExtensionPixelFiring {
    struct Record: Equatable {
        let type: DuckDuckGoWebExtensionType?
        let trigger: WebExtensionReloadTrigger
        let phase: WebExtensionReloadFailurePhase
        let errorDomain: String
        let errorCode: String
    }

    private(set) var records: [Record] = []

    func fire(_ event: WebExtensionPixelEvent) {
        guard case .reloadError(let type, let trigger, let phase, let error) = event else { return }
        let metadata = WebExtensionReloadErrorPixelMetadata(
            type: type,
            trigger: trigger,
            phase: phase,
            error: error
        )
        records.append(Record(
            type: type,
            trigger: trigger,
            phase: phase,
            errorDomain: metadata.parameters["d"] ?? "missing",
            errorCode: metadata.parameters["e"] ?? "missing"
        ))
    }
}

@available(macOS 15.4, iOS 18.4, *)
private final class EventCapturingPixelFiring: WebExtensionPixelFiring {
    private(set) var events: [String] = []

    func fire(_ event: WebExtensionPixelEvent) {
        switch event {
        case .bitwardenDailyActive(let isDefault):
            events.append("bitwarden dau, default: \(isDefault)")
        case .defaultPasswordManagerSet(let pixelExtension):
            events.append("default set: \(pixelExtension.parameterValue)")
        case .apiCompatibilityGaps(let catalogEntry, let version, let missingAPICount, let unsupportedURLCount):
            events.append("gaps \(catalogEntry.rawValue) \(version): \(missingAPICount) apis, \(unsupportedURLCount) urls")
        default:
            break
        }
    }
}

@available(macOS 15.4, iOS 18.4, *)
@MainActor
private final class CatalogNamingWebStore: ChromeWebStoreManaging {
    let entries: [String: ExtensionsCatalogSubfeature]

    init(entries: [String: ExtensionsCatalogSubfeature]) {
        self.entries = entries
    }

    var catalogExtensionIDs: [String] { [] }
    var learnMoreURL: URL? { nil }
    func status(for identifier: String) -> ChromeWebStoreStatus { .unknown }
    func install(identifier: String, downloadURL: URL) async -> Bool { false }
    func remove(identifier: String) async -> Bool { false }
    func catalogEntry(of identifier: String) -> ExtensionsCatalogSubfeature? { entries[identifier] }
    func listing(of subfeature: ExtensionsCatalogSubfeature) -> ChromeWebStoreListing? { nil }
}

@available(macOS 15.4, iOS 18.4, *)
@MainActor
private final class ApprovingPermissionPrompter: WebExtensionPermissionPrompting {
    func confirmInstallation(of webExtension: WKWebExtension, permissions: WebExtensionPermissionRequest) async -> WebExtensionPermissionInstallationPromptResult {
        .granted(privateDataAccess: false)
    }

    func confirmPermissions(_ permissions: WebExtensionPermissionRequest, for context: WKWebExtensionContext) async -> WebExtensionPermissionPromptResult {
        .granted
    }
}

/// A native messaging host that takes a while to start, like a real host process, and then records
/// every message the port delivers.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
private final class SlowStartingNativeMessagingHandler: WebExtensionNativeMessagingHandling {
    let receivedFirstMessage = XCTestExpectation(description: "The host received a port message")
    private(set) var receivedMessages: [Any] = []
    private let startupDelay: Duration

    init(startupDelay: Duration) {
        self.startupDelay = startupDelay
    }

    func connect(_ port: WKWebExtension.MessagePort,
                 applicationIdentifier: String?,
                 for context: WKWebExtensionContext) async throws {
        try await Task.sleep(for: startupDelay)
        port.messageHandler = { [weak self] message, _ in
            guard let self, let message else { return }
            Task { @MainActor in
                self.receivedMessages.append(message)
                self.receivedFirstMessage.fulfill()
            }
        }
    }

    func sendMessage(_ message: Any,
                     applicationIdentifier: String?,
                     for context: WKWebExtensionContext) async throws -> Any? {
        nil
    }
}
