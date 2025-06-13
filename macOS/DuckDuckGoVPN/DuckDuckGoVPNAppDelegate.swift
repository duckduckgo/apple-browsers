//
//  DuckDuckGoVPNAppDelegate.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import AppLauncher
import BrowserServicesKit
import Cocoa
import Combine
import Common
import Configuration
import FeatureFlags
import LoginItems
import Networking
import NetworkExtension
import NetworkProtection
import NetworkProtectionProxy
import NetworkProtectionUI
import os.log
import PixelKit
import ServiceManagement
import Subscription
import SwiftUI
import VPNAppLauncher
import VPNAppState
import VPNExtensionManagement

@objc(Application)
final class DuckDuckGoVPNApplication: NSApplication {

    public var accountManager: AccountManager
    public var subscriptionManagerV2: any SubscriptionManagerV2
    private let _delegate: DuckDuckGoVPNAppDelegate

    override init() {
        Logger.networkProtection.log("🟢 Status Bar Agent starting\nPath: (\(Bundle.main.bundlePath, privacy: .public))\nVersion: \("\(Bundle.main.versionNumber!).\(Bundle.main.buildNumber)", privacy: .public)\nPID: \(NSRunningApplication.current.processIdentifier, privacy: .public)")

        // prevent agent from running twice
        if let anotherInstance = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!).first(where: { $0 != .current }) {
            Logger.networkProtection.error("Stopping: another instance is running: \(anotherInstance.processIdentifier, privacy: .public).")
            exit(0)
        }

        // Configure Subscription
        let subscriptionAppGroup = Bundle.main.appGroup(bundle: .subs)
        let subscriptionUserDefaults = UserDefaults(suiteName: subscriptionAppGroup)!
        let subscriptionEnvironment = DefaultSubscriptionManager.getSavedOrDefaultEnvironment(userDefaults: subscriptionUserDefaults)
        let keychainType = KeychainType.dataProtection(.named(subscriptionAppGroup))
        // V1
        let subscriptionEndpointService = DefaultSubscriptionEndpointService(currentServiceEnvironment: subscriptionEnvironment.serviceEnvironment,
                                                                             userAgent: UserAgent.duckDuckGoUserAgent())
        let authEndpointService = DefaultAuthEndpointService(currentServiceEnvironment: subscriptionEnvironment.serviceEnvironment,
                                                             userAgent: UserAgent.duckDuckGoUserAgent())
        let entitlementsCache = UserDefaultsCache<[Entitlement]>(userDefaults: subscriptionUserDefaults,
                                                                 key: UserDefaultsCacheKey.subscriptionEntitlements,
                                                                 settings: UserDefaultsCacheSettings(defaultExpirationInterval: .minutes(20)))
        let accessTokenStorage = SubscriptionTokenKeychainStorage(keychainType: keychainType)
        accountManager = DefaultAccountManager(accessTokenStorage: accessTokenStorage,
                                               entitlementsCache: entitlementsCache,
                                               subscriptionEndpointService: subscriptionEndpointService,
                                               authEndpointService: authEndpointService)
        // V2
        subscriptionManagerV2 = DefaultSubscriptionManagerV2(keychainType: keychainType,
                                                             environment: subscriptionEnvironment,
                                                             userDefaults: subscriptionUserDefaults,
                                                             canPerformAuthMigration: false,
                                                             pixelHandlingSource: .vpnApp)

        _delegate = DuckDuckGoVPNAppDelegate(accountManager: accountManager,
                                             subscriptionManagerV2: subscriptionManagerV2,
                                             accessTokenStorage: accessTokenStorage,
                                             subscriptionEnvironment: subscriptionEnvironment)

        super.init()

