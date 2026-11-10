//
//  WebExtensionManager.swift
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

import Combine
import Foundation
import PrivacyConfig
import os.log
import Persistence
import WebKit

/// Manages web extensions including installation, loading, and lifecycle.
/// Platform-specific behavior is delegated to the windowTabProvider and lifecycleDelegate.
@available(macOS 15.4, iOS 18.4, *)
open class WebExtensionManager: NSObject, WebExtensionManaging, WebExtensionInstallationPathResolving {

    private enum Selector {
        static let backgroundWebView = NSSelectorFromString("_backgroundWebView")
    }

    private enum InstalledExtensionsLoadLifecycle {
        case initial
        case reloadAll(trigger: WebExtensionReloadTrigger, identifiers: Set<String>)
        /// Completes lifecycle reporting for identifiers whose data-clearing unload already emitted `willReload`.
        case reloadFallback(trigger: WebExtensionReloadTrigger, identifiers: Set<String>)

        func reloadFailureContext(for identifier: String) -> (trigger: WebExtensionReloadTrigger, phase: WebExtensionReloadFailurePhase)? {
            switch self {
            case .initial:
                return nil
            case .reloadAll(let trigger, let identifiers):
                return identifiers.contains(identifier) ? (trigger, .fullLoad) : nil
            case .reloadFallback(let trigger, let identifiers):
                return identifiers.contains(identifier) ? (trigger, .fallbackLoad) : nil
            }
        }

        func loadSucceededEvent(identifier: String, type: DuckDuckGoWebExtensionType?) -> WebExtensionLifecycleEvent? {
            switch self {
            case .initial:
                return .loaded(identifier: identifier, type: type)
            case .reloadAll(let trigger, let identifiers):
                guard identifiers.contains(identifier) else { return nil }
                return .reloaded(identifier: identifier, type: type, trigger: trigger)
            case .reloadFallback(let trigger, let identifiers):
                guard identifiers.contains(identifier) else { return nil }
                return .reloaded(identifier: identifier, type: type, trigger: trigger)
            }
        }

        func loadFailedEvent(identifier: String, type: DuckDuckGoWebExtensionType?) -> WebExtensionLifecycleEvent? {
            switch self {
            case .reloadAll(let trigger, let identifiers):
                guard identifiers.contains(identifier) else { return nil }
                return .reloadFailed(identifier: identifier, type: type, trigger: trigger)
            case .reloadFallback(let trigger, let identifiers):
                guard identifiers.contains(identifier) else { return nil }
                return .reloadFailed(identifier: identifier, type: type, trigger: trigger)
            case .initial:
                return nil
            }
        }
    }

    private struct InstalledExtensionsLoadSummary {
        var failures: [(identifier: String, error: Error)] = []
        var successCount = 0
        var firstError: Error?
    }

    // MARK: - Dependencies

    public let installationStore: InstalledWebExtensionStoring
    public let storageProvider: WebExtensionStorageProviding
    let cpmBaseURLPolicy: CPMExtensionBaseURLPolicy
    public let loader: WebExtensionLoading
    public let permissionController: WebExtensionPermissionController?
    public var chromeWebStore: ChromeWebStoreManaging?
    /// Disables extensions that remote configuration lists. `nil` until the host starts enforcement.
    public var remoteDisableEnforcer: WebExtensionRemoteDisableEnforcer?
    let controller: WKWebExtensionController
    public var eventsListener: WebExtensionEventsListening { listener }
    private let listener = WebExtensionEventsListener()

    /// Resolves shipped extension resources; tests can supply temporary fixtures.
    let bundledExtensionURL: (EmbeddedWebExtensionDescriptor) -> URL?

    /// Platform-specific window/tab operations.
    public let windowTabProvider: WebExtensionWindowTabProviding

    /// Platform-specific lifecycle hooks.
    public private(set) weak var lifecycleDelegate: WebExtensionLifecycleDelegate?

    /// Optional internal site handler for platform-specific URL handling.
    public private(set) var internalSiteHandler: (any WebExtensionInternalSiteHandling)?

    /// Message router for handling native messages from extensions.
    public let messageRouter: WebExtensionMessageRouting

    /// Provider for creating extension-specific message handlers.
    public private(set) var handlerProvider: WebExtensionHandlerProviding?

    /// Talks to native messaging hosts. `nil` where hosts are unavailable, such as on iOS.
    let nativeMessagingHandler: WebExtensionNativeMessagingHandling?

    /// Coordinator for managing scriptlet installation to extensions (created internally from scriptlet configuration).
    private(set) var scriptletCoordinator: WebExtensionScriptletCoordinator?

    /// The scriptlet configuration, if scriptlet support is enabled.
    private let scriptletConfiguration: ScriptletConfiguration?

    /// Tracks whether `loadInstalledExtensions()` is currently running.
    /// Used to prevent `syncEmbeddedExtensions` from interleaving during load,
    /// which can cause race conditions where sync deletes files that load still needs.
    @MainActor
    private(set) var isLoadingInstalledExtensions = false

    /// Parsed extensions captured by `unloadAllExtensions()` so that `reloadInstalledExtensions()`
    /// can re-create their contexts without re-reading and re-parsing them from disk. Cleared once
    /// consumed by a reload.
    private var unloadedExtensionsCache: [String: WKWebExtension] = [:]
    /// Invalidated by user/lifecycle mutations so a suspended update cannot commit stale state.
    private var extensionUpdateGenerations: [String: UUID] = [:]
    private lazy var extensionUpdateTransactions = WebExtensionUpdateTransactionStore(extensionsDirectory: storageProvider.extensionsDirectory,
                                                                                   fileManager: storageProvider.fileManager)
    weak var startupUpdateInstaller: ChromeWebStoreUpdateInstaller?
    /// A failed debug-state write retains the transaction for retry without failing an already committed update.
    var didCommitStoreUpdate: (InstalledWebExtension, UUID?) -> Bool = { _, _ in true }
    private var updateRecoveryBlockedIdentifiers: Set<String> = []
    private var retainedUpdateIdentifiers: Set<String> = []
    /// Distinguishes the next full load as restoration after data clearing rather than initial startup.
    private var isDataClearingReloadPending = false
    /// Extensions whose data-clearing reload lifecycle began before their contexts were unloaded.
    private var dataClearingReloadIdentifiers: Set<String> = []

    /// Store identities available before a successful first load creates the installation record.
    var installingStoreIdentities: [String: WebExtensionStoreIdentity] = [:]

    /// Tasks that keep background pages with open native messaging ports loaded, by extension identifier.
    var nativePortKeepAliveTasks: [String: NativePortKeepAlive] = [:]

    /// See `WebExtensionUnloadGuard`. Settable only so tests can inject a controlled clock.
    var unloadGuard: WebExtensionUnloadGuard

    /// Receives the API compatibility reports of extension pages.
    private let apiCompatibilityHandler: WebExtensionAPICompatibilityMessageHandler

#if os(macOS)
    /// The keyboard shortcuts the user picked for extension commands. `nil` without a key-value store.
    public let commandShortcuts: WebExtensionCommandShortcutStore?

    /// The `chrome.privacy.services` values extensions set, which let one take over DuckDuckGo autofill.
    /// `nil` without a key-value store.
    public let privacySettings: WebExtensionPrivacySettingsStore?
#endif

    private let storePixelsReporter: WebExtensionStorePixelsReporter?

    /// Deduplicates compatibility issues reported by JavaScript and native extension APIs.
    private let compatibilityReporter: WebExtensionAPICompatibilityReporter

#if os(macOS)
    /// Answers `chrome.idle.queryState` for extension pages.
    private let idleHandler = WebExtensionIdleMessageHandler()

    /// Answers `chrome.privacy.services` calls for extension pages.
    private let privacyHandler = WebExtensionPrivacyMessageHandler()
    private let permissionsHandler = WebExtensionPermissionsMessageHandler()
#endif

    /// The badge colors extensions set, which WebKit doesn't pass to the app.
    public let badgeColors = WebExtensionBadgeColorStore()

    private let badgeColorHandler = WebExtensionBadgeColorMessageHandler()

    /// Pixel firing for analytics.
    let pixelFiring: WebExtensionPixelFiring
    /// Shared monitor because all tabs communicate through the same embedded-extension process.
    public let cpmMessagingHealthMonitor: CPMMessagingHealthMonitoring
    /// Passive state recorder used to attribute CPM failures without changing recovery behavior.
    public let cpmDiagnosticsRecorder: CPMMessagingDiagnosticsRecorder?
    /// Reads the runtime kill switch immediately before a CPM messaging hang recovery reload.
    private let isCPMMessagingHangRecoveryEnabled: @MainActor () -> Bool
    /// Captured at manager creation so one startup cannot mix the enabled and disabled upgrade paths.
    public let isCPMUpgradeBeforeLoadEnabled: Bool
    /// Independent kill switch for retrying a failed background load in its current context.
    private let isCPMBackgroundLoadRecoveryEnabled: @MainActor () -> Bool
    /// Independent kill switch for restarting the context when a failed background view is still retained.
    private let isCPMBackgroundLoadRestartEnabled: @MainActor () -> Bool
    /// Platform lifecycle state must remain available when diagnostics are disabled.
    private let isApplicationInBackground: @MainActor () -> Bool

    /// Concurrent navigations share one wake; a replacement context must start its own preparation.
    private weak var preferredEmbeddedBackgroundContext: WKWebExtensionContext?
    private var embeddedBackgroundStartup: Task<Void, Never>?
    private weak var embeddedBackgroundStartupContext: WKWebExtensionContext?
    private var embeddedBackgroundStartupCompletion: AsyncStream<Void>.Continuation?
    private var isCPMMessagingRecoveryInProgress = false
    private var lastBackgroundLoadRecoveryAt: Date?
    private let backgroundLoadRecoveryCooldown: TimeInterval
    private var backgroundLoadRecoveryCooldownTask: Task<Void, Never>?
    private struct BackgroundLoadRecoveryAttempt {
        weak var context: WKWebExtensionContext?
        weak var failedView: WKWebView?
    }
    private var pendingBackgroundLoadRecovery: BackgroundLoadRecoveryAttempt?
    private var isBackgroundLoadRecoveryScheduled = false
    private var backgroundLoadErrorObserver: NSObjectProtocol?
    /// WebKit can retain historical errors after recovery. Weak keys keep generations independent.
    private let observedBackgroundLoadErrors = NSMapTable<WKWebExtensionContext, NSArray>.weakToStrongObjects()
    private var backgroundStartupFix: [String: CPMRecoveryFix] = [:]
    private weak var backgroundLoadRestartContext: WKWebExtensionContext?
    /// Three restarts without an attributed response; four means the exhausted budget was reported.
    private var backgroundLoadRestartAttempts = 0
    private var navigationWaitContexts: Set<String> = []
    /// Distinguishes first startup from idle wakes without retaining replaced contexts.
    private let preparedEmbeddedBackgroundContexts = NSHashTable<WKWebExtensionContext>.weakObjects()
    @MainActor
    private var backgroundRecovery: CPMBackgroundReadinessRecovery? {
        (cpmMessagingHealthMonitor as? CPMMessagingHealthMonitor)?.backgroundReadinessRecovery
    }
    private let now: () -> Date
    /// Keeps the health monitor informed of app suspension for as long as the manager lives.
    private var cpmInterruptionObserver: CPMInterruptionObserver?

    private let cpmNetworkProcessRecovery: CPMNetworkProcessRecovery

    // MARK: - AsyncStream

    private var continuation: AsyncStream<Void>.Continuation?
    public private(set) lazy var extensionUpdates = AsyncStream<Void> { [weak self] continuation in
        self?.continuation = continuation
    }
    /// Continuation retained for observers of detailed extension lifecycle transitions.
    private var lifecycleEventsContinuation: AsyncStream<WebExtensionLifecycleEvent>.Continuation?
    public private(set) lazy var lifecycleEvents = AsyncStream<WebExtensionLifecycleEvent> { [weak self] continuation in
        self?.lifecycleEventsContinuation = continuation
    }

    // MARK: - Init