        setupPixelKit()
        self.delegate = _delegate
        accountManager.delegate = _delegate
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @MainActor
    private func setupPixelKit() {
        let dryRun: Bool

#if DEBUG || REVIEW
        dryRun = true
#else
        dryRun = false
#endif

        let pixelSource: String

#if !APPSTORE
        pixelSource = "vpnAgent"
#else
        pixelSource = "vpnAgentAppStore"
#endif

        PixelKit.setUp(dryRun: dryRun,
                       appVersion: AppVersion.shared.versionNumber,
                       source: pixelSource,
                       defaultHeaders: [:],
                       defaults: .netP) { (pixelName: String, headers: [String: String], parameters: [String: String], _, _, onComplete: @escaping PixelKit.CompletionBlock) in

            let url = URL.pixelUrl(forPixelNamed: pixelName)
            let apiHeaders = APIRequest.Headers(additionalHeaders: headers) // workaround - Pixel class should really handle APIRequest.Headers by itself
            let configuration = APIRequest.Configuration(url: url, method: .get, queryParameters: parameters, headers: apiHeaders)
            let request = APIRequest(configuration: configuration)

            request.fetch { _, error in
                onComplete(error == nil, error)
            }
        }
    }
}

@main
final class DuckDuckGoVPNAppDelegate: NSObject, NSApplicationDelegate {

    private static let recentThreshold: TimeInterval = 5.0

    private let appLauncher = AppLauncher()
    private let accountManager: any AccountManager
    private let subscriptionManagerV2: any SubscriptionManagerV2
    private let accessTokenStorage: SubscriptionTokenKeychainStorage

    private let configurationStore = ConfigurationStore()
    private let configurationManager: ConfigurationManager
    private var configurationSubscription: AnyCancellable?
    private let privacyConfigurationManager = VPNPrivacyConfigurationManager(internalUserDecider: DefaultInternalUserDecider(store: UserDefaults.appConfiguration))
    private let featureFlagOverridesPublishingHandler = FeatureFlagOverridesPublishingHandler<FeatureFlag>()
    private lazy var featureFlagger = DefaultFeatureFlagger(
        internalUserDecider: privacyConfigurationManager.internalUserDecider,
        privacyConfigManager: privacyConfigurationManager,
        localOverrides: FeatureFlagLocalOverrides(
            keyValueStore: UserDefaults.appConfiguration,
            actionHandler: featureFlagOverridesPublishingHandler
        ),
        experimentManager: nil,
        for: FeatureFlag.self)

    public init(accountManager: any AccountManager,
                subscriptionManagerV2: any SubscriptionManagerV2,
                accessTokenStorage: SubscriptionTokenKeychainStorage,
                subscriptionEnvironment: SubscriptionEnvironment) {
        self.accountManager = accountManager
        self.subscriptionManagerV2 = subscriptionManagerV2
        self.accessTokenStorage = accessTokenStorage
        self.tunnelSettings = VPNSettings(defaults: .netP)
        self.tunnelSettings.alignTo(subscriptionEnvironment: subscriptionEnvironment)
        self.configurationManager = ConfigurationManager(privacyConfigManager: privacyConfigurationManager, store: configurationStore)
        super.init()

        var tokenFound: Bool
        if !vpnAppState.isAuthV2Enabled {
            tokenFound = accountManager.accessToken != nil
        } else {
            tokenFound = subscriptionManagerV2.isUserAuthenticated
        }

        if tokenFound {
            Logger.networkProtection.debug("🟢 VPN Agent found \(self.vpnAppState.isAuthV2Enabled ? "Token Container (V2)" : "Token (V1)", privacy: .public)")
        } else {
            Logger.networkProtection.error("🔴 VPN Agent found no \(self.vpnAppState.isAuthV2Enabled ? "Token Container (V2)" : "Token (V1)", privacy: .public)")
        }
    }

    private var cancellables = Set<AnyCancellable>()
    private lazy var networkExtensionController = NetworkExtensionController(sysexBundleID: Self.tunnelSysexBundleID, featureFlagger: featureFlagger)
    private let vpnAppState = VPNAppState(defaults: .netP)
    private let tunnelSettings: VPNSettings
    private lazy var userDefaults = UserDefaults.netP
    private let proxySettings: TransparentProxySettings = TransparentProxySettings(defaults: .netP)

    @MainActor
    private lazy var vpnProxyLauncher = VPNProxyLauncher(
        tunnelController: tunnelController,
        proxyController: proxyController)

    @MainActor
    private lazy var proxyController: TransparentProxyController = {
        let eventHandler = TransparentProxyControllerEventHandler(logger: .transparentProxyLogger)

        let controller = TransparentProxyController(
            extensionResolver: proxyExtensionResolver,
            vpnAppState: vpnAppState,
            settings: proxySettings,
            eventHandler: eventHandler) { [weak self] manager in
                guard let self else { return }

                manager.localizedDescription = "DuckDuckGo VPN Proxy"

                if !manager.isEnabled {
                    manager.isEnabled = true
                }

                let extensionBundleID = await proxyExtensionResolver.activeExtensionBundleID

                manager.protocolConfiguration = {
                    let protocolConfiguration = manager.protocolConfiguration as? NETunnelProviderProtocol ?? NETunnelProviderProtocol()
                    protocolConfiguration.serverAddress = "127.0.0.1" // Dummy address... the NetP service will take care of grabbing a real server
                    protocolConfiguration.providerBundleIdentifier = extensionBundleID

                    // always-on
                    protocolConfiguration.disconnectOnSleep = false

                    // kill switch
                    // protocolConfiguration.enforceRoutes = false

                    // this setting breaks Connection Tester
                    // protocolConfiguration.includeAllNetworks = settings.includeAllNetworks

                    // This is intentionally not used but left here for documentation purposes.
                    // The reason for this is that we want to have full control of the routes that
                    // are excluded, so instead of using this setting we're just configuring the
                    // excluded routes through our VPNSettings class, which our extension reads directly.
                    // protocolConfiguration.excludeLocalNetworks = settings.excludeLocalNetworks

                    return protocolConfiguration
                }()
            }

        return controller
    }()

    private static let tunnelSysexBundleID = Bundle.tunnelSysexBundleID
    private static let tunnelAppexBundleID = Bundle.tunnelAppexBundleID
    private static let proxySysexBundleID = Bundle.tunnelSysexBundleID
    private static let proxyAppexBundleID = Bundle.proxyAppexBundleID

    private let tunnelExtensions: VPNExtensionResolver.AvailableExtensions = {
#if APPSTORE
        return .both(appexBundleID: tunnelAppexBundleID, sysexBundleID: tunnelSysexBundleID)
#else
        return .sysex(sysexBundleID: tunnelSysexBundleID)
#endif
    }()

    private let proxyExtensions: VPNExtensionResolver.AvailableExtensions = {
#if APPSTORE
        return .both(appexBundleID: proxyAppexBundleID, sysexBundleID: proxySysexBundleID)
#else
        return .sysex(sysexBundleID: proxySysexBundleID)
#endif
    }()

    @MainActor
    private lazy var proxyExtensionResolver = VPNExtensionResolver(
        availableExtensions: proxyExtensions,
        featureFlagger: featureFlagger,
        isConfigurationInstalled: tunnelController.isConfigurationInstalled(extensionBundleID:))

    @MainActor
    private lazy var tunnelController = NetworkProtectionTunnelController(
        availableExtensions: tunnelExtensions,
        networkExtensionController: networkExtensionController,
        featureFlagger: featureFlagger,
        settings: tunnelSettings,
        defaults: userDefaults,
        accessTokenStorage: accessTokenStorage,
        subscriptionManagerV2: subscriptionManagerV2,
        vpnAppState: vpnAppState)

    /// An IPC server that provides access to the tunnel controller.
    ///
    /// This is used by our main app to control the tunnel through the VPN login item.
    ///
    @MainActor
    private lazy var tunnelControllerIPCService: TunnelControllerIPCService = {
        let ipcServer = TunnelControllerIPCService(
            tunnelController: tunnelController,
            uninstaller: vpnUninstaller,
            networkExtensionController: networkExtensionController,
            statusReporter: statusReporter)
        ipcServer.activate()
        return ipcServer
    }()

    @MainActor
    private lazy var statusObserver = ConnectionStatusObserverThroughSession(
        tunnelSessionProvider: tunnelController,
        platformSnoozeTimingStore: NetworkProtectionSnoozeTimingStore(userDefaults: .netP),
        platformNotificationCenter: NSWorkspace.shared.notificationCenter,
        platformDidWakeNotification: NSWorkspace.didWakeNotification)