    @MainActor
    public init(configuration: WebExtensionConfigurationProviding,
                controllerConfiguration: WKWebExtensionController.Configuration? = nil,
                windowTabProvider: WebExtensionWindowTabProviding,
                storageProvider: WebExtensionStorageProviding,
                installationStore: InstalledWebExtensionStoring = InstalledWebExtensionStore(),
                permissionController: WebExtensionPermissionController? = nil,
                loader: WebExtensionLoading? = nil,
                lifecycleDelegate: WebExtensionLifecycleDelegate? = nil,
                internalSiteHandler: (any WebExtensionInternalSiteHandling)? = nil,
                pixelFiring: WebExtensionPixelFiring = NoOpWebExtensionPixelFiring(),
                cpmMessagingHealthMonitor: CPMMessagingHealthMonitoring? = nil,
                cpmDiagnosticsRecorder: CPMMessagingDiagnosticsRecorder? = nil,
                isCPMMessagingHangRecoveryEnabled: @escaping @MainActor () -> Bool = { true },
                isCPMNetworkProcessRecoveryEnabled: @escaping @MainActor () -> Bool = { false },
                cpmNetworkProcessRecoveryFeatureFlagUpdates: AnyPublisher<Void, Never>? = nil,
                isCPMBackgroundLoadRecoveryEnabled: @escaping @MainActor () -> Bool = { true },
                isCPMBackgroundLoadRestartEnabled: @escaping @MainActor () -> Bool = { false },
                backgroundLoadRecoveryCooldown: TimeInterval = 60,
                isApplicationInBackground: @escaping @MainActor () -> Bool = { false },
                isCPMLateBackgroundDocumentRecoveryEnabled: @escaping @MainActor () -> Bool = { false },
                isCPMStableBaseURLEnabled: @escaping @MainActor () -> Bool = { false },
                isCPMUpgradeBeforeLoadEnabled: Bool = false,
                messageRouter: WebExtensionMessageRouting? = nil,
                handlerProvider: WebExtensionHandlerProviding? = nil,
                nativeMessagingHandler: WebExtensionNativeMessagingHandling? = nil,
                keyValueStore: (any ThrowingKeyValueStoring)? = nil,
                retentionStore: WebExtensionRetentionStore? = nil,
                isAutofillTakeoverEnabled: @escaping @MainActor () -> Bool = { true },
                scriptletConfiguration: ScriptletConfiguration? = nil,
                bundledExtensionURL: @escaping (EmbeddedWebExtensionDescriptor) -> URL? = { $0.bundledURL },
                now: @escaping () -> Date = Date.init) {
        let compatibilityReporter = WebExtensionAPICompatibilityReporter()
        self.compatibilityReporter = compatibilityReporter
        self.apiCompatibilityHandler = WebExtensionAPICompatibilityMessageHandler(reporter: compatibilityReporter)
        let controllerConfiguration = controllerConfiguration ?? WKWebExtensionController.Configuration.default()
        controllerConfiguration.webViewConfiguration.applicationNameForUserAgent = configuration.applicationNameForUserAgent

        // The API compatibility script, which `WebExtensionLoader` adds for each third-party extension,
        // reports which unsupported APIs the extension touches, for the API compatibility log.
        controllerConfiguration.webViewConfiguration.userContentController.add(apiCompatibilityHandler,
                                                                                name: WebExtensionAPICompatibilityScript.messageHandlerName)

#if os(macOS)
        // `chrome.idle.queryState` asks the app for the idle state and waits for the reply.
        controllerConfiguration.webViewConfiguration.userContentController.addScriptMessageHandler(
            idleHandler, contentWorld: .page, name: WebExtensionAPIStubScript.idleMessageHandlerName)
        // `chrome.privacy.services` settings are kept by the app, which decides who controls each one.
        controllerConfiguration.webViewConfiguration.userContentController.addScriptMessageHandler(
            privacyHandler, contentWorld: .page, name: WebExtensionAPIStubScript.privacyMessageHandlerName)
        // `chrome.permissions` asks the app for the permissions WebKit doesn't know, such as `privacy`.
        controllerConfiguration.webViewConfiguration.userContentController.addScriptMessageHandler(
            permissionsHandler, contentWorld: .page, name: WebExtensionAPIStubScript.permissionsMessageHandlerName)
#endif
        controllerConfiguration.webViewConfiguration.userContentController.add(
            badgeColorHandler, contentWorld: .page, name: WebExtensionAPIStubScript.badgeColorMessageHandlerName)

        self.controller = WKWebExtensionController(configuration: controllerConfiguration)

        self.windowTabProvider = windowTabProvider
        self.storageProvider = storageProvider
        self.installationStore = installationStore
        self.permissionController = permissionController
        self.bundledExtensionURL = bundledExtensionURL
        let baseURLPolicy = CPMExtensionBaseURLPolicy(installationStore: installationStore, isEnabled: isCPMStableBaseURLEnabled)
        self.cpmBaseURLPolicy = baseURLPolicy
        self.loader = loader ?? WebExtensionLoader(storageProvider: storageProvider,
                                                   isInspectable: configuration.isInspectable,
                                                   permissionController: permissionController,
                                                   baseURLProvider: baseURLPolicy.baseURL)
        self.lifecycleDelegate = lifecycleDelegate
        self.internalSiteHandler = internalSiteHandler
        self.pixelFiring = pixelFiring
        self.now = now
        self.cpmMessagingHealthMonitor = cpmMessagingHealthMonitor ?? CPMMessagingHealthMonitor(pixelFiring: pixelFiring)
        (self.cpmMessagingHealthMonitor as? CPMMessagingHealthMonitor)?.backgroundReadinessRecovery = CPMBackgroundReadinessRecovery(
            isEnabled: isCPMLateBackgroundDocumentRecoveryEnabled,
            isApplicationInBackground: isApplicationInBackground,
            pixelFiring: pixelFiring
        )
        self.cpmDiagnosticsRecorder = cpmDiagnosticsRecorder
        self.isCPMMessagingHangRecoveryEnabled = isCPMMessagingHangRecoveryEnabled
        self.isCPMUpgradeBeforeLoadEnabled = isCPMUpgradeBeforeLoadEnabled
        self.cpmNetworkProcessRecovery = CPMNetworkProcessRecovery(
            isEnabled: isCPMNetworkProcessRecoveryEnabled,
            featureFlagUpdates: cpmNetworkProcessRecoveryFeatureFlagUpdates,
            pixelFiring: pixelFiring
        )
        self.isCPMBackgroundLoadRecoveryEnabled = isCPMBackgroundLoadRecoveryEnabled
        self.isCPMBackgroundLoadRestartEnabled = isCPMBackgroundLoadRestartEnabled
        self.backgroundLoadRecoveryCooldown = backgroundLoadRecoveryCooldown
        self.isApplicationInBackground = isApplicationInBackground
        self.messageRouter = messageRouter ?? WebExtensionMessageRouter()
        self.handlerProvider = handlerProvider
        self.nativeMessagingHandler = nativeMessagingHandler
        self.storePixelsReporter = retentionStore.map { WebExtensionStorePixelsReporter(store: $0, installationStore: installationStore, pixelFiring: pixelFiring, now: now) }
#if os(macOS)
        self.commandShortcuts = keyValueStore.map { WebExtensionCommandShortcutStore(keyValueStore: $0) }
        self.privacySettings = keyValueStore.map { WebExtensionPrivacySettingsStore(keyValueStore: $0) }
#endif
        self.scriptletConfiguration = scriptletConfiguration
        self.unloadGuard = WebExtensionUnloadGuard()

        super.init()

        badgeColorHandler.store = badgeColors
        badgeColorHandler.extensionContext = { [weak self] url in
            self?.extensionContext(for: url)
        }

        apiCompatibilityHandler.resolveExtension = { [weak self] url in
            guard let webExtension = self?.extensionContext(for: url)?.webExtension else { return nil }
            return (WebExtensionAPICompatibilityLog.sanitizedField(webExtension.displayName),
                    WebExtensionAPICompatibilityLog.sanitizedField(webExtension.version))
        }

#if os(macOS)
        idleHandler.isLoadedExtension = { [weak self] url in
            self?.extensionContext(for: url) != nil
        }

        privacyHandler.store = privacySettings
        privacyHandler.extensionIdentifier = { [weak self] url in
            self?.extensionContext(for: url)?.uniqueIdentifier
        }
        permissionsHandler.controller = permissionController
        permissionsHandler.extensionContext = { [weak self] url in
            self?.extensionContext(for: url)
        }
        // Granting `privacy` can make an extension's earlier setting count; taking it back hands autofill
        // back to DuckDuckGo, so the extension's settings go too.
        permissionController?.appPermissionsDidChange = { [weak self] identifier in
            guard let self, let privacySettings else { return }
            if permissionController?.isGranted(.privacy, to: identifier) != true {
                privacySettings.removeSettings(for: identifier)
            }
            privacySettings.notifyControlMayHaveChanged()
        }
        launchDate = now()
        listener.onBrowsingActivity = { [weak self] in
            MainActor.assumeIsolated {
                self?.fireBitwardenDailyActiveIfLoaded()
                self?.fireAPICompatibilityGapsIfDue()
                self?.storePixelsReporter?.reportIfDue(chromeWebStore: self?.chromeWebStore)
            }
        }
        apiCompatibilityHandler.onIssue = { [weak self] issue, url in
            MainActor.assumeIsolated {
                guard let identifier = self?.extensionContext(for: url)?.uniqueIdentifier else { return }
                self?.recordAPICompatibilityIssue(issue, for: identifier)
            }
        }
        privacySettings?.onDefaultPasswordManagerSet = { [weak self] identifier in
            guard let self else { return }
            let storeIdentity = installationStore.installedExtension(withUniqueIdentifier: identifier)?.storeIdentity
            pixelFiring.fire(.defaultPasswordManagerSet(extension: pixelExtension(for: storeIdentity)))
        }
        // Only a loaded extension that declares `privacy` and that the user granted it can take over autofill,
        // and only while the app allows it. Without a permission controller nothing is granted.
        privacySettings?.canControl = { [weak self] identifier in
            guard let self, isAutofillTakeoverEnabled(),
                  context(for: identifier)?.webExtension.declaresPermission(WebExtensionPrivacySettingsStore.permission) == true else {
                return false
            }
            return permissionController?.isGranted(.privacy, to: identifier) == true
        }
#endif

        if let scriptletConfiguration {
            let coordinator = WebExtensionScriptletCoordinator(
                scriptletProvider: scriptletConfiguration.provider,
                installationTracker: scriptletConfiguration.installationTracker,
                installer: scriptletConfiguration.installer,
                pixelFiring: scriptletConfiguration.pixelFiring,
                cacheRootDirectory: scriptletConfiguration.cacheRootDirectory,
                installationPathResolver: self
            )
            self.scriptletCoordinator = coordinator
        }

        controller.delegate = self
        self.loader.delegate = self

        configureCPMMonitoring()
    }

    @MainActor
    private func configureCPMMonitoring() {
        if let cpmDiagnosticsRecorder {
            (self.cpmMessagingHealthMonitor as? CPMMessagingHealthMonitor)?.diagnosticsProvider = cpmDiagnosticsRecorder
            cpmDiagnosticsRecorder.nativeMessageHandlerCheck = { [weak self] context in
                self?.messageRouter.hasHandler(for: context.uniqueIdentifier, featureName: "autoconsent") ?? false
            }
        }

        if let healthMonitor = self.cpmMessagingHealthMonitor as? CPMMessagingHealthMonitor {
            healthMonitor.isCurrentEmbeddedExtension = { [weak self] identifier in
                guard let self, !self.isCPMMessagingRecoveryInProgress else { return false }
                return self.embeddedBackgroundContextForNavigation?.uniqueIdentifier == identifier
            }
            healthMonitor.onHealthyResponse = { [weak self] in
                self?.backgroundLoadRestartAttempts = 0
            }
            healthMonitor.onConfirmedHang = { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.reloadEmbeddedExtensionAfterCPMMessagingHang()
                }
            }
        }
        self.cpmInterruptionObserver = CPMInterruptionObserver(monitor: cpmMessagingHealthMonitor) { [weak self] in
            self?.resumePendingBackgroundLoadRecovery()
        }