    @MainActor
    private lazy var statusReporter: NetworkProtectionStatusReporter = {
        let errorObserver = ConnectionErrorObserverThroughSession(
            tunnelSessionProvider: tunnelController,
            platformNotificationCenter: NSWorkspace.shared.notificationCenter,
            platformDidWakeNotification: NSWorkspace.didWakeNotification)

        let serverInfoObserver = ConnectionServerInfoObserverThroughSession(
            tunnelSessionProvider: tunnelController,
            platformNotificationCenter: NSWorkspace.shared.notificationCenter,
            platformDidWakeNotification: NSWorkspace.didWakeNotification)

        let dataVolumeObserver = DataVolumeObserverThroughSession(
            tunnelSessionProvider: tunnelController,
            platformNotificationCenter: NSWorkspace.shared.notificationCenter,
            platformDidWakeNotification: NSWorkspace.didWakeNotification)

        return DefaultNetworkProtectionStatusReporter(
            statusObserver: statusObserver,
            serverInfoObserver: serverInfoObserver,
            connectionErrorObserver: errorObserver,
            connectivityIssuesObserver: DisabledConnectivityIssueObserver(),
            controllerErrorMessageObserver: ControllerErrorMesssageObserverThroughDistributedNotifications(),
            dataVolumeObserver: dataVolumeObserver,
            knownFailureObserver: KnownFailureObserverThroughDistributedNotifications()
        )
    }()

    @MainActor
    private lazy var vpnAppEventsHandler = {
        VPNAppEventsHandler(tunnelController: tunnelController, appState: vpnAppState)
    }()

    @MainActor
    private lazy var vpnUninstaller: VPNUninstaller = {
        VPNUninstaller(
            tunnelController: tunnelController,
            networkExtensionController: networkExtensionController)
    }()

    /// The status bar NetworkProtection menu
    ///
    /// For some reason the App will crash if this is initialized right away, which is why it was changed to be lazy.
    ///
    @MainActor
    private lazy var networkProtectionMenu: StatusBarMenu = {
        makeStatusBarMenu()
    }()

    // MARK: - VPN Update offering

    private func refreshVPNUpdateOffered() {
        refreshVPNUpdateOffered(isUsingSystemExtension: vpnAppState.isUsingSystemExtension)
    }

    private func refreshVPNUpdateOffered(isUsingSystemExtension: Bool) {
        let newValue = featureFlagger.isFeatureOn(.networkProtectionAppStoreSysexMessage) && !isUsingSystemExtension

        isExtensionUpdateOfferedSubject.send(newValue)
    }

    private lazy var isExtensionUpdateOfferedSubject: CurrentValueSubject<Bool, Never> = {
#if APPSTORE
        let initialValue = featureFlagger.isFeatureOn(.networkProtectionAppStoreSysexMessage)
            && !vpnAppState.isUsingSystemExtension

        let isExtensionUpdateOfferedSubject = CurrentValueSubject<Bool, Never>(initialValue)

        return isExtensionUpdateOfferedSubject
#else
        return CurrentValueSubject(false)
#endif
    }()

    private func statusViewSubmenu() -> [StatusBarMenu.MenuItem] {
        let appLauncher = AppLauncher()
        let proxySettings = TransparentProxySettings(defaults: .netP)
        let excludedAppsMinusDBPAgent = proxySettings.excludedApps.filter { $0 != Bundle.main.dbpBackgroundAgentBundleId }

        var menuItems = [StatusBarMenu.MenuItem]()

        if UserDefaults.netP.networkProtectionOnboardingStatus == .completed {
            menuItems.append(
                .text(icon: Image(.settings16), title: UserText.vpnStatusViewVPNSettingsMenuItemTitle, action: {
                    try? await appLauncher.launchApp(withCommand: VPNAppLaunchCommand.showSettings)
                }))
        }

        if vpnAppState.isUsingSystemExtension {
            menuItems.append(contentsOf: [
                .textWithDetail(
                    icon: Image(.window16),
                    title: UserText.vpnStatusViewExcludedAppsMenuItemTitle,
                    detail: "(\(excludedAppsMinusDBPAgent.count))",
                    action: { [weak self] in

                        try? await self?.appLauncher.launchApp(withCommand: VPNAppLaunchCommand.manageExcludedApps)
                    }),
                .textWithDetail(
                    icon: Image(.globe16),
                    title: UserText.vpnStatusViewExcludedDomainsMenuItemTitle,
                    detail: "(\(proxySettings.excludedDomains.count))",
                    action: { [weak self] in

                        try? await self?.appLauncher.launchApp(withCommand: VPNAppLaunchCommand.manageExcludedDomains)
                    }),
                .divider()
            ])
        }

        menuItems.append(contentsOf: [
            .text(icon: Image(.help16), title: UserText.vpnStatusViewFAQMenuItemTitle, action: { [weak self] in
                try? await self?.appLauncher.launchApp(withCommand: VPNAppLaunchCommand.showFAQ)
            }),
            .text(icon: Image(.support16), title: UserText.vpnStatusViewSendFeedbackMenuItemTitle, action: { [weak self] in
                try? await self?.appLauncher.launchApp(withCommand: VPNAppLaunchCommand.shareFeedback)
            })
        ])

        return menuItems
    }

    @MainActor
    private func makeStatusBarMenu() -> StatusBarMenu {
        #if DEBUG
        let iconProvider = DebugMenuIconProvider()
        #elseif REVIEW
        let iconProvider = ReviewMenuIconProvider()
        #else
        let iconProvider = MenuIconProvider()
        #endif

        let onboardingStatusPublisher = UserDefaults.netP.publisher(for: \.networkProtectionOnboardingStatusRawValue).map { rawValue in
            OnboardingStatus(rawValue: rawValue) ?? .default
        }.eraseToAnyPublisher()

        let model = StatusBarMenuModel(vpnSettings: .init(defaults: .netP))
        let uiActionHandler = VPNUIActionHandler(
            appLauncher: appLauncher,
            proxySettings: proxySettings)

        let menuItems = { [weak self] () -> [NetworkProtectionStatusView.Model.MenuItem] in
            guard let self else { return [] }
            return statusViewSubmenu()
        }

        let isExtensionUpdateOfferedPublisher = CurrentValuePublisher<Bool, Never>(
            initialValue: isExtensionUpdateOfferedSubject.value,
            publisher: isExtensionUpdateOfferedSubject.eraseToAnyPublisher())

        // Make sure that if the user switches to sysex or vice-versa, we update
        // the offering message.
        vpnAppState.isUsingSystemExtensionPublisher
            .sink { [weak self] value in
                self?.refreshVPNUpdateOffered(isUsingSystemExtension: value)
            }
            .store(in: &cancellables)

        return StatusBarMenu(
            model: model,
            onboardingStatusPublisher: onboardingStatusPublisher,
            statusReporter: statusReporter,
            controller: tunnelController,
            iconProvider: iconProvider,
            uiActionHandler: uiActionHandler,
            menuItems: menuItems,
            agentLoginItem: nil,
            isMenuBarStatusView: true,
            isExtensionUpdateOfferedPublisher: isExtensionUpdateOfferedPublisher,
            userDefaults: .netP,
            locationFormatter: DefaultVPNLocationFormatter(),
            uninstallHandler: { [weak self] _ in
                guard let self else { return }

                do {
                    try await self.vpnUninstaller.uninstall(showNotification: true)
                    exit(EXIT_SUCCESS)
                } catch {
                    // Intentional no-op: we already anonymously track VPN uninstallation failures using
                    // pixels within the vpn uninstaller.
                }
            }
        )
    }