        backgroundLoadErrorObserver = NotificationCenter.default.addObserver(
            forName: WKWebExtensionContext.errorsDidUpdateNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let context = notification.object as? WKWebExtensionContext else { return }
            MainActor.assumeIsolated {
                guard let self, self.context(for: context.uniqueIdentifier) === context else { return }
                let errors = context.errors.map(NSError.webKitSafe).filter(\.isBackgroundContentLoadFailure)
                var previousErrors = self.observedBackgroundLoadErrors.object(forKey: context) as? [NSError] ?? []
                // Consume equal historical entries individually: another equal entry is a new failure.
                let newErrors = errors.filter { error in
                    guard let index = previousErrors.firstIndex(where: { $0.isEqual(error) }) else { return true }
                    previousErrors.remove(at: index)
                    return false
                }
                self.observedBackgroundLoadErrors.setObject(errors as NSArray, forKey: context)
                guard let error = newErrors.first else { return }
                self.cpmBaseURLPolicy.recordBackgroundLoadFailure(in: context, errors: [error])
                // WebKit can record a service-worker load failure without invoking pending
                // loadBackgroundContent callbacks. Release callers before retrying its background.
                if self.embeddedBackgroundStartupContext === context {
                    // Retained callbacks may succeed with a later retry. They must not turn this
                    // known failed startup into a P4 detection or an automatic document reload.
                    self.backgroundRecovery?.invalidate()
                    self.clearEmbeddedBackgroundStartup()
                }
                // Capture the failing view on this notification's turn, before WebKit can replace it.
                self.recoverEmbeddedBackgroundLoadFailure(error, context: context)
            }
        }
    }

    deinit {
        backgroundLoadRecoveryCooldownTask?.cancel()
        if let backgroundLoadErrorObserver {
            NotificationCenter.default.removeObserver(backgroundLoadErrorObserver)
        }
    }

    // MARK: - Computed Properties

    public var contexts: [WKWebExtensionContext] {
        Array(controller.extensionContexts)
    }

    public var webExtensionIdentifiers: [String] {
        installationStore.installedExtensions.map(\.uniqueIdentifier)
    }

    public var loadedExtensions: Set<WKWebExtensionContext> {
        controller.extensionContexts
    }

    public var extensionsDirectory: URL {
        storageProvider.extensionsDirectory
    }

    /// Whether the embedded autoconsent web extension is loaded and active.
    public var isAutoconsentExtensionLoaded: Bool {
        contexts.contains { $0.duckDuckGoWebExtensionType == .embedded }
    }

    // MARK: - Install/Uninstall

    @MainActor
    public func installExtension(from sourceURL: URL) async throws {
        try await installExtension(from: sourceURL, storeIdentity: nil, replacing: nil)
    }

    @MainActor
    // swiftlint:disable:next cyclomatic_complexity
    public func installExtension(from sourceURL: URL,
                                 storeIdentity: WebExtensionStoreIdentity?,
                                 replacing oldIdentifier: String? = nil) async throws {
        Logger.webExtensions.debug("🔄 Installing extension from: \(sourceURL.path)")

        if let oldIdentifier {
            extensionUpdateGenerations.removeValue(forKey: oldIdentifier)
            await startupUpdateInstaller?.cancelAndWait()
            guard let storeIdentity,
                  let installed = installationStore.installedExtension(withUniqueIdentifier: oldIdentifier),
                  installed.storeIdentity == storeIdentity else {
                throw WebExtensionError.updateIdentityMismatch
            }
        }

        let metadata = try await WKWebExtension.metadata(from: sourceURL)
        let identifier = UUID().uuidString
        var embeddedType = storeIdentity == nil ? metadata.type : nil

        if embeddedType != nil, let permissionController {
            // A manifest's DDG identifier is not proof that it came from the app bundle. Verify its source URL, too.
            let isBundled = EmbeddedWebExtensionRegistry.all.contains {
                bundledExtensionURL($0)?.standardizedFileURL == sourceURL.standardizedFileURL
            }
            if isBundled {
                permissionController.trustedInstallations.insert(identifier)
            } else {
                embeddedType = nil
            }
        }
        defer { permissionController?.trustedInstallations.remove(identifier) }

        if metadata.requiresExtraction {
            _ = try storageProvider.extractExtension(from: sourceURL, identifier: identifier)
        } else {
            _ = try storageProvider.copyExtension(from: sourceURL, identifier: identifier)
        }

        Logger.webExtensions.debug("🔄 Extension stored with identifier: \(identifier)")

        var replacedContext: WKWebExtensionContext?
        do {
            if let oldIdentifier {
                try permissionController?.copyPermissionsForUpdate(from: oldIdentifier, to: identifier)
#if os(macOS)
                commandShortcuts?.copyShortcutsForUpdate(from: oldIdentifier, to: identifier)
                privacySettings?.copySettingsForUpdate(from: oldIdentifier, to: identifier)
#endif
            }
            if storeIdentity?.store == .chromeWebStore,
               let oldIdentifier, let oldContext = context(for: oldIdentifier) {
                // Both versions use the same origin, so only one can be loaded at a time.
                await unloadGuard.awaitSettled(oldContext)
                try loader.unloadExtension(identifier: oldIdentifier, from: controller)
                replacedContext = oldContext
                cpmNetworkProcessRecovery.stopWatching(identifier: oldIdentifier)
                cpmDiagnosticsRecorder?.contextDidUnload(identifier: oldIdentifier)
                unregisterHandlers(for: oldIdentifier)
            }
            installingStoreIdentities[identifier] = storeIdentity
            defer { installingStoreIdentities.removeValue(forKey: identifier) }
            let loadResult = try await loader.loadWebExtension(identifier: identifier, into: controller)
            unloadGuard.recordLoad(of: identifier)

            let webExtension = context(for: identifier)?.webExtension
            let installedExtension = InstalledWebExtension(
                uniqueIdentifier: identifier,
                filename: loadResult.filename,
                name: loadResult.displayName,
                version: loadResult.version,
                embeddedType: embeddedType,
                storeIdentity: storeIdentity,
                permissions: webExtension?.requiredPermissionNames,
                matchPatterns: webExtension?.allRequestedMatchPatterns.map(\.string)
            )

            installationStore.add(installedExtension)
            reportLifecycleEvent(.loaded(identifier: identifier, type: embeddedType))

            Logger.webExtensions.info("✅ Successfully installed extension \(installedExtension.filename) v\(installedExtension.version ?? "unknown") (\(identifier))")
            reportInstalled(storeIdentity: storeIdentity, replacing: oldIdentifier)

            if let type = embeddedType {
                await scriptletCoordinator?.onExtensionEnabled(for: type)
            }
        } catch {
            unregisterHandlers(for: identifier)
            do {
                try permissionController?.forget(identifier)
            } catch {
                Logger.webExtensions.error("Failed to remove extension consent after installation failure: \(error.localizedDescription)")
            }
#if os(macOS)
            commandShortcuts?.removeShortcuts(for: identifier)
            privacySettings?.removeSettings(for: identifier)
#endif
            try? storageProvider.removeExtension(identifier: identifier)

            if let replacedContext {
                let oldIdentifier = replacedContext.uniqueIdentifier
                do {
                    try await permissionController?.prepare(replacedContext)
                    webExtensionLoader(loader, willLoad: replacedContext, identifier: oldIdentifier)
                    try controller.loadCopyingErrors(replacedContext)
                    unloadGuard.recordLoad(of: oldIdentifier)
                } catch {
                    permissionController?.didUnload(oldIdentifier)
                    unregisterHandlers(for: oldIdentifier)
                    Logger.webExtensions.error("Failed to restore extension after replacement failure: \(error.localizedDescription)")
                }
                notifyUpdate()
            }

            if let preparationError = error as? WebExtensionLoader.PermissionPreparationError,
               let permissionError = preparationError.underlyingError as? WebExtensionPermissionController.PermissionError,
               case .installationDenied = permissionError {
                Logger.webExtensions.info("Extension installation cancelled by the user (\(identifier))")
                throw WebExtensionError.installationCancelled
            }

            Logger.webExtensions.error("❌ Failed to load extension '\(identifier)': \(error.localizedDescription)")
            pixelFiring.fire(.installError(extension: pixelExtension(for: storeIdentity), error: error))
            throw WebExtensionError.failedToLoadWebExtension(error)
        }

        notifyUpdate()
        if let storeIdentity, storeIdentity.store == .chromeWebStore {
            NotificationCenter.default.post(name: .chromeWebStoreExtensionChanged, object: self,
                                            userInfo: ["extensionId": storeIdentity.id])
        }
    }

    @MainActor
    public func uninstallExtension(identifier: String) throws {
        extensionUpdateGenerations.removeValue(forKey: identifier)
        startupUpdateInstaller?.uninstalling(identifier)
        retainedUpdateIdentifiers.remove(identifier)
        updateRecoveryBlockedIdentifiers.remove(identifier)
        Logger.webExtensions.debug("🔄 Uninstalling extension '\(identifier)'")

        let installedExtension = installationStore.installedExtension(withUniqueIdentifier: identifier)
        let embeddedType = installedExtension?.embeddedType
        let removesCurrentEmbeddedContext = embeddedBackgroundContextForNavigation?.uniqueIdentifier == identifier

        do {
            try loader.unloadExtension(identifier: identifier, from: controller)
            cpmNetworkProcessRecovery.stopWatching(identifier: identifier)
            cpmDiagnosticsRecorder?.contextDidUnload(identifier: identifier)
            Logger.webExtensions.debug("✅ Unloaded extension '\(identifier)' from memory")
        } catch {
            if context(for: identifier) != nil {
                throw WebExtensionError.failedToUnloadWebExtension(error)
            }
            Logger.webExtensions.debug("⚠️ Extension '\(identifier)' was not loaded in memory: \(error.localizedDescription)")
            cpmDiagnosticsRecorder?.contextUnloadFailed(identifier: identifier, error: error)
        }

        if removesCurrentEmbeddedContext {
            // A preflight can still be suspended after startup completed. Do not reload its
            // document after uninstall, or cancel the replacement when removing an old version.
            backgroundRecovery?.invalidate()
        }
        clearEmbeddedBackgroundStartup(identifier: identifier)
        do {
            try permissionController?.forget(identifier)
        } catch {
            // Consent cleanup must not leave an unloaded extension installed.
            Logger.webExtensions.error("Could not remove extension permissions during uninstall: \(error.localizedDescription)")
        }
#if os(macOS)
        commandShortcuts?.removeShortcuts(for: identifier)
        privacySettings?.removeSettings(for: identifier)
#endif
        installationStore.remove(uniqueIdentifier: identifier)
        unloadedExtensionsCache.removeValue(forKey: identifier)
        dataClearingReloadIdentifiers.remove(identifier)
        unregisterHandlers(for: identifier)
        if let embeddedType {
            scriptletCoordinator?.onExtensionDisabled(for: embeddedType)
        }

        do {
            try storageProvider.removeExtension(identifier: identifier)
        } catch {
            Logger.webExtensions.error("❌ Failed to remove extension files for '\(identifier)': \(error.localizedDescription)")
            cpmDiagnosticsRecorder?.extensionFilesRemoveFailed(identifier: identifier, error: error)
            pixelFiring.fire(.uninstallError(error: error))
            throw WebExtensionError.failedToRemoveWebExtension(error)
        }

        Logger.webExtensions.info("✅ Successfully uninstalled extension '\(identifier)'")
        reportUninstalled(installedExtension)
        notifyUpdate()
        if let storeIdentity = installedExtension?.storeIdentity, storeIdentity.store == .chromeWebStore {
            NotificationCenter.default.post(name: .chromeWebStoreExtensionChanged, object: self,
                                            userInfo: ["extensionId": storeIdentity.id])
        }
    }

    @MainActor
    @discardableResult
    public func uninstallAllExtensions() -> [Result<Void, Error>] {
        let installedExtensions = installationStore.installedExtensions
        Logger.webExtensions.debug("🔄 Uninstalling all extensions (count: \(installedExtensions.count))")

        let results: [Result<Void, Error>] = installedExtensions.map { ext in
            do {
                try uninstallExtension(identifier: ext.uniqueIdentifier)
                return .success(())
            } catch {
                return .failure(error)
            }
        }

        let successCount = results.filter { if case .success = $0 { return true } else { return false } }.count
        let failureCount = results.count - successCount
        if failureCount > 0 {
            Logger.webExtensions.error("❌ Uninstall all completed with errors: \(successCount) succeeded, \(failureCount) failed")
            if let firstError = results.compactMap({ result -> Error? in
                if case .failure(let error) = result { return error }
                return nil
            }).first {
                pixelFiring.fire(.uninstallAllError(error: firstError))
            }
        } else {
            Logger.webExtensions.info("✅ Uninstall all completed: \(successCount) extensions removed")
            pixelFiring.fire(.uninstalledAll)
        }

        storageProvider.cleanupOrphanedExtensions(keeping: Set(installationStore.installedExtensions.map(\.uniqueIdentifier)))

        return results
    }

    @MainActor
    public func unloadAllExtensions() {
        extensionUpdateGenerations.removeAll()
        startupUpdateInstaller?.cancelStartup()
        isDataClearingReloadPending = true
        let contexts = controller.extensionContexts
        Logger.webExtensions.debug("🔄 Unloading all extensions from memory (count: \(contexts.count))")

        var successCount = 0
        var failureCount = 0

        for context in contexts {
            let identifier = context.uniqueIdentifier
            let type = installationStore.installedExtension(withUniqueIdentifier: identifier)?.embeddedType
            reportLifecycleEvent(.willReload(identifier: identifier, type: type, trigger: .dataClearing))
            do {
                try controller.unloadCopyingErrors(context)
                cpmBaseURLPolicy.prepareForDataClearingReload(of: context)
                permissionController?.didUnload(identifier)
                cpmNetworkProcessRecovery.stopWatching(identifier: identifier)
                cpmDiagnosticsRecorder?.contextDidUnload(identifier: identifier)
                // Capture the parsed extension only after a confirmed unload, so the cache never
                // holds an extension still loaded in the controller. reloadInstalledExtensions()
                // uses it to re-create the context without re-reading and re-parsing from disk.
                unloadedExtensionsCache[identifier] = context.webExtension
                dataClearingReloadIdentifiers.insert(identifier)
                unregisterHandlers(for: identifier)
                successCount += 1
            } catch {
                Logger.webExtensions.error("❌ Failed to unload extension '\(identifier)': \(error.localizedDescription)")
                cpmDiagnosticsRecorder?.contextUnloadFailed(identifier: identifier, error: error)
                pixelFiring.fire(.reloadError(type: type,
                                              trigger: .dataClearing,
                                              phase: .unload,
                                              error: error))
                reportLifecycleEvent(.reloadFailed(identifier: identifier, type: type, trigger: .dataClearing))
                failureCount += 1
            }
        }

        if failureCount > 0 {
            Logger.webExtensions.warning("⚠️ Unload all completed with \(failureCount) error(s): \(successCount) succeeded, \(failureCount) failed")
        } else {
            Logger.webExtensions.debug("✅ Successfully unloaded \(successCount) extension(s) from memory")
        }
    }

    @MainActor
    public func clearCachedScriptlets() {
        scriptletConfiguration?.provider.clearCachedScriptlets()
    }

    /// Debug: moves pending store installs `interval` earlier, so the next browsing activity reports their retention.
    @MainActor
    public func backdateStoreInstalls(by interval: TimeInterval) {
        storePixelsReporter?.backdateInstalls(by: interval)
    }

    @MainActor
    public func scriptletDebugInfo() -> [ScriptletDebugInfo] {
        guard let config = scriptletConfiguration else { return [] }

        return DuckDuckGoWebExtensionType.allCases.compactMap { type in
            let cachedVersion = config.provider.scriptletVersion(for: type)
            let installedVersion = config.installationTracker.installedVersion(for: type)
            let scriptletPaths = config.provider.scriptlets(for: type)?.map(\.path)

            guard cachedVersion != nil || installedVersion != nil else { return nil }

            return ScriptletDebugInfo(
                extensionType: type,
                cachedVersion: cachedVersion,
                installedVersion: installedVersion,
                scriptletPaths: scriptletPaths ?? []
            )
        }
    }

    @MainActor
    public func reloadExtension(identifier: String) async throws {
        try await reloadExtension(identifier: identifier, trigger: .explicit)
    }

    @MainActor
    func reloadExtension(identifier: String, trigger: WebExtensionReloadTrigger) async throws {
        extensionUpdateGenerations.removeValue(forKey: identifier)
        await startupUpdateInstaller?.cancelAndWait()
        guard !updateRecoveryBlockedIdentifiers.contains(identifier) else { throw UpdateInstallationError.recoveryFailed }
        Logger.webExtensions.debug("🔄 Reloading extension '\(identifier)'")

        let type = installationStore.installedExtension(withUniqueIdentifier: identifier)?.embeddedType
        reportLifecycleEvent(.willReload(identifier: identifier, type: type, trigger: trigger))
        await unloadGuard.awaitSettled(context(for: identifier))

        let previousContext = context(for: identifier)
        let previousErrors = previousContext?.errors ?? []
        do {
            try loader.unloadExtension(identifier: identifier, from: controller)
            if let previousContext {
                cpmBaseURLPolicy.recordBackgroundLoadFailure(in: previousContext, errors: previousErrors)
            }
            cpmNetworkProcessRecovery.stopWatching(identifier: identifier)
            cpmDiagnosticsRecorder?.contextDidUnload(identifier: identifier)
        } catch {
            // The extension and its native handlers are still active when unload fails.
            cpmDiagnosticsRecorder?.contextUnloadFailed(identifier: identifier, error: error)
            pixelFiring.fire(.reloadError(type: type,
                                          trigger: trigger,
                                          phase: .unload,
                                          error: error))
            reportLifecycleEvent(.reloadFailed(identifier: identifier, type: type, trigger: trigger))
            throw error
        }

        // Safe to unregister up front only because the unload above succeeded: the context these
        // handlers served is gone, so the gap before `loadWebExtension` re-registers them is not a
        // window in which a live context is left without handlers. (An earlier revision unregistered
        // before the unload, which did open that window — hence the ordering here.)
        unregisterHandlers(for: identifier)

        do {
            _ = try await loader.loadWebExtension(identifier: identifier, into: controller)
            unloadGuard.recordLoad(of: identifier)
        } catch {
            // `loadWebExtension` registers handlers as part of loading, so a partially completed
            // load can leave some behind for a context that never became active. Clear them again.
            unregisterHandlers(for: identifier)
            pixelFiring.fire(.reloadError(type: type,
                                          trigger: trigger,
                                          phase: .load,
                                          error: error))
            reportLifecycleEvent(.reloadFailed(identifier: identifier, type: type, trigger: trigger))
            throw error
        }

        reportLifecycleEvent(.reloaded(identifier: identifier, type: type, trigger: trigger))
        Logger.webExtensions.info("✅ Reloaded extension '\(identifier)'")
        notifyUpdate()
    }

    @MainActor
    public func disableExtension(identifier: String) async throws {
        extensionUpdateGenerations.removeValue(forKey: identifier)
        await startupUpdateInstaller?.cancelAndWait()
        if isRemotelyDisabled(identifier: identifier) { startupUpdateInstaller?.uninstalling(identifier) }
        guard let installedExtension = installationStore.installedExtension(withUniqueIdentifier: identifier) else {
            throw WebExtensionError.extensionNotInstalled
        }
        guard !installedExtension.isEmbedded else {
            throw WebExtensionError.embeddedExtensionCannotBeDisabled
        }
        // A disabled extension can still be loaded when it was disabled while installed extensions were loading.
        guard !installedExtension.isDisabled || context(for: identifier) != nil else { return }

        Logger.webExtensions.debug("🔄 Disabling extension '\(identifier)'")
        await unloadGuard.awaitSettled(context(for: identifier))

        // An extension whose consent could not be read at launch is installed but has no context.
        if context(for: identifier) != nil {
            do {
                // The loader saves the extension's permissions before it forgets the context.
                try loader.unloadExtension(identifier: identifier, from: controller)
            } catch {
                Logger.webExtensions.error("❌ Failed to disable extension '\(identifier)': \(error.localizedDescription)")
                throw WebExtensionError.failedToUnloadWebExtension(error)
            }
        }
        unregisterHandlers(for: identifier)
        // Keep a pending data-clearing reload from loading the extension again.
        unloadedExtensionsCache.removeValue(forKey: identifier)
        dataClearingReloadIdentifiers.remove(identifier)

        var disabledExtension = installedExtension
        disabledExtension.isDisabled = true
        installationStore.update(disabledExtension)

        // Unloading an extension that was disabled while loading doesn't change its state.
        if !installedExtension.isDisabled {
            reportEnabledStateChange(isEnabled: false, storeIdentity: installedExtension.storeIdentity)
        }

        Logger.webExtensions.info("✅ Disabled extension '\(identifier)'")
        notifyUpdate()
    }

    /// Whether the extension is installed and not disabled. Loads re-check it after each suspension point,
    /// because the extension can be disabled while they wait.
    @MainActor
    private func isInstalledAndEnabled(_ identifier: String) -> Bool {
        installationStore.installedExtension(withUniqueIdentifier: identifier)?.isDisabled == false
    }

    /// Unloads an extension that was disabled while it was loading. Disabling found no context to unload
    /// then, so the load put the extension back into the controller.
    @MainActor
    private func unloadExtensionDisabledWhileLoading(_ identifier: String) async {
        guard installationStore.installedExtension(withUniqueIdentifier: identifier) != nil else {
            // A removed extension isn't recorded anymore, so unload its context directly.
            try? loader.unloadExtension(identifier: identifier, from: controller)
            unregisterHandlers(for: identifier)
            return
        }
        do {
            try await disableExtension(identifier: identifier)
        } catch {
            Logger.webExtensions.error("❌ Failed to unload extension '\(identifier)' disabled while loading: \(error.localizedDescription)")
        }
    }

    @MainActor
    public func enableExtension(identifier: String) async throws {
        let generation = beginStoreExtensionEnable(identifier: identifier)
        defer { endStoreExtensionEnable(identifier: identifier, generation: generation) }
        await startupUpdateInstaller?.cancelAndWait()
        try await validateStoreExtensionEnable(identifier: identifier, generation: generation, installed: nil)
        guard !updateRecoveryBlockedIdentifiers.contains(identifier) else { throw UpdateInstallationError.recoveryFailed }
        guard var installedExtension = installationStore.installedExtension(withUniqueIdentifier: identifier) else {
            throw WebExtensionError.extensionNotInstalled
        }
        guard installedExtension.isDisabled else { return }
        try await acknowledgeUpdateRegistryBeforeEnable(installedExtension, generation: generation)

        Logger.webExtensions.debug("🔄 Enabling extension '\(identifier)'")
        var enabledContext: WKWebExtensionContext?
        do {
            _ = try await loadStoreExtensionForEnable(installedExtension, generation: generation)
            enabledContext = context(for: identifier)
            unloadGuard.recordLoad(of: identifier)
        } catch {
            // A partially completed load can leave handlers behind for a context that never became active.
            unregisterHandlers(for: identifier)
            try await validateStoreExtensionEnable(identifier: identifier, generation: generation, installed: installedExtension,
                                                   ownedContext: context(for: identifier))
            guard let predecessor = try await enableRetainedPredecessor(installedExtension, generation: generation, originalFailure: error) else {
                Logger.webExtensions.error("❌ Failed to enable extension '\(identifier)': \(error.localizedDescription)")
                throw WebExtensionError.failedToLoadWebExtension(error)
            }
            installedExtension = predecessor
            enabledContext = context(for: identifier)
        }

        try await validateStoreExtensionEnable(identifier: identifier, generation: generation, installed: installedExtension, ownedContext: enabledContext)
        var enabledExtension = installedExtension
        enabledExtension.isDisabled = false
        installationStore.update(enabledExtension)
        reportLifecycleEvent(.loaded(identifier: identifier, type: nil))

        reportEnabledStateChange(isEnabled: true, storeIdentity: installedExtension.storeIdentity)

        Logger.webExtensions.info("✅ Enabled extension '\(identifier)'")
        notifyUpdate()
        do { try await finishEnabledExtensionUpdate(identifier: identifier) } catch {
            Logger.webExtensions.error("Extension update enabled-package cleanup failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Loading

    @MainActor
    func connectEventsListener() {
        listener.controller = controller
    }

    @MainActor
    public func loadInstalledExtensions() async {
        if let startupUpdateInstaller {
            updateRecoveryBlockedIdentifiers.formUnion(await startupUpdateInstaller.runOnce())
        }
        let lifecycle: InstalledExtensionsLoadLifecycle = isDataClearingReloadPending
            ? .reloadAll(trigger: .dataClearing, identifiers: dataClearingReloadIdentifiers)
            : .initial
        isDataClearingReloadPending = false
        dataClearingReloadIdentifiers.removeAll()
        await loadInstalledExtensions(lifecycle: lifecycle)
    }

    /// Tracks the exact replacement while the old and new installations coexist during upgrade.
    @MainActor
    func trackEmbeddedBackgroundStartup(identifier: String) {
        guard let context = context(for: identifier), context.webExtension.hasBackgroundContent else { return }
        backgroundRecovery?.invalidate()
        backgroundStartupFix[identifier] = installationStore.installedExtensions.contains {
            $0.embeddedType == .embedded && $0.uniqueIdentifier != identifier
        } ? .upgradeReadiness : .installReadiness
        preferredEmbeddedBackgroundContext = context
        Task { @MainActor [weak self] in
            await self?.loadEmbeddedExtensionBackgroundContent(in: context)
        }
    }

    @MainActor
    var embeddedBackgroundContextForNavigation: WKWebExtensionContext? {
        if let preferred = preferredEmbeddedBackgroundContext, context(for: preferred.uniqueIdentifier) === preferred {
            return preferred
        }
        // Installations are appended before the previous version is removed; prefer the newest.
        for installed in installationStore.installedExtensions.reversed() where installed.embeddedType == .embedded {
            if let context = context(for: installed.uniqueIdentifier) { return context }
        }
        // Lightweight clients may load a context without an installation store. Never guess
        // between overlapping versions when their installation order is unavailable.
        let contexts = controller.extensionContexts.filter { $0.webExtension.duckDuckGoWebExtensionType == .embedded }
        return contexts.count == 1 ? contexts.first : nil
    }

    @MainActor
    public var pendingEmbeddedBackgroundStartup: Task<Void, Never>? { embeddedBackgroundStartup }

    @MainActor
    public func prepareEmbeddedBackgroundForNavigation() -> Task<Void, Never>? {
        guard let context = embeddedBackgroundContextForNavigation, context.webExtension.hasBackgroundContent else { return nil }
        navigationWaitContexts.insert(context.uniqueIdentifier)
        return startEmbeddedBackgroundContent(in: context)
    }

    @MainActor
    public func loadEmbeddedExtensionBackgroundContent() async {
        guard let context = embeddedBackgroundContextForNavigation else { return }
        await loadEmbeddedExtensionBackgroundContent(in: context)
    }

    @MainActor
    private func loadEmbeddedExtensionBackgroundContent(in context: WKWebExtensionContext) async {
        await startEmbeddedBackgroundContent(in: context)?.value
    }

    @MainActor
    private func startEmbeddedBackgroundContent(in context: WKWebExtensionContext) -> Task<Void, Never>? {
        guard self.context(for: context.uniqueIdentifier) === context, context.webExtension.hasBackgroundContent else { return nil }

        if let startup = embeddedBackgroundStartup, embeddedBackgroundStartupContext === context {
            return startup
        }

        clearEmbeddedBackgroundStartup()
        let (completion, continuation) = AsyncStream<Void>.makeStream()
        let startup = Task<Void, Never> { for await _ in completion { } }
        embeddedBackgroundStartup = startup
        embeddedBackgroundStartupContext = context
        embeddedBackgroundStartupCompletion = continuation
        let started = Date()
        let startupID = UUID()
        let isFirstLoad = !preparedEmbeddedBackgroundContexts.contains(context)
        preparedEmbeddedBackgroundContexts.add(context)
        backgroundRecovery?.backgroundStarted(startupID, isFirstLoad: isFirstLoad)
        let identifier = context.uniqueIdentifier
        let fix = backgroundStartupFix.removeValue(forKey: identifier) ?? .backgroundWake
        Logger.webExtensions.debug("[CPM Background] Starting background wait for \(identifier, privacy: .public)")
        // Copies WebKit's error on the main thread, as the other background-load paths do.
        context.loadBackgroundContentCopyingErrors { [weak self, weak context] error in
            let elapsed = Date().timeIntervalSince(started)
            if elapsed >= 1 {
                Logger.webExtensions.info("[CPM Background] Background callback for \(identifier, privacy: .public) after \(elapsed, privacy: .public)s")
            }
            if let error {
                Logger.webExtensions.error("❌ Failed to load embedded extension background content: \(error.localizedDescription)")
            }
            if let self, let context, self.embeddedBackgroundContextForNavigation === context {
                self.backgroundRecovery?.backgroundCompleted(startupID, succeeded: error == nil)
                let didWaitForNavigation = self.navigationWaitContexts.remove(identifier) != nil
                if self.backgroundLoadRestartContext === context {
                    self.backgroundLoadRestartContext = nil
                    if error == nil { self.pixelFiring.fire(.cpmBackgroundLoadRestart(.backgroundReady)) }
                }
                if error == nil, (elapsed >= 1 && didWaitForNavigation) || fix == .backgroundLoadRetry {
                    self.pixelFiring.fire(.cpmRecovery(fix, outcome: .backgroundReady))
                }
            }
            if self?.embeddedBackgroundStartup == startup {
                self?.clearEmbeddedBackgroundStartup()
            }
            continuation.finish()
        }
        return startup
    }

    @MainActor
    private func clearEmbeddedBackgroundStartup(identifier: String? = nil) {
        if let identifier, embeddedBackgroundStartupContext?.uniqueIdentifier != identifier { return }
        embeddedBackgroundStartupCompletion?.finish()
        embeddedBackgroundStartup = nil
        embeddedBackgroundStartupContext = nil
        embeddedBackgroundStartupCompletion = nil
    }

    @discardableResult
    @MainActor
    func recoverEmbeddedBackgroundLoadFailure(_ error: Error, context: WKWebExtensionContext) -> Bool {
        guard NSError.webKitSafe(error).isBackgroundContentLoadFailure else { return false }
        let attempt = BackgroundLoadRecoveryAttempt(context: context, failedView: backgroundWebView(in: context))
        return scheduleBackgroundLoadRecovery(attempt)
    }

    @MainActor
    private func canRecoverBackgroundLoad(in context: WKWebExtensionContext) -> Bool {
        context.webExtension.duckDuckGoWebExtensionType == .embedded
            && self.context(for: context.uniqueIdentifier) === context
            && embeddedBackgroundContextForNavigation === context
            && isCPMBackgroundLoadRecoveryEnabled()
            && !isCPMMessagingRecoveryInProgress
    }

    @MainActor
    private func resumePendingBackgroundLoadRecovery() {
        guard !isApplicationInBackground(), !isBackgroundLoadRecoveryScheduled,
              let attempt = pendingBackgroundLoadRecovery else { return }
        // Scheduling consumes invalid attempts, but preserves failures still waiting for cooldown.
        pendingBackgroundLoadRecovery = nil
        _ = scheduleBackgroundLoadRecovery(attempt)
    }

    @MainActor
    private func scheduleBackgroundLoadRecovery(_ attempt: BackgroundLoadRecoveryAttempt) -> Bool {
        guard let context = attempt.context, canRecoverBackgroundLoad(in: context) else { return false }
        guard !isApplicationInBackground(), !isBackgroundLoadRecoveryScheduled else {
            // Preserve the newest failure even in foreground: a queued attempt may skip its old view.
            pendingBackgroundLoadRecovery = attempt
            return false
        }
        let remainingCooldown = lastBackgroundLoadRecoveryAt.map {
            backgroundLoadRecoveryCooldown - now().timeIntervalSince($0)
        } ?? 0
        guard remainingCooldown <= 0 else {
            pendingBackgroundLoadRecovery = attempt
            scheduleBackgroundLoadRecoveryAfterCooldown(remainingCooldown)
            return false
        }
        backgroundLoadRecoveryCooldownTask?.cancel()
        backgroundLoadRecoveryCooldownTask = nil
        pendingBackgroundLoadRecovery = nil
        isBackgroundLoadRecoveryScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isBackgroundLoadRecoveryScheduled = false
            // A foreground notification can precede this task's turn. Preserve and service any
            // newer deferred failure after this attempt has finished or skipped its obsolete view.
            defer { self.resumePendingBackgroundLoadRecovery() }
            guard let context = attempt.context, self.canRecoverBackgroundLoad(in: context) else { return }
            guard !self.isApplicationInBackground() else {
                // A newer error observed in the background takes precedence over this queued attempt.
                if self.pendingBackgroundLoadRecovery == nil { self.pendingBackgroundLoadRecovery = attempt }
                return
            }
            let currentView = self.backgroundWebView(in: context)
            // Keep the original failure's view across suspension. A new view is WebKit's own recovery,
            // even if the replacement is still loading; do not restart it or join its load.
            guard currentView == nil || currentView === attempt.failedView else { return }
            if self.isCPMBackgroundLoadRestartEnabled(), currentView != nil {
                // WebKit cannot replace a retained failed view with a background-only retry.
                await self.restartEmbeddedExtensionAfterRetainedBackgroundLoadFailure(context)
                return
            }
            // Otherwise retry background content without replacing the context, preserving in-flight
            // content-script replies. Confirmed-hang recovery remains the fallback if messaging stays stuck.
            self.lastBackgroundLoadRecoveryAt = self.now()
            self.backgroundStartupFix[context.uniqueIdentifier] = .backgroundLoadRetry
            await self.loadEmbeddedExtensionBackgroundContent(in: context)
        }
        return true
    }

    @MainActor
    private func scheduleBackgroundLoadRecoveryAfterCooldown(_ delay: TimeInterval) {
        guard backgroundLoadRecoveryCooldownTask == nil else { return }
        backgroundLoadRecoveryCooldownTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.backgroundLoadRecoveryCooldownTask = nil
            // If expiry happens in background, keep the attempt for the next recovery-ready event.
            // Otherwise scheduling rechecks its context, view, runtime flags and cooldown.
            self.resumePendingBackgroundLoadRecovery()
        }
    }

    @MainActor
    func backgroundWebView(in context: WKWebExtensionContext) -> WKWebView? {
        guard context.responds(to: Selector.backgroundWebView) else { return nil }
        return context.value(forKey: NSStringFromSelector(Selector.backgroundWebView)) as? WKWebView
    }

    @MainActor
    private func restartEmbeddedExtensionAfterRetainedBackgroundLoadFailure(_ context: WKWebExtensionContext) async {
        guard !isCPMMessagingRecoveryInProgress, self.context(for: context.uniqueIdentifier) === context else { return }
        guard backgroundLoadRestartAttempts < 3 else {
            if backgroundLoadRestartAttempts == 3 {
                backgroundLoadRestartAttempts += 1
                pixelFiring.fire(.cpmBackgroundLoadRestart(.restartLimitReached))
            }
            return
        }
        backgroundLoadRestartAttempts += 1
        lastBackgroundLoadRecoveryAt = now()
        await reloadEmbeddedContext(identifier: context.uniqueIdentifier, trigger: .cpmBackgroundLoadFailure)
    }

    @MainActor
    private func reloadEmbeddedContext(identifier: String, trigger: WebExtensionReloadTrigger) async {
        guard !isCPMMessagingRecoveryInProgress else { return }
        isCPMMessagingRecoveryInProgress = true
        defer { isCPMMessagingRecoveryInProgress = false }
        do {
            try await reloadExtension(identifier: identifier, trigger: trigger)
            if trigger == .cpmBackgroundLoadFailure {
                // Set this before scheduling the background load so even an immediate callback is attributed.
                backgroundLoadRestartContext = context(for: identifier)
            }
            // A missing WebKit completion must not hold the recovery guard forever.
            Task { @MainActor [weak self] in await self?.loadEmbeddedExtensionBackgroundContent() }
        } catch {
            Logger.webExtensions.error("[CPM] Failed to reload the embedded extension during recovery: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func loadInstalledExtensions(lifecycle: InstalledExtensionsLoadLifecycle) async {

        isLoadingInstalledExtensions = true
        defer { isLoadingInstalledExtensions = false }

        listener.controller = controller

        lifecycleDelegate?.webExtensionManagerWillLoadExtensions(self)

        // Disabled extensions stay installed, so orphan cleanup below keeps their files.
        let extensions = installationStore.installedExtensions.filter { !$0.isDisabled && !updateRecoveryBlockedIdentifiers.contains($0.uniqueIdentifier) }
        Logger.webExtensions.debug("🔄 Loading installed extensions (count: \(extensions.count))")

        let identifiers = extensions.map(\.uniqueIdentifier)
        let results = await loader.loadWebExtensions(identifiers: identifiers, into: controller)

        let summary = processInstalledExtensionLoadResults(extensions: extensions, results: results, lifecycle: lifecycle)

        for (installedExtension, result) in zip(extensions, results) {
            guard case .success = result, !isInstalledAndEnabled(installedExtension.uniqueIdentifier) else { continue }
            await unloadExtensionDisabledWhileLoading(installedExtension.uniqueIdentifier)
        }

        await processInstalledExtensionLoadFailures(summary.failures)
        await finishRetainedUpdatesAfterLoad(extensions: extensions, results: results)

        if summary.failures.isEmpty {
            Logger.webExtensions.info("✅ Extension loading completed: \(summary.successCount) loaded")
            if summary.successCount > 0 {
                pixelFiring.fire(.loaded)
            }
        } else {
            Logger.webExtensions.error("❌ Extension loading completed with errors: \(summary.successCount) loaded, \(summary.failures.count) failed")
            if let firstError = summary.firstError {
                pixelFiring.fire(.loadError(error: firstError))
            }
        }

        let knownIdentifiers = Set(installationStore.installedExtensions.map(\.uniqueIdentifier))
        storageProvider.cleanupOrphanedExtensions(keeping: knownIdentifiers)

        for ext in installationStore.installedExtensions {
            if let type = ext.embeddedType {
                await scriptletCoordinator?.onExtensionEnabled(for: type)
            }
        }

        notifyUpdate()
    }

    @MainActor
    private func processInstalledExtensionLoadFailures(_ failures: [(identifier: String, error: Error)]) async {
        for (identifier, error) in failures {
            if retainedUpdateIdentifiers.contains(identifier) {
                await recoverRetainedExtensionAfterLoadFailure(identifier: identifier, originalFailure: error)
                continue
            }
            // Uninstall broken 3rd-party extensions, unless they only failed to load because of a consent/settings read failure.
            if installationStore.installedExtension(withUniqueIdentifier: identifier)?.isEmbedded == false,
               permissionController != nil,
               error is WebExtensionLoader.PermissionPreparationError
            {
                continue
            }
            do {
                try uninstallExtension(identifier: identifier)
            } catch {
                Logger.webExtensions.error("❌ Failed to uninstall broken extension '\(identifier)': \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private func finishRetainedUpdatesAfterLoad(extensions: [InstalledWebExtension], results: [Result<WebExtensionLoadResult, Error>]) async {
        for (installed, result) in zip(extensions, results) {
            guard case .success = result, retainedUpdateIdentifiers.contains(installed.uniqueIdentifier) else { continue }
            try? await finishEnabledExtensionUpdate(identifier: installed.uniqueIdentifier)
        }
    }

    @MainActor
    private func processInstalledExtensionLoadResults(
        extensions: [InstalledWebExtension],
        results: [Result<WebExtensionLoadResult, Error>],
        lifecycle: InstalledExtensionsLoadLifecycle
    ) -> InstalledExtensionsLoadSummary {
        var summary = InstalledExtensionsLoadSummary()
        for (installedExtension, result) in zip(extensions, results) {
            switch result {
            case .success:
                Logger.webExtensions.debug("✅ Loaded extension `\(installedExtension.name ?? "")` v\(installedExtension.version ?? "unknown") | \(installedExtension.filename) | \(installedExtension.uniqueIdentifier)")
                unloadGuard.recordLoad(of: installedExtension.uniqueIdentifier)
                if let event = lifecycle.loadSucceededEvent(
                    identifier: installedExtension.uniqueIdentifier,
                    type: installedExtension.embeddedType
                ) {
                    reportLifecycleEvent(event)
                }
                summary.successCount += 1
            case .failure(let error):
                Logger.webExtensions.error("❌ Failed to load web extension \(installedExtension.filename) (\(installedExtension.uniqueIdentifier)): \(error.localizedDescription)")
                if let event = lifecycle.loadFailedEvent(
                    identifier: installedExtension.uniqueIdentifier,
                    type: installedExtension.embeddedType
                ) {
                    reportLifecycleEvent(event)
                }
                summary.failures.append((identifier: installedExtension.uniqueIdentifier, error: error))
                summary.firstError = summary.firstError ?? error
                if let failureContext = lifecycle.reloadFailureContext(for: installedExtension.uniqueIdentifier) {
                    pixelFiring.fire(.reloadError(type: installedExtension.embeddedType,
                                                  trigger: failureContext.trigger,
                                                  phase: failureContext.phase,
                                                  error: error))
                }
            }
        }
        return summary
    }

    /// Reloads the extensions that the most recent `unloadAllExtensions()` removed, reusing the
    /// parsed `WKWebExtension` objects captured at unload time. This deliberately skips the disk
    /// resolution, manifest parsing, installed-store reads and orphaned-file cleanup performed by
    /// `loadInstalledExtensions()`; the only retained work is the `controller.load` that restarts
    /// each extension's background page (resetting its in-memory state).
    ///
    /// Intended for the data-clearing (fire) flow, where the installed set is unchanged. Falls back
    /// to `loadInstalledExtensions()` when there is nothing cached, or when a cached extension fails
    /// to reload.
    @MainActor
    public func reloadInstalledExtensions() async {
        extensionUpdateGenerations.removeAll()
        await startupUpdateInstaller?.cancelAndWait()
        guard !unloadedExtensionsCache.isEmpty else {
            await loadInstalledExtensions()
            return
        }

        isDataClearingReloadPending = false
        dataClearingReloadIdentifiers.removeAll()

        // Mirror loadInstalledExtensions(): block syncEmbeddedExtensions from interleaving across
        // this method's await points, so a concurrent sync (e.g. a remote config change during a
        // fire) can't mutate the installed set while the reload is in progress.
        isLoadingInstalledExtensions = true
        defer { isLoadingInstalledExtensions = false }

        let cachedExtensions = unloadedExtensionsCache
        unloadedExtensionsCache.removeAll()

        listener.controller = controller

        var successCount = 0
        var failedExtensionIdentifiers: [String] = []
        for (identifier, webExtension) in cachedExtensions {
            let type = installationStore.installedExtension(withUniqueIdentifier: identifier)?.embeddedType

            // Yield between extensions so the main run loop can service system events,
            // mirroring loadWebExtensions' watchdog (0x8badf00d) mitigation.
            await Task.yield()
            guard isInstalledAndEnabled(identifier) else {
                Logger.webExtensions.debug("Skipping reload of extension '\(identifier)' because it was disabled or removed")
                continue
            }
            do {
                try await loader.reloadWebExtension(webExtension, identifier: identifier, into: controller)
                guard isInstalledAndEnabled(identifier) else {
                    await unloadExtensionDisabledWhileLoading(identifier)
                    continue
                }
                unloadGuard.recordLoad(of: identifier)
                reportLifecycleEvent(.reloaded(identifier: identifier, type: type, trigger: .dataClearing))
                successCount += 1
            } catch {
                Logger.webExtensions.error("❌ Failed to reload web extension '\(identifier)': \(error.localizedDescription)")
                pixelFiring.fire(.reloadError(type: type,
                                              trigger: .dataClearing,
                                              phase: .lightweightLoad,
                                              error: error))
                failedExtensionIdentifiers.append(identifier)
            }
        }

        if !failedExtensionIdentifiers.isEmpty {
            // Recover anything that failed the lightweight reload via a full load from disk.
            // Already-loaded contexts are skipped by the idempotent loader.
            Logger.webExtensions.error("⚠️ Lightweight reload incomplete; falling back to loadInstalledExtensions()")
            let failedIdentifiers = Set(failedExtensionIdentifiers)
            await loadInstalledExtensions(lifecycle: .reloadFallback(trigger: .dataClearing, identifiers: failedIdentifiers))
            return
        }

        Logger.webExtensions.info("✅ Reloaded \(successCount) extension(s) from memory")
        notifyUpdate()
    }

    /// Loads installed extensions and then syncs embedded extensions as an atomic sequence.
    /// This prevents race conditions where a concurrent sync could delete extension files
    /// that the loader still needs.
    @MainActor
    public func loadAndSyncExtensions(enabledTypes: Set<DuckDuckGoWebExtensionType>) async {
        await loadInstalledExtensions()
        guard !Task.isCancelled else { return }
        await syncEmbeddedExtensions(enabledTypes: enabledTypes)
    }

    // MARK: - Web view configuration

    public func attachExtensions(to configuration: WKWebViewConfiguration) {
        configuration.webExtensionController = controller
    }

    // MARK: - Lookups

    public func extensionName(for identifier: String) -> String? {
        // An unloaded extension has no context, so fall back to the name saved at installation.
        contexts.first { $0.uniqueIdentifier == identifier }?.webExtension.displayName
            ?? installationStore.installedExtension(withUniqueIdentifier: identifier)?.name
    }

    public func installedExtension(identifier: String) -> InstalledWebExtension? {
        installationStore.installedExtension(withUniqueIdentifier: identifier)
    }

    @MainActor
    public func isRemotelyDisabled(identifier: String) -> Bool {
        guard let remoteDisableEnforcer, let installedExtension = installedExtension(identifier: identifier) else { return false }
        return remoteDisableEnforcer.isRemotelyDisabled(installedExtension)
    }

    public func extensionVersion(for identifier: String) -> String? {
        installationStore.installedExtension(withUniqueIdentifier: identifier)?.version
    }

    public func extensionPermissions(for identifier: String) -> [String] {
        // Records saved before permissions were stored fall back to the loaded extension.
        installationStore.installedExtension(withUniqueIdentifier: identifier)?.permissions
            ?? context(for: identifier)?.webExtension.requiredPermissionNames
            ?? []
    }

    public func extensionMatchPatterns(for identifier: String) -> [String] {
        installationStore.installedExtension(withUniqueIdentifier: identifier)?.matchPatterns
            ?? context(for: identifier)?.webExtension.allRequestedMatchPatterns.map(\.string)
            ?? []
    }

    public func extensionContext(for url: URL) -> WKWebExtensionContext? {
        contexts.first { Self.url(url, isWithin: $0.baseURL) }
    }

    /// Hosts are case-insensitive, and a security origin's host does not always keep the case the
    /// extension's base URL was created with, so the prefix is compared without regard to case.
    static func url(_ url: URL, isWithin baseURL: URL) -> Bool {
        url.absoluteString.range(of: baseURL.absoluteString, options: [.anchored, .caseInsensitive]) != nil
    }

    public func context(for identifier: String) -> WKWebExtensionContext? {
        contexts.first { $0.uniqueIdentifier == identifier }
    }

    /// Hands a script message from an extension page in a tab, where the controller's own message
    /// handlers are not installed, to the API compatibility log.
    public func handleAPICompatibilityMessage(_ message: WKScriptMessage) {
        apiCompatibilityHandler.handle(message)
    }

#if os(macOS)
    /// Answers an idle state request from an extension page in a tab, where the controller's own
    /// message handlers are not installed.
    public func handleIdleMessage(_ message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        idleHandler.reply(to: message, replyHandler: replyHandler)
    }

    /// Answers a `chrome.privacy.services` call from an extension page in a tab, where the
    /// controller's own message handlers are not installed.
    @MainActor
    public func handlePrivacyMessage(_ message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        privacyHandler.reply(to: message, replyHandler: replyHandler)
    }

    /// Answers a `chrome.permissions` call for an app permission from an extension page in a tab, where
    /// the controller's own message handlers are not installed.
    @MainActor
    public func handlePermissionsMessage(_ message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        permissionsHandler.reply(to: message, replyHandler: replyHandler)
    }
#endif

    @MainActor
    func reportLifecycleEvent(_ event: WebExtensionLifecycleEvent) {
        if case .willReload(let identifier, _, _) = event,
           embeddedBackgroundStartupContext?.uniqueIdentifier == identifier {
            clearEmbeddedBackgroundStartup()
        }
        lifecycleEventsContinuation?.yield(event)
        cpmMessagingHealthMonitor.handle(.extensionLifecycle(event))
    }

    @MainActor
    private func reloadEmbeddedExtensionAfterCPMMessagingHang() async {
        guard !isCPMMessagingRecoveryInProgress else { return }
        guard isCPMMessagingHangRecoveryEnabled() else {
            Logger.webExtensions.info("[CPM Health Monitor] Skipping embedded extension reload after a confirmed hang because cpmMessagingHangRecovery is disabled")
            return
        }

        guard let installedExtension = installedEmbeddedExtension(for: .embedded) else {
            Logger.webExtensions.warning("[CPM Health Monitor] Cannot reload the embedded extension after a confirmed hang because it is not installed")
            return
        }

        await reloadEmbeddedContext(identifier: installedExtension.uniqueIdentifier, trigger: .cpmMessagingHang)
    }

    @MainActor
    public func recoverEmbeddedBackgroundAfterNetworkProcessReplacement() {
        cpmNetworkProcessRecovery.recoverIfNeeded()
    }

    /// The extension pixels report: its Chrome Web Store catalog entry, or `other` for one the catalog
    /// doesn't list.
    @MainActor
    func pixelExtension(for storeIdentity: WebExtensionStoreIdentity?) -> WebExtensionPixelExtension {
        guard let storeIdentity, storeIdentity.store == .chromeWebStore,
              let entry = chromeWebStore?.catalogEntry(of: storeIdentity.id) else {
            return .other
        }
        return .catalog(entry)
    }

    /// Native unsupported APIs use the same log and gap accounting as extension-page reports.
    @MainActor
    func reportUnsupportedAPI(_ api: String, for context: WKWebExtensionContext) {
        guard !declaresDuckDuckGoSettings(inManifest: context.webExtension.manifest),
              let issue = WebExtensionAPICompatibilityClassifier.issue(kind: .missing, reportedAPI: api) else { return }
        compatibilityReporter.report(kind: issue.kind, api: issue.api,
                                     extensionName: WebExtensionAPICompatibilityLog.sanitizedField(context.webExtension.displayName),
                                     version: WebExtensionAPICompatibilityLog.sanitizedField(context.webExtension.version))
#if os(macOS)
        recordAPICompatibilityIssue(issue, for: context.uniqueIdentifier)
#endif
    }

#if os(macOS)
    /// When the Bitwarden daily pixel was last sent, to skip checking again within the hour.
    private var lastBitwardenDailyActiveDate: Date?

    /// When this manager was created, at launch or when web extensions are turned back on.
    private var launchDate = Date.distantPast
    /// When the gap counts were last reported, to skip reporting again within the hour.
    private var lastAPICompatibilityGapsDate: Date?
    /// The distinct missing APIs and Chrome pages each installation ran into since launch, by identifier.
    private var apiCompatibilityGaps: [String: (missingAPIs: Set<String>, unsupportedURLs: Set<String>)] = [:]

    /// Counts what the compatibility log takes. A permission WebKit dropped is not an API the extension
    /// used, a stub stands in for its API, and a call WebKit rejected for its arguments is not a missing
    /// API, so none of them counts.
    @MainActor
    func recordAPICompatibilityIssue(_ issue: WebExtensionAPICompatibilityClassifier.Issue, for identifier: String) {
        switch issue.kind {
        case .missing:
            guard !issue.api.hasPrefix(WebExtensionAPICompatibilityClassifier.permissionPrefix) else { return }
            apiCompatibilityGaps[identifier, default: ([], [])].missingAPIs.insert(issue.api)
        case .unsupportedURL:
            apiCompatibilityGaps[identifier, default: ([], [])].unsupportedURLs.insert(issue.api)
        case .stubbed, .invalidArgs:
            return
        }
    }

    /// Reports each loaded catalog extension's gap counts since launch, zeros included, once the app has
    /// been running for an hour, so the counts cover some use. It runs on browsing activity at most once
    /// an hour; each pixel is daily, so each extension reports once a day.
    @MainActor
    private func fireAPICompatibilityGapsIfDue() {
        let date = now()
        guard date.timeIntervalSince(launchDate) >= 60 * 60 else { return }
        if let lastAPICompatibilityGapsDate, date.timeIntervalSince(lastAPICompatibilityGapsDate) < 60 * 60 {
            return
        }
        lastAPICompatibilityGapsDate = date
        for installedExtension in installationStore.installedExtensions {
            guard let context = context(for: installedExtension.uniqueIdentifier),
                  case .catalog(let catalogEntry) = pixelExtension(for: installedExtension.storeIdentity) else { continue }
            let gaps = apiCompatibilityGaps[installedExtension.uniqueIdentifier]
            pixelFiring.fire(.apiCompatibilityGaps(extension: catalogEntry,
                                                   version: WebExtensionPixelExtension.version(context.webExtension.version),
                                                   missingAPICount: gaps?.missingAPIs.count ?? 0,
                                                   unsupportedURLCount: gaps?.unsupportedURLs.count ?? 0))
        }
    }

    /// Reports that Bitwarden is loaded while the browser is in use, and whether it's the default password
    /// manager. It runs on browsing activity, which is frequent; the pixel is daily, so each device counts once a day.
    @MainActor
    private func fireBitwardenDailyActiveIfLoaded() {
        if let lastBitwardenDailyActiveDate, now().timeIntervalSince(lastBitwardenDailyActiveDate) < 60 * 60 {
            return
        }
        let bitwarden = installationStore.installedExtensions.first { installedExtension in
            context(for: installedExtension.uniqueIdentifier) != nil
                && pixelExtension(for: installedExtension.storeIdentity) == .catalog(.bitwarden)
        }
        guard let bitwarden else { return }
        let isDefault = privacySettings?.identifierTurningOff(.passwordSavingEnabled) == bitwarden.uniqueIdentifier
        pixelFiring.fire(.bitwardenDailyActive(isDefault: isDefault))
        lastBitwardenDailyActiveDate = now()
    }
#endif

    func notifyUpdate() {
        continuation?.yield()
        lifecycleDelegate?.webExtensionManagerDidUpdateExtensions(self)
        NotificationCenter.default.post(name: .webExtensionsDidChangeLoadedExtensions, object: self)
#if os(macOS)
        // Only loaded extensions control settings, so loading or unloading one can change who does.
        privacySettings?.notifyControlMayHaveChanged()
#endif
    }
}

public extension Notification.Name {

    /// Posted after successful installation or removal and the corresponding installation-state update.
    /// `userInfo["extensionId"]` contains the Chrome Web Store ID, not the local installation UUID.
    static let chromeWebStoreExtensionChanged = Notification.Name("chromeWebStoreExtensionChanged")

    /// Posted by `WebExtensionManager` when the set of loaded extensions changes.
    ///
    /// Unlike `extensionUpdates`, which an `AsyncStream` limits to a single consumer,
    /// this notification reaches every observer. Per-window UI needs that, because each
    /// browser window keeps its own set of extension toolbar buttons.
    static let webExtensionsDidChangeLoadedExtensions = Notification.Name("webExtensionsDidChangeLoadedExtensions")

    /// Posted by `WebExtensionManager` when an extension changes its toolbar action, such as its icon,
    /// from JavaScript. The object is the extension's `WKWebExtensionContext`.
    static let webExtensionActionDidChange = Notification.Name("webExtensionActionDidChange")
}

// MARK: - WKWebExtensionControllerDelegate

@available(macOS 15.4, iOS 18.4, *)
extension WebExtensionManager: WKWebExtensionControllerDelegate {

    public func webExtensionController(_ controller: WKWebExtensionController,
                                       didUpdate action: WKWebExtension.Action,
                                       forExtensionContext context: WKWebExtensionContext) {
        NotificationCenter.default.post(name: .webExtensionActionDidChange, object: context)
    }

    @objc(_webExtensionController:didCreateBackgroundWebView:forExtensionContext:)
    public func webExtensionController(_ controller: WKWebExtensionController,
                                       didCreateBackgroundWebView webView: WKWebView,
                                       forExtensionContext extensionContext: WKWebExtensionContext) {
        guard extensionContext.webExtension.duckDuckGoWebExtensionType == .embedded else { return }
        MainActor.assumeIsolated {
            // WebKit clears background-load errors just after this callback. Reset this view's history
            // now: delayed clear/add notifications may both see an equal error from the new view.
            observedBackgroundLoadErrors.removeObject(forKey: extensionContext)
            cpmNetworkProcessRecovery.watch(webView, identifier: extensionContext.uniqueIdentifier) { [weak self, weak controller, weak extensionContext, weak webView] in
                guard let extensionContext, let webView,
                      controller?.extensionContexts.contains(extensionContext) == true else { return false }
                return self?.backgroundWebView(in: extensionContext) === webView
            }
            cpmDiagnosticsRecorder?.didCreateBackgroundWebView(webView, for: extensionContext)
        }
    }

    public func webExtensionController(_ controller: WKWebExtensionController,
                                       openWindowsFor extensionContext: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        windowTabProvider.openWindows(for: extensionContext)
    }

    public func webExtensionController(_ controller: WKWebExtensionController,
                                       focusedWindowFor extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        windowTabProvider.focusedWindow(for: extensionContext)
    }

    public func webExtensionController(_ controller: WKWebExtensionController,
                                       openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
                                       for extensionContext: WKWebExtensionContext) async throws -> (any WKWebExtensionWindow)? {
        try await windowTabProvider.openNewWindow(using: configuration, for: extensionContext)
    }

    public func webExtensionController(_ controller: WKWebExtensionController,
                                       openNewTabUsing configuration: WKWebExtension.TabConfiguration,
                                       for extensionContext: WKWebExtensionContext) async throws -> (any WKWebExtensionTab)? {
        // A Chrome page such as `chrome://password-manager/settings` opens the browser's counterpart.
        // Without one, it opens nothing and goes to the compatibility log instead.
        if let url = configuration.url, url.scheme == "chrome" {
            if windowTabProvider.openChromePage(url, for: extensionContext) {
                return nil
            }
            let page = "chrome://" + (url.host ?? "") + url.path
            compatibilityReporter.report(kind: .unsupportedURL,
                                         api: page,
                                         extensionName: WebExtensionAPICompatibilityLog.sanitizedField(extensionContext.webExtension.displayName),
                                         version: WebExtensionAPICompatibilityLog.sanitizedField(extensionContext.webExtension.version))
#if os(macOS)
            recordAPICompatibilityIssue(.init(kind: .unsupportedURL, api: page), for: extensionContext.uniqueIdentifier)
#endif
            return nil
        }
        return try await windowTabProvider.openNewTab(using: configuration, for: extensionContext)
    }

    public func webExtensionController(_ controller: WKWebExtensionController,
                                       openOptionsPageFor extensionContext: WKWebExtensionContext) async throws {
        throw WebExtensionControllerDelegateError.notSupported
    }

    public func webExtensionController(_ controller: WKWebExtensionController,
                                       presentActionPopup action: WKWebExtension.Action,
                                       for extensionContext: WKWebExtensionContext) async throws {
        try await windowTabProvider.presentPopup(action, for: extensionContext)
    }

    // MARK: - Permissions

    public func webExtensionController(_ controller: WKWebExtensionController,
                                       promptForPermissions permissions: Set<WKWebExtension.Permission>,
                                       in tab: (any WKWebExtensionTab)?,
                                       for extensionContext: WKWebExtensionContext) async -> (Set<WKWebExtension.Permission>, Date?) {
        guard let permissionController else { return (permissions, nil) }
        let granted = await permissionController.request(WebExtensionPermissionRequest(permissions: permissions), for: extensionContext)
        return (granted ? permissions : [], nil)
    }

    public func webExtensionController(_ controller: WKWebExtensionController,
                                       promptForPermissionToAccess urls: Set<URL>,
                                       in tab: (any WKWebExtensionTab)?,
                                       for extensionContext: WKWebExtensionContext) async -> (Set<URL>, Date?) {
        guard let permissionController else { return (urls, nil) }
        let granted = await permissionController.request(WebExtensionPermissionRequest(urls: urls), for: extensionContext)
        return (granted ? urls : [], nil)
    }

    public func webExtensionController(_ controller: WKWebExtensionController,
                                       promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
                                       in tab: (any WKWebExtensionTab)?,
                                       for extensionContext: WKWebExtensionContext) async -> (Set<WKWebExtension.MatchPattern>, Date?) {
        guard let permissionController else { return (matchPatterns, nil) }
        let granted = await permissionController.request(WebExtensionPermissionRequest(matchPatterns: matchPatterns), for: extensionContext)
        return (granted ? matchPatterns : [], nil)
    }
}

// MARK: - Verified Store Updates

@available(macOS 15.4, iOS 18.4, *)
@MainActor
extension WebExtensionManager {
    enum UpdateInstallationResult { case applied, installedDisabled }
    enum UpdateInstallationError: Error { case installationChanged, alreadyUpdating, invalidPackage, rollbackFailed, recoveryFailed }

    /// Kept internal until lifecycle eligibility is connected. Missing or increased approval installs disabled.
    func applyVerifiedUpdate(_ update: ChromeWebStoreVerifiedUpdate,
                             replacing installed: InstalledWebExtension,
                             reportedInstalledVersion: String? = nil,
                             versionOverrideIdentifier: UUID? = nil,
                             isEligible: () -> Bool) async throws -> UpdateInstallationResult {
        let identifier = installed.uniqueIdentifier
        guard !installed.isEmbedded, installed.storeIdentity == .init(store: .chromeWebStore, id: update.extensionID),
              Self.isVersionEligibleForUpdate(update.version, installedVersion: installed.version,
                                              reportedInstalledVersion: reportedInstalledVersion) else {
            throw UpdateInstallationError.invalidPackage
        }
        guard extensionUpdateGenerations[identifier] == nil else { throw UpdateInstallationError.alreadyUpdating }
        let generation = UUID()
        extensionUpdateGenerations[identifier] = generation
        permissionController?.beginUpdate(for: identifier)
        defer {
            permissionController?.endUpdate(for: identifier)
            if extensionUpdateGenerations[identifier] == generation { extensionUpdateGenerations.removeValue(forKey: identifier) }
        }
        func checkEligibility() throws {
            try Task.checkCancellation()
            guard extensionUpdateGenerations[identifier] == generation,
                  installationStore.installedExtension(withUniqueIdentifier: identifier) == installed,
                  isEligible() else { throw UpdateInstallationError.installationChanged }
        }

        try checkEligibility()
        try? permissionController?.snapshotForUpdate(for: identifier)
        let staged = try await stageVerifiedExtensionUpdate(update, installed: installed, versionOverrideIdentifier: versionOverrideIdentifier)
        let previousContext = context(for: identifier)
        var didUnload = false
        var didReplace = false
        var attemptedCandidateLoad = false
        var candidateContext: WKWebExtensionContext?
        var failureOutcome: WebExtensionUpdateInstallFailure = .invalidPackage
        do {
            try checkEligibility()
            let candidate = try await WKWebExtension.makeCopyingErrors(at: staged.bundleURL)
            guard candidate.version == update.version else { throw UpdateInstallationError.invalidPackage }
            try checkEligibility()
            var disabled = updateRequiresDisabling(candidate, installed: installed)

            await unloadGuard.awaitSettled(previousContext)
            try checkEligibility()
            disabled = disabled || updateRequiresDisabling(candidate, installed: installed)
            if previousContext != nil {
                failureOutcome = .unloadFailure
                try loader.unloadExtension(identifier: identifier, from: controller)
                didUnload = true
                cpmNetworkProcessRecovery.stopWatching(identifier: identifier)
                cpmDiagnosticsRecorder?.contextDidUnload(identifier: identifier)
                unregisterHandlers(for: identifier)
            }
            // The actor journals before moving the incumbent; even a failed second rename must be rolled back.
            didReplace = true
            failureOutcome = .storageFailure
            try await extensionUpdateTransactions.replace(staged)
            try checkEligibility()
            disabled = disabled || updateRequiresDisabling(candidate, installed: installed)
            if !disabled {
                attemptedCandidateLoad = true
                failureOutcome = .loadFailure
                disabled = !(try await loadApprovedExtensionUpdate(identifier: identifier, beforeActivation: { parsed in
                    try checkEligibility()
                    try self.requireSavedUpdateConsent(parsed, identifier: identifier)
                }))
                candidateContext = context(for: identifier)
                try checkEligibility()
            }
            disabled = disabled || updateRequiresDisabling(candidate, installed: installed)
            if disabled, candidateContext != nil {
                failureOutcome = .unloadFailure
                try loader.unloadExtension(identifier: identifier, from: controller)
                unregisterHandlers(for: identifier)
                candidateContext = nil
            }
            let replacement = InstalledWebExtension(uniqueIdentifier: identifier, filename: staged.installedFilename, name: candidate.displayName,
                                                    version: candidate.version, storeIdentity: installed.storeIdentity,
                                                    permissions: candidate.requiredPermissionNames,
                                                    matchPatterns: candidate.allRequestedMatchPatterns.map(\.string), isDisabled: disabled)
            failureOutcome = .storageFailure
            try await extensionUpdateTransactions.commit(staged, updatedMetadata: JSONEncoder().encode(replacement), retainPrevious: disabled)
            try checkEligibility()
            installationStore.update(replacement)
            await didCommitExtensionUpdate(replacement, replacing: installed, transactionID: staged.transactionID,
                                            versionOverrideIdentifier: versionOverrideIdentifier)
            return disabled ? .installedDisabled : .applied
        } catch {
            let installationError = error
            let failedContext = candidateContext ?? failedUpdateContext(identifier: identifier, generation: generation, attemptedLoad: attemptedCandidateLoad)
            do {
                try await restorePreviousExtensionUpdate(installed, staged: staged, generation: generation,
                                                         candidateContext: failedContext, shouldReload: didUnload && didReplace)
            } catch {
                reportUpdateInstallationFailureIfNeeded(error, outcome: .rollbackFailure, storeIdentity: installed.storeIdentity)
                throw error
            }
            reportUpdateInstallationFailureIfNeeded(installationError, outcome: failureOutcome, storeIdentity: installed.storeIdentity)
            throw installationError
        }
    }

    /// Debug overrides may permit a verified same-version reinstall, but can never lower the actual installed version.
    static func isVersionEligibleForUpdate(_ offeredVersion: String, installedVersion: String?, reportedInstalledVersion: String? = nil) -> Bool {
        guard let installedVersion else { return false }
        let comparator = SemanticVersionComparator()
        return comparator.isVersion(offeredVersion, newerThan: reportedInstalledVersion ?? installedVersion)
            && !comparator.isVersion(installedVersion, newerThan: offeredVersion)
    }

    private func stageVerifiedExtensionUpdate(_ update: ChromeWebStoreVerifiedUpdate, installed: InstalledWebExtension,
                                              versionOverrideIdentifier: UUID?) async throws -> WebExtensionUpdateTransactionStore.Staged {
        do {
            return try await extensionUpdateTransactions.stage(update, installationID: installed.uniqueIdentifier, previousVersion: installed.version,
                                                                previousMetadata: JSONEncoder().encode(installed), versionOverrideIdentifier: versionOverrideIdentifier)
        } catch {
            reportUpdateInstallationFailureIfNeeded(error, outcome: .storageFailure, storeIdentity: installed.storeIdentity)
            throw error
        }
    }

    static func isUpdateInstallationDeferral(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if case WebExtensionUpdateTransactionStore.TransactionError.transactionAlreadyExists = error { return true }
        guard let failure = error as? UpdateInstallationError else { return false }
        switch failure {
        case .installationChanged, .alreadyUpdating, .recoveryFailed: return true
        case .invalidPackage, .rollbackFailed: return false
        }
    }

    private static func shouldReportUpdateInstallationFailure(_ error: Error, outcome: WebExtensionUpdateInstallFailure) -> Bool {
        guard !isUpdateInstallationDeferral(error) else { return false }
        // Repair runs even during cancellation. A real rollback failure must remain visible regardless of its error type.
        return outcome == .rollbackFailure || !Task.isCancelled
    }

    func reportUpdateInstallationFailure(_ failure: WebExtensionUpdateInstallFailure, storeIdentity: WebExtensionStoreIdentity?) {
        pixelFiring.fire(.updateInstallFailed(extension: pixelExtension(for: storeIdentity), outcome: failure))
    }

    private func reportUpdateInstallationFailureIfNeeded(_ error: Error, outcome: WebExtensionUpdateInstallFailure,
                                                         storeIdentity: WebExtensionStoreIdentity?) {
        guard Self.shouldReportUpdateInstallationFailure(error, outcome: outcome) else { return }
        reportUpdateInstallationFailure(outcome, storeIdentity: storeIdentity)
    }

    private func reportUpdateRollback(storeIdentity: WebExtensionStoreIdentity?) {
        pixelFiring.fire(.updateRolledBack(extension: pixelExtension(for: storeIdentity)))
        Logger.webExtensions.info("Extension update installation: \(storeIdentity?.id ?? "unknown", privacy: .public) rolled back")
    }

    private func updateRequiresDisabling(_ candidate: WKWebExtension, installed: InstalledWebExtension) -> Bool {
        guard !installed.isDisabled, let permissionController else { return true }
        do { try permissionController.snapshotForUpdate(for: installed.uniqueIdentifier) } catch { return true }
        return !permissionController.canActivateUpdate(candidate, for: installed.uniqueIdentifier)
    }

    private func loadApprovedExtensionUpdate(identifier: String, beforeActivation: @MainActor (WKWebExtension) throws -> Void) async throws -> Bool {
        do {
            _ = try await loader.loadWebExtension(identifier: identifier, into: controller, beforeActivation: beforeActivation)
            unloadGuard.recordLoad(of: identifier)
            return true
        } catch let preparation as WebExtensionLoader.PermissionPreparationError {
            guard let failure = preparation.underlyingError as? WebExtensionPermissionController.PermissionError,
                  case .updateConsentRequired = failure else { throw preparation }
            // Approval disappeared while the loader parsed the bundle; prepare rejected it before executing code.
            unregisterHandlers(for: identifier)
            return false
        }
    }

    private func requireSavedUpdateConsent(_ parsed: WKWebExtension, identifier: String, requiresApprovedAccess: Bool = true) throws {
        let approved = requiresApprovedAccess
            ? permissionController?.canActivateUpdate(parsed, for: identifier)
            : permissionController?.hasSavedPermissions(for: identifier)
        guard approved == true else {
            throw WebExtensionLoader.PermissionPreparationError(underlyingError: WebExtensionPermissionController.PermissionError.updateConsentRequired)
        }
    }

    private func requireCurrentStoreActivation(_ installed: InstalledWebExtension, generation: UUID?, allowsDisabled: Bool) throws {
        let identifier = installed.uniqueIdentifier
        guard installationStore.installedExtension(withUniqueIdentifier: identifier) == installed,
              generation.map({ extensionUpdateGenerations[identifier] == $0 }) ?? true,
              allowsDisabled || !installed.isDisabled, !isRemotelyDisabled(identifier: identifier),
              !updateRecoveryBlockedIdentifiers.contains(identifier) else { throw UpdateInstallationError.installationChanged }
    }

    private func loadStoreExtensionForEnable(_ installed: InstalledWebExtension, generation: UUID?) async throws -> WebExtensionLoadResult {
        let identifier = installed.uniqueIdentifier
        guard generation != nil else { return try await loader.loadWebExtension(identifier: identifier, into: controller) }
        permissionController?.beginUpdate(for: identifier, requiresApprovedAccess: false)
        defer { permissionController?.endUpdate(for: identifier) }
        return try await loader.loadWebExtension(identifier: identifier, into: controller, beforeActivation: { parsed in
            try self.requireCurrentStoreActivation(installed, generation: generation, allowsDisabled: true)
            try self.requireSavedUpdateConsent(parsed, identifier: identifier, requiresApprovedAccess: false)
        })
    }

    private func failedUpdateContext(identifier: String, generation: UUID, attemptedLoad: Bool) -> WKWebExtensionContext? {
        guard attemptedLoad, extensionUpdateGenerations[identifier] == generation else { return nil }
        let failed = context(for: identifier)
        if failed == nil { unregisterHandlers(for: identifier) }
        return failed
    }

    private func didCommitExtensionUpdate(_ replacement: InstalledWebExtension, replacing installed: InstalledWebExtension, transactionID: UUID,
                                          versionOverrideIdentifier: UUID?) async {
        let identifier = replacement.uniqueIdentifier
        guard installationStore.installedExtension(withUniqueIdentifier: identifier) == replacement else { return }
        let registryAcknowledged = await acknowledgeUpdateRegistry(transactionID, required: installed.version == replacement.version)
        let overrideCleared = didCommitStoreUpdate(replacement, versionOverrideIdentifier)
        pixelFiring.fire(.updateApplied(extension: pixelExtension(for: replacement.storeIdentity)))
        if replacement.isDisabled {
            retainedUpdateIdentifiers.insert(identifier)
            if !installed.isDisabled { reportEnabledStateChange(isEnabled: false, storeIdentity: installed.storeIdentity) }
        } else {
            reportLifecycleEvent(.loaded(identifier: identifier, type: nil))
        }
        notifyUpdate()
        if let identity = replacement.storeIdentity {
            NotificationCenter.default.post(name: .chromeWebStoreExtensionChanged, object: self, userInfo: ["extensionId": identity.id])
        }
        if !replacement.isDisabled, registryAcknowledged, overrideCleared {
            // The new version and registry are committed. Cleanup failure must not roll that success back.
            await extensionUpdateTransactions.cleanup(transactionID)
        }
    }

    private func restorePreviousExtensionUpdate(_ installed: InstalledWebExtension, staged: WebExtensionUpdateTransactionStore.Staged,
                                                generation: UUID, candidateContext: WKWebExtensionContext?, shouldReload: Bool) async throws {
        let identifier = installed.uniqueIdentifier
        do {
            if let candidateContext, context(for: identifier) === candidateContext {
                // If unloading fails, its files must stay in place until launch recovery can run without live code.
                try loader.unloadExtension(identifier: identifier, from: controller)
                unregisterHandlers(for: identifier)
            } else if shouldReload, extensionUpdateGenerations[identifier] == generation {
                // A loader failure may have registered handlers without leaving a loaded context.
                unregisterHandlers(for: identifier)
            }
            let current = installationStore.installedExtension(withUniqueIdentifier: identifier)
            let stillInstalled = current?.storeIdentity == installed.storeIdentity && current?.version == installed.version
            let metadata = try await extensionUpdateTransactions.rollback(staged.transactionID, restoreInstallation: stillInstalled)
            try await reconcileRolledBackExtensionUpdate(metadata, installed: installed, transactionID: staged.transactionID,
                                                         requiresAcknowledgement: installed.version == staged.version)
            if shouldReload, extensionUpdateGenerations[identifier] == generation,
               installationStore.installedExtension(withUniqueIdentifier: identifier) == installed, !installed.isDisabled {
                _ = try await loader.loadWebExtension(identifier: identifier, into: controller, beforeActivation: { parsed in
                    // Restoring the incumbent is allowed after cancellation or update-flag disable, but not after user/remote removal.
                    try self.requireCurrentStoreActivation(installed, generation: generation, allowsDisabled: false)
                    try self.requireSavedUpdateConsent(parsed, identifier: identifier)
                })
                if installationStore.installedExtension(withUniqueIdentifier: identifier) == installed,
                   extensionUpdateGenerations[identifier] == generation {
                    unloadGuard.recordLoad(of: identifier)
                } else {
                    try? loader.unloadExtension(identifier: identifier, from: controller)
                    unregisterHandlers(for: identifier)
                }
            }
            if metadata != nil, let restored = installationStore.installedExtension(withUniqueIdentifier: identifier),
               restored.storeIdentity == installed.storeIdentity, restored.version == installed.version {
                reportUpdateRollback(storeIdentity: installed.storeIdentity)
            }
        } catch {
            if Self.isUpdateInstallationDeferral(error) { throw error }
            // Retain the journal and backup if recovery itself fails; launch recovery can retry.
            Logger.webExtensions.error("Extension update rollback failed for \(identifier): \(error.localizedDescription)")
            throw UpdateInstallationError.rollbackFailed
        }
    }

    private func reconcileRolledBackExtensionUpdate(_ metadata: Data?, installed: InstalledWebExtension, transactionID: UUID,
                                                    requiresAcknowledgement: Bool) async throws {
        guard let metadata else { return }
        if let current = installationStore.installedExtension(withUniqueIdentifier: installed.uniqueIdentifier),
           current.storeIdentity == installed.storeIdentity, current.version == installed.version {
            var previous = try JSONDecoder().decode(InstalledWebExtension.self, from: metadata)
            guard previous.uniqueIdentifier == current.uniqueIdentifier, previous.storeIdentity == current.storeIdentity else {
                throw WebExtensionUpdateTransactionStore.TransactionError.invalidJournal
            }
            previous.isDisabled = previous.isDisabled || current.isDisabled
            installationStore.update(previous)
        }
        // If uninstalled during the rollback await, discard the journal without recreating its registry entry.
        if await acknowledgeUpdateRegistry(transactionID, required: requiresAcknowledgement) {
            await extensionUpdateTransactions.cleanup(transactionID)
        }
    }

    private func acknowledgeUpdateRegistry(_ transactionID: UUID, required: Bool) async -> Bool {
        guard required else { return true }
        return await extensionUpdateTransactions.acknowledgeRegistry(transactionID)
    }

    /// Must run before loading installed extensions once the production update flow is connected.
    @discardableResult
    func recoverExtensionUpdates(isAllowed: (String) -> Bool) async throws -> Set<String> {
        var failures: Set<String> = []
        let journals: [WebExtensionUpdateTransactionStore.Journal]
        do { journals = try await extensionUpdateTransactions.journals() } catch {
            reportUpdateInstallationFailureIfNeeded(error, outcome: .storageFailure, storeIdentity: nil)
            throw error
        }
        for journal in journals {
            let candidateAllowed = isAllowed(journal.extensionID)
            if journal.phase == .committed, journal.retainsPrevious { retainedUpdateIdentifiers.insert(journal.installationID) }
            do { try await recoverExtensionUpdate(journal, candidateAllowed: candidateAllowed, isAllowed: isAllowed) } catch {
                failures.insert(journal.installationID)
                let outcome: WebExtensionUpdateInstallFailure = journal.phase == .committed && candidateAllowed ? .storageFailure : .rollbackFailure
                reportUpdateInstallationFailureIfNeeded(error, outcome: outcome, storeIdentity: .init(store: .chromeWebStore, id: journal.extensionID))
                Logger.webExtensions.error("Extension update recovery failed for \(journal.installationID): \(error.localizedDescription)")
            }
        }
        updateRecoveryBlockedIdentifiers.formUnion(failures)
        return failures
    }

    func blockLoadingAfterUpdateRecoveryFailure(_ identifiers: Set<String>) {
        updateRecoveryBlockedIdentifiers.formUnion(identifiers)
    }

    private func recoverExtensionUpdate(_ journal: WebExtensionUpdateTransactionStore.Journal, candidateAllowed: Bool,
                                        isAllowed: (String) -> Bool) async throws {
        let current = installationStore.installedExtension(withUniqueIdentifier: journal.installationID)
        let identity = WebExtensionStoreIdentity(store: .chromeWebStore, id: journal.extensionID)
        let matches = current?.storeIdentity == identity && (current?.version == journal.previousVersion || current?.version == journal.version)
        let allowed = candidateAllowed
        let metadata = try await extensionUpdateTransactions.recover(journal, installationStillMatches: matches, rejectCandidate: !allowed)
        guard let metadata, let before = current,
              installationStore.installedExtension(withUniqueIdentifier: journal.installationID) == before else { return }
        var recovered = try JSONDecoder().decode(InstalledWebExtension.self, from: metadata)
        guard recovered.uniqueIdentifier == before.uniqueIdentifier, recovered.storeIdentity == before.storeIdentity else {
            throw WebExtensionUpdateTransactionStore.TransactionError.invalidJournal
        }
        let alreadyReconciled = journal.registryCommitted
            ?? ((journal.phase == .committed && before.version == journal.version)
                    || (journal.phase == .rollingBack && before.version == journal.previousVersion))
        if allowed, alreadyReconciled {
            // Registry changes after a successful explicit enable/disable are newer than the journal's commit metadata.
            recovered = before
        } else {
            recovered.isDisabled = recovered.isDisabled || before.isDisabled
        }
        recovered.isDisabled = recovered.isDisabled || !isAllowed(journal.extensionID)
        installationStore.update(recovered)
        let registryAcknowledged = await acknowledgeUpdateRegistry(journal.transactionID, required: journal.registryCommitted != nil)
        let overrideCleared = journal.phase != .committed || !allowed || didCommitStoreUpdate(recovered, journal.versionOverrideIdentifier)
        if journal.phase == .replacing || (journal.phase == .rollingBack && !alreadyReconciled) || (!allowed && journal.phase == .committed) {
            reportUpdateRollback(storeIdentity: recovered.storeIdentity)
        } else if journal.phase == .committed, !alreadyReconciled {
            pixelFiring.fire(.updateApplied(extension: pixelExtension(for: recovered.storeIdentity)))
            Logger.webExtensions.info("Extension update installation: \(journal.extensionID, privacy: .public) recovered committed package")
        }
        let enabledRegistryCommitted = allowed && recovered.version == journal.version && !recovered.isDisabled
        if registryAcknowledged, overrideCleared,
           journal.phase != .committed || !allowed || !journal.retainsPrevious || enabledRegistryCommitted {
            await extensionUpdateTransactions.cleanup(journal.transactionID)
            retainedUpdateIdentifiers.remove(journal.installationID)
        }
    }

    func prepareRetainedExtensionUpdateForReplacement(_ installed: InstalledWebExtension, offeredVersion: String,
                                                      reportedInstalledVersion: String? = nil) async throws -> InstalledWebExtension {
        guard Self.isVersionEligibleForUpdate(offeredVersion, installedVersion: installed.version, reportedInstalledVersion: reportedInstalledVersion) else {
            throw UpdateInstallationError.invalidPackage
        }
        guard installed.isDisabled else { return installed }
        do {
            return try await restoreRetainedExtensionUpdate(installed, disabled: true) ?? installed
        } catch {
            reportUpdateInstallationFailureIfNeeded(error, outcome: .rollbackFailure, storeIdentity: installed.storeIdentity)
            throw error
        }
    }

    private func restoreRetainedExtensionUpdate(_ installed: InstalledWebExtension, disabled: Bool,
                                                generation: UUID? = nil) async throws -> InstalledWebExtension? {
        let identifier = installed.uniqueIdentifier
        guard retainedUpdateIdentifiers.contains(identifier) else { return nil }
        let journals = try await extensionUpdateTransactions.journals()
        try Task.checkCancellation()
        guard let journal = journals.first(where: { $0.installationID == identifier && $0.phase == .committed && $0.retainsPrevious }) else { return nil }
        guard installationStore.installedExtension(withUniqueIdentifier: identifier) == installed,
              generation.map({ extensionUpdateGenerations[identifier] == $0 }) ?? true,
              installed.storeIdentity == .init(store: .chromeWebStore, id: journal.extensionID), installed.version == journal.version else {
            throw UpdateInstallationError.installationChanged
        }
        if let active = context(for: identifier) {
            unloadGuard.recordLoad(of: identifier)
            await unloadGuard.awaitSettled(active)
            try Task.checkCancellation()
            guard installationStore.installedExtension(withUniqueIdentifier: identifier) == installed, context(for: identifier) === active,
                  generation.map({ extensionUpdateGenerations[identifier] == $0 }) ?? true else {
                throw UpdateInstallationError.installationChanged
            }
            try loader.unloadExtension(identifier: identifier, from: controller)
            unregisterHandlers(for: identifier)
        }
        guard let metadata = try await extensionUpdateTransactions.rollback(journal.transactionID, restoreInstallation: true) else {
            throw UpdateInstallationError.rollbackFailed
        }
        guard let current = installationStore.installedExtension(withUniqueIdentifier: identifier),
              current.storeIdentity == installed.storeIdentity, current.version == installed.version else {
            if installationStore.installedExtension(withUniqueIdentifier: identifier) == nil { await extensionUpdateTransactions.cleanup(journal.transactionID) }
            throw UpdateInstallationError.installationChanged
        }
        var predecessor = try JSONDecoder().decode(InstalledWebExtension.self, from: metadata)
        guard predecessor.uniqueIdentifier == identifier, predecessor.storeIdentity == installed.storeIdentity else { throw UpdateInstallationError.invalidPackage }
        predecessor.isDisabled = disabled || current.isDisabled || isRemotelyDisabled(identifier: identifier)
        installationStore.update(predecessor)
        if await acknowledgeUpdateRegistry(journal.transactionID, required: journal.registryCommitted != nil) {
            await extensionUpdateTransactions.cleanup(journal.transactionID)
        }
        retainedUpdateIdentifiers.remove(identifier)
        return predecessor
    }

    private func beginStoreExtensionEnable(identifier: String) -> UUID? {
        extensionUpdateGenerations.removeValue(forKey: identifier)
        guard installationStore.installedExtension(withUniqueIdentifier: identifier)?.storeIdentity?.store == .chromeWebStore,
              startupUpdateInstaller != nil || retainedUpdateIdentifiers.contains(identifier) else { return nil }
        let generation = UUID()
        extensionUpdateGenerations[identifier] = generation
        return generation
    }

    /// Persist the existing registry state before allowing a user mutation that ambiguous same-version recovery could undo.
    private func acknowledgeUpdateRegistryBeforeEnable(_ installed: InstalledWebExtension, generation: UUID?) async throws {
        guard generation != nil else { return }
        let identifier = installed.uniqueIdentifier
        let journals = try await extensionUpdateTransactions.journals()
        try await validateStoreExtensionEnable(identifier: identifier, generation: generation, installed: installed)
        for journal in journals where journal.installationID == identifier && journal.registryCommitted == false {
            guard installed.storeIdentity == .init(store: .chromeWebStore, id: journal.extensionID),
                  (journal.phase == .committed && installed.version == journal.version)
                    || (journal.phase == .rollingBack && installed.version == journal.previousVersion) else {
                throw UpdateInstallationError.recoveryFailed
            }
            let acknowledged = await extensionUpdateTransactions.acknowledgeRegistry(journal.transactionID)
            try await validateStoreExtensionEnable(identifier: identifier, generation: generation, installed: installed)
            guard acknowledged else { throw UpdateInstallationError.recoveryFailed }
        }
    }

    private func endStoreExtensionEnable(identifier: String, generation: UUID?) {
        if let generation, extensionUpdateGenerations[identifier] == generation { extensionUpdateGenerations.removeValue(forKey: identifier) }
    }

    private func enableRetainedPredecessor(_ installed: InstalledWebExtension, generation: UUID?, originalFailure: Error) async throws -> InstalledWebExtension? {
        let identifier = installed.uniqueIdentifier
        guard retainedUpdateIdentifiers.contains(identifier) else { return nil }
        do {
            guard let predecessor = try await restoreRetainedExtensionUpdate(installed, disabled: true, generation: generation) else { return nil }
            try await validateStoreExtensionEnable(identifier: identifier, generation: generation, installed: predecessor)
            try await acknowledgeUpdateRegistryBeforeEnable(predecessor, generation: generation)
            permissionController?.beginUpdate(for: identifier)
            defer { permissionController?.endUpdate(for: identifier) }
            _ = try await loader.loadWebExtension(identifier: identifier, into: controller, beforeActivation: { parsed in
                try self.requireCurrentStoreActivation(predecessor, generation: generation, allowsDisabled: true)
                try self.requireSavedUpdateConsent(parsed, identifier: identifier)
            })
            try await validateStoreExtensionEnable(identifier: identifier, generation: generation, installed: predecessor, ownedContext: context(for: identifier))
            unloadGuard.recordLoad(of: identifier)
            reportUpdateInstallationFailureIfNeeded(originalFailure, outcome: .loadFailure, storeIdentity: installed.storeIdentity)
            reportUpdateRollback(storeIdentity: predecessor.storeIdentity)
            return predecessor
        } catch {
            reportUpdateInstallationFailureIfNeeded(error, outcome: .rollbackFailure, storeIdentity: installed.storeIdentity)
            throw error
        }
    }

    private func validateStoreExtensionEnable(identifier: String, generation: UUID?, installed: InstalledWebExtension?,
                                              ownedContext: WKWebExtensionContext? = nil) async throws {
        guard let generation else { return }
        let current = installationStore.installedExtension(withUniqueIdentifier: identifier)
        guard extensionUpdateGenerations[identifier] != generation || (installed != nil && current != installed) else { return }
        if let ownedContext, context(for: identifier) === ownedContext {
            await unloadGuard.awaitSettled(ownedContext)
            if context(for: identifier) === ownedContext {
                try loader.unloadExtension(identifier: identifier, from: controller)
                unregisterHandlers(for: identifier)
            }
        }
        throw UpdateInstallationError.installationChanged
    }

    private func recoverRetainedExtensionAfterLoadFailure(identifier: String, originalFailure: Error) async {
        guard let installed = installationStore.installedExtension(withUniqueIdentifier: identifier) else { return }
        guard let generation = beginStoreExtensionEnable(identifier: identifier) else { return }
        defer { endStoreExtensionEnable(identifier: identifier, generation: generation) }
        var predecessorWasRestored = false
        do {
            try await validateStoreExtensionEnable(identifier: identifier, generation: generation, installed: installed)
            guard let predecessor = try await restoreRetainedExtensionUpdate(installed, disabled: installed.isDisabled, generation: generation) else { return }
            predecessorWasRestored = true
            try await validateStoreExtensionEnable(identifier: identifier, generation: generation, installed: predecessor)
            guard !predecessor.isDisabled else { return }
            permissionController?.beginUpdate(for: identifier)
            defer { permissionController?.endUpdate(for: identifier) }
            do {
                _ = try await loader.loadWebExtension(identifier: identifier, into: controller, beforeActivation: { parsed in
                    try self.requireCurrentStoreActivation(predecessor, generation: generation, allowsDisabled: false)
                    try self.requireSavedUpdateConsent(parsed, identifier: identifier)
                })
            } catch {
                try await validateStoreExtensionEnable(identifier: identifier, generation: generation, installed: predecessor,
                                                       ownedContext: context(for: identifier))
                throw error
            }
            let loadedContext = context(for: identifier)
            try await validateStoreExtensionEnable(identifier: identifier, generation: generation, installed: predecessor, ownedContext: loadedContext)
            unloadGuard.recordLoad(of: identifier)
            reportUpdateInstallationFailureIfNeeded(originalFailure, outcome: .loadFailure, storeIdentity: installed.storeIdentity)
            reportUpdateRollback(storeIdentity: predecessor.storeIdentity)
            notifyUpdate()
        } catch {
            if case UpdateInstallationError.installationChanged = error,
               predecessorWasRestored || installationStore.installedExtension(withUniqueIdentifier: identifier) == nil { return }
            updateRecoveryBlockedIdentifiers.insert(identifier)
            reportUpdateInstallationFailureIfNeeded(error, outcome: .rollbackFailure, storeIdentity: installed.storeIdentity)
            Logger.webExtensions.error("Extension update retained predecessor recovery failed for \(identifier): \(error.localizedDescription)")
        }
    }

    /// A disabled update keeps its predecessor until an explicit enable has loaded the candidate successfully.
    func finishEnabledExtensionUpdate(identifier: String) async throws {
        guard retainedUpdateIdentifiers.contains(identifier) else { return }
        guard let installed = installationStore.installedExtension(withUniqueIdentifier: identifier), !installed.isDisabled else { return }
        for journal in try await extensionUpdateTransactions.journals()
        where journal.installationID == identifier && journal.phase == .committed && journal.retainsPrevious {
            guard installationStore.installedExtension(withUniqueIdentifier: identifier) == installed,
                  installed.storeIdentity == .init(store: .chromeWebStore, id: journal.extensionID), installed.version == journal.version,
                  context(for: identifier)?.webExtension.version == journal.version else { continue }
            guard await acknowledgeUpdateRegistry(journal.transactionID, required: journal.registryCommitted != nil),
                  didCommitStoreUpdate(installed, journal.versionOverrideIdentifier) else { continue }
            await extensionUpdateTransactions.cleanup(journal.transactionID)
            retainedUpdateIdentifiers.remove(identifier)
        }
    }
}

// MARK: - WebExtensionInternalSiteHandlerDataSource

@available(macOS 15.4, iOS 18.4, *)
extension WebExtensionManager: WebExtensionInternalSiteHandlerDataSource {

    public func webExtensionContext(for url: URL) -> WKWebExtensionContext? {
        extensionContext(for: url)
    }
}

// MARK: - Errors

@available(macOS 15.4, iOS 18.4, *)
public enum WebExtensionControllerDelegateError: Error {
    case notSupported
}

// MARK: - Extension Management Pixels

@available(macOS 15.4, iOS 18.4, *)
@MainActor
private extension WebExtensionManager {

    /// An update isn't an install, matching Windows, and keeps the original installation's retention wait.
    func reportInstalled(storeIdentity: WebExtensionStoreIdentity?, replacing oldIdentifier: String?) {
        guard oldIdentifier == nil else { return }
        pixelFiring.fire(.installed(extension: pixelExtension(for: storeIdentity)))
        if let storeIdentity {
            storePixelsReporter?.recordInstall(storeIdentity.id)
        }
    }

    func reportUninstalled(_ installedExtension: InstalledWebExtension?) {
        pixelFiring.fire(.uninstalled(extension: pixelExtension(for: installedExtension?.storeIdentity)))
    }

    func reportEnabledStateChange(isEnabled: Bool, storeIdentity: WebExtensionStoreIdentity?) {
        let reported = pixelExtension(for: storeIdentity)
        pixelFiring.fire(isEnabled ? .enabled(extension: reported) : .disabled(extension: reported))
    }
}