    @MainActor
    func applicationDidFinishLaunching(_ aNotification: Notification) {

        APIRequest.Headers.setUserAgent(UserAgent.duckDuckGoUserAgent())
        Logger.networkProtection.log("DuckDuckGoVPN started")

        // Setup Remote Configuration
        Configuration.setURLProvider(VPNAgentConfigurationURLProvider())
        configurationManager.start()
        // Load cached config (if any)
        privacyConfigurationManager.reload(etag: configurationStore.loadEtag(for: .privacyConfiguration), data: configurationStore.loadData(for: .privacyConfiguration))

        // It's important for this to be set-up after the privacy configuration is loaded
        // as it relies on it for the remote feature flag.
        TipKitAppEventHandler(featureFlagger: featureFlagger).appDidFinishLaunching()

        setupMenuVisibility()

        Task { @MainActor in
            // Initialize lazy properties
            _ = tunnelControllerIPCService
            _ = vpnProxyLauncher

            vpnAppEventsHandler.appDidFinishLaunching()

            let launchInformation = LoginItemLaunchInformation(agentBundleID: Bundle.main.bundleIdentifier!, defaults: .netP)
            let launchedOnStartup = launchInformation.wasLaunchedByStartup
            launchInformation.update()

            setUpSubscriptionMonitoring()

            if launchedOnStartup {
                Task {
                    let isConnected = await tunnelController.isConnected

                    if !isConnected && tunnelSettings.connectOnLogin {
                        await tunnelController.start()
                    }
                }
            }
        }
    }

    @MainActor
    private func setupMenuVisibility() {
        if tunnelSettings.showInMenuBar {
            refreshVPNUpdateOffered()
            networkProtectionMenu.show()
        } else {
            networkProtectionMenu.hide()
        }

        tunnelSettings.showInMenuBarPublisher.sink { [weak self] showInMenuBar in
            Task { @MainActor in
                if showInMenuBar {
                    self?.networkProtectionMenu.show()
                } else {
                    self?.networkProtectionMenu.hide()
                }
            }
        }.store(in: &cancellables)
    }

    private lazy var entitlementMonitor = NetworkProtectionEntitlementMonitor()

    private func setUpSubscriptionMonitoring() {

        var isUserAuthenticated: Bool
        let entitlementsCheck: () async -> Swift.Result<Bool, Error>
        if !vpnAppState.isAuthV2Enabled {
            isUserAuthenticated = accountManager.isUserAuthenticated
            entitlementsCheck = {
                await self.accountManager.hasEntitlement(forProductName: .networkProtection, cachePolicy: .reloadIgnoringLocalCacheData)
            }
        } else {
            isUserAuthenticated = subscriptionManagerV2.isUserAuthenticated
            entitlementsCheck = {
                do {
                    let tokenContainer = try await self.subscriptionManagerV2.getTokenContainer(policy: .localValid)
                    let isNetworkProtectionEnabled = tokenContainer.decodedAccessToken.hasEntitlement(.networkProtection)
                    Logger.networkProtection.log("NetworkProtectionEnabled if: \( isNetworkProtectionEnabled ? "Enabled" : "Disabled", privacy: .public)")
                    return .success(isNetworkProtectionEnabled)
                } catch {
                    return .failure(error)
                }
            }
        }
        guard isUserAuthenticated else { return }

        Task {
            await entitlementMonitor.start(entitlementCheck: entitlementsCheck) { [weak self] result in
                switch result {
                case .validEntitlement:
                    UserDefaults.netP.networkProtectionEntitlementsExpired = false
                case .invalidEntitlement:
                    UserDefaults.netP.networkProtectionEntitlementsExpired = true

                    guard let self else { return }
                    Task {
                        let isConnected = await self.tunnelController.isConnected
                        if isConnected {
                            await self.tunnelController.stop()
                            DistributedNotificationCenter.default().post(.showExpiredEntitlementNotification)
                        }
                    }
                case .error:
                    break
                }
            }
        }
    }
}

extension DuckDuckGoVPNAppDelegate: AccountManagerKeychainAccessDelegate {

    public func accountManagerKeychainAccessFailed(accessType: AccountKeychainAccessType, error: any Error) {

        guard let expectedError = error as? AccountKeychainAccessError else {
            assertionFailure("Unexpected error type: \(error)")
            Logger.networkProtection.fault("Unexpected error type: \(error)")
            return
        }

        PixelKit.fire(PrivacyProErrorPixel.privacyProKeychainAccessError(accessType: accessType,
                                                                         accessError: expectedError,
                                                                         source: KeychainErrorSource.vpn,
                                                                         authVersion: KeychainErrorAuthVersion.v1),
                      frequency: .legacyDailyAndCount)
    }
}
